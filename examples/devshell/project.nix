{ pkgs, native }:

let
  # Build target for clangd
  app = native.executable {
    name = "devshell-app";
    root = ./.;
    sources = [ "main.cc" ];
  };

  # clangd configuration
  clangd = native.lsps.clangd {
    targets = [ app ];
  };

in {
  inherit app;
  devshellExample = app;
}
