# Nixnative API Reference

This document describes the public API exposed by `nixnative.lib.native`.

## API Overview

nixnative provides two API levels:

| API Level | Functions | When to Use |
|-----------|-----------|-------------|
| **High-level** | `executable`, `staticLib`, `sharedLib`, `headerOnly`, `devShell`, `shell`, `test` | Most users - automatic toolchain selection |
| **Low-level** | `mkExecutable`, `mkStaticLib`, `mkSharedLib`, `mkHeaderOnly`, `mkDevShell`, `mkTest` | Advanced users - explicit toolchain control |

**Key differences:**

- High-level API accepts `compiler`/`linker` as strings (e.g., `"gcc"`, `"mold"`)
- Low-level API requires explicit `toolchain` object
- Both use `tools` parameter for code generation

---

## High-Level API (Recommended)

### `executable`

Builds an executable binary with automatic toolchain selection.

```nix
native.executable {
  name = "my-app";              # Required: output name
  root = ./.;                   # Required: project root directory
  sources = [ "src/main.cc" ];  # Required: list of source files (relative to root)

  # Optional: toolchain selection (defaults to clang + lld)
  compiler = "clang";           # "clang", "gcc", or compiler object
  linker = "lld";               # "lld", "mold", "gold", "ld", or linker object

  # Optional build configuration
  includeDirs = [ "include" ];  # Include directories
  defines = [ "DEBUG" ];        # Preprocessor definitions
  compileFlags = [ "-O2" ];     # Additional compiler flags
  langFlags = { cpp = [ "-std=c++20" ]; };  # Per-language flags
  ldflags = [ "-lm" ];          # Additional linker flags
  libraries = [ myLib ];        # Library dependencies
  tools = [ myTool ];           # Tool plugins (protobuf, jinja, etc.)

  # Ergonomic optimization flags (alternative to `flags` list)
  lto = "thin";                 # false, true, "thin", or "full"
  sanitizers = [ "address" ];   # [ "address" "undefined" "thread" "memory" "leak" ]
  coverage = false;             # Enable code coverage
  optimize = "2";               # "0", "1", "2", "3", "s", "z", "fast"
  warnings = "all";             # "none", "default", "all", "extra", "pedantic"
}
```

### `staticLib`

Builds a static library with public interface.

```nix
native.staticLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ];  # Headers exposed to consumers
  publicDefines = [ "MY_LIB=1" ];     # Defines propagated to consumers
  # ... same options as executable
}
```

### `sharedLib`

Builds a shared library (`.so`/`.dylib`).

```nix
native.sharedLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ];
  # ... same options as staticLib
}
```

### `headerOnly`

Defines a header-only library (no compilation).

```nix
native.headerOnly {
  name = "my-headers";
  root = ./.;
  publicIncludeDirs = [ "include" ];
  publicDefines = [ "HEADER_ONLY=1" ];
}
```

### `devShell`

Creates a development shell from a built target with toolchain and IDE support.

```nix
native.devShell {
  target = myApp;               # Built target to get toolchain from
  extraPackages = [ pkgs.gdb ]; # Additional packages
  includeTools = true;          # Include clang-tools, gdb (default: true)
}
```

### `shell`

Creates a standalone development shell without a target (just the toolchain).

```nix
native.shell {
  compiler = "clang";           # "clang", "gcc", or compiler object
  linker = "mold";              # "lld", "mold", "gold", "ld", or linker object
  extraPackages = [ pkgs.cmake pkgs.ninja ];  # Additional packages
  includeTools = true;          # Include clang-tools, gdb (default: true)
}
```

This is useful when you want a development environment before defining any build targets.

### `test`

Runs a test executable during the build.

```nix
native.test {
  name = "my-test";
  executable = myApp;
  args = [ "--verbose" ];
  expectedOutput = "PASSED";    # Optional: verify output contains this
}
```

---

## Low-Level API

For advanced use cases requiring explicit toolchain control.

### `mkExecutable`

Builds an executable binary with explicit toolchain.

```nix
native.mkExecutable {
  name = "my-app";
  root = ./.;
  sources = [ "src/main.cc" ];

  # Required: explicit toolchain
  toolchain = native.mkToolchain {
    compiler = native.compilers.clang;
    linker = native.linkers.mold;
  };

  # Optional arguments
  includeDirs = [ "include" ];
  defines = [ "DEBUG" ];
  compileFlags = [ "-O2" ];
  langFlags = { cpp = [ "-std=c++20" ]; };
  ldflags = [ "-lm" ];
  libraries = [ myLib ];
  tools = [ myTool ];

  # Abstract flags (alternative to ergonomic params)
  flags = [
    (native.flags.lto "thin")
    (native.flags.sanitizer "address")
  ];
}
```

**Parameter Details:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Output binary name |
| `root` | Yes | - | Project root directory |
| `sources` | Yes | - | List of source files (strings relative to root) |
| `toolchain` | Yes | - | Toolchain from `mkToolchain` |
| `includeDirs` | No | `[]` | Include directories |
| `defines` | No | `[]` | Preprocessor definitions (strings or `{ name, value }` attrsets) |
| `compileFlags` | No | `[]` | Additional compiler flags (all languages) |
| `langFlags` | No | `{}` | Per-language compiler flags (`{ c = [...]; cpp = [...]; }`) |
| `ldflags` | No | `[]` | Additional linker flags |
| `libraries` | No | `[]` | Library dependencies |
| `tools` | No | `[]` | Code generators (see Tool Schema) |
| `flags` | No | `[]` | Abstract flags (lto, sanitizers, etc.) |

### `mkStaticLib`

Builds a static library (`.a`) with explicit toolchain.

```nix
native.mkStaticLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  toolchain = myToolchain;
  publicIncludeDirs = [ "include" ];
  # ... same options as mkExecutable
}
```

### `mkSharedLib`

Builds a shared library (`.so`/`.dylib`) with explicit toolchain.

```nix
native.mkSharedLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  toolchain = myToolchain;
  publicIncludeDirs = [ "include" ];
}
```

### `mkHeaderOnly`

Defines a header-only library interface.

```nix
native.mkHeaderOnly {
  name = "my-headers";
  root = ./.;
  publicIncludeDirs = [ "include" ];
  publicDefines = [ "MY_LIB_ENABLED" ];
}
```

### `mkDevShell`

Creates a development shell with explicit toolchain.

```nix
native.mkDevShell {
  target = myApp;
  toolchain = myToolchain;  # Optional: override target's toolchain
  includeTools = true;
}
```

### `mkTest`

Runs a test executable during the build.

```nix
native.mkTest {
  name = "my-test";
  executable = myApp;
  args = [ "--test" ];
  stdin = "input data";
  expectedOutput = "Success";
}
```

---

## Abstract Flags

nixnative provides an abstract flag system for compiler-agnostic optimization settings. These flags are translated to the correct CLI arguments for each compiler.

### Ergonomic Syntax (Recommended)

Use these parameters directly on builders:

```nix
native.executable {
  name = "app";
  sources = [ "main.cc" ];
  lto = "thin";               # Link-time optimization
  sanitizers = [ "address" ]; # Runtime sanitizers
  coverage = true;            # Code coverage
}
```

### Abstract Flag Objects

For advanced use, pass the `flags` parameter with abstract flag objects:

```nix
native.executable {
  name = "app";
  sources = [ "main.cc" ];
  flags = [
    (native.flags.lto "thin")
    (native.flags.sanitizer "address")
    native.flags.coverage
    (native.flags.optimize "2")
    (native.flags.debug "full")
    (native.flags.standard "c++20")
    (native.flags.warnings "extra")
  ];
}
```

### Available Flag Constructors

| Constructor | Arguments | Description |
|-------------|-----------|-------------|
| `flags.lto` | `"thin"`, `"full"`, or `true` | Link-time optimization |
| `flags.sanitizer` | `"address"`, `"thread"`, `"undefined"`, `"memory"`, `"leak"` | Runtime sanitizer |
| `flags.coverage` | (none) | Code coverage instrumentation |
| `flags.optimize` | `"0"`, `"1"`, `"2"`, `"3"`, `"s"`, `"z"`, `"fast"` | Optimization level |
| `flags.debug` | `"none"`, `"line-tables"`, `"full"` | Debug info level |
| `flags.standard` | `"c++17"`, `"c++20"`, `"c++23"`, `"c11"`, `"c17"` | Language standard |
| `flags.warnings` | `"none"`, `"default"`, `"all"`, `"extra"`, `"pedantic"` | Warning level |
| `flags.pic` | (none) | Position-independent code |

---

## Tool Schema

Tools allow you to integrate code generation (e.g., Jinja templates, protobuf, FlatBuffers) into the build pipeline. Use the `tools` parameter with any builder.

A tool is an attrset with the following shape:

```nix
{
  # Optional: name for error messages
  name = "my-generator";

  # Optional: generated headers
  headers = [
    {
      rel = "gen/config.h";        # Relative path in the build tree
      path = generatorDrv + "/include/config.h";  # Actual file location
      # Or use 'store' instead of 'path'
    }
  ];

  # Optional: generated source files
  sources = [
    {
      rel = "gen/generated.cc";    # Relative path (will be compiled)
      path = generatorDrv + "/src/generated.cc";
    }
  ];

  # Optional: additional include directories
  includeDirs = [ generatorDrv + "/include" ];

  # Optional: additional preprocessor definitions
  defines = [ "GENERATED_CODE=1" ];

  # Optional: additional compiler flags
  cxxFlags = [ ];

  # Optional: public flags propagated to dependents
  public = {
    includeDirs = [ ];   # Must be a list
    defines = [ ];       # Must be a list
    cxxFlags = [ ];      # Must be a list
    linkFlags = [ ];     # Must be a list
  };
}
```

### Tool Header/Source Entry Schema

Each entry in `headers` or `sources` must have:

| Field | Required | Description |
|-------|----------|-------------|
| `rel` (or `relative`) | Yes | Relative path in the build tree |
| `path` or `store` | Yes | Actual file location (path or store path) |

### Minimal Tool Example

```nix
let
  configHeader = pkgs.writeText "config.h" ''
    #pragma once
    #define VERSION "1.0.0"
  '';
in {
  name = "config-generator";
  headers = [
    { rel = "include/config.h"; path = configHeader; }
  ];
  includeDirs = [ "include" ];
}
```

---

## Public Attribute Schema

Libraries expose a `public` attribute that propagates flags to dependents:

```nix
{
  includeDirs = [ ];   # List of include directories (paths or { path = ...; } attrsets)
  defines = [ ];       # List of preprocessor definitions
  cxxFlags = [ ];      # List of compiler flags
  linkFlags = [ ];     # List of linker flags (e.g., library paths, -l flags)
}
```

All fields must be lists. Invalid types will produce clear error messages.

---

## Tool Plugins

Tool plugins enable code generation (protobuf, Jinja templates, etc.) that integrates into the build pipeline. Use these with the `tools` parameter (high-level API) or `generators` parameter (low-level API).

### Built-in Tools

```nix
# Protobuf code generation
native.tools.protobuf.run {
  inputFiles = [ "proto/messages.proto" ];
  root = ./.;
  config = {
    protoPath = "proto";
  };
}

# gRPC code generation
native.tools.grpc.run {
  inputFiles = [ "proto/service.proto" ];
  root = ./.;
}

# Jinja2 template generation
native.tools.jinja.run {
  inputFiles = [ "templates/config.h.j2" ];
  root = ./.;
  config = {
    variables = { version = "1.0.0"; };
  };
}

# Config header generation (convenience wrapper)
native.tools.configHeader {
  name = "app_config";
  variables = {
    VERSION = "1.0.0";
    DEBUG = false;
    MAX_CONNECTIONS = 100;
  };
}

# Enum generation (convenience wrapper)
native.tools.enumGenerator {
  name = "Status";
  namespace = "app";
  values = [ "OK" "ERROR" "PENDING" ];
}
```

### Creating Custom Tools

Use `mkTool` to create reusable tool plugins:

```nix
myTool = native.mkTool {
  name = "my-generator";

  # Transform function: produces a derivation from inputs
  transform = { inputFiles, root, config }:
    pkgs.runCommand "my-gen" { src = root; } ''
      # Generate code from inputFiles
    '';

  # Output schema: describes what the tool produces
  outputs = { drv, inputFiles, config }: {
    headers = [ { rel = "gen/output.h"; store = "${drv}/output.h"; } ];
    sources = [ { rel = "gen/output.cc"; store = "${drv}/output.cc"; } ];
    includeDirs = [ { path = drv; } ];
  };

  dependencies = [ "-lmylib" ];  # Runtime link dependencies
  defaultConfig = {};
};
```

### Incremental Builds for Tools

**IMPORTANT**: The `mkTool` infrastructure automatically captures only the specified `inputFiles` rather than the entire `root` directory. This is critical for incremental builds:

```nix
# Good: Only proto files are captured
native.tools.protobuf.run {
  inputFiles = [ "proto/a.proto" "proto/b.proto" ];
  root = ./.;
}
# Changing src/main.cc will NOT invalidate this tool's output
```

For custom tools that don't use `mkTool`, use the `captureFiles` helper:

```nix
# Capture only specific files (incremental-build safe)
templateFiles = native.utils.captureFiles {
  root = ./.;
  files = [ "templates/foo.j2" "templates/bar.j2" ];
};
# Or capture individual files
singleFile = builtins.path { path = ./templates/config.j2; };
```

**Anti-pattern** (breaks incremental builds):
```nix
# BAD: Captures entire directory - any file change invalidates this
rootStore = builtins.path { path = root; };
```

---

## Utilities

### `utils.captureFiles`

Captures specific files from a directory into a minimal store path. Essential for incremental builds.

```nix
native.utils.captureFiles {
  root = ./.;
  files = [ "templates/a.j2" "templates/b.j2" ];
  name = "my-templates";  # Optional: store path name
}
```

**Why this matters**: Using `builtins.path { path = root; }` captures the _entire_ directory, meaning any file change invalidates all derivations that depend on it. `captureFiles` captures only the specified files, so changes to other files don't cause unnecessary rebuilds.

### `utils.captureFile`

Convenience wrapper for capturing a single file:

```nix
native.utils.captureFile {
  root = ./.;
  file = "config/settings.json";
}
```

---

## pkg-config Integration

### `pkgConfig.mkPkgConfigLibrary`

Creates a library from pkg-config modules:

```nix
native.pkgConfig.mkPkgConfigLibrary {
  name = "zlib";
  packages = [ pkgs.zlib ];   # Nix packages providing pkg-config files
  modules = [ "zlib" ];       # pkg-config module names (defaults to [ name ])
}
```
