{
  description = "Dynamic Plugin System example for nixclang";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixclang.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixclang }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          cpp = nixclang.lib.cpp { inherit pkgs; };
          
          # Common interface library (header-only)
          commonLib = cpp.mkHeaderOnly {
            name = "plugin-interface";
            includeDirs = [ ./common ];
          };

          # The Plugin (Shared Library)
          myPlugin = cpp.mkSharedLib {
            name = "my-plugin";
            root = ./.;
            sources = [ "plugin/plugin.cc" ];
            libraries = [ commonLib ];
          };

          # The Host Application
          hostApp = cpp.mkExecutable {
            name = "host-app";
            root = ./.;
            sources = [ "host/main.cc" ];
            libraries = [ commonLib ];
            # We need to link against dl for dlopen
            ldflags = if pkgs.stdenv.isLinux then [ "-ldl" ] else [ ];
          };
          
          # Wrapper script to run the host with the plugin
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
