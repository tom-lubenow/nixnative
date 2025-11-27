# Protobuf tool plugin for nixnative
#
# Generates C++ code from .proto files using protoc.
#
{ pkgs, lib, mkTool }:

let
  inherit (lib) concatStringsSep concatMapStrings removeSuffix hasSuffix;

  # Get proto file base name without extension
  protoBaseName = file:
    let
      name = if builtins.isAttrs file && file ? rel then file.rel else file;
    in
    removeSuffix ".proto" name;

  # Protobuf transformation
  protobufTransform = { inputFiles, root, config }:
    let
      protoPath = config.protoPath or ".";
      cppOut = config.cppOut or ".";
      extraArgs = config.extraArgs or [];

      # Convert input files to paths
      protoFiles = map (f:
        if builtins.isAttrs f && f ? rel then f.rel
        else if builtins.isString f then f
        else throw "nixnative/protobuf: input files must be strings or attrsets with 'rel'"
      ) inputFiles;

      protoFilesStr = concatStringsSep " " protoFiles;
      extraArgsStr = concatStringsSep " " extraArgs;
    in
    pkgs.runCommand "protobuf-gen"
      {
        nativeBuildInputs = [ pkgs.protobuf ];
        src = root;
      }
      ''
        set -euo pipefail
        mkdir -p $out

        cd $src

        # Generate C++ files
        protoc \
          --proto_path=${protoPath} \
          --cpp_out=$out \
          ${extraArgsStr} \
          ${protoFilesStr}
      '';

  # Protobuf output schema
  protobufOutputs = { drv, inputFiles, config }:
    let
      # Generate header and source entries for each proto file
      mkOutputs = file:
        let
          base = protoBaseName file;
          # Remove directory components for the output names
          baseName = builtins.baseNameOf base;
        in
        {
          header = {
            rel = "${baseName}.pb.h";
            store = "${drv}/${baseName}.pb.h";
          };
          source = {
            rel = "${baseName}.pb.cc";
            store = "${drv}/${baseName}.pb.cc";
          };
        };

      outputs = map mkOutputs inputFiles;
    in
    {
      headers = map (o: o.header) outputs;
      sources = map (o: o.source) outputs;
      includeDirs = [ { path = drv; } ];
      manifest = {
        schema = 1;
        units = builtins.listToAttrs (map (o: {
          name = o.source.rel;
          value = {
            dependencies = [ o.header.rel ];
          };
        }) outputs);
      };
      defines = [];
      cxxFlags = [];
      linkFlags = [];
    };

in rec {
  # ==========================================================================
  # Protobuf Tool
  # ==========================================================================

  protobuf = mkTool {
    name = "protobuf";

    transform = protobufTransform;
    outputs = protobufOutputs;

    # Link against protobuf runtime
    dependencies = [
      "-l${pkgs.protobuf.lib}/lib/libprotobuf${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}"
    ];

    defaultConfig = {
      protoPath = ".";
      cppOut = ".";
      extraArgs = [];
    };
  };

  # ==========================================================================
  # Convenience: Run protobuf directly
  # ==========================================================================

  # Helper to run protobuf on a list of .proto files
  generate = { inputFiles, root ? ./., config ? {} }:
    protobuf.run { inherit inputFiles root config; };

  # ==========================================================================
  # gRPC Extension
  # ==========================================================================

  # Protobuf with gRPC plugin
  grpc = mkTool {
    name = "grpc";

    transform = { inputFiles, root, config }:
      let
        protoPath = config.protoPath or ".";
        extraArgs = config.extraArgs or [];

        protoFiles = map (f:
          if builtins.isAttrs f && f ? rel then f.rel
          else if builtins.isString f then f
          else throw "nixnative/grpc: input files must be strings or attrsets with 'rel'"
        ) inputFiles;

        protoFilesStr = concatStringsSep " " protoFiles;
        extraArgsStr = concatStringsSep " " extraArgs;
      in
      pkgs.runCommand "grpc-gen"
        {
          nativeBuildInputs = [ pkgs.protobuf pkgs.grpc ];
          src = root;
        }
        ''
          set -euo pipefail
          mkdir -p $out

          cd $src

          # Generate C++ files
          protoc \
            --proto_path=${protoPath} \
            --cpp_out=$out \
            --grpc_out=$out \
            --plugin=protoc-gen-grpc=${pkgs.grpc}/bin/grpc_cpp_plugin \
            ${extraArgsStr} \
            ${protoFilesStr}
        '';

    outputs = { drv, inputFiles, config }:
      let
        mkOutputs = file:
          let
            base = protoBaseName file;
            baseName = builtins.baseNameOf base;
          in
          {
            pbHeader = { rel = "${baseName}.pb.h"; store = "${drv}/${baseName}.pb.h"; };
            pbSource = { rel = "${baseName}.pb.cc"; store = "${drv}/${baseName}.pb.cc"; };
            grpcHeader = { rel = "${baseName}.grpc.pb.h"; store = "${drv}/${baseName}.grpc.pb.h"; };
            grpcSource = { rel = "${baseName}.grpc.pb.cc"; store = "${drv}/${baseName}.grpc.pb.cc"; };
          };

        outputs = map mkOutputs inputFiles;
      in
      {
        headers = (map (o: o.pbHeader) outputs) ++ (map (o: o.grpcHeader) outputs);
        sources = (map (o: o.pbSource) outputs) ++ (map (o: o.grpcSource) outputs);
        includeDirs = [ { path = drv; } ];
        manifest = { schema = 1; units = {}; };
        defines = [];
        cxxFlags = [];
        linkFlags = [];
      };

    dependencies = [
      "-lprotobuf"
      "-lgrpc++"
    ];

    defaultConfig = {
      protoPath = ".";
      extraArgs = [];
    };
  };
}
