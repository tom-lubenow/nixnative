# Option B: Function with compiler/linker params
#
# Style:  native.executable { compiler = "clang"; ... }
#         native.staticLib { compiler = "gcc"; linker = "mold"; ... }
#
# Single function per target type with compiler as a parameter.
# Easy to parameterize and pass around.
#
{ pkgs }:

let
  lib = import ./native-lib.nix { inherit pkgs; };
  native = lib.optionB;
in
rec {
  # Build the math library (defaults to clang)
  mathLib = native.staticLib {
    name = "math";
    root = ./.;
    sources = [ "lib/math.cc" ];
    publicIncludeDirs = [ "lib" ];
  };

  # Build the main executable (defaults to clang)
  app = native.executable {
    name = "demo";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Alternative: Explicitly specify GCC
  appGcc = native.executable {
    compiler = "gcc";
    name = "demo-gcc";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Alternative: Clang with Mold linker
  appMold = native.executable {
    compiler = "clang";
    linker = "mold";
    name = "demo-mold";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Easy to parameterize with a variable
  mkApp = { compiler ? "clang", suffix ? "" }:
    native.executable {
      inherit compiler;
      name = "demo${suffix}";
      root = ./.;
      sources = [ "src/main.cc" ];
      includeDirs = [ "lib" ];
      libraries = [ mathLib ];
    };

  appClang = mkApp { compiler = "clang"; suffix = "-clang"; };
  appGcc2 = mkApp { compiler = "gcc"; suffix = "-gcc2"; };

  default = app;
}
