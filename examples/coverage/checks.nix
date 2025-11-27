{ pkgs, native, packages }:

{
  coverage = native.test {
    name = "coverage-test";
    executable = packages.appWithCoverage;
    expectedOutput = "All tests passed";
  };

  noCoverage = native.test {
    name = "no-coverage-test";
    executable = packages.appNoCoverage;
    expectedOutput = "All tests passed";
  };
} // (if pkgs.stdenv.hostPlatform.isLinux && packages ? appCoverageAsan then {
  coverageAsan = native.test {
    name = "coverage-asan-test";
    executable = packages.appCoverageAsan;
    expectedOutput = "All tests passed";
  };
} else {})
