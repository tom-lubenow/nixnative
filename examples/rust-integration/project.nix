{ pkgs, cpp }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" ];

  rustStaticLib = pkgs.runCommand "nixclang-rust-lib"
    {
      src = ./rust-lib;
      buildInputs = [ pkgs.rustc ];
    }
    ''
      set -euo pipefail
      mkdir -p "$out/lib"
      rustc \
        --crate-type staticlib \
        --crate-name nixclang_rust \
        --edition=2021 \
        -C opt-level=2 \
        -C panic=abort \
        "$src/src/lib.rs" \
        -o "$out/lib/libnixclang_rust.a"
    '';

  rustLibrary = {
    drv = rustStaticLib;
    public = {
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      linkFlags = [ "${rustStaticLib}/lib/libnixclang_rust.a" ];
    };
  };

  executable = cpp.mkExecutable {
    name = "rust-integration";
    inherit root includeDirs sources;
    libraries = [ rustLibrary ];
  };

in {
  rustInteropExample = executable;
}
