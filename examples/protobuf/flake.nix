{
  description = "Protobuf example for nixnative";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };

          # Import protobuf generator (tool plugin)
          mkProtobuf = import ../../nix/generators/protobuf.nix { inherit pkgs; };

          protoGen = mkProtobuf {
            protos = [ "message.proto" ];
            root = ./.;
          };

          # We need the protobuf library for linking
          protobufLib = native.pkgConfig.makeLibrary {
            name = "protobuf";
            packages = [ pkgs.protobuf ];
          };

        in
        {
          default = native.executable {
            name = "protobuf-example";
            root = ./.;
            sources = [ "main.cc" ];
            tools = [ protoGen ];
            libraries = [ protobufLib ];
          };
        }
      );
    };
}
