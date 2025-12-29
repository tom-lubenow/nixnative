# Python C++ extension example
#
# Builds a Python module using pybind11 and nixnative
#
{ pkgs, native }:

let
  # Python version to target
  python = pkgs.python312;
  pybind11 = python.pkgs.pybind11;

  # Get the extension suffix for this Python version
  # e.g., ".cpython-312-x86_64-linux-gnu.so"
  extensionSuffix = python.stdenv.hostPlatform.extensions.sharedLibrary;

  # Build the extension as a shared library
  mathext = native.sharedLib {
    name = "mathext";
    root = ./.;
    sources = [ "src/mathext.cpp" ];

    # Include pybind11 and Python headers
    includeDirs = [
      "${pybind11}/include"
      "${python}/include/python${python.pythonVersion}"
    ];

    # pybind11 compile flags
    extraCxxFlags = [
      "-fvisibility=hidden"
      "-std=c++17"
    ];

    # No need to link against Python on Linux with pybind11
    # (it uses the Python interpreter's symbols at runtime)
  };

  # Create a Python package that includes the extension
  pythonPackage = pkgs.stdenv.mkDerivation {
    name = "mathext-python";

    # We need the shared library built by nixnative
    buildInputs = [ mathext.passthru.target ];

    dontUnpack = true;
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      # Get the actual extension suffix from Python
      ext_suffix=$(${python}/bin/python3 -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")

      mkdir -p $out/lib/python${python.pythonVersion}/site-packages

      # Copy and rename the shared library to the correct Python extension name
      cp ${mathext.passthru.target}/libmathext.so \
         $out/lib/python${python.pythonVersion}/site-packages/mathext$ext_suffix

      runHook postBuild
    '';

    dontInstall = true;
    dontFixup = true;
  };

  # Create a Python environment with the extension installed
  pythonWithExt = python.withPackages (ps: [
    # Add any Python dependencies here
  ]);

in {
  # The raw shared library
  inherit mathext;

  # The Python package
  inherit pythonPackage;

  # Convenience: Python interpreter with the extension
  pythonEnv = pkgs.buildEnv {
    name = "python-with-mathext";
    paths = [ pythonWithExt pythonPackage ];
  };
}
