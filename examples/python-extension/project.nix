{ pkgs, cpp }:

let
  root = ./.;
  sources = [ "src/hello_ext.cc" ];
  python = pkgs.python3;

  extension = cpp.mkPythonExtension {
    name = "hello_ext";
    inherit root sources;
    inherit python;
  };

in {
  pythonExtension = extension;
}
