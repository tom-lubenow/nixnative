# project.nix - Build definition for the testing example
#
# Demonstrates testing configurations with explicit LTO/sanitizer flags and args.

{ pkgs, native }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  proj = native.project {
    root = ./.;
  };

  app = proj.executable {
    name = "test-app";
    sources = [ "main.cc" ];
  };

  appLto = proj.executable {
    name = "test-app-lto";
    sources = [ "main.cc" ];
    compileFlags = [ "-flto=thin" ];
    linkFlags = [ "-flto=thin" ];
  };

  appMinimal = proj.executable {
    name = "test-app-minimal";
    sources = [ "main.cc" ];
    includeDirs = [ ];
    defines = [ ];
    compileFlags = [ ];
    libraries = [ ];
    tools = [ ];
  };

  appAsan = if isLinux then proj.executable {
    name = "test-app-asan";
    sources = [ "main.cc" ];
    compileFlags = [ "-fsanitize=address,undefined" ];
    linkFlags = [ "-fsanitize=address,undefined" ];
  } else null;

  test1 = native.test {
    name = "test-1";
    executable = app;
    expectedOutput = "Hello Test";
  };

  test2 = native.test {
    name = "test-2";
    executable = app;
    args = [ "World" ];
    expectedOutput = "Hello World";
  };

  test3 = native.test {
    name = "test-3";
    executable = app;
    args = [ "it's \"quoted\" & $special" ];
    expectedOutput = "Hello it's \"quoted\" & $special";
  };

  testLto = native.test {
    name = "test-lto";
    executable = appLto;
    expectedOutput = "Hello Test";
  };

  testMinimal = native.test {
    name = "test-minimal";
    executable = appMinimal;
    expectedOutput = "Hello Test";
  };

  testAsan = if isLinux then native.test {
    name = "test-asan";
    executable = appAsan;
    expectedOutput = "Hello Test";
  } else null;

in {
  packages = {
    inherit app appLto appMinimal;
  } // (if isLinux then { inherit appAsan; } else { });

  checks = {
    inherit test1 test2 test3 testLto testMinimal;
  } // (if isLinux then { inherit testAsan; } else { });
}
