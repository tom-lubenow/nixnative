# Project Options

## `project` (Recommended)

Creates a project with shared defaults and returns scoped builders.

```nix
let
  proj = native.project {
    root = ./.;
    includeDirs = [ "include" ];
    compileFlags = [ "-Wall" "-Wextra" ];
  };

  myLib = proj.staticLib {
    name = "libmylib";
    sources = [ "src/lib.cc" ];
    publicIncludeDirs = [ "include" ];
  };

  myApp = proj.executable {
    name = "my-app";
    sources = [ "src/main.cc" ];
    libraries = [ myLib ];  # Direct reference!
  };

  testMyApp = native.test {
    name = "test-my-app";
    executable = myApp;
    expectedOutput = "Hello";
  };
in {
  packages = { inherit myLib myApp; };
  checks = { inherit testMyApp; };
  devShells.default = native.devShell { target = myApp; };
}
```

## Project Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `root` | Yes | - | Project root directory |
| `compiler` | No | `"clang"` | Compiler: `"clang"`, `"gcc"`, or compiler object |
| `linker` | No | `"lld"` | Linker: `"lld"`, `"mold"`, `"ld"`, or linker object |
| `includeDirs` | No | `[]` | Default include directories for all targets |
| `defines` | No | `[]` | Default preprocessor definitions |
| `compileFlags` | No | `[]` | Default compiler flags |
| `languageFlags` | No | `{}` | Per-language flags (`{ c = [...]; cpp = [...]; }`) |
| `linkFlags` | No | `[]` | Default linker flags |
| `libraries` | No | `[]` | Default libraries for all targets |
| `tools` | No | `[]` | Default code-generation tools |
| `publicIncludeDirs` | No | `[]` | Default public include dirs for library targets |
| `publicDefines` | No | `[]` | Default public defines for library targets |
| `publicCompileFlags` | No | `[]` | Default public compile flags for library targets |
| `publicLinkFlags` | No | `[]` | Default public link flags for library targets |

## Scoped Builders

The project returns these scoped builder functions:

- `proj.executable { ... }` - Build an executable
- `proj.staticLib { ... }` - Build a static library
- `proj.sharedLib { ... }` - Build a shared library
- `proj.headerOnly { ... }` - Define a header-only library

All builders inherit the project's defaults but can override them. Lists are concatenated; lists of strings/paths are
deduplicated (first occurrence wins) while lists of attrsets are not.

## Extending Projects

Use `proj.extend` to create nested projects with additional defaults:

```nix
let
  proj = native.project {
    root = ./.;
    compileFlags = [ "-Wall" "-Wextra" ];
  };

  debugProj = proj.extend {
    defines = [ "DEBUG" ];
    compileFlags = [ "-g" "-O0" ];
  };

  releaseProj = proj.extend {
    compileFlags = [ "-O2" "-flto=thin" ];
    linkFlags = [ "-flto=thin" ];
  };
in { ... }
```

## Direct References

Targets are real values that can be passed directly:

```nix
myLib = proj.staticLib { name = "mylib"; sources = [ "lib.cc" ]; };
myApp = proj.executable {
  name = "myapp";
  sources = [ "main.cc" ];
  libraries = [ myLib ];  # Direct reference, not a string!
};
```

This replaces the older module-based `{ target = "name"; }` syntax.
