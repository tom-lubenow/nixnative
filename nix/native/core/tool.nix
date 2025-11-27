# Tool plugin interface for nixnative
#
# Tools generate code (headers, sources) that integrate into the build.
# Examples: protobuf, flatbuffers, jinja templates, etc.
#
{ lib }:

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
  # - public: Public interface (defines, cxxFlags, linkFlags)
  #
  mkTool =
    { name                    # Tool identifier: "protobuf", "jinja"

    # The transformation function
    # Takes: { inputFiles, config, root } -> derivation
    , transform

    # Output schema function
    # Takes: { drv, inputFiles, config } -> { headers, sources, includeDirs, manifest, public }
    , outputs ? defaultOutputs

    # Runtime dependencies (libraries to link)
    , dependencies ? []

    # Default configuration
    , defaultConfig ? {}
    }:
    {
      inherit name transform outputs dependencies defaultConfig;

      # =======================================================================
      # Methods
      # =======================================================================

      # Run the tool with input files
      run = { inputFiles, root ? ./., config ? {} }:
        let
          mergedConfig = defaultConfig // config;

          # Run the transformation
          drv = transform {
            inherit inputFiles root;
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
          headers = outputInfo.headers or [];
          sources = outputInfo.sources or [];

          # Include directories for generated headers
          includeDirs = outputInfo.includeDirs or [ { path = drv; } ];

          # Dependency manifest for generated files
          manifest = outputInfo.manifest or { schema = 1; units = {}; };

          # Public interface for consumers
          public = {
            includeDirs = outputInfo.includeDirs or [ { path = drv; } ];
            defines = outputInfo.defines or [];
            cxxFlags = outputInfo.cxxFlags or [];
            linkFlags = (outputInfo.linkFlags or [])
              ++ (map (dep: if builtins.isString dep then dep else dep.linkFlags or []) dependencies);
          };

          # Evaluation inputs (for Nix to track)
          evalInputs = [ drv ];
        };
    };

  # ==========================================================================
  # Default Output Schema
  # ==========================================================================

  # Default outputs function - uses convention-based discovery
  defaultOutputs = { drv, inputFiles, config }:
    {
      headers = [];
      sources = [];
      includeDirs = [ { path = drv; } ];
      manifest = { schema = 1; units = {}; };
      defines = [];
      cxxFlags = [];
      linkFlags = [];
    };

  # ==========================================================================
  # Tool Helpers
  # ==========================================================================

  # Create a header output entry
  mkHeader = { rel, store }:
    { inherit rel store; };

  # Create a source output entry
  mkSource = { rel, store }:
    { inherit rel store; };

  # Create include directory entry
  mkIncludeDir = path:
    if builtins.isString path then { inherit path; }
    else if builtins.isPath path then { path = builtins.toString path; }
    else if builtins.isAttrs path && path ? path then path
    else if builtins.isAttrs path && path ? outPath then { path = path.outPath; }
    else throw "nixnative: mkIncludeDir expects a path or attrset with 'path'";

  # ==========================================================================
  # Validation
  # ==========================================================================

  validateTool = tool:
    let
      required = [ "name" "transform" ];
      missing = builtins.filter (f: !(tool ? ${f})) required;
    in
    if missing != []
    then throw "nixnative: tool missing required fields: ${lib.concatStringsSep ", " missing}"
    else tool;

  # Validate tool run output
  validateToolOutput = output:
    let
      required = [ "drv" "name" ];
      missing = builtins.filter (f: !(output ? ${f})) required;
    in
    if missing != []
    then throw "nixnative: tool output missing required fields: ${lib.concatStringsSep ", " missing}"
    else output;
}
