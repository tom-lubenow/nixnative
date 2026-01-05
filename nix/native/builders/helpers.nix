# High-level build helpers for nixnative
#
# These functions provide the primary API for building C/C++ targets.
# Uses nix-ninja for incremental per-file compilation.
#
{
  pkgs,
  lib,
  utils,
  platform,
  processTools, # Tool processing
  ninja,        # nix-ninja integration
}:

let
  inherit (lib) concatStringsSep hasPrefix removePrefix;
  inherit (utils)
    sanitizePath
    sanitizeName
    normalizeIncludeDir
    mergePublic
    ensureList
    collectPublic
    emptyPublic
    collectObjectRefs
    collectLinkFlags
    isGlob
    expandGlob
    ;

  # Collect ninja-built library target outputs for dependency tracking
  # Returns list of builtins.outputOf references that ensure dynamic derivations are built
  collectLibraryInputs = libs:
    let
      collectFromLib = lib:
        if builtins.isAttrs lib then
          # Check if this is a ninja-built library (has passthru.target)
          if lib ? passthru && lib.passthru ? target then
            # Return the target (builtins.outputOf) so Nix builds the dynamic derivation
            [ lib.passthru.target ] ++ (if lib ? libraries then collectLibraryInputs lib.libraries else [])
          else if lib ? libraries then
            collectLibraryInputs lib.libraries
          else
            []
        else
          [];
    in
    lib.unique (lib.concatMap collectFromLib libs);

  # Language detection for source files
  detectLanguage = path:
    let
      ext = lib.last (lib.splitString "." (toString path));
    in
    if builtins.elem ext [ "c" "h" ] then "c"
    else if builtins.elem ext [ "cc" "cpp" "cxx" "C" "hpp" "hxx" ] then "cpp"
    else null;

  # Normalize a source file for ninja consumption
  # Returns: { storePath, relNorm, objectName, lang }
  #
  # For incremental builds, each source file gets its own store path via builtins.path.
  # This ensures that changing one file only invalidates derivations that depend on it.
  #
  # IMPORTANT: We do NOT call sanitizePath on root here! sanitizePath would copy the
  # entire directory to the store, defeating per-file incrementality. Instead, we
  # keep root as a local path and use builtins.path on individual source files.
  normalizeSourceForNinja = { root, source }:
    let
      # Keep root as a local path - do NOT copy to store yet
      # We need this for computing relative paths
      rootStr = if builtins.isPath root then toString root
                else if builtins.isString root then root
                else if root ? path then toString root.path
                else throw "Invalid root: ${builtins.toJSON root}";

      # Handle different source formats
      srcInfo =
        if builtins.isString source then
          { rel = source; path = root + "/${source}"; store = null; }
        else if builtins.isPath source then
          let
            pathStr = toString source;
            rel = if hasPrefix rootStr pathStr
              then removePrefix (rootStr + "/") pathStr
              else builtins.baseNameOf pathStr;
          in
          { inherit rel; path = source; store = null; }
        else if source ? rel then
          { rel = source.rel; path = source.path or (root + "/${source.rel}"); store = source.store or null; }
        else
          throw "Invalid source format: ${builtins.toJSON source}";

      relNorm = if hasPrefix "./" srcInfo.rel
        then removePrefix "./" srcInfo.rel
        else srcInfo.rel;

      lang = detectLanguage relNorm;
      ext = lib.last (lib.splitString "." relNorm);
      baseName = lib.removeSuffix ".${ext}" relNorm;
      objectName = sanitizeName baseName + ".o";

      # For incremental builds: create individual store paths for each source file
      # This is the key to incrementality - each file is its own store path, so
      # changing one file doesn't invalidate derivations that don't use it.
      #
      # IMPORTANT: We preserve the file extension in the store path name so the
      # compiler can determine the source language.
      storePath =
        if srcInfo.store != null then
          # Tool-generated sources already have a store path (explicit)
          "${srcInfo.store}"
        else if builtins.isString srcInfo.path && builtins.hasContext srcInfo.path then
          # Tool-generated sources with derivation context in path string
          # (e.g., "${drv}/foo.pb.cc"). Don't call builtins.path - that would
          # try to read the file at eval time before the derivation is built.
          srcInfo.path
        else
          # Regular source file: create an individual store path
          # builtins.path copies just this one file to the store
          # Preserve the extension (e.g., .c, .cpp) so compilers recognize the file type
          builtins.path {
            path = srcInfo.path;
            name = sanitizeName baseName + ".${ext}";
          };
    in
    {
      inherit storePath relNorm objectName lang;
    };

  # Normalize all sources for ninja (with glob expansion)
  normalizeSourcesForNinja = { root, sources }:
    let
      # Expand globs first
      expandedSources = lib.concatMap (source:
        if isGlob source then
          expandGlob { inherit root; pattern = source; }
        else
          [ source ]
      ) sources;
    in
    map (source: normalizeSourceForNinja { inherit root source; }) expandedSources;

  # Common preparation for all target types
  # Returns: { normalizedSources, resolvedIncludeDirs, combinedDefines, combinedCompileFlags, legacyLinkFlags, libraryInputs }
  prepareTarget = {
    toolchain,
    root,
    sources,
    includeDirs,
    defines,
    compileFlags,
    libraries,
    tools,
  }:
    let
      tc = toolchain;

      # For incrementality: create a headers-only store path that excludes source files.
      # This way, changing a .c file doesn't invalidate all include paths.
      # Header extensions we care about:
      headerExtensions = [ "h" "hpp" "hxx" "H" "hh" "h++" "tcc" "inc" "inl" ];
      isHeaderFile = name: type:
        type == "regular" &&
        builtins.any (ext: lib.hasSuffix ".${ext}" name) headerExtensions;

      # Filter to include directories AND header files only
      # We need directories to preserve the tree structure
      headersAndDirsFilter = name: type:
        type == "directory" || isHeaderFile name type;

      # Create a store path with only headers (and directory structure)
      # This is stable as long as headers don't change
      headersOnlyPath = builtins.path {
        path = root;
        name = "headers";
        filter = headersAndDirsFilter;
      };

      # Keep rootPath for backwards compatibility, but prefer headersOnlyPath for includes
      rootPath = headersOnlyPath;

      # Process tools for generated headers/sources
      toolInfo = processTools tools;

      # Collect public attributes from libraries
      libsPublic = collectPublic libraries;

      # Merge library and tool public attributes
      publicAggregate = mergePublic libsPublic toolInfo.public;

      # Combine sources (own + tool-generated)
      allSources = sources ++ toolInfo.sources;

      # Combine include directories
      combinedIncludeDirs = includeDirs
        ++ (map (d: d.path) publicAggregate.includeDirs)
        ++ toolInfo.includeDirs;

      # Combine defines
      combinedDefines = defines ++ publicAggregate.defines ++ toolInfo.defines;

      # Combine compile flags
      combinedCompileFlags = compileFlags ++ publicAggregate.compileFlags ++ toolInfo.compileFlags;

      # Collect legacy link flags (for external libs like pkg-config)
      legacyLinkFlags = collectLinkFlags libraries;

      # Normalize sources for ninja
      normalizedSources = normalizeSourcesForNinja {
        inherit root;
        sources = allSources;
      };

      # Resolve include directories to store paths
      resolvedIncludeDirs = map (d:
        if builtins.isPath d then builtins.toString d
        else if builtins.isString d then
          if hasPrefix "/" d then d
          else builtins.toString (rootPath + "/${d}")
        else if d ? path then builtins.toString d.path
        else throw "Invalid include dir: ${builtins.toJSON d}"
      ) combinedIncludeDirs;

      # Collect library wrapper derivations for dependency tracking
      libraryInputs = collectLibraryInputs libraries;
    in {
      inherit normalizedSources resolvedIncludeDirs combinedDefines combinedCompileFlags;
      inherit legacyLinkFlags libraryInputs;
      inherit rootPath publicAggregate;
      runtimeInputs = tc.runtimeInputs;
    };

in
rec {
  # ==========================================================================
  # Executable Builder
  # ==========================================================================

  mkExecutable =
    {
      name,
      toolchain,
      root,
      sources,
      includeDirs ? [],
      defines ? [],
      compileFlags ? [],
      languageFlags ? {},
      linkFlags ? [],
      libraries ? [],
      tools ? [],
      ...
    }@args:
    let
      prep = prepareTarget {
        inherit toolchain root sources includeDirs defines compileFlags libraries tools;
      };

      ninjaContent = ninja.generateExecutable {
        inherit name toolchain languageFlags;
        sources = prep.normalizedSources;
        includeDirs = prep.resolvedIncludeDirs;
        defines = prep.combinedDefines;
        compileFlags = prep.combinedCompileFlags;
        linkFlags = linkFlags ++ prep.legacyLinkFlags;
      };

      # Extract individual source file store paths for incremental builds
      # This ensures changing one source file only invalidates derivations that use it
      sourceFilePaths = map (s: s.storePath) prep.normalizedSources;

      wrapper = ninja.mkNinjaDerivation {
        inherit name ninjaContent;
        libraryInputs = prep.libraryInputs;
        target = name;
        # Use individual source file paths for better incrementality
        # Include directories are embedded in ninjaContent and tracked via the ninja file
        sourceInputs = sourceFilePaths;
        toolInputs = prep.runtimeInputs;
        outputType = "executable";
      };

      targetOut = wrapper.passthru.target;
    in
    wrapper // {
      artifactType = "executable";
      inherit name libraries tools;
      executablePath = "${targetOut}/bin/${name}";
      passthru = wrapper.passthru // {
        inherit toolchain;
        tus = prep.normalizedSources;
        inherit ninjaContent;
      };
    };

  # ==========================================================================
  # Static Library Builder
  # ==========================================================================

  # Build a static library from C/C++ sources
  #
  # Produces a .a archive via nix-ninja.
  #
  mkStaticLib =
    {
      name,
      toolchain,
      root,
      sources,
      includeDirs ? [],
      defines ? [],
      compileFlags ? [],
      languageFlags ? {},
      libraries ? [],
      tools ? [],
      publicIncludeDirs ? null,  # Defaults to includeDirs if not specified
      publicDefines ? [],
      publicCompileFlags ? [],
      ...
    }@args:
    let
      prep = prepareTarget {
        inherit toolchain root sources includeDirs defines compileFlags libraries tools;
      };

      rootHost = builtins.toString prep.rootPath;

      # Resolve public include directories (default to includeDirs if not specified)
      resolvedPublicIncludeDirs = if publicIncludeDirs == null then includeDirs else publicIncludeDirs;

      publicIncludeStores = map (dir:
        normalizeIncludeDir { inherit rootHost dir; }
      ) (ensureList resolvedPublicIncludeDirs);

      archiveName = "${name}.a";

      ninjaContent = ninja.generateStaticLib {
        inherit name toolchain languageFlags;
        sources = prep.normalizedSources;
        includeDirs = prep.resolvedIncludeDirs;
        defines = prep.combinedDefines;
        compileFlags = prep.combinedCompileFlags;
      };

      # Extract individual source file store paths for incremental builds
      sourceFilePaths = map (s: s.storePath) prep.normalizedSources;

      wrapper = ninja.mkNinjaDerivation {
        inherit name ninjaContent;
        target = archiveName;
        sourceInputs = sourceFilePaths;
        toolInputs = prep.runtimeInputs;
        outputType = "staticLib";
      };

      archiveOut = wrapper.passthru.target;

      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        compileFlags = publicCompileFlags;
        linkFlags = [ "${archiveOut}/${archiveName}" ];
      };

      combinedPublic = {
        includeDirs = prep.publicAggregate.includeDirs ++ basePublic.includeDirs;
        defines = prep.publicAggregate.defines ++ basePublic.defines;
        compileFlags = prep.publicAggregate.compileFlags ++ basePublic.compileFlags;
        linkFlags = basePublic.linkFlags;
      };
    in
    wrapper // {
      artifactType = "static";
      inherit name libraries tools;
      archivePath = "${archiveOut}/${archiveName}";
      public = combinedPublic;
      passthru = wrapper.passthru // {
        inherit toolchain;
        tus = prep.normalizedSources;
        inherit ninjaContent;
      };
    };

  # ==========================================================================
  # Shared Library Builder
  # ==========================================================================

  # Build a shared library (.so) from C/C++ sources
  #
  mkSharedLib =
    {
      name,
      toolchain,
      root,
      sources,
      includeDirs ? [],
      defines ? [],
      compileFlags ? [],
      languageFlags ? {},
      linkFlags ? [],
      libraries ? [],
      tools ? [],
      publicIncludeDirs ? null,  # Defaults to includeDirs if not specified
      publicDefines ? [],
      publicCompileFlags ? [],
      ...
    }@args:
    let
      prep = prepareTarget {
        inherit toolchain root sources includeDirs defines compileFlags libraries tools;
      };

      rootHost = builtins.toString prep.rootPath;

      # Resolve public include directories (default to includeDirs if not specified)
      resolvedPublicIncludeDirs = if publicIncludeDirs == null then includeDirs else publicIncludeDirs;

      publicIncludeStores = map (dir:
        normalizeIncludeDir { inherit rootHost dir; }
      ) (ensureList resolvedPublicIncludeDirs);

      sharedName = "${name}.so";

      ninjaContent = ninja.generateSharedLib {
        inherit name toolchain languageFlags;
        sources = prep.normalizedSources;
        includeDirs = prep.resolvedIncludeDirs;
        defines = prep.combinedDefines;
        compileFlags = prep.combinedCompileFlags;
        linkFlags = linkFlags ++ prep.legacyLinkFlags;
      };

      # Extract individual source file store paths for incremental builds
      sourceFilePaths = map (s: s.storePath) prep.normalizedSources;

      wrapper = ninja.mkNinjaDerivation {
        inherit name ninjaContent;
        libraryInputs = prep.libraryInputs;
        target = sharedName;
        sourceInputs = sourceFilePaths;
        toolInputs = prep.runtimeInputs;
        outputType = "sharedLib";
      };

      sharedOut = wrapper.passthru.target;
      sharedLibPath = "${sharedOut}/${sharedName}";

      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        compileFlags = publicCompileFlags;
        linkFlags = [ sharedLibPath ];
      };

      combinedPublic = {
        includeDirs = prep.publicAggregate.includeDirs ++ basePublic.includeDirs;
        defines = prep.publicAggregate.defines ++ basePublic.defines;
        compileFlags = prep.publicAggregate.compileFlags ++ basePublic.compileFlags;
        linkFlags = basePublic.linkFlags;
      };
    in
    wrapper // {
      artifactType = "shared";
      inherit name libraries tools;
      sharedLibrary = sharedLibPath;
      public = combinedPublic;
      passthru = wrapper.passthru // {
        inherit toolchain;
        tus = prep.normalizedSources;
        inherit ninjaContent;
      };
    };

  # ==========================================================================
  # Header-Only Library
  # ==========================================================================

  # Create a header-only library (no compilation)
  #
  mkHeaderOnly =
    {
      name,
      root ? ./.,
      includeDirs ? [],
      defines ? [],
      compileFlags ? [],
      libraries ? [],
      publicIncludeDirs ? null,  # Defaults to includeDirs if not specified
      publicDefines ? [],
      publicCompileFlags ? [],
      tools ? [],
    }:
    let
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;

      # Process tools for generated headers
      toolInfo = processTools tools;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic libsPublic (toolInfo.public or emptyPublic);

      # Resolve public include directories (default to includeDirs if not specified)
      resolvedPublicIncludeDirs = if publicIncludeDirs == null then includeDirs else publicIncludeDirs;

      publicIncludeStores = map (
        dir:
        normalizeIncludeDir {
          inherit rootHost;
          inherit dir;
        }
      ) (ensureList resolvedPublicIncludeDirs);

      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        compileFlags = publicCompileFlags;
        linkFlags = [];
      };

      combinedPublic = mergePublic publicAggregate basePublic;
    in
    {
      artifactType = "header-only";
      inherit name;
      public = combinedPublic;
      inherit libraries tools;
      objectRefs = [];  # No objects for header-only
    };

  # ==========================================================================
  # Development Shell
  # ==========================================================================

  # Create a development shell for a target
  #
  mkDevShell =
    {
      target,
      toolchain ? null,
      extraPackages ? [],
      linkCompileCommands ? true,
      symlinkName ? "compile_commands.json",
      includeTools ? true,
    }:
    let
      tc =
        if toolchain != null then
          toolchain
        else
          target.passthru.toolchain or (throw "mkDevShell: no toolchain provided or found in target");

      compileCommands = target.compileCommands or target.passthru.compileCommands or null;

      # Include common development tools
      devTools =
        if includeTools then
          [
            pkgs.clang-tools
            pkgs.gdb
          ]
        else
          [];

      packages = lib.unique (
        tc.runtimeInputs
        ++ devTools
        ++ extraPackages
      );

      # Hook to symlink compile_commands.json
      linkHook =
        if linkCompileCommands && compileCommands != null then
          ''
            ln -sf "${compileCommands}" "${symlinkName}"
          ''
        else
          "";

      # Environment exports
      envExports = tc.getEnvironmentExports;
    in
    pkgs.mkShell {
      inherit packages;
      shellHook = ''
        ${linkHook}
        export CC="${tc.getCompilerForLanguage "c"}"
        export CXX="${tc.getCompilerForLanguage "cpp"}"
        ${envExports}
      '';
    };

  # ==========================================================================
  # Test Runner
  # ==========================================================================

  # Create a test derivation that runs an executable
  #
  # For nix-ninja built executables, uses ninja.mkNinjaTest.
  # For traditional executables, uses a simple runCommand.
  #
  mkTest =
    {
      name,
      executable,
      args ? [],
      stdin ? null,
      expectedOutput ? null,
    }:
    let
      # Check if this is a ninja-built executable
      isNinjaBuilt = executable ? passthru && executable.passthru ? target;

      stdinFile = if stdin != null then pkgs.writeText "stdin" stdin else null;
      escapedArgs = map lib.escapeShellArg args;

      # Ninja-built executable test
      # Get the executable name from the wrapper (strip .drv suffix if present)
      exeName = lib.removeSuffix ".drv" (executable.name or "unknown");
      ninjaTest = ninja.mkNinjaTest {
        inherit name args;
        # Pass both the wrapper (for dependency) and target (for path resolution)
        wrapper = executable;
        target = executable.passthru.target;
        executableName = exeName;
        inherit expectedOutput;
      };

      # Traditional runCommand test for non-ninja executables
      traditionalTest = let
        execPath = "${executable}/bin/${executable.name or "unknown"}";
        expectedOutputFile =
          if expectedOutput != null then pkgs.writeText "expected-output" expectedOutput else null;
      in
      pkgs.runCommand "test-${name}"
        {
          nativeBuildInputs = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.findutils
          ];
          buildInputs = [ pkgs.stdenv.cc.cc.lib ];
        }
        ''
          set -euo pipefail
          mkdir -p $out

          BIN="${execPath}"
          echo "Running test: $BIN (${toString (builtins.length args)} args)"

          ${if stdin != null then "cat ${stdinFile} |" else ""} \
          "$BIN" ${concatStringsSep " " escapedArgs} > output.log 2>&1 || {
            echo "Test failed with exit code $?"
            cat output.log
            exit 1
          }

          cat output.log

          ${
            if expectedOutput != null then
              ''
                expected=$(cat ${expectedOutputFile})
                if ! grep -qF "$expected" output.log; then
                  echo "Test failed: Expected output not found."
                  echo "Expected: $expected"
                  exit 1
                fi
              ''
            else
              ""
          }

          cp output.log $out/test.log
        '';
    in
    if isNinjaBuilt then ninjaTest else traditionalTest;
}
