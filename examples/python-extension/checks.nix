# Checks for python-extension example
{ pkgs, native, packages }:

let
  python = pkgs.python312;
  pythonPackage = packages.pythonPackage;

  # Create a test script that imports and uses the extension
  testScript = pkgs.writeText "test_mathext.py" ''
    import mathext

    # Test basic functions
    assert mathext.add(2, 3) == 5, "add failed"
    assert mathext.multiply(3, 4) == 12, "multiply failed"
    assert abs(mathext.power(2.0, 3.0) - 8.0) < 0.001, "power failed"

    # Test vector operations
    assert abs(mathext.dot_product([1.0, 2.0, 3.0], [4.0, 5.0, 6.0]) - 32.0) < 0.001, "dot_product failed"
    result = mathext.scale_vector([1.0, 2.0, 3.0], 2.0)
    assert result == [2.0, 4.0, 6.0], f"scale_vector failed: {result}"

    # Test Calculator class
    calc = mathext.Calculator(10.0)
    calc.add(5.0)
    assert calc.value == 15.0, "Calculator.add failed"
    calc.multiply(2.0)
    assert calc.value == 30.0, "Calculator.multiply failed"

    print("Python extension tests passed!")
  '';

in {
  # Test that the Python extension works correctly
  pythonExtension = pkgs.runCommand "python-extension-test" {
    buildInputs = [ python pythonPackage ];
  } ''
    # Add the extension to Python path
    export PYTHONPATH="${pythonPackage}/lib/python${python.pythonVersion}/site-packages:$PYTHONPATH"

    # Run the test
    ${python}/bin/python3 ${testScript}

    # Mark success
    mkdir -p $out
    echo "Python extension test passed" > $out/result
  '';
}
