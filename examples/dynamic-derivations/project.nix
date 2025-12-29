# Dynamic derivations example
#
# Demonstrates using dynamic derivations to avoid IFD (Import From Derivation).
# Requires Nix with experimental features: dynamic-derivations, ca-derivations
#
# With the refactored architecture, all builds use dynamic derivations by default.
# Each source file gets its own compile wrapper, enabling true parallelism.
#
{ pkgs, native }:

let
  # Use the default toolchain (clang + lld)
  toolchain = native.mkToolchain {
    languages = {
      c = native.compilers.clang.c;
      cpp = native.compilers.clang.cpp;
    };
  };
in {
  # All executables now use dynamic derivations automatically
  # Each source file gets a separate compile wrapper, built in parallel
  parallelExample = native.executable {
    name = "parallel-example";
    root = ./.;
    sources = [ "src/*.cc" ];
    includeDirs = [ ./include ];
    inherit toolchain;
  };
}
