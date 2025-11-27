{ pkgs, native, packages }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

in {
  # Test that default builds and runs
  multiToolchainDefault = native.test {
    name = "test-multi-default";
    executable = packages.default;
    expectedOutput = "Compiler:";
  };

  # Test optimized build
  multiToolchainO3 = native.test {
    name = "test-multi-o3";
    executable = packages.withO3;
    expectedOutput = "compute(100)";
  };
}
