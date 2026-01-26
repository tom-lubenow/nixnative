# Documentation generator for nixnative module options
#
# Extracts options from the module system and generates Markdown documentation.
{ lib }:

let
  types = lib.types;

  # Type aliases (mirrored from modules/project.nix)
  listOfStrings = types.listOf types.str;
  listOfLinkFlags = types.listOf (types.oneOf [ types.str types.path ]);
  pathLike = types.oneOf [ types.path types.str types.attrs ];
  listOfPathLike = types.listOf pathLike;
  defineType = types.oneOf [ types.str types.attrs ];
  listOfDefines = types.listOf defineType;

  toolchainType = types.addCheck types.attrs (value:
    builtins.isAttrs value
    && value ? name
    && value ? languages
  );

  toolOutputType = types.addCheck types.attrs (value:
    builtins.isAttrs value && value ? rel && value ? path
  );

  libraryType = types.oneOf [
    types.str
    types.path
    (types.submodule { options.target = lib.mkOption { type = types.str; }; })
    (types.submodule { options.public = lib.mkOption { type = types.attrs; }; })
    (types.submodule { options.linkFlags = lib.mkOption { type = listOfLinkFlags; }; })
  ];

  # Public interface submodule
  publicType = types.submodule {
    options = {
      includeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Public include directories propagated to dependents.";
      };
      defines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = "Public preprocessor defines propagated to dependents.";
      };
      compileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Public compile flags propagated to dependents.";
      };
      linkFlags = lib.mkOption {
        type = listOfLinkFlags;
        default = [ ];
        description = "Public link flags propagated to dependents.";
      };
    };
  };

  # Tool plugin submodule
  toolType = types.submodule {
    options = {
      name = lib.mkOption {
        type = types.str;
        description = "Tool identifier.";
      };
      outputs = lib.mkOption {
        type = types.listOf toolOutputType;
        default = [ ];
        description = "Generated outputs from the tool (list of `{ rel, path }` entries).";
      };
      includeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Include directories provided by the tool.";
      };
      defines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = "Preprocessor defines from the tool.";
      };
      compileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Compile flags from the tool.";
      };
      evalInputs = lib.mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Packages needed during Nix evaluation.";
      };
      public = lib.mkOption {
        type = publicType;
        default = { };
        description = "Public interface exposed by the tool to dependents.";
      };
    };
    freeformType = types.attrs;
  };

  # ============================================================================
  # Standalone module definitions for documentation extraction
  # ============================================================================

  # Target options (native.targets.<name>.*)
  targetDocModule = {
    options = {
      type = lib.mkOption {
        type = types.nullOr (types.enum [ "executable" "staticLib" "sharedLib" "headerOnly" ]);
        default = null;
        description = ''
          Target type. Determines how the target is built:
          - `executable`: Linked binary
          - `staticLib`: Static library (.a)
          - `sharedLib`: Shared library (.so)
          - `headerOnly`: Header-only library (no compilation)
        '';
      };
      name = lib.mkOption {
        type = types.str;
        default = "<name>";
        description = "Output name for the target. Defaults to the attribute name.";
      };
      root = lib.mkOption {
        type = types.nullOr pathLike;
        default = null;
        description = "Project root directory. Source paths are relative to this.";
      };
      sources = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = ''
          Source files to compile. Can be:
          - Paths: `./src/main.cc`
          - Strings: `"src/*.cc"` (glob patterns)
        '';
      };
      includeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Include directories for this target (private).";
      };
      defines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = ''
          Preprocessor defines. Can be:
          - Strings: `"DEBUG"`, `"VERSION=1"`
          - Attrs: `{ name = "FOO"; value = "bar"; }`
        '';
      };
      compileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Raw compiler flags passed to all source files.";
      };
      languageFlags = lib.mkOption {
        type = types.attrsOf listOfStrings;
        default = { };
        description = ''
          Per-language compile flags. Example:
          ```nix
          languageFlags = {
            cpp = [ "-std=c++20" ];
            c = [ "-std=c11" ];
          };
          ```
        '';
      };
      linkFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Raw linker flags.";
      };
      libraries = lib.mkOption {
        type = types.listOf libraryType;
        default = [ ];
        description = ''
          Library dependencies. Can be:
          - Target reference: `{ target = "myLib"; }`
          - Package: `pkgs.zlib`
          - String/path for manual linking
          - Public interface: `{ public = { includeDirs = [...]; }; }`
        '';
      };
      tools = lib.mkOption {
        type = types.listOf toolType;
        default = [ ];
        description = "Tool plugins for code generation (protobuf, jinja, etc.).";
      };
      compiler = lib.mkOption {
        type = types.nullOr (types.oneOf [ types.str types.attrs ]);
        default = null;
        description = ''
          Compiler selection. Can be:
          - String: `"clang"`, `"gcc"`, `"clang18"`, `"gcc14"`
          - Compiler object from `native.compilers.*`
        '';
      };
      linker = lib.mkOption {
        type = types.nullOr (types.oneOf [ types.str types.attrs ]);
        default = null;
        description = ''
          Linker selection. Can be:
          - String: `"lld"`, `"mold"`, `"ld"`
          - Linker object from `native.linkers.*`
        '';
      };
      toolchain = lib.mkOption {
        type = types.nullOr toolchainType;
        default = null;
        description = "Explicit toolchain object. Overrides compiler/linker settings.";
      };
      contentAddressed = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable content-addressed derivations for better caching.";
      };
      lto = lib.mkOption {
        type = types.nullOr (types.oneOf [ types.bool types.str ]);
        default = null;
        description = ''
          Link-time optimization mode:
          - `false`: Disabled
          - `true` or `"full"`: Full LTO
          - `"thin"`: ThinLTO (faster, recommended)
        '';
      };
      sanitizers = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = ''
          Sanitizers to enable. Common values:
          - `"address"`: AddressSanitizer (ASan)
          - `"undefined"`: UndefinedBehaviorSanitizer (UBSan)
          - `"thread"`: ThreadSanitizer (TSan)
        '';
      };
      coverage = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable code coverage instrumentation.";
      };
      optimize = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optimization level:
          - `"0"`: No optimization (debug)
          - `"1"`, `"2"`, `"3"`: Increasing optimization
          - `"s"`: Optimize for size
          - `"fast"`: Aggressive optimization
        '';
      };
      warnings = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Warnings preset:
          - `"none"`: No warnings
          - `"default"`: Compiler default
          - `"all"`: -Wall
          - `"extra"`: -Wall -Wextra
          - `"pedantic"`: -Wall -Wextra -Wpedantic
        '';
      };
      publicIncludeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Include directories exposed to dependents (for libraries).";
      };
      publicDefines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = "Preprocessor defines exposed to dependents (for libraries).";
      };
      publicCompileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Compile flags exposed to dependents (for libraries).";
      };
    };
  };

  # Defaults options (native.defaults.*)
  defaultsDocModule = {
    options = {
      includeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Default include directories applied to all targets.";
      };
      defines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = "Default preprocessor defines applied to all targets.";
      };
      compileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Default compile flags applied to all targets.";
      };
      languageFlags = lib.mkOption {
        type = types.attrsOf listOfStrings;
        default = { };
        description = "Default per-language compile flags.";
      };
      linkFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Default link flags applied to all targets.";
      };
      libraries = lib.mkOption {
        type = types.listOf libraryType;
        default = [ ];
        description = "Default libraries linked to all targets.";
      };
      tools = lib.mkOption {
        type = types.listOf toolType;
        default = [ ];
        description = "Default tools applied to all targets.";
      };
      contentAddressed = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Default content-addressed setting.";
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
      publicIncludeDirs = lib.mkOption {
        type = listOfPathLike;
        default = [ ];
        description = "Default public include directories for library targets.";
      };
      publicDefines = lib.mkOption {
        type = listOfDefines;
        default = [ ];
        description = "Default public defines for library targets.";
      };
      publicCompileFlags = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Default public compile flags for library targets.";
      };
    };
  };

  # Test options (native.tests.<name>.*)
  testDocModule = {
    options = {
      name = lib.mkOption {
        type = types.str;
        default = "<name>";
        description = "Test derivation name. Defaults to the attribute name.";
      };
      executable = lib.mkOption {
        type = types.nullOr (types.oneOf [ types.str types.attrs ]);
        default = null;
        description = ''
          Executable to run. Can be:
          - String: Target name (e.g., `"myTests"`)
          - Derivation: Direct package reference
        '';
      };
      args = lib.mkOption {
        type = listOfStrings;
        default = [ ];
        description = "Command-line arguments passed to the test executable.";
      };
      stdin = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Input to provide via stdin.";
      };
      expectedOutput = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Expected substring in stdout. Test fails if not found.";
      };
    };
  };

  # Shell options (native.shells.<name>.*)
  shellDocModule = {
    options = {
      name = lib.mkOption {
        type = types.str;
        default = "<name>";
        description = "Development shell name. Defaults to the attribute name.";
      };
      target = lib.mkOption {
        type = types.nullOr (types.oneOf [ types.str types.attrs ]);
        default = null;
        description = ''
          Target to derive toolchain from. Can be:
          - String: Target name (e.g., `"myApp"`)
          - Derivation: Direct package reference
        '';
      };
      toolchain = lib.mkOption {
        type = types.nullOr toolchainType;
        default = null;
        description = "Explicit toolchain. Overrides target-derived toolchain.";
      };
      extraPackages = lib.mkOption {
        type = types.listOf types.anything;
        default = [ ];
        description = "Additional packages to include in the shell (e.g., `pkgs.gdb`).";
      };
      linkCompileCommands = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Create symlink to compile_commands.json for IDE support.";
      };
      symlinkName = lib.mkOption {
        type = types.str;
        default = "compile_commands.json";
        description = "Name of the compile_commands.json symlink.";
      };
      includeTools = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Include common dev tools (clang-tools, gdb, etc.).";
      };
    };
  };

  # Project-level options (native.*)
  projectDocModule = {
    options = {
      root = lib.mkOption {
        type = types.nullOr pathLike;
        default = null;
        description = "Default project root for all targets.";
      };
      compiler = lib.mkOption {
        type = types.nullOr (types.oneOf [ types.str types.attrs ]);
        default = null;
        description = "Default compiler for all targets.";
      };
      linker = lib.mkOption {
        type = types.nullOr (types.oneOf [ types.str types.attrs ]);
        default = null;
        description = "Default linker for all targets.";
      };
      toolchain = lib.mkOption {
        type = types.nullOr toolchainType;
        default = null;
        description = "Default toolchain for all targets.";
      };
      contentAddressed = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Default content-addressed setting for all targets.";
      };
      defaults = lib.mkOption {
        type = types.submodule defaultsDocModule;
        default = { };
        description = "Default settings applied to all targets.";
      };
      targets = lib.mkOption {
        type = types.attrsOf (types.submodule targetDocModule);
        default = { };
        description = "Build targets (executables, libraries).";
      };
      tests = lib.mkOption {
        type = types.attrsOf (types.submodule testDocModule);
        default = { };
        description = "Test definitions.";
      };
      shells = lib.mkOption {
        type = types.attrsOf (types.submodule shellDocModule);
        default = { };
        description = "Development shell definitions.";
      };
      extraPackages = lib.mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Additional packages to expose in project outputs.";
      };
      extraChecks = lib.mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Additional checks to expose in project outputs.";
      };
      packages = lib.mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Built target outputs (read-only, computed).";
        readOnly = true;
      };
      checks = lib.mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Test derivations (read-only, computed).";
        readOnly = true;
      };
      devShells = lib.mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Development shells (read-only, computed).";
        readOnly = true;
      };
    };
  };

  # ============================================================================
  # Markdown generation
  # ============================================================================

  # Convert a type to a human-readable string
  typeToString = type:
    let
      # Get the type description or name
      desc = type.description or type.name or "unknown";
    in
    desc;

  # Format a default value for display
  formatDefault = default:
    if default == null then
      "_none_"
    else if default == [ ] then
      "`[]`"
    else if default == { } then
      "`{}`"
    else if builtins.isBool default then
      "`${lib.boolToString default}`"
    else if builtins.isString default then
      "`\"${default}\"`"
    else
      "`${builtins.toJSON default}`";

  # Generate markdown for a single option
  optionToMarkdown = prefix: name: opt: ''
    ### `${prefix}${name}`

    ${opt.description or "_No description_"}

    **Type:** `${typeToString opt.type}`

    **Default:** ${formatDefault (opt.default or null)}

  '';

  # Check if an attribute is a real option (has _type = "option")
  isOption = opt: opt ? _type && opt._type == "option";

  # Generate markdown for all options in a module
  moduleToMarkdown = title: prefix: module:
    let
      eval = lib.evalModules {
        modules = [ module ];
      };
      options = eval.options;

      # Get option names, excluding:
      # - _module (internal)
      # - nested submodules we document separately
      optionNames = builtins.filter
        (name:
          name != "_module"
          && !(builtins.elem name [ "defaults" "targets" "tests" "shells" ])
          && isOption options.${name})
        (builtins.attrNames options);

      optionDocs = map
        (name: optionToMarkdown prefix name options.${name})
        optionNames;
    in
    ''
      # ${title}

      ${lib.concatStringsSep "\n" optionDocs}
    '';

  # Generate the index page
  generateIndex = ''
    # API Reference

    This documentation is automatically generated from the nixnative module system.

    ## Module Structure

    nixnative uses the Nix module system for configuration. The main entry point is `native.project`:

    ```nix
    native.project {
      modules = [ ./project.nix ];
    }
    ```

    ## Sections

    - [Project Options](project.md) - Top-level project configuration
    - [Target Options](targets.md) - Build target configuration (executables, libraries)
    - [Defaults Options](defaults.md) - Default settings for all targets
    - [Test Options](tests.md) - Test definitions
    - [Shell Options](shells.md) - Development shell configuration
  '';

  # Generate all documentation
  generateDocs = {
    index = generateIndex;

    project = moduleToMarkdown
      "Project Options"
      "native."
      projectDocModule;

    targets = moduleToMarkdown
      "Target Options"
      "native.targets.<name>."
      targetDocModule;

    defaults = moduleToMarkdown
      "Default Options"
      "native.defaults."
      defaultsDocModule;

    tests = moduleToMarkdown
      "Test Options"
      "native.tests.<name>."
      testDocModule;

    shells = moduleToMarkdown
      "Shell Options"
      "native.shells.<name>."
      shellDocModule;
  };

in
{
  inherit generateDocs;
}
