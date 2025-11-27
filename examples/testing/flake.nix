# Testing example for nixnative
#
# Demonstrates the test infrastructure and edge cases like:
# - Basic tests with expected output
# - Tests with arguments
# - Shell escaping (special characters)
# - LTO builds
# - AddressSanitizer (Linux only)
# - Minimal configuration

{
  description = "Testing mkTest and edge cases";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };

          # Basic app for testing - prints "Hello <arg>" or "Hello Test"
          app = native.executable {
            name = "test-app";
            root = ./.;
            sources = [ "main.cc" ];
          };

          # ================================================================
          # Basic Tests
          # ================================================================

          # Simple test: run executable, check output
          test1 = native.test {
            name = "basic-test";
            executable = app;
            expectedOutput = "Hello Test";
          };

          # Test with command-line arguments
          test2 = native.test {
            name = "arg-test";
            executable = app;
            args = [ "World" ];
            expectedOutput = "Hello World";
          };

          # Edge case: verify shell escaping works correctly
          # This catches bugs where special characters aren't properly quoted
          test3 = native.test {
            name = "special-chars-test";
            executable = app;
            args = [ "it's \"quoted\" & $special" ];
            expectedOutput = "Hello it's \"quoted\" & $special";
          };

          # ================================================================
          # Build Configuration Tests
          # ================================================================

          # Test LTO (Link-Time Optimization) builds
          appLto = native.executable {
            name = "test-app-lto";
            root = ./.;
            sources = [ "main.cc" ];
            flags = [ { type = "lto"; value = "thin"; } ];
          };

          testLto = native.test {
            name = "lto-test";
            executable = appLto;
            expectedOutput = "Hello Test";
          };

          # Test AddressSanitizer builds (Linux only - ASan has runtime
          # issues on macOS within Nix sandboxing)
          appAsan = native.executable {
            name = "test-app-asan";
            root = ./.;
            sources = [ "main.cc" ];
            flags = [
              { type = "sanitizer"; value = "address"; }
              { type = "sanitizer"; value = "undefined"; }
            ];
          };

          testAsan = native.test {
            name = "asan-test";
            executable = appAsan;
            expectedOutput = "Hello Test";
          };

          # ================================================================
          # Edge Cases
          # ================================================================

          # Test that empty optional lists work correctly
          appMinimal = native.executable {
            name = "test-app-minimal";
            root = ./.;
            sources = [ "main.cc" ];
            includeDirs = [ ];
            defines = [ ];
            extraCxxFlags = [ ];
            libraries = [ ];
            tools = [ ];
          };

          testMinimal = native.test {
            name = "minimal-test";
            executable = appMinimal;
            expectedOutput = "Hello Test";
          };

        in
        {
          default = app;
          inherit app appLto appMinimal;
          inherit test1 test2 test3 testLto testMinimal;
        }
        # ASan tests only on Linux
        // (if pkgs.stdenv.hostPlatform.isLinux then {
          inherit appAsan testAsan;
        } else { })
      );

      # Expose tests for `nix flake check`
      checks = forAllSystems (system:
        let
          packages' = self.packages.${system};
        in
        {
          inherit (packages') test1 test2 test3 testLto testMinimal;
        }
        // (if (packages' ? testAsan) then {
          inherit (packages') testAsan;
        } else { })
      );
    };
}
