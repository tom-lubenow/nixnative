# Protobuf example for nixnative
#
# Demonstrates code generation with Protocol Buffers using the tool plugin system.

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

          # Generate C++ code from .proto files using the built-in tool plugin
          #
          # This creates:
          #   - message.pb.h  (header with message classes)
          #   - message.pb.cc (implementation)
          #
          # The tool plugin captures only the input files, so changes to main.cc
          # won't invalidate the protobuf generation step.
          protoGen = native.tools.protobuf.run {
            inputFiles = [ "message.proto" ];
            root = ./.;
          };

          # Wrap the protobuf runtime library via pkg-config
          #
          # This extracts include paths and link flags automatically.
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

            # Tool plugins generate code that's compiled into the target
            tools = [ protoGen ];

            # The protobuf runtime library for linking
            libraries = [ protobufLib ];
          };
        }
      );
    };
}
