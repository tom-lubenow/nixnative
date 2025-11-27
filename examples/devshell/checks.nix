{ pkgs, native, packages }:

{
  # Just verify the app builds and runs
  devshell = native.test {
    name = "devshell-app-test";
    executable = packages.app;
    # No expectedOutput - just verifies the app runs without error
  };
}
