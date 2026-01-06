{ pkgs, native }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

in
native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          app = {
            type = "executable";
            name = "test-app";
            sources = [ "main.cc" ];
          };

          appLto = {
            type = "executable";
            name = "test-app-lto";
            sources = [ "main.cc" ];
            compileFlags = [ "-flto=thin" ];
            linkFlags = [ "-flto=thin" ];
          };

          appMinimal = {
            type = "executable";
            name = "test-app-minimal";
            sources = [ "main.cc" ];
            includeDirs = [ ];
            defines = [ ];
            compileFlags = [ ];
            libraries = [ ];
            tools = [ ];
          };
        }
        // (if isLinux then {
          appAsan = {
            type = "executable";
            name = "test-app-asan";
            sources = [ "main.cc" ];
            compileFlags = [ "-fsanitize=address,undefined" ];
            linkFlags = [ "-fsanitize=address,undefined" ];
          };
        } else { });

        tests = {
          test1 = {
            executable = "app";
            expectedOutput = "Hello Test";
          };

          test2 = {
            executable = "app";
            args = [ "World" ];
            expectedOutput = "Hello World";
          };

          test3 = {
            executable = "app";
            args = [ "it's \"quoted\" & $special" ];
            expectedOutput = "Hello it's \"quoted\" & $special";
          };

          testLto = {
            executable = "appLto";
            expectedOutput = "Hello Test";
          };

          testMinimal = {
            executable = "appMinimal";
            expectedOutput = "Hello Test";
          };
        }
        // (if isLinux then {
          testAsan = {
            executable = "appAsan";
            expectedOutput = "Hello Test";
          };
        } else { });
      };
    }
  ];
}
