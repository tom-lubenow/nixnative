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

          # Basic app for testing
          app = native.executable {
            name = "test-app";
            root = ./.;
            sources = [ "main.cc" ];
          };

          # Basic tests
          test1 = native.test {
            name = "basic-test";
            executable = app;
            expectedOutput = "Hello Test";
          };

          test2 = native.test {
            name = "arg-test";
            executable = app;
            args = [ "World" ];
            expectedOutput = "Hello World";
          };

          # Edge case: special characters in args (shell escaping test)
          test3 = native.test {
            name = "special-chars-test";
            executable = app;
            args = [ "it's \"quoted\" & $special" ];
            expectedOutput = "Hello it's \"quoted\" & $special";
          };

          # Edge case: LTO build using abstract flags
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

          # Edge case: Address sanitizer (only on Linux, ASan has issues on macOS)
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

          # Edge case: empty optional lists (should work fine)
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
        # Only include ASan tests on Linux (ASan has runtime issues on macOS with Nix)
        // (if pkgs.stdenv.hostPlatform.isLinux then {
          inherit appAsan testAsan;
        } else { })
      );

      # Expose checks for `nix flake check`
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
