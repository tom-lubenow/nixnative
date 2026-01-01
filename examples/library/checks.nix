{ pkgs, native, packages }:

let
  mathLibrary = packages.mathLibrary;
  toolchain = mathLibrary.passthru.toolchain;

  # Build a test executable that uses the math library
  testExec = native.executable {
    name = "math-library-test";
    inherit toolchain;
    root = ./test;
    sources = [ "main.cc" ];
    libraries = [ mathLibrary ];
  };
in {
  # Run the test and verify the library works correctly
  # add(2,3) = 5, mul(3,4) = 12
  mathLibrary = native.test {
    name = "math-library-test";
    executable = testExec;
    expectedOutput = "5 12";
  };
}
