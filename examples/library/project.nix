# project.nix - Build definition for the library example
#
# Demonstrates building a static library that can be consumed by other targets.

{ pkgs, native }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/math.cc" ];

  # Build a static library using the high-level API
  #
  # Key difference from executable:
  #   - `publicIncludeDirs` exposes headers to consumers
  #   - Output is a .a archive, not an executable
  #   - The `public` attribute propagates interface to dependents
  mathLibrary = native.staticLib {
    name = "math-example";
    inherit root includeDirs sources;

    # Headers to install and expose to consumers
    # These end up in $out/include/ and are added to dependent builds
    publicIncludeDirs = includeDirs;

    # Optional: propagate defines to consumers
    # publicDefines = [ "MATH_LIB_ENABLED" ];
  };

in {
  mathLibrary = mathLibrary;
}
