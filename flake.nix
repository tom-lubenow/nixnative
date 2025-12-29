{
  description = "nixnative: Incremental C/C++ builds using Nix dynamic derivations";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  # Nix with full dynamic derivations support (John Ericson's RFC 92 work)
  # Requires: experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
  inputs.nix.url = "github:NixOS/nix/d904921eecbc17662fef67e8162bd3c7d1a54ce0";
  inputs.nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
            # Nix package with dynamic derivations support
            nixPackage = nix.packages.${system}.default;
            native = import ./nix/native { inherit pkgs nixPackage; };
            examples = import ./examples/examples.nix {
              inherit pkgs native system;
            };
          in
          f { inherit pkgs native examples; }
        );
    in
    {
      lib = {
        native = import ./nix/native;
      };

      packages = forAllSystems (
        {
          pkgs,
          native,
          examples,
          ...
        }:
        examples.packages
        // {
          default = examples.defaults.app;
        }
      );

      checks = forAllSystems (
        {
          pkgs,
          native,
          examples,
          ...
        }:
        examples.checks
        // {
          pkgconfig-zlib = pkgs.runCommand "pkgconfig-zlib-check" { } ''
            set -euo pipefail
            drv=${
              (native.pkgConfig.makeLibrary {
                name = "zlib";
                packages = [ pkgs.zlib ];
                modules = [ "zlib" ];
              }).drv
            }
            grep -q -- "-lz" "$drv"
            test "$(grep -c 'includeDirs' "$drv")" -gt 0
            touch "$out"
          '';
        }
      );

      # Apps removed - sync-manifest was for static scanning mode (now obsolete)

      devShells = forAllSystems (
        {
          pkgs,
          native,
          examples,
        }:
        {
          default = native.devShell {
            target = examples.defaults.app;
            extraPackages = [
              pkgs.nushell
            ];
          };
        }
      );
    };
}
