# Mixed C/C++ example for nixnative
#
# Demonstrates building projects with both C (.c) and C++ (.cc) sources.
# Shows proper extern "C" usage for C/C++ interoperability.

{
  description = "Mixed C/C++ project example for nixnative";

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

          # ================================================================
          # Option 1: Single executable with mixed sources
          # ================================================================
          #
          # nixnative handles .c files with the C compiler and .cc/.cpp
          # files with the C++ compiler automatically based on extension.
          mixedApp = native.executable {
            name = "mixed-app";
            root = ./.;

            # Mix of C and C++ sources - handled automatically
            sources = [
              "clib.c"     # Compiled as C
              "main.cc"    # Compiled as C++
            ];

            includeDirs = [ "include" ];
          };

          # ================================================================
          # Option 2: C library consumed by C++ code
          # ================================================================
          #
          # Build the C code as a separate static library, then link
          # it into the C++ application. This is useful when you want
          # to reuse the C library in multiple projects.

          # C-only static library
          cLib = native.staticLib {
            name = "clib";
            root = ./.;
            sources = [ "clib.c" ];
            includeDirs = [ "include" ];
            publicIncludeDirs = [ "include" ];
          };

          # C++ application using the C library
          cppApp = native.executable {
            name = "cpp-app";
            root = ./.;
            sources = [ "main.cc" ];
            includeDirs = [ "include" ];
            libraries = [ cLib ];
          };

        in
        {
          default = mixedApp;
          inherit mixedApp cLib cppApp;
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages' = self.packages.${system};
        in
        {
          mixedApp = native.test {
            name = "mixed-app";
            executable = packages'.mixedApp;
            expectedOutput = "Mixed C/C++ working correctly";
          };

          cppApp = native.test {
            name = "cpp-app";
            executable = packages'.cppApp;
            expectedOutput = "Mixed C/C++ working correctly";
          };
        }
      );
    };
}
