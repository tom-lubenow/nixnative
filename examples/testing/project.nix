{ pkgs, native }:

let
  # Basic app for testing
  app = native.executable {
    name = "test-app";
    root = ./.;
    sources = [ "main.cc" ];
  };

  # LTO build
  appLto = native.executable {
    name = "test-app-lto";
    root = ./.;
    sources = [ "main.cc" ];
    compileFlags = [ "-flto=thin" ];
    linkFlags = [ "-flto=thin" ];
  };

  # Minimal config build
  appMinimal = native.executable {
    name = "test-app-minimal";
    root = ./.;
    sources = [ "main.cc" ];
    includeDirs = [ ];
    defines = [ ];
    compileFlags = [ ];
    libraries = [ ];
    tools = [ ];
  };

  # ASan build (Linux only)
  appAsan = native.executable {
    name = "test-app-asan";
    root = ./.;
    sources = [ "main.cc" ];
    compileFlags = [ "-fsanitize=address,undefined" ];
    linkFlags = [ "-fsanitize=address,undefined" ];
  };

in {
  inherit app appLto appMinimal;
  testingExample = app;
} // (if pkgs.stdenv.hostPlatform.isLinux then {
  inherit appAsan;
} else {})
