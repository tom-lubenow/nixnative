# Dynamic build context for nixnative
#
# This module provides a build context that uses dynamic derivations
# instead of IFD (Import From Derivation) for dependency scanning.
#
# The context returns placeholders that are resolved at build time,
# allowing evaluation to complete instantly.
#
{
  pkgs,
  lib,
  utils,
  driver,
  scanner,
}:

let
  inherit (lib) concatStringsSep;
  inherit (utils)
    sanitizePath
    normalizeSources
    collectPublic
    mergePublic
    collectEvalInputs
    validatePublic
    ;
  inherit (scanner) processTools;
  inherit (driver) mkDynamicDriver mkObjectsRef;

in
rec {
  # ==========================================================================
  # Dynamic Build Context Factory
  # ==========================================================================

  # Create a dynamic build context that defers scanning to build time
  #
  # This is an alternative to mkBuildContext that uses dynamic derivations
  # instead of IFD. The key difference is that objectPaths contains
  # placeholders that are resolved at build time rather than actual paths.
  #
  # Arguments are the same as mkBuildContext.
  #
  mkDynamicBuildContext =
    {
      name,
      toolchain,
      root,
      sources,
      includeDirs ? [],
      defines ? [],
      flags ? [],
      compileFlags ? [],
      langFlags ? {},
      ldflags ? [],
      linkFlags ? [],
      libraries ? [],
      tools ? [],
      outputType ? "executable",  # "executable", "sharedLibrary", or "staticArchive"
      ...
    }@args:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };

      # Process tool plugins
      toolInfo = processTools tools;

      # Validate public attributes from libraries
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

      # Collect public attributes from libraries
      libsPublic = collectPublic libraries;

      # Collect evalInputs from libraries
      libsEvalInputs = collectEvalInputs libraries;

      # Merge library and tool public attributes
      publicAggregate = mergePublic libsPublic toolInfo.public;

      # Combine sources
      allSources = sources ++ toolInfo.sources;

      # Combine include directories
      combinedIncludeDirs = includeDirs ++ publicAggregate.includeDirs ++ toolInfo.includeDirs;

      # Combine defines
      combinedDefines = defines ++ publicAggregate.defines ++ toolInfo.defines;

      # Combine compile flags
      combinedCompileFlags = compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Normalize sources to translation units
      tus = normalizeSources {
        inherit root;
        sources = allSources;
      };

      # Combine link flags from libraries
      combinedLinkFlags = linkFlags ++ publicAggregate.linkFlags;
      combinedLdflags = ldflags ++ publicAggregate.ldFlags;

      # Create the dynamic driver
      driverDrv = mkDynamicDriver {
        inherit name root toolchain flags outputType;
        sources = allSources;
        includeDirs = combinedIncludeDirs;
        defines = combinedDefines;
        compileFlags = combinedCompileFlags;
        inherit langFlags;
        ldflags = combinedLdflags;
        linkFlags = combinedLinkFlags;
        headerOverrides = toolInfo.headerOverrides;
        sourceOverrides = toolInfo.sourceOverrides;
        extraInputs = toolInfo.evalInputs ++ libsEvalInputs;
      };

      # Reference to the driver's output (resolved at build time)
      objectsRef = mkObjectsRef driverDrv;

    in
    {
      inherit name toolchain;
      rootPath = rootPath;

      # The driver derivation
      inherit driverDrv;

      # Object paths - this is a placeholder resolved at build time
      # For dynamic mode, we reference the driver's output
      objectPaths = [ objectsRef ];

      # These are not available at evaluation time in dynamic mode
      objectInfos = [];
      manifest = null;

      # Compile commands will be in the driver output
      compileCommands = "${driverDrv}/compile_commands.json";

      # Configuration
      inherit combinedIncludeDirs combinedDefines;
      inherit combinedCompileFlags combinedLinkFlags combinedLdflags;
      combinedLangFlags = langFlags;
      inherit publicAggregate;
      inherit libraries tools;
      inherit flags outputType;
      inherit libsEvalInputs;

      # Mark as dynamic mode
      isDynamic = true;
      scanMode = "dynamic";
      scanDerivations = [ driverDrv ];
      inherit tus;

      # Content addressed is always true for dynamic mode
      contentAddressed = true;
    };
}
