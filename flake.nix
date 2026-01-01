{
  description = "nixnative: Incremental C/C++ builds using Nix dynamic derivations";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  # Nix with full dynamic derivations support (John Ericson's RFC 92 work)
  # Requires: experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
  inputs.nix.url = "github:NixOS/nix/d904921eecbc17662fef67e8162bd3c7d1a54ce0";
  inputs.nix.inputs.nixpkgs.follows = "nixpkgs";

  # nix-ninja: Incremental builds with per-file derivations
  # Fork with patchelf fix for system libraries
  inputs.nix-ninja.url = "git+ssh://git@github.com/tom-lubenow/nix-ninja";
  inputs.nix-ninja.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      nix,
      nix-ninja,
    }:
    let
      systems = [
        "x86_64-linux"
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
            # nix-ninja packages for incremental builds
            ninjaPackages = nix-ninja.packages.${system};
            native = import ./nix/native {
              inherit pkgs nixPackage;
              inherit (ninjaPackages) nix-ninja nix-ninja-task;
            };
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

      # Build all examples as a check
      # Note: Dynamic derivation outputs don't create result symlinks.
      # Use --print-out-paths or legacyPackages for actual outputs.
      packages = forAllSystems (
        { pkgs, native, examples, ... }:
        {
          default = native.mkBuildAllCheck pkgs "nixnative-examples" (builtins.attrValues examples.packages);
        }
      );

      # legacyPackages exposes the actual build outputs (builtins.outputOf results)
      # This is the recommended way to build nixnative targets:
      #   nix build .#executableExample --print-out-paths
      #
      # Note: Dynamic derivations don't create result symlinks.
      # Use --print-out-paths to get the store path.
      legacyPackages = forAllSystems (
        {
          pkgs,
          native,
          examples,
          ...
        }:
        let
          # Extract .passthru.target from packages that have it
          realizeTarget = pkg:
            if pkg ? passthru && pkg.passthru ? target
            then pkg.passthru.target
            else pkg;
        in
        pkgs.lib.mapAttrs (_: realizeTarget) examples.packages
        // {
          default = realizeTarget examples.defaults.app;
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
