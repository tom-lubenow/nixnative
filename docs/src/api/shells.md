# Shell Options

Development shells provide a configured environment for working on your project.

## `devShell`

Creates a development shell from a built target with toolchain and IDE support.

```nix
native.devShell {
  target = myApp;               # Built target to get toolchain from
  extraPackages = [ pkgs.gdb ]; # Additional packages
  includeTools = true;          # Include clang-tools, gdb (default: true)
}
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `target` | Yes | - | Built target to derive toolchain from |
| `extraPackages` | No | `[]` | Additional packages to include |
| `includeTools` | No | `true` | Include clang-tools, gdb, etc. |

## Basic Usage

```nix
let
  proj = native.project { root = ./.; };

  myApp = proj.executable {
    name = "my-app";
    sources = [ "src/main.cc" ];
  };
in {
  devShells.default = native.devShell { target = myApp; };
}
```

Enter the shell:
```sh
nix develop
```

## What's Included

When `includeTools = true` (default), the shell includes:

- The target's compiler (clang or gcc)
- The target's linker (lld, mold, or ld)
- clang-tools (clang-format, clang-tidy, clangd)
- gdb debugger
- Any packages from `extraPackages`

## `shell`

Creates a standalone development shell without a target (just the toolchain).

```nix
native.shell {
  compiler = "clang";           # "clang", "gcc", or compiler object
  linker = "mold";              # "lld", "mold", "ld", or linker object
  extraPackages = [ pkgs.cmake pkgs.ninja ];
  includeTools = true;
}
```

This is useful when you want a development environment before defining any build targets.

## Parameters for `shell`

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `compiler` | No | `"clang"` | Compiler to include |
| `linker` | No | `"lld"` | Linker to include |
| `extraPackages` | No | `[]` | Additional packages |
| `includeTools` | No | `true` | Include clang-tools, gdb |

## Adding Extra Packages

```nix
native.devShell {
  target = myApp;
  extraPackages = [
    pkgs.cmake
    pkgs.ninja
    pkgs.valgrind
    pkgs.perf
  ];
}
```

## Multiple Shells

Define different shells for different purposes:

```nix
let
  proj = native.project { root = ./.; };

  app = proj.executable {
    name = "app";
    sources = [ "main.cc" ];
  };

  debugApp = proj.executable {
    name = "app-debug";
    sources = [ "main.cc" ];
    sanitizers = [ "address" ];
  };
in {
  devShells = {
    default = native.devShell { target = app; };
    debug = native.devShell {
      target = debugApp;
      extraPackages = [ pkgs.valgrind ];
    };
  };
}
```

Enter a specific shell:
```sh
nix develop .#debug
```

## Low-Level Variant

`mkDevShell` allows explicit toolchain specification:

```nix
native.mkDevShell {
  target = myApp;
  toolchain = myToolchain;  # Optional: override target's toolchain
  includeTools = true;
}
```

## IDE Integration

The development shell sets up environment variables that IDEs can use:

- `CC` - C compiler path
- `CXX` - C++ compiler path
- `LD` - Linker path

clangd (for LSP support) will automatically find the compiler from the shell environment.
