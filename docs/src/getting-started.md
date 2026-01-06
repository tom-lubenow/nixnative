# Getting Started

## Quick Start

```nix
# flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixnative.url = "github:tom-lubenow/nixnative";

  outputs = { nixpkgs, nixnative, ... }: {
    packages.x86_64-linux.default = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      native = nixnative.lib.native { inherit pkgs; };
    in (native.project {
      modules = [
        {
          native = {
            root = ./.;
            targets.hello = {
              type = "executable";
              name = "hello";
              sources = [ "src/main.cc" ];
            };
          };
        }
      ];
    }).packages.hello;
  };
}
```

Build and run:

```sh
# Build and get the output path in one command
nix build --print-out-paths
# Output: /nix/store/xxx-hello

# Run directly from the store path
$(nix build --print-out-paths)/bin/hello
```

> **Note**: Dynamic derivations don't create the traditional `./result` symlink.
> Use `--print-out-paths` to get the store path, or `nix path-info .#target` after building.

## Module-First API

The recommended way to use nixnative is through the module-first API:

```nix
native.project {
  modules = [
    {
      native = {
        root = ./.;
        defaults = {
          includeDirs = [ "include" ];
          warnings = "all";
        };

        targets.myApp = {
          type = "executable";
          name = "my-app";
          sources = [ "src/main.cc" ];
        };

        targets.myLib = {
          type = "staticLib";
          name = "libmylib";
          sources = [ "src/lib.cc" ];
          publicIncludeDirs = [ "include" ];
        };

        tests.myApp = {
          executable = "myApp";
          expectedOutput = "Hello";
        };

        shells.default = {
          target = "myApp";
        };
      };
    }
  ];
}
```

The `project` function returns:

- `packages` - built targets
- `checks` - test derivations
- `devShells` - development shells
- `config` - evaluated module config (for introspection)

## Target Types

- `executable` - Linked binary
- `staticLib` - Static library (.a)
- `sharedLib` - Shared library (.so)
- `headerOnly` - Header-only library (no compilation)

## Target References

Use `{ target = "name"; }` to reference other targets:

```nix
targets.myApp = {
  type = "executable";
  sources = [ "src/main.cc" ];
  libraries = [ { target = "myLib"; } ];  # Reference by name
};
```

## Examples

See the `examples/` directory for working examples:

- `examples/executable` – Minimal executable
- `examples/library` – Static library with public headers
- `examples/header-only` – Header-only library
- `examples/library-chain` – Transitive library dependencies
- `examples/app-with-library` – Executable depending on a static library
- `examples/multi-toolchain` – Different compiler/linker combinations
- `examples/testing` – Unit tests with module-defined tests
- `examples/test-libraries` – GoogleTest, Catch2, and doctest integration
- `examples/coverage` – Code coverage with gcov/llvm-cov
- `examples/plugins` – Shared library plugins with dlopen
- `examples/devshell` – Development shell with clangd support

Build an example:

```sh
nix build .#executableExample --print-out-paths
```
