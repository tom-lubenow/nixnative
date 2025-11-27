{ pkgs, native, packages }:

{
  crossCompile = native.test {
    name = "cross-compile-native-test";
    executable = packages.nativeApp;
    expectedOutput = "Build successful";
  };
}
