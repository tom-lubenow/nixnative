{ pkgs, cpp }:

let
  root = ./.;
  python = pkgs.python3;

  extension = cpp.mkPythonExtension {
    name = "hello_ext";
    inherit root python;
    sources = [ "src/hello_ext.cc" ];
  };

in {
  pythonExtension = extension;
}
