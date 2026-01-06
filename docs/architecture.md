# Architecture Notes

## Overview

nixnative uses [nix-ninja](https://github.com/aspect-build/nix-ninja) as its build driver. At Nix evaluation time, nixnative generates a ninja build file describing the compilation graph. At build time, nix-ninja parses this file and creates one derivation per source file using RFC 92 dynamic derivations.

## Build Pipeline

```
EVALUATION TIME (nixnative):
  native.project { modules = [ ... ] }
    │
    ├── Resolve toolchain (compiler, linker, flags)
    ├── Process tool plugins (code generators)
    ├── Normalize source paths
    │
    └── Generate build.ninja content
        │
        └── Create wrapper derivation that invokes nix-ninja
            │
            └── builtins.outputOf → placeholder for final output

BUILD TIME (nix-ninja):
  nix-ninja -f build.ninja <target>
    │
    ├── Parse ninja build file
    ├── Scan headers per-source (deps = gcc)
    ├── Create one derivation per source file
    ├── Build each source → .o files
    │
    └── Link final executable/library
```

## Key Components

### 1. Module-First Project Interface (`modules/project.nix`)

The primary entrypoint for new code:
- Typed module options for targets, tests, and dev shells
- Applies defaults and resolves target references
- Emits `packages`, `checks`, and `devShells`

### 2. High-Level API (`builders/api.nix`)

The user-facing API that handles:
- Compiler/linker resolution from string names to objects
- Abstract flag translation (e.g., `lto = "thin"` → `-flto=thin`)
- Parameter validation and helpful error messages

### 3. Helpers (`builders/helpers.nix`)

Low-level builder functions that:
- Normalize source paths and globs
- Aggregate library dependencies and their public interfaces
- Process tool plugins for generated sources/headers
- Generate ninja file content
- Create wrapper derivations

### 4. Ninja Generation (`ninja/generate.nix`)

Pure functions that generate ninja build file content:

```ninja
rule cpp
  command = clang++ $FLAGS -MD -MF $out.d -c $in -o $out
  deps = gcc
  depfile = $out.d

build main.o: cpp /nix/store/xxx-src/main.cc
  FLAGS = -std=c++20 -I/nix/store/yyy-includes -DFOO=1

build app: link_exe main.o util.o
  LDFLAGS = -lm
```

Key features:
- All paths are absolute `/nix/store/...` paths
- `deps = gcc` enables nix-ninja's header scanning
- Per-language compile rules for C vs C++

### 5. Ninja Wrapper (`ninja/wrapper.nix`)

Creates the wrapper derivation that invokes nix-ninja:

```nix
mkNinjaDerivation = { name, ninjaContent, ... }:
  pkgs.stdenv.mkDerivation {
    __contentAddressed = true;
    outputHashMode = "text";
    requiredSystemFeatures = [ "recursive-nix" ];

    buildPhase = ''
      nix-ninja -f build.ninja ${target}
      # Output is the generated .drv path
    '';
  };
```

### 6. Toolchain Abstraction (`core/toolchain.nix`)

Composes compilers, linkers, and binutils:
- Language-aware (C, C++, potentially Rust)
- Flag translation for abstract flags
- Platform-specific defaults

### 7. Tool Plugins (`scanner/scanner.nix`, `tools/`)

Code generators that produce headers and sources at eval time:
- Built-in: Jinja2, protobuf, gRPC
- Custom tools via `mkTool`
- Outputs are merged into the ninja build graph

## Incremental Build Strategy

### Per-File Derivations

nix-ninja creates one derivation per source file. This means:
- Changing `src/foo.cc` only rebuilds `foo.o` + link step
- Unchanged objects are fetched from the Nix store cache
- Header changes trigger rebuilds via `deps = gcc` scanning

### Source Capture

Each source file is captured individually:

```nix
store = builtins.path { path = "${rootHost}/${relNorm}"; };
```

This makes each source content-addressed, so changing one file doesn't invalidate others.

### Tool Plugin Capture

Tool plugins use `captureFiles` to avoid capturing the entire source tree:

```nix
capturedRoot = utils.captureFiles {
  inherit root;
  files = normalizedFiles;  # Only the input files
};
```

## Library Dependencies

Libraries expose a `public` attribute with:
- `includeDirs` - Header paths for consumers
- `defines` - Preprocessor definitions to propagate
- `compileFlags` - Compiler flags to propagate
- `linkFlags` - Linker flags (e.g., `-lmylib`)

When a target depends on a library, these are automatically merged into the build.

## Outputs

Each build target provides:
- The built artifact (executable, library, etc.)
- `compileCommands` - `compile_commands.json` for IDE integration
- `passthru.toolchain` - The toolchain used for building
- `passthru.target` - The `builtins.outputOf` reference to the actual output

## Extensibility

### Custom Toolchains

```nix
native.mkToolchain {
  languages = {
    c = native.compilers.gcc.c;
    cpp = native.compilers.gcc.cpp;
  };
  linker = native.linkers.mold;
  bintools = native.compilers.gcc.bintools;
}
```

### Custom Tools

```nix
native.mkTool {
  name = "my-generator";
  transform = { inputFiles, root, config }: pkgs.runCommand "gen" {} ''...';
  outputs = { drv, ... }: { headers = [...]; sources = [...]; };
}
```

### Platform Support

Currently Linux-only (x86_64 and aarch64). The linker and platform abstractions are designed to support additional platforms if needed.

## Known Limitations

- Requires Nix with experimental features: `dynamic-derivations`, `ca-derivations`, `recursive-nix`
- Windows/MSVC is not supported
- IDE integration requires `compile_commands.json` which is generated at build time, not eval time
