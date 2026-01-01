{ pkgs, native }:

let
  sources = [ "src/*.cc" ];  # Glob pattern matches all .cc files in src/
  includeDirs = [ "src" ];

  # Coverage build
  appWithCoverage = native.executable {
    name = "coverage-example";
    root = ./.;
    inherit sources includeDirs;
    compileFlags = [ "--coverage" "-g" "-O0" ];
    ldflags = [ "--coverage" ];
  };

  # Non-coverage build
  appNoCoverage = native.executable {
    name = "coverage-example-no-cov";
    root = ./.;
    inherit sources includeDirs;
    compileFlags = [ "-O2" ];
  };

  # Coverage + ASan (Linux only)
  appCoverageAsan = native.executable {
    name = "coverage-example-asan";
    root = ./.;
    inherit sources includeDirs;
    compileFlags = [ "--coverage" "-fsanitize=address,undefined" "-g" "-O0" ];
    ldflags = [ "--coverage" "-fsanitize=address,undefined" ];
  };

in {
  inherit appWithCoverage appNoCoverage;
  coverageExample = appWithCoverage;
} // (if pkgs.stdenv.hostPlatform.isLinux then {
  inherit appCoverageAsan;
} else {})
