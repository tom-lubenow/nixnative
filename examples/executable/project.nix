{ pkgs, native }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" "src/hello.cc" ];

  # Using high-level API (defaults to clang + platform linker)
  executable = native.executable {
    name = "executable-example";
    inherit root includeDirs sources;
  };

in {
  executableExample = executable;
}
