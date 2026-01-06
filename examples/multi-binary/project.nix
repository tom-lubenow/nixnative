{ pkgs, native }:

native.project {
  modules = [
    ({ config, ... }:
      let
        combined = pkgs.symlinkJoin {
          name = "myapp";
          paths = [
            config.native.packages.cli.passthru.target
            config.native.packages.daemon.passthru.target
            config.native.packages.tests.passthru.target
          ];
        };
      in
      {
        native = {
          root = ./.;

          targets = {
            commonLib = {
              type = "staticLib";
              name = "libmyapp-common";
              sources = [ "common/*.cc" ];
              includeDirs = [ "common/include" ];
              publicIncludeDirs = [ "common/include" ];
            };

            cli = {
              type = "executable";
              name = "myapp-cli";
              sources = [ "cli/main.cc" ];
              libraries = [ { target = "commonLib"; } ];
            };

            daemon = {
              type = "executable";
              name = "myapp-daemon";
              sources = [ "daemon/main.cc" ];
              libraries = [ { target = "commonLib"; } ];
              defines = [ "DAEMON_MODE" ];
            };

            tests = {
              type = "executable";
              name = "myapp-tests";
              sources = [ "tests/main.cc" ];
              libraries = [ { target = "commonLib"; } ];
              defines = [ "TEST_MODE" ];
              compileFlags = [ "-g" "-O0" ];
            };
          };

          tests = {
            multiBinaryTests = {
              executable = "tests";
              expectedOutput = "All tests passed";
            };

            multiBinaryCli = {
              executable = "cli";
              args = [ "--version" ];
              expectedOutput = "myapp version";
            };

            multiBinaryDaemon = {
              executable = "daemon";
              args = [ "--check" ];
              expectedOutput = "Configuration OK";
            };
          };

          extraPackages = {
            inherit combined;
            multiBinaryExample = combined;
          };
        };
      })
  ];
}
