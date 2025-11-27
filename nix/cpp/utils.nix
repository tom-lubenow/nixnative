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
    unique;
in
rec {
  # ==========================================================================
  # Validation helpers
  # ==========================================================================

  # Validates that a value is a list, with a contextual error message
  assertList = { value, name, context }:
    if builtins.isList value then value
    else throw "nixclang (${context}): '${name}' must be a list, got ${builtins.typeOf value}";

  # Validates the structure of a 'public' attribute set
  validatePublic = { public, context }:
    let
      checkField = field: expected:
        if !(public ? ${field}) then
          throw "nixclang (${context}): public attribute missing required field '${field}'"
        else if expected == "list" && !(builtins.isList public.${field}) then
          throw "nixclang (${context}): public.${field} must be a list, got ${builtins.typeOf public.${field}}"
        else
          true;
      _ = checkField "includeDirs" "list";
      __ = checkField "defines" "list";
      ___ = checkField "cxxFlags" "list";
      ____ = checkField "linkFlags" "list";
    in
    public;

  # Formats a value for error messages
  showValue = value:
    if builtins.isString value then "'${value}'"
    else if builtins.isPath value then "<path: ${toString value}>"
    else if builtins.isAttrs value then
      if value ? name then "<attrset with name='${value.name}'>"
      else if value ? rel then "<attrset with rel='${value.rel}'>"
      else "<attrset with keys: ${concatStringsSep ", " (builtins.attrNames value)}>"
    else if builtins.isList value then "<list of ${toString (builtins.length value)} items>"
    else "<${builtins.typeOf value}>";
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
    else throw "nixclang: expected a path-like value (path, string, or attrset with 'path'/'outPath'), got ${showValue value}";

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
      throw "nixclang: includeDirs entries must be relative strings, paths, or attrsets with 'path', got ${showValue dir}";

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
            else throw "nixclang: sources must be relative strings or attrsets with 'rel' attribute, got ${showValue source}";
          relNorm =
            if hasPrefix "./" rel then removePrefix "./" rel else rel;
          host =
            if builtins.isAttrs source && source ? path then builtins.toString source.path
            else "${rootHost}/${relNorm}";
          objectName = "${sanitizeName relNorm}.o";
          _ = if builtins.pathExists host then true
              else throw "nixclang: source '${relNorm}' not found at ${host}. Check that the file exists and the 'root' path is correct.";
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
        else throw "nixclang: includeDirs entries must be strings, paths, or attrsets with 'path', got ${showValue dir}";
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
          throw "nixclang: defines must be strings or attrsets with 'name' (and optional 'value'), got ${showValue define}"
      )
      defines;
}
