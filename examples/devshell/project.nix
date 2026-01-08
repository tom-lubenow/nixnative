# project.nix - Build definition for the devshell example
#
# Demonstrates creating a development shell with clangd support.

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
  };

  app = proj.executable {
    name = "devshell-app";
    sources = [ "main.cc" ];
  };

  testDevshell = native.test {
    name = "test-devshell";
    executable = app;
  };

in {
  packages = {
    inherit app;
    devshellExample = app;
  };

  checks = {
    inherit testDevshell;
  };

  devShells.default = native.devShell {
    target = app;
  };
}
