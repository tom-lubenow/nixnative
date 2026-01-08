# project.nix - Build definition for the pkg-config example
#
# Demonstrates using pkg-config to wrap system libraries (zlib, curl).

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

  proj = native.project {
    root = ./.;
  };

  demo = proj.executable {
    name = "pkgconfig-demo";
    sources = [ "main.cc" ];
    libraries = [ zlibLib curlLib ];
  };

  testPkgConfig = native.test {
    name = "test-pkgconfig";
    executable = demo;
    expectedOutput = "All libraries working correctly!";
  };

in {
  packages = {
    inherit demo;
  };

  checks = {
    inherit testPkgConfig;
  };
}
