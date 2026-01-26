# Utility functions for nixnative
#
# Common helpers used across the build system.
# Adapted from nix/cpp/utils.nix with updates for the new architecture.
#
{ pkgs, globset ? null }:

let
  lib = pkgs.lib;
  globsetLib =
    if globset == null then
      null
    else if builtins.isAttrs globset && globset ? lib then
      globset.lib
    else
      globset;

  globsetSrc =
    if globset == null then
      null
    else if builtins.isAttrs globset && globset ? outPath then
      globset.outPath
    else if builtins.isPath globset || builtins.isString globset then
      globset
    else
      null;

  globsetInternal =
    if globsetLib != null && globsetSrc != null then
      import "${globsetSrc}/internal" {
        lib = lib // { globset = globsetLib; };
      }
    else
      null;

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
      ___ = checkField "compileFlags" "list";
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
  # Flag Formatting
  # ==========================================================================

  mkIncludeFlag = dir: "-I${toString dir}";

  mkDefineFlag =
    d:
    if builtins.isString d then "-D${d}"
    else if d ? name && d ? value then "-D${d.name}=${toString d.value}"
    else if d ? name then "-D${d.name}"
    else throw "nixnative: invalid define: ${showValue d}";

  compileFlagsForLanguage =
    {
      toolchain,
      language,
      includeDirs ? [ ],
      defines ? [ ],
      compileFlags ? [ ],
      languageFlags ? { },
      extraCFlags ? [ ],
    }:
    let
      langFlags = languageFlags.${language} or [ ];
      platformFlags = toolchain.getPlatformCompileFlags or [ ];
      defaultFlags = toolchain.getDefaultFlagsForLanguage language;
    in
    defaultFlags
    ++ platformFlags
    ++ extraCFlags
    ++ compileFlags
    ++ langFlags
    ++ (map mkIncludeFlag includeDirs)
    ++ (map mkDefineFlag defines);

  # ==========================================================================
  # Public Attribute Handling
  # ==========================================================================

  emptyPublic = {
    includeDirs = [ ];
    defines = [ ];
    compileFlags = [ ];
    linkFlags = [ ];
  };

  mergePublic = a: b: {
    includeDirs = a.includeDirs ++ b.includeDirs;
    defines = a.defines ++ b.defines;
    compileFlags = a.compileFlags ++ b.compileFlags;
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
      emptyPublic // { linkFlags = [ (builtins.toString lib) ]; }
    else
      emptyPublic;

  collectPublic = libs: foldl' mergePublic emptyPublic (map libraryPublic libs);

  # Extract evalInputs from a library (packages needed in sandbox)
  libraryEvalInputs =
    lib: if builtins.isAttrs lib && lib ? evalInputs then ensureList lib.evalInputs else [ ];

  # Collect all evalInputs from libraries
  collectEvalInputs = libs: concatMap libraryEvalInputs libs;

  # ==========================================================================
  # Glob Pattern Expansion
  # ==========================================================================

  # Check if a string contains glob characters
  hasExtendedGlobMeta = s:
    lib.hasInfix "[" s || lib.hasInfix "{" s;

  isGlob = s:
    builtins.isString s && (
      lib.hasInfix "*" s
      || (globsetInternal != null && hasExtendedGlobMeta s)
    );

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
    in
    if globsetInternal != null then
      let
        segments = globsetInternal.globSegments rootStr pattern true;
      in
      filter (s: s != "") segments
    else
      let
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
          # Skip objectRefs-style libs ONLY if objectRefs is non-empty.
          # Ninja-built libs have objectRefs = [] and should use linkFlags instead.
          if lib ? objectRefs && lib.objectRefs != [] then
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
