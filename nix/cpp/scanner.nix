{ pkgs, lib, utils, clangToolchain }:
let
  inherit (lib) concatStringsSep unique foldl';
  inherit (utils)
    sanitizePath
    toPathLike
    normalizeSources
    toDefineFlags
    emptyPublic
    mergePublic
    collectPublic;
in
rec {
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
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
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
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
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
}
