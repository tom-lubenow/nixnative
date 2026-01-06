{ pkgs, native }:

let
  zlibLib = native.pkgConfig.makeLibrary {
    name = "zlib";
    packages = [ pkgs.zlib ];
  };

  curlLib = native.pkgConfig.makeLibrary {
    name = "curl";
    packages = [ pkgs.curl ];
    modules = [ "libcurl" ];
  };

in
native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets.demo = {
          type = "executable";
          name = "pkgconfig-demo";
          sources = [ "main.cc" ];
          libraries = [ zlibLib curlLib ];
        };

        tests.pkgConfig = {
          executable = "demo";
          expectedOutput = "All libraries working correctly!";
        };
      };
    }
  ];
}
