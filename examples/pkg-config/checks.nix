{ pkgs, native, packages }:

{
  pkgConfig = native.test {
    name = "pkgconfig-test";
    executable = packages.demo;
    expectedOutput = "All libraries working correctly!";
  };
}
