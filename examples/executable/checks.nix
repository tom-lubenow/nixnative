{ pkgs, native, packages }:

{
  # Use native.test which handles dynamic derivations properly
  executableExample = native.test {
    name = "executable-example";
    executable = packages.executableExample;
    expectedOutput = "Hello from nixnative executable example";
  };
}
