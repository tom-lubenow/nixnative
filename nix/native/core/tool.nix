# Tool plugin interface for nixnative
#
# Tools generate outputs (headers, sources, data files) that integrate into the build.
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
  language,
}:

let
  inherit (lib) foldl';
  inherit (utils)
    toPathLike
    emptyPublic
    mergePublic
    showValue
    validatePublic
    ;

in
rec {
  # ==========================================================================
  # Tool Factory
  # ==========================================================================

  # Create a tool plugin
  #
  # A tool takes input files and produces:
  # - outputs: Generated files (categorized by extension at build time)
  # - includeDirs: Include paths for generated headers
  # - public: Public interface (defines, compileFlags, linkFlags)
  #
  mkTool =
    {
      name, # Tool identifier: "protobuf", "jinja"

      # The transformation function
      # Takes: { inputFiles, config, root } -> derivation
      transform,

      # Output schema function
      # Takes: { drv, inputFiles, config } -> { outputs, includeDirs, ... }
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

          # Generated files (generic - categorized by extension at build time)
          outputs = outputInfo.outputs or [ ];

          # Include directories for generated headers
          includeDirs = outputInfo.includeDirs or [ { path = drv; } ];

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
      outputs = [ ];
      includeDirs = [ { path = drv; } ];
      defines = [ ];
      compileFlags = [ ];
      linkFlags = [ ];
    };

  # ==========================================================================
  # Tool Helpers
  # ==========================================================================

  # Create an output entry
  mkOutput =
    { rel, path ? null, store ? null }:
    if path != null then
      { inherit rel path; }
    else if store != null then
      { inherit rel; path = store; }
    else
      throw "nixnative: mkOutput requires either 'path' or 'store'";

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
  #     outputs = [ "version.h" ];
  #   };
  #
  #   protobufTool = native.mkGeneratedSources {
  #     name = "proto-gen";
  #     drv = myProtobufDerivation;
  #     outputs = [ "foo.pb.h" "foo.pb.cc" "bar.pb.h" "bar.pb.cc" ];
  #     includeDir = "proto";  # Subdirectory within drv for includes
  #   };
  #
  mkGeneratedSources =
    {
      name,
      drv,
      # Files within drv (strings are converted to { rel, path } entries)
      outputs ? [],
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

      # Convert relative file paths to output entries
      mkOutputEntry = file:
        if builtins.isString file then
          { rel = file; path = "${drv}/${file}"; }
        else if file ? rel then
          { rel = file.rel; path = file.path or "${drv}/${file.rel}"; }
        else
          throw "nixnative: mkGeneratedSources output must be a string or have 'rel' attribute";

      outputEntries = map mkOutputEntry outputs;
    in
    {
      inherit drv name;

      # Generated files
      outputs = outputEntries;

      # Include directories for generated headers
      includeDirs = [ { path = includePath; } ];

      # Public interface for consumers
      public = {
        includeDirs = [ { path = includePath; } ];
        inherit defines compileFlags linkFlags;
      };

      # Evaluation inputs (for Nix to track)
      evalInputs = [ drv ];
    };

  # ==========================================================================
  # Tool Processing
  # ==========================================================================

  # Process tool plugins (code generators, etc.)
  #
  # Tools produce generic outputs that are categorized by file extension:
  #   - Headers (.h, .hpp, etc.) - included but not compiled
  #   - Sources (.c, .cc, .cpp, etc.) - need to be compiled
  #
  # Each tool can provide:
  #   name        - Tool name (for error messages)
  #   outputs     - List of { rel, path } for generated files
  #   includeDirs - Additional include directories
  #   defines     - Additional preprocessor defines
  #   compileFlags - Additional compile flags
  #   evalInputs  - Derivations to add as build inputs
  #   public      - Public interface for consumers
  #
  processTools =
    tools:
    let
      # Convert an output entry to a normalized form
      normalizeOutput =
        output:
        let
          relRaw =
            if output ? rel then
              output.rel
            else if output ? relative then
              output.relative
            else
              throw "nixnative: tool output must provide a 'rel' or 'relative' attribute. Got: ${showValue output}";
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
          path =
            if output ? path then
              toPathLike output.path
            else if output ? store then
              toPathLike output.store
            else
              throw "nixnative: tool output '${rel}' must provide 'path' or 'store' attribute. Got: ${showValue output}";
        in
        { inherit rel path; };

      # Categorize a single output by extension
      categorizeOutput =
        output:
        let
          normalized = normalizeOutput output;
        in
        if language.isSourceFile normalized.rel then
          { sources = [ normalized ]; headers = []; }
        else if language.isHeaderFile normalized.rel then
          { sources = []; headers = [ normalized ]; }
        else
          # Unknown extension - treat as header (include but don't compile)
          { sources = []; headers = [ normalized ]; };

      # Process outputs from a single tool
      processToolOutputs =
        tool:
        let
          outputs = tool.outputs or [];
          categorized = map categorizeOutput outputs;
        in
        {
          sources = lib.concatMap (c: c.sources) categorized;
          headers = lib.concatMap (c: c.headers) categorized;
        };

      step =
        acc: tool:
        let
          toolName = tool.name or "<unnamed tool>";

          # Process generic outputs
          processed = processToolOutputs tool;

          # Convert to source entries (just the rel paths for compilation)
          toolSources = map (s: s) processed.sources;

          # Validate and get public attributes
          toolPublic =
            if tool ? public then
              validatePublic {
                public = tool.public;
                context = "tool '${toolName}'";
              }
            else
              emptyPublic;

          # Collect other attributes
          toolIncludeDirs = tool.includeDirs or [ ];
          toolDefines = tool.defines or [ ];
          toolCompileFlags = tool.compileFlags or [ ];
          toolEvalInputs =
            if tool ? evalInputs then
              tool.evalInputs
            else if tool ? drv then
              [ tool.drv ]
            else
              [ ];
        in
        {
          sources = acc.sources ++ toolSources;
          headers = acc.headers ++ processed.headers;
          includeDirs = acc.includeDirs ++ toolIncludeDirs;
          defines = acc.defines ++ toolDefines;
          compileFlags = acc.compileFlags ++ toolCompileFlags;
          public = mergePublic acc.public toolPublic;
          evalInputs = acc.evalInputs ++ toolEvalInputs;
        };
    in
    foldl' step {
      sources = [ ];
      headers = [ ];
      includeDirs = [ ];
      defines = [ ];
      compileFlags = [ ];
      public = emptyPublic;
      evalInputs = [ ];
    } tools;
}
