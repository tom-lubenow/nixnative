# project.nix - Build definition for the executable example
#
# This file defines what to build. It's imported by flake.nix and receives
# `pkgs` (nixpkgs) and `native` (the nixnative library).

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
  };

  executableExample = proj.executable {
    name = "executable-example";
    sources = [ "src/*.cc" ];
    includeDirs = [ "include" ];
  };

  testExecutable = native.test {
    name = "test-executable-example";
    executable = executableExample;
    expectedOutput = "Hello from nixnative executable example";
  };

in {
  packages = {
    inherit executableExample;
  };

  checks = {
    inherit testExecutable;
  };
}
