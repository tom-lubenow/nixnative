# Project Options

## `project` (Recommended)

Creates a project with shared defaults and returns scoped builders.

```nix
let
  proj = native.project {
    root = ./.;
    includeDirs = [ "include" ];
    warnings = "all";
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
| `warnings` | No | `"default"` | Warning level: `"none"`, `"default"`, `"all"`, `"extra"`, `"pedantic"` |
| `optimize` | No | `null` | Optimization: `"0"`, `"1"`, `"2"`, `"3"`, `"s"`, `"z"`, `"fast"` |
| `lto` | No | `false` | LTO: `false`, `true`, `"thin"`, or `"full"` |

## Scoped Builders

The project returns these scoped builder functions:

- `proj.executable { ... }` - Build an executable
- `proj.staticLib { ... }` - Build a static library
- `proj.sharedLib { ... }` - Build a shared library
- `proj.headerOnly { ... }` - Define a header-only library

All builders inherit the project's defaults but can override them.

## Extending Projects

Use `proj.extend` to create nested projects with additional defaults:

```nix
let
  proj = native.project {
    root = ./.;
    warnings = "all";
  };

  debugProj = proj.extend {
    defines = [ "DEBUG" ];
    optimize = "0";
  };

  releaseProj = proj.extend {
    lto = "thin";
    optimize = "2";
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
