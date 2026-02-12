# Getting Started

## Quick Start

```nix
# flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixnative.url = "github:tom-lubenow/nixnative";

  outputs = { nixpkgs, nixnative, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      nixPackage = nixnative.inputs.nix.packages.${system}.default;
      ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
      native = nixnative.lib.native {
        inherit pkgs nixPackage;
        inherit (ninjaPackages) nix-ninja nix-ninja-task;
      };

      # Create a project with shared defaults
      proj = native.project {
        root = ./.;
        compileFlags = [ "-Wall" "-Wextra" ];
      };

      # Build a simple executable
      hello = proj.executable {
        name = "hello";
        sources = [ "src/main.cc" ];
      };
    in {
      packages.${system}.default = hello;
    };
}
```

Build and run:

```sh
# Build and get the output path
nix build --print-out-paths
# Output: /nix/store/xxx-hello

# Run directly
$(nix build --print-out-paths)/hello
```

> **Note**: Dynamic derivations don't create the traditional `./result` symlink.
> Use `--print-out-paths` to get the store path.

## The Project Helper

`native.project` creates scoped builders with shared defaults. It returns an attrset containing `executable`, `staticLib`, `sharedLib`, `headerOnly`, `devShell`, and `test` functions that automatically merge your defaults with per-target arguments.

```nix
let
  proj = native.project {
    root = ./.;
    includeDirs = [ "include" ];
    defines = [ "DEBUG" ];
    compileFlags = [ "-Wall" "-Wextra" ];
  };

  # All targets inherit the defaults above
  libfoo = proj.staticLib {
    name = "libfoo";
    sources = [ "src/foo.c" ];
    publicIncludeDirs = [ "include" ];
  };

  app = proj.executable {
    name = "app";
    sources = [ "src/main.c" ];
    libraries = [ libfoo ];  # Direct reference - not a string!
  };
in {
  packages = { inherit libfoo app; };
}
```

### Key Benefits

- **Targets are real values**: Pass them directly to `libraries`, import from other files, or compose with plain Nix functions
- **No indirection**: Dependencies are plain values, not a separate label/reference system
- **Composable**: Use standard Nix patterns like helpers, imports, and function composition

## Mental Model

Think in three layers:

1. **Toolchain** (`toolset` + `policy`) defines *how* code is compiled and linked.
2. **Project defaults** define shared conventions (`includeDirs`, flags, shared libraries).
3. **Targets** define concrete artifacts and compose by passing target values through `libraries`.

In practice, keep defaults small and explicit, and model reusable link/include policy as reusable library values.

### Merge Behavior

When you call a scoped builder like `proj.executable { ... }`:

- **Lists** (includeDirs, defines, libraries, etc.) are **concatenated**: defaults ++ target
  - Lists of strings/paths are deduplicated (first occurrence wins); lists of attrsets are not
- **Attrs** (languageFlags) are **merged**: `defaults // target`
- **Scalars** (name, root, compiler, etc.) from target **override** defaults

## Helper Patterns

For projects with many similar targets, use plain Nix functions:

```nix
let
  proj = native.project {
    root = ./.;
    defines = [ "HAVE_CONFIG_H" ];
  };

  # Common settings for CLI tools
  cliDefaults = {
    linkFlags = [ "-lpthread" "-ldl" ];
    libraries = [ libcommon ];
  };

  # Helper to create CLI tools
  mkCli = args: proj.executable (cliDefaults // args);

  # Create multiple tools
  sinfo = mkCli { name = "sinfo"; sources = [ "src/sinfo.c" ]; };
  squeue = mkCli { name = "squeue"; sources = [ "src/squeue.c" ]; };
in { ... }
```

## Extending Projects

Use `proj.extend` to create nested projects with additional defaults:

```nix
let
  base = native.project {
    root = ./.;
    defines = [ "BASE" ];
  };

  # Extend with additional defaults for daemons
  daemon = base.extend {
    linkFlags = [ "-lpthread" "-lrt" ];
    defines = [ "DAEMON" ];  # Appended: [ "BASE" "DAEMON" ]
  };

  myDaemon = daemon.executable { name = "mydaemon"; sources = [...]; };
in { ... }
```

## Target Types

- `executable` - Linked binary
- `staticLib` - Static library (.a)
- `sharedLib` - Shared library (.so)
- `headerOnly` - Header-only library (no compilation)

## Incrementality Gate

Run the incrementality quality gate before making performance claims:

```sh
nix run .#incrementality-gate
```

## Examples

See the `examples/` directory:

- `examples/composable-project` – New composable API pattern
- `examples/executable` – Minimal executable
- `examples/library` – Static library with public headers
- `examples/app-with-library` – Executable depending on a library
- `examples/multi-toolchain` – Different compiler/linker combinations
- `examples/testing` – Unit tests
- `examples/devshell` – Development shell with clangd support

Build an example:

```sh
nix build .#executableExample --print-out-paths
```
