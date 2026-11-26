{
  description = "Forward or mirror desktop audio between PCs over SSH";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems f;
    in
    {
      packages = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          package = name: source: pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = with pkgs; [ coreutils gawk openssh pulseaudio ];
            text = builtins.readFile source;
          };
        in rec {
          forward-audio-to = package "forward-audio-to" ./forward-audio-to;
          forward-audio-from = package "forward-audio-from" ./forward-audio-from;
          default = pkgs.symlinkJoin {
            name = "forward-audio";
            paths = [ forward-audio-to forward-audio-from ];
          };
        });

      apps = eachSystem (system:
        let app = name: {
          type = "app";
          program = "${self.packages.${system}.${name}}/bin/${name}";
        };
        in {
          default = app "forward-audio-to";
          forward-audio-from = app "forward-audio-from";
        });

      checks = eachSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.runCommand "forward-audio-to-tests" {
            nativeBuildInputs = with pkgs; [ bash coreutils gawk gnugrep ];
          } ''
            bash ${./tests/test.sh} ${./forward-audio-to} ${./forward-audio-from}
            touch "$out"
          '';
        });
    };
}
