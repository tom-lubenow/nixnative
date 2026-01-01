# Tool plugin interface for nixnative
#
# Tools generate code (headers, sources) that integrate into the build.
# Examples: protobuf, flatbuffers, jinja templates, etc.
#
# IMPORTANT FOR INCREMENTAL BUILDS:
# The tool infrastructure automatically captures only the specified input files
# (not the entire root directory) to ensure changes to unrelated files don't
# invalidate the tool's output. This is critical for achieving true per-file
# incremental compilation.
#
{
  pkgs,
  lib,
  utils,
}:

rec {
  # ==========================================================================
  # Tool Factory
  # ==========================================================================

  # Create a tool plugin
  #
  # A tool takes input files and produces:
  # - headers: Generated header files
  # - sources: Generated source files
  # - includeDirs: Include paths for generated headers
  # - manifest: Dependency manifest for generated files
  # - public: Public interface (defines, compileFlags, linkFlags)
  #
  mkTool =
    {
      name, # Tool identifier: "protobuf", "jinja"

      # The transformation function
      # Takes: { inputFiles, config, root } -> derivation
      transform,

      # Output schema function
      # Takes: { drv, inputFiles, config } -> { headers, sources, includeDirs, manifest, public }
      outputs ? defaultOutputs,

      # Runtime dependencies (libraries to link)
      dependencies ? [ ],

      # Default configuration
      defaultConfig ? { },
    }:
    {
      inherit
        name
        transform
        outputs
        dependencies
        defaultConfig
        ;

      # =======================================================================
      # Methods
      # =======================================================================

      # Run the tool with input files
      #
      # IMPORTANT: For incremental builds, the tool automatically captures only
      # the specified input files rather than the entire root directory. This
      # ensures that changes to other files in the project don't invalidate
      # the tool's output.
      #
      run =
        {
          inputFiles,
          root ? ./.,
          config ? { },
        }:
        let
          mergedConfig = defaultConfig // config;

          # Normalize input file paths to strings
          normalizedFiles = map (
            f:
            if builtins.isAttrs f && f ? rel then
              f.rel
            else if builtins.isString f then
              f
            else
              throw "nixnative/tool: input files must be strings or attrsets with 'rel'"
          ) inputFiles;

          # Capture only the input files, not the entire root directory.
          # This is CRITICAL for incremental builds: changes to files not in
          # inputFiles will not invalidate this derivation.
          capturedRoot = utils.captureFiles {
            inherit root;
            files = normalizedFiles;
            name = "${name}-inputs";
          };

          # Run the transformation with the captured (minimal) root
          drv = transform {
            inherit inputFiles;
            root = capturedRoot;
            config = mergedConfig;
          };

          # Get structured outputs
          outputInfo = outputs {
            inherit drv inputFiles;
            config = mergedConfig;
          };
        in
        {
          inherit drv name;

          # Generated files
          headers = outputInfo.headers or [ ];
          sources = outputInfo.sources or [ ];

          # Include directories for generated headers
          includeDirs = outputInfo.includeDirs or [ { path = drv; } ];

          # Dependency manifest for generated files
          manifest =
            outputInfo.manifest or {
              schema = 1;
              units = { };
            };

          # Public interface for consumers
          public = {
            includeDirs = outputInfo.includeDirs or [ { path = drv; } ];
            defines = outputInfo.defines or [ ];
            compileFlags = outputInfo.compileFlags or [ ];
            linkFlags =
              (outputInfo.linkFlags or [ ])
              ++ (map (dep: if builtins.isString dep then dep else dep.linkFlags or [ ]) dependencies);
          };

          # Evaluation inputs (for Nix to track)
          evalInputs = [ drv ];
        };
    };

  # ==========================================================================
  # Default Output Schema
  # ==========================================================================

  # Default outputs function - uses convention-based discovery
  defaultOutputs =
    {
      drv,
      inputFiles,
      config,
    }:
    {
      headers = [ ];
      sources = [ ];
      includeDirs = [ { path = drv; } ];
      manifest = {
        schema = 1;
        units = { };
      };
      defines = [ ];
      compileFlags = [ ];
      linkFlags = [ ];
    };

  # ==========================================================================
  # Tool Helpers
  # ==========================================================================

  # Create a header output entry
  mkHeader =
    { rel, store }:
    {
      inherit rel store;
    };

  # Create a source output entry
  mkSource =
    { rel, store }:
    {
      inherit rel store;
    };

  # Create include directory entry
  mkIncludeDir =
    path:
    if builtins.isString path then
      { inherit path; }
    else if builtins.isPath path then
      { path = builtins.toString path; }
    else if builtins.isAttrs path && path ? path then
      path
    else if builtins.isAttrs path && path ? outPath then
      { path = path.outPath; }
    else
      throw "nixnative: mkIncludeDir expects a path or attrset with 'path'";

  # ==========================================================================
  # Validation
  # ==========================================================================

  validateTool =
    tool:
    let
      required = [
        "name"
        "transform"
      ];
      missing = builtins.filter (f: !(tool ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: tool missing required fields: ${lib.concatStringsSep ", " missing}"
    else
      tool;

  # Validate tool run output
  validateToolOutput =
    output:
    let
      required = [
        "drv"
        "name"
      ];
      missing = builtins.filter (f: !(output ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: tool output missing required fields: ${lib.concatStringsSep ", " missing}"
    else
      output;

  # ==========================================================================
  # Simplified Tool API
  # ==========================================================================

  # Create a tool from a pre-built derivation
  #
  # This is the simple API for when you already have a derivation that
  # produces generated code and just want to integrate it into the build.
  #
  # Usage:
  #   versionTool = native.mkGeneratedSources {
  #     name = "version-header";
  #     drv = pkgs.runCommand "gen-version" {} ''
  #       mkdir -p $out
  #       echo '#define VERSION "1.0.0"' > $out/version.h
  #     '';
  #     headers = [ "version.h" ];
  #   };
  #
  #   protobufTool = native.mkGeneratedSources {
  #     name = "proto-gen";
  #     drv = myProtobufDerivation;
  #     headers = [ "foo.pb.h" "bar.pb.h" ];
  #     sources = [ "foo.pb.cc" "bar.pb.cc" ];
  #     includeDir = "proto";  # Subdirectory within drv for includes
  #   };
  #
  mkGeneratedSources =
    {
      name,
      drv,
      # Files within drv
      headers ? [],
      sources ? [],
      # Where to look for includes (subdirectory within drv, or null for drv root)
      includeDir ? null,
      # Additional public interface
      defines ? [],
      compileFlags ? [],
      linkFlags ? [],
    }:
    let
      # Determine the include directory path
      includePath = if includeDir != null
        then "${drv}/${includeDir}"
        else "${drv}";

      # Convert relative file paths to source entries
      mkSourceEntry = rel: {
        inherit rel;
        store = "${drv}/${rel}";
      };

      headerEntries = map mkSourceEntry headers;
      sourceEntries = map mkSourceEntry sources;
    in
    {
      inherit drv name;

      # Generated files
      headers = headerEntries;
      sources = sourceEntries;

      # Include directories for generated headers
      includeDirs = [ { path = includePath; } ];

      # Dependency manifest (empty - no deps tracking for pre-built)
      manifest = {
        schema = 1;
        units = {};
      };

      # Public interface for consumers
      public = {
        includeDirs = [ { path = includePath; } ];
        inherit defines compileFlags linkFlags;
      };

      # Evaluation inputs (for Nix to track)
      evalInputs = [ drv ];
    };
}
