# Tool plugin processing for nixnative
#
# Handles tool plugins (code generators, etc.) that produce headers and
# sources at evaluation time. These are passed to the dynamic driver.
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
  # Tool Plugin Processing
  # ==========================================================================

  # Process tool plugins (code generators, etc.)
  #
  # Tools are evaluated at eval time and their outputs (headers, sources)
  # are passed to the dynamic driver as inputs. This allows code generation
  # tools like protobuf or template renderers to work with dynamic derivations.
  #
  # Each tool can provide:
  #   name       - Tool name (for error messages)
  #   headers    - List of { rel, path/store } for generated headers
  #   sources    - List of { rel, path/store } for generated sources
  #   includeDirs - Additional include directories
  #   defines    - Additional preprocessor defines
  #   cxxFlags   - Additional compile flags
  #   evalInputs - Derivations to add as build inputs
  #   public     - Public interface for consumers
  #
  processTools =
    tools:
    let
      toOverrideEntry =
        header:
        let
          relRaw =
            if header ? rel then
              header.rel
            else if header ? relative then
              header.relative
            else
              throw "nixnative: tool header must provide a 'rel' or 'relative' attribute. Got: ${showValue header}";
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
          value =
            if header ? store then
              toPathLike header.store
            else if header ? path then
              toPathLike header.path
            else
              throw "nixnative: tool header '${rel}' must provide 'path' or 'store' attribute. Got: ${showValue header}";
        in
        {
          name = rel;
          inherit value;
        };

      toSourceOverride =
        source:
        let
          relRaw =
            if source ? rel then
              source.rel
            else
              throw "nixnative: tool source must provide a 'rel' attribute. Got: ${showValue source}";
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
          value =
            if source ? store then
              toPathLike source.store
            else if source ? path then
              toPathLike source.path
            else
              throw "nixnative: tool source '${rel}' must provide 'path' or 'store' attribute. Got: ${showValue source}";
        in
        {
          name = rel;
          inherit value;
        };

      step =
        acc: tool:
        let
          toolName = tool.name or "<unnamed tool>";

          # Get header overrides
          overrides = if tool ? headers then builtins.listToAttrs (map toOverrideEntry tool.headers) else { };

          # Get source overrides
          sourceOverridesMap =
            if tool ? sources then builtins.listToAttrs (map toSourceOverride tool.sources) else { };

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
          toolSources = tool.sources or [ ];
          toolIncludeDirs = tool.includeDirs or [ ];
          toolDefines = tool.defines or [ ];
          toolCxxFlags = tool.cxxFlags or [ ];
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
          includeDirs = acc.includeDirs ++ toolIncludeDirs;
          defines = acc.defines ++ toolDefines;
          cxxFlags = acc.cxxFlags ++ toolCxxFlags;
          public = mergePublic acc.public toolPublic;
          headerOverrides = acc.headerOverrides // overrides;
          sourceOverrides = acc.sourceOverrides // sourceOverridesMap;
          evalInputs = acc.evalInputs ++ toolEvalInputs;
        };
    in
    foldl' step {
      sources = [ ];
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      public = emptyPublic;
      headerOverrides = { };
      sourceOverrides = { };
      evalInputs = [ ];
    } tools;
}
