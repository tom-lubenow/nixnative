{ pkgs, native, packages }:

let
  mathLibrary = packages.mathLibrary;
  toolchain = mathLibrary.passthru.toolchain;

  # Build a test executable that uses the math library
  # This properly consumes the library's objectRefs
  testExec = native.executable {
    name = "math-library-test";
    inherit toolchain;
    root = ./test;
    sources = [ "main.cc" ];
    libraries = [ mathLibrary ];
  };
in {
  # For now, just check that the executable can be built
  # The actual executable is accessed via testExec.out
  mathLibrary = testExec;
}
