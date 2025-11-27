# Dynamic Plugin System example for nixnative
#
# Demonstrates building a plugin system with shared libraries (dlopen/dlsym).

{
  description = "Dynamic Plugin System example for nixnative";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };

          # Header-only library defining the plugin interface
          #
          # Both the host application and plugins include this header to share
          # the Plugin base class and CreatePluginFunc type.
          commonLib = native.headerOnly {
            name = "plugin-interface";
            includeDirs = [ ./common ];
          };

          # Plugin: a shared library that implements the Plugin interface
          #
          # Exports a C-linkage factory function: Plugin* createPlugin()
          # The host loads this via dlopen/dlsym at runtime.
          myPlugin = native.sharedLib {
            name = "my-plugin";
            root = ./.;
            sources = [ "plugin/plugin.cc" ];
            libraries = [ commonLib ];
          };

          # Host application that loads plugins at runtime
          #
          # Uses dlopen to load the plugin .so/.dylib and dlsym to find
          # the createPlugin factory function.
          hostApp = native.executable {
            name = "host-app";
            root = ./.;
            sources = [ "host/main.cc" ];
            libraries = [ commonLib ];
            # Linux requires -ldl for dlopen/dlsym; macOS has them in libc
            ldflags = if pkgs.stdenv.isLinux then [ "-ldl" ] else [ ];
          };

          # Wrapper script that runs the host with the plugin
          runScript = pkgs.writeShellScriptBin "run-plugin-example" ''
            ${hostApp}/bin/host-app ${myPlugin.sharedLibrary}
          '';

        in
        {
          inherit hostApp myPlugin;
          default = runScript;
        }
      );
    };
}
