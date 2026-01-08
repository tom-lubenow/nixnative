# Python C++ extension example
#
# Builds a Python module using pybind11 and nixnative

{ pkgs, native }:

let
  python = pkgs.python312;
  pybind11 = python.pkgs.pybind11;

  proj = native.project {
    root = ./.;
  };

  mathext = proj.sharedLib {
    name = "mathext";
    sources = [ "src/mathext.cpp" ];
    includeDirs = [
      "${pybind11}/include"
      "${python}/include/python${python.pythonVersion}"
    ];
    compileFlags = [ "-fvisibility=hidden" ];
    languageFlags = {
      cpp = [ "-std=c++17" ];
    };
  };

  # Package the shared library as a Python module
  pythonPackage = pkgs.stdenv.mkDerivation {
    name = "mathext-python";

    buildInputs = [ mathext.passthru.target ];

    dontUnpack = true;
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      ext_suffix=$(${python}/bin/python3 -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")

      mkdir -p $out/lib/python${python.pythonVersion}/site-packages

      cp ${mathext.passthru.target}/mathext.so \
         $out/lib/python${python.pythonVersion}/site-packages/mathext$ext_suffix

      runHook postBuild
    '';

    dontInstall = true;
    dontFixup = true;
  };

  pythonWithExt = python.withPackages (ps: [ ]);

  pythonEnv = pkgs.buildEnv {
    name = "python-with-mathext";
    paths = [ pythonWithExt pythonPackage ];
  };

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

  pythonExtensionCheck = pkgs.runCommand "python-extension-test" {
    buildInputs = [ python pythonPackage ];
  } ''
    export PYTHONPATH="${pythonPackage}/lib/python${python.pythonVersion}/site-packages:$PYTHONPATH"

    ${python}/bin/python3 ${testScript}

    mkdir -p $out
    echo "Python extension test passed" > $out/result
  '';

in {
  packages = {
    inherit mathext pythonPackage pythonEnv;
  };

  checks = {
    pythonExtension = pythonExtensionCheck;
  };
}
