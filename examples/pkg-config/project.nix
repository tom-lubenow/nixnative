{ pkgs, native }:

let
  # zlib library
  zlibLib = native.pkgConfig.makeLibrary {
    name = "zlib";
    packages = [ pkgs.zlib ];
  };

  # curl library
  curlLib = native.pkgConfig.makeLibrary {
    name = "curl";
    packages = [ pkgs.curl ];
    modules = [ "libcurl" ];
  };

  # Demo app
  demo = native.executable {
    name = "pkgconfig-demo";
    root = ./.;
    sources = [ "main.cc" ];
    libraries = [ zlibLib curlLib ];
  };

in {
  inherit demo;
  pkgConfigExample = demo;
}
