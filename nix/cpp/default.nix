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
    unique;

  clangToolchain =
    let
      llvm = pkgs.llvmPackages_18;
    in
    rec {
      name = "clang18";
      clang = llvm.clang;
      cxx = "${clang}/bin/clang++";
      cc = "${clang}/bin/clang";
      ar = "${llvm.bintools}/bin/llvm-ar";
      ranlib = "${llvm.bintools}/bin/llvm-ranlib";
      nm = "${llvm.bintools}/bin/llvm-nm";
      ld = "${llvm.lld}/bin/ld.lld";
      defaultCxxFlags = [ "-std=c++20" "-fdiagnostics-color" "-Wall" "-Wextra" ];
      defaultLdFlags = [ ];
      runtimeInputs = [
        clang
        llvm.lld
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gawk
      ];
      targetTriple = llvm.stdenv.targetPlatform.config;
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
      rootPath = builtins.path { path = root; };
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
          store = builtins.path { path = host; };
          inherit relNorm host objectName;
        };
    in
    map mkEntry sources;

  headerSet =
    { root
    , manifest
    , tu
    }:
    let
      rootPath = builtins.path { path = root; };
      rootHost = builtins.toString rootPath;
      entry = manifest.units.${tu.relNorm} or null;
      deps = if entry == null then [ ] else entry.dependencies or [ ];
      mkHeader = path:
        let
          rel = if hasPrefix "./" path then removePrefix "./" path else path;
          host = "${rootHost}/${rel}";
        in
        {
          rel = rel;
          host = host;
          store = builtins.path { path = host; };
        };
    in
    map mkHeader deps;

  mkSourceTree =
    { tu
    , headers
    }:
    let
      headerMap =
        builtins.listToAttrs
          (map (header: { name = header.rel; value = header.store; }) headers);
      headerEntries =
        mapAttrsToList (name: path: { inherit name path; }) headerMap;
    in
    pkgs.linkFarm "tu-${sanitizeName tu.relNorm}-src"
      ([ { name = tu.relNorm; path = tu.store; } ] ++ headerEntries);

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
    { root
    , tu
    , headers
    , includeDirs
    , defines
    , cxxFlags
    }:
    let
      srcTree = mkSourceTree { inherit tu headers; };
      includeFlags = toIncludeFlags { inherit srcTree includeDirs; };
      defineFlags = toDefineFlags defines;
      drv =
        pkgs.runCommand "${sanitizeName tu.relNorm}.o"
          {
            buildInputs = clangToolchain.runtimeInputs;
          }
          ''
            set -euo pipefail
            mkdir -p "$out"
            ${clangToolchain.cxx} \
              ${concatStringsSep " " clangToolchain.defaultCxxFlags} \
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
    { name
    , objects
    , cxxFlags
    , ldflags
    , linkFlags
    }:
    pkgs.runCommand name
      {
        buildInputs = clangToolchain.runtimeInputs;
      }
      ''
        set -euo pipefail
        mkdir -p "$out/bin"
        ${clangToolchain.cxx} \
          ${concatStringsSep " " clangToolchain.defaultCxxFlags} \
          ${concatStringsSep " " cxxFlags} \
          ${concatStringsSep " " objects} \
          ${concatStringsSep " " (ldflags ++ linkFlags)} \
          -o "$out/bin/${name}"
      '';

  generateCompileCommands =
    { root
    , tus
    , includeDirs
    , defines
    , cxxFlags
    }:
    let
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
                ([ clangToolchain.cxx ]
                  ++ clangToolchain.defaultCxxFlags
                  ++ cxxFlags
                  ++ includeFlags
                  ++ defineFlags
                  ++ [ "-c" tu.relNorm "-o" tu.objectName ]);
            })
          tus;
    in
    pkgs.writeText "compile_commands.json" (builtins.toJSON entries);

  mkManifest =
    manifestPath:
    let
      json = builtins.fromJSON (builtins.readFile manifestPath);
    in
    if json ? units then json
    else throw "Dependency manifest must contain a `units` attribute.";

  mkDependencyScanner =
    { name ? "deps"
    , root
    , sources
    , includeDirs ? [ ]
    , cxxFlags ? [ ]
    , defines ? [ ]
    }:
    let
      tus = normalizeSources { inherit root sources; };
      includeFlags =
        map
          (dir:
            if builtins.isString dir then "-I${dir}"
            else if builtins.isPath dir then "-I${dir}"
            else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
            else throw "mkDependencyScanner: includeDirs entries must be strings or paths."
          )
          includeDirs;
      defineFlags = toDefineFlags defines;
    in
    pkgs.runCommand "${name}.json"
      {
        buildInputs = clangToolchain.runtimeInputs ++ [ pkgs.python3 ];
        src = builtins.path { path = root; name = "scanner-root"; };
        passAsFile = [ "sourceList" ];
        sourceList = concatStringsSep "\n" (map (tu: tu.relNorm) tus) + "\n";
      }
      ''
        set -euo pipefail
        work=$TMP/work
        mkdir -p "$work"
        cp -r "$src"/* "$work"
        cd "$work"

        while IFS= read -r srcFile; do
          test -z "$srcFile" && continue
          depfile="$TMP/$(echo "$srcFile" | tr '/' '_').d"
          ${clangToolchain.cxx} \
            ${concatStringsSep " " clangToolchain.defaultCxxFlags} \
            ${concatStringsSep " " cxxFlags} \
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
    }:
    let
      rootPath = builtins.path { path = root; };
      libsPublic = collectPublic libraries;
      combinedIncludeDirs = includeDirs ++ libsPublic.includeDirs;
      combinedDefines = defines ++ libsPublic.defines;
      combinedCxxFlags = cxxFlags ++ libsPublic.cxxFlags;
      tus = normalizeSources { inherit root sources; };
      manifest =
        if depsManifest != null then mkManifest depsManifest
        else if scanner != null then mkManifest scanner
        else { units = { }; };

      objectInfos =
        map
          (tu:
            let
              headers = headerSet { inherit root manifest tu; };
            in
            compileTranslationUnit {
              inherit root tu headers;
              includeDirs = combinedIncludeDirs;
              defines = combinedDefines;
              cxxFlags = combinedCxxFlags;
            })
          tus;

      objectPaths = map (info: info.object) objectInfos;
      compileCommands =
        generateCompileCommands {
          root = rootPath;
          tus = tus;
          includeDirs = combinedIncludeDirs;
          defines = combinedDefines;
          cxxFlags = combinedCxxFlags;
        };
      drv =
        linkExecutable {
          inherit name;
          cxxFlags = combinedCxxFlags;
          objects = objectPaths;
          ldflags = ldflags;
          linkFlags = libsPublic.linkFlags;
        };
    in
    drv // {
      passthru = (drv.passthru or { }) // {
        inherit objectInfos compileCommands manifest tus combinedIncludeDirs combinedDefines combinedCxxFlags;
        libraries = libraries;
        public = libsPublic;
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
    }:
    let
      rootPath = builtins.path { path = root; };
      rootHost = builtins.toString rootPath;
      libsPublic = collectPublic libraries;
      combinedIncludeDirs = includeDirs ++ libsPublic.includeDirs;
      combinedDefines = defines ++ libsPublic.defines;
      combinedCxxFlags = cxxFlags ++ libsPublic.cxxFlags;
      manifest =
        if depsManifest != null then mkManifest depsManifest
        else if scanner != null then mkManifest scanner
        else { units = { }; };
      tus = normalizeSources { inherit root sources; };
      objectInfos =
        map
          (tu:
            let
              headers = headerSet { inherit root manifest tu; };
            in
            compileTranslationUnit {
              inherit root tu headers;
              includeDirs = combinedIncludeDirs;
              defines = combinedDefines;
              cxxFlags = combinedCxxFlags;
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
            ${clangToolchain.ar} rc "${archiveName}" ${objectsArg}
            ${clangToolchain.ranlib} "${archiveName}"
            mv "${archiveName}" "$out/lib/"
          '';
      archive =
        pkgs.runCommand "static-${name}"
          {
            buildInputs =
              clangToolchain.runtimeInputs
              ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.darwin.cctools;
          }
          ''
            set -euo pipefail
            mkdir -p "$out/lib"
            ${archiveScript}
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
      combinedPublic = mergePublic libsPublic basePublic;
      compileCommands =
        generateCompileCommands {
          root = rootPath;
          tus = tus;
          includeDirs = combinedIncludeDirs;
          defines = combinedDefines;
          cxxFlags = combinedCxxFlags;
        };
    in
    {
      type = "static";
      inherit name;
      drv = archive;
      archivePath = "${archive}/lib/${archiveName}";
      inherit objectInfos compileCommands manifest;
      inherit libraries;
      public = combinedPublic;
      passthru = {
        inherit manifest objectInfos compileCommands libraries;
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
    }:
    let
      rootPath = builtins.path { path = root; };
      rootHost = builtins.toString rootPath;
      libsPublic = collectPublic libraries;
      combinedIncludeDirs = includeDirs ++ libsPublic.includeDirs;
      combinedDefines = defines ++ libsPublic.defines;
      combinedCxxFlags = cxxFlags ++ libsPublic.cxxFlags;
      manifest =
        if depsManifest != null then mkManifest depsManifest
        else if scanner != null then mkManifest scanner
        else { units = { }; };
      tus = normalizeSources { inherit root sources; };
      objectInfos =
        map
          (tu:
            let
              headers = headerSet { inherit root manifest tu; };
            in
            compileTranslationUnit {
              inherit root tu headers;
              includeDirs = combinedIncludeDirs;
              defines = combinedDefines;
              cxxFlags = combinedCxxFlags;
            })
          tus;
      objectPaths = map (info: info.object) objectInfos;
      sharedExt = if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so";
      sharedName = "lib${name}.${sharedExt}";
      sharedDrv =
        pkgs.runCommand "shared-${name}"
          {
            buildInputs = clangToolchain.runtimeInputs;
          }
          ''
            set -euo pipefail
            mkdir -p "$out/lib"
            ${clangToolchain.cxx} \
              -shared \
              ${concatStringsSep " " clangToolchain.defaultCxxFlags} \
              ${concatStringsSep " " combinedCxxFlags} \
              ${concatStringsSep " " objectPaths} \
              ${concatStringsSep " " ldflags} \
              ${concatStringsSep " " libsPublic.linkFlags} \
              -o "$out/lib/${sharedName}"
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
      combinedPublic = mergePublic libsPublic basePublic;
      compileCommands =
        generateCompileCommands {
          root = rootPath;
          tus = tus;
          includeDirs = combinedIncludeDirs;
          defines = combinedDefines;
          cxxFlags = combinedCxxFlags;
        };
    in
    {
      type = "shared";
      inherit name;
      drv = sharedDrv;
      sharedLibrary = "${sharedDrv}/lib/${sharedName}";
      inherit objectInfos compileCommands manifest libraries;
      public = combinedPublic;
      passthru = {
        inherit manifest objectInfos compileCommands libraries sharedName;
      };
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

in
{
  toolchains = {
    clang = clangToolchain;
  };

  inherit mkDependencyScanner mkExecutable mkStaticLib mkSharedLib mkHeaderOnly;
}
