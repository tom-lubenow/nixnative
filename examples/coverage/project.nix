{ pkgs, native }:

let
  sources = [ "src/*.cc" ];
  includeDirs = [ "src" ];
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

in
native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          appWithCoverage = {
            type = "executable";
            name = "coverage-example";
            inherit sources includeDirs;
            compileFlags = [ "--coverage" "-g" "-O0" ];
            linkFlags = [ "--coverage" ];
          };

          appNoCoverage = {
            type = "executable";
            name = "coverage-example-no-cov";
            inherit sources includeDirs;
            compileFlags = [ "-O2" ];
          };
        }
        // (if isLinux then {
          appCoverageAsan = {
            type = "executable";
            name = "coverage-example-asan";
            inherit sources includeDirs;
            compileFlags = [ "--coverage" "-fsanitize=address,undefined" "-g" "-O0" ];
            linkFlags = [ "--coverage" "-fsanitize=address,undefined" ];
          };
        } else { });

        tests = {
          coverage = {
            executable = "appWithCoverage";
            expectedOutput = "All tests passed";
          };

          noCoverage = {
            executable = "appNoCoverage";
            expectedOutput = "All tests passed";
          };
        }
        // (if isLinux then {
          coverageAsan = {
            executable = "appCoverageAsan";
            expectedOutput = "All tests passed";
          };
        } else { });
      };
    }
  ];
}
