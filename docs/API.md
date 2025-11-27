# NixClang API Reference

This document describes the public API exposed by `nixclang.lib.cpp`.

## Core Builders

### `mkExecutable`
Builds an executable binary.

```nix
mkExecutable {
  name = "my-app";           # Required: output name
  root = ./.;                # Required: project root directory
  sources = [ "src/main.cc" ]; # Required: list of source files (relative to root)

  # Optional arguments
  includeDirs = [ "include" ];  # Include directories (relative to root or absolute)
  defines = [ "DEBUG" ];        # Preprocessor definitions
  cxxFlags = [ "-O2" ];         # Additional compiler flags
  ldflags = [ "-lm" ];          # Additional linker flags
  libraries = [ myLib ];        # Library dependencies (from mkStaticLib, mkSharedLib, etc.)
  generators = [ myGenerator ]; # Code generators (see Generator Schema below)
  toolchain = clangToolchain;   # Custom toolchain (defaults to clang18)

  # Optimization options (new)
  lto = false;                  # Link-time optimization: false, true, "thin", or "full"
  sanitizers = [ ];             # Sanitizers: [ "address" "undefined" "thread" "memory" "leak" ]
  coverage = false;             # Enable code coverage instrumentation

  # Dependency manifest (pick one approach)
  depsManifest = ./deps.nix;    # Strict mode: use checked-in manifest
  scanner = myScanner;          # Or provide a custom scanner derivation
  # If neither is provided, auto-scanner runs via IFD
}
```

**Parameter Details:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Output binary name |
| `root` | Yes | - | Project root directory |
| `sources` | Yes | - | List of source files (strings relative to root) |
| `includeDirs` | No | `[]` | Include directories |
| `defines` | No | `[]` | Preprocessor definitions (strings or `{ name, value }` attrsets) |
| `cxxFlags` | No | `[]` | Additional C++ compiler flags |
| `ldflags` | No | `[]` | Additional linker flags |
| `libraries` | No | `[]` | Library dependencies |
| `generators` | No | `[]` | Code generators |
| `toolchain` | No | `clangToolchain` | Compiler toolchain |
| `lto` | No | `false` | LTO mode: `false`, `true`/`"thin"`, or `"full"` |
| `sanitizers` | No | `[]` | List of sanitizers to enable |
| `coverage` | No | `false` | Enable coverage instrumentation |
| `depsManifest` | No | `null` | Path to dependency manifest file |
| `scanner` | No | `null` | Custom scanner derivation |

### `mkStaticLib`
Builds a static library (`.a`) and installs headers.

```nix
mkStaticLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ]; # Installed to $out/include
  # ... standard build args
}
```

### `mkSharedLib`
Builds a shared library (`.so` / `.dylib`) and installs headers.

```nix
mkSharedLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ];
  # ... standard build args
}
```

### `mkHeaderOnly`
Defines a header-only library interface.

```nix
mkHeaderOnly {
  name = "my-headers";
  publicIncludeDirs = [ "include" ];
  publicDefines = [ "MY_LIB_ENABLED" ];
}
```

### `mkPythonExtension`
Builds a CPython extension module.

```nix
mkPythonExtension {
  name = "my_ext";
  root = ./.;
  sources = [ "src/bindings.cc" ];
  # ... standard build args
}
```

## Testing & Documentation

### `mkTest`
Runs a test executable during the build.

```nix
mkTest {
  name = "my-test";
  executable = myApp;
  args = [ "--test" ];
  stdin = "input data";
  expectedOutput = "Success";
}
```

### `mkDoc`
Generates documentation using Doxygen.

```nix
mkDoc {
  name = "my-docs";
  root = ./.;
  sources = [ "src" "include" ];
}
```

## Development

### `mkDevShell`
Creates a development shell with tools and environment variables.

```nix
mkDevShell {
  target = myApp;
  includeTools = true; # Adds clang-tools, lldb/gdb
}
```

## Advanced

### `mkDependencyScanner`
Creates a derivation that scans source files for dependencies using `clang -MMD`. Used internally by builders when no manifest is provided.

### `mkBuildContext`
(Internal) Prepares the build context (sources, flags, headers) for all builder types.

---

## Generator Schema

Generators allow you to integrate code generation (e.g., Jinja templates, protobuf, FlatBuffers) into the build pipeline. A generator is an attrset with the following shape:

```nix
{
  # Optional: name for error messages
  name = "my-generator";

  # Optional: dependency manifest for generated sources
  manifest = ./generated.clang-deps.nix;
  # Or an inline manifest:
  # manifest = { schema = 1; units = { "gen/file.cc" = { dependencies = [...]; }; }; };

  # Optional: generated headers (will override headers from root)
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

  # Optional: derivations needed at evaluation time (for IFD)
  evalInputs = [ generatorDrv ];
}
```

### Generator Header/Source Entry Schema

Each entry in `headers` or `sources` must have:

| Field | Required | Description |
|-------|----------|-------------|
| `rel` (or `relative`) | Yes | Relative path in the build tree |
| `path` or `store` | Yes | Actual file location (path or store path) |

### Minimal Generator Example

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

## Dependency Manifest Schema

Manifests describe header dependencies for each translation unit:

```nix
{
  schema = 1;  # Schema version (currently always 1)
  units = {
    "src/main.cc" = {
      dependencies = [
        "src/main.cc"        # The source itself
        "include/foo.hpp"    # Headers it includes
        "include/bar.h"
      ];
    };
    "src/lib.cc" = {
      dependencies = [ "src/lib.cc" "include/lib.h" ];
    };
  };
}
```

Manifests can be:
- `.nix` files (imported directly)
- `.json` files (parsed with `builtins.fromJSON`)
- Inline attrsets
- Derivations that produce JSON output

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

## pkg-config Integration

### `pkgConfig.mkPkgConfigLibrary`

Creates a library from pkg-config modules:

```nix
cpp.pkgConfig.mkPkgConfigLibrary {
  name = "zlib";
  packages = [ pkgs.zlib ];   # Nix packages providing pkg-config files
  modules = [ "zlib" ];       # pkg-config module names (defaults to [ name ])
}
```

### `pkgConfig.mkFrameworkLibrary`

Creates a library for macOS frameworks:

```nix
cpp.pkgConfig.mkFrameworkLibrary {
  name = "CoreFoundation";
  framework = "CoreFoundation";  # Framework name (defaults to name)
  sdk = pkgs.apple-sdk.sdkroot;  # SDK root (auto-detected if omitted)
}
```
