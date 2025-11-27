{ pkgs, native, packages }:

{
  simpleTool = native.test {
    name = "simple-tool-test";
    executable = packages.appInline;
    expectedOutput = "Code generation working";
  };
}
