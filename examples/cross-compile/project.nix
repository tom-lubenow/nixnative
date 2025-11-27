{ pkgs, native }:

let
  sources = [ "src/main.cc" ];

  # Native build
  nativeApp = native.executable {
    name = "cross-example-native";
    root = ./.;
    inherit sources;
  };

in {
  inherit nativeApp;
  crossCompileExample = nativeApp;
}
