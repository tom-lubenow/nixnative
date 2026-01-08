{
  description = "Example: C++ calling Rust static library";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixnative.url = "path:../..";

  outputs =
    {
      self,
      nixpkgs,
      nixnative,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
            nixPackage = nixnative.inputs.nix.packages.${system}.default;
            ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
            native = nixnative.lib.native {
              inherit pkgs nixPackage;
              inherit (ninjaPackages) nix-ninja nix-ninja-task;
            };

            rustLib = pkgs.rustPlatform.buildRustPackage {
              pname = "rust_math";
              version = "0.1.0";
              src = ./rust-lib;
              cargoLock.lockFile = ./rust-lib/Cargo.lock;
              buildType = "release";
            };

            rustMathLib = {
              public = {
                includeDirs = [ { path = ./include; } ];
                defines = [ ];
                compileFlags = [ ];
                linkFlags = [
                  "${rustLib}/lib/librust_math.a"
                  "-lpthread"
                  "-ldl"
                  "-lm"
                ];
              };
            };

            proj = native.project {
              root = ./.;
            };

            app = proj.executable {
              name = "cpp-calls-rust";
              sources = [ "src/main.cpp" ];
              libraries = [ rustMathLib ];
            };

            testRun = native.test {
              name = "test-cpp-calls-rust";
              executable = app;
              expectedOutput = "rust_add(3, 4) = 7";
            };

          in
          f {
            inherit pkgs native app testRun;
          }
        );
    in
    {
      packages = forAllSystems (
        { app, ... }:
        {
          default = app;
          cppCallsRust = app;
        }
      );

      checks = forAllSystems (
        { testRun, ... }:
        {
          run = testRun;
        }
      );
    };
}
