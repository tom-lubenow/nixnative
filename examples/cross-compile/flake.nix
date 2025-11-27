# Cross-compilation example for nixnative
#
# Demonstrates patterns for cross-compiling C++ code to different architectures.
# Note: Full cross-compilation support is experimental.

{
  description = "Cross-compilation example for nixnative";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };

          # Cross-compile to aarch64-linux (only from linux hosts)
          crossAarch64Linux =
            if pkgs.stdenv.hostPlatform.isLinux then
              let
                pkgsCross = import nixpkgs {
                  inherit system;
                  crossSystem = { config = "aarch64-unknown-linux-gnu"; };
                };
                nativeCross = nixnative.lib.native { pkgs = pkgsCross; };
              in
              nativeCross.executable {
                name = "cross-example-aarch64-linux";
                root = ./.;
                sources = [ "src/main.cc" ];
              }
            else null;

          # Cross-compile to x86_64-linux (only from aarch64-linux)
          crossX86_64Linux =
            if system == "aarch64-linux" then
              let
                pkgsCross = import nixpkgs {
                  inherit system;
                  crossSystem = { config = "x86_64-unknown-linux-gnu"; };
                };
                nativeCross = nixnative.lib.native { pkgs = pkgsCross; };
              in
              nativeCross.executable {
                name = "cross-example-x86_64-linux";
                root = ./.;
                sources = [ "src/main.cc" ];
              }
            else null;
        in
        packages
        // { default = packages.nativeApp; }
        // (if crossAarch64Linux != null then { aarch64-linux = crossAarch64Linux; } else {})
        // (if crossX86_64Linux != null then { x86_64-linux = crossX86_64Linux; } else {})
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
        in
        import ./checks.nix { inherit pkgs native packages; }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.zig pkgs.file pkgs.qemu ];
            shellHook = ''
              echo "Cross-compilation development shell"
              echo "  zig cc -target <target>  - Cross-compile with Zig"
              echo "  file <binary>            - Check binary architecture"
            '';
          };
        }
      );
    };
}
