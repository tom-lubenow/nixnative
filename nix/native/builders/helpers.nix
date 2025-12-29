# High-level build helpers for nixnative
#
# These functions provide the primary API for building C/C++ targets.
# They use the dynamic compilation primitives and produce ready-to-use derivations.
#
{
  pkgs,
  lib,
  utils,
  link,
  platform,
  scanner,  # Tool processing
  dynamic,  # Dynamic compilation module (required)
}:

let
  inherit (lib) concatStringsSep;
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
    ;
  inherit (scanner) processTools;
  inherit (dynamic)
    mkCompileSet
    mkLinkWrapper
    mkArchiveWrapper
    ;
  inherit (link) createStaticArchive;

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

      # Combine compile flags
      combinedCompileFlags = compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Compile own sources
      compileSet = mkCompileSet {
        inherit name root toolchain flags;
        sources = allSources;
        includeDirs = combinedIncludeDirs;
        defines = combinedDefines;
        compileFlags = combinedCompileFlags;
        inherit langFlags;
        headerOverrides = toolInfo.headerOverrides;
        sourceOverrides = toolInfo.sourceOverrides;
        extraInputs = toolInfo.evalInputs;
      };

      # Collect object refs from libraries
      libObjectRefs = collectObjectRefs libraries;

      # Collect legacy link flags (for external libs like pkg-config)
      legacyLinkFlags = collectLinkFlags libraries;

      # All object references (own + from libraries)
      allObjectRefs = compileSet.objectRefs ++ libObjectRefs;

      # Link into executable
      linked = mkLinkWrapper {
        inherit name toolchain flags;
        objectRefs = allObjectRefs;
        outputType = "executable";
        inherit ldflags;
        linkFlags = legacyLinkFlags;
      };

      # Create a derivation that wraps the linked output
      drv = pkgs.runCommand name {
        linkedOutput = linked.out;
      } ''
        mkdir -p $out
        cp -r "$linkedOutput"/* $out/
      '';
    in
    drv // {
      artifactType = "executable";
      inherit name;
      executablePath = "${drv}/bin/${name}";
      inherit (compileSet) objectRefs;
      compileCommands = null;  # TODO: generate at build time
      passthru = {
        inherit toolchain;
        inherit (compileSet) wrappers tus;
        inherit libraries tools;
      };
    };

  # ==========================================================================
  # Static Library Builder
  # ==========================================================================

  # Build a static library from C/C++ sources
  #
  # Objects are compiled but NOT linked. The objectRefs are exposed for
  # consumers (executables, shared libs) to collect and link.
  #
  # Use mkArchive if you need an actual .a archive file.
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
      publicIncludeDirs ? [],
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

      # Combine compile flags
      combinedCompileFlags = compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Compile sources (NO linking!)
      compileSet = mkCompileSet {
        inherit name root toolchain flags;
        sources = allSources;
        includeDirs = combinedIncludeDirs;
        defines = combinedDefines;
        compileFlags = combinedCompileFlags;
        inherit langFlags;
        headerOverrides = toolInfo.headerOverrides;
        sourceOverrides = toolInfo.sourceOverrides;
        extraInputs = toolInfo.evalInputs;
      };

      # Normalize public include directories
      publicIncludeStores = map (
        dir:
        normalizeIncludeDir {
          inherit rootHost;
          inherit dir;
        }
      ) (ensureList publicIncludeDirs);

      # Install headers only (no archive - objects are passed via objectRefs)
      installHeaders = concatStringsSep "\n" (
        map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores
      );

      headersDrv = pkgs.runCommand "lib-${name}" { } ''
        set -euo pipefail
        mkdir -p "$out/include"
        ${installHeaders}
      '';

      # Build public interface
      # NOTE: linkFlags is EMPTY - consumers get objects via objectRefs
      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        cxxFlags = publicCxxFlags;
        linkFlags = [];  # No linkFlags - use objectRefs instead
      };

      # Merge headers/defines/cxxFlags from dependencies
      combinedPublic = {
        includeDirs = publicAggregate.includeDirs ++ basePublic.includeDirs;
        defines = publicAggregate.defines ++ basePublic.defines;
        cxxFlags = publicAggregate.cxxFlags ++ basePublic.cxxFlags;
        linkFlags = [];  # Consumers use objectRefs
      };
    in
    headersDrv // {
      artifactType = "static";
      inherit name;

      # Expose object references for consumers
      inherit (compileSet) objectRefs;

      # Keep reference to libraries for transitive dependency resolution
      inherit libraries tools;

      public = combinedPublic;
      compileCommands = null;  # TODO: generate at build time
      passthru = {
        inherit toolchain;
        inherit (compileSet) wrappers tus;
      };
    };

  # ==========================================================================
  # Static Archive Builder
  # ==========================================================================

  # Create a static archive (.a) from a static library
  #
  # Use this when you need an actual .a file for:
  # - External distribution/installation
  # - Traditional archive link semantics (selective object inclusion)
  #
  mkArchive =
    {
      lib,
      name ? lib.name,
    }:
    let
      tc = lib.passthru.toolchain;

      # Get objectRefs from the library
      objectRefs = lib.objectRefs or [];

      # If no objectRefs, fall back to legacy objectPaths
      hasObjectRefs = objectRefs != [];

      # Create archive using new primitive or legacy method
      archiveResult =
        if hasObjectRefs then
          mkArchiveWrapper {
            inherit name objectRefs;
            toolchain = tc;
          }
        else
          # Legacy fallback
          let
            objects = lib.objectPaths or lib.passthru.objectPaths or [];
            archiveDrv = createStaticArchive {
              toolchain = tc;
              inherit name objects;
            };
          in {
            drv = archiveDrv;
            archivePath = "${archiveDrv}/lib/lib${sanitizeName name}.a";
          };

      archiveName = "lib${sanitizeName name}.a";

      # Combine archive with headers from original lib
      archive = pkgs.runCommand "archive-${name}" {
        archiveOutput = archiveResult.out or archiveResult.archivePath;
      } ''
        set -euo pipefail
        mkdir -p "$out/lib" "$out/include"
        if [ -d "$archiveOutput" ]; then
          cp -r "$archiveOutput"/lib/* "$out/lib/" 2>/dev/null || true
        else
          cp "$archiveOutput" "$out/lib/${archiveName}"
        fi
        cp -r ${lib}/include/. $out/include/ 2>/dev/null || true
      '';
    in
    archive // {
      artifactType = "archive";
      inherit name;
      archivePath = "${archive}/lib/${archiveName}";
      public = lib.public // {
        linkFlags = [ "${archive}/lib/${archiveName}" ];
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
      flags ? [],
      compileFlags ? [],
      langFlags ? {},
      ldflags ? [],
      libraries ? [],
      tools ? [],
      publicIncludeDirs ? [],
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

      # Combine compile flags
      combinedCompileFlags = compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Compile sources
      compileSet = mkCompileSet {
        inherit name root toolchain flags;
        sources = allSources;
        includeDirs = combinedIncludeDirs;
        defines = combinedDefines;
        compileFlags = combinedCompileFlags;
        inherit langFlags;
        headerOverrides = toolInfo.headerOverrides;
        sourceOverrides = toolInfo.sourceOverrides;
        extraInputs = toolInfo.evalInputs;
      };

      # Collect object refs from libraries
      libObjectRefs = collectObjectRefs libraries;

      # Collect legacy link flags
      legacyLinkFlags = collectLinkFlags libraries;

      # All object references (own + from libraries)
      allObjectRefs = compileSet.objectRefs ++ libObjectRefs;

      # Link into shared library
      linked = mkLinkWrapper {
        inherit name toolchain flags;
        objectRefs = allObjectRefs;
        outputType = "sharedLibrary";
        inherit ldflags;
        linkFlags = legacyLinkFlags;
      };

      # Determine shared library name
      sharedExt = builtins.substring 1 100 (platform.sharedLibExtension targetPlatform);
      sharedName = "lib${name}.${sharedExt}";

      # Normalize public include directories
      publicIncludeStores = map (
        dir:
        normalizeIncludeDir {
          inherit rootHost;
          inherit dir;
        }
      ) (ensureList publicIncludeDirs);

      # Install headers
      installHeaders = concatStringsSep "\n" (
        map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores
      );

      # Combine link output + headers
      sharedDrv = pkgs.runCommand "shared-${name}" {
        linkedOutput = linked.out;
      } ''
        set -euo pipefail
        mkdir -p "$out/lib" "$out/include"
        cp -r "$linkedOutput"/lib/* "$out/lib/" 2>/dev/null || true
        ${installHeaders}
      '';

      # Build public interface
      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        cxxFlags = publicCxxFlags;
        linkFlags = [ "${sharedDrv}/lib/${sharedName}" ];
      };

      # Merge headers/defines/cxxFlags from dependencies
      combinedPublic = {
        includeDirs = publicAggregate.includeDirs ++ basePublic.includeDirs;
        defines = publicAggregate.defines ++ basePublic.defines;
        cxxFlags = publicAggregate.cxxFlags ++ basePublic.cxxFlags;
        linkFlags = basePublic.linkFlags;
      };
    in
    sharedDrv // {
      artifactType = "shared";
      inherit name;
      sharedLibrary = "${sharedDrv}/lib/${sharedName}";
      inherit (compileSet) objectRefs;
      inherit libraries tools;
      public = combinedPublic;
      compileCommands = null;
      passthru = {
        inherit toolchain;
        inherit (compileSet) wrappers tus;
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
      cxxFlags ? [],
      libraries ? [],
      publicIncludeDirs ? [],
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

      publicIncludeStores = map (
        dir:
        normalizeIncludeDir {
          inherit rootHost;
          inherit dir;
        }
      ) (ensureList publicIncludeDirs);

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
  mkTest =
    {
      name,
      executable,
      args ? [],
      stdin ? null,
      expectedOutput ? null,
    }:
    let
      stdinFile = if stdin != null then pkgs.writeText "stdin" stdin else null;
      escapedArgs = map lib.escapeShellArg args;
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

        # Locate the executable binary
        BIN=$(find ${executable}/bin -type f -executable | head -n 1)
        if [ -z "$BIN" ]; then
          echo "Error: No executable found in ${executable}/bin"
          exit 1
        fi

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
}
