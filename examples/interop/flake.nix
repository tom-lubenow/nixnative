# Zig interop example for nixnative
#
# Demonstrates linking C++ code with a Zig static library.
# The same pattern works for any language that produces C ABI static libraries.

{
  description = "Dual-Language Linkage (C++ & Zig) example for nixnative";

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

          # Build Zig library to a static archive
          #
          # Zig's `export` keyword generates C-compatible symbols that
          # can be called from C/C++ code.
          zigLibDrv = pkgs.runCommand "zig-lib" {
            nativeBuildInputs = [ pkgs.zig ];
          } ''
            mkdir -p $out/lib
            # Zig requires writable cache directories
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
            zig build-lib ${./lib.zig}
            ls -la
            find . -name "*.a" -exec mv {} $out/lib/libmath.a \;
          '';

          # Wrap the Zig library for nixnative
          #
          # This pattern works for any foreign static library:
          # 1. Build the library with its native toolchain
          # 2. Create a C header declaring the functions
          # 3. Wrap with the public interface for nixnative
          zigLib = {
            name = "zig-math";
            staticLibrary = "${zigLibDrv}/lib/libmath.a";
            includeDirs = [ ./. ];  # Directory containing header.h
            public = {
              linkFlags = [ "${zigLibDrv}/lib/libmath.a" ];
              cxxFlags = [];
              defines = [];
              includeDirs = [ ./. ];
            };
          };

        in
        {
          default = native.executable {
            name = "interop-example";
            root = ./.;
            sources = [ "main.cc" ];
            libraries = [ zigLib ];
          };
        }
      );
    };
}
