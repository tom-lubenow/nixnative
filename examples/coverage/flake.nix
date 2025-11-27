# Code coverage example for nixnative
#
# Demonstrates code coverage instrumentation using abstract flags.
# Shows how to build coverage-enabled binaries and generate reports.

{
  description = "Code coverage example for nixnative";

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
          packages = import ./project.nix { inherit pkgs native; };
        in
        packages // { default = packages.coverageExample; }
      );

      # Development shell with coverage tools
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.lcov       # Coverage report generation
              pkgs.gcovr      # Alternative coverage tool
            ] ++ (if pkgs.stdenv.hostPlatform.isDarwin
              then [ ]  # llvm-cov is part of clang on Darwin
              else [ pkgs.lcov ]);

            shellHook = ''
              echo "Coverage development shell"
              echo ""
              echo "Available commands:"
              echo "  lcov --capture --directory . --output-file coverage.info"
              echo "  genhtml coverage.info --output-directory coverage-report"
              echo ""
            '';
          };
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
        in
        import ./checks.nix { inherit pkgs native packages; }
      );
    };
}
