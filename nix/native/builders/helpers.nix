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
  scanner,  # Tool processing
  ninja,    # nix-ninja integration
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
  inherit (scanner) processTools;

  # Collect ninja-built library derivations for dependency tracking
  # Returns list of wrapper derivations that need to be realized before linking
  collectLibraryInputs = libs:
    let
      collectFromLib = lib:
        if builtins.isAttrs lib then
          # Check if this is a ninja-built library (has passthru.target)
          if lib ? passthru && lib.passthru ? target then
            [ lib ] ++ (if lib ? libraries then collectLibraryInputs lib.libraries else [])
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
  # Returns: { store, relNorm, objectName, lang }
  normalizeSourceForNinja = { root, source }:
    let
      rootPath = sanitizePath { path = root; };
      rootStr = builtins.toString rootPath;

      # Handle different source formats
      srcInfo =
        if builtins.isString source then
          { rel = source; path = rootPath + "/${source}"; store = null; }
        else if builtins.isPath source then
          let
            pathStr = builtins.toString source;
            rel = if hasPrefix rootStr pathStr
              then removePrefix (rootStr + "/") pathStr
              else builtins.baseNameOf pathStr;
          in
          { inherit rel; path = source; store = null; }
        else if source ? rel then
          { rel = source.rel; path = source.path or (rootPath + "/${source.rel}"); store = source.store or null; }
        else
          throw "Invalid source format: ${builtins.toJSON source}";

      relNorm = if hasPrefix "./" srcInfo.rel
        then removePrefix "./" srcInfo.rel
        else srcInfo.rel;

      lang = detectLanguage relNorm;
      objectName = sanitizeName (lib.removeSuffix ".${lib.last (lib.splitString "." relNorm)}" relNorm) + ".o";

      # For tool-generated sources, extract the store base from the full path
      # by removing the relative path suffix
      storeBase =
        if srcInfo.store != null then
          let
            pathStr = builtins.toString srcInfo.path;
            # Remove the relative path suffix to get the store directory
            # e.g., "/nix/store/xxx/generated/foo.cc" - "generated/foo.cc" = "/nix/store/xxx"
            storeDir = lib.removeSuffix "/${relNorm}" pathStr;
          in
          storeDir
        else
          rootPath;
    in
    {
      store = storeBase;
      inherit relNorm objectName lang;
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

in
rec {
  # ==========================================================================
  # Executable Builder
  # ==========================================================================

  # Build an executable from C/C++ sources
  #
  # Arguments:
  #   name         - Target name (becomes executable name)
  #   toolchain    - Toolchain from mkToolchain
  #   root         - Source root directory
  #   sources      - List of source files
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   flags        - Abstract flags (lto, sanitizers, etc.)
  #   compileFlags - Raw compile flags (all languages)
  #   langFlags    - Per-language raw flags { c = [...]; cpp = [...]; }
  #   ldflags      - Additional linker flags
  #   libraries    - Library dependencies
  #   tools        - Tool plugins
  #
  mkExecutable =
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
      libraries ? [],
      tools ? [],
      ...
    }@args:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };

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

      # Translate abstract flags to concrete compiler flags
      translatedFlags = if flags != [] then tc.translateFlags flags else [];

      # Some flags (sanitizers, coverage, LTO) need to be passed to both compiler and linker
      # Extract these from the abstract flags for linking
      linkRequiredFlags = lib.concatMap (flag:
        if flag.type == "sanitizer" then [ "-fsanitize=${flag.value}" ]
        else if flag.type == "coverage" then [ "--coverage" ]
        else if flag.type == "lto" then
          if flag.value == "thin" then [ "-flto=thin" ]
          else [ "-flto" ]
        else []
      ) flags;

      # Combine compile flags
      combinedCompileFlags = translatedFlags ++ compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Collect legacy link flags (for external libs like pkg-config)
      legacyLinkFlags = collectLinkFlags libraries;

      # ----- NINJA PATH (when nix-ninja is available) -----
      ninjaResult = let
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

        # Generate ninja file content
        ninjaContent = ninja.generateExecutable {
          inherit name toolchain;
          sources = normalizedSources;
          includeDirs = resolvedIncludeDirs;
          defines = combinedDefines;
          compileFlags = combinedCompileFlags;
          inherit langFlags;
          ldflags = linkRequiredFlags ++ ldflags ++ legacyLinkFlags;
        };

        # Collect library wrapper derivations for dependency tracking
        libraryInputs = collectLibraryInputs libraries;

        # Create wrapper derivation
        wrapper = ninja.mkNinjaDerivation {
          inherit name ninjaContent libraryInputs;
          target = name;
          sourceInputs = [ rootPath ];
          toolInputs = tc.runtimeInputs;
          outputType = "executable";
        };

        # The actual target output (accessed via dynamic derivation output)
        targetOut = wrapper.passthru.target;
      in
      # Return the wrapper derivation with extra attributes merged in
      wrapper // {
        artifactType = "executable";
        inherit name;
        # The target output path (via dynamic derivation)
        out = targetOut;
        executablePath = "${targetOut}/bin/${name}";
        objectRefs = [];  # Not tracked with ninja
        compileCommands = null;
        passthru = wrapper.passthru // {
          inherit toolchain;
          wrappers = [];
          tus = normalizedSources;
          inherit libraries tools;
          ninjaContent = ninjaContent;
        };
      };
    in
    ninjaResult;

  # ==========================================================================
  # Static Library Builder
  # ==========================================================================

  # Build a static library from C/C++ sources
  #
  # With ninja: Produces a .a archive directly.
  # With dynamic: Objects are compiled and objectRefs exposed for consumers.
  #
  mkStaticLib =
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
      libraries ? [],
      tools ? [],
      publicIncludeDirs ? null,  # Defaults to includeDirs if not specified
      publicDefines ? [],
      publicCxxFlags ? [],
      ...
    }@args:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;

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

      # Translate abstract flags to concrete compiler flags
      translatedFlags = if flags != [] then tc.translateFlags flags else [];

      # Combine compile flags
      combinedCompileFlags = translatedFlags ++ compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Resolve public include directories (default to includeDirs if not specified)
      resolvedPublicIncludeDirs = if publicIncludeDirs == null then includeDirs else publicIncludeDirs;

      # Normalize public include directories
      publicIncludeStores = map (
        dir:
        normalizeIncludeDir {
          inherit rootHost;
          inherit dir;
        }
      ) (ensureList resolvedPublicIncludeDirs);

      # ----- NINJA PATH -----
      ninjaResult = let
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

        archiveName = "lib${name}.a";

        # Generate ninja file content
        ninjaContent = ninja.generateStaticLib {
          inherit name toolchain;
          sources = normalizedSources;
          includeDirs = resolvedIncludeDirs;
          defines = combinedDefines;
          compileFlags = combinedCompileFlags;
          inherit langFlags;
        };

        # Create wrapper derivation
        wrapper = ninja.mkNinjaDerivation {
          inherit name ninjaContent;
          target = archiveName;
          sourceInputs = [ rootPath ];
          toolInputs = tc.runtimeInputs;
          outputType = "staticLib";
        };

        # The actual archive output (accessed via dynamic derivation output)
        archiveOut = wrapper.passthru.target;

        # Build public interface with archive path
        basePublic = {
          includeDirs = map (dir: { path = dir; }) publicIncludeStores;
          defines = publicDefines;
          cxxFlags = publicCxxFlags;
          linkFlags = [ "${archiveOut}/${archiveName}" ];
        };

        combinedPublic = {
          includeDirs = publicAggregate.includeDirs ++ basePublic.includeDirs;
          defines = publicAggregate.defines ++ basePublic.defines;
          cxxFlags = publicAggregate.cxxFlags ++ basePublic.cxxFlags;
          linkFlags = basePublic.linkFlags;
        };
      in
      wrapper // {
        artifactType = "static";
        inherit name;
        out = archiveOut;
        archivePath = "${archiveOut}/${archiveName}";
        objectRefs = [];  # Not tracked with ninja - use archivePath instead
        inherit libraries tools;
        public = combinedPublic;
        compileCommands = null;
        passthru = wrapper.passthru // {
          inherit toolchain;
          wrappers = [];
          tus = normalizedSources;
          ninjaContent = ninjaContent;
        };
      };
    in
    ninjaResult;

  # ==========================================================================
  # Static Archive Builder
  # ==========================================================================

  # Create a static archive (.a) from a static library
  #
  # With nix-ninja, mkStaticLib already produces an archive, so this is a pass-through.
  #
  mkArchive =
    {
      lib,
      name ? lib.name,
    }:
    let
      archiveName = "lib${sanitizeName name}.a";
    in
    # Library already has an archive, just return it with archive interface
    lib // {
      artifactType = "archive";
      inherit name archiveName;
      headers = lib;
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
      flags ? [],
      compileFlags ? [],
      langFlags ? {},
      ldflags ? [],
      libraries ? [],
      tools ? [],
      publicIncludeDirs ? null,  # Defaults to includeDirs if not specified
      publicDefines ? [],
      publicCxxFlags ? [],
      ...
    }@args:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;

      targetPlatform = tc.targetPlatform;

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

      # Translate abstract flags to concrete compiler flags
      translatedFlags = if flags != [] then tc.translateFlags flags else [];

      # Some flags (sanitizers, coverage, LTO) need to be passed to both compiler and linker
      linkRequiredFlags = lib.concatMap (flag:
        if flag.type == "sanitizer" then [ "-fsanitize=${flag.value}" ]
        else if flag.type == "coverage" then [ "--coverage" ]
        else if flag.type == "lto" then
          if flag.value == "thin" then [ "-flto=thin" ]
          else [ "-flto" ]
        else []
      ) flags;

      # Combine compile flags
      combinedCompileFlags = translatedFlags ++ compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Collect legacy link flags from library dependencies
      legacyLinkFlags = collectLinkFlags libraries;

      # Resolve public include directories (default to includeDirs if not specified)
      resolvedPublicIncludeDirs = if publicIncludeDirs == null then includeDirs else publicIncludeDirs;

      # Normalize public include directories
      publicIncludeStores = map (
        dir:
        normalizeIncludeDir {
          inherit rootHost;
          inherit dir;
        }
      ) (ensureList resolvedPublicIncludeDirs);

      # Shared library name
      sharedName = "lib${name}.so";

      # ----- NINJA PATH -----
      ninjaResult = let
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

        # Generate ninja file content
        ninjaContent = ninja.generateSharedLib {
          inherit name toolchain;
          sources = normalizedSources;
          includeDirs = resolvedIncludeDirs;
          defines = combinedDefines;
          compileFlags = combinedCompileFlags;
          inherit langFlags;
          ldflags = linkRequiredFlags ++ ldflags ++ legacyLinkFlags;
        };

        # Collect library wrapper derivations for dependency tracking
        libraryInputs = collectLibraryInputs libraries;

        # Create wrapper derivation
        wrapper = ninja.mkNinjaDerivation {
          inherit name ninjaContent libraryInputs;
          target = sharedName;
          sourceInputs = [ rootPath ];
          toolInputs = tc.runtimeInputs;
          outputType = "sharedLib";
        };

        # The actual shared lib output (accessed via dynamic derivation output)
        sharedOut = wrapper.passthru.target;
        sharedLibPath = "${sharedOut}/${sharedName}";

        # Build public interface with shared lib path
        basePublic = {
          includeDirs = map (dir: { path = dir; }) publicIncludeStores;
          defines = publicDefines;
          cxxFlags = publicCxxFlags;
          linkFlags = [ sharedLibPath ];
        };

        combinedPublic = {
          includeDirs = publicAggregate.includeDirs ++ basePublic.includeDirs;
          defines = publicAggregate.defines ++ basePublic.defines;
          cxxFlags = publicAggregate.cxxFlags ++ basePublic.cxxFlags;
          linkFlags = basePublic.linkFlags;
        };
      in
      wrapper // {
        artifactType = "shared";
        inherit name;
        out = sharedOut;
        sharedLibrary = sharedLibPath;
        objectRefs = [];  # Not tracked with ninja
        inherit libraries tools;
        public = combinedPublic;
        compileCommands = null;
        passthru = wrapper.passthru // {
          inherit toolchain;
          wrappers = [];
          tus = normalizedSources;
          ninjaContent = ninjaContent;
        };
      };
    in
    ninjaResult;

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
      cxxFlags ? [],
      libraries ? [],
      publicIncludeDirs ? null,  # Defaults to includeDirs if not specified
      publicDefines ? [],
      publicCxxFlags ? [],
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
        cxxFlags = publicCxxFlags;
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
