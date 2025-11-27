{ pkgs, native }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" ];

  # Build Rust static library manually
  rustStaticLib = pkgs.runCommand "nixnative-rust-lib"
    {
      src = ./rust-lib;
      buildInputs = [ pkgs.rustc ];
    }
    ''
      set -euo pipefail
      mkdir -p "$out/lib"
      rustc \
        --crate-type staticlib \
        --crate-name nixnative_rust \
        --edition=2021 \
        -C opt-level=2 \
        -C panic=abort \
        "$src/src/lib.rs" \
        -o "$out/lib/libnixnative_rust.a"
    '';

  # Wrap as a library with public interface
  rustLibrary = {
    name = "rust-lib";
    drv = rustStaticLib;
    public = {
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      linkFlags = [ "${rustStaticLib}/lib/libnixnative_rust.a" ];
    };
  };

  # Build executable using high-level API
  executable = native.executable {
    name = "rust-integration";
    inherit root includeDirs sources;
    libraries = [ rustLibrary ];
  };

in {
  rustInteropExample = executable;
}
