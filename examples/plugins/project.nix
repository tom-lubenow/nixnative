{ pkgs, native }:

let
  # Header-only library for plugin interface
  commonLib = native.headerOnly {
    name = "plugin-interface";
    publicIncludeDirs = [ ./common ];
  };

  # Plugin shared library
  myPlugin = native.sharedLib {
    name = "my-plugin";
    root = ./.;
    sources = [ "plugin/plugin.cc" ];
    libraries = [ commonLib ];
  };

  # Host application
  hostApp = native.executable {
    name = "host-app";
    root = ./.;
    sources = [ "host/main.cc" ];
    libraries = [ commonLib ];
    linkFlags = if pkgs.stdenv.isLinux then [ "-ldl" ] else [ ];
  };

in {
  inherit myPlugin hostApp commonLib;
  # With dynamic derivations, we can't create a runScript that references
  # placeholder paths at evaluation time. The hostApp and myPlugin are
  # available as separate packages that can be built and tested.
  pluginsExample = hostApp;
}
