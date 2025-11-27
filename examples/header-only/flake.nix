# Header-only library example for nixnative
#
# Demonstrates creating and consuming header-only libraries using native.headerOnly.
# Header-only libraries have no compiled sources - just headers that consumers include.

{
  description = "Header-only library example for nixnative";

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

          # Header-only library: no sources to compile, just headers
          #
          # This creates a library that can be used as a dependency.
          # Consumers get the include directories added to their compile commands.
          vec3Lib = native.headerOnly {
            name = "vec3";
            root = ./.;

            # Headers to expose to consumers
            # These will be available as #include "vec3.hpp"
            publicIncludeDirs = [ "include" ];

            # Optional: propagate defines to consumers
            # publicDefines = [ "VEC3_USE_SIMD" ];
          };

          # Executable that uses the header-only library
          demo = native.executable {
            name = "header-only-demo";
            root = ./.;
            sources = [ "main.cc" ];

            # The header-only library is consumed like any other library
            libraries = [ vec3Lib ];
          };

        in
        {
          default = demo;
          inherit vec3Lib demo;
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages' = self.packages.${system};
        in
        {
          # Verify the demo runs correctly
          demo = native.test {
            name = "header-only-demo";
            executable = packages'.demo;
            expectedOutput = "a + b = (5, 7, 9)";
          };
        }
      );
    };
}
