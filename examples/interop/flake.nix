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

          # Build Zig library
          zigLibDrv = pkgs.runCommand "zig-lib" {
            nativeBuildInputs = [ pkgs.zig ];
          } ''
            mkdir -p $out/lib
            # Build static library
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
            zig build-lib ${./lib.zig}
            ls -la
            find . -name "*.a" -exec mv {} $out/lib/libmath.a \;
          '';

          # Wrap as a library with public interface
          zigLib = {
            name = "zig-math";
            staticLibrary = "${zigLibDrv}/lib/libmath.a";
            includeDirs = [ ./. ]; # header.h is in the root
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
            ldflags = [ "-v" ];
          };
        }
      );
    };
}
