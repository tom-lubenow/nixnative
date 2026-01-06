{ pkgs, native }:

let
  linkFlags = if pkgs.stdenv.isLinux then [ "-ldl" ] else [ ];

in
native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          commonLib = {
            type = "headerOnly";
            name = "plugin-interface";
            publicIncludeDirs = [ ./common ];
          };

          myPlugin = {
            type = "sharedLib";
            name = "my-plugin";
            sources = [ "plugin/plugin.cc" ];
            libraries = [ { target = "commonLib"; } ];
          };

          hostApp = {
            type = "executable";
            name = "host-app";
            sources = [ "host/main.cc" ];
            libraries = [ { target = "commonLib"; } ];
            inherit linkFlags;
          };
        };

        extraChecks = {
          pluginsHostBuilds = { target = "hostApp"; };
          pluginsPluginBuilds = { target = "myPlugin"; };
        };
      };
    }
  ];
}
