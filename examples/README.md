# nixnative Examples

This directory contains self-contained example flakes demonstrating nixnative features.

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
1. executable/          → Basic executable, high-level API
       ↓
2. library/             → Static libraries, public interfaces
       ↓
3. header-only/         → Header-only libraries (no compilation)
       ↓
4. library-chain/       → Multi-library dependencies
       ↓
5. app-with-library/    → Combining libraries, code generation, manifests
       ↓
6. multi-toolchain/     → Compilers, linkers, optimization flags
```

Then explore specific features as needed:
- **Testing**: `testing/`, `coverage/`
- **IDE Support**: `devshell/`
- **Shared Libraries**: `plugins/`, `install/`
- **Multi-Binary Projects**: `multi-binary/`
- **Language Interop**: `rust-integration/`, `rust-integration-crane/`, `interop/`, `python-extension/`
- **Code Generation**: `protobuf/`, `grpc/`, `jinja-templates/`, `simple-tool/`
- **System Libraries**: `pkg-config/`
- **Mixed Languages**: `c-and-cpp/`
- **Cross-Compilation**: `cross-compile/` (experimental)

## Example Index

| Example | Description | Key Features |
|---------|-------------|--------------|
| [executable](./executable/) | Minimal executable | `native.executable`, auto-scanning |
| [library](./library/) | Static library | `native.staticLib`, `publicIncludeDirs` |
| [header-only](./header-only/) | Header-only library | `native.headerOnly`, templates |
| [library-chain](./library-chain/) | Multi-library deps | Transitive dependencies, layered architecture |
| [app-with-library](./app-with-library/) | Complete application | Libraries, tools, manifests, pkg-config |
| [multi-toolchain](./multi-toolchain/) | Compiler/linker variations | Abstract flags, build matrices |
| [testing](./testing/) | Test infrastructure | `native.test`, edge cases |
| [devshell](./devshell/) | Development environment | `native.lsps.clangd`, IDE integration |
| [plugins](./plugins/) | Dynamic plugin system | `native.sharedLib`, dlopen |
| [install](./install/) | Library installation | Static vs shared comparison |
| [protobuf](./protobuf/) | Protocol Buffers | `native.tools.protobuf`, code generation |
| [grpc](./grpc/) | gRPC services | `native.tools.grpc`, server/client |
| [jinja-templates](./jinja-templates/) | Jinja2 templates | `native.tools.jinja`, config headers |
| [simple-tool](./simple-tool/) | Custom code generator | Generator schema, inline tools |
| [pkg-config](./pkg-config/) | System libraries | `makeLibrary` |
| [c-and-cpp](./c-and-cpp/) | Mixed C/C++ | `.c` + `.cc` sources, `extern "C"` |
| [rust-integration](./rust-integration/) | Rust interop (rustc) | Foreign library wrapping |
| [rust-integration-crane](./rust-integration-crane/) | Rust interop (Cargo) | Crane integration |
| [interop](./interop/) | Zig interop | C ABI, foreign libraries |
| [multi-binary](./multi-binary/) | Multiple executables | Shared libraries, CLI + daemon + tests |
| [coverage](./coverage/) | Code coverage | `{ type = "coverage"; }`, lcov |
| [cross-compile](./cross-compile/) | Cross-compilation (experimental) | Nix cross, Zig targets |
| [python-extension](./python-extension/) | Python C extension | Python C API, shared libraries |

## Feature Matrix

| Feature | Example(s) |
|---------|-----------|
| High-level API (`native.executable`, etc.) | All examples |
| Low-level API (`native.mkExecutable`, etc.) | `multi-toolchain/` |
| Static libraries | `library/`, `library-chain/`, `app-with-library/`, `install/`, `multi-binary/` |
| Shared libraries | `plugins/`, `install/`, `python-extension/` |
| Header-only libraries | `header-only/`, `plugins/` |
| Abstract flags (LTO, sanitizers, coverage) | `multi-toolchain/`, `testing/`, `coverage/` |
| Custom toolchains | `multi-toolchain/` |
| Dependency manifests | `app-with-library/` |
| Code generation tools | `app-with-library/`, `protobuf/`, `grpc/`, `jinja-templates/`, `simple-tool/` |
| Jinja2 templates | `jinja-templates/`, `app-with-library/` |
| gRPC services | `grpc/` |
| pkg-config integration | `pkg-config/`, `app-with-library/`, `protobuf/`, `grpc/` |
| Test infrastructure | `testing/`, `coverage/`, most examples via checks |
| Code coverage | `coverage/` |
| IDE/LSP integration | `devshell/`, `multi-binary/` |
| Foreign language interop | `rust-integration/`, `rust-integration-crane/`, `interop/`, `python-extension/` |
| Python extensions | `python-extension/` |
| Mixed C/C++ sources | `c-and-cpp/` |
| Multi-library dependencies | `library-chain/` |
| Multi-binary projects | `multi-binary/` |
| Cross-compilation | `cross-compile/` |

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
nix build .#simple-strict
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
2. Update `flake.nix` to point to nixnative (change `path:../..` to your input)
3. Modify `project.nix` with your sources and libraries
4. Run `nix build` to verify

Example `flake.nix` for a new project:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "github:your-org/nixnative";  # or local path
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
