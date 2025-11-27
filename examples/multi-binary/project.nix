{ pkgs, native }:

let
  # Shared static library
  commonLib = native.staticLib {
    name = "myapp-common";
    root = ./.;
    sources = [
      "common/config.cc"
      "common/logger.cc"
      "common/database.cc"
    ];
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
    flags = [
      { type = "debug"; value = "full"; }
      { type = "optimize"; value = "0"; }
    ];
  };

  # Combined package
  combined = pkgs.symlinkJoin {
    name = "myapp";
    paths = [ cli daemon tests ];
  };

in {
  inherit commonLib cli daemon tests combined;
  multiBinaryExample = combined;
}
