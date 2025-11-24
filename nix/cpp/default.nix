{ pkgs }:

let
  lib = pkgs.lib;

  inherit (lib)
    concatMap
    concatStringsSep
    filter
    foldl'
    hasPrefix
    hasSuffix
    removePrefix
    removeSuffix
    replaceStrings
    mapAttrsToList
    recursiveUpdate
    unique;

  clangToolchain =
    let
      llvm = pkgs.llvmPackages_18;
      libcxx = llvm.libcxx;
      libcxxDev = llvm.libcxx.dev;
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      sdkRoot =
        if isDarwin then
          pkgs.apple-sdk.sdkroot
        else
          null;
      deploymentTarget =
        if isDarwin then
          pkgs.stdenv.hostPlatform.darwinMinVersion or "11.0"
        else
          null;
      darwinLibcxxInclude =
        if isDarwin then
          "${libcxxDev}/include/c++/v1"
        else
          null;
      darwinCxxFlags =
        if isDarwin then
          [
            "-isysroot"
            (builtins.toString sdkRoot)
            "-isystem"
            darwinLibcxxInclude
          ]
        else
          [ ];
      darwinLdFlags =
        if isDarwin then
          [
            "-Wl,-syslibroot,${builtins.toString sdkRoot}"
            "-isysroot"
            (builtins.toString sdkRoot)
            "-F${builtins.toString sdkRoot}/System/Library/Frameworks"
          ]
        else
          [ ];
      darwinEnv =
        if isDarwin then
          {
            SDKROOT = builtins.toString sdkRoot;
            MACOSX_DEPLOYMENT_TARGET = deploymentTarget;
          }
        else
          { };
    in
    rec {
      name = "clang18";
      clang = llvm.clang;
      cxx = "${clang}/bin/clang++";
      cc = "${clang}/bin/clang";
      ar = "${llvm.bintools}/bin/ar";
      ranlib = "${llvm.bintools}/bin/ranlib";
      nm = "${llvm.bintools}/bin/nm";
      ld =
        if isDarwin then
          "${pkgs.stdenv.cc.bintools.bintools}/bin/ld"
        else
          "${llvm.lld}/bin/ld.lld";
      runtimeInputs = [
        clang
        llvm.lld
        llvm.bintools
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gawk
      ]
      ++ lib.optionals isDarwin [
        pkgs.stdenv.cc.bintools.bintools
        pkgs.darwin.cctools
        pkgs.apple-sdk
        libcxx
        libcxxDev
      ];
      targetTriple = llvm.stdenv.targetPlatform.config;
      defaultCxxFlags = [ "-std=c++20" "-fdiagnostics-color" "-Wall" "-Wextra" ] ++ darwinCxxFlags;
      defaultLdFlags = darwinLdFlags;
      environment = darwinEnv;
    };

  sanitizeName = name:
    let
      dropExt =
        file:
        let
          exts = [ ".cc" ".cpp" ".cxx" ".c" ".C" ];
        in
        foldl'
          (acc: ext: if lib.hasSuffix ext acc then lib.removeSuffix ext acc else acc)
          file
          exts;
      replace = lib.replaceStrings [ "/" ":" " " "." ] [ "-" "-" "-" "-" ];
    in
    replace (dropExt name);

  ensureList = value: if builtins.isList value then value else [ value ];

  toPathLike = value:
    if builtins.isPath value then value
    else if builtins.isString value then value
    else if builtins.isAttrs value && value ? path then toPathLike value.path
    else if builtins.isAttrs value && value ? outPath then value.outPath
    else throw "Expected a path-like value";

  stripExtension = file: ext:
    if hasSuffix ext file then removeSuffix ext file else file;

  sanitizePath =
    { path
    , name ? null
    }:
    let
      base = {
        inherit path;
        filter = _: _: true;
      };
      withName = if name == null then base else base // { inherit name; };
    in
    builtins.path withName;

  normalizeIncludeDir =
    { rootHost
    , dir
    }:
    if builtins.isString dir then
      let
        rel = if hasPrefix "./" dir then removePrefix "./" dir else dir;
      in
      builtins.path { path = "${rootHost}/${rel}"; }
    else if builtins.isPath dir then dir
    else if builtins.isAttrs dir && dir ? path then builtins.path { path = dir.path; }
    else
      throw "includeDirs entries must be relative strings or paths.";

  emptyPublic =
    {
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      linkFlags = [ ];
    };

  mergePublic = a: b:
    {
      includeDirs = a.includeDirs ++ b.includeDirs;
      defines = a.defines ++ b.defines;
      cxxFlags = a.cxxFlags ++ b.cxxFlags;
      linkFlags = a.linkFlags ++ b.linkFlags;
    };

  libraryPublic =
    lib:
    if builtins.isAttrs lib && lib ? public then lib.public
    else if builtins.isAttrs lib && lib ? linkFlags then emptyPublic // { linkFlags = ensureList lib.linkFlags; }
    else if builtins.isString lib then emptyPublic // { linkFlags = [ lib ]; }
    else if builtins.isPath lib then emptyPublic // { linkFlags = [ builtins.toString lib ]; }
    else
      emptyPublic;

  collectPublic = libs:
    foldl' mergePublic emptyPublic (map libraryPublic libs);

  normalizeSources =
    { root
    , sources
    }:
    let
      rootPath = sanitizePath { path = root; name = "sources-root"; };
      rootHost = builtins.toString rootPath;
      mkEntry = source:
        let
          rel =
            if builtins.isAttrs source && source ? rel then source.rel
            else if builtins.isString source then source
            else throw "mkExecutable: sources must be relative strings or attrsets with `rel`.";
          relNorm =
            if hasPrefix "./" rel then removePrefix "./" rel else rel;
          host =
            if builtins.isAttrs source && source ? path then builtins.toString source.path
            else "${rootHost}/${relNorm}";
          objectName = "${sanitizeName relNorm}.o";
        in
        {
          store =
            if builtins.isAttrs source && source ? store then toPathLike source.store
            else builtins.path { path = host; };
          inherit relNorm host objectName;
        };
    in
    map mkEntry sources;

  headerSet =
    { root
    , manifest
    , tu
    , overrides ? { }
    }:
    let
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;
      entry = manifest.units.${tu.relNorm} or null;
      deps = if entry == null then [ ] else entry.dependencies or [ ];
      mkHeader = path:
        let
          rel = if hasPrefix "./" path then removePrefix "./" path else path;
          override = overrides.${rel} or null;
          storePath =
            if override != null then toPathLike override
            else builtins.path { path = "${rootHost}/${rel}"; };
          host =
            if override != null then builtins.toString storePath
            else "${rootHost}/${rel}";
        in
        {
          rel = rel;
          host = host;
          store = storePath;
        };
    in
    map mkHeader deps;

  mkSourceTree =
    { tu
    , headers
    }:
    let
      headersToLink = builtins.filter (header: header.rel != tu.relNorm) headers;
      headerScripts =
        lib.concatMapStrings (header: ''
          dst="${header.rel}"
          mkdir -p "$out/$(dirname "$dst")"
          cp ${header.store} "$out/$dst"
        '') headersToLink;
    in
    pkgs.runCommand "tu-${sanitizeName tu.relNorm}-src"
      {
        buildInputs = [ pkgs.coreutils ];
      }
      ''
        set -euo pipefail
        mkdir -p "$out"
        dst="${tu.relNorm}"
        mkdir -p "$out/$(dirname "$dst")"
        cp ${tu.store} "$out/$dst"
        ${headerScripts}
      '';

  toIncludeFlags =
    { srcTree
    , includeDirs
    }:
    let
      toFlag = dir:
        if builtins.isString dir then "-I${srcTree}/${dir}"
        else if builtins.isPath dir then "-I${dir}"
        else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
        else throw "mkExecutable: includeDirs entries must be strings or paths.";
    in
    map toFlag includeDirs;

  toDefineFlags = defines:
    map
      (define:
        if builtins.isString define then "-D${define}"
        else if builtins.isAttrs define && define ? name then
          let
            value = define.value or "";
          in
          if value == "" then "-D${define.name}"
          else "-D${define.name}=${toString value}"
        else
          throw "mkExecutable: defines must be strings or attrsets with name/value."
      )
      defines;

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

  linkExecutable =
    { toolchain
    , name
    , objects
    , cxxFlags
    , ldflags
    , linkFlags
    }:
    let
      tc = toolchain;
      groupedLinkFlags =
        if pkgs.stdenv.hostPlatform.isLinux
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
        mkdir -p "$out/bin"
        ${tc.cxx} \
          ${concatStringsSep " " tc.defaultCxxFlags} \
          ${concatStringsSep " " cxxFlags} \
          ${concatStringsSep " " objects} \
          ${concatStringsSep " " finalLinkFlags} \
          -o "$out/bin/${name}"
      '';

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

  mkManifest =
    manifestSpec:
    let
      load = spec:
        if builtins.isAttrs spec && spec ? units then spec
        else
          let
            path = toPathLike spec;
            pathStr = builtins.toString path;
          in
          if lib.hasSuffix ".nix" pathStr then import path
          else builtins.fromJSON (builtins.readFile path);
      manifest = load manifestSpec;
    in
    if manifest ? units then manifest
    else throw "Dependency manifest must contain a `units` attribute.";

  mkDependencyScanner =
    { name ? "deps"
    , root
    , sources
    , includeDirs ? [ ]
    , cxxFlags ? [ ]
    , defines ? [ ]
    , extraInputs ? [ ]
    , libraries ? [ ]
    , generators ? [ ]
    , toolchain ? clangToolchain
    }:
    let
      tc = toolchain;
      generatorInfo = processGenerators generators;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic generatorInfo.public libsPublic;
      combinedIncludeDirs =
        includeDirs
        ++ generatorInfo.includeDirs
        ++ publicAggregate.includeDirs;
      combinedDefines = defines ++ generatorInfo.defines ++ publicAggregate.defines;
      combinedCxxFlags = cxxFlags ++ generatorInfo.cxxFlags ++ publicAggregate.cxxFlags;
      generatorInputs = generatorInfo.evalInputs;
      headerOverrides = generatorInfo.headerOverrides;
      allSources = sources ++ generatorInfo.sources;
      headerOverrideLines =
        map
          (name: "${name}=${headerOverrides.${name}}")
          (builtins.attrNames headerOverrides);
      sourceOverrides = generatorInfo.sourceOverrides;
      sourceOverrideLines =
        map
          (name: "${name}=${sourceOverrides.${name}}")
          (builtins.attrNames sourceOverrides);
      tus = normalizeSources { inherit root; sources = allSources; };
      includeFlags =
        map
          (dir:
            if builtins.isString dir then "-I${dir}"
            else if builtins.isPath dir then "-I${dir}"
            else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
            else throw "mkDependencyScanner: includeDirs entries must be strings or paths."
          )
          combinedIncludeDirs;
      defineFlags = toDefineFlags combinedDefines;
      buildInputs = tc.runtimeInputs ++ map toPathLike (extraInputs ++ generatorInputs);
      extraInputPaths = map toPathLike (extraInputs ++ generatorInputs);
    in
    pkgs.runCommand "${name}.json"
      ({
        buildInputs = buildInputs ++ [ pkgs.python3 ];
        src = sanitizePath { path = root; name = "scanner-root"; };
        passAsFile = [ "sourceList" ];
        sourceList = concatStringsSep "\n" (map (tu: tu.relNorm) tus) + "\n";
      } // tc.environment)
      ''
        set -euo pipefail
        for dep in ${concatStringsSep " " extraInputPaths}; do
          test -z "$dep" && continue
          if [ ! -e "$dep" ]; then
            echo "missing generator input: $dep" >&2
            exit 1
          fi
        done
        work=$TMP/work
        mkdir -p "$work"
        cp -r "$src"/* "$work"
        chmod -R u+w "$work"
        while IFS='=' read -r rel target; do
          [ -z "$rel" ] && continue
          mkdir -p "$work/$(dirname "$rel")"
          if [ "$target" != "$work/$rel" ]; then
            cp "$target" "$work/$rel"
          fi
        done <<'EOF'
${concatStringsSep "\n" headerOverrideLines}
EOF
        while IFS='=' read -r rel target; do
          [ -z "$rel" ] && continue
          mkdir -p "$work/$(dirname "$rel")"
          if [ "$target" != "$work/$rel" ]; then
            cp "$target" "$work/$rel"
          fi
        done <<'EOF'
${concatStringsSep "\n" sourceOverrideLines}
EOF
        cd "$work"

        while IFS= read -r srcFile; do
          test -z "$srcFile" && continue
          depfile="$TMP/$(echo "$srcFile" | tr '/' '_').d"
          ${tc.cxx} \
            ${concatStringsSep " " tc.defaultCxxFlags} \
            ${concatStringsSep " " combinedCxxFlags} \
            ${concatStringsSep " " includeFlags} \
            ${concatStringsSep " " defineFlags} \
            -MMD -MF "$depfile" \
            -fsyntax-only "$srcFile"
        done < "$sourceListPath"

        ${pkgs.python3}/bin/python - "$TMP" "$sourceListPath" "$out" <<'PY'
import json
import os
import pathlib
import sys

tmp_dir = pathlib.Path(sys.argv[1])
sources = pathlib.Path(sys.argv[2])
out_path = pathlib.Path(sys.argv[3])

units = {}
for line in sources.read_text().splitlines():
    rel = line.strip()
    if not rel:
        continue
    depfile = tmp_dir / (rel.replace('/', '_') + ".d")
    deps = []
    if depfile.exists():
        raw = depfile.read_text().replace("\\\n", " ")
        try:
            _, payload = raw.split(":", 1)
        except ValueError:
            payload = ""
        parts = [p for p in payload.strip().split() if p]
        for part in parts:
            path = pathlib.Path(part)
            if not path.is_absolute():
                deps.append(str(path))
    units[rel] = { "dependencies": deps }

out_path.write_text(json.dumps({ "schema": 1, "units": units }, indent=2))
PY
      '';

  emptyManifest = {
    schema = 1;
    units = { };
  };

  mergeManifests = base: addition:
    let
      baseUnits = base.units or { };
      additionUnits = addition.units or { };
      schema =
        if base ? schema then base.schema
        else if addition ? schema then addition.schema
        else 1;
      keys = unique ((builtins.attrNames baseUnits) ++ (builtins.attrNames additionUnits));
      mergeEntry = baseEntry: additionEntry:
        if baseEntry == null then additionEntry
        else if additionEntry == null then baseEntry
        else
          let
            baseDeps = baseEntry.dependencies or [ ];
            additionDeps = additionEntry.dependencies or [ ];
          in
          baseEntry // additionEntry // {
            dependencies = unique (baseDeps ++ additionDeps);
          };
      mergedUnits = builtins.listToAttrs (map (name:
        {
          name = name;
          value = mergeEntry (baseUnits.${name} or null) (additionUnits.${name} or null);
        }) keys);
    in
    {
      schema = schema;
      units = mergedUnits;
    };

  processGenerators = generators:
    let
      toOverrideEntry = header:
        let
          relRaw =
            if header ? rel then header.rel
            else if header ? relative then header.relative
            else throw "Generator headers must provide a `rel` attribute.";
          rel = if hasPrefix "./" relRaw then removePrefix "./" relRaw else relRaw;
          value =
            if header ? store then toPathLike header.store
            else if header ? path then toPathLike header.path
            else throw "Generator headers must provide `path` or `store`.";
        in
        { name = rel; value = value; };
      toSourceOverride = source:
        let
          relRaw =
            if source ? rel then source.rel
            else throw "Generator sources must provide a `rel` attribute.";
          rel = if hasPrefix "./" relRaw then removePrefix "./" relRaw else relRaw;
          value =
            if source ? store then toPathLike source.store
            else if source ? path then toPathLike source.path
            else throw "Generator sources must provide `path` or `store`.";
        in
        { name = rel; value = value; };

      step = acc: generator:
        let
          genManifest =
            if generator ? manifest then mkManifest generator.manifest
            else emptyManifest;
          overrides =
            if generator ? headers
            then builtins.listToAttrs (map toOverrideEntry generator.headers)
            else { };
          sourceOverridesMap =
            if generator ? sources
            then builtins.listToAttrs (map toSourceOverride generator.sources)
            else { };
          genPublic =
            if generator ? public then generator.public else emptyPublic;
          genSources = generator.sources or [ ];
          genIncludeDirs = generator.includeDirs or [ ];
          genDefines = generator.defines or [ ];
          genCxxFlags = generator.cxxFlags or [ ];
          genEvalInputs =
            if generator ? evalInputs then generator.evalInputs
            else if generator ? drv then [ generator.drv ]
            else [ ];
        in
        {
          sources = acc.sources ++ genSources;
          includeDirs = acc.includeDirs ++ genIncludeDirs;
          defines = acc.defines ++ genDefines;
          cxxFlags = acc.cxxFlags ++ genCxxFlags;
          manifest = mergeManifests acc.manifest genManifest;
          public = mergePublic acc.public genPublic;
          headerOverrides = acc.headerOverrides // overrides;
          sourceOverrides = acc.sourceOverrides // sourceOverridesMap;
          evalInputs = acc.evalInputs ++ genEvalInputs;
        };
    in
    foldl' step {
      sources = [ ];
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      manifest = emptyManifest;
      public = emptyPublic;
      headerOverrides = { };
      sourceOverrides = { };
      evalInputs = [ ];
    } generators;

  mkExecutable =
    { name
    , root ? ./. 
    , sources
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
      generatorInfo = processGenerators generators;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic libsPublic generatorInfo.public;
      allSources = sources ++ generatorInfo.sources;
      combinedIncludeDirs = includeDirs ++ publicAggregate.includeDirs ++ generatorInfo.includeDirs;
      combinedDefines = defines ++ publicAggregate.defines ++ generatorInfo.defines;
      combinedCxxFlags = cxxFlags ++ publicAggregate.cxxFlags ++ generatorInfo.cxxFlags;
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
      drv =
        linkExecutable {
          toolchain = tc;
          inherit name;
          cxxFlags = combinedCxxFlags;
          objects = objectPaths;
          ldflags = ldflags;
          linkFlags = publicAggregate.linkFlags;
        };
    in
    drv // {
      passthru = (drv.passthru or { }) // {
        inherit objectInfos compileCommands manifest tus combinedIncludeDirs combinedDefines combinedCxxFlags;
        libraries = libraries;
        generators = generators;
        public = publicAggregate;
        toolchain = tc;
        scanner = effectiveScanner;
      };
    };

  mkStaticLib =
    { name
    , root ? ./. 
    , sources
    , includeDirs ? [ ]
    , defines ? [ ]
    , cxxFlags ? [ ]
    , libraries ? [ ]
    , depsManifest ? null
    , scanner ? null
    , publicIncludeDirs ? includeDirs
    , publicDefines ? [ ]
    , publicCxxFlags ? [ ]
    , generators ? [ ]
    , toolchain ? clangToolchain
    }:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;
      generatorInfo = processGenerators generators;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic libsPublic generatorInfo.public;
      allSources = sources ++ generatorInfo.sources;
      combinedIncludeDirs = includeDirs ++ publicAggregate.includeDirs ++ generatorInfo.includeDirs;
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
      archiveName = "lib${name}.a";
      objectsArg = concatStringsSep " " objectPaths;
      archiveScript =
        if pkgs.stdenv.hostPlatform.isDarwin then
          ''
            ${pkgs.darwin.cctools}/bin/libtool -static -o "$out/lib/${archiveName}" ${objectsArg}
          ''
        else
          ''
            ${tc.ar} rc "${archiveName}" ${objectsArg}
            ${tc.ranlib} "${archiveName}"
            mv "${archiveName}" "$out/lib/"
          '';
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
            ${installHeaders}
          '';
      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; dir = dir; })
          (ensureList publicIncludeDirs);
      basePublic =
        {
          includeDirs = map (dir: { path = dir; }) publicIncludeStores;
          defines = publicDefines;
          cxxFlags = publicCxxFlags;
          linkFlags = [ "${archive}/lib/${archiveName}" ];
        };
      combinedPublic = mergePublic publicAggregate basePublic;
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
    archive // {
      artifactType = "static";
      inherit name;
      archivePath = "${archive}/lib/${archiveName}";
      inherit objectInfos compileCommands manifest libraries generators;
      public = combinedPublic;
      passthru = (archive.passthru or { }) // {
        inherit manifest objectInfos compileCommands libraries generators;
        toolchain = tc;
        scanner = effectiveScanner;
      };
    };

  mkSharedLib =
    { name
    , root ? ./.
    , sources
    , includeDirs ? [ ]
    , defines ? [ ]
    , cxxFlags ? [ ]
    , ldflags ? [ ]
    , libraries ? [ ]
    , depsManifest ? null
    , scanner ? null
    , publicIncludeDirs ? includeDirs
    , publicDefines ? [ ]
    , publicCxxFlags ? [ ]
    , generators ? [ ]
    , toolchain ? clangToolchain
    }:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;
      generatorInfo = processGenerators generators;
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic libsPublic generatorInfo.public;
      allSources = sources ++ generatorInfo.sources;
      combinedIncludeDirs = includeDirs ++ publicAggregate.includeDirs ++ generatorInfo.includeDirs;
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
      sharedExt = if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so";
      sharedName = "lib${name}.${sharedExt}";
      installHeaders = concatStringsSep "\n" (map (dir: "cp -r ${dir}/. $out/include/") publicIncludeStores);
      sharedDrv =
        pkgs.runCommand "shared-${name}"
          ({
            buildInputs = tc.runtimeInputs;
          } // tc.environment)
          ''
            set -euo pipefail
            mkdir -p "$out/lib" "$out/include"
            ${tc.cxx} \
              -shared \
              ${concatStringsSep " " tc.defaultCxxFlags} \
              ${concatStringsSep " " combinedCxxFlags} \
              ${concatStringsSep " " objectPaths} \
              ${concatStringsSep " " tc.defaultLdFlags} \
              ${concatStringsSep " " ldflags} \
              ${concatStringsSep " " publicAggregate.linkFlags} \
              -o "$out/lib/${sharedName}"
            ${installHeaders}
          '';
      publicIncludeStores =
        map (dir: normalizeIncludeDir { inherit rootHost; dir = dir; })
          (ensureList publicIncludeDirs);
      basePublic =
        {
          includeDirs = map (dir: { path = dir; }) publicIncludeStores;
          defines = publicDefines;
          cxxFlags = publicCxxFlags;
          linkFlags = [ "${sharedDrv}/lib/${sharedName}" ];
        };
      combinedPublic = mergePublic publicAggregate basePublic;
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
      artifactType = "shared";
      inherit name;
      sharedLibrary = "${sharedDrv}/lib/${sharedName}";
      inherit objectInfos compileCommands manifest libraries generators;
      public = combinedPublic;
      passthru = (sharedDrv.passthru or { }) // {
        inherit manifest objectInfos compileCommands libraries sharedName generators;
        toolchain = tc;
        scanner = effectiveScanner;
      };
    };

  mkPythonExtension =
    { name
    , moduleName ? name
    , root ? ./.
    , python
    , sources
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
      generatorInfo = processGenerators generators;
      libsPublic = collectPublic libraries;
      pythonIncludeDir = builtins.path { path = "${python}/include/${python.libPrefix}"; };
      pythonSitePackages = python.sitePackages or "lib/${python.libPrefix}/site-packages";
      pythonLinkFlags =
        if pkgs.stdenv.hostPlatform.isDarwin then
          [ "-undefined" "dynamic_lookup" ]
        else
          [ "-L${python}/lib" "-Wl,-rpath,${python}/lib" "-l${python.libPrefix}" ];
      pythonPublic = {
        includeDirs = [ { path = pythonIncludeDir; } ];
        defines = [ ];
        cxxFlags = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ "-fPIC" ];
        linkFlags = pythonLinkFlags;
      };
      basePublic = mergePublic libsPublic generatorInfo.public;
      publicAggregate = mergePublic basePublic pythonPublic;
      combinedIncludeDirs = includeDirs ++ generatorInfo.includeDirs ++ publicAggregate.includeDirs;
      combinedDefines = defines ++ generatorInfo.defines ++ publicAggregate.defines;
      combinedCxxFlags = cxxFlags ++ generatorInfo.cxxFlags ++ publicAggregate.cxxFlags;
      allSources = sources ++ generatorInfo.sources;
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
      extensionName =
        let
          ext = if pkgs.stdenv.hostPlatform.isDarwin then "so" else "so";
        in
        "${moduleName}.${ext}";
      extensionDrv =
        pkgs.runCommand "python-extension-${name}"
          ({
            buildInputs = tc.runtimeInputs ++ [ python ];
          } // tc.environment)
          ''
            set -euo pipefail
            mkdir -p "$out/${pythonSitePackages}"
            ${tc.cxx} \
              -shared \
              ${concatStringsSep " " tc.defaultCxxFlags} \
              ${concatStringsSep " " combinedCxxFlags} \
              ${concatStringsSep " " objectPaths} \
              ${concatStringsSep " " tc.defaultLdFlags} \
              ${concatStringsSep " " ldflags} \
              ${concatStringsSep " " publicAggregate.linkFlags} \
              -o "$out/${pythonSitePackages}/${extensionName}"
          '';
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
      type = "python-extension";
      inherit name python;
      drv = extensionDrv;
      extensionPath = "${extensionDrv}/${pythonSitePackages}/${extensionName}";
      pythonPath = "${extensionDrv}/${pythonSitePackages}";
      inherit manifest objectInfos compileCommands libraries generators;
      public = publicAggregate;
      passthru = {
        inherit manifest objectInfos compileCommands libraries generators python moduleName;
        pythonPath = "${extensionDrv}/${pythonSitePackages}";
        extension = "${extensionDrv}/${pythonSitePackages}/${extensionName}";
        toolchain = tc;
        scanner = effectiveScanner;
      };
    };

  mkDevShell =
    { target
    , extraPackages ? [ ]
    , linkCompileCommands ? true
    , symlinkName ? "compile_commands.json"
    }:
    let
      tc = target.passthru.toolchain or clangToolchain;
      compileCommands = target.passthru.compileCommands or null;
      packages = pkgs.lib.unique (
        tc.runtimeInputs
        ++ [ tc.clang ]
        ++ extraPackages
      );
      linkHook =
        if linkCompileCommands && compileCommands != null then
          ''
            if [ ! -e ${symlinkName} ] || [ "$(readlink ${symlinkName} 2>/dev/null)" != "${compileCommands}" ]; then
              ln -sf ${compileCommands} ${symlinkName}
              echo "Linked ${symlinkName} -> ${compileCommands}" >&2
            fi
          ''
        else "";
    in
    pkgs.mkShell {
      inherit packages;
      shellHook = pkgs.lib.optionalString (linkHook != "") linkHook;
    };

  mkHeaderOnly =
    { name
    , includeDir
    , publicDefines ? [ ]
    , publicCxxFlags ? [ ]
    }:
    let
      resolve = value:
        if builtins.isString value then builtins.path { path = value; }
        else if builtins.isPath value then value
        else if builtins.isAttrs value && value ? path then builtins.path { path = value.path; }
        else throw "mkHeaderOnly: includeDir must be a path or string";
      includeSource = resolve includeDir;
      drv = pkgs.runCommand "header-only-${name}" { } ''
        set -euo pipefail
        mkdir -p "$out/include"
        cp -R ${includeSource}/. "$out/include/"
      '';
      public = {
        includeDirs = [ { path = "${drv}/include"; } ];
        defines = publicDefines;
        cxxFlags = publicCxxFlags;
        linkFlags = [ ];
      };
    in
    {
      type = "header-only";
      inherit name drv public;
      passthru = {
        includePath = "${drv}/include";
      };
    };

  mkPkgConfigLibrary =
    { name
    , packages
    , modules ? [ name ]
    }:
    let
      pkgDirs = concatMap (pkg:
        let
          candidate = toPathLike pkg;
        in
        map (suffix: "${candidate}/${suffix}")
          [ "lib/pkgconfig" "lib64/pkgconfig" "share/pkgconfig" ]
      ) packages;
      pkgConfigPath = concatStringsSep ":" pkgDirs;
      moduleArgs = concatStringsSep " " (map lib.escapeShellArg modules);
      nixDrv =
        pkgs.runCommand "pkg-config-${name}.nix"
          {
            buildInputs = [ pkgs.pkg-config pkgs.python3 ] ++ packages;
            PKG_CONFIG_PATH = pkgConfigPath;
          }
          ''
            set -euo pipefail
            cflags=$(${pkgs.pkg-config}/bin/pkg-config --cflags ${moduleArgs})
            libs=$(${pkgs.pkg-config}/bin/pkg-config --libs ${moduleArgs})
${pkgs.python3}/bin/python - "$cflags" "$libs" "$out" <<'PY'
import shlex
import sys

cflags = shlex.split(sys.argv[1])
libs = shlex.split(sys.argv[2])
out_path = sys.argv[3]

include_dirs = []
defines = []
cxx_flags = []
for token in cflags:
    if token.startswith('-I'):
        include_dirs.append(token[2:])
    elif token.startswith('-D'):
        defines.append(token[2:])
    else:
        cxx_flags.append(token)

link_flags = []
for token in libs:
    if token.startswith('-L') or token.startswith('-l') or token.startswith('-Wl'):
        link_flags.append(token)
    else:
        link_flags.append(token)

def dedup(seq):
    out = []
    seen = set()
    for item in seq:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out

include_dirs = dedup(include_dirs)
defines = dedup(defines)
cxx_flags = dedup(cxx_flags)
link_flags = dedup(link_flags)

def quote(s):
    return s.replace('\\\\', '\\\\\\\\').replace('"', '\\\\"')

with open(out_path, 'w') as fh:
    fh.write("{\n")
    fh.write("  includeDirs = [\n")
    for dir in include_dirs:
        fh.write(f'    (builtins.toPath "{quote(dir)}")\n')
    fh.write("  ];\n")
    fh.write("  defines = [\n")
    for define in defines:
        fh.write(f'    "{quote(define)}"\n')
    fh.write("  ];\n")
    fh.write("  cxxFlags = [\n")
    for flag in cxx_flags:
        fh.write(f'    "{quote(flag)}"\n')
    fh.write("  ];\n")
    fh.write("  linkFlags = [\n")
    for flag in link_flags:
        fh.write(f'    "{quote(flag)}"\n')
    fh.write("  ];\n")
    fh.write("}\n")
PY
          '';
      info = import nixDrv;
      includeDirAttrs = map (dir: { path = dir; }) info.includeDirs;
      definesList = info.defines;
    in
    {
      inherit name nixDrv;
      drv = nixDrv;
      public = {
        includeDirs = includeDirAttrs;
        defines = definesList;
        cxxFlags = info.cxxFlags;
        linkFlags = info.linkFlags;
      };
      passthru = {
        inherit packages modules info;
      };
    };

  mkTest =
    { name
    , executable
    , args ? []
    , stdin ? null
    , expectedOutput ? null
    }:
    pkgs.runCommand "test-${name}"
      {
        nativeBuildInputs = [ executable ];
      }
      ''
        set -euo pipefail
        echo "Running test: ${name}"
        
        # Construct command
        # We assume the executable name matches the derivation name, or we find the first binary
        BIN_PATH=$(find ${executable}/bin -type f -executable | head -n 1)
        CMD="$BIN_PATH ${builtins.concatStringsSep " " args}"
        
        echo "Command: $CMD"
        
        # Run with stdin if provided
        ${if stdin != null then "echo '${stdin}' | $CMD > output.log" else "$CMD > output.log"}
        
        # Check output if expected
        ${if expectedOutput != null then ''
          if ! grep -q "${expectedOutput}" output.log; then
            echo "Test failed: Expected output '${expectedOutput}' not found."
            echo "Actual output:"
            cat output.log
            exit 1
          fi
        '' else ""}
        
        # Save output as result
        mkdir -p $out
        cp output.log $out/test.log
        echo "Test passed"
      '';

in
{
  toolchains = {
    clang = clangToolchain;
  };

  inherit mkDependencyScanner mkExecutable mkStaticLib mkSharedLib mkPythonExtension mkHeaderOnly mkTest;

  inherit mkDevShell;

  pkgConfig = {
    makeLibrary = mkPkgConfigLibrary;
  };
}
