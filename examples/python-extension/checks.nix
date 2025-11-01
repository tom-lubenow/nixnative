{ pkgs, packages }:

let
  extension = packages.pythonExtension;
  python = extension.passthru.python;

in {
  pythonExtension = pkgs.runCommand "python-ext-test" {
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
}
