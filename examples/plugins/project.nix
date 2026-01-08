# project.nix - Build definition for the plugins example
#
# Demonstrates a plugin system with a header-only interface,
# shared library plugin, and host application.

{ pkgs, native }:

let
  linkFlags = if pkgs.stdenv.isLinux then [ "-ldl" ] else [ ];

  proj = native.project {
    root = ./.;
  };

  commonLib = proj.headerOnly {
    name = "plugin-interface";
    publicIncludeDirs = [ ./common ];
  };

  myPlugin = proj.sharedLib {
    name = "my-plugin";
    sources = [ "plugin/plugin.cc" ];
    libraries = [ commonLib ];
  };

  hostApp = proj.executable {
    name = "host-app";
    sources = [ "host/main.cc" ];
    libraries = [ commonLib ];
    inherit linkFlags;
  };

in {
  packages = {
    inherit commonLib myPlugin hostApp;
  };

  # Build checks - verify both host and plugin compile
  checks = {
    pluginsHostBuilds = hostApp;
    pluginsPluginBuilds = myPlugin;
  };
}
