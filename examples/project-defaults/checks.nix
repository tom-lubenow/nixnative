{ pkgs, native, packages }:

let
  # Run CLI and verify output
  cliCheck = native.test {
    name = "project-defaults-cli";
    executable = packages.cli;
    expectedOutput = "[100] CLI tool running";
  };

  # Run daemon and verify output
  daemonCheck = native.test {
    name = "project-defaults-daemon";
    executable = packages.daemon;
    expectedOutput = "daemon mode";
  };

in {
  inherit cliCheck daemonCheck;
}
