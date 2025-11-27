{ pkgs, lib, utils, clangToolchain, scanner }:
let
  inherit (lib) concatStringsSep ensureList escapeShellArg;
  inherit (utils)
    sanitizeName
    sanitizePath
    toPathLike
    normalizeIncludeDir
    emptyPublic
    mergePublic
    collectPublic
    normalizeSources
    headerSet
    mkSourceTree
    toIncludeFlags
    toDefineFlags
    validatePublic
    showValue;
  inherit (scanner)
    mkManifest
    emptyManifest
    mergeManifests
    processGenerators
    mkDependencyScanner;

  # ==========================================================================
  # Shared link step helper (consolidates duplicate link logic)
  # ==========================================================================
  mkLinkStep =
    { toolchain
    , name
    , objects
    , cxxFlags
    , ldflags
    , linkFlags
    , outputDir ? "bin"
    , outputName ? name
    , extraFlags ? [ ]  # e.g. [ "-shared" ] for shared libs
    , targetPlatform ? pkgs.stdenv.targetPlatform  # Use target, not host, for cross-compilation
    }:
    let
      tc = toolchain;
      # Use target platform for linker flag decisions (correct for cross-compilation)
      groupedLinkFlags =
        if targetPlatform.isLinux
        then [ "-Wl,--start-group" ] ++ linkFlags ++ [ "-Wl,--end-group" ]
        else linkFlags;
      finalLinkFlags = tc.defaultLdFlags ++ ldflags ++ groupedLinkFlags;
      envAttrs = tc.environment;
    in
    pkgs.runCommand name
      ({
        buildInputs = tc.runtimeInputs;
      } // envAttrs)
      ''
        set -euo pipefail
        mkdir -p "$out/${outputDir}"
        ${tc.cxx} \
          ${concatStringsSep " " extraFlags} \
          ${concatStringsSep " " tc.defaultCxxFlags} \
          ${concatStringsSep " " cxxFlags} \
          ${concatStringsSep " " objects} \
          ${concatStringsSep " " finalLinkFlags} \
          -o "$out/${outputDir}/${outputName}"
      '';

  # ==========================================================================
  # Optimization and sanitizer flag helpers
  # ==========================================================================

  # Build LTO flags based on mode
  ltoFlags = mode:
    if mode == "thin" then [ "-flto=thin" ]
    else if mode == "full" then [ "-flto" ]
    else if mode == true then [ "-flto=thin" ]  # default to thin LTO
    else [ ];

  # Build sanitizer flags
  sanitizerFlags = sanitizers:
    let
      validSanitizers = [ "address" "memory" "thread" "undefined" "leak" ];
      checkSanitizer = s:
        if builtins.elem s validSanitizers then "-fsanitize=${s}"
        else throw "nixclang: unknown sanitizer '${s}'. Valid options: ${concatStringsSep ", " validSanitizers}";
    in
    map checkSanitizer sanitizers;

  # Build coverage flags
  coverageFlags = enable:
    if enable then [ "--coverage" "-fprofile-arcs" "-ftest-coverage" ]
    else [ ];

in
rec {
  compileTranslationUnit =
    { toolchain
    , root
    , tu
    , headers
    , includeDirs
    , defines
    , cxxFlags
    , extraInputs ? [ ]
    }:
    let
      tc = toolchain;
      srcTree = mkSourceTree { inherit tu headers; };
      includeFlags = toIncludeFlags { inherit srcTree includeDirs; };
      defineFlags = toDefineFlags defines;
      drv =
        pkgs.runCommand "${sanitizeName tu.relNorm}.o"
          ({
            buildInputs = tc.runtimeInputs ++ extraInputs;
          } // tc.environment)
          ''
            set -euo pipefail
            mkdir -p "$out"
            ${tc.cxx} \
              ${concatStringsSep " " tc.defaultCxxFlags} \
              ${concatStringsSep " " cxxFlags} \
              ${concatStringsSep " " includeFlags} \
              ${concatStringsSep " " defineFlags} \
              -c ${srcTree}/${tu.relNorm} \
              -o "$out/${tu.objectName}"
          '';
    in
    {
      derivation = drv;
      object = "${drv}/${tu.objectName}";
      inherit tu headers srcTree includeFlags defineFlags;
    };

  # Legacy wrapper that uses mkLinkStep internally
  linkExecutable =
    { toolchain
    , name
    , objects
    , cxxFlags
    , ldflags
    , linkFlags
    }:
    mkLinkStep {
      inherit toolchain name objects cxxFlags ldflags linkFlags;
      outputDir = "bin";
    };

  generateCompileCommands =
    { toolchain
    , root
    , tus
    , includeDirs
    , defines
    , cxxFlags
    }:
    let
      tc = toolchain;
      includeFlags =
        map
          (dir:
            if builtins.isString dir then "-I${dir}"
            else if builtins.isPath dir then "-I${dir}"
            else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
            else throw "compileCommands: unsupported include path value"
          )
          includeDirs;
      defineFlags = toDefineFlags defines;
      entries =
        map
          (tu:
            {
              directory = builtins.toString root;
              file = tu.relNorm;
              command = concatStringsSep " "
                ([ tc.cxx ]
                  ++ tc.defaultCxxFlags
                  ++ cxxFlags
                  ++ includeFlags
                  ++ defineFlags
                  ++ [ "-c" tu.relNorm "-o" tu.objectName ]);
            })
          tus;
    in
    pkgs.writeText "compile_commands.json" (builtins.toJSON entries);

  mkBuildContext =
    { name
    , root
    , sources
    , includeDirs ? [ ]
    , defines ? [ ]
    , cxxFlags ? [ ]
    , libraries ? [ ]
    , depsManifest ? null
    , scanner ? null
    , generators ? [ ]
    , toolchain ? clangToolchain
    # New optimization options
    , lto ? false          # false, true, "thin", or "full"
    , sanitizers ? [ ]     # [ "address" "undefined" ] etc.
    , coverage ? false     # Enable code coverage instrumentation
    , ...
    }:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };
      generatorInfo = processGenerators generators;
      # Validate public attributes from libraries
      _ = map (lib:
        if lib ? public then validatePublic { public = lib.public; context = "library '${lib.name or "unknown"}'"; }
        else true
      ) libraries;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic libsPublic generatorInfo.public;
      allSources = sources ++ generatorInfo.sources;
      combinedIncludeDirs = includeDirs ++ publicAggregate.includeDirs ++ generatorInfo.includeDirs;
      combinedDefines = defines ++ publicAggregate.defines ++ generatorInfo.defines;
      # Add LTO, sanitizer, and coverage flags
      extraOptFlags = (ltoFlags lto) ++ (sanitizerFlags sanitizers) ++ (coverageFlags coverage);
      combinedCxxFlags = cxxFlags ++ publicAggregate.cxxFlags ++ generatorInfo.cxxFlags ++ extraOptFlags;
      tus = normalizeSources { inherit root; sources = allSources; };
      autoScanner =
        if depsManifest == null && scanner == null then
          mkDependencyScanner {
            name = "${name}-scanner";
            inherit root;
            sources = allSources;
            includeDirs = combinedIncludeDirs;
            defines = combinedDefines;
            cxxFlags = combinedCxxFlags;
            libraries = libraries;
            generators = generators;
            toolchain = tc;
          }
        else
          null;
      effectiveScanner = if scanner != null then scanner else autoScanner;
      baseManifest =
        if depsManifest != null then mkManifest depsManifest
        else if effectiveScanner != null then mkManifest effectiveScanner
        else emptyManifest;
      manifest = mergeManifests baseManifest generatorInfo.manifest;

      objectInfos =
        map
          (tu:
            let
              headers = headerSet { inherit root manifest tu; overrides = generatorInfo.headerOverrides; };
            in
            compileTranslationUnit {
              inherit root tu headers;
              toolchain = tc;
              includeDirs = combinedIncludeDirs;
              defines = combinedDefines;
              cxxFlags = combinedCxxFlags;
              extraInputs = generatorInfo.evalInputs;
            })
          tus;

      objectPaths = map (info: info.object) objectInfos;
      compileCommands =
        generateCompileCommands {
          toolchain = tc;
          root = rootPath;
          tus = tus;
          includeDirs = combinedIncludeDirs;
          defines = combinedDefines;
          cxxFlags = combinedCxxFlags;
        };
    in
    {
      inherit name rootPath toolchain;
      inherit objectInfos objectPaths compileCommands;
      inherit manifest tus;
      inherit combinedIncludeDirs combinedDefines combinedCxxFlags;
      inherit publicAggregate;
      inherit libraries generators;
      scanner = effectiveScanner;
    };

  mkExecutable = args:
    let
      ctx = mkBuildContext args;
      inherit (ctx) toolchain name objectPaths combinedCxxFlags publicAggregate;
      
      drv =
        linkExecutable {
          inherit toolchain name;
          objects = objectPaths;
          cxxFlags = combinedCxxFlags;
          ldflags = args.ldflags or [ ];
          linkFlags = publicAggregate.linkFlags;
        };
    in
    drv // {
      passthru = (drv.passthru or { }) // ctx;
    };

  mkStaticLib = args:
    let
      ctx = mkBuildContext args;
      inherit (ctx) toolchain name rootPath publicAggregate;
      tc = toolchain;
      
      publicIncludeDirs = args.publicIncludeDirs or args.includeDirs or [ ];
      publicDefines = args.publicDefines or [ ];
      publicCxxFlags = args.publicCxxFlags or [ ];

      # We need rootHost for normalizeIncludeDir, which is toString rootPath
      rootHost = builtins.toString rootPath;
      
      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; dir = dir; })
          (utils.ensureList publicIncludeDirs);

      archiveScript =
        lib.concatMapStrings (obj: "${tc.ar} rcs \"${archiveName}\" \"${obj}\"\n") ctx.objectPaths;
      archiveName = "lib${sanitizeName name}.a";
      
      installHeaders = concatStringsSep "\n" (map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores);
      
      archive =
        pkgs.runCommand "static-${name}"
          ({
            buildInputs =
              tc.runtimeInputs
              ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.darwin.cctools;
          } // tc.environment)
          ''
            set -euo pipefail
            mkdir -p "$out/lib" "$out/include"
            ${archiveScript}
            ${tc.ranlib} "${archiveName}"
            mv "${archiveName}" "$out/lib/"
            ${installHeaders}
          '';

      basePublic =
        {
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
      inherit (ctx) objectInfos compileCommands manifest libraries generators;
      public = combinedPublic;
      passthru = (archive.passthru or { }) // ctx;
    };

  mkSharedLib = args:
    let
      ctx = mkBuildContext args;
      inherit (ctx) toolchain name rootPath publicAggregate combinedCxxFlags;
      tc = toolchain;

      publicIncludeDirs = args.publicIncludeDirs or args.includeDirs or [ ];
      publicDefines = args.publicDefines or [ ];
      publicCxxFlags = args.publicCxxFlags or [ ];

      # We need rootHost for normalizeIncludeDir, which is toString rootPath
      rootHost = builtins.toString rootPath;

      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; dir = dir; })
          (utils.ensureList publicIncludeDirs);

      # Use target platform (correct for cross-compilation)
      sharedExt = if pkgs.stdenv.targetPlatform.isDarwin then "dylib" else "so";
      sharedName = "lib${name}.${sharedExt}";
      installHeaders = concatStringsSep "\n" (map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores);

      # Use mkLinkStep for consistent link handling
      linkDrv = mkLinkStep {
        inherit toolchain;
        name = "shared-${name}-link";
        objects = ctx.objectPaths;
        cxxFlags = combinedCxxFlags;
        ldflags = args.ldflags or [ ];
        linkFlags = publicAggregate.linkFlags;
        outputDir = "lib";
        outputName = sharedName;
        extraFlags = [ "-shared" ];
        targetPlatform = pkgs.stdenv.targetPlatform;
      };

      # Combine link output with header installation
      sharedDrv =
        pkgs.runCommand "shared-${name}"
          { }
          ''
            set -euo pipefail
            mkdir -p "$out/lib" "$out/include"
            cp ${linkDrv}/lib/${sharedName} "$out/lib/"
            ${installHeaders}
          '';

      basePublic =
        {
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
      inherit (ctx) objectInfos compileCommands manifest libraries generators;
      public = combinedPublic;
      passthru = (sharedDrv.passthru or { }) // ctx;
    };

  mkPythonExtension =
    { name
    , root ? ./. 
    , sources
    , python ? pkgs.python3
    , includeDirs ? [ ]
    , defines ? [ ]
    , cxxFlags ? [ ]
    , ldflags ? [ ]
    , libraries ? [ ]
    , depsManifest ? null
    , scanner ? null
    , generators ? [ ]
    , toolchain ? clangToolchain
    }:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };
      pyLibPrefix = python.libPrefix or (if python ? pythonVersion then "python${python.pythonVersion}" else "python3");
      pyIncludeBase = if python ? dev then python.dev else python;
      pyInclude = "${pyIncludeBase}/include/${pyLibPrefix}";
      pyLibBase = if python ? out then python else python;
      pyLibDir = "${pyLibBase}/lib";
      pyLdFlags = [ "-L${pyLibDir}" "-l${pyLibPrefix}" ];
      generatorInfo = processGenerators generators;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic libsPublic generatorInfo.public;
      allSources = sources ++ generatorInfo.sources;
      combinedIncludeDirs =
        includeDirs
        ++ [ { path = pyInclude; } ]
        ++ publicAggregate.includeDirs
        ++ generatorInfo.includeDirs;
      combinedDefines = defines ++ publicAggregate.defines ++ generatorInfo.defines;
      combinedCxxFlags = cxxFlags ++ publicAggregate.cxxFlags ++ generatorInfo.cxxFlags;
      autoScanner =
        if depsManifest == null && scanner == null then
          mkDependencyScanner {
            name = "${name}-scanner";
            inherit root;
            sources = allSources;
            includeDirs = combinedIncludeDirs;
            defines = combinedDefines;
            cxxFlags = combinedCxxFlags;
            libraries = libraries;
            generators = generators;
            toolchain = tc;
          }
        else
          null;
      effectiveScanner = if scanner != null then scanner else autoScanner;
      baseManifest =
        if depsManifest != null then mkManifest depsManifest
        else if effectiveScanner != null then mkManifest effectiveScanner
        else emptyManifest;
      manifest = mergeManifests baseManifest generatorInfo.manifest;
      tus = normalizeSources { inherit root; sources = allSources; };
      objectInfos =
        map
          (tu:
            let
              headers = headerSet { inherit root manifest tu; overrides = generatorInfo.headerOverrides; };
            in
            compileTranslationUnit {
              toolchain = tc;
              inherit root tu headers;
              includeDirs = combinedIncludeDirs;
              defines = combinedDefines;
              cxxFlags = combinedCxxFlags;
              extraInputs = generatorInfo.evalInputs;
            })
          tus;
      objectPaths = map (info: info.object) objectInfos;
      # Python expects extension modules to use `.so` on all platforms.
      sharedExt = "so";
      sharedName = "${name}.${sharedExt}";
      # Use mkLinkStep for consistent link handling
      sharedDrv = mkLinkStep {
        toolchain = tc;
        name = "python-ext-${name}";
        objects = objectPaths;
        cxxFlags = combinedCxxFlags;
        ldflags = pyLdFlags ++ ldflags;
        linkFlags = publicAggregate.linkFlags;
        outputDir = "lib";
        outputName = sharedName;
        extraFlags = [ "-shared" ];
        targetPlatform = pkgs.stdenv.targetPlatform;
      };
      compileCommands =
        generateCompileCommands {
          toolchain = tc;
          root = rootPath;
          tus = tus;
          includeDirs = combinedIncludeDirs;
          defines = combinedDefines;
          cxxFlags = combinedCxxFlags;
        };
    in
    sharedDrv // {
      artifactType = "python-extension";
      inherit name;
      extensionPath = "${sharedDrv}/lib/${sharedName}";
      pythonPath = "${sharedDrv}/lib";
      inherit objectInfos compileCommands manifest libraries generators;
      passthru = (sharedDrv.passthru or { }) // {
        inherit manifest objectInfos compileCommands libraries sharedName generators;
        toolchain = tc;
        scanner = effectiveScanner;
        inherit python;
        pythonPath = "${sharedDrv}/lib";
      };
    };

  mkHeaderOnly =
    { name
    , root ? ./. 
    , includeDirs ? [ ]
    , defines ? [ ]
    , cxxFlags ? [ ]
    , libraries ? [ ]
    , publicIncludeDirs ? includeDirs
    , publicDefines ? [ ]
    , publicCxxFlags ? [ ]
    , generators ? [ ]
    }:
    let
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;
      generatorInfo = processGenerators generators;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic libsPublic generatorInfo.public;
      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; dir = dir; })
          (utils.ensureList publicIncludeDirs);
      basePublic =
        {
          includeDirs = map (dir: { path = dir; }) publicIncludeStores;
          defines = publicDefines;
          cxxFlags = publicCxxFlags;
          linkFlags = [ ];
        };
      combinedPublic = mergePublic publicAggregate basePublic;
    in
    {
      artifactType = "header-only";
      inherit name;
      public = combinedPublic;
      inherit libraries generators;
    };

  mkDoc =
    { name
    , root ? ./.
    , sources ? []
    , doxygenConfig ? null
    }:
    let
      rootPath = sanitizePath { path = root; };
      defaultDoxyfile = pkgs.writeText "Doxyfile" ''
        PROJECT_NAME = "${name}"
        INPUT = ${if sources == [] then "." else builtins.concatStringsSep " " sources}
        RECURSIVE = YES
        OUTPUT_DIRECTORY = doc
        GENERATE_HTML = YES
        GENERATE_LATEX = NO
      '';
      configFile = if doxygenConfig != null then doxygenConfig else defaultDoxyfile;
    in
    pkgs.runCommand "doc-${name}"
      {
        nativeBuildInputs = [ pkgs.doxygen ];
        src = rootPath;
      }
      ''
        mkdir -p $out
        cp ${configFile} Doxyfile
        # Copy source content to current dir to allow Doxygen to find files relative to root
        cp -r $src/. .
        chmod -R u+w .
        
        doxygen Doxyfile
        
        mv doc/html $out/html
      '';

  mkTest =
    { name
    , executable
    , args ? []
    , stdin ? null
    , expectedOutput ? null
    }:
    let
      stdinFile = if stdin != null then pkgs.writeText "stdin" stdin else null;
      # Properly escape args for shell
      escapedArgs = map escapeShellArg args;
      # Write expected output to a file to avoid shell escaping issues
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

  mkDevShell =
    { target
    , toolchain ? null
    , extraPackages ? [ ]
    , linkCompileCommands ? true
    , symlinkName ? "compile_commands.json"
    , includeTools ? true
    }:
    let
      tc =
        if toolchain != null then toolchain
        else target.passthru.toolchain or clangToolchain;
      compileCommands = target.passthru.compileCommands or null;
      tools =
        if includeTools then
          [
            pkgs.clang-tools
            (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
          ]
        else
          [ ];
      packages = pkgs.lib.unique (
        tc.runtimeInputs
        ++ [ tc.clang ]
        ++ tools
        ++ extraPackages
      );
      linkHook =
        if linkCompileCommands && compileCommands != null then
          ''
            ln -sf "${compileCommands}" "${symlinkName}"
          ''
        else
          "";
    in
    pkgs.mkShell {
      packages = packages;
      shellHook =
        ''
          ${linkHook}
          export CC="${tc.cc}"
          export CXX="${tc.cxx}"
        ''
        + (if tc.environment ? SDKROOT then "export SDKROOT=\"${tc.environment.SDKROOT}\"\n" else "")
        + (if tc.environment ? MACOSX_DEPLOYMENT_TARGET then "export MACOSX_DEPLOYMENT_TARGET=\"${tc.environment.MACOSX_DEPLOYMENT_TARGET}\"\n" else "");
    };
}
