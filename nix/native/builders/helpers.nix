# High-level build helpers for nixnative
#
# These functions provide the primary API for building C/C++ targets.
# Uses nix-ninja for incremental per-file compilation.
#
{
  pkgs,
  lib,
  utils,
  language,
  processTools, # Tool processing
  ninja,        # nix-ninja integration
}:

let
  inherit (lib) concatStringsSep hasPrefix removePrefix;
  inherit (utils)
    sanitizeName
    normalizeIncludeDir
    mergePublic
    ensureList
    collectPublic
    collectEvalInputs
    compileFlagsForLanguage
    emptyPublic
    collectLinkFlags
    isGlob
    ;

  # Collect ninja-built library target outputs for dependency tracking
  # Returns list of builtins.outputOf references that ensure dynamic derivations are built
  collectLibraryInputs = libs:
    let
      # Named 'library' to avoid shadowing nixpkgs 'lib'
      collectFromLibrary = library:
        if builtins.isAttrs library then
          let
            realizedTarget =
              if library ? target then
                library.target
              else if library ? passthru && library.passthru ? target then
                library.passthru.target
              else
                null;
          in
          # Return the target (builtins.outputOf) so Nix builds the dynamic derivation
          if realizedTarget != null then
            [ realizedTarget ] ++ (if library ? libraries then collectLibraryInputs library.libraries else [])
          else if library ? libraries then
            collectLibraryInputs library.libraries
          else
            []
        else
          [];
    in
    lib.unique (lib.concatMap collectFromLibrary libs);

  resolveIncludeDir = { rootBase, dir }:
    let
      baseStr = toString rootBase;
    in
    if builtins.isPath dir then
      toString dir
    else if builtins.isString dir then
      if hasPrefix "/" dir then dir else "${baseStr}/${dir}"
    else if builtins.isAttrs dir && dir ? path then
      toString dir.path
    else
      throw "Invalid include dir: ${builtins.toJSON dir}";

  # Normalize a source file for ninja consumption
  # Returns: { storePath, relativePath, objectFile, language, path }
  #
  # For incremental builds, each source file gets its own store path via builtins.path.
  # This ensures that changing one file only invalidates derivations that depend on it.
  #
  # IMPORTANT: We do NOT call sanitizePath on root here! sanitizePath would copy the
  # entire directory to the store, defeating per-file incrementality. Instead, we
  # keep root as a local path and use builtins.path on individual source files.
  mkSourceUnit =
    {
      relativePath,
      sourcePath,
      sourceStorePath ? null,
    }:
    let
      normalizedRelativePath =
        if hasPrefix "./" relativePath then
          removePrefix "./" relativePath
        else
          relativePath;
      sourceLanguage = language.detectLanguageName normalizedRelativePath;
      ext = lib.last (lib.splitString "." normalizedRelativePath);
      baseName = lib.removeSuffix ".${ext}" normalizedRelativePath;
      # Include extension in object file name to avoid collisions
      sanitizedPath = lib.replaceStrings [ "/" ":" " " "." ] [ "-" "-" "-" "-" ] normalizedRelativePath;
      objectHash = builtins.substring 0 8 (builtins.hashString "sha256" normalizedRelativePath);
      objectFile = "${sanitizedPath}-${objectHash}.o";

      finalStorePath =
        if sourceStorePath != null then
          "${sourceStorePath}"
        else if builtins.isString sourcePath && builtins.hasContext sourcePath then
          sourcePath
        else
          builtins.path {
            path = sourcePath;
            name = sanitizeName baseName + ".${ext}";
          };
    in
    {
      storePath = finalStorePath;
      relativePath = normalizedRelativePath;
      inherit objectFile;
      path = sourcePath;
      language = sourceLanguage;
    };

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

    in
    mkSourceUnit {
      relativePath = srcInfo.rel;
      sourcePath = srcInfo.path;
      sourceStorePath = srcInfo.store;
    };

  # Normalize all sources for ninja.
  # Sources must be explicit file entries. Source discovery via globs is a
  # separate step and should be done with `native.utils.discoverSources`.
  normalizeSourcesForNinja = { root, sources }:
    let
      globSources = builtins.filter isGlob sources;
      globError =
        if globSources == [ ] then
          null
        else
          throw ''
            nixnative: sources must be explicit file paths; glob patterns are not accepted directly.
            Use native.utils.discoverSources { root = ...; patterns = [ ... ]; } to expand globs first.
          '';
    in
    builtins.seq globError (map (source: normalizeSourceForNinja { inherit root source; }) sources);

  # Common preparation for all target types
  # Returns: { normalizedSources, resolvedIncludeDirs, combinedIncludeDirs, combinedDefines, combinedCompileFlags, libraryLinkFlags, wrappedLibraryLinkFlags, libraryInputs, evalInputs }
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
      isHeaderFile = name: type:
        type == "regular" && language.isHeaderFile name;

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

      # Include resolution uses the header-only tree for stable incremental behavior.
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

      # Collect raw link flags from library values (for external libs like pkg-config)
      libraryLinkFlags = collectLinkFlags libraries;
      wrappedLibraryLinkFlags =
        if libraryLinkFlags == [ ] then
          [ ]
        else
          tc.wrapLibraryFlags libraryLinkFlags;

      # Normalize sources for ninja
      normalizedSources = normalizeSourcesForNinja {
        inherit root;
        sources = allSources;
      };

      # Resolve include directories to store paths
      resolvedIncludeDirs = map (d: resolveIncludeDir { rootBase = rootPath; dir = d; }) combinedIncludeDirs;

      # Collect library wrapper derivations for dependency tracking
      libraryInputs = collectLibraryInputs libraries;
      evalInputs = lib.unique (collectEvalInputs libraries ++ toolInfo.evalInputs);
    in {
      inherit normalizedSources resolvedIncludeDirs combinedIncludeDirs combinedDefines combinedCompileFlags;
      inherit libraryLinkFlags wrappedLibraryLinkFlags libraryInputs evalInputs;
      inherit rootPath publicAggregate;
      runtimeInputs = tc.runtimeInputs;
    };

  # Create compile_commands.json for a target
  mkCompileCommands =
    {
      name,
      root,
      toolchain,
      sources,
      includeDirs,
      defines,
      compileFlags,
      languageFlags,
      extraCFlags ? [],
    }:
    let
      rootStr =
        if builtins.isPath root then toString root
        else if builtins.isString root then root
        else if root ? path then toString root.path
        else throw "Invalid root: ${builtins.toJSON root}";

      resolvedIncludeDirs = map (dir: resolveIncludeDir { rootBase = rootStr; inherit dir; }) includeDirs;

      mkLangFlags = langKey:
        compileFlagsForLanguage {
          inherit toolchain;
          language = langKey;
          includeDirs = resolvedIncludeDirs;
          inherit defines compileFlags languageFlags extraCFlags;
        };

      mkCommand = source:
        let
          srcPath = toString source.path;
          objectFile = source.objectFile;
          depFile = "${objectFile}.d";
          compiler =
            if source.language == "c" then toolchain.getCompilerForLanguage "c"
            else toolchain.getCompilerForLanguage "cpp";
          flags = mkLangFlags source.language;
        in
        {
          directory = rootStr;
          file = srcPath;
          arguments =
            [ compiler ]
            ++ flags
            ++ [
              "-MD"
              "-MF"
              depFile
              "-c"
              srcPath
              "-o"
              objectFile
            ];
        };

      commands = map mkCommand sources;
    in
    pkgs.writeText "${name}-compile_commands.json" (builtins.toJSON commands);

  # Common ninja build path for compiled targets (executable/static/shared)
  mkCompiledTarget =
    {
      name,
      toolchain,
      root,
      sources,
      includeDirs,
      defines,
      compileFlags,
      languageFlags,
      libraries,
      tools,
      outputType,
      targetName,
      includeLibraryInputs ? false,
      extraCompileCommandsCFlags ? [],
      buildNinjaContent,
    }:
    let
      prep = prepareTarget {
        inherit toolchain root sources includeDirs defines compileFlags libraries tools;
      };

      ninjaContent = buildNinjaContent prep;

      compileCommands = mkCompileCommands {
        inherit name root toolchain languageFlags;
        sources = prep.normalizedSources;
        includeDirs = prep.combinedIncludeDirs;
        defines = prep.combinedDefines;
        compileFlags = prep.combinedCompileFlags;
        extraCFlags = extraCompileCommandsCFlags;
      };

      # Extract individual source file store paths for incremental builds
      # This ensures changing one source file only invalidates derivations that use it
      sourceFilePaths = map (s: s.storePath) prep.normalizedSources;

      wrapper = ninja.mkNinjaDerivation {
        inherit name ninjaContent;
        target = targetName;
        sourceInputs = sourceFilePaths;
        toolInputs = prep.runtimeInputs;
        evalInputs = prep.evalInputs;
        outputType = outputType;
        libraryInputs = if includeLibraryInputs then prep.libraryInputs else [ ];
      };

      targetOut = wrapper.target or wrapper.passthru.target;
    in
    {
      inherit prep ninjaContent compileCommands wrapper targetOut;
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
    }:
    let
      build = mkCompiledTarget {
        inherit name toolchain root sources includeDirs defines compileFlags languageFlags libraries tools;
        outputType = "executable";
        targetName = name;
        includeLibraryInputs = true;
        buildNinjaContent = prep: ninja.generateExecutable {
          inherit name toolchain languageFlags;
          sources = prep.normalizedSources;
          includeDirs = prep.resolvedIncludeDirs;
          defines = prep.combinedDefines;
          compileFlags = prep.combinedCompileFlags;
          linkFlags = linkFlags ++ prep.wrappedLibraryLinkFlags;
        };
      };

      wrapper = build.wrapper;
      targetOut = build.targetOut;
    in
    wrapper // {
      artifactType = "executable";
      inherit name libraries tools;
      target = targetOut;
      inherit toolchain;
      executablePath = "${targetOut}/${name}";
      compileCommands = build.compileCommands;
      sourceUnits = build.prep.normalizedSources;
      ninjaContent = build.ninjaContent;
      passthru = wrapper.passthru // {
        inherit toolchain;
        sourceUnits = build.prep.normalizedSources;
        ninjaContent = build.ninjaContent;
        compileCommands = build.compileCommands;
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
      publicLinkFlags ? [],
      ...
    }:
    let
      build = mkCompiledTarget {
        inherit name toolchain root sources includeDirs defines compileFlags languageFlags libraries tools;
        outputType = "staticLib";
        targetName = "${name}.a";
        buildNinjaContent = prep: ninja.generateStaticLib {
          inherit name toolchain languageFlags;
          sources = prep.normalizedSources;
          includeDirs = prep.resolvedIncludeDirs;
          defines = prep.combinedDefines;
          compileFlags = prep.combinedCompileFlags;
        };
      };

      rootHost = builtins.toString build.prep.rootPath;

      # Resolve public include directories (default to includeDirs if not specified)
      resolvedPublicIncludeDirs = if publicIncludeDirs == null then includeDirs else publicIncludeDirs;

      publicIncludeStores = map (dir:
        normalizeIncludeDir { inherit rootHost dir; }
      ) (ensureList resolvedPublicIncludeDirs);

      archiveName = "${name}.a";
      wrapper = build.wrapper;
      archiveOut = build.targetOut;

      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        compileFlags = publicCompileFlags;
        linkFlags = [ "${archiveOut}/${archiveName}" ] ++ publicLinkFlags;
      };

      combinedPublic = {
        includeDirs = build.prep.publicAggregate.includeDirs ++ basePublic.includeDirs;
        defines = build.prep.publicAggregate.defines ++ basePublic.defines;
        compileFlags = build.prep.publicAggregate.compileFlags ++ basePublic.compileFlags;
        linkFlags = basePublic.linkFlags;
      };
    in
    wrapper // {
      artifactType = "static";
      inherit name libraries tools;
      target = archiveOut;
      inherit toolchain;
      archivePath = "${archiveOut}/${archiveName}";
      public = combinedPublic;
      compileCommands = build.compileCommands;
      sourceUnits = build.prep.normalizedSources;
      ninjaContent = build.ninjaContent;
      passthru = wrapper.passthru // {
        inherit toolchain;
        sourceUnits = build.prep.normalizedSources;
        ninjaContent = build.ninjaContent;
        compileCommands = build.compileCommands;
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
      publicLinkFlags ? [],
      ...
    }:
    let
      sharedExtraCFlags =
        if builtins.elem "-fPIC" (toolchain.getPlatformCompileFlags or [ ])
        then [ ]
        else [ "-fPIC" ];

      build = mkCompiledTarget {
        inherit name toolchain root sources includeDirs defines compileFlags languageFlags libraries tools;
        outputType = "sharedLib";
        targetName = "${name}.so";
        includeLibraryInputs = true;
        extraCompileCommandsCFlags = sharedExtraCFlags;
        buildNinjaContent = prep: ninja.generateSharedLib {
          inherit name toolchain languageFlags;
          sources = prep.normalizedSources;
          includeDirs = prep.resolvedIncludeDirs;
          defines = prep.combinedDefines;
          compileFlags = prep.combinedCompileFlags;
          linkFlags = linkFlags ++ prep.wrappedLibraryLinkFlags;
        };
      };

      rootHost = builtins.toString build.prep.rootPath;

      # Resolve public include directories (default to includeDirs if not specified)
      resolvedPublicIncludeDirs = if publicIncludeDirs == null then includeDirs else publicIncludeDirs;

      publicIncludeStores = map (dir:
        normalizeIncludeDir { inherit rootHost dir; }
      ) (ensureList resolvedPublicIncludeDirs);

      wrapper = build.wrapper;
      sharedOut = build.targetOut;
      sharedLibPath = "${sharedOut}/${name}.so";

      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        compileFlags = publicCompileFlags;
        linkFlags = [ sharedLibPath ] ++ publicLinkFlags;
      };

      combinedPublic = {
        includeDirs = build.prep.publicAggregate.includeDirs ++ basePublic.includeDirs;
        defines = build.prep.publicAggregate.defines ++ basePublic.defines;
        compileFlags = build.prep.publicAggregate.compileFlags ++ basePublic.compileFlags;
        linkFlags = basePublic.linkFlags;
      };
    in
    wrapper // {
      artifactType = "shared";
      inherit name libraries tools;
      target = sharedOut;
      inherit toolchain;
      sharedLibrary = sharedLibPath;
      public = combinedPublic;
      compileCommands = build.compileCommands;
      sourceUnits = build.prep.normalizedSources;
      ninjaContent = build.ninjaContent;
      passthru = wrapper.passthru // {
        inherit toolchain;
        sourceUnits = build.prep.normalizedSources;
        ninjaContent = build.ninjaContent;
        compileCommands = build.compileCommands;
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
      publicLinkFlags ? [],
      tools ? [],
      ...
    }:
    let
      isHeaderFile = name: type:
        type == "regular" && language.isHeaderFile name;

      headersAndDirsFilter = name: type:
        type == "directory" || isHeaderFile name type;

      rootPath = builtins.path {
        path = root;
        name = "headers";
        filter = headersAndDirsFilter;
      };
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
        linkFlags = publicLinkFlags;
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
      target ? null,
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
        else if target != null then
          target.toolchain or target.passthru.toolchain or (throw "mkDevShell: target has no toolchain metadata; pass 'toolchain' explicitly")
        else
          throw "mkDevShell: provide either 'toolchain' or 'target'";

      compileCommands =
        if target == null then
          null
        else
          target.compileCommands or target.passthru.compileCommands or null;

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
      isNinjaBuilt = executable ? target || (executable ? passthru && executable.passthru ? target);

      stdinFile = if stdin != null then pkgs.writeText "stdin" stdin else null;
      escapedArgs = map lib.escapeShellArg args;

      # Ninja-built executable test
      # Get the executable name from the wrapper (strip .drv suffix if present)
      exeName = lib.removeSuffix ".drv" (executable.name or "unknown");
      ninjaTest = ninja.mkNinjaTest {
        inherit name args;
        target = executable.target or executable.passthru.target;
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
