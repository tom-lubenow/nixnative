# nixnative API Reference

This document describes the public API exposed by `nixnative.lib.native`.

## API Layers

| API Level | Functions | When to Use |
|-----------|-----------|-------------|
| **Composable (canonical)** | `project` | Recommended for almost all projects |
| **Direct builders** | `executable`, `staticLib`, `sharedLib`, `headerOnly`, `devShell`, `shell`, `test` | One-off targets or custom composition |
| **Low-level explicit** | `mkExecutable`, `mkStaticLib`, `mkSharedLib`, `mkHeaderOnly`, `mkDevShell`, `mkTest` | Full explicit toolchain control |

## Canonical Pattern

Use `native.project` as the default entrypoint.

```nix
let
  proj = native.project {
    root = ./.;
    includeDirs = [ "include" ];
    compileFlags = [ "-Wall" "-Wextra" ];
  };

  libmath = proj.staticLib {
    name = "libmath";
    sources = [ "src/math.cc" ];
    publicIncludeDirs = [ "include" ];
  };

  app = proj.executable {
    name = "app";
    sources = [ "src/main.cc" ];
    libraries = [ libmath ];
  };
in {
  packages = { inherit libmath app; };
}
```

The key model is value composition: targets are plain values passed through `libraries`.

## Toolchains

Toolchains are explicit composition of:

- `toolset`: compilers/linker/binutils
- `policy`: platform/runtime/flag merge policy

```nix
native.mkToolchain {
  toolset = native.mkToolset {
    languages = {
      c = native.compilers.clang.c;
      cpp = native.compilers.clang.cpp;
    };
    linker = native.linkers.lld;
    bintools = native.compilers.clang.bintools;
  };
  policy = native.mkPolicy { };
}
```

## Language Scope

nixnative's native compilation pipeline currently supports **C/C++**.

## Generated Option Reference

Option-level reference docs are generated from the shared schema in `nix/native/modules/schema.nix`:

- `docs/src/api/index.md`
- `docs/src/api/project.md`
- `docs/src/api/targets.md`
- `docs/src/api/defaults.md`
- `docs/src/api/tests.md`
- `docs/src/api/shells.md`

## Incrementality Gate

Run this before making incrementality/cache behavior claims:

```sh
nix run .#incrementality-gate
```

The gate verifies no-op rebuild behavior plus one-file-change behavior on a two-source target.
