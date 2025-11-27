{ pkgs, native, craneLib }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" ];

  # Build Rust library using crane
  crateSrc = craneLib.cleanCargoSource ./rust-crate;

  rustStatic = craneLib.buildPackage {
    pname = "nixnative-rust-crane";
    version = "0.1.0";
    src = crateSrc;
    cargoExtraArgs = "--locked";
  };

  rustLibPath = "${rustStatic}/lib/libnixnative_rust_crane.a";

  # Wrap as a library with public interface
  rustLibrary = {
    name = "rust-crane-lib";
    drv = rustStatic;
    public = {
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      linkFlags = [ rustLibPath ];
    };
  };

  # Build executable using high-level API
  executable = native.executable {
    name = "rust-crane-integration";
    inherit root includeDirs sources;
    libraries = [ rustLibrary ];
  };

in {
  rustCraneInterop = executable;
}
