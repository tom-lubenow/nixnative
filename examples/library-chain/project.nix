{ pkgs, native }:

let
  # Layer 1: Utility library (no dependencies - base of the chain)
  libUtil = native.staticLib {
    name = "libutil";
    root = ./.;
    sources = [ "libutil/util.cc" ];
    includeDirs = [ "libutil/include" ];
    publicIncludeDirs = [ "libutil/include" ];
  };

  # Layer 2: Core library (depends on util)
  libCore = native.staticLib {
    name = "libcore";
    root = ./.;
    sources = [ "libcore/core.cc" ];
    includeDirs = [ "libcore/include" ];
    publicIncludeDirs = [ "libcore/include" ];
    libraries = [ libUtil ];
  };

  # Layer 3: Math extension library (depends on core, transitively on util)
  libMathExt = native.staticLib {
    name = "libmath_ext";
    root = ./.;
    sources = [ "libmath/math_ext.cc" ];
    includeDirs = [ "libmath/include" ];
    publicIncludeDirs = [ "libmath/include" ];
    libraries = [ libCore ];
  };

  # Application using the full chain
  app = native.executable {
    name = "library-chain-app";
    root = ./.;
    sources = [ "main.cc" ];
    libraries = [ libMathExt ];
  };

in {
  inherit libCore libUtil libMathExt app;
  libraryChainExample = app;
}
