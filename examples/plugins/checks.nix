{ pkgs, native, packages }:

{
  plugins = native.test {
    name = "plugins-test";
    executable = packages.runScript;
    expectedOutput = "Hello from MyPlugin!";
  };
}
