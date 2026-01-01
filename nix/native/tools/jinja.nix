# Jinja2 template tool plugin for nixnative
#
# Generates C/C++ code from Jinja2 templates.
# Useful for generating configuration headers, enum definitions, etc.
#
{
  pkgs,
  lib,
  mkTool,
}:

let
  inherit (lib) concatStringsSep removeSuffix hasSuffix;

  # Python script for Jinja2 rendering
  jinjaRenderer = pkgs.writeText "jinja_render.py" ''
    #!/usr/bin/env python3
    import json
    import os
    import sys
    from pathlib import Path

    try:
        from jinja2 import Environment, FileSystemLoader, StrictUndefined
    except ImportError:
        print("Error: jinja2 not available", file=sys.stderr)
        sys.exit(1)

    def main():
        if len(sys.argv) < 4:
            print("Usage: jinja_render.py <template_dir> <output_dir> <config_json>", file=sys.stderr)
            sys.exit(1)

        template_dir = Path(sys.argv[1])
        output_dir = Path(sys.argv[2])
        config_json = sys.argv[3]

        # Load configuration
        config = json.loads(config_json)
        templates = config.get("templates", [])
        variables = config.get("variables", {})

        # Setup Jinja2 environment
        env = Environment(
            loader=FileSystemLoader(str(template_dir)),
            undefined=StrictUndefined,
            keep_trailing_newline=True,
        )

        # Render each template
        for tmpl_config in templates:
            tmpl_path = tmpl_config["template"]
            out_path = tmpl_config["output"]
            tmpl_vars = {**variables, **tmpl_config.get("variables", {})}

            template = env.get_template(tmpl_path)
            rendered = template.render(**tmpl_vars)

            out_file = output_dir / out_path
            out_file.parent.mkdir(parents=True, exist_ok=True)
            out_file.write_text(rendered)
            print(f"Generated: {out_path}")

    if __name__ == "__main__":
        main()
  '';

  # Jinja transformation
  jinjaTransform =
    {
      inputFiles,
      root,
      config,
    }:
    let
      templates =
        config.templates or (map (f: {
          template = if builtins.isAttrs f && f ? rel then f.rel else f;
          output = removeSuffix ".j2" (
            removeSuffix ".jinja2" (if builtins.isAttrs f && f ? rel then f.rel else f)
          );
        }) inputFiles);

      variables = config.variables or { };

      # Check if any templates are store paths (from writeText)
      isStorePath = path: lib.hasPrefix "/nix/store/" path;
      storePathTemplates = builtins.filter (t: isStorePath t.template) templates;
      localTemplates = builtins.filter (t: !isStorePath t.template) templates;

      # Create a derivation that collects all template files into one directory
      templateInputs = pkgs.runCommand "jinja-inputs" { } (
        ''
          mkdir -p $out
          # Copy store-path templates to output with their basename
        ''
        + concatStringsSep "\n" (
          map (
            t:
            let
              baseName = builtins.baseNameOf t.template;
            in
            "cp ${t.template} $out/${baseName}"
          ) storePathTemplates
        )
      );

      # Rewrite templates to use basenames for store paths
      rewrittenTemplates = map (
        t: if isStorePath t.template then t // { template = builtins.baseNameOf t.template; } else t
      ) templates;

      configJson = builtins.toJSON {
        templates = rewrittenTemplates;
        inherit variables;
      };

      hasStorePathTemplates = storePathTemplates != [ ];
    in
    pkgs.runCommand "jinja-gen"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.jinja2 ])) ];
        src = root;
      }
      ''
        set -euo pipefail
        mkdir -p $out

        # Merge source templates with any store-path templates
        TEMPLATE_DIR="$src"
        ${lib.optionalString hasStorePathTemplates ''
          # Create merged template directory
          TEMPLATE_DIR=$(mktemp -d)
          cp -r "$src"/* "$TEMPLATE_DIR/" 2>/dev/null || true
          cp ${templateInputs}/* "$TEMPLATE_DIR/" 2>/dev/null || true
        ''}

        ${pkgs.python3.withPackages (ps: [ ps.jinja2 ])}/bin/python3 \
          ${jinjaRenderer} \
          "$TEMPLATE_DIR" \
          "$out" \
          '${configJson}'
      '';

  # Jinja output schema
  jinjaOutputs =
    {
      drv,
      inputFiles,
      config,
    }:
    let
      templates =
        config.templates or (map (f: {
          template = if builtins.isAttrs f && f ? rel then f.rel else f;
          output = removeSuffix ".j2" (
            removeSuffix ".jinja2" (if builtins.isAttrs f && f ? rel then f.rel else f)
          );
        }) inputFiles);

      mkOutput = tmpl: {
        rel = tmpl.output;
        path = "${drv}/${tmpl.output}";
      };
    in
    {
      outputs = map mkOutput templates;
      includeDirs = [ { path = drv; } ];
      defines = [ ];
      compileFlags = [ ];
      linkFlags = [ ];
    };

in
rec {
  # ==========================================================================
  # Jinja2 Tool
  # ==========================================================================

  jinja = mkTool {
    name = "jinja";

    transform = jinjaTransform;
    outputs = jinjaOutputs;

    # No runtime dependencies for Jinja (it's compile-time only)
    dependencies = [ ];

    defaultConfig = {
      variables = { };
    };
  };

  # ==========================================================================
  # Convenience: Run jinja directly
  # ==========================================================================

  # Helper to run jinja on template files
  generate =
    {
      inputFiles,
      root ? ./.,
      config ? { },
    }:
    jinja.run { inherit inputFiles root config; };

  # ==========================================================================
  # Specialized Generators
  # ==========================================================================

  # Generate a config header from variables
  configHeader =
    {
      name,
      variables,
      root ? ./.,
      templateContent ? null,
    }:
    let
      # Default template for config headers
      defaultTemplate = ''
        // Auto-generated configuration header
        // Do not edit directly

        #pragma once

        {% for key, value in config.items() %}
        {% if value is string %}
        #define {{ key }} "{{ value }}"
        {% elif value is number %}
        #define {{ key }} {{ value }}
        {% elif value is sameas true %}
        #define {{ key }} 1
        {% elif value is sameas false %}
        // #define {{ key }} 0  // disabled
        {% endif %}
        {% endfor %}
      '';

      template = if templateContent != null then templateContent else defaultTemplate;

      # Create a temporary template file
      templateFile = pkgs.writeText "${name}.h.j2" template;
    in
    jinja.run {
      inputFiles = [ ];
      inherit root;
      config = {
        templates = [
          {
            template = builtins.toString templateFile;
            output = "${name}.h";
            variables = {
              config = variables;
            };
          }
        ];
      };
    };

  # Generate an enum from a list of values
  enumGenerator =
    {
      name,
      values,
      root ? ./.,
      namespace ? null,
    }:
    let
      template = ''
        // Auto-generated enum
        #pragma once

        {% if namespace %}namespace {{ namespace }} { {% endif %}

        enum class {{ name }} {
        {% for value in values %}
            {{ value }}{% if not loop.last %},{% endif %}

        {% endfor %}
        };

        {% if namespace %}} // namespace {{ namespace }}{% endif %}
      '';

      templateFile = pkgs.writeText "${name}_enum.h.j2" template;
    in
    jinja.run {
      inputFiles = [ ];
      inherit root;
      config = {
        templates = [
          {
            template = builtins.toString templateFile;
            output = "${name}.h";
            variables = { inherit name values namespace; };
          }
        ];
      };
    };
}
