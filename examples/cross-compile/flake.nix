# Cross-compilation example for nixnative
#
# Demonstrates patterns for cross-compiling C++ code to different architectures.
# Note: Full cross-compilation support is experimental.
#
# Cross-compiled packages are intentionally NOT included in the packages output
# because they require building cross-compilation toolchains from scratch, which
# can take 30+ minutes. To build cross-compiled binaries locally:
#
#   nix build --impure --expr '
#     let
#       nixpkgs = builtins.getFlake "github:NixOS/nixpkgs/nixos-25.05";
#       nixnative = builtins.getFlake "path:./../..";
#       pkgsCross = import nixpkgs {
#         system = "x86_64-linux";
#         crossSystem = { config = "aarch64-unknown-linux-gnu"; };
#       };
#       native = nixnative.lib.native { pkgs = pkgsCross; };
#     in native.executable { name = "cross-example"; root = ./.; sources = ["src/main.cc"]; }
#   '

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
      # Only export native builds - cross-compiled packages are too slow for CI
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
        in
        packages // { default = packages.nativeApp; }
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
