{
  description = "Incremental clang build graph using Nix per translation unit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          let
            pkgs = import nixpkgs {
              inherit system;
            };
            cpp = import ./nix/cpp { inherit pkgs; };
            example = import ./examples/simple { inherit pkgs cpp; };
          in
          f { inherit pkgs cpp example; }
        );
    in
    {
      lib = {
        cpp = import ./nix/cpp;
      };

      packages = forAllSystems ({ pkgs, cpp, example }:
        example.packages // {
          default = example.packages.strict;
        }
      );

      checks = forAllSystems ({ pkgs, cpp, example }:
        example.checks // {
          simpleScanManifest = example.scannedManifest;
        }
      );

      devShells = forAllSystems ({ pkgs, cpp, example }:
        {
          default = pkgs.mkShell {
            packages = [
              cpp.toolchains.clang.clang
              pkgs.llvmPackages_18.lld
              pkgs.nix
              pkgs.git
            ];
            shellHook = ''
              echo "nixclang dev shell loaded"
            '';
          };
        }
      );
    };
}
