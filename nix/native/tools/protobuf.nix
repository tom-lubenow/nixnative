# Protobuf tool plugin for nixnative
#
# Generates C++ code from .proto files using protoc.
#
{
  pkgs,
  lib,
  mkTool,
}:

let
  inherit (lib)
    concatStringsSep
    removeSuffix
    hasPrefix
    escapeShellArg
    ;

  # Get proto file base name without extension
  protoBaseName =
    file:
    let
      name = if builtins.isAttrs file && file ? rel then file.rel else file;
    in
    removeSuffix ".proto" name;

  normalizeRel =
    rel:
    if hasPrefix "./" rel then
      builtins.substring 2 ((builtins.stringLength rel) - 2) rel
    else
      rel;

  normalizeOutDir =
    outDir:
    let
      stripped = normalizeRel outDir;
      noTrailing = removeSuffix "/" stripped;
    in
    if noTrailing == "." then "" else noTrailing;

  # Protobuf transformation
  protobufTransform =
    {
      inputFiles,
      root,
      config,
    }:
    let
      protoPath = config.protoPath or ".";
      cppOut = config.cppOut or ".";
      extraArgs = config.extraArgs or [ ];
      cppOutDir = normalizeOutDir cppOut;

      # Convert input files to paths
      protoFiles = map (
        f:
        if builtins.isAttrs f && f ? rel then
          normalizeRel f.rel
        else if builtins.isString f then
          normalizeRel f
        else
          throw "nixnative/protobuf: input files must be strings or attrsets with 'rel'"
      ) inputFiles;

      protoFilesArgs = concatStringsSep " " (map escapeShellArg protoFiles);
      extraArgsArgs = concatStringsSep " " (map escapeShellArg extraArgs);
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
        cpp_out_dir="$out"
        ${lib.optionalString (cppOutDir != "") ''
          cpp_out_dir="$out/${cppOutDir}"
        ''}
        mkdir -p "$cpp_out_dir"

        # Generate C++ files
        protoc \
          --proto_path=${escapeShellArg protoPath} \
          --cpp_out="$cpp_out_dir" \
          ${extraArgsArgs} \
          ${protoFilesArgs}
      '';

  # Protobuf output schema
  protobufOutputs =
    {
      drv,
      inputFiles,
      config,
    }:
    let
      cppOutDir = normalizeOutDir (config.cppOut or ".");
      # Generate output entries for each proto file
      mkOutputs =
        file:
        let
          base = normalizeRel (protoBaseName file);
          relBase = if cppOutDir == "" then base else "${cppOutDir}/${base}";
        in
        [
          { rel = "${relBase}.pb.h"; path = "${drv}/${relBase}.pb.h"; }
          { rel = "${relBase}.pb.cc"; path = "${drv}/${relBase}.pb.cc"; }
        ];
      includePath = if cppOutDir == "" then drv else "${drv}/${cppOutDir}";
    in
    {
      outputs = lib.concatMap mkOutputs inputFiles;
      includeDirs = [ { path = includePath; } ];
      defines = [ ];
      compileFlags = [ ];
      linkFlags = [ ];
    };

in
rec {
  # ==========================================================================
  # Protobuf Tool
  # ==========================================================================

  protobuf = mkTool {
    name = "protobuf";

    transform = protobufTransform;
    outputs = protobufOutputs;

    # Link against protobuf runtime
    dependencies = [
      "${pkgs.protobuf}/lib/libprotobuf${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}"
    ];

    defaultConfig = {
      protoPath = ".";
      cppOut = ".";
      extraArgs = [ ];
    };
  };

  # ==========================================================================
  # Convenience: Run protobuf directly
  # ==========================================================================

  # Helper to run protobuf on a list of .proto files
  generate =
    {
      inputFiles,
      root ? ./.,
      config ? { },
    }:
    protobuf.run { inherit inputFiles root config; };

  # ==========================================================================
  # gRPC Extension
  # ==========================================================================

  # Protobuf with gRPC plugin
  grpc = mkTool {
    name = "grpc";

    transform =
      {
        inputFiles,
        root,
        config,
      }:
      let
        protoPath = config.protoPath or ".";
        cppOut = config.cppOut or ".";
        grpcOut = config.grpcOut or cppOut;
        extraArgs = config.extraArgs or [ ];
        cppOutDir = normalizeOutDir cppOut;
        grpcOutDir = normalizeOutDir grpcOut;

        protoFiles = map (
          f:
          if builtins.isAttrs f && f ? rel then
            normalizeRel f.rel
          else if builtins.isString f then
            normalizeRel f
          else
            throw "nixnative/grpc: input files must be strings or attrsets with 'rel'"
        ) inputFiles;

        protoFilesArgs = concatStringsSep " " (map escapeShellArg protoFiles);
        extraArgsArgs = concatStringsSep " " (map escapeShellArg extraArgs);
      in
      pkgs.runCommand "grpc-gen"
        {
          nativeBuildInputs = [
            pkgs.protobuf
            pkgs.grpc
          ];
          src = root;
        }
        ''
          set -euo pipefail
          mkdir -p $out

          cd $src
          cpp_out_dir="$out"
          grpc_out_dir="$out"
          ${lib.optionalString (cppOutDir != "") ''
            cpp_out_dir="$out/${cppOutDir}"
          ''}
          ${lib.optionalString (grpcOutDir != "") ''
            grpc_out_dir="$out/${grpcOutDir}"
          ''}
          mkdir -p "$cpp_out_dir" "$grpc_out_dir"

          # Generate C++ files
          protoc \
            --proto_path=${escapeShellArg protoPath} \
            --cpp_out="$cpp_out_dir" \
            --grpc_out="$grpc_out_dir" \
            --plugin=protoc-gen-grpc=${pkgs.grpc}/bin/grpc_cpp_plugin \
            ${extraArgsArgs} \
            ${protoFilesArgs}
        '';

    outputs =
      {
        drv,
        inputFiles,
        config,
      }:
      let
        cppOutDir = normalizeOutDir (config.cppOut or ".");
        grpcOutDir = normalizeOutDir (config.grpcOut or (config.cppOut or "."));
        mkOutputs =
          file:
          let
            base = normalizeRel (protoBaseName file);
            cppRelBase = if cppOutDir == "" then base else "${cppOutDir}/${base}";
            grpcRelBase = if grpcOutDir == "" then base else "${grpcOutDir}/${base}";
          in
          [
            { rel = "${cppRelBase}.pb.h"; path = "${drv}/${cppRelBase}.pb.h"; }
            { rel = "${cppRelBase}.pb.cc"; path = "${drv}/${cppRelBase}.pb.cc"; }
            { rel = "${grpcRelBase}.grpc.pb.h"; path = "${drv}/${grpcRelBase}.grpc.pb.h"; }
            { rel = "${grpcRelBase}.grpc.pb.cc"; path = "${drv}/${grpcRelBase}.grpc.pb.cc"; }
          ];
        includeDirs =
          map
            (path: { inherit path; })
            (
              lib.unique (
                map
                  (d: if d == "" then drv else "${drv}/${d}")
                  [
                    cppOutDir
                    grpcOutDir
                  ]
              )
            );
      in
      {
        outputs = lib.concatMap mkOutputs inputFiles;
        inherit includeDirs;
        defines = [ ];
        compileFlags = [ ];
        linkFlags = [ ];
      };

    dependencies = [
      "-lprotobuf"
      "-lgrpc++"
    ];

    defaultConfig = {
      protoPath = ".";
      cppOut = ".";
      grpcOut = ".";
      extraArgs = [ ];
    };
  };
}
