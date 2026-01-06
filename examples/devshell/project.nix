{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets.app = {
          type = "executable";
          name = "devshell-app";
          sources = [ "main.cc" ];
        };

        tests.devshell = {
          executable = "app";
        };

        extraPackages = {
          devshellExample = { target = "app"; };
        };
      };
    }
  ];
}
