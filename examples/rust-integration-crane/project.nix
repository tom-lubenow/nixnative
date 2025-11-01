{ pkgs, cpp, craneLib }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" ];

  crateSrc = craneLib.cleanCargoSource ./rust-crate;

  rustStatic = craneLib.buildPackage {
    pname = "nixclang-rust-crane";
    version = "0.1.0";
    src = crateSrc;
    cargoExtraArgs = "--locked";
  };

  rustLibPath = "${rustStatic}/lib/libnixclang_rust_crane.a";

  rustLibrary = {
    drv = rustStatic;
    public = {
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      linkFlags = [ rustLibPath ];
    };
  };

  executable = cpp.mkExecutable {
    name = "rust-crane-integration";
    inherit root includeDirs sources;
    libraries = [ rustLibrary ];
  };

in {
  rustCraneInterop = executable;
}
