# Library chain example for nixnative
#
# Demonstrates multi-library dependencies where:
#   app → libmath → libcore → libutil
#
# Each library only needs to declare its direct dependencies;
# transitive dependencies are handled automatically.

{
  description = "Multi-library dependency chain example for nixnative";

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
          # Layer 1: libutil (no dependencies)
          # ================================================================
          #
          # The bottom of the chain - basic utility functions
          libutil = native.staticLib {
            name = "util";
            root = ./.;
            sources = [ "libutil/util.cc" ];
            includeDirs = [ "libutil/include" ];
            publicIncludeDirs = [ "libutil/include" ];
          };

          # ================================================================
          # Layer 2: libcore (depends on libutil)
          # ================================================================
          #
          # Core geometry types that use utility functions
          libcore = native.staticLib {
            name = "core";
            root = ./.;
            sources = [ "libcore/core.cc" ];
            includeDirs = [ "libcore/include" ];
            publicIncludeDirs = [ "libcore/include" ];

            # Direct dependency on libutil
            # libutil's public includes are automatically available
            libraries = [ libutil ];
          };

          # ================================================================
          # Layer 3: libmath (depends on libcore)
          # ================================================================
          #
          # Higher-level math operations using core types.
          # Note: we only list libcore as a dependency.
          # libutil is a transitive dependency - its headers and link flags
          # are propagated through libcore automatically.
          libmath = native.staticLib {
            name = "math_ext";
            root = ./.;
            sources = [ "libmath/math_ext.cc" ];
            includeDirs = [ "libmath/include" ];
            publicIncludeDirs = [ "libmath/include" ];

            # Only direct dependency - transitive deps handled automatically
            libraries = [ libcore ];
          };

          # ================================================================
          # Application (depends on libmath)
          # ================================================================
          #
          # The application only needs to declare libmath as a dependency.
          # All transitive dependencies (libcore, libutil) are handled.
          app = native.executable {
            name = "library-chain-demo";
            root = ./.;
            sources = [ "main.cc" ];

            # For demonstration, we also directly use libutil and libcore
            # headers in main.cc, so we include them explicitly.
            # In a typical project, you'd only include your direct dependency.
            libraries = [ libmath libcore libutil ];
          };

        in
        {
          default = app;
          inherit app libutil libcore libmath;
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages' = self.packages.${system};
        in
        {
          app = native.test {
            name = "library-chain-demo";
            executable = packages'.app;
            expectedOutput = "Library chain working correctly";
          };
        }
      );
    };
}
