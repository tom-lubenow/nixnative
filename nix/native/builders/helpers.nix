# High-level build helpers for nixnative
#
# These functions provide the primary API for building C/C++ targets.
# They use mkBuildContext internally and produce ready-to-use derivations.
#
{ pkgs, lib, utils, context, link }:

let
  inherit (lib) concatStringsSep optional;
  inherit (utils)
    sanitizeName
    normalizeIncludeDir
    mergePublic
    ensureList;
  inherit (context) mkBuildContext;
  inherit (link)
    linkExecutable
    linkSharedLibrary
    createStaticArchive;

in rec {
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
  #   extraCxxFlags - Additional raw C++ flags
  #   ldflags      - Additional linker flags
  #   libraries    - Library dependencies
  #   tools        - Tool plugins
  #   depsManifest - Pre-computed dependency manifest
  #   scanner      - Custom scanner
  #
  mkExecutable = args:
    let
      ctx = mkBuildContext args;
      inherit (ctx) toolchain name objectPaths flags combinedExtraCxxFlags publicAggregate;

      drv = linkExecutable {
        inherit toolchain name flags;
        objects = objectPaths;
        extraCxxFlags = combinedExtraCxxFlags;
        ldflags = args.ldflags or [];
        linkFlags = publicAggregate.linkFlags;
      };
    in
    drv // {
      artifactType = "executable";
      inherit name;
      executablePath = "${drv}/bin/${name}";
      passthru = (drv.passthru or {}) // ctx;
    };

  # ==========================================================================
  # Static Library Builder
  # ==========================================================================

  # Build a static library (.a) from C/C++ sources
  #
  # Additional arguments:
  #   publicIncludeDirs - Headers to expose to consumers
  #   publicDefines     - Defines to propagate to consumers
  #   publicCxxFlags    - C++ flags to propagate to consumers
  #
  mkStaticLib = args:
    let
      ctx = mkBuildContext args;
      inherit (ctx) toolchain name rootPath publicAggregate objectPaths;

      # Public interface for consumers
      publicIncludeDirs = args.publicIncludeDirs or args.includeDirs or [];
      publicDefines = args.publicDefines or [];
      publicCxxFlags = args.publicCxxFlags or [];

      rootHost = builtins.toString rootPath;

      # Normalize public include directories
      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; inherit dir; })
          (ensureList publicIncludeDirs);

      # Create the archive
      archiveDrv = createStaticArchive {
        inherit toolchain name;
        objects = objectPaths;
      };

      archiveName = "lib${sanitizeName name}.a";

      # Install headers
      installHeaders = concatStringsSep "\n"
        (map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores);

      # Combine archive + headers
      archive =
        pkgs.runCommand "static-${name}"
          {}
          ''
            set -euo pipefail
            mkdir -p "$out/lib" "$out/include"
            cp ${archiveDrv}/lib/${archiveName} "$out/lib/"
            ${installHeaders}
          '';

      # Build public interface
      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        cxxFlags = publicCxxFlags;
        linkFlags = [ "${archive}/lib/${archiveName}" ];
      };

      combinedPublic = mergePublic publicAggregate basePublic;
    in
    archive // {
      artifactType = "static";
      inherit name;
      archivePath = "${archive}/lib/${archiveName}";
      inherit (ctx) objectInfos compileCommands manifest libraries tools;
      public = combinedPublic;
      passthru = (archive.passthru or {}) // ctx;
    };

  # ==========================================================================
  # Shared Library Builder
  # ==========================================================================

  # Build a shared library (.so/.dylib) from C/C++ sources
  #
  mkSharedLib = args:
    let
      ctx = mkBuildContext args;
      inherit (ctx) toolchain name rootPath publicAggregate objectPaths flags combinedExtraCxxFlags;

      targetPlatform = toolchain.targetPlatform;

      # Public interface for consumers
      publicIncludeDirs = args.publicIncludeDirs or args.includeDirs or [];
      publicDefines = args.publicDefines or [];
      publicCxxFlags = args.publicCxxFlags or [];

      rootHost = builtins.toString rootPath;

      # Normalize public include directories
      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; inherit dir; })
          (ensureList publicIncludeDirs);

      # Determine shared library name
      sharedExt = if targetPlatform.isDarwin then "dylib" else "so";
      sharedName = "lib${name}.${sharedExt}";

      # Link the shared library
      linkDrv = linkSharedLibrary {
        inherit toolchain name flags;
        objects = objectPaths;
        extraCxxFlags = combinedExtraCxxFlags;
        ldflags = args.ldflags or [];
        linkFlags = publicAggregate.linkFlags;
      };

      # Install headers
      installHeaders = concatStringsSep "\n"
        (map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores);

      # Combine link output + headers
      sharedDrv =
        pkgs.runCommand "shared-${name}"
          {}
          ''
            set -euo pipefail
            mkdir -p "$out/lib" "$out/include"
            cp ${linkDrv}/lib/${sharedName} "$out/lib/"
            ${installHeaders}
          '';

      # Build public interface
      basePublic = {
        includeDirs = map (dir: { path = dir; }) publicIncludeStores;
        defines = publicDefines;
        cxxFlags = publicCxxFlags;
        linkFlags = [ "${sharedDrv}/lib/${sharedName}" ];
      };

      combinedPublic = mergePublic publicAggregate basePublic;
    in
    sharedDrv // {
      artifactType = "shared";
      inherit name;
      sharedLibrary = "${sharedDrv}/lib/${sharedName}";
      inherit (ctx) objectInfos compileCommands manifest libraries tools;
      public = combinedPublic;
      passthru = (sharedDrv.passthru or {}) // ctx;
    };

  # ==========================================================================
  # Header-Only Library
  # ==========================================================================

  # Create a header-only library (no compilation)
  #
  mkHeaderOnly =
    { name
    , root ? ./.
    , includeDirs ? []
    , defines ? []
    , cxxFlags ? []
    , libraries ? []
    , publicIncludeDirs ? includeDirs
    , publicDefines ? []
    , publicCxxFlags ? []
    , tools ? []
    }:
    let
      rootPath = utils.sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;

      # Process tools for generated headers
      toolInfo = utils.processTools or (_: { public = utils.emptyPublic; }) tools;
      libsPublic = utils.collectPublic libraries;
      publicAggregate = mergePublic libsPublic (toolInfo.public or utils.emptyPublic);

      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; inherit dir; })
          (ensureList publicIncludeDirs);

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
    };

  # ==========================================================================
  # Development Shell
  # ==========================================================================

  # Create a development shell for a target
  #
  mkDevShell =
    { target
    , toolchain ? null
    , extraPackages ? []
    , linkCompileCommands ? true
    , symlinkName ? "compile_commands.json"
    , includeTools ? true
    }:
    let
      tc =
        if toolchain != null then toolchain
        else target.passthru.toolchain or (throw "mkDevShell: no toolchain provided or found in target");

      compileCommands = target.passthru.compileCommands or null;

      # Include common development tools
      devTools =
        if includeTools then [
          pkgs.clang-tools
          (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
        ]
        else [];

      packages = lib.unique (
        tc.runtimeInputs
        ++ (if tc.compiler.package != null then [ tc.compiler.package ] else [])
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
        export CC="${tc.getCC}"
        export CXX="${tc.getCXX}"
        ${envExports}
      '';
    };

  # ==========================================================================
  # Test Runner
  # ==========================================================================

  # Create a test derivation that runs an executable
  #
  mkTest =
    { name
    , executable
    , args ? []
    , stdin ? null
    , expectedOutput ? null
    }:
    let
      stdinFile = if stdin != null then pkgs.writeText "stdin" stdin else null;
      escapedArgs = map lib.escapeShellArg args;
      expectedOutputFile = if expectedOutput != null
        then pkgs.writeText "expected-output" expectedOutput
        else null;
    in
    pkgs.runCommand "test-${name}"
      {
        nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.findutils ];
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

        ${if expectedOutput != null then ''
          expected=$(cat ${expectedOutputFile})
          if ! grep -qF "$expected" output.log; then
            echo "Test failed: Expected output not found."
            echo "Expected: $expected"
            exit 1
          fi
        '' else ""}

        cp output.log $out/test.log
      '';
}
