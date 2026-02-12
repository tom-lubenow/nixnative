# project.nix - Build definition for the coverage example
#
# Demonstrates building with coverage instrumentation.

{ pkgs, native }:

let
  sources = native.utils.discoverSources {
    root = ./.;
    patterns = [ "src/*.cc" ];
  };
  includeDirs = [ "src" ];
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  proj = native.project {
    root = ./.;
  };

  appWithCoverage = proj.executable {
    name = "coverage-example";
    inherit sources includeDirs;
    compileFlags = [ "--coverage" "-g" "-O0" ];
    linkFlags = [ "--coverage" ];
  };

  appNoCoverage = proj.executable {
    name = "coverage-example-no-cov";
    inherit sources includeDirs;
    compileFlags = [ "-O2" ];
  };

  appCoverageAsan = if isLinux then proj.executable {
    name = "coverage-example-asan";
    inherit sources includeDirs;
    compileFlags = [ "--coverage" "-fsanitize=address,undefined" "-g" "-O0" ];
    linkFlags = [ "--coverage" "-fsanitize=address,undefined" ];
  } else null;

  testCoverage = native.test {
    name = "test-coverage";
    executable = appWithCoverage;
    expectedOutput = "All tests passed";
  };

  testNoCoverage = native.test {
    name = "test-no-coverage";
    executable = appNoCoverage;
    expectedOutput = "All tests passed";
  };

  testCoverageAsan = if isLinux then native.test {
    name = "test-coverage-asan";
    executable = appCoverageAsan;
    expectedOutput = "All tests passed";
  } else null;

in {
  packages = {
    inherit appWithCoverage appNoCoverage;
  } // (if isLinux then { inherit appCoverageAsan; } else { });

  checks = {
    inherit testCoverage testNoCoverage;
  } // (if isLinux then { inherit testCoverageAsan; } else { });
}
