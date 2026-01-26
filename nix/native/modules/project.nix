# Module-first project interface for nixnative
#
# Provides typed options for targets/tests/devShells and an eval helper
# to build packages from module configuration.
{
  lib,
  pkgs,
  api,
  helpers,
}:

let
  types = lib.types;

  listOfStrings = types.listOf types.str;
  listOfLinkFlags = types.listOf (types.oneOf [ types.str types.path ]);
  pathLike = types.oneOf [ types.path types.str types.attrs ];
  listOfPathLike = types.listOf pathLike;
  defineType = types.oneOf [ types.str types.attrs ];
  listOfDefines = types.listOf defineType;

  isDedupableList = values:
    builtins.all (value: builtins.isString value || builtins.isPath value) values;

  emptyPublic = {
    includeDirs = [ ];
    defines = [ ];
    compileFlags = [ ];
    linkFlags = [ ];
  };

  publicType = types.submodule ({ lib, ... }: {
    options = {
      includeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Public include dirs.";
      };

      defines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = "Public defines.";
      };

      compileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Public compile flags.";
      };

      linkFlags = lib.mkOption {
        type = listOfLinkFlags;
        default = [ ];
        description = "Public link flags.";
      };
    };
  });

  libraryTargetRefType =
    types.addCheck (types.submodule ({ lib, ... }: {
      options = {
        target = lib.mkOption {
          type = types.str;
          description = "Target reference name.";
        };
      };
    })) (value: builtins.isAttrs value && value ? target);

  libraryPublicType =
    types.addCheck (types.submodule ({ lib, ... }: {
      options = {
        public = lib.mkOption {
          type = publicType;
          description = "Public interface for a library dependency.";
        };
      };
      freeformType = types.attrs;
    })) (value: builtins.isAttrs value && value ? public);

  libraryLinkFlagsType =
    types.addCheck (types.submodule ({ lib, ... }: {
      options = {
        linkFlags = lib.mkOption {
          type = listOfLinkFlags;
          description = "Raw link flags for a library dependency.";
        };
      };
      freeformType = types.attrs;
    })) (value: builtins.isAttrs value && value ? linkFlags);

  libraryType = types.oneOf [
    types.str
    types.path
    libraryTargetRefType
    libraryPublicType
    libraryLinkFlagsType
  ];

  toolchainType =
    types.addCheck types.attrs (
      value:
      builtins.isAttrs value
      && value ? name
      && value ? languages
      && builtins.isAttrs value.languages
      && value.languages != { }
      && value ? linker
      && builtins.isAttrs value.linker
      && value.linker ? driverFlag
      && value ? targetPlatform
    );

  isPathLikeValue = value:
    builtins.isPath value
    || builtins.isString value
    || (builtins.isAttrs value && (value ? path || value ? outPath));

  toolOutputType =
    types.addCheck types.attrs (
      value:
      let
        relValue =
          if value ? rel then
            value.rel
          else if value ? relative then
            value.relative
          else
            null;
        pathValue =
          if value ? path then
            value.path
          else if value ? store then
            value.store
          else
            null;
      in
      builtins.isAttrs value
      && relValue != null
      && builtins.isString relValue
      && pathValue != null
      && isPathLikeValue pathValue
    );

  toolType = types.submodule ({ lib, ... }: {
    options = {
      name = lib.mkOption {
        type = types.str;
        description = "Tool identifier.";
      };

      outputs = lib.mkOption {
        type = types.listOf toolOutputType;
        default = [ ];
        description = "Generated outputs from the tool.";
      };

      includeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Include dirs provided by the tool.";
      };

      defines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = "Additional preprocessor defines from the tool.";
      };

      compileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Additional compile flags from the tool.";
      };

      evalInputs = lib.mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Evaluation inputs for the tool.";
      };

      public = lib.mkOption {
        type = publicType;
        default = emptyPublic;
        description = "Public interface exposed by the tool.";
      };
    };
    freeformType = types.attrs;
  });

  mergeDefaults = defaults: target:
    let
      mergeValue = _name: defaultVal: targetVal:
        if targetVal == null then
          defaultVal
        else if builtins.isList defaultVal && builtins.isList targetVal then
          let
            merged = defaultVal ++ targetVal;
          in
          if isDedupableList merged then
            lib.unique merged
          else
            merged
        else if builtins.isAttrs defaultVal && builtins.isAttrs targetVal then
          mergeDefaults defaultVal targetVal
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

  targetModule = { config, lib, name, ... }:
    {
      options = {
        type = lib.mkOption {
          type = types.nullOr (types.enum [
            "executable"
            "staticLib"
            "sharedLib"
            "headerOnly"
          ]);
          default = null;
          description = "Target type.";
        };

        name = lib.mkOption {
          type = types.str;
          default = name;
          description = "Output name for the target.";
        };

        root = lib.mkOption {
          type = types.nullOr pathLike;
          default = null;
          description = "Project root for the target.";
        };

        sources = lib.mkOption {
          type = listOfPathLike;
          default = [ ];
          description = "Source files for the target.";
        };

        includeDirs = lib.mkOption {
          type = listOfPathLike;
          default = [ ];
          description = "Include directories.";
        };

        defines = lib.mkOption {
          type = listOfDefines;
          default = [ ];
          description = "Preprocessor defines.";
        };

        compileFlags = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Raw compile flags.";
        };

        languageFlags = lib.mkOption {
          type = types.attrsOf listOfStrings;
          default = { };
          description = "Per-language compile flags.";
        };

        linkFlags = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Raw link flags.";
        };

        lto = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.bool types.str ]);
          default = null;
          description = "LTO mode: false, true, \"thin\", or \"full\".";
        };

        sanitizers = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Sanitizers to enable.";
        };

        coverage = lib.mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = "Enable coverage instrumentation.";
        };

        optimize = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optimization level (e.g., \"0\", \"2\", \"s\", \"fast\").";
        };

        warnings = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Warnings preset (e.g., \"all\", \"extra\").";
        };

        libraries = lib.mkOption {
          type = types.listOf libraryType;
          default = [ ];
          description = "Library dependencies.";
        };

        tools = lib.mkOption {
          type = types.listOf toolType;
          default = [ ];
          description = "Tool plugins (code generators, etc.).";
        };

        compiler = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.str types.attrs ]);
          default = null;
          description = "Compiler selection for this target.";
        };

        linker = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.str types.attrs ]);
          default = null;
          description = "Linker selection for this target.";
        };

        toolchain = lib.mkOption {
          type = types.nullOr toolchainType;
          default = null;
          description = "Explicit toolchain for this target.";
        };

        publicIncludeDirs = lib.mkOption {
          type = listOfPathLike;
          default = [ ];
          description = "Public include dirs (libraries).";
        };

        publicDefines = lib.mkOption {
          type = listOfDefines;
          default = [ ];
          description = "Public defines (libraries).";
        };

        publicCompileFlags = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Public compile flags (libraries).";
        };

      };

    };

  defaultsModule = { lib, ... }:
    {
      options = {
        includeDirs = lib.mkOption {
          type = listOfPathLike;
          default = [ ];
          description = "Default include directories.";
        };

        defines = lib.mkOption {
          type = listOfDefines;
          default = [ ];
          description = "Default preprocessor defines.";
        };

        compileFlags = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Default compile flags.";
        };

        languageFlags = lib.mkOption {
          type = types.attrsOf listOfStrings;
          default = { };
          description = "Default per-language compile flags.";
        };

        linkFlags = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Default link flags.";
        };

        libraries = lib.mkOption {
          type = types.listOf libraryType;
          default = [ ];
          description = "Default libraries.";
        };

        tools = lib.mkOption {
          type = types.listOf toolType;
          default = [ ];
          description = "Default tools.";
        };

        publicIncludeDirs = lib.mkOption {
          type = listOfPathLike;
          default = [ ];
          description = "Default public include dirs for libraries.";
        };

        publicDefines = lib.mkOption {
          type = listOfDefines;
          default = [ ];
          description = "Default public defines for libraries.";
        };

        publicCompileFlags = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Default public compile flags for libraries.";
        };

        lto = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.bool types.str ]);
          default = null;
          description = "Default LTO mode.";
        };

        sanitizers = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Default sanitizers.";
        };

        coverage = lib.mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = "Default coverage setting.";
        };

        optimize = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Default optimization level.";
        };

        warnings = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Default warnings preset.";
        };
      };
    };

  testModule = { name, lib, ... }:
    {
      options = {
        name = lib.mkOption {
          type = types.str;
          default = name;
          description = "Test derivation name.";
        };

        executable = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.str types.attrs ]);
          default = null;
          description = "Executable target (name or derivation).";
        };

        args = lib.mkOption {
          type = listOfStrings;
          default = [ ];
          description = "Arguments passed to the executable.";
        };

        stdin = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional stdin for the test.";
        };

        expectedOutput = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional expected output substring.";
        };
      };
    };

  shellModule = { name, lib, ... }:
    {
      options = {
        name = lib.mkOption {
          type = types.str;
          default = name;
          description = "Dev shell name.";
        };

        target = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.str types.attrs ]);
          default = null;
          description = "Target to derive toolchain from.";
        };

        toolchain = lib.mkOption {
          type = types.nullOr toolchainType;
          default = null;
          description = "Explicit toolchain for the dev shell.";
        };

        extraPackages = lib.mkOption {
          type = types.listOf types.anything;
          default = [ ];
          description = "Extra packages to include.";
        };

        linkCompileCommands = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Symlink compile_commands.json if available.";
        };

        symlinkName = lib.mkOption {
          type = types.str;
          default = "compile_commands.json";
          description = "Symlink name for compile commands.";
        };

        includeTools = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Include common dev tools (clang-tools, gdb).";
        };
      };
    };

  projectModule = { config, lib, ... }:
    let
      cfg = config.native;
      defaults =
        cfg.defaults
        // {
          root = cfg.root;
          compiler = cfg.compiler;
          linker = cfg.linker;
          toolchain = cfg.toolchain;
        };

      resolveTarget = _name: target:
        mergeDefaults defaults target;

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
      options.native = {
        root = lib.mkOption {
          type = types.nullOr pathLike;
          default = null;
          description = "Default project root.";
        };

        compiler = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.str types.attrs ]);
          default = null;
          description = "Default compiler selection.";
        };

        linker = lib.mkOption {
          type = types.nullOr (types.oneOf [ types.str types.attrs ]);
          default = null;
          description = "Default linker selection.";
        };

        toolchain = lib.mkOption {
          type = types.nullOr toolchainType;
          default = null;
          description = "Default toolchain for all targets.";
        };

        defaults = lib.mkOption {
          type = types.submodule defaultsModule;
          default = { };
          description = "Default target settings.";
        };

        targets = lib.mkOption {
          type = types.attrsOf (types.submodule targetModule);
          default = { };
          description = "Build targets.";
        };

        tests = lib.mkOption {
          type = types.attrsOf (types.submodule testModule);
          default = { };
          description = "Test definitions.";
        };

        shells = lib.mkOption {
          type = types.attrsOf (types.submodule shellModule);
          default = { };
          description = "Development shells.";
        };

        extraPackages = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "Additional packages to expose alongside targets.";
        };

        extraChecks = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "Additional checks to expose alongside tests.";
        };

        packages = lib.mkOption {
          type = types.attrsOf types.anything;
          readOnly = true;
          description = "Built target outputs.";
        };

        checks = lib.mkOption {
          type = types.attrsOf types.anything;
          readOnly = true;
          description = "Test derivations.";
        };

        devShells = lib.mkOption {
          type = types.attrsOf types.anything;
          readOnly = true;
          description = "Development shells.";
        };
      };

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
