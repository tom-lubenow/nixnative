# Dependency scanner for nixnative
#
# Provides per-file dependency scanning with support for content-addressed
# derivations. Each source file gets its own scanner derivation, enabling
# incremental rebuilds when using CA derivations.
#
# Architecture:
# - mkFileScan: Creates a derivation that scans a single source file
# - mergeFileScans: Combines per-file scan results into a manifest
# - processTools: Handles tool plugin integration (protobuf, jinja, etc.)
#
{
  pkgs,
  lib,
  utils,
  manifest,
  language,
  parsers,
}:

let
  inherit (lib) concatStringsSep unique foldl' groupBy mapAttrsToList concatLists;
  inherit (utils)
    sanitizePath
    sanitizeName
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
  inherit (language) detectLanguageName detectLanguage;
  inherit (parsers) mkParseScript;

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
  # Per-File Scanner
  # ==========================================================================

  # Scan a single source file for header dependencies.
  #
  # Creates a derivation that:
  # 1. Uses the language-specific scanner from the language config
  # 2. Parses the output to extract relative dependencies
  # 3. Outputs a simple text file with one dependency per line
  #
  # When contentAddressed is true, the derivation uses CA mode, meaning
  # identical outputs will be deduplicated even if inputs differ.
  #
  mkFileScan =
    {
      langConfig,          # Language config with scanner
      file,                # { rel, store } - normalized source file
      root,                # Project root (for header access)
      includeDirs ? [ ],   # Include directories
      defines ? [ ],       # Preprocessor defines
      extraFlags ? [ ],    # Additional compiler flags
      extraInputs ? [ ],   # Additional derivation inputs
      headerOverrides ? { }, # Generated header overrides from tools
      sourceOverrides ? { }, # Generated source overrides from tools
      contentAddressed ? false,
    }:
    let
      scanner = langConfig.scanner;

      # Build flags string
      includeFlags = map (dir:
        if builtins.isString dir then "-I${dir}"
        else if builtins.isPath dir then "-I${dir}"
        else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
        else throw "mkFileScan: includeDirs entries must be strings, paths, or {path} attrs"
      ) includeDirs;

      defineFlags = toDefineFlags defines;

      flagsStr = concatStringsSep " " (
        includeFlags ++ defineFlags ++ extraFlags
      );

      # Sanitize filename for derivation name
      safeName = sanitizeName (builtins.replaceStrings ["/"] ["_"] file.rel);

      # Generate override copy commands
      headerOverrideLines = map (name: "${name}=${headerOverrides.${name}}") (
        builtins.attrNames headerOverrides
      );
      sourceOverrideLines = map (name: "${name}=${sourceOverrides.${name}}") (
        builtins.attrNames sourceOverrides
      );

      hasOverrides = headerOverrideLines != [] || sourceOverrideLines != [];

      # Build script for setting up working directory
      # Fast path: no overrides - just cd to source (read-only is fine for scanning)
      # Slow path: with overrides - symlink source tree, copy overrides on top
      setupScript = if hasOverrides then ''
        # Set up working directory with symlinks + overrides
        work="$TMPDIR/work"
        mkdir -p "$work"

        # Symlink source tree (faster than copying)
        for item in "$src"/*; do
          [ -e "$item" ] && ln -s "$item" "$work/" 2>/dev/null || true
        done
        cd "$work"

        # Apply header overrides from tools (copy on top of symlinks)
        while IFS='=' read -r rel target; do
          [ -z "$rel" ] && continue
          # Remove symlink if it exists, create parent dirs, copy file
          rm -f "$rel" 2>/dev/null || true
          mkdir -p "$(dirname "$rel")"
          cp "$target" "$rel"
        done <<'HEADER_OVERRIDES'
        ${concatStringsSep "\n" headerOverrideLines}
        HEADER_OVERRIDES

        # Apply source overrides from tools
        while IFS='=' read -r rel target; do
          [ -z "$rel" ] && continue
          rm -f "$rel" 2>/dev/null || true
          mkdir -p "$(dirname "$rel")"
          cp "$target" "$rel"
        done <<'SOURCE_OVERRIDES'
        ${concatStringsSep "\n" sourceOverrideLines}
        SOURCE_OVERRIDES
      '' else ''
        # Fast path: no overrides, just cd to source directory
        cd "$src"
      '';

    in
    pkgs.runCommand "scan-${safeName}"
      ({
        src = root;
        buildInputs = scanner.runtimeInputs ++ (map toPathLike extraInputs);

        # Pass through source file info
        passthru = {
          sourceFile = file.rel;
          inherit langConfig;
        };
      } // lib.optionalAttrs contentAddressed {
        __contentAddressed = true;
      })
      ''
        set -euo pipefail

        ${setupScript}

        # Unset Nix wrapper environment variables
        unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
        unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET

        # Run the scanner
        depfile="$TMPDIR/deps.d"
        ${scanner.mkScanCommand {
          file = file.rel;
          depfile = "$depfile";
          flags = flagsStr;
        }}

        # Parse dependencies and write output
        ${mkParseScript {
          format = scanner.outputFormat;
          depfile = "$depfile";
          outfile = "$out";
          sourceFile = file.rel;
        }}
      '';

  # ==========================================================================
  # Manifest Merging
  # ==========================================================================

  # Merge multiple per-file scan results into a single manifest.
  #
  # Takes a list of scan derivations (from mkFileScan) and produces
  # a manifest in the standard format:
  #   { schema = 1; units = { "file.cc" = { dependencies = [...]; }; }; }
  #
  mergeFileScans =
    scans:
    let
      # Read deps from a scan derivation
      # Each scan output is a file with one dep per line
      readDeps = scan:
        let
          content = builtins.readFile scan;
          lines = lib.filter (l: l != "") (lib.splitString "\n" content);
        in
        {
          name = scan.passthru.sourceFile;
          value = { dependencies = lines; };
        };

      units = builtins.listToAttrs (map readDeps scans);
    in
    {
      schema = 1;
      inherit units;
    };

  # ==========================================================================
  # Batch Scanner (Convenience)
  # ==========================================================================

  # High-level scanner that creates per-file scans for all sources.
  #
  # This is the main entry point for the new per-file scanning architecture.
  # It groups sources by language and creates appropriate scan derivations.
  #
  mkSourceScans =
    {
      name ? "scans",
      root,
      sources,
      toolchain,
      includeDirs ? [ ],
      defines ? [ ],
      extraFlags ? [ ],
      extraInputs ? [ ],
      headerOverrides ? { },
      sourceOverrides ? { },
      contentAddressed ? false,
    }:
    let
      # Normalize sources
      tus = normalizeSources { inherit root sources; };

      # Group by language
      tusByLang = groupBy (tu:
        let lang = detectLanguage tu.relNorm;
        in if lang == null then "unknown" else lang.name
      ) tus;

      # Create scans for each language
      mkLangScans = lang: files:
        if toolchain.supportsLanguage lang then
          map (file: mkFileScan {
            langConfig = toolchain.languages.${lang};
            file = { rel = file.relNorm; store = file.store; };
            inherit root includeDirs defines extraFlags extraInputs;
            inherit headerOverrides sourceOverrides contentAddressed;
          }) files
        else if toolchain.supportsLanguage "cpp" then
          # Fallback to C++ for unknown languages
          map (file: mkFileScan {
            langConfig = toolchain.languages.cpp;
            file = { rel = file.relNorm; store = file.store; };
            inherit root includeDirs defines extraFlags extraInputs;
            inherit headerOverrides sourceOverrides contentAddressed;
          }) files
        else
          [ ];  # Skip unsupported languages

      allScans = concatLists (mapAttrsToList mkLangScans tusByLang);
    in
    {
      # Individual scan derivations
      scans = allScans;

      # Merged manifest (lazy - only evaluated if needed)
      manifest = mergeFileScans allScans;
    };

  # ==========================================================================
  # Legacy Scanner (Deprecated)
  # ==========================================================================

  # Original batch scanner that scans all files in a single derivation.
  # Kept for backwards compatibility but deprecated in favor of mkSourceScans.
  #
  # NOTE: This scanner does NOT support contentAddressed mode and will
  # re-scan all files whenever any input changes.
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
          lang = detectLanguage tu.relNorm;
        in
        if lang == null then "unknown" else lang.name
      ) tus;

      # Get the list of languages we need to scan (that the toolchain supports)
      supportedLangs = lib.filter (lang: tc.supportsLanguage lang) (builtins.attrNames tusByLang);

      # For unsupported languages, fall back to C++ (maintains backward compat)
      unsupportedLangs = lib.filter (lang: !(tc.supportsLanguage lang)) (builtins.attrNames tusByLang);

      # Generate scanner script for a specific language
      # Uses the language's scanner config
      mkScannerScript = lang:
        let
          langConfig = tc.languages.${lang};
          scanner = langConfig.scanner;
        in
        ''
          srcFile="$1"
          depfile="$TMP/$(echo "$srcFile" | tr '/' '_').d"
          ${scanner.mkScanCommand {
            file = "$srcFile";
            depfile = "$depfile";
            flags = commonFlags;
          }}
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
