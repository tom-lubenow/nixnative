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

  # macOS frameworks (if on Darwin)
  frameworkLibs =
    if pkgs.stdenv.isDarwin then [
      (native.pkgConfig.mkFrameworkLibrary { name = "CoreFoundation"; })
      (native.pkgConfig.mkFrameworkLibrary { name = "Security"; })
    ]
    else [];

  # Demo app
  demo = native.executable {
    name = "pkgconfig-demo";
    root = ./.;
    sources = [ "main.cc" ];
    libraries = [ zlibLib curlLib ] ++ frameworkLibs;
  };

in {
  inherit zlibLib curlLib demo;
  pkgConfigExample = demo;
}
