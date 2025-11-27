# Python extension module example for nixnative
#
# Demonstrates building Python C/C++ extension modules using nixnative's
# shared library builder with Python-specific configuration.

{
  description = "Python extension module example for nixnative";

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
        packages // { default = packages.mathextPackage; }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
        in
        import ./checks.nix { inherit pkgs native packages; }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
        in
        {
          default = pkgs.mkShell {
            packages = [ packages.pythonWithMathext pkgs.python3Packages.pytest ];
            shellHook = ''
              echo "Python extension development shell"
              echo "  python3 -c 'import mathext; print(mathext.add(1, 2))'"
            '';
          };
        }
      );
    };
}
