{ pkgs, native, packages }:

{
  headerOnly = native.test {
    name = "header-only-test";
    executable = packages.testApp;
    expectedOutput = "a + b = (5, 7, 9)";  # Vec3 addition test
  };
}
