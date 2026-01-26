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
#   lib = project.staticLib { name = "mylib"; sources = [ "*.c" ]; };
#   app = project.executable { name = "myapp"; sources = [ "main.c" ]; };
#
{
  lib,
  api,
  helpers,
}:

let
  isDedupableList = values:
    builtins.all (value: builtins.isString value || builtins.isPath value) values;

  # Merge two attribute sets, concatenating lists and recursively merging attrs
  # Target values take precedence over defaults for non-list values
  mergeDefaults = defaults: target:
    let
      mergeValue = name: defaultVal: targetVal:
        if targetVal == null then
          defaultVal
        else if builtins.isList defaultVal && builtins.isList targetVal then
          # Lists are concatenated (defaults first, then target additions)
          let
            merged = defaultVal ++ targetVal;
          in
          if isDedupableList merged then lib.unique merged else merged
        else if builtins.isAttrs defaultVal && builtins.isAttrs targetVal then
          # Attrs are recursively merged
          mergeDefaults defaultVal targetVal
        else
          # Scalars: target wins
          targetVal;

      # Get all keys from both defaults and target
      allKeys = lib.unique (
        builtins.attrNames defaults ++ builtins.attrNames target
      );

      # Merge each key
      mergedPairs = map (name:
        let
          hasDefault = defaults ? ${name};
          hasTarget = target ? ${name};
          defaultVal = defaults.${name} or null;
          targetVal = target.${name} or null;
        in
        {
          inherit name;
          value =
            if hasDefault && hasTarget then
              mergeValue name defaultVal targetVal
            else if hasDefault then
              defaultVal
            else
              targetVal;
        }
      ) allKeys;
    in
    builtins.listToAttrs mergedPairs;

  # Create a project with shared defaults
  mkProject =
    {
      # Project root directory (inherited by all targets unless overridden)
      root,

      # Default settings applied to all targets
      # Supported fields: defines, compileFlags, languageFlags, linkFlags,
      #                   includeDirs, libraries, tools, publicDefines,
      #                   publicIncludeDirs, publicCompileFlags
      defaults ? {},

      # Optional: compiler/linker for all targets
      compiler ? null,
      linker ? null,
      toolchain ? null,
    }:
    let
      # Build the toolchain args to pass through
      toolchainArgs =
        (if compiler != null then { inherit compiler; } else {})
        // (if linker != null then { inherit linker; } else {})
        // (if toolchain != null then { inherit toolchain; } else {});

      # Wrap a builder to apply defaults
      wrapBuilder = builder: targetArgs:
        let
          # Start with root from project
          withRoot = { inherit root; } // targetArgs;

          # Merge defaults with target args
          merged = mergeDefaults defaults withRoot;

          # Add toolchain args
          final = toolchainArgs // merged;
        in
        builder final;

      # Wrap the low-level mk* builders too
      wrapMkBuilder = builder: targetArgs:
        let
          withRoot = { inherit root; } // targetArgs;
          merged = mergeDefaults defaults withRoot;
          # For mk* builders, toolchain must be provided by caller or project
          final = (if toolchain != null then { inherit toolchain; } else {}) // merged;
        in
        builder final;

    in
    {
      # Expose the defaults for inspection
      inherit defaults root;

      # High-level builders (resolve compiler/linker automatically)
      executable = wrapBuilder api.executable;
      staticLib = wrapBuilder api.staticLib;
      sharedLib = wrapBuilder api.sharedLib;
      headerOnly = args: helpers.mkHeaderOnly (mergeDefaults defaults ({ inherit root; } // args));

      # Low-level builders (require explicit toolchain)
      mkExecutable = wrapMkBuilder helpers.mkExecutable;
      mkStaticLib = wrapMkBuilder helpers.mkStaticLib;
      mkSharedLib = wrapMkBuilder helpers.mkSharedLib;

      # Utility: create a sub-project with additional defaults
      extend = extraDefaults: mkProject {
        inherit root compiler linker toolchain;
        defaults = mergeDefaults defaults extraDefaults;
      };
    };

in
{
  inherit mkProject;
}
