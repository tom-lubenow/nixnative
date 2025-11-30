# Dependency scanner for nixnative
#
# Scans source files to discover header dependencies using -MMD.
# Also processes tool plugins to integrate generated code.
#
{
  pkgs,
  lib,
  utils,
  manifest,
  language,
}:

let
  inherit (lib) concatStringsSep unique foldl' groupBy;
  inherit (utils)
    sanitizePath
    toPathLike
    normalizeSources
    toDefineFlags
    emptyPublic
    mergePublic
    collectPublic
    collectEvalInputs
    showValue
    validatePublic
    ;
  inherit (manifest) mkManifest emptyManifest mergeManifests;
  inherit (language) detectLanguageName;

in
rec {
  # Re-export manifest functions
  inherit mkManifest emptyManifest mergeManifests;

  # ==========================================================================
  # Tool Plugin Processing
  # ==========================================================================

  # Process tool plugins (protobuf, jinja, etc.)
  # This replaces the old "processGenerators" function
  #
  processTools =
    tools:
    let
      toOverrideEntry =
        header:
        let
          relRaw =
            if header ? rel then
              header.rel
            else if header ? relative then
              header.relative
            else
              throw "nixnative: tool header must provide a 'rel' or 'relative' attribute. Got: ${showValue header}";
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
          value =
            if header ? store then
              toPathLike header.store
            else if header ? path then
              toPathLike header.path
            else
              throw "nixnative: tool header '${rel}' must provide 'path' or 'store' attribute. Got: ${showValue header}";
        in
        {
          name = rel;
          inherit value;
        };

      toSourceOverride =
        source:
        let
          relRaw =
            if source ? rel then
              source.rel
            else
              throw "nixnative: tool source must provide a 'rel' attribute. Got: ${showValue source}";
          rel = if lib.hasPrefix "./" relRaw then lib.removePrefix "./" relRaw else relRaw;
          value =
            if source ? store then
              toPathLike source.store
            else if source ? path then
              toPathLike source.path
            else
              throw "nixnative: tool source '${rel}' must provide 'path' or 'store' attribute. Got: ${showValue source}";
        in
        {
          name = rel;
          inherit value;
        };

      step =
        acc: tool:
        let
          toolName = tool.name or "<unnamed tool>";

          # Get manifest from tool
          toolManifest = if tool ? manifest then mkManifest tool.manifest else emptyManifest;

          # Get header overrides
          overrides = if tool ? headers then builtins.listToAttrs (map toOverrideEntry tool.headers) else { };

          # Get source overrides
          sourceOverridesMap =
            if tool ? sources then builtins.listToAttrs (map toSourceOverride tool.sources) else { };

          # Validate and get public attributes
          toolPublic =
            if tool ? public then
              validatePublic {
                public = tool.public;
                context = "tool '${toolName}'";
              }
            else
              emptyPublic;

          # Collect other attributes
          toolSources = tool.sources or [ ];
          toolIncludeDirs = tool.includeDirs or [ ];
          toolDefines = tool.defines or [ ];
          toolCxxFlags = tool.cxxFlags or [ ];
          toolEvalInputs =
            if tool ? evalInputs then
              tool.evalInputs
            else if tool ? drv then
              [ tool.drv ]
            else
              [ ];
        in
        {
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
      sources = [ ];
      includeDirs = [ ];
      defines = [ ];
      cxxFlags = [ ];
      manifest = emptyManifest;
      public = emptyPublic;
      headerOverrides = { };
      sourceOverrides = { };
      evalInputs = [ ];
    } tools;

  # ==========================================================================
  # Dependency Scanner
  # ==========================================================================

  # Scan sources for header dependencies using -MMD
  #
  # NOTE: Currently uses C++ compiler for all files. This works because
  # we're only parsing headers (-fsyntax-only), not generating code.
  # For most projects this is fine. Future enhancement: per-file language
  # detection for scanning.
  #
  mkDependencyScanner =
    {
      name ? "deps",
      root,
      sources,
      toolchain,
      includeDirs ? [ ],
      extraFlags ? [ ],
      defines ? [ ],
      extraInputs ? [ ],
      libraries ? [ ],
      tools ? [ ],
    }:
    let
      tc = toolchain;

      # Process tool plugins
      toolInfo = processTools tools;

      # Collect library public attributes
      libsPublic = collectPublic libraries;
      publicAggregate = mergePublic toolInfo.public libsPublic;

      # Combine all include dirs
      combinedIncludeDirs = includeDirs ++ toolInfo.includeDirs ++ publicAggregate.includeDirs;

      # Combine all defines
      combinedDefines = defines ++ toolInfo.defines ++ publicAggregate.defines;

      # Combine all extra flags (applied during scanning)
      combinedExtraFlags = extraFlags ++ toolInfo.cxxFlags ++ publicAggregate.cxxFlags;

      # Collect tool inputs
      toolInputs = toolInfo.evalInputs;

      # Collect library inputs (packages needed in sandbox for include paths)
      libraryInputs = collectEvalInputs libraries;

      # Header and source overrides from tools
      headerOverrides = toolInfo.headerOverrides;

      # All sources (user + tool-generated)
      allSources = sources ++ toolInfo.sources;

      # Normalize sources to translation units
      tus = normalizeSources {
        inherit root;
        sources = allSources;
      };

      # Build source overrides: combine tool overrides with derivation sources
      # Derivation sources have store paths that point outside the root
      rootPath = sanitizePath { path = root; name = "scanner-root-check"; };
      rootStr = builtins.toString rootPath;

      # Extract derivation source overrides from translation units
      # A TU is a derivation source if its store path doesn't start with the root
      derivationSourceOverrides = builtins.listToAttrs (
        lib.filter (x: x != null) (
          map (tu:
            let
              storeStr = builtins.toString tu.store;
            in
            # If the store path doesn't start with the root path, it's a derivation source
            if !(lib.hasPrefix rootStr storeStr) then
              { name = tu.relNorm; value = tu.store; }
            else
              null
          ) tus
        )
      );

      # Merge tool source overrides with derivation source overrides
      sourceOverrides = toolInfo.sourceOverrides // derivationSourceOverrides;

      # Generate override lines for shell script
      headerOverrideLines = map (name: "${name}=${headerOverrides.${name}}") (
        builtins.attrNames headerOverrides
      );

      sourceOverrideLines = map (name: "${name}=${sourceOverrides.${name}}") (
        builtins.attrNames sourceOverrides
      );

      # Build include flags
      includeFlags = map (
        dir:
        if builtins.isString dir then
          "-I${dir}"
        else if builtins.isPath dir then
          "-I${dir}"
        else if builtins.isAttrs dir && dir ? path then
          "-I${dir.path}"
        else
          throw "mkDependencyScanner: includeDirs entries must be strings or paths."
      ) combinedIncludeDirs;

      # Build define flags
      defineFlags = toDefineFlags combinedDefines;

      # Common flags for all languages
      commonFlags = concatStringsSep " " (
        tc.getPlatformCompileFlags
        ++ combinedExtraFlags
        ++ includeFlags
        ++ defineFlags
      );

      # Group translation units by language for per-language scanning
      # Uses language detection based on file extension
      tusByLang = groupBy (tu:
        let
          lang = language.detectLanguage tu.relNorm;
        in
        if lang == null then "unknown" else lang.name
      ) tus;

      # Get the list of languages we need to scan (that the toolchain supports)
      supportedLangs = lib.filter (lang: tc.supportsLanguage lang) (builtins.attrNames tusByLang);

      # For unsupported languages, fall back to C++ (maintains backward compat)
      unsupportedLangs = lib.filter (lang: !(tc.supportsLanguage lang)) (builtins.attrNames tusByLang);

      # Generate scanner script for a specific language
      mkScannerScript = lang:
        let
          compiler = tc.getCompilerForLanguage lang;
          defaultFlags = concatStringsSep " " (tc.getDefaultFlagsForLanguage lang);
        in
        ''
          srcFile="$1"
          depfile="$TMP/$(echo "$srcFile" | tr '/' '_').d"
          if ! ${compiler} \
              ${defaultFlags} \
              ${commonFlags} \
              -MMD -MF "$depfile" -fsyntax-only "$srcFile" 2>"$depfile.err"; then
            echo "$srcFile" >> "$TMP/failed"
          fi
        '';

      # Generate source list for a language
      mkSourceList = lang:
        let
          langTus = tusByLang.${lang} or [];
        in
        concatStringsSep "\n" (map (tu: tu.relNorm) langTus) + "\n";

      # Scanner scripts per language (only for supported languages)
      scannerScripts = lib.listToAttrs (map (lang: {
        name = lang;
        value = mkScannerScript lang;
      }) supportedLangs);

      # Source lists per language
      sourceLists = lib.listToAttrs (map (lang: {
        name = lang;
        value = mkSourceList lang;
      }) supportedLangs);

      # For unsupported languages, use C++ as fallback
      fallbackLangs = unsupportedLangs;
      fallbackScannerScript = if fallbackLangs != [] && tc.supportsLanguage "cpp"
        then mkScannerScript "cpp"
        else "";
      fallbackSourceList = if fallbackLangs != []
        then concatStringsSep "\n" (lib.concatMap (lang: map (tu: tu.relNorm) (tusByLang.${lang} or [])) fallbackLangs) + "\n"
        else "";

      # Build inputs (include library packages so their store paths exist in sandbox)
      allExtraInputs = extraInputs ++ toolInputs ++ libraryInputs;
      buildInputs = tc.runtimeInputs ++ map toPathLike allExtraInputs;
      extraInputPaths = map toPathLike (extraInputs ++ toolInputs);

      # Build passAsFile entries for all languages
      langPassAsFile = lib.concatMap (lang: [
        "sourceList_${lang}"
        "scannerScript_${lang}"
      ]) supportedLangs;

      # Build env vars for all languages
      langEnvVars = lib.listToAttrs (lib.concatMap (lang: [
        { name = "sourceList_${lang}"; value = sourceLists.${lang}; }
        { name = "scannerScript_${lang}"; value = scannerScripts.${lang}; }
      ]) supportedLangs);

      # Fallback env vars (for unknown language extensions)
      fallbackEnvVars = if fallbackSourceList != "" then {
        sourceList_fallback = fallbackSourceList;
        scannerScript_fallback = fallbackScannerScript;
      } else {};

      fallbackPassAsFile = if fallbackSourceList != "" then [
        "sourceList_fallback"
        "scannerScript_fallback"
      ] else [];

      # Shell code to scan each language
      # Note: We generate the variable names at Nix eval time so shell can reference them
      scanCommands = concatStringsSep "\n" (map (lang:
        let
          srcListVar = "sourceList_${lang}Path";
          scriptVar = "scannerScript_${lang}Path";
        in ''
        if [ -s "''$${srcListVar}" ]; then
          cp "''$${scriptVar}" "$TMP/scan-${lang}.sh"
          chmod +x "$TMP/scan-${lang}.sh"
          xargs -P"$(nproc)" -a "''$${srcListVar}" -I{} bash "$TMP/scan-${lang}.sh" {}
        fi
      '') supportedLangs);

      fallbackScanCommand = if fallbackSourceList != "" then ''
        if [ -s "$sourceList_fallbackPath" ]; then
          cp "$scannerScript_fallbackPath" "$TMP/scan-fallback.sh"
          chmod +x "$TMP/scan-fallback.sh"
          xargs -P"$(nproc)" -a "$sourceList_fallbackPath" -I{} bash "$TMP/scan-fallback.sh" {}
        fi
      '' else "";

      # Full source list for the Python script (combines all languages)
      fullSourceList = concatStringsSep "\n" (map (tu: tu.relNorm) tus) + "\n";

    in
    pkgs.runCommand "${name}.json"
      (
        {
          # Explicit dependencies:
          # - python3: parse .d files and generate manifest JSON
          # - findutils: xargs -a (GNU extension for reading args from file)
          # - coreutils: nproc (GNU extension for CPU count)
          buildInputs = buildInputs ++ [
            pkgs.python3
            pkgs.findutils
            pkgs.coreutils
          ];
          src = sanitizePath {
            path = root;
            name = "scanner-root";
          };
          passAsFile = [ "fullSourceList" ] ++ langPassAsFile ++ fallbackPassAsFile;
          inherit fullSourceList;
        }
        // langEnvVars
        // fallbackEnvVars
        // tc.environment
      )
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

                # Unset Nix wrapper environment variables that interfere with our explicit flags
                unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
                unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET

                # Scan each language with its appropriate compiler
                ${scanCommands}
                ${fallbackScanCommand}

                # Report any failures with context
                if [ -s "$TMP/failed" ]; then
                  echo "Scanner failed for the following files:" >&2
                  while IFS= read -r f; do
                    echo "  $f" >&2
                    errfile="$TMP/$(echo "$f" | tr '/' '_').d.err"
                    [ -s "$errfile" ] && sed 's/^/    /' "$errfile" >&2
                  done < "$TMP/failed"
                  exit 1
                fi

                # Parse dependency files and generate manifest
                ${pkgs.python3}/bin/python - "$TMP" "$fullSourceListPath" "$out" <<'PY'
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
