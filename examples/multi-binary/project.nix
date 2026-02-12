# project.nix - Build definition for the multi-binary example
#
# Demonstrates building multiple executables from a shared library,
# and combining them into a single package.

{ pkgs, native }:

let
  commonSources = native.utils.discoverSources {
    root = ./.;
    patterns = [ "common/*.cc" ];
  };

  proj = native.project {
    root = ./.;
  };

  commonLib = proj.staticLib {
    name = "libmyapp-common";
    sources = commonSources;
    includeDirs = [ "common/include" ];
    publicIncludeDirs = [ "common/include" ];
  };

  cli = proj.executable {
    name = "myapp-cli";
    sources = [ "cli/main.cc" ];
    libraries = [ commonLib ];
  };

  daemon = proj.executable {
    name = "myapp-daemon";
    sources = [ "daemon/main.cc" ];
    libraries = [ commonLib ];
    defines = [ "DAEMON_MODE" ];
  };

  tests = proj.executable {
    name = "myapp-tests";
    sources = [ "tests/main.cc" ];
    libraries = [ commonLib ];
    defines = [ "TEST_MODE" ];
    compileFlags = [ "-g" "-O0" ];
  };

  # Combined package with all binaries
  combined = pkgs.symlinkJoin {
    name = "myapp";
    paths = [
      cli.target
      daemon.target
      tests.target
    ];
  };

  testTests = native.test {
    name = "test-multi-binary-tests";
    executable = tests;
    expectedOutput = "All tests passed";
  };

  testCli = native.test {
    name = "test-multi-binary-cli";
    executable = cli;
    args = [ "--version" ];
    expectedOutput = "myapp version";
  };

  testDaemon = native.test {
    name = "test-multi-binary-daemon";
    executable = daemon;
    args = [ "--check" ];
    expectedOutput = "Configuration OK";
  };

in {
  packages = {
    inherit commonLib cli daemon tests combined;
    multiBinaryExample = combined;
  };

  checks = {
    inherit testTests testCli testDaemon;
  };
}
