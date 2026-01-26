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
      native = nixnative.lib.native { inherit pkgs; };

      # Create a project with shared defaults
      proj = native.project {
        root = ./.;
        warnings = "all";
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
    warnings = "all";
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
- **No string references**: Unlike module-based APIs, you don't need `{ target = "name"; }`
- **Composable**: Use standard Nix patterns like helpers, imports, and function composition

### Merge Behavior

When you call a scoped builder like `proj.executable { ... }`:

- **Lists** (includeDirs, defines, libraries, etc.) are **concatenated**: defaults ++ target
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

## Alternative: Module-Based API

If you prefer typed options and Nix module composition, use `native.evalProject`:

```nix
native.evalProject {
  modules = [
    {
      native = {
        root = ./.;
        targets.myApp = {
          type = "executable";
          sources = [ "src/main.cc" ];
        };
      };
    }
  ];
}
```

This returns `{ packages, checks, devShells, config }`. See the [API Reference](api/project.md) for module option documentation.

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
