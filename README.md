# nixnative

Incremental C/C++ builds using Nix dynamic derivations.

## Overview

nixnative implements minimal, incremental C/C++ build graphs natively in Nix using [RFC 92 dynamic derivations](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md). Each source file becomes its own derivation, enabling true per-file incrementality while eliminating IFD (Import From Derivation) during evaluation.

**This project requires Nix with dynamic derivations support.** All builds use dynamic derivations—there is no fallback to traditional IFD-based builds.

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

## Why Dynamic Derivations?

Traditional approaches to incremental C++ builds in Nix face a fundamental tradeoff:

1. **IFD-based scanning**: Evaluation blocks while scanning dependencies, breaking `nix flake check` and slowing CI.
2. **Checked-in manifests**: Requires manual synchronization, adding maintenance burden.

Dynamic derivations solve this by deferring derivation creation to build time while keeping evaluation instant.

## How It Works

nixnative uses a two-phase architecture with separate compilation and linking:

```
EVALUATION TIME (instant):
  sources → compile-wrapper.drv (per source file)
                    ↓
            builtins.outputOf → placeholder for .o
                    ↓
            link-wrapper.drv (references all placeholders)
                    ↓
            builtins.outputOf → placeholder for executable

BUILD TIME:
  Phase 1 - Compile Wrappers:
    1. Each compile-wrapper.drv scans headers (clang -MMD)
    2. Generates a compile-<source>.drv via `nix derivation add`
    3. Nix builds the generated .drv → produces .o file

  Phase 2 - Link Wrapper:
    1. link-wrapper.drv receives actual .o paths (placeholders resolved)
    2. Generates link.drv via `nix derivation add`
    3. Nix builds link.drv → produces final executable/library
```

**Key insight**: Compile wrappers output `.drv` files (text mode), not object files directly. This allows Nix to resolve the `builtins.outputOf` placeholders and chain derivations together.

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

  outputs = { nixpkgs, nixnative, ... }: {
    packages.x86_64-linux.default = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      native = nixnative.lib.native { inherit pkgs; };
    in native.executable {
      name = "hello";
      root = ./.;
      sources = [ "src/main.cc" ];
    };
  };
}
```

Build and run:

```sh
nix build
./result/bin/hello
```

## Features

- **Modular toolchains**: Compilers and linkers are independent, composable pieces. Use clang with mold, gcc with lld, or define your own.
- **Abstract flags**: Write `lto = "thin";` once—nixnative translates it to the right CLI flags for each compiler.
- **Tool plugins**: Code generators (templates, etc.) integrate cleanly—generated sources and headers flow through automatically.
- **Structured libraries**: Static, shared, and header-only libraries propagate their public interface to dependents.
- **IDE integration**: Every target exports `compile_commands.json` for clangd/LSP.

## Examples

See the `examples/` directory for working examples:

- `examples/executable` – Minimal executable
- `examples/library` – Static library with public headers
- `examples/header-only` – Header-only library
- `examples/library-chain` – Transitive library dependencies
- `examples/app-with-library` – Executable depending on a static library
- `examples/multi-toolchain` – Different compiler/linker combinations (clang/gcc + lld/mold)
- `examples/testing` – Unit tests with `native.test`
- `examples/test-libraries` – GoogleTest, Catch2, and doctest integration
- `examples/coverage` – Code coverage with gcov/llvm-cov
- `examples/plugins` – Shared library plugins with dlopen
- `examples/multi-binary` – Multiple executables from one project
- `examples/pkg-config` – Using external libraries via pkg-config
- `examples/c-and-cpp` – Mixed C and C++ sources
- `examples/devshell` – Development shell with clangd support
- `examples/simple-tool` – Custom code generation tool plugin

Build and run an example:

```sh
nix build .#executableExample
./result/bin/executable-example
```

Run all checks:

```sh
nix flake check
```

## Platform Support

- **Linux** (x86_64, aarch64): Primary supported platform
- **macOS** (aarch64-darwin): Best-effort support

## Repository Layout

```
.
├── flake.nix           # Top-level flake exposing native.lib and examples
├── nix/native/
│   ├── default.nix     # Main entry point, assembles all modules
│   ├── core/           # Compiler, linker, toolchain, and flag abstractions
│   ├── compilers/      # Compiler implementations (clang, gcc)
│   ├── linkers/        # Linker implementations (lld, mold, gold, ld)
│   ├── dynamic/        # Dynamic derivations (compile/link wrappers)
│   ├── builders/       # High-level API (executable, staticLib, etc.)
│   ├── scanner/        # Tool plugin processing
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
- [nix-ninja project](https://github.com/aspect-build/nix-ninja)

## License

MIT
