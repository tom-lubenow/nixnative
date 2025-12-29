# Python C++ extension example for nixnative
#
# Demonstrates building a Python module with C++ code using pybind11.
# The extension is built as a shared library and packaged for Python.

{
  description = "Python C++ extension built with nixnative and pybind11";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nixPackage = nixnative.inputs.nix.packages.${system}.default;
          ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
          native = nixnative.lib.native {
            inherit pkgs nixPackage;
            inherit (ninjaPackages) nix-ninja nix-ninja-task;
          };
          packages = import ./project.nix { inherit pkgs native; };
        in
        packages // {
          default = packages.pythonPackage;
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nixPackage = nixnative.inputs.nix.packages.${system}.default;
          ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
          native = nixnative.lib.native {
            inherit pkgs nixPackage;
            inherit (ninjaPackages) nix-ninja nix-ninja-task;
          };
          packages = import ./project.nix { inherit pkgs native; };
          python = pkgs.python312;
        in
        {
          # Test that the extension can be imported and used
          pythonExtension = pkgs.stdenv.mkDerivation {
            name = "test-python-extension";

            buildInputs = [
              python
              packages.pythonPackage
            ];

            dontUnpack = true;
            dontConfigure = true;

            buildPhase = ''
              runHook preBuild

              export PYTHONPATH="${packages.pythonPackage}/lib/python${python.pythonVersion}/site-packages:$PYTHONPATH"

              # Test basic import
              ${python}/bin/python3 -c "import mathext; print('Import successful')"

              # Test functions
              ${python}/bin/python3 << 'EOF'
import mathext

# Test add
assert mathext.add(2, 3) == 5, "add failed"
print("add(2, 3) =", mathext.add(2, 3))

# Test multiply
assert mathext.multiply(4, 5) == 20, "multiply failed"
print("multiply(4, 5) =", mathext.multiply(4, 5))

# Test power
assert abs(mathext.power(2.0, 3.0) - 8.0) < 0.001, "power failed"
print("power(2.0, 3.0) =", mathext.power(2.0, 3.0))

# Test dot_product
result = mathext.dot_product([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
assert abs(result - 32.0) < 0.001, "dot_product failed"
print("dot_product([1,2,3], [4,5,6]) =", result)

# Test scale_vector
scaled = mathext.scale_vector([1.0, 2.0, 3.0], 2.0)
assert scaled == [2.0, 4.0, 6.0], "scale_vector failed"
print("scale_vector([1,2,3], 2.0) =", scaled)

# Test Calculator class
calc = mathext.Calculator(10.0)
print("Calculator(10.0) =", calc)
calc.add(5.0)
assert calc.value == 15.0, "Calculator.add failed"
calc.multiply(2.0)
assert calc.value == 30.0, "Calculator.multiply failed"
print("After add(5) and multiply(2):", calc)

print("\nAll tests passed!")
EOF

              runHook postBuild
            '';

            installPhase = ''
              mkdir -p $out
              echo "Python extension tests passed" > $out/result
            '';
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nixPackage = nixnative.inputs.nix.packages.${system}.default;
          ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
          native = nixnative.lib.native {
            inherit pkgs nixPackage;
            inherit (ninjaPackages) nix-ninja nix-ninja-task;
          };
          packages = import ./project.nix { inherit pkgs native; };
          python = pkgs.python312;
        in
        {
          default = pkgs.mkShell {
            packages = [
              python
              python.pkgs.pybind11
              pkgs.gdb
            ];

            inputsFrom = [ packages.pythonPackage ];

            shellHook = ''
              export PYTHONPATH="${packages.pythonPackage}/lib/python${python.pythonVersion}/site-packages:$PYTHONPATH"
              echo "Python extension development shell"
              echo "Run 'python3' to test the mathext module"
            '';
          };
        }
      );
    };
}
