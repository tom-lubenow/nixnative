{ pkgs, cpp }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" "src/hello.cc" ];

  executable = cpp.mkExecutable {
    name = "executable-example";
    inherit root includeDirs sources;
  };

in {
  executableExample = executable;
}
