# forward-audio-to

Stream desktop audio between PCs over SSH, using PulseAudio or
PipeWire-Pulse on both computers. No persistent sound-system configuration.

## Build, run, install

```sh
nix build .
nix flake check
nix run . -- other_host
nix profile install .
forward-audio-to other_host
```

The flake provides the sender-side tools automatically (`ssh`, `pactl`, `parec`,
`awk`, and coreutils). Supports `x86_64-linux` and `aarch64-linux`.

## Audio modes

**Redirect** (default): move the active default output to a temporary virtual
sink and stream it to the remote computer. Local speakers are silent for the
redirected streams. Ctrl-C restores the original output and moves existing
streams back.

```sh
forward-audio-to other_host
```

**Mirror**: leave the local output alone, but capture its monitor and send the
same sound to the other computer. Local speakers keep playing. No virtual sink
is created, and there is no audio routing to restore.

```sh
forward-audio-to --keep-local other_host
# --mirror is an alias for --keep-local
```

`-h`/`--help` prints usage, and `-V`/`--version` prints the version. Options
can appear before or after the host.

## Play audio from a remote host

```sh
forward-audio-from other_host
forward-audio-from --keep-remote other_host
nix run .#forward-audio-from -- other_host
```

By default, `forward-audio-from` redirects the remote host's default output
to this machine. Ctrl-C restores the remote output and moves its streams
back. Use `--keep-remote` (or `--mirror`) to keep playing through the
remote speakers as well.

The remote SSH session needs `bash`, `pactl`, `parec`, `awk`, and `cat`,
with access to the remote user's desktop audio session. The flake supplies
`pacat` and the other tools needed on the local machine.

## Receiver setup

The **receiving PC** must have `pacat` and `pactl` available to its SSH
session, with a working PulseAudio or PipeWire-Pulse desktop audio session.
On NixOS, install `pulseaudio` on the receiving host or into the receiver's
user profile:

```sh
nix profile install nixpkgs#pulseaudio
```

SSH keys avoid repeated password prompts. The stream is stereo, 16-bit PCM at
48 kHz (~1.5 Mbit/s before SSH framing). Press Ctrl-C to stop. If the default
output changes while mirroring, the existing sink continues to be mirrored;
restart the command to follow the new default.

Both commands request 20 ms of capture latency and 60 ms of playback
latency. Actual end-to-end delay depends on the audio devices, sound
servers, and network conditions.

If using Nix flakes from within a Git repository, stage new files before
building (`git add flake.nix forward-audio-to forward-audio-from`).
