# Introduction

nixnative provides a composable API for building C/C++ projects with dynamic-derivation-driven incremental builds. It uses [nix-ninja](https://github.com/tom-lubenow/nix-ninja) as the build driver, which generates one derivation per source file at build time using [RFC 92 dynamic derivations](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md).

Launch scope: nixnative's native compilation pipeline is C/C++ only.

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

This architecture gives you:

- **Instant evaluation**: No IFD blocking during `nix eval` or `nix flake check`
- **Incrementality gate**: verify one-file-change behavior with `nix run .#incrementality-gate`
- **Parallel compilation**: Each source compiles in its own derivation
- **Full toolchain control**: Compilers, linkers, and flags are explicit inputs
- **Content-addressed caching**: Identical compilations are deduplicated across projects

## Features

- **Modular toolchains**: Compilers and linkers are independent, composable pieces. Use clang with mold, gcc with lld, or define your own.
- **Explicit flags**: Use `compileFlags`, `languageFlags`, and `linkFlags` directly for predictable compiler and linker behavior.
- **Tool plugins**: Code generators (templates, etc.) integrate cleanly—generated sources and headers flow through automatically.
- **Structured libraries**: Static, shared, and header-only libraries propagate their public interface to dependents.
- **IDE integration**: Every target exports `compile_commands.json` for clangd/LSP.

## Requirements

Nix with dynamic derivations support is **mandatory**. Enable the required experimental features in your Nix configuration (`~/.config/nix/nix.conf`):

```
experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
```
