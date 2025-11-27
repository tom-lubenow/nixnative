{ pkgs, native, packages }:

{
  libraryChain = native.test {
    name = "library-chain-test";
    executable = packages.app;
    expectedOutput = "Library chain working";
  };
}
