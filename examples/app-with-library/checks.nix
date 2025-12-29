{ pkgs, native, packages }:

{
  # Verify the app runs and outputs expected content
  simpleApp = native.test {
    name = "simple-app";
    executable = packages.app;
    expectedOutput = "2 + 3 = 5";  # Just check one key line
  };
}
