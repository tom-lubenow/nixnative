{ pkgs, cpp }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" "src/hello.cc" ];

  executable = cpp.mkExecutable {
    name = "executable-example";
    inherit root sources includeDirs;
    depsManifest = ./deps.json;
  };

in {
  executableExample = executable;
}
