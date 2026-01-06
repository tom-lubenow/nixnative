{
  description = "Example: Rust calling C++ library (using bindgen)";

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

            cppProject = native.project {
              modules = [
                {
                  native = {
                    root = ./cpp-lib;

                    targets.cppLib = {
                      type = "staticLib";
                      name = "mathlib";
                      sources = [ "src/mathlib.cpp" ];
                      includeDirs = [ "include" ];
                      publicIncludeDirs = [ "include" ];
                    };
                  };
                }
              ];
            };

            cppLib = cppProject.packages.cppLib;
            cppLibPath = cppLib.archivePath;
            cppLibDir = builtins.dirOf cppLibPath;

            rustApp = pkgs.rustPlatform.buildRustPackage {
              pname = "rust-calls-cpp";
              version = "0.1.0";
              src = pkgs.lib.cleanSourceWith {
                src = ./.;
                filter = path: type:
                  let
                    baseName = builtins.baseNameOf path;
                  in
                  (pkgs.lib.hasSuffix ".rs" baseName) ||
                  (pkgs.lib.hasSuffix ".toml" baseName) ||
                  (baseName == "Cargo.lock") ||
                  (baseName == "build.rs") ||
                  (baseName == "src") ||
                  (type == "directory" && baseName != "cpp-lib");
              };

              cargoLock.lockFile = ./Cargo.lock;

              nativeBuildInputs = [
                pkgs.rustPlatform.bindgenHook
              ];

              CPP_LIB_PATH = cppLibDir;
              CPP_INCLUDE_PATH = ./cpp-lib/include;

              preBuild = ''
                echo "C++ library path: $CPP_LIB_PATH"
                ls -la "$CPP_LIB_PATH" || true
              '';
            };

          in
          f {
            inherit pkgs native cppLib rustApp;
          }
        );
    in
    {
      packages = forAllSystems (
        { rustApp, ... }:
        {
          default = rustApp;
          rustCallsCpp = rustApp;
        }
      );

      checks = forAllSystems (
        { pkgs, rustApp, ... }:
        {
          run = pkgs.runCommand "rust-calls-cpp-check" { } ''
            ${rustApp}/bin/rust-calls-cpp > $out
            grep -q "cpp_add(5, 3) = 8" $out
            grep -q "cpp_multiply(4, 7) = 28" $out
            grep -q "cpp_fibonacci(20) = 6765" $out
          '';
        }
      );
    };
}
