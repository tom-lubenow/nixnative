{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          mixedApp = {
            type = "executable";
            name = "mixed-app";
            sources = [
              "clib.c"
              "main.cc"
            ];
            includeDirs = [ "include" ];
          };

          cLib = {
            type = "staticLib";
            name = "libclib";
            sources = [ "clib.c" ];
            includeDirs = [ "include" ];
            publicIncludeDirs = [ "include" ];
          };

          cppApp = {
            type = "executable";
            name = "cpp-app";
            sources = [ "main.cc" ];
            includeDirs = [ "include" ];
            libraries = [ { target = "cLib"; } ];
          };
        };

        tests = {
          mixedApp = {
            executable = "mixedApp";
            expectedOutput = "Mixed C/C++ working correctly!";
          };

          cppApp = {
            executable = "cppApp";
            expectedOutput = "Mixed C/C++ working correctly!";
          };
        };
      };
    }
  ];
}
