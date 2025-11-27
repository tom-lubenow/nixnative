{ pkgs, native, packages }:

{
  mixedApp = native.test {
    name = "mixed-app-test";
    executable = packages.mixedApp;
    expectedOutput = "Mixed C/C++ working correctly!";
  };

  cppApp = native.test {
    name = "cpp-app-test";
    executable = packages.cppApp;
    expectedOutput = "Mixed C/C++ working correctly!";
  };
}
