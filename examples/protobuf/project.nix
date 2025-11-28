{ pkgs, native }:

let
  # Generate C++ from proto files
  protoGen = native.tools.protobuf.run {
    inputFiles = [ "message.proto" ];
    root = ./.;
  };

  # Protobuf runtime library
  protobufLib = native.pkgConfig.makeLibrary {
    name = "protobuf";
    packages = [ pkgs.protobuf ];
  };

  # Build executable
  app = native.executable {
    name = "protobuf-example";
    root = ./.;
    sources = [ "main.cc" ];
    tools = [ protoGen ];
    libraries = [ protobufLib ];
  };

in {
  inherit app;
  protobufExample = app;
}
