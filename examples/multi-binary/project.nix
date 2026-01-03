{ pkgs, native }:

let
  # Shared static library
  commonLib = native.staticLib {
    name = "libmyapp-common";
    root = ./.;
    sources = [ "common/*.cc" ];  # Glob pattern matches all .cc files
    includeDirs = [ "common/include" ];
    publicIncludeDirs = [ "common/include" ];
  };

  # CLI tool
  cli = native.executable {
    name = "myapp-cli";
    root = ./.;
    sources = [ "cli/main.cc" ];
    libraries = [ commonLib ];
  };

  # Daemon
  daemon = native.executable {
    name = "myapp-daemon";
    root = ./.;
    sources = [ "daemon/main.cc" ];
    libraries = [ commonLib ];
    defines = [ "DAEMON_MODE" ];
  };

  # Test binary
  tests = native.executable {
    name = "myapp-tests";
    root = ./.;
    sources = [ "tests/main.cc" ];
    libraries = [ commonLib ];
    defines = [ "TEST_MODE" ];
    compileFlags = [ "-g" "-O0" ];  # Full debug info, no optimization
  };

  # Combined package - need to use .passthru.target for dynamic derivation outputs
  combined = pkgs.symlinkJoin {
    name = "myapp";
    paths = [
      cli.passthru.target
      daemon.passthru.target
      tests.passthru.target
    ];
  };

in {
  inherit commonLib cli daemon tests combined;
  multiBinaryExample = combined;
}
