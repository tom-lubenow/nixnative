# Utility functions for nixnative
#
# Common helpers used across the build system.
# Adapted from nix/cpp/utils.nix with updates for the new architecture.
#
{ pkgs }:

let
  lib = pkgs.lib;
  inherit (lib)
    concatMap
    concatStringsSep
    escapeShellArg
    filter
    foldl'
    hasPrefix
    hasSuffix
    removePrefix
    removeSuffix
    replaceStrings
    mapAttrsToList
    recursiveUpdate
    unique
    ;

in
rec {
  # ==========================================================================
  # Validation Helpers
  # ==========================================================================

  # Validates that a value is a list, with a contextual error message
  assertList =
    {
      value,
      name,
      context,
    }:
    if builtins.isList value then
      value
    else
      throw "nixnative (${context}): '${name}' must be a list, got ${builtins.typeOf value}";

  # Validates the structure of a 'public' attribute set
  validatePublic =
    { public, context }:
    let
      checkField =
        field: expected:
        if !(public ? ${field}) then
          throw "nixnative (${context}): public attribute missing required field '${field}'"
        else if expected == "list" && !(builtins.isList public.${field}) then
          throw "nixnative (${context}): public.${field} must be a list, got ${
            builtins.typeOf public.${field}
          }"
        else
          true;
      _ = checkField "includeDirs" "list";
      __ = checkField "defines" "list";
      ___ = checkField "cxxFlags" "list";
      ____ = checkField "linkFlags" "list";
    in
    public;

  # Formats a value for error messages
  showValue =
    value:
    if builtins.isString value then
      "'${value}'"
    else if builtins.isPath value then
      "<path: ${toString value}>"
    else if builtins.isAttrs value then
      if value ? name then
        "<attrset with name='${value.name}'>"
      else if value ? rel then
        "<attrset with rel='${value.rel}'>"
      else
        "<attrset with keys: ${concatStringsSep ", " (builtins.attrNames value)}>"
    else if builtins.isList value then
      "<list of ${toString (builtins.length value)} items>"
    else
      "<${builtins.typeOf value}>";

  # ==========================================================================
  # Name/Path Sanitization
  # ==========================================================================

  sanitizeName =
    name:
    let
      dropExt =
        file:
        let
          exts = [
            ".cc"
            ".cpp"
            ".cxx"
            ".c"
            ".C"
          ];
        in
        foldl' (acc: ext: if lib.hasSuffix ext acc then lib.removeSuffix ext acc else acc) file exts;
      replace = lib.replaceStrings [ "/" ":" " " "." ] [ "-" "-" "-" "-" ];
    in
    replace (dropExt name);

  ensureList = value: if builtins.isList value then value else [ value ];

  toPathLike =
    value:
    if builtins.isPath value then
      value
    else if builtins.isString value then
      value
    else if builtins.isAttrs value && value ? path then
      toPathLike value.path
    else if builtins.isAttrs value && value ? outPath then
      value.outPath
    else
      throw "nixnative: expected a path-like value (path, string, or attrset with 'path'/'outPath'), got ${showValue value}";

  stripExtension = file: ext: if hasSuffix ext file then removeSuffix ext file else file;

  sanitizePath =
    {
      path,
      name ? null,
    }:
    let
      base = {
        inherit path;
        filter = _: _: true;
      };
      withName = if name == null then base else base // { inherit name; };
    in
    builtins.path withName;

  # ==========================================================================
  # Include Directory Handling
  # ==========================================================================

  normalizeIncludeDir =
    {
      rootHost,
      dir,
    }:
    if builtins.isString dir then
      let
        rel = if hasPrefix "./" dir then removePrefix "./" dir else dir;
      in
      builtins.path { path = "${rootHost}/${rel}"; }
    else if builtins.isPath dir then
      dir
    else if builtins.isAttrs dir && dir ? path then
      builtins.path { path = dir.path; }
    else
      throw "nixnative: includeDirs entries must be relative strings, paths, or attrsets with 'path', got ${showValue dir}";

  # ==========================================================================
  # Public Attribute Handling
  # ==========================================================================

  emptyPublic = {
    includeDirs = [ ];
    defines = [ ];
    cxxFlags = [ ];
    linkFlags = [ ];
  };

  mergePublic = a: b: {
    includeDirs = a.includeDirs ++ b.includeDirs;
    defines = a.defines ++ b.defines;
    cxxFlags = a.cxxFlags ++ b.cxxFlags;
    linkFlags = a.linkFlags ++ b.linkFlags;
  };

  libraryPublic =
    lib:
    if builtins.isAttrs lib && lib ? public then
      lib.public
    else if builtins.isAttrs lib && lib ? linkFlags then
      emptyPublic // { linkFlags = ensureList lib.linkFlags; }
    else if builtins.isString lib then
      emptyPublic // { linkFlags = [ lib ]; }
    else if builtins.isPath lib then
      emptyPublic
      // {
        linkFlags = [
          builtins.toString
          lib
        ];
      }
    else
      emptyPublic;

  collectPublic = libs: foldl' mergePublic emptyPublic (map libraryPublic libs);

  # ==========================================================================
  # Recursive Library Resolution
  # ==========================================================================

  # Recursively collect all link flags from a library and its transitive dependencies.
  # This properly handles the case where static libraries don't embed their dependencies'
  # objects, avoiding duplicate symbol errors.
  #
  # Arguments:
  #   libs - List of library dependencies
  #
  # Returns:
  #   List of unique link flags (object files, archives, shared libs) in dependency order
  #
  collectAllLinkFlags =
    libs:
    let
      # Collect from a single library and its dependencies
      collectFromLib =
        lib:
        if !(builtins.isAttrs lib) then
          # Raw string/path link flag
          [ (toPathLike lib) ]
        else
          let
            # Get this library's direct link flags
            directFlags = lib.public.linkFlags or [ ];
            # Recursively get transitive dependencies' flags
            transitiveFlags =
              if lib ? libraries then
                collectAllLinkFlags lib.libraries
              else
                [ ];
          in
          # Transitive deps come BEFORE this lib (dependency order for static linking)
          transitiveFlags ++ directFlags;

      # Collect from all libraries
      allFlags = concatMap collectFromLib libs;
    in
    # Remove duplicates while preserving order (later occurrences kept for link order)
    unique allFlags;

  # Extract evalInputs from a library (packages needed in sandbox)
  libraryEvalInputs =
    lib: if builtins.isAttrs lib && lib ? evalInputs then ensureList lib.evalInputs else [ ];

  # Collect all evalInputs from libraries
  collectEvalInputs = libs: concatMap libraryEvalInputs libs;

  # ==========================================================================
  # Glob Pattern Expansion
  # ==========================================================================

  # Check if a string contains glob characters
  isGlob = s: builtins.isString s && (lib.hasInfix "*" s);

  # Check if a filename matches a simple pattern like "*.cc" or "foo*.h"
  # Supports only single * at one position in the pattern
  matchPattern = pattern: filename:
    let
      parts = lib.splitString "*" pattern;
    in
    if builtins.length parts == 1 then
      # No wildcard, exact match
      pattern == filename
    else if builtins.length parts == 2 then
      # Single wildcard: check prefix and suffix
      let
        prefix = builtins.elemAt parts 0;
        suffix = builtins.elemAt parts 1;
        prefixLen = builtins.stringLength prefix;
        suffixLen = builtins.stringLength suffix;
        filenameLen = builtins.stringLength filename;
      in
      filenameLen >= prefixLen + suffixLen
      && (prefix == "" || hasPrefix prefix filename)
      && (suffix == "" || hasSuffix suffix filename)
    else
      # Multiple wildcards - not supported in simple matching
      false;

  # List files in a directory (non-recursive)
  listFiles = dir:
    let
      entries = builtins.readDir dir;
      files = lib.filterAttrs (_: type: type == "regular") entries;
    in
    builtins.attrNames files;

  # List subdirectories in a directory
  listDirs = dir:
    let
      entries = builtins.readDir dir;
      dirs = lib.filterAttrs (_: type: type == "directory") entries;
    in
    builtins.attrNames dirs;

  # Recursively list all files under a directory
  listFilesRecursive = dir:
    let
      entries = builtins.readDir dir;
      processEntry = name: type:
        if type == "regular" then
          [ name ]
        else if type == "directory" then
          map (f: "${name}/${f}") (listFilesRecursive "${dir}/${name}")
        else
          [];
    in
    concatMap (name: processEntry name entries.${name}) (builtins.attrNames entries);

  # Expand a glob pattern relative to a root directory
  # Supports:
  #   - "*.cc" - files matching pattern in current dir
  #   - "src/*.cc" - files matching pattern in src/
  #   - "**/*.cc" - recursive: all matching files in any subdirectory
  #   - "src/**/*.cc" - recursive under src/
  expandGlob = { root, pattern }:
    let
      rootStr = builtins.toString root;

      # Check if pattern is recursive (contains **)
      isRecursive = lib.hasInfix "**" pattern;

      # Split pattern into directory prefix and file pattern
      # e.g., "src/foo/*.cc" -> { dir = "src/foo"; filePattern = "*.cc"; }
      # e.g., "src/**/*.cc" -> { dir = "src"; filePattern = "*.cc"; recursive = true; }
      parsePattern = pat:
        let
          # Handle recursive patterns
          recursiveParts = lib.splitString "/**/" pat;
          hasRecursiveMid = builtins.length recursiveParts == 2;

          # Handle patterns starting with **/
          startsWithRecursive = hasPrefix "**/" pat;
          patAfterStart = if startsWithRecursive then removePrefix "**/" pat else pat;

          # For non-recursive, split on last /
          lastSlash = lastIndexOf "/" pat;
          nonRecursiveDir = if lastSlash == -1 then "." else builtins.substring 0 lastSlash pat;
          nonRecursiveFile = if lastSlash == -1 then pat else builtins.substring (lastSlash + 1) (builtins.stringLength pat) pat;
        in
        if hasRecursiveMid then
          { dir = builtins.elemAt recursiveParts 0; filePattern = builtins.elemAt recursiveParts 1; recursive = true; }
        else if startsWithRecursive then
          { dir = "."; filePattern = patAfterStart; recursive = true; }
        else
          { dir = nonRecursiveDir; filePattern = nonRecursiveFile; recursive = false; };

      parsed = parsePattern pattern;
      baseDir = if parsed.dir == "." then rootStr else "${rootStr}/${parsed.dir}";
      dirPrefix = if parsed.dir == "." then "" else "${parsed.dir}/";

      # Get list of files to check
      filesToCheck =
        if parsed.recursive then
          map (f: "${dirPrefix}${f}") (listFilesRecursive baseDir)
        else
          map (f: "${dirPrefix}${f}") (listFiles baseDir);

      # Filter files matching the pattern
      matchingFiles = filter (f:
        let
          basename = basestring f;
        in
        matchPattern parsed.filePattern basename
      ) filesToCheck;
    in
    matchingFiles;

  # Get basename of a path (last component)
  basestring = path:
    let
      parts = lib.splitString "/" path;
      len = builtins.length parts;
    in
    if len == 0 then path else builtins.elemAt parts (len - 1);

  # Find the last index of a character in a string (-1 if not found)
  lastIndexOf = char: str:
    let
      len = builtins.stringLength str;
      findLast = idx:
        if idx < 0 then -1
        else if builtins.substring idx 1 str == char then idx
        else findLast (idx - 1);
    in
    findLast (len - 1);

  # ==========================================================================
  # Source Normalization
  # ==========================================================================

  # Check if a value is a derivation (has outPath attribute)
  isDerivation = x: builtins.isAttrs x && x ? outPath;

  normalizeSources =
    {
      root,
      sources,
    }:
    let
      rootPath = sanitizePath {
        path = root;
        name = "sources-root";
      };
      rootHost = builtins.toString rootPath;

      # Expand any glob patterns in the sources list
      # Globs are only supported for simple strings, not attrsets or derivations
      # Note: We don't deduplicate here because non-strings (attrsets, derivations)
      # can't be easily compared. Deduplication happens at the string level only.
      expandedStrings = concatMap (source:
        if isGlob source then
          expandGlob { inherit root; pattern = source; }
        else if builtins.isString source then
          [ source ]
        else
          []  # Non-strings handled separately
      ) sources;

      # Get non-string sources (attrsets, derivations)
      nonStringSources = filter (s: !builtins.isString s) sources;

      # Deduplicate string sources and combine with non-strings
      expandedSources = (unique expandedStrings) ++ nonStringSources;

      mkEntry =
        source:
        # Case 1: Derivation source - { drv, rel } or { drv, rel, file }
        # Use this for generated sources from pkgs.writeText, tool outputs, etc.
        if builtins.isAttrs source && source ? drv && isDerivation source.drv then
          let
            rel = source.rel or (throw "nixnative: derivation sources must have 'rel' attribute specifying the relative path");
            relNorm = if hasPrefix "./" rel then removePrefix "./" rel else rel;
            # If 'file' is specified, the derivation is a directory and we need a specific file
            # Otherwise, the derivation IS the file (e.g., from pkgs.writeText)
            store =
              if source ? file then
                "${source.drv}/${source.file}"
              else
                source.drv.outPath;
            objectName = "${sanitizeName relNorm}.o";
          in
          {
            inherit store relNorm objectName;
            host = store; # For error messages
          }
        # Case 2: Attrset with 'rel' (and optional 'path'/'store')
        else if builtins.isAttrs source && source ? rel then
          let
            rel = source.rel;
            relNorm = if hasPrefix "./" rel then removePrefix "./" rel else rel;
            host =
              if source ? path then
                builtins.toString source.path
              else
                "${rootHost}/${relNorm}";
            objectName = "${sanitizeName relNorm}.o";
            _ =
              if source ? store then
                true
              else if builtins.pathExists host then
                true
              else
                throw "nixnative: source '${relNorm}' not found at ${host}. Check that the file exists and the 'root' path is correct.";
          in
          {
            store =
              if source ? store then
                toPathLike source.store
              else
                builtins.path { path = host; };
            inherit relNorm host objectName;
          }
        # Case 3: Simple string (relative path)
        else if builtins.isString source then
          let
            relNorm = if hasPrefix "./" source then removePrefix "./" source else source;
            host = "${rootHost}/${relNorm}";
            objectName = "${sanitizeName relNorm}.o";
            _ =
              if builtins.pathExists host then
                true
              else
                throw "nixnative: source '${relNorm}' not found at ${host}. Check that the file exists and the 'root' path is correct.";
          in
          {
            store = builtins.path { path = host; };
            inherit relNorm host objectName;
          }
        else
          throw "nixnative: sources must be relative strings, attrsets with 'rel', or derivation sources { drv, rel }, got ${showValue source}";
    in
    map mkEntry expandedSources;

  # ==========================================================================
  # Header Set Building
  # ==========================================================================

  headerSet =
    {
      root,
      manifest,
      tu,
      overrides ? { },
    }:
    let
      rootPath = sanitizePath { path = root; };
      rootHost = builtins.toString rootPath;
      entry = manifest.units.${tu.relNorm} or null;
      deps = if entry == null then [ ] else entry.dependencies or [ ];
      mkHeader =
        path:
        let
          rel = if hasPrefix "./" path then removePrefix "./" path else path;
          override = overrides.${rel} or null;
          storePath =
            if override != null then toPathLike override else builtins.path { path = "${rootHost}/${rel}"; };
          host = if override != null then builtins.toString storePath else "${rootHost}/${rel}";
        in
        {
          inherit rel host;
          store = storePath;
        };
    in
    map mkHeader deps;

  # ==========================================================================
  # Source Tree Building
  # ==========================================================================

  mkSourceTree =
    {
      tu,
      headers,
    }:
    let
      headersToLink = builtins.filter (header: header.rel != tu.relNorm) headers;
      headerScripts = lib.concatMapStrings (header: ''
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

  # ==========================================================================
  # Flag Generation
  # ==========================================================================

  toIncludeFlags =
    {
      srcTree,
      includeDirs,
    }:
    let
      toFlag =
        dir:
        if builtins.isString dir then
          "-I${srcTree}/${dir}"
        else if builtins.isPath dir then
          "-I${dir}"
        else if builtins.isAttrs dir && dir ? path then
          "-I${dir.path}"
        else
          throw "nixnative: includeDirs entries must be strings, paths, or attrsets with 'path', got ${showValue dir}";
    in
    map toFlag includeDirs;

  toDefineFlags =
    defines:
    map (
      define:
      if builtins.isString define then
        "-D${define}"
      else if builtins.isAttrs define && define ? name then
        let
          value = define.value or "";
        in
        if value == "" then "-D${define.name}" else "-D${define.name}=${toString value}"
      else
        throw "nixnative: defines must be strings or attrsets with 'name' (and optional 'value'), got ${showValue define}"
    ) defines;

  # ==========================================================================
  # File Capture Utilities
  # ==========================================================================

  # Capture specific files from a directory into a minimal store path.
  #
  # IMPORTANT FOR INCREMENTAL BUILDS:
  # Using `builtins.path { path = root; }` captures the ENTIRE directory,
  # meaning ANY file change invalidates ALL derivations that depend on it.
  # This function captures only the specified files, so changes to other
  # files in the directory do not cause unnecessary rebuilds.
  #
  # Arguments:
  #   root  - The source directory (path)
  #   files - List of relative file paths to capture
  #   name  - Optional name for the store path (default: "captured-files")
  #
  # Returns:
  #   A derivation containing only the specified files with their
  #   relative directory structure preserved.
  #
  # Example:
  #   captureFiles {
  #     root = ./.;
  #     files = [ "templates/foo.j2" "templates/bar.j2" ];
  #   }
  #   # Returns store path containing only those two files
  #
  captureFiles =
    {
      root,
      files,
      name ? "captured-files",
    }:
    let
      rootStr = builtins.toString root;

      # Capture each file individually (content-addressed)
      capturedFiles = map (
        relPath:
        let
          absPath = "${rootStr}/${relPath}";
          # Each file is captured separately - only changes to THIS file
          # will invalidate THIS store path
          store = builtins.path { path = absPath; };
        in
        {
          rel = relPath;
          inherit store;
        }
      ) files;

      # Create a derivation that assembles the files into a directory tree
      assembled = pkgs.runCommand name { } ''
        set -euo pipefail
        mkdir -p "$out"
        ${lib.concatMapStrings (f: ''
          dst="$out/${f.rel}"
          mkdir -p "$(dirname "$dst")"
          cp ${f.store} "$dst"
        '') capturedFiles}
      '';
    in
    assembled;

  # Capture a single file from a directory.
  # Convenience wrapper around builtins.path for explicit single-file capture.
  #
  # Example:
  #   captureFile { root = ./.; file = "src/main.cc"; }
  #
  captureFile =
    {
      root,
      file,
    }:
    let
      rootStr = builtins.toString root;
    in
    builtins.path { path = "${rootStr}/${file}"; };

  # ==========================================================================
  # Object Reference Collection (for dynamic derivations)
  # ==========================================================================

  # Recursively collect object references from library dependencies.
  #
  # This function gathers objectRefs from static libraries and converts
  # legacy linkFlags (from archives, shared libs, external libs) to
  # pseudo-refs that can be passed to the linker.
  #
  # Arguments:
  #   libs - List of library dependencies
  #
  # Returns:
  #   List of { wrapper?, objectName?, ref?, path } records
  #   - Dynamic refs have: wrapper, objectName, ref, path
  #   - Legacy/external refs have: path only
  #
  collectObjectRefs =
    libs:
    let
      collectFromLib = lib:
        if !(builtins.isAttrs lib) then
          # Raw string (e.g., "-lz") - pass through as link flag, not object ref
          []
        else if lib ? objectRefs then
          # New-style static library with object refs
          let
            # Recursively collect from transitive dependencies
            transitiveRefs =
              if lib ? libraries then collectObjectRefs lib.libraries
              else [];
          in
          transitiveRefs ++ lib.objectRefs
        else if lib ? public && lib.public ? linkFlags && lib.public.linkFlags != [] then
          # Legacy library or archive - convert linkFlags to pseudo-refs
          # These don't have compile wrappers, just direct paths
          map (path: { inherit path; wrapper = null; }) lib.public.linkFlags
          ++ (if lib ? libraries then collectObjectRefs lib.libraries else [])
        else if lib ? libraries then
          # Library without own linkFlags but with dependencies
          collectObjectRefs lib.libraries
        else
          [];
    in
    concatMap collectFromLib libs;

  # Collect legacy link flags from libraries.
  # This handles external libraries (pkg-config, etc.) that don't use objectRefs.
  #
  # Arguments:
  #   libs - List of library dependencies
  #
  # Returns:
  #   List of link flag strings (e.g., ["-lz", "/path/to/lib.a"])
  #
  collectLinkFlags =
    libs:
    let
      collectFromLib = lib:
        if builtins.isString lib then
          # Raw string link flag
          [ lib ]
        else if builtins.isAttrs lib then
          # Skip objectRefs-style libs (handled by collectObjectRefs)
          if lib ? objectRefs then
            if lib ? libraries then collectLinkFlags lib.libraries else []
          else if lib ? public && lib.public ? linkFlags then
            lib.public.linkFlags ++ (if lib ? libraries then collectLinkFlags lib.libraries else [])
          else if lib ? libraries then
            collectLinkFlags lib.libraries
          else
            []
        else
          [];
    in
    unique (concatMap collectFromLib libs);
}
