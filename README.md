# nixnative

Incremental C/C++ builds using Nix dynamic derivations and nix-ninja.

## Overview

nixnative provides a module-first API for building C/C++ projects with true per-file incrementality. It uses [nix-ninja](https://github.com/tom-lubenow/nix-ninja) as the build driver, which generates one derivation per source file at build time using [RFC 92 dynamic derivations](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md).

**This project requires Nix with dynamic derivations support.** All builds use nix-ninja for incremental compilation—there is no fallback to traditional builds.

## Requirements

Nix with dynamic derivations support is **mandatory**. The recommended version is pinned in `flake.nix`:

```nix
# Nix with full dynamic derivations support (commit d904921)
inputs.nix.url = "github:NixOS/nix/d904921eecbc17662fef67e8162bd3c7d1a54ce0";
```

Enable the required experimental features in your Nix configuration (`~/.config/nix/nix.conf`):

```
experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
```

## Language Scope

nixnative currently compiles **C and C++** sources.

Other languages can still participate through normal library composition (for example prebuilt/static/shared libraries produced by external toolchains), but the native compilation pipeline in nixnative is intentionally C/C++ only for now.

## Why Dynamic Derivations?

Traditional approaches to incremental C++ builds in Nix face a fundamental tradeoff:

1. **IFD-based scanning**: Evaluation blocks while scanning dependencies, breaking `nix flake check` and slowing CI.
2. **Checked-in manifests**: Requires manual synchronization, adding maintenance burden.

Dynamic derivations solve this by deferring derivation creation to build time while keeping evaluation instant.

## How It Works

nixnative generates a ninja build file at Nix evaluation time, then uses nix-ninja to execute it with per-file derivations:

```
EVALUATION TIME (instant):
  proj = native.project { root = ./.; ... }
  app = proj.executable { name = "app"; sources = [...]; }
    → Generate build.ninja content (pure Nix)
    → Create wrapper derivation that invokes nix-ninja
    → builtins.outputOf → placeholder for final output

BUILD TIME (nix-ninja):
  1. nix-ninja parses build.ninja
  2. Scans headers per-source (deps = gcc)
  3. Creates one derivation per source file
  4. Compiles each source → .o files
  5. Links final executable/library
```

**Key insight**: nix-ninja handles all the complexity of creating per-file derivations and tracking header dependencies. nixnative just generates the ninja build file.

This architecture gives you:

- **Instant evaluation**: No IFD blocking during `nix eval` or `nix flake check`
- **True incrementality**: Change one file, rebuild one derivation
- **Parallel compilation**: Each source compiles in its own derivation
- **Full toolchain control**: Compilers, linkers, and flags are explicit inputs
- **Content-addressed caching**: Identical compilations are deduplicated across projects

## Quick Start

```nix
# flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixnative.url = "github:your/nixnative";

  outputs = { nixpkgs, nixnative, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      native = nixnative.lib.native { inherit pkgs; };

      # Create a project with shared defaults
      proj = native.project {
        root = ./.;
        compileFlags = [ "-Wall" "-Wextra" ];
      };

      # Build targets - real values, not string references
      hello = proj.executable {
        name = "hello";
        sources = [ "src/main.cc" ];
      };
    in {
      packages.x86_64-linux.default = hello;
    };
}
```

Build and run:

```sh
# Build and get the output path in one command
nix build --print-out-paths
# Output: /nix/store/xxx-hello

# Run directly from the store path
$(nix build --print-out-paths)/hello
```

> **Note**: Dynamic derivations don't create the traditional `./result` symlink.
> Use `--print-out-paths` to get the store path, or `nix path-info .#target` after building.

## Features

- **Modular toolchains**: Compilers and linkers are independent, composable pieces. Use clang with mold, gcc with lld, or define your own.
- **Explicit flags**: Use raw `compileFlags`, `languageFlags`, and `linkFlags` for precise and predictable control.
- **Tool plugins**: Code generators (templates, etc.) integrate cleanly—generated sources and headers flow through automatically.
- **Structured libraries**: Static, shared, and header-only libraries propagate their public interface to dependents.
- **IDE integration**: Every target exports `compile_commands.json` for clangd/LSP.

## Recommended Pattern: System Link Dependencies

When multiple targets share system linker flags (for example `-lpthread`/`-ldl`/`-lm`), define local "system library" objects and compose them through `libraries` instead of repeating `linkFlags` everywhere:

```nix
let
  mkSystemLibrary = { name, compileFlags ? [ ], linkFlags ? [ ] }: {
    inherit name;
    public = {
      includeDirs = [ ];
      defines = [ ];
      inherit compileFlags linkFlags;
    };
  };

  sys = {
    threads = mkSystemLibrary { name = "threads"; linkFlags = [ "-lpthread" ]; };
    dl = mkSystemLibrary { name = "dl"; linkFlags = [ "-ldl" ]; };
    m = mkSystemLibrary { name = "m"; linkFlags = [ "-lm" ]; };
  };

  commonSystemLibraries = [ sys.threads sys.dl sys.m ];
in
proj.executable {
  name = "app";
  sources = [ "src/main.c" ];
  libraries = [ myLib ] ++ commonSystemLibraries;
}
```

This keeps link policy explicit, reusable, and local to your project without requiring a dedicated framework abstraction.

## Examples

See the `examples/` directory for working examples:

- `examples/executable` – Minimal executable
- `examples/library` – Static library with public headers
- `examples/header-only` – Header-only library
- `examples/library-chain` – Transitive library dependencies
- `examples/app-with-library` – Executable depending on a static library
- `examples/multi-toolchain` – Different compiler/linker combinations (clang/gcc + lld/mold)
- `examples/testing` – Unit tests with module-defined tests
- `examples/test-libraries` – GoogleTest, Catch2, and doctest integration
- `examples/coverage` – Code coverage with gcov/llvm-cov
- `examples/plugins` – Shared library plugins with dlopen
- `examples/multi-binary` – Multiple executables from one project
- `examples/pkg-config` – Using external libraries via pkg-config
- `examples/c-and-cpp` – Mixed C and C++ sources
- `examples/devshell` – Development shell with clangd support
- `examples/simple-tool` – Custom code generation tool plugin
- `examples/python-extension` – Python C++ extension with pybind11

Build and run an example:

```sh
nix build .#executableExample --print-out-paths
# Output: /nix/store/xxx-executable-example

# Or in one line:
$(nix build .#executableExample --print-out-paths)/executable-example
```

Run all checks:

```sh
nix flake check
```

## Platform Support

- **Linux** (x86_64, aarch64): Fully supported

## Repository Layout

```
.
├── flake.nix           # Top-level flake exposing native.lib and examples
├── nix/native/
│   ├── default.nix     # Main entry point, assembles all modules
│   ├── core/           # Compiler, linker, toolchain, and tool plugin abstractions
│   ├── compilers/      # Compiler implementations (clang, gcc)
│   ├── linkers/        # Linker implementations (lld, mold, ld)
│   ├── ninja/          # nix-ninja integration (build file generation)
│   ├── modules/        # Module-first project interface
│   ├── builders/       # High-level API (executable, staticLib, etc.)
│   ├── tools/          # Built-in tool plugins (protobuf, jinja, binary-blob)
│   ├── testlibs/       # Test framework integrations (gtest, catch2, doctest)
│   ├── lsps/           # LSP/IDE support (clangd)
│   └── utils/          # Shared utilities
└── examples/           # Working example projects
```

## Current Status

This project builds on experimental Nix features. The dynamic derivations implementation is based on [John Ericson's work on RFC 92](https://github.com/NixOS/nix/commits/author/John-Ericson).

Key references:
- [RFC 92: Plan Dynamism](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md)
- [Farid Zakaria's nix-ninja blog posts](https://fzakaria.com/)
- [nix-ninja project fork used by this repo](https://github.com/tom-lubenow/nix-ninja)

## License

MIT
