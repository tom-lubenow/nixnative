# nixnative Examples

This directory contains self-contained example flakes demonstrating nixnative features.

All examples use Nix dynamic derivations for incremental builds without IFD.

## Requirements

Nix with dynamic derivations support:

```
experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
```

## Getting Started

**New to nixnative?** Start with `executable/` - it's the simplest example.

```sh
cd executable
nix build
./result/bin/executable-example
```

## Learning Path

Follow this progression to learn nixnative:

```
1. executable/          → Basic executable
       ↓
2. library/             → Static libraries, public interfaces
       ↓
3. header-only/         → Header-only libraries (no compilation)
       ↓
4. library-chain/       → Multi-library dependencies
       ↓
5. app-with-library/    → Combining libraries, code generation
       ↓
6. multi-toolchain/     → Compilers, linkers, optimization flags
```

Then explore specific features as needed:
- **Testing**: `testing/`, `test-libraries/`, `coverage/`
- **IDE Support**: `devshell/`
- **Shared Libraries**: `plugins/`, `install/`
- **Multi-Binary Projects**: `multi-binary/`
- **Code Generation**: `simple-tool/`
- **System Libraries**: `pkg-config/`
- **Mixed Languages**: `c-and-cpp/`
- **Dynamic Derivations**: `dynamic-derivations/`

## Example Index

| Example | Description | Key Features |
|---------|-------------|--------------|
| [executable](./executable/) | Minimal executable | `native.executable` |
| [library](./library/) | Static library | `native.staticLib`, `publicIncludeDirs` |
| [header-only](./header-only/) | Header-only library | `native.headerOnly` |
| [library-chain](./library-chain/) | Multi-library deps | Transitive dependencies |
| [app-with-library](./app-with-library/) | Complete application | Libraries, tool plugins, pkg-config |
| [multi-toolchain](./multi-toolchain/) | Compiler/linker variations | Abstract flags, build matrices |
| [testing](./testing/) | Test infrastructure | `native.test`, edge cases |
| [test-libraries](./test-libraries/) | Test frameworks | GTest, Catch2, doctest |
| [devshell](./devshell/) | Development environment | `native.lsps.clangd`, IDE integration |
| [plugins](./plugins/) | Dynamic plugin system | `native.sharedLib`, dlopen |
| [install](./install/) | Library installation | Static vs shared comparison |
| [simple-tool](./simple-tool/) | Custom code generator | Tool plugin interface |
| [pkg-config](./pkg-config/) | System libraries | `makeLibrary` |
| [c-and-cpp](./c-and-cpp/) | Mixed C/C++ | `.c` + `.cc` sources, `extern "C"` |
| [multi-binary](./multi-binary/) | Multiple executables | Shared libraries, CLI + daemon |
| [coverage](./coverage/) | Code coverage | `{ type = "coverage"; }`, lcov |
| [dynamic-derivations](./dynamic-derivations/) | Dynamic mode | Explicit dynamic derivations example |

## Feature Matrix

| Feature | Example(s) |
|---------|-----------|
| High-level API (`native.executable`, etc.) | All examples |
| Static libraries | `library/`, `library-chain/`, `app-with-library/`, `install/`, `multi-binary/` |
| Shared libraries | `plugins/`, `install/` |
| Header-only libraries | `header-only/`, `plugins/` |
| Abstract flags (LTO, sanitizers, coverage) | `multi-toolchain/`, `testing/`, `coverage/` |
| Custom toolchains | `multi-toolchain/` |
| Code generation tools | `app-with-library/`, `simple-tool/` |
| pkg-config integration | `pkg-config/`, `app-with-library/` |
| Test infrastructure | `testing/`, `test-libraries/`, `coverage/` |
| Code coverage | `coverage/` |
| IDE/LSP integration | `devshell/`, `multi-binary/` |
| Mixed C/C++ sources | `c-and-cpp/` |
| Multi-library dependencies | `library-chain/` |
| Multi-binary projects | `multi-binary/` |

## Running Examples

Each example is a standalone flake:

```sh
cd <example>
nix build              # Build default package
nix flake check        # Run tests
nix develop            # Enter dev shell (if available)
```

From the root nixnative directory:

```sh
nix build .#executableExample
nix build .#app
nix flake check        # Run all example tests
```

## Structure

Each example follows a consistent structure:

```
example/
├── flake.nix       # Flake with inputs and outputs
├── project.nix     # Build definitions (optional, can be inline)
├── checks.nix      # Tests (optional)
├── README.md       # Documentation
└── src/            # Source files
```

## Creating Your Own Project

1. Copy an example directory as a starting point
2. Update `flake.nix` to point to nixnative
3. Modify `project.nix` with your sources and libraries
4. Run `nix build` to verify

Example `flake.nix` for a new project:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "github:your-org/nixnative";
  };

  outputs = { self, nixpkgs, nixnative }: {
    packages.x86_64-linux = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      native = nixnative.lib.native { inherit pkgs; };
    in {
      default = native.executable {
        name = "my-app";
        root = ./.;
        sources = [ "src/main.cc" ];
      };
    };
  };
}
```
