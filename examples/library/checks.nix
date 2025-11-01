{ pkgs, packages }:

let
  mathLibrary = packages.mathLibrary;
  toolchain = mathLibrary.passthru.toolchain;
  includeFlags = pkgs.lib.concatMapStringsSep " " (dir: "-I${dir.path}") mathLibrary.public.includeDirs;
  linkFlags = pkgs.lib.concatStringsSep " " mathLibrary.public.linkFlags;
  defaultCxxFlags = pkgs.lib.concatStringsSep " " toolchain.defaultCxxFlags;

in {
  mathLibrary = pkgs.runCommand "library-example-check" {
    buildInputs = toolchain.runtimeInputs;
  } ''
    set -euo pipefail
    cat > main.cc <<'CC'
#include <iostream>
#include "math.hpp"

int main() {
  std::cout << add(2, 3) << " " << mul(3, 4) << "\n";
  return 0;
}
CC
    ${toolchain.cxx} ${defaultCxxFlags} ${includeFlags} main.cc ${linkFlags} -o test
    ./test > "$out"
  '';
}
