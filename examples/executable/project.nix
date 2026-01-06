# project.nix - Build definition for the executable example
#
# This file defines what to build. It's imported by flake.nix and receives
# `pkgs` (nixpkgs) and `native` (the nixnative library).

{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets.executableExample = {
          type = "executable";
          name = "executable-example";
          sources = [ "src/*.cc" ];
          includeDirs = [ "include" ];
        };

        tests.executableExample = {
          executable = "executableExample";
          expectedOutput = "Hello from nixnative executable example";
        };
      };
    }
  ];
}
