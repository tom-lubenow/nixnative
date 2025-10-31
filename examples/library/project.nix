{ pkgs, cpp }:

let
  lib = pkgs.lib;
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/math.cc" ];
  toolchain = cpp.toolchains.clang;

  library = cpp.mkStaticLib {
    name = "math-example";
    inherit root includeDirs sources;
    depsManifest = ./deps.json;
    toolchain = toolchain;
    publicIncludeDirs = includeDirs;
  };

  includeFlags = lib.concatMapStringsSep " " (dir: "-I${dir.path}") library.public.includeDirs;
  linkFlags = lib.concatStringsSep " " library.public.linkFlags;
  defaultCxxFlags = lib.concatStringsSep " " toolchain.defaultCxxFlags;

  runCheck = pkgs.runCommand "library-example-check" {
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

in {
  packages = {
    mathLibrary = library.drv;
  };

  checks = {
    mathLibrary = runCheck;
  };
}
