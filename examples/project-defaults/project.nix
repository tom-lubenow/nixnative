# project.nix - Example: Using project defaults for shared settings
#
# This example demonstrates how project-level defaults reduce boilerplate
# by defining common settings once and applying them to all targets.

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
    defines = [ "PROJECT_VERSION=100" ];
    compileFlags = [ "-Wall" "-Wextra" ];
    languageFlags = { cpp = [ "-std=c++17" ]; };
    includeDirs = [ "src/common" ];
  };

  libcommon = proj.staticLib {
    name = "libcommon";
    sources = [ "src/common/*.cc" ];
    publicIncludeDirs = [ "src/common" ];
  };

  cli = proj.executable {
    name = "cli";
    sources = [ "src/cli/main.cc" ];
    libraries = [ libcommon ];
  };

  daemon = proj.executable {
    name = "daemon";
    sources = [ "src/daemon/main.cc" ];
    libraries = [ libcommon ];
    defines = [ "DAEMON_MODE" ];
  };

  cliDebug = proj.executable {
    name = "cli-debug";
    sources = [ "src/cli/main.cc" ];
    libraries = [ libcommon ];
    compileFlags = [ "-g" "-O0" ];
    defines = [ "DEBUG" ];
  };

  testCli = native.test {
    name = "test-cli";
    executable = cli;
    expectedOutput = "[100] CLI tool running";
  };

  testDaemon = native.test {
    name = "test-daemon";
    executable = daemon;
    expectedOutput = "daemon mode";
  };

in {
  packages = {
    inherit libcommon cli daemon cliDebug;
  };

  checks = {
    inherit testCli testDaemon;
  };
}
