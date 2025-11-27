{ pkgs, native }:

let
  # Generate gRPC code
  grpcGen = native.tools.grpc.run {
    inputFiles = [ "proto/greeter.proto" ];
    root = ./.;
    config = {
      protoPath = "proto";
    };
  };

  # Protobuf runtime
  protobufLib = native.pkgConfig.makeLibrary {
    name = "protobuf";
    packages = [ pkgs.protobuf ];
  };

  # gRPC C++ library
  grpcLib = native.pkgConfig.makeLibrary {
    name = "grpc++";
    packages = [ pkgs.grpc ];
    modules = [ "grpc++" ];
  };

  allLibs = [ protobufLib grpcLib ];

  # Server
  server = native.executable {
    name = "greeter-server";
    root = ./.;
    sources = [ "server/main.cc" ];
    tools = [ grpcGen ];
    libraries = allLibs;
    flags = [ { type = "standard"; value = "c++17"; } ];
  };

  # Client
  client = native.executable {
    name = "greeter-client";
    root = ./.;
    sources = [ "client/main.cc" ];
    tools = [ grpcGen ];
    libraries = allLibs;
    flags = [ { type = "standard"; value = "c++17"; } ];
  };

  # Combined
  combined = pkgs.symlinkJoin {
    name = "greeter";
    paths = [ server client ];
  };

in {
  inherit grpcGen server client combined;
  grpcExample = combined;
}
