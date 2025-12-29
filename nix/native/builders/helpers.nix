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
    in
    linked.drv // {
      artifactType = "executable";
      inherit name;
      out = linked.out;
      executablePath = linked.executablePath;
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

      archiveName = "lib${sanitizeName name}.a";

    in
    if hasObjectRefs then
      # Dynamic derivations path - return archive wrapper directly
      # NOTE: For dynamic derivations, the actual archive is built when
      # the wrapper is built. Use the wrapper's output to get the archive.
      let
        archiveWrapper = mkArchiveWrapper {
          inherit name objectRefs;
          toolchain = tc;
        };
      in
      archiveWrapper.drv // {
        artifactType = "archive";
        inherit name archiveName;
        # Store the wrapper for dynamic output access
        archiveWrapper = archiveWrapper;
        # Headers come from the original lib
        headers = lib;
        # Public interface (can't use dynamic paths here)
        public = lib.public;
        passthru = {
          toolchain = tc;
          inherit archiveWrapper;
        };
      }
    else
      # Legacy fallback for non-dynamic derivations
      let
        objects = lib.objectPaths or lib.passthru.objectPaths or [];
        archiveDrv = createStaticArchive {
          toolchain = tc;
          inherit name objects;
        };

        # Combine archive with headers from original lib
        archive = pkgs.runCommand "archive-${name}" {} ''
          set -euo pipefail
          mkdir -p "$out/lib" "$out/include"
          cp -r ${archiveDrv}/lib/* "$out/lib/" 2>/dev/null || true
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

      # Install headers only (separate from linked output)
      installHeaders = concatStringsSep "\n" (
        map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores
      );

      headersDrv = pkgs.runCommand "shared-${name}-headers" { } ''
        set -euo pipefail
        mkdir -p "$out/include"
        ${installHeaders}
      '';

      # Build public interface
      # NOTE: linkFlags uses the placeholder path from linked.sharedLibPath
      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        cxxFlags = publicCxxFlags;
        linkFlags = [ linked.sharedLibPath ];
      };

      # Merge headers/defines/cxxFlags from dependencies
      combinedPublic = {
        includeDirs = publicAggregate.includeDirs ++ basePublic.includeDirs;
        defines = publicAggregate.defines ++ basePublic.defines;
        cxxFlags = publicAggregate.cxxFlags ++ basePublic.cxxFlags;
        linkFlags = basePublic.linkFlags;
      };
    in
    # Return link wrapper directly (like mkExecutable)
    linked.drv // {
      artifactType = "shared";
      inherit name;
      out = linked.out;
      sharedLibrary = linked.sharedLibPath;
      inherit (compileSet) objectRefs;
      inherit libraries tools;
      public = combinedPublic;
      headers = headersDrv;
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
  # For dynamic derivations (executables built with mkExecutable), this creates
  # a test wrapper that properly depends on the link output via dynamicOutputs.
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
      # Check if this is a dynamic derivation executable
      isDynamic = executable ? passthru && executable.passthru ? wrappers;

      stdinFile = if stdin != null then pkgs.writeText "stdin" stdin else null;
      escapedArgs = map lib.escapeShellArg args;

      # Scripts directory for dynamic test generation
      scriptsDir = ../dynamic/scripts;

      # Dynamic derivation test wrapper
      dynamicTest = let
        tc = executable.passthru.toolchain;
        execName = executable.name;
        linkWrapperDrv = builtins.unsafeDiscardStringContext executable.drvPath;

        testConfig = {
          bashPath = "${pkgs.bash}/bin/bash";
          coreutilsPath = "${pkgs.coreutils}";
          gccLibPath = "${pkgs.stdenv.cc.cc.lib}";
          inherit args;
          expectedOutput = expectedOutput;
          stdinPath = if stdin != null then "${stdinFile}" else null;
        };

        testConfigJson = builtins.toJSON testConfig;

        nixPackage = pkgs.nix;

        wrapper = pkgs.stdenv.mkDerivation {
          name = "test-${name}.drv";

          __contentAddressed = true;
          outputHashMode = "text";
          outputHashAlgo = "sha256";

          requiredSystemFeatures = [ "recursive-nix" ];

          nativeBuildInputs = [
            nixPackage
            pkgs.python3
            pkgs.coreutils
            pkgs.bash
          ];

          inherit testConfigJson;
          passAsFile = [ "testConfigJson" ];

          NIX_BIN = "${nixPackage}/bin/nix";
          NIX_CONFIG = ''
            extra-experimental-features = nix-command ca-derivations dynamic-derivations
          '';

          dontUnpack = true;
          dontConfigure = true;
          dontInstall = true;
          dontFixup = true;

          buildPhase = ''
            runHook preBuild

            python3 ${scriptsDir}/generate-test-drv.py \
              --name "${name}" \
              --link-wrapper-drv "${linkWrapperDrv}" \
              --exec-name "${execName}" \
              --test-config "$testConfigJsonPath" \
              --system "${pkgs.stdenv.hostPlatform.system}" \
              --output "$TMPDIR/test.json"

            drv_path=$($NIX_BIN derivation add < "$TMPDIR/test.json")
            echo "Created test derivation: $drv_path" >&2

            cp "$drv_path" "$out"

            runHook postBuild
          '';
        };

        # Reference to the test output
        testOut = builtins.outputOf
          (builtins.unsafeDiscardOutputDependency wrapper.outPath)
          "out";
      in
      wrapper // {
        out = testOut;
        passthru = { inherit executable; };
      };

      # Traditional runCommand test for non-dynamic executables
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
    if isDynamic then dynamicTest else traditionalTest;
}
