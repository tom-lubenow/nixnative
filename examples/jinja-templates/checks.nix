{ pkgs, native, packages }:

{
  jinjaTemplates = native.test {
    name = "jinja-templates-test";
    executable = packages.app;
    expectedOutput = "All templates working correctly!";
  };
}
