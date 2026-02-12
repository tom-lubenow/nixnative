# Module-first project interface for nixnative
#
# Provides typed options for targets/tests/devShells and an eval helper
# to build packages from module configuration.
{
  lib,
  pkgs,
  utils,
  defaultsCore,
  api,
  helpers,
  projectSchema,
}:

let
  flagListFields = builtins.filter (name: name != "languageFlags") defaultsCore.projectFlagFields;

  isDedupableList = values:
    builtins.all (value: builtins.isString value || builtins.isPath value) values;

  mergeDefaults =
    {
      defaults,
      target,
      mergeOrder ? "defaults-first",
      dedupeFlags ? true,
    }:
    let
      mergeValue = _name: defaultVal: targetVal:
        if targetVal == null then
          defaultVal
        else if builtins.elem _name flagListFields && builtins.isList defaultVal && builtins.isList targetVal then
          utils.mergeFlagLists {
            defaults = defaultVal;
            target = targetVal;
            inherit mergeOrder;
            dedupe = dedupeFlags;
          }
        else if _name == "languageFlags" && builtins.isAttrs defaultVal && builtins.isAttrs targetVal then
          utils.mergeLanguageFlagAttrs {
            defaults = defaultVal;
            target = targetVal;
            inherit mergeOrder;
            dedupe = dedupeFlags;
          }
        else if builtins.isList defaultVal && builtins.isList targetVal then
          let
            merged = defaultVal ++ targetVal;
          in
          if isDedupableList merged then
            lib.unique merged
          else
            merged
        else if builtins.isAttrs defaultVal && builtins.isAttrs targetVal then
          mergeDefaults {
            defaults = defaultVal;
            target = targetVal;
            inherit mergeOrder dedupeFlags;
          }
        else
          targetVal;

      allKeys = lib.unique (builtins.attrNames defaults ++ builtins.attrNames target);

      mergedPairs = map (name:
        let
          defaultVal = defaults.${name} or null;
          targetVal = target.${name} or null;
        in
        {
          inherit name;
          value =
            if defaults ? ${name} && target ? ${name} then
              mergeValue name defaultVal targetVal
            else if defaults ? ${name} then
              defaultVal
            else
              targetVal;
        }
      ) allKeys;
    in
    builtins.listToAttrs mergedPairs;

  projectModule = { config, ... }:
    let
      cfg = config.native;
      defaults =
        defaultsCore.project
        // cfg.defaults
        // {
          root = cfg.root;
          compiler = cfg.compiler;
          linker = cfg.linker;
          toolchain = cfg.toolchain;
        };

      resolveTarget = _name: target:
        let
          mergeToolchain =
            if target.toolchain or null != null then
              target.toolchain
            else
              defaults.toolchain or null;
        in
        mergeDefaults {
          inherit defaults target;
          mergeOrder = utils.flagMergeOrderForToolchain mergeToolchain;
          dedupeFlags = utils.flagDedupeForToolchain mergeToolchain;
        };

      resolvedTargets = lib.mapAttrs resolveTarget cfg.targets;

      # Resolve a target reference: { target = "name"; }, string, or passthrough
      resolveRef = value:
        if builtins.isAttrs value && value ? target then
          packages.${value.target} or (throw "nixnative.project: unknown target '${value.target}'")
        else if builtins.isString value then
          packages.${value} or (throw "nixnative.project: unknown target '${value}'")
        else
          value;

      resolveLibraryRefs = libs:
        map resolveRef libs;

      buildTarget = target:
        let
          baseArgs = builtins.removeAttrs target [ "type" ];
          withLibraries = baseArgs // {
            libraries = resolveLibraryRefs (baseArgs.libraries or [ ]);
          };
          withPublicIncludeDirs =
            if (withLibraries.publicIncludeDirs or [ ]) == [ ] then
              withLibraries // { publicIncludeDirs = withLibraries.includeDirs or [ ]; }
            else
              withLibraries;
          buildArgs =
            if withPublicIncludeDirs.toolchain or null == null then
              builtins.removeAttrs withPublicIncludeDirs [ "toolchain" ]
            else
              withPublicIncludeDirs;
          headerOnlyArgs =
            let
              allowed = [
                "name"
                "root"
                "includeDirs"
                "defines"
                "compileFlags"
                "libraries"
                "publicIncludeDirs"
                "publicDefines"
                "publicCompileFlags"
                "publicLinkFlags"
                "tools"
              ];
              stripped = lib.filterAttrs (name: _value: lib.elem name allowed) withPublicIncludeDirs;
            in
            if stripped.root or null == null then
              builtins.removeAttrs stripped [ "root" ]
            else
              stripped;
        in
        if target.type == null then
          throw "nixnative.project: target '${target.name or "unknown"}' must set type"
        else if target.type == "executable" then
          api.executable buildArgs
        else if target.type == "staticLib" then
          api.staticLib buildArgs
        else if target.type == "sharedLib" then
          api.sharedLib buildArgs
        else if target.type == "headerOnly" then
          helpers.mkHeaderOnly headerOnlyArgs
        else
          throw "nixnative.project: invalid target type for '${target.name or "unknown"}'";

      builtPackages = lib.mapAttrs (_: buildTarget) resolvedTargets;

      buildTest = name: test:
        let
          executable =
            if test.executable == null then
              throw "nixnative.project: test '${test.name or name}' must set executable"
            else
              resolveRef test.executable;
        in
        helpers.mkTest {
          inherit (test) args stdin expectedOutput;
          inherit executable;
          name = test.name;
        };

      builtChecks = lib.mapAttrs buildTest cfg.tests;

      buildShell = name: shell:
        let
          resolvedTarget = if shell.target == null then null else resolveRef shell.target;
        in
        helpers.mkDevShell {
          target = resolvedTarget;
          inherit (shell) toolchain extraPackages linkCompileCommands symlinkName includeTools;
        };

      devShells = lib.mapAttrs buildShell cfg.shells;

      resolveExtraOutputs = extras:
        lib.mapAttrs (_: resolveRef) extras;

      packages = builtPackages // resolveExtraOutputs cfg.extraPackages;
      checks = builtChecks // resolveExtraOutputs cfg.extraChecks;
    in
    {
      imports = [ projectSchema.projectOptionsModule ];

      config = {
        native.packages = packages;
        native.checks = checks;
        native.devShells = devShells;
      };
    };

  evalProject =
    {
      modules,
      specialArgs ? { },
    }:
    let
      modulesList =
        if builtins.isList modules then
          modules
        else
          [ modules ];
      eval = lib.evalModules {
        modules = [ projectModule ] ++ modulesList;
        specialArgs = specialArgs // {
          inherit pkgs lib api helpers;
        };
      };
    in
    {
      inherit (eval.config.native) packages checks devShells;
      config = eval.config.native;
    };

in
{
  inherit evalProject projectModule;
}
