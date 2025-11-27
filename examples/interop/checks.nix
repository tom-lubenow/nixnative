{ pkgs, native, packages }:

{
  interop = native.test {
    name = "interop-test";
    executable = packages.app;
    expectedOutput = "42";
  };
}
