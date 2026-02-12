# Documentation generator for nixnative module options.
#
# Option metadata is sourced directly from the shared schema definitions in
# nix/native/modules/schema.nix.
{ lib }:

let
  defaultsCore = import ../native/core/defaults.nix;
  schema = import ../native/modules/schema.nix {
    inherit lib defaultsCore;
  };

  # Convert a type to a human-readable string.
  typeToString = type:
    type.description or type.name or "unknown";

  # Format a default value for display.
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

  # Check if an attribute is a real option (has _type = "option").
  isOption = opt: opt ? _type && opt._type == "option";

  optionToMarkdown = prefix: name: opt: ''
    ### `${prefix}${name}`

    ${opt.description or "_No description_"}

    **Type:** `${typeToString opt.type}`

    **Default:** ${formatDefault (opt.default or null)}

  '';

  moduleOptions = module:
    let
      eval = lib.evalModules {
        modules = [ module ];
      };
    in
    eval.options;

  optionsToMarkdown =
    {
      title,
      prefix,
      options,
      exclude ? [ ],
    }:
    let
      optionNames = builtins.filter
        (name:
          name != "_module"
          && !(builtins.elem name exclude)
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

  projectOptions = (moduleOptions (schema.projectOptionsModule { inherit lib; })).native;
  targetOptions = moduleOptions (schema.targetModule { inherit lib; name = "<name>"; });
  defaultsOptions = moduleOptions (schema.defaultsModule { inherit lib; });
  testOptions = moduleOptions (schema.testModule { inherit lib; name = "<name>"; });
  shellOptions = moduleOptions (schema.shellModule { inherit lib; name = "<name>"; });

  generateIndex = ''
    # API Reference

    This documentation is automatically generated from the nixnative schema.

    ## Sections

    - [Project Options](project.md) - Top-level project configuration
    - [Target Options](targets.md) - Build target configuration (executables, libraries)
    - [Defaults Options](defaults.md) - Default settings for all targets
    - [Test Options](tests.md) - Test definitions
    - [Shell Options](shells.md) - Development shell configuration
  '';

  generateDocs = {
    index = generateIndex;

    project = optionsToMarkdown {
      title = "Project Options";
      prefix = "native.";
      options = projectOptions;
      exclude = [
        "defaults"
        "targets"
        "tests"
        "shells"
      ];
    };

    targets = optionsToMarkdown {
      title = "Target Options";
      prefix = "native.targets.<name>.";
      options = targetOptions;
    };

    defaults = optionsToMarkdown {
      title = "Default Options";
      prefix = "native.defaults.";
      options = defaultsOptions;
    };

    tests = optionsToMarkdown {
      title = "Test Options";
      prefix = "native.tests.<name>.";
      options = testOptions;
    };

    shells = optionsToMarkdown {
      title = "Shell Options";
      prefix = "native.shells.<name>.";
      options = shellOptions;
    };
  };
in
{
  inherit generateDocs;
}
