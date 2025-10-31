{
  description = "Template: executable + library with generated sources";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  inputs.nixclang.url = "path:../..";

  outputs = { self, nixpkgs, nixclang }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          cpp = nixclang.lib.cpp { inherit pkgs; };
          example = import ./project.nix { inherit pkgs cpp; };
        in f { inherit pkgs cpp example; }
      );
    in {
      packages = forAllSystems ({ example, ... }:
        example.packages // {
          default = example.packages.strict;
        }
      );

      checks = forAllSystems ({ example, ... }: example.checks);
    };
}
