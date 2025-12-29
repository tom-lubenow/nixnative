# Dynamic derivations example
#
# Demonstrates using dynamic derivations to avoid IFD (Import From Derivation).
# Requires Nix with experimental features: dynamic-derivations, ca-derivations
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
  # Sequential mode: single driver, simple but not parallel
  sequentialExample = native.executable {
    name = "sequential-example";
    root = ./.;
    sources = [ "src/*.cc" ];
    includeDirs = [ ./include ];
    dynamic = true;  # Uses mkDynamicDriver (sequential)
  };

  # Parallel mode: per-source wrappers, true parallelism
  # This creates N compile wrapper derivations at eval time
  # Nix builds them all in parallel!
  parallelExample = native.mkParallelDriver {
    name = "parallel-example";
    root = ./.;
    sources = [ "src/*.cc" ];
    includeDirs = [ ./include ];
    inherit toolchain;
    outputType = "executable";
  };
}
