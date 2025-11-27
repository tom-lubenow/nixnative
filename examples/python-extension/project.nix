{ pkgs, native }:

let
  python = pkgs.python3;
  pythonVersion = python.pythonVersion;

  # Python library via pkg-config
  pythonLib = native.pkgConfig.makeLibrary {
    name = "python";
    packages = [ python ];
    modules = [ "python3" ];
  };

  # Build extension as shared library
  mathextLib = native.sharedLib {
    name = "mathext";
    root = ./.;
    sources = [ "src/mathmodule.cc" ];
    libraries = [ pythonLib ];
    ldflags =
      if pkgs.stdenv.isDarwin
      then [ "-undefined" "dynamic_lookup" ]
      else [ ];
    flags = [ { type = "standard"; value = "c++17"; } ];
  };

  # Create Python-compatible package
  # Python extension modules always use .so on Unix (including macOS), not .dylib
  mathextPackage = pkgs.runCommand "mathext-${pythonVersion}" {} ''
    mkdir -p $out/lib/python${pythonVersion}/site-packages
    cp ${mathextLib.sharedLibrary} $out/lib/python${pythonVersion}/site-packages/mathext.so
  '';

  # Python with extension
  pythonWithMathext = python.withPackages (ps: [ mathextPackage ]);

  # Test runner
  testRunner = pkgs.writeShellScriptBin "test-mathext" ''
    export PYTHONPATH="${mathextPackage}/lib/python${pythonVersion}/site-packages:$PYTHONPATH"
    ${python}/bin/python3 ${./test_math.py}
  '';

in {
  inherit mathextLib mathextPackage pythonWithMathext testRunner;
  pythonExtensionExample = mathextPackage;
}
