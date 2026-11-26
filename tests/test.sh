#!/usr/bin/env bash
# Mock integration tests: no audio server, SSH daemon, or Nix required.
set -euo pipefail
script=${1:?usage: test.sh PATH_TO_FORWARD_AUDIO_TO}
script=$(realpath "$script")
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"

write_mock() {
    printf '#!%s\n' "$BASH"
    cat
}

write_mock >"$tmp/bin/pactl" <<'MOCK'
set -euo pipefail
printf 'pactl %s\n' "$*" >>"$MOCK_STATE/log"
case "$*" in
    info) : ;;
    get-default-sink) cat "$MOCK_STATE/default" ;;
    'list short sinks')
        if [[ -e "$MOCK_STATE/virtual" ]]; then
            printf '0\tlocal\n1\t%s\n' "$(cat "$MOCK_STATE/virtual")"
        else
            printf '0\tlocal\n'
        fi ;;
    'list short sink-inputs')
        printf '9\t%s\n' "$(cat "$MOCK_STATE/stream")" ;;
    'load-module module-null-sink '* )
        for arg in "$@"; do
            if [[ $arg == sink_name=* ]]; then printf '%s' "${arg#sink_name=}" >"$MOCK_STATE/virtual"; fi
        done
        printf '23\n' ;;
    'set-default-sink '* ) printf '%s\n' "$2" >"$MOCK_STATE/default" ;;
    'move-sink-input '* )
        if [[ $3 == local ]]; then echo 0 >"$MOCK_STATE/stream"; else echo 1 >"$MOCK_STATE/stream"; fi ;;
    'unload-module 23') rm "$MOCK_STATE/virtual" ;;
    *) echo "Unknown pactl invocation: $*" >&2; exit 4 ;;
esac
MOCK

write_mock >"$tmp/bin/parec" <<'MOCK'
set -euo pipefail
printf 'parec %s\n' "$*" >>"$MOCK_STATE/log"
printf a
exec sleep 60
MOCK

write_mock >"$tmp/bin/ssh" <<'MOCK'
set -euo pipefail
case "${*: -1}" in
    'command -v pacat >/dev/null && pactl info >/dev/null')
        printf 'ssh preflight %s\n' "$3" >>"$MOCK_STATE/log"
        [[ ! -e "$MOCK_STATE/remote_failure" ]] ;;
    'exec bash -c '*)
        printf 'ssh capture %s\n' "$3" >>"$MOCK_STATE/log"
        exec bash -c "${*: -1}" ;;
    *)
        printf 'ssh stream %s\n' "$3" >>"$MOCK_STATE/log"
        cat >/dev/null ;;
esac
MOCK
chmod +x "$tmp/bin/"*
export MOCK_STATE="$tmp/state"
export PATH="$tmp/bin:$PATH"

reset_state() {
    rm -f "$MOCK_STATE"/*
    echo local >"$MOCK_STATE/default"
    echo 0 >"$MOCK_STATE/stream"
    : >"$MOCK_STATE/log"
}

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_has() { grep -Fq -- "$1" "$MOCK_STATE/log" || fail "missing in log: $1"; }
assert_lacks() { if grep -Fq -- "$1" "$MOCK_STATE/log"; then fail "unexpected in log: $1"; fi; }

[[ $(bash "$script" --version) == 'forward-audio-to 0.2.0' ]] || fail 'version flag'
bash "$script" --help | grep -Fq -- '--keep-local' || fail 'help flag'
bash "$script" -h >/dev/null
bash "$script" -V >/dev/null
for args in '' '--bogus' 'one two' '--keep-local'; do
    # Intentional word splitting: testing combinations of separate arguments.
    if bash "$script" $args >"$tmp/out" 2>&1; then fail "accepted invalid CLI: $args"; fi
    grep -Fq 'Try "forward-audio-to --help"' "$tmp/out" || fail "missing CLI error: $args"
done

start_and_stop() {
    local text=$1
    shift
    reset_state
    bash "$script" "$@" >"$tmp/out" 2>"$tmp/err" &
    local pid=$!
    local i
    for ((i=0; i<100; i++)); do
        if grep -Fq "$text" "$tmp/err" 2>/dev/null; then break; fi
        if ! kill -0 "$pid" 2>/dev/null; then
            cat "$tmp/err" >&2
            fail 'stream terminated prematurely'
        fi
        sleep 0.02
    done
    grep -Fq "$text" "$tmp/err" || fail 'stream never started'
    kill -TERM "$pid"
    local rc=0
    wait "$pid" || rc=$?
    [[ $rc -eq 143 ]] || fail "unexpected SIGTERM exit: $rc"
    [[ $(cat "$MOCK_STATE/default") == local ]] || fail 'default audio sink not restored'
    [[ $(cat "$MOCK_STATE/stream") == 0 ]] || fail 'existing stream not restored'
}

start_and_stop 'Audio mirrored' --keep-local receiver
assert_has 'ssh preflight receiver'
assert_has 'ssh stream receiver'
assert_has '--device=local.monitor'
assert_lacks 'load-module'
assert_lacks 'set-default-sink'
assert_lacks 'move-sink-input'
assert_lacks 'unload-module'
[[ ! -e "$MOCK_STATE/virtual" ]] || fail 'mirror created virtual sink'

# Options may also follow host, and --mirror aliases --keep-local.
start_and_stop 'Audio mirrored' receiver --mirror
assert_has '--device=local.monitor'

start_and_stop 'Audio redirected' receiver
assert_has 'load-module module-null-sink'
assert_has '--device=ssh_audio_'
assert_has 'set-default-sink ssh_audio_'
assert_has 'move-sink-input 9 ssh_audio_'
assert_has 'move-sink-input 9 local'
assert_has 'unload-module 23'
[[ ! -e "$MOCK_STATE/virtual" ]] || fail 'virtual sink not removed'

reset_state
touch "$MOCK_STATE/remote_failure"
if bash "$script" --keep-local receiver >"$tmp/out" 2>"$tmp/err"; then
    fail 'preflight failure accepted'
fi
assert_lacks 'load-module'
assert_lacks 'parec'

printf 'All forward-audio-to tests passed.\n'

if (( $# < 2 )); then exit 0; fi
script=$(realpath "$2")
write_mock >"$tmp/bin/pacat" <<'MOCK'
exec cat >"$MOCK_STATE/playback"
MOCK
chmod +x "$tmp/bin/pacat"

[[ $(bash "$script" --version) == 'forward-audio-from 0.2.0' ]] || fail 'version flag'
bash "$script" --help | grep -Fq -- '--keep-remote' || fail 'help flag'
if bash "$script" receiver extra >"$tmp/out" 2>&1; then fail 'accepted two hosts'; fi

# Wait for a byte of actual playback before signalling the client.
start_and_stop_from() {
    reset_state
    bash "$script" "$@" >"$tmp/out" 2>"$tmp/err" &
    local pid=$! i rc=0
    for ((i=0; i<100; i++)); do
        [[ ! -s "$MOCK_STATE/playback" ]] || break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.02
    done
    kill -TERM "$pid" 2>/dev/null || :
    wait "$pid" || rc=$?
    if [[ $rc -ne 143 ]]; then cat "$tmp/err" >&2; fail "unexpected exit: $rc"; fi
    [[ $(cat "$MOCK_STATE/playback") == a ]] || fail 'expected raw PCM at local pacat'
    [[ $(cat "$MOCK_STATE/default") == local ]] || fail 'remote default sink not restored'
    [[ $(cat "$MOCK_STATE/stream") == 0 ]] || fail 'remote stream not restored'
    [[ ! -e "$MOCK_STATE/virtual" ]] || fail 'remote virtual sink not removed'
}

start_and_stop_from sender --mirror
assert_has 'ssh capture sender'
assert_has '--device=local.monitor'
assert_lacks 'load-module'
assert_lacks 'set-default-sink'
assert_lacks 'move-sink-input'

start_and_stop_from sender
assert_has 'load-module module-null-sink'
assert_has '--device=ssh_audio_'
assert_has 'move-sink-input 9 ssh_audio_'
assert_has 'move-sink-input 9 local'
assert_has 'unload-module 23'

printf 'All forward-audio-from tests passed.\n'
