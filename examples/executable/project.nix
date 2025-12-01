# project.nix - Build definition for the executable example
#
# This file defines what to build. It's imported by flake.nix and receives
# `pkgs` (nixpkgs) and `native` (the nixnative library).

{ pkgs, native }:

let
  # Project root directory - all paths are relative to this
  root = ./.;

  # Directories to search for headers (relative to root)
  includeDirs = [ "include" ];

  # Source files to compile (relative to root)
  # Supports glob patterns:
  #   - "src/*.cc"    - all .cc files in src/
  #   - "**/*.cc"     - all .cc files recursively
  #   - "src/**/*.cc" - all .cc files under src/ recursively
  sources = [ "src/*.cc" ];

  # Build the executable using the high-level API
  # This automatically:
  #   - Selects a default toolchain (clang + platform linker)
  #   - Scans for header dependencies
  #   - Generates compile_commands.json for IDE support
  executable = native.executable {
    name = "executable-example";
    inherit root includeDirs sources;

    # Optional parameters (not used here, shown for reference):
    # defines = [ "DEBUG" ];              # Preprocessor definitions
    # flags = [ { type = "optimize"; value = "2"; } ];  # Abstract flags
    # libraries = [ someLib ];            # Library dependencies
    # compiler = "gcc";                   # Override compiler (default: clang)
    # linker = "mold";                    # Override linker (platform default)
  };

in
{
  executableExample = executable;
}
