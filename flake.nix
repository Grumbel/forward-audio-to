{
  description = "Temporarily forward desktop audio to another PC over SSH";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems f;
    in
    {
      packages = eachSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.writeShellApplication {
            name = "forward-audio-to";
            runtimeInputs = with pkgs; [
              coreutils  # mkfifo, mktemp, rm, rmdir
              gawk       # awk
              openssh    # ssh
              pulseaudio # pactl and parec (also work with PipeWire)
            ];
            text = builtins.readFile ./forward-audio-to;
          };
        });

      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/forward-audio-to";
        };
      });
    };
}
