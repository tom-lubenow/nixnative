{ pkgs, native }:

let
  sources = [ "src/main.cc" "src/calculator.cc" ];
  includeDirs = [ "src" ];

  # Coverage build
  appWithCoverage = native.executable {
    name = "coverage-example";
    root = ./.;
    inherit sources includeDirs;
    flags = [
      { type = "coverage"; }
      { type = "debug"; value = "full"; }
      { type = "optimize"; value = "0"; }
    ];
  };

  # Non-coverage build
  appNoCoverage = native.executable {
    name = "coverage-example-no-cov";
    root = ./.;
    inherit sources includeDirs;
    flags = [
      { type = "optimize"; value = "2"; }
    ];
  };

  # Coverage + ASan (Linux only)
  appCoverageAsan = native.executable {
    name = "coverage-example-asan";
    root = ./.;
    inherit sources includeDirs;
    flags = [
      { type = "coverage"; }
      { type = "sanitizer"; value = "address"; }
      { type = "sanitizer"; value = "undefined"; }
      { type = "debug"; value = "full"; }
      { type = "optimize"; value = "0"; }
    ];
  };

in {
  inherit appWithCoverage appNoCoverage;
  coverageExample = appWithCoverage;
} // (if pkgs.stdenv.hostPlatform.isLinux then {
  inherit appCoverageAsan;
} else {})
