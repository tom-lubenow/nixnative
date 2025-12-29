{ pkgs, native }:

let
  # Static library (objects for internal use)
  staticLibObjects = native.staticLib {
    name = "mylib-static";
    root = ./.;
    sources = [ "lib.cc" ];
    includeDirs = [ ./. ];  # For own compilation
    publicIncludeDirs = [ ./. ];  # For consumers
  };

  # Static archive for installation/external distribution
  staticLib = native.archive { lib = staticLibObjects; };

  # Shared library
  sharedLib = native.sharedLib {
    name = "mylib-shared";
    root = ./.;
    sources = [ "lib.cc" ];
    includeDirs = [ ./. ];  # For own compilation
    publicIncludeDirs = [ ./. ];  # For consumers
  };

in {
  inherit staticLib sharedLib;
  installExample = staticLib;
}
