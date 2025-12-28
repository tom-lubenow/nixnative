# nixnative

Incremental C/C++ builds using Nix dynamic derivations.

## Overview

nixnative implements minimal, incremental C/C++ build graphs natively in Nix using [RFC 92 dynamic derivations](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md). Each source file becomes its own derivation, enabling true per-file incrementality while eliminating IFD (Import From Derivation) during evaluation.

## Requirements

This project requires Nix with dynamic derivations support. The recommended version is pinned in `flake.nix`:

```nix
# Nix with full dynamic derivations support (commit d904921)
inputs.nix.url = "github:NixOS/nix/d904921eecbc17662fef67e8162bd3c7d1a54ce0";
```

Enable the required experimental features in your Nix configuration:

```
experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
```

## Why Dynamic Derivations?

Traditional approaches to incremental C++ builds in Nix face a fundamental tradeoff:

1. **IFD-based scanning**: Evaluation blocks while scanning dependencies, breaking `nix flake check` and slowing CI.
2. **Checked-in manifests**: Requires manual synchronization, adding maintenance burden.

Dynamic derivations solve this by deferring derivation creation to build time:

```
EVALUATION (instant):
  sources → driver.drv (single derivation)
                ↓
  builtins.outputOf → placeholder for compilation outputs

BUILD TIME:
  1. driver.drv runs scanner (clang -MMD)
  2. driver.drv generates compilation .drv files via `nix derivation add`
  3. Nix automatically builds those .drv files
  4. link step receives actual object paths
```

This gives you:

- **Instant evaluation**: No IFD blocking during `nix eval` or `nix flake check`
- **True incrementality**: Change one file, rebuild one derivation
- **Full toolchain control**: Compilers, linkers, and flags are explicit inputs
- **Content-addressed caching**: Identical compilations are deduplicated

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
- `examples/app-with-library` – Executable + library + tool plugins
- `examples/multi-toolchain` – Different compiler/linker combinations
- `examples/dynamic-derivations` – Explicit dynamic mode example

Build an example:

```sh
nix build .#executableExample
./result/bin/executable-example
```

## Platform Support

- **Linux** (x86_64, aarch64): Primary supported platform
- **macOS** (aarch64-darwin): Best-effort support

## Repository Layout

```
.
├── flake.nix       # Top-level flake with examples
├── nix/native/     # Core library (compilers, linkers, toolchains, builders)
│   ├── dynamic/    # Dynamic derivations implementation
│   ├── builders/   # High-level build functions
│   └── ...
└── examples/       # Example projects
```

## Current Status

This project builds on experimental Nix features. The dynamic derivations implementation is based on [John Ericson's work on RFC 92](https://github.com/NixOS/nix/commits/author/John-Ericson).

Key references:
- [RFC 92: Plan Dynamism](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md)
- [Farid Zakaria's nix-ninja blog posts](https://fzakaria.com/)
- [nix-ninja project](https://github.com/aspect-build/nix-ninja)

## License

MIT
