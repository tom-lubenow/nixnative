{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          vec3Lib = {
            type = "headerOnly";
            name = "vec3";
            publicIncludeDirs = [ ./include ];
          };

          testApp = {
            type = "executable";
            name = "header-only-test";
            sources = [ "main.cc" ];
            libraries = [ { target = "vec3Lib"; } ];
          };
        };

        tests.headerOnly = {
          executable = "testApp";
          expectedOutput = "a + b = (5, 7, 9)";
        };

        extraPackages = {
          headerOnlyExample = { target = "testApp"; };
        };
      };
    }
  ];
}
