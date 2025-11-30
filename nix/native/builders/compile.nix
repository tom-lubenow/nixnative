# Compilation step for nixnative
#
# Compiles individual translation units using the toolchain abstraction.
#
{
  pkgs,
  lib,
  utils,
}:

let
  inherit (lib) concatStringsSep;
  inherit (utils)
    sanitizeName
    mkSourceTree
    toIncludeFlags
    toDefineFlags
    ;

in
rec {
  # ==========================================================================
  # Translation Unit Compilation
  # ==========================================================================

  # Compile a single translation unit to an object file
  #
  # Arguments:
  #   toolchain    - Toolchain from mkToolchain
  #   root         - Source root directory
  #   tu           - Translation unit (from normalizeSources)
  #   headers      - Set of header dependencies
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   flags        - Abstract flags (from flags.nix)
  #   extraFlags   - Additional raw compiler flags
  #   extraInputs  - Additional build inputs
  #
  compileTranslationUnit =
    {
      toolchain,
      root,
      tu,
      headers,
      includeDirs,
      defines,
      flags ? [ ], # Abstract flags
      extraFlags ? [ ], # Raw flags (language-agnostic)
      extraInputs ? [ ],
    }:
    let
      tc = toolchain;

      # Detect language and get appropriate compiler/flags
      compiler = tc.getCompilerForFile tu.relNorm;
      languageDefaultFlags = tc.getDefaultFlagsForFile tu.relNorm;

      # Build source tree with headers
      srcTree = mkSourceTree { inherit tu headers; };

      # Convert include dirs to flags
      includeFlags = toIncludeFlags { inherit srcTree includeDirs; };

      # Convert defines to flags
      defineFlags = toDefineFlags defines;

      # Translate abstract flags to concrete CLI args
      translatedFlags = tc.translateFlags flags;

      # Platform-specific flags (e.g., -fPIC on Linux)
      platformFlags = tc.getPlatformCompileFlags;

      # Combine all flags
      allFlags = languageDefaultFlags ++ platformFlags ++ translatedFlags ++ extraFlags;

      # Get linker driver flag (for LTO to work, linker must be specified at compile time too)
      linkerFlag = if tc.linker.driverFlag != "" then [ tc.linker.driverFlag ] else [ ];

      # Build the derivation
      drv =
        pkgs.runCommand "${sanitizeName tu.relNorm}.o"
          (
            {
              buildInputs = tc.runtimeInputs ++ extraInputs;
            }
            // tc.environment
          )
          ''
            set -euo pipefail
            # Unset Nix wrapper environment variables that interfere with our explicit flags
            unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
            unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET
            mkdir -p "$out"
            ${compiler} \
              ${concatStringsSep " " allFlags} \
              ${concatStringsSep " " linkerFlag} \
              ${concatStringsSep " " includeFlags} \
              ${concatStringsSep " " defineFlags} \
              -c ${srcTree}/${tu.relNorm} \
              -o "$out/${tu.objectName}"
          '';
    in
    {
      derivation = drv;
      object = "${drv}/${tu.objectName}";
      inherit
        tu
        headers
        srcTree
        includeFlags
        defineFlags
        ;
      compileFlags = allFlags;
    };

  # ==========================================================================
  # Compile Commands Generation
  # ==========================================================================

  # Generate compile_commands.json for IDE integration
  generateCompileCommands =
    {
      toolchain,
      root,
      tus,
      includeDirs,
      defines,
      flags ? [ ],
      extraFlags ? [ ],
    }:
    let
      tc = toolchain;

      # Convert include dirs to flags (simplified for compile_commands)
      includeFlags = map (
        dir:
        if builtins.isString dir then
          "-I${dir}"
        else if builtins.isPath dir then
          "-I${dir}"
        else if builtins.isAttrs dir && dir ? path then
          "-I${dir.path}"
        else
          throw "compileCommands: unsupported include path value"
      ) includeDirs;

      defineFlags = toDefineFlags defines;
      translatedFlags = tc.translateFlags flags;
      platformFlags = tc.getPlatformCompileFlags;

      # Generate entry for each translation unit with language-appropriate compiler/flags
      mkEntry = tu:
        let
          compiler = tc.getCompilerForFile tu.relNorm;
          languageDefaultFlags = tc.getDefaultFlagsForFile tu.relNorm;
          allFlags = languageDefaultFlags ++ platformFlags ++ translatedFlags ++ extraFlags;
        in
        {
          directory = builtins.toString root;
          file = tu.relNorm;
          command = concatStringsSep " " (
            [ compiler ]
            ++ allFlags
            ++ includeFlags
            ++ defineFlags
            ++ [
              "-c"
              tu.relNorm
              "-o"
              tu.objectName
            ]
          );
        };

      entries = map mkEntry tus;
    in
    pkgs.writeText "compile_commands.json" (builtins.toJSON entries);
}
