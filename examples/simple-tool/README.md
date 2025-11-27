# Simple Tool Example

This example demonstrates the simplest ways to create custom code generators in nixnative.

## What This Demonstrates

- Creating inline generators with just an attrset
- Using derivations for more complex generation
- The generator schema that nixnative expects
- When to use each approach

## Project Structure

```
simple-tool/
├── flake.nix      # Generator definitions
├── version.txt    # Input file for generation
└── main.cc        # Uses the generated header
```

## Build and Run

```sh
nix build
./result/bin/simple-tool-inline
```

Expected output:
```
Simple Tool Example
===================

Version info (generated at build time):
  Full version: 1.2.3
  Major: 1
  Minor: 2
  Patch: 3

Code generation working!
```

## How It Works

### The Generator Schema

A generator is an attrset with this shape:

```nix
{
  name = "my-generator";     # Optional: for error messages

  # Generated headers
  headers = [
    {
      rel = "foo.h";         # Path used in #include
      path = "/nix/store/..."; # Actual file location
    }
  ];

  # Generated source files (optional)
  sources = [
    {
      rel = "foo.cc";
      path = "/nix/store/...";
    }
  ];

  # Include directories
  includeDirs = [ { path = "/nix/store/..."; } ];

  # Optional: preprocessor defines
  defines = [ "GENERATED=1" ];
}
```

### Method 1: Inline Generator (Simplest)

For simple cases, use `pkgs.writeText` directly:

```nix
myHeader = pkgs.writeText "config.h" ''
  #pragma once
  #define VERSION "1.0.0"
'';

generator = {
  headers = [ { rel = "config.h"; path = myHeader; } ];
  includeDirs = [ { path = builtins.dirOf myHeader; } ];
};

app = native.executable {
  sources = [ "main.cc" ];
  tools = [ generator ];
};
```

**Use when:**
- Generating simple text from Nix expressions
- No external tools needed
- Single file output

### Method 2: Derivation Generator

For complex generation requiring commands:

```nix
generatorDrv = pkgs.runCommand "my-gen" {} ''
  mkdir -p $out/include
  # Run any commands: sed, awk, python, etc.
  echo '#define FOO 42' > $out/include/config.h
'';

generator = {
  headers = [
    { rel = "config.h"; path = "${generatorDrv}/include/config.h"; }
  ];
  includeDirs = [ { path = "${generatorDrv}/include"; } ];
};
```

**Use when:**
- Running external tools (protoc, flatc, etc.)
- Complex text processing
- Multiple output files

### Method 3: Built-in Tools

For common patterns, use built-in tools:

```nix
# Jinja templates
native.tools.jinja.run { ... }

# Protobuf
native.tools.protobuf.run { ... }

# gRPC
native.tools.grpc.run { ... }
```

**Use when:**
- The built-in tool matches your use case
- You want incremental build support

## Generator vs Tool Plugin

| Aspect | Inline Generator | Tool Plugin (mkTool) |
|--------|------------------|----------------------|
| Complexity | Simple attrset | Factory function |
| Incremental | Rebuilds on any input change | Captures only specified files |
| Reusability | Copy-paste | Reusable across projects |
| Use case | One-off generation | Repeated pattern |

## Incremental Build Considerations

The inline approach captures the entire flake for IFD, meaning any
change to flake.nix triggers regeneration. For better incrementality,
use `native.utils.captureFiles`:

```nix
# Only capture the files the generator needs
templateFiles = native.utils.captureFiles {
  root = ./.;
  files = [ "version.txt" ];
};

generator = pkgs.runCommand "gen" { src = templateFiles; } ''
  # Only rebuilds when version.txt changes
'';
```

## Common Patterns

### Version Header from Git

```nix
gitVersion = pkgs.runCommand "git-version" {
  nativeBuildInputs = [ pkgs.git ];
  src = ./.;
} ''
  cd $src
  echo "#define GIT_HASH \"$(git rev-parse --short HEAD)\"" > $out
'';
```

### Build Timestamp

```nix
timestamp = pkgs.writeText "timestamp.h" ''
  #define BUILD_TIME "${builtins.toString builtins.currentTime}"
'';
```

### Environment-Based Config

```nix
config = pkgs.writeText "config.h" ''
  #define DEBUG_MODE ${if debug then "1" else "0"}
  #define LOG_LEVEL ${toString logLevel}
'';
```

## Next Steps

- See `app-with-library/` for Jinja template generation
- See `protobuf/` for Protocol Buffer generation
- See the API docs for `native.mkTool` to create reusable tools
