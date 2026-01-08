# Library chain example for nixnative
#
# Demonstrates multi-library dependencies where:
#   app → libMathExt → libCore → libUtil
#
# Each library only needs to declare its direct dependencies;
# transitive dependencies are handled automatically.

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
  };

  # Build libraries in dependency order - each references the previous directly
  libUtil = proj.staticLib {
    name = "libutil";
    sources = [ "libutil/util.cc" ];
    includeDirs = [ "libutil/include" ];
    publicIncludeDirs = [ "libutil/include" ];
  };

  libCore = proj.staticLib {
    name = "libcore";
    sources = [ "libcore/core.cc" ];
    includeDirs = [ "libcore/include" ];
    publicIncludeDirs = [ "libcore/include" ];
    libraries = [ libUtil ];  # Direct reference!
  };

  libMathExt = proj.staticLib {
    name = "libmath_ext";
    sources = [ "libmath/math_ext.cc" ];
    includeDirs = [ "libmath/include" ];
    publicIncludeDirs = [ "libmath/include" ];
    libraries = [ libCore ];  # Transitive dep on libUtil handled automatically
  };

  app = proj.executable {
    name = "library-chain-app";
    sources = [ "main.cc" ];
    libraries = [ libMathExt ];  # Only direct dep needed
  };

  testLibraryChain = native.test {
    name = "test-library-chain";
    executable = app;
    expectedOutput = "Library chain working";
  };

in {
  packages = {
    inherit libUtil libCore libMathExt app;
  };

  checks = {
    inherit testLibraryChain;
  };
}
