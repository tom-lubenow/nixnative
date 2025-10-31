{ pkgs, cpp }:

let
  root = ./.;
  python = pkgs.python3;

  extension = cpp.mkPythonExtension {
    name = "hello_ext";
    inherit root python;
    sources = [ "src/hello_ext.cc" ];
  };

  test = pkgs.runCommand "python-ext-test" {
    buildInputs = [ python ];
  } ''
    set -euo pipefail
    export PYTHONPATH=${extension.pythonPath}
    ${python}/bin/python - <<'PY'
import hello_ext
assert hello_ext.greet("Nix") == "hello, Nix!"
PY
    mkdir -p "$out"
    touch "$out/passed"
  '';

in {
  packages = {
    pythonExtension = extension.drv;
  };

  checks = {
    pythonExtension = test;
  };

  passthru = {
    inherit extension python;
  };
}
