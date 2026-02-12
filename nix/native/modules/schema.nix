# Shared module schema for nixnative.
#
# This is the single source of truth for project/default/target/test/shell
# option types and defaults. Both module evaluation and docs/validation should
# consume this file.
{
  lib,
  defaultsCore,
}:

let
  types = lib.types;

  listOfStrings = types.listOf types.str;
  listOfLinkFlags = types.listOf (types.oneOf [ types.str types.path ]);
  pathLike = types.oneOf [ types.path types.str types.attrs ];
  listOfPathLike = types.listOf pathLike;
  defineType = types.oneOf [ types.str types.attrs ];
  listOfDefines = types.listOf defineType;

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

  targetModule = { lib, name ? "<name>", ... }:
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

        publicLinkFlags = lib.mkOption {
          type = listOfLinkFlags;
          default = [ ];
          description = "Public link flags (libraries).";
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

        publicLinkFlags = lib.mkOption {
          type = listOfLinkFlags;
          default = [ ];
          description = "Default public link flags for libraries.";
        };
      };
    };

  testModule = { name ? "<name>", lib, ... }:
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

  shellModule = { name ? "<name>", lib, ... }:
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

  projectOptionsModule = { lib, ... }:
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
          default = defaultsCore.project;
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
    };

  # Validation schema for `native.project { ... }` (builder API).
  projectBuilderModule = { lib, ... }:
    {
      options =
        (defaultsModule { inherit lib; }).options
        // {
          root = lib.mkOption {
            type = pathLike;
            description = "Project root directory.";
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
            description = "Default toolchain selection.";
          };
        };
    };

  evalSingleOption = { key, type, value }:
    let
      eval = lib.evalModules {
        modules = [
          {
            options.${key} = lib.mkOption { inherit type; };
            config.${key} = value;
          }
        ];
      };
    in
    eval.config.${key};

  validateTargetArgs = args:
    evalSingleOption {
      key = "target";
      type = types.submodule targetModule;
      value = args;
    };

  validateDefaultsArgs = args:
    evalSingleOption {
      key = "defaults";
      type = types.submodule defaultsModule;
      value = args;
    };

  validateTestArgs = args:
    evalSingleOption {
      key = "test";
      type = types.submodule testModule;
      value = args;
    };

  validateShellArgs = args:
    evalSingleOption {
      key = "shell";
      type = types.submodule shellModule;
      value = args;
    };

  validateProjectArgs = args:
    evalSingleOption {
      key = "project";
      type = types.submodule projectBuilderModule;
      value = args;
    };

in
{
  inherit
    types
    listOfStrings
    listOfLinkFlags
    pathLike
    listOfPathLike
    defineType
    listOfDefines
    libraryType
    toolchainType
    toolOutputType
    toolType
    publicType
    emptyPublic
    targetModule
    defaultsModule
    testModule
    shellModule
    projectOptionsModule
    projectBuilderModule
    validateTargetArgs
    validateDefaultsArgs
    validateTestArgs
    validateShellArgs
    validateProjectArgs
    ;
}
