{
  pkgs,
  native,
  packages,
}:

{
  pythonExtension = native.test {
    name = "python-extension-test";
    executable = packages.testRunner;
    expectedOutput = "All tests passed";
  };
}
