# Example: Using module defaults for shared settings
#
# This example demonstrates how project-level defaults reduce boilerplate
# by defining common settings once and applying them to all targets.
#
{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        defaults = {
          defines = [ "PROJECT_VERSION=100" ];
          compileFlags = [ "-Wall" "-Wextra" ];
          languageFlags = { cpp = [ "-std=c++17" ]; };
          includeDirs = [ "src/common" ];
        };

        targets = {
          libcommon = {
            type = "staticLib";
            name = "libcommon";
            sources = [ "src/common/*.cc" ];
            publicIncludeDirs = [ "src/common" ];
          };

          cli = {
            type = "executable";
            name = "cli";
            sources = [ "src/cli/main.cc" ];
            libraries = [ { target = "libcommon"; } ];
          };

          daemon = {
            type = "executable";
            name = "daemon";
            sources = [ "src/daemon/main.cc" ];
            libraries = [ { target = "libcommon"; } ];
            defines = [ "DAEMON_MODE" ];
          };

          cliDebug = {
            type = "executable";
            name = "cli-debug";
            sources = [ "src/cli/main.cc" ];
            libraries = [ { target = "libcommon"; } ];
            compileFlags = [ "-g" "-O0" ];
            defines = [ "DEBUG" ];
          };
        };

        tests = {
          cliCheck = {
            executable = "cli";
            expectedOutput = "[100] CLI tool running";
          };

          daemonCheck = {
            executable = "daemon";
            expectedOutput = "daemon mode";
          };
        };
      };
    }
  ];
}
