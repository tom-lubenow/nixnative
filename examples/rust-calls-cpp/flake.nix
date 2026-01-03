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

            # Build the C++ static library with nixnative (incremental!)
            cppLib = native.staticLib {
              name = "mathlib";
              root = ./cpp-lib;
              sources = [ "src/mathlib.cpp" ];
              includeDirs = [ "include" ];
              publicIncludeDirs = [ "include" ];
            };

            # The archive path from the dynamic derivation
            cppLibPath = cppLib.archivePath;
            # Directory containing the archive
            cppLibDir = builtins.dirOf cppLibPath;

            # Build the Rust binary that links against the C++ library
            rustApp = pkgs.rustPlatform.buildRustPackage {
              pname = "rust-calls-cpp";
              version = "0.1.0";
              src = pkgs.lib.cleanSourceWith {
                src = ./.;
                filter = path: type:
                  let
                    baseName = builtins.baseNameOf path;
                  in
                  # Include Rust source files and Cargo files
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

              # Pass the C++ library paths to build.rs
              CPP_LIB_PATH = cppLibDir;
              CPP_INCLUDE_PATH = ./cpp-lib/include;

              # Ensure the library is built before Rust compilation
              preBuild = ''
                # The CPP_LIB_PATH contains the nixnative-built library
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
