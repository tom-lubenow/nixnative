# Project defaults for nixnative
#
# mkProject creates a scoped set of builders with shared defaults,
# reducing boilerplate in projects with many targets.
#
# Usage:
#   project = native.mkProject {
#     root = ./.;
#     defaults = {
#       defines = [ "HAVE_CONFIG_H" ];
#       compileFlags = [ "-Wall" ];
#       languageFlags = { c = [ "-std=gnu11" ]; };
#     };
#   };
#
#   lib = project.staticLib { name = "mylib"; sources = [ "src/foo.c" "src/bar.c" ]; };
#   app = project.executable { name = "myapp"; sources = [ "main.c" ]; };
#
{
  lib,
  utils,
  defaultsCore,
  api,
  helpers,
}:

let
  legacyFlagAliases = [
    "cFlags"
    "cxxFlags"
    "ldFlags"
  ];

  assertNoLegacyFlagAliases =
    { context, args }:
    let
      found = builtins.filter (field: args ? ${field}) legacyFlagAliases;
    in
    if found == [ ] then
      null
    else
      throw "nixnative.${context}: unsupported flag fields: ${lib.concatStringsSep ", " found}. Use compileFlags/languageFlags/linkFlags instead.";

  isDedupableList = values:
    builtins.all (value: builtins.isString value || builtins.isPath value) values;

  flagSetFrom = attrs: {
    compileFlags = attrs.compileFlags or [ ];
    linkFlags = attrs.linkFlags or [ ];
    languageFlags = attrs.languageFlags or { };
    publicCompileFlags = attrs.publicCompileFlags or [ ];
    publicLinkFlags = attrs.publicLinkFlags or [ ];
  };

  # Merge two attribute sets for project defaults.
  # Non-flag lists are deduped (first occurrence wins); flags use policy merge order.
  mergeDefaults =
    {
      defaults,
      target,
      toolchain ? null,
    }:
    let
      listFields = defaultsCore.projectListFields;

      scalarDefaults = builtins.removeAttrs defaults listFields;
      scalarTarget = builtins.removeAttrs target listFields;

      mergedLists = lib.foldl' (
        acc: field:
        let
          merged = (defaults.${field} or [ ]) ++ (target.${field} or [ ]);
          value = if isDedupableList merged then lib.unique merged else merged;
        in
        if merged == [ ] then acc else acc // { ${field} = value; }
      ) { } listFields;

      mergeOrder = utils.flagMergeOrderForToolchain toolchain;
      dedupe = utils.flagDedupeForToolchain toolchain;
      mergedFlags = utils.mergeFlagSets {
        defaults = flagSetFrom defaults;
        target = flagSetFrom target;
        inherit mergeOrder dedupe;
      };
    in
    scalarDefaults // scalarTarget // mergedLists // mergedFlags;

  # Create a project with shared defaults
  mkProject =
    {
      # Project root directory (inherited by all targets unless overridden)
      root,

      # Default settings applied to all targets
      # Supported fields: defines, compileFlags, languageFlags, linkFlags,
      #                   includeDirs, libraries, tools, publicDefines,
      #                   publicIncludeDirs, publicCompileFlags, publicLinkFlags
      defaults ? {},

      # Optional: compiler/linker for all targets
      compiler ? null,
      linker ? null,
      toolchain ? null,
    }:
    let
      _legacyDefaultsCheck = assertNoLegacyFlagAliases { context = "mkProject(defaults)"; args = defaults; };
      baseDefaults = defaultsCore.project // defaults;

      # Build the toolchain args to pass through
      toolchainArgs =
        (if compiler != null then { inherit compiler; } else {})
        // (if linker != null then { inherit linker; } else {})
        // (if toolchain != null then { inherit toolchain; } else {});

      # Wrap a builder to apply defaults
      wrapBuilder = builder: targetArgs:
        let
          _legacyTargetCheck = assertNoLegacyFlagAliases { context = "mkProject(target)"; args = targetArgs; };

          # Start with root from project
          withRoot = { inherit root; } // targetArgs;

          # Merge defaults with target args
          merged = mergeDefaults {
            defaults = baseDefaults;
            target = withRoot;
            toolchain = withRoot.toolchain or toolchain;
          };

          # Add toolchain args
          final = toolchainArgs // merged;
        in
        builtins.seq _legacyTargetCheck (builder final);

      # Wrap the low-level mk* builders too
      wrapMkBuilder = builder: targetArgs:
        let
          _legacyTargetCheck = assertNoLegacyFlagAliases { context = "mkProject(target)"; args = targetArgs; };
          withRoot = { inherit root; } // targetArgs;
          merged = mergeDefaults {
            defaults = baseDefaults;
            target = withRoot;
            toolchain = withRoot.toolchain or toolchain;
          };
          # For mk* builders, toolchain must be provided by caller or project
          final = (if toolchain != null then { inherit toolchain; } else {}) // merged;
        in
        builtins.seq _legacyTargetCheck (builder final);

    in
    builtins.seq _legacyDefaultsCheck {
      # Expose the defaults for inspection
      defaults = baseDefaults;
      inherit root;

      # High-level builders (resolve compiler/linker automatically)
      executable = wrapBuilder api.executable;
      staticLib = wrapBuilder api.staticLib;
      sharedLib = wrapBuilder api.sharedLib;
      headerOnly = args:
        helpers.mkHeaderOnly (mergeDefaults {
          defaults = baseDefaults;
          target = ({ inherit root; } // args);
          toolchain = toolchain;
        });

      # Low-level builders (require explicit toolchain)
      mkExecutable = wrapMkBuilder helpers.mkExecutable;
      mkStaticLib = wrapMkBuilder helpers.mkStaticLib;
      mkSharedLib = wrapMkBuilder helpers.mkSharedLib;

      # Utility: create a sub-project with additional defaults
      extend = extraDefaults: mkProject {
        inherit root compiler linker toolchain;
        defaults = mergeDefaults {
          defaults = baseDefaults;
          target = extraDefaults;
          inherit toolchain;
        };
      };
    };

in
{
  inherit mkProject;
}
