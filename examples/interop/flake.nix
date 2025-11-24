{
  description = "Dual-Language Linkage (C++ & Zig) example for nixclang";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixclang.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixclang }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          cpp = nixclang.lib.cpp { inherit pkgs; };
          
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

          # Wrap it as a nixclang library
          zigLib = {
            staticLibrary = "${zigLibDrv}/lib/libmath.a";
            includeDirs = [ ./. ]; # header.h is in the root
            
            # We might need to link against libc/libunwind if Zig depends on it,
            # but for this simple example it should be fine or handled by C++ toolchain.
            public = {
              linkFlags = [ "${zigLibDrv}/lib/libmath.a" ];
              cxxFlags = [];
              defines = [];
              includeDirs = [ ./. ];
            };
          };

        in
        {
          default = cpp.mkExecutable {
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
