{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          libUtil = {
            type = "staticLib";
            name = "libutil";
            sources = [ "libutil/util.cc" ];
            includeDirs = [ "libutil/include" ];
            publicIncludeDirs = [ "libutil/include" ];
          };

          libCore = {
            type = "staticLib";
            name = "libcore";
            sources = [ "libcore/core.cc" ];
            includeDirs = [ "libcore/include" ];
            publicIncludeDirs = [ "libcore/include" ];
            libraries = [ { target = "libUtil"; } ];
          };

          libMathExt = {
            type = "staticLib";
            name = "libmath_ext";
            sources = [ "libmath/math_ext.cc" ];
            includeDirs = [ "libmath/include" ];
            publicIncludeDirs = [ "libmath/include" ];
            libraries = [ { target = "libCore"; } ];
          };

          app = {
            type = "executable";
            name = "library-chain-app";
            sources = [ "main.cc" ];
            libraries = [ { target = "libMathExt"; } ];
          };
        };

        tests.libraryChain = {
          executable = "app";
          expectedOutput = "Library chain working";
        };
      };
    }
  ];
}
