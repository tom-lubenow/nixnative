# Jinja Templates Example

This example demonstrates standalone Jinja2 template code generation using `native.tools.jinja`.

## What This Demonstrates

- Using `native.tools.jinja.run` for template-based code generation
- Multiple templates with different output types (headers, sources)
- Passing variables to templates
- Template-generated configuration and enum definitions
- Using convenience helpers `configHeader` and `enumGenerator`

## Project Structure

```
jinja-templates/
├── flake.nix              # Build definitions
├── templates/
│   ├── config.h.j2        # Configuration header template
│   ├── messages.h.j2      # Message strings template
│   └── messages.cc.j2     # Message implementation template
└── main.cc                # Application using generated code
```

## Build and Run

```sh
nix build
./result/bin/jinja-example
```

Expected output:
```
Jinja Templates Example
=======================

Configuration:
  App Name: jinja-example
  Version: 1.2.3
  Debug: enabled
  Max Connections: 100

Messages:
  WELCOME: Welcome to the application!
  GOODBYE: Thank you for using jinja-example!
  ERROR: An error has occurred.

Status enum values: IDLE, RUNNING, PAUSED, STOPPED

All templates working correctly!
```

## How It Works

### Method 1: Template Files

Create `.j2` template files and use `jinja.run`:

```nix
protoGen = native.tools.jinja.run {
  inputFiles = [ "templates/config.h.j2" "templates/messages.h.j2" ];
  root = ./.;
  config = {
    variables = {
      appName = "my-app";
      version = "1.0.0";
    };
  };
};
```

Templates use Jinja2 syntax:
```jinja
#pragma once
#define APP_NAME "{{ appName }}"
#define VERSION "{{ version }}"
```

### Method 2: Config Header Helper

For simple configuration headers:

```nix
configGen = native.tools.configHeader {
  name = "app_config";
  variables = {
    DEBUG = true;
    VERSION = "1.0.0";
    MAX_SIZE = 1024;
  };
};
```

Generates:
```c
#pragma once
#define DEBUG 1
#define VERSION "1.0.0"
#define MAX_SIZE 1024
```

### Method 3: Enum Generator Helper

For generating C++ enums:

```nix
enumGen = native.tools.enumGenerator {
  name = "Status";
  namespace = "app";
  values = [ "IDLE" "RUNNING" "PAUSED" "STOPPED" ];
};
```

Generates:
```cpp
#pragma once
namespace app {
enum class Status {
    IDLE,
    RUNNING,
    PAUSED,
    STOPPED,
};
} // namespace app
```

## Template Syntax

Jinja2 templates support:

| Syntax | Description | Example |
|--------|-------------|---------|
| `{{ var }}` | Variable substitution | `{{ appName }}` |
| `{% if %}` | Conditionals | `{% if debug %}...{% endif %}` |
| `{% for %}` | Loops | `{% for item in items %}...{% endfor %}` |
| `{# #}` | Comments | `{# This is a comment #}` |
| `{{ var \| filter }}` | Filters | `{{ name \| upper }}` |

## Configuration Options

### `jinja.run` Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `inputFiles` | Yes | - | List of template files |
| `root` | Yes | - | Project root directory |
| `config.variables` | No | `{}` | Variables passed to all templates |
| `config.templates` | No | auto | Override template output paths |

### Custom Output Paths

```nix
native.tools.jinja.run {
  inputFiles = [ "src.j2" ];
  root = ./.;
  config = {
    templates = [
      {
        template = "src.j2";
        output = "generated/custom_name.h";
        variables = { specific = "value"; };
      }
    ];
  };
};
```

## Incremental Builds

The jinja tool only captures specified input files, not the entire project directory. Changes to other files (like `main.cc`) won't invalidate the template generation step.

## Next Steps

- See `app-with-library/` for jinja combined with other tools
- See `simple-tool/` for creating custom inline generators
- See `protobuf/` for another code generation example
