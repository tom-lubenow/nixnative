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

            # Build the Rust static library
            rustLib = pkgs.rustPlatform.buildRustPackage {
              pname = "rust_math";
              version = "0.1.0";
              src = ./rust-lib;
              cargoLock.lockFile = ./rust-lib/Cargo.lock;
              # We want the static library, not an executable
              buildType = "release";
            };

            # Wrap the Rust library for nixnative consumption
            rustMathLib = {
              public = {
                includeDirs = [ { path = ./include; } ];
                defines = [ ];
                compileFlags = [ ];
                linkFlags = [
                  "${rustLib}/lib/librust_math.a"
                  # Rust static libs need these system libraries
                  "-lpthread"
                  "-ldl"
                  "-lm"
                ];
              };
            };

            # C++ executable that calls Rust
            app = native.executable {
              name = "cpp-calls-rust";
              root = ./.;
              sources = [ "src/main.cpp" ];
              libraries = [ rustMathLib ];
            };

          in
          f {
            inherit pkgs native app;
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
        { native, app, ... }:
        {
          run = native.test {
            name = "cpp-calls-rust";
            executable = app;
            expectedOutput = "rust_add(3, 4) = 7";
          };
        }
      );
    };
}
