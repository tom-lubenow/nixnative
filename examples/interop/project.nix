{ pkgs, native }:

let
  # Build Zig library
  zigLibDrv = pkgs.runCommand "zig-lib" {
    nativeBuildInputs = [ pkgs.zig ];
  } ''
    mkdir -p $out/lib
    export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
    export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
    zig build-lib ${./lib.zig}
    find . -name "*.a" -exec mv {} $out/lib/libmath.a \;
  '';

  # Wrap as nixnative library
  zigLib = {
    name = "zig-math";
    staticLibrary = "${zigLibDrv}/lib/libmath.a";
    includeDirs = [ ./. ];
    public = {
      linkFlags = [ "${zigLibDrv}/lib/libmath.a" ];
      cxxFlags = [];
      defines = [];
      includeDirs = [ ./. ];
    };
  };

  # C++ app using Zig library
  app = native.executable {
    name = "interop-example";
    root = ./.;
    sources = [ "main.cc" ];
    libraries = [ zigLib ];
  };

in {
  inherit zigLibDrv zigLib app;
  interopExample = app;
}
