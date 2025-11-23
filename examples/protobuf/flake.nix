{
  description = "Protobuf example for nixclang";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixclang.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixclang }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          cpp = nixclang.lib.cpp { inherit pkgs; };
          
          # Import our generator
          mkProtobuf = import ../../nix/generators/protobuf.nix { inherit pkgs; };
          
          protoGen = mkProtobuf {
            protos = [ "message.proto" ];
            root = ./.;
          };
          
          # We need the protobuf library for linking
          protobufLib = cpp.pkgConfig.makeLibrary {
            name = "protobuf";
            packages = [ pkgs.protobuf ];
          };

        in
        {
          default = cpp.mkExecutable {
            name = "protobuf-example";
            root = ./.;
            sources = [ "main.cc" ];
            generators = [ protoGen ];
            libraries = [ protobufLib ];
          };
        }
      );
    };
}
