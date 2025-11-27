# Option A: Namespace-based API
#
# Style:  native.clang.executable { ... }
#         native.gcc.staticLib { ... }
#
# The compiler is part of the namespace, making it clear and discoverable.
# Override the linker with: native.clang.withLinker native.linkers.mold
#
{ pkgs }:

let
  lib = import ./native-lib.nix { inherit pkgs; };
  native = lib.optionA;
in
rec {
  # Build the math library with Clang
  mathLib = native.clang.staticLib {
    name = "math";
    root = ./.;
    sources = [ "lib/math.cc" ];
    publicIncludeDirs = [ "lib" ];
  };

  # Build the main executable with Clang
  app = native.clang.executable {
    name = "demo";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Alternative: Build with GCC instead
  appGcc = native.gcc.executable {
    name = "demo-gcc";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Alternative: Clang with Mold linker (Linux only)
  appMold = (native.clang.withLinker native.native.linkers.mold).executable {
    name = "demo-mold";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  default = app;
}
