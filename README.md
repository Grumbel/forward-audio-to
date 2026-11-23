# forward-audio-to

Redirect all desktop audio to another PC via SSH. Interrupting the command
restores the previous default sink and removes the temporary virtual sink.

## Build, run, install

```sh
nix build .
nix run . -- other_host
nix profile install .
forward-audio-to other_host
```

The Nix package makes sender-side tools available automatically (SSH,
PulseAudio CLI utilities, coreutils, awk), including on PipeWire systems.

The **receiving PC** must have `pacat` and `pactl` available to its SSH
session, with a working PulseAudio or PipeWire-Pulse desktop audio session.
For example, on NixOS, add `pulseaudio` to the receiver's installed packages,
or install it in the receiver user's profile with:

```sh
nix profile install nixpkgs#pulseaudio
```

Use SSH key authentication to avoid repeated prompts. Ctrl-C cleans up.

If the flake lives inside a Git repository, add the new files to the Git
index before using Nix flakes (`git add flake.nix forward-audio-to`).
