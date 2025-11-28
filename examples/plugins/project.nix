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
    ldflags = if pkgs.stdenv.isLinux then [ "-ldl" ] else [ ];
  };

  # Wrapper script that runs host with plugin
  runScript = pkgs.writeShellScriptBin "run-plugin-example" ''
    ${hostApp}/bin/host-app ${myPlugin.sharedLibrary}
  '';

in {
  inherit myPlugin hostApp runScript;
  pluginsExample = runScript;
}
