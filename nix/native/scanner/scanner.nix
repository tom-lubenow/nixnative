# Dependency scanner for nixnative
#
# Scans source files to discover header dependencies using -MMD.
# Also processes tool plugins to integrate generated code.
#
{ pkgs, lib, utils, manifest }:

let
  inherit (lib) concatStringsSep unique foldl';
  inherit (utils)
    sanitizePath
    toPathLike
    normalizeSources
    toDefineFlags
    emptyPublic
    mergePublic
    collectPublic
    showValue
    validatePublic;
  inherit (manifest) mkManifest emptyManifest mergeManifests;

in rec {
  # Re-export manifest functions
  inherit mkManifest emptyManifest mergeManifests;

  # ==========================================================================
  # Tool Plugin Processing
  # ==========================================================================

  # Process tool plugins (protobuf, jinja, etc.)
  # This replaces the old "processGenerators" function
  #
  processTools = tools:
    let
      toOverrideEntry = header:
        let
          relRaw =
            if header ? rel then header.rel
            else if header ? relative then header.relative
            else throw "nixnative: tool header must provide a 'rel' or 'relative' attribute. Got: ${showValue header}";
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
          value =
            if header ? store then toPathLike header.store
            else if header ? path then toPathLike header.path
            else throw "nixnative: tool header '${rel}' must provide 'path' or 'store' attribute. Got: ${showValue header}";
        in
        { name = rel; inherit value; };

      toSourceOverride = source:
        let
          relRaw =
            if source ? rel then source.rel
            else throw "nixnative: tool source must provide a 'rel' attribute. Got: ${showValue source}";
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
          value =
            if source ? store then toPathLike source.store
            else if source ? path then toPathLike source.path
            else throw "nixnative: tool source '${rel}' must provide 'path' or 'store' attribute. Got: ${showValue source}";
        in
        { name = rel; inherit value; };

      step = acc: tool:
        let
          toolName = tool.name or "<unnamed tool>";

          # Get manifest from tool
          toolManifest =
            if tool ? manifest then mkManifest tool.manifest
            else emptyManifest;

          # Get header overrides
          overrides =
            if tool ? headers
            then builtins.listToAttrs (map toOverrideEntry tool.headers)
            else {};

          # Get source overrides
          sourceOverridesMap =
            if tool ? sources
            then builtins.listToAttrs (map toSourceOverride tool.sources)
            else {};

          # Validate and get public attributes
          toolPublic =
            if tool ? public then
              validatePublic { public = tool.public; context = "tool '${toolName}'"; }
            else emptyPublic;

          # Collect other attributes
          toolSources = tool.sources or [];
          toolIncludeDirs = tool.includeDirs or [];
          toolDefines = tool.defines or [];
          toolCxxFlags = tool.cxxFlags or [];
          toolEvalInputs =
            if tool ? evalInputs then tool.evalInputs
            else if tool ? drv then [ tool.drv ]
            else [];
        in {
          sources = acc.sources ++ toolSources;
          includeDirs = acc.includeDirs ++ toolIncludeDirs;
          defines = acc.defines ++ toolDefines;
          cxxFlags = acc.cxxFlags ++ toolCxxFlags;
          manifest = mergeManifests acc.manifest toolManifest;
          public = mergePublic acc.public toolPublic;
          headerOverrides = acc.headerOverrides // overrides;
          sourceOverrides = acc.sourceOverrides // sourceOverridesMap;
          evalInputs = acc.evalInputs ++ toolEvalInputs;
        };
    in
    foldl' step {
      sources = [];
      includeDirs = [];
      defines = [];
      cxxFlags = [];
      manifest = emptyManifest;
      public = emptyPublic;
      headerOverrides = {};
      sourceOverrides = {};
      evalInputs = [];
    } tools;

  # ==========================================================================
  # Dependency Scanner
  # ==========================================================================

  # Scan sources for header dependencies using -MMD
  #
  mkDependencyScanner =
    { name ? "deps"
    , root
    , sources
    , toolchain
    , includeDirs ? []
    , cxxFlags ? []
    , defines ? []
    , extraInputs ? []
    , libraries ? []
    , tools ? []
    }:
    let
      tc = toolchain;

      # Process tool plugins
      toolInfo = processTools tools;

      # Collect library public attributes
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic toolInfo.public libsPublic;

      # Combine all include dirs
      combinedIncludeDirs =
        includeDirs
        ++ toolInfo.includeDirs
        ++ publicAggregate.includeDirs;

      # Combine all defines
      combinedDefines = defines ++ toolInfo.defines ++ publicAggregate.defines;

      # Combine all C++ flags
      combinedCxxFlags = cxxFlags ++ toolInfo.cxxFlags ++ publicAggregate.cxxFlags;

      # Collect tool inputs
      toolInputs = toolInfo.evalInputs;

      # Header and source overrides from tools
      headerOverrides = toolInfo.headerOverrides;
      sourceOverrides = toolInfo.sourceOverrides;

      # All sources (user + tool-generated)
      allSources = sources ++ toolInfo.sources;

      # Generate override lines for shell script
      headerOverrideLines =
        map
          (name: "${name}=${headerOverrides.${name}}")
          (builtins.attrNames headerOverrides);

      sourceOverrideLines =
        map
          (name: "${name}=${sourceOverrides.${name}}")
          (builtins.attrNames sourceOverrides);

      # Normalize sources to translation units
      tus = normalizeSources { inherit root; sources = allSources; };

      # Build include flags
      includeFlags =
        map
          (dir:
            if builtins.isString dir then "-I${dir}"
            else if builtins.isPath dir then "-I${dir}"
            else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
            else throw "mkDependencyScanner: includeDirs entries must be strings or paths."
          )
          combinedIncludeDirs;

      # Build define flags
      defineFlags = toDefineFlags combinedDefines;

      # Build inputs
      buildInputs = tc.runtimeInputs ++ map toPathLike (extraInputs ++ toolInputs);
      extraInputPaths = map toPathLike (extraInputs ++ toolInputs);
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

        # Verify tool inputs exist
        for dep in ${concatStringsSep " " extraInputPaths}; do
          test -z "$dep" && continue
          if [ ! -e "$dep" ]; then
            echo "missing tool input: $dep" >&2
            exit 1
          fi
        done

        work=$TMP/work
        mkdir -p "$work"
        cp -r "$src"/* "$work"
        chmod -R u+w "$work"

        # Apply header overrides from tools
        while IFS='=' read -r rel target; do
          [ -z "$rel" ] && continue
          mkdir -p "$work/$(dirname "$rel")"
          if [ "$target" != "$work/$rel" ]; then
            cp "$target" "$work/$rel"
          fi
        done <<'EOF'
${concatStringsSep "\n" headerOverrideLines}
EOF

        # Apply source overrides from tools
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

        # Scan each source file for dependencies
        while IFS= read -r srcFile; do
          test -z "$srcFile" && continue
          depfile="$TMP/$(echo "$srcFile" | tr '/' '_').d"
          ${tc.getCXX} \
            ${concatStringsSep " " (tc.getDefaultCxxFlags)} \
            ${concatStringsSep " " combinedCxxFlags} \
            ${concatStringsSep " " includeFlags} \
            ${concatStringsSep " " defineFlags} \
            -MMD -MF "$depfile" \
            -fsyntax-only "$srcFile"
        done < "$sourceListPath"

        # Parse dependency files and generate manifest
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
