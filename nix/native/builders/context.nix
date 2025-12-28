# Build context for nixnative
#
# A build context aggregates all configuration needed to compile a target:
# sources, include directories, defines, flags, libraries, tools, etc.
#
# Uses dynamic derivations for dependency scanning (no IFD).
#
{
  pkgs,
  lib,
  utils,
  flags,
  compile,
  scanner,
  dynamic,  # Dynamic derivations module (required)
}:

let
  inherit (utils) validatePublic;

in
rec {
  # ==========================================================================
  # Build Context Factory
  # ==========================================================================

  # Create a build context using dynamic derivations
  #
  # Arguments:
  #   name         - Target name
  #   toolchain    - Toolchain from mkToolchain
  #   root         - Source root directory
  #   sources      - List of source files
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   flags        - Abstract flags (lto, sanitizers, etc.)
  #   compileFlags - Raw compile-only flags (all languages)
  #   langFlags    - Per-language raw flags { c = [...]; cpp = [...]; }
  #   libraries    - Library dependencies
  #   tools        - Tool plugins (code generators, etc.)
  #
  mkBuildContext =
    {
      name,
      toolchain,
      root,
      sources,
      includeDirs ? [ ],
      defines ? [ ],
      flags ? [ ],
      compileFlags ? [ ],
      langFlags ? { },
      libraries ? [ ],
      tools ? [ ],
      ...
    }@args:
    let
      # Validate library public attributes
      _ = map (
        libItem:
        if libItem ? public then
          validatePublic {
            public = libItem.public;
            context = "library '${libItem.name or "unknown"}'";
          }
        else
          true
      ) libraries;
    in
    # Delegate to dynamic build context
    dynamic.mkDynamicBuildContext args;
}
