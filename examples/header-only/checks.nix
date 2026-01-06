{ pkgs, native }:

let
  project = import ./project.nix { inherit pkgs native; };
in
project.checks
