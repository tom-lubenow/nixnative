# Example: Using mkProject for shared defaults
#
# This example demonstrates how mkProject reduces boilerplate by defining
# common settings once and having them automatically apply to all targets.
#
{ pkgs, native }:

let
  # Create a project with shared defaults
  project = native.mkProject {
    root = ./.;

    # These settings apply to ALL targets in this project
    defaults = {
      # Common preprocessor defines
      defines = [ "PROJECT_VERSION=100" ];

      # Common compile flags
      compileFlags = [ "-Wall" "-Wextra" ];

      # Per-language flags
      languageFlags = {
        cpp = [ "-std=c++17" ];
      };

      # Common include directories
      includeDirs = [ "src/common" ];
    };
  };

  # Shared library - inherits all defaults automatically
  libcommon = project.staticLib {
    name = "libcommon";
    sources = [ "src/common/*.cc" ];
    publicIncludeDirs = [ "src/common" ];
  };

  # CLI tool - inherits defaults, adds its own sources
  cli = project.executable {
    name = "cli";
    sources = [ "src/cli/main.cc" ];
    libraries = [ libcommon ];
  };

  # Daemon - inherits defaults, adds daemon-specific define
  daemon = project.executable {
    name = "daemon";
    sources = [ "src/daemon/main.cc" ];
    libraries = [ libcommon ];
    # This gets merged with project defaults
    defines = [ "DAEMON_MODE" ];
  };

  # Debug build - extend the project with debug-specific defaults
  debugProject = project.extend {
    compileFlags = [ "-g" "-O0" ];
    defines = [ "DEBUG" ];
  };

  cliDebug = debugProject.executable {
    name = "cli-debug";
    sources = [ "src/cli/main.cc" ];
    libraries = [ libcommon ];
  };

in {
  inherit libcommon cli daemon cliDebug;

  # For testing
  projectDefaultsExample = cli;
}
