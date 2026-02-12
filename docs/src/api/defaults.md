# Default Options

This page covers the common options shared across all target types and how defaults propagate through the project.

## Toolchain Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `compiler` | `"clang"`, `"gcc"`, or object | `"clang"` | C/C++ compiler |
| `linker` | `"lld"`, `"mold"`, `"ld"`, or object | `"lld"` | Linker |

## Explicit Flag Presets

Use raw flags directly in `compileFlags` and `linkFlags`.

| Intent | `compileFlags` | `linkFlags` |
|--------|----------------|-------------|
| Strict warnings | `[ "-Wall" "-Wextra" "-Wpedantic" ]` | `[]` |
| Release | `[ "-O2" ]` | `[]` |
| LTO thin | `[ "-O2" "-flto=thin" ]` | `[ "-flto=thin" ]` |
| Address/UB sanitizers | `[ "-fsanitize=address,undefined" "-g" ]` | `[ "-fsanitize=address,undefined" ]` |
| Coverage | `[ "--coverage" "-g" "-O0" ]` | `[ "--coverage" ]` |

## Per-Language Flags

Use `languageFlags` to set different flags for C and C++:

```nix
proj.executable {
  name = "mixed-app";
  sources = [ "legacy.c" "modern.cc" ];
  languageFlags = {
    c = [ "-std=c11" ];
    cpp = [ "-std=c++20" ];
  };
}
```

## Preprocessor Definitions

Definitions can be strings or attribute sets:

```nix
defines = [
  "DEBUG"                        # Simple define
  { name = "VERSION"; value = "1.0.0"; }  # Define with value
];
```

## Include Directories

Include directories are resolved relative to `root`:

```nix
proj.executable {
  root = ./.;
  sources = [ "src/main.cc" ];
  includeDirs = [
    "include"           # Relative path
    "third_party/lib"   # Another relative path
  ];
}
```

## Default Inheritance

Project defaults flow to all targets:

```nix
let
  proj = native.project {
    root = ./.;
    compileFlags = [ "-Wall" "-Wextra" "-O2" ];
    includeDirs = [ "include" ];  # All targets include this
  };

  # Inherits project defaults
  app = proj.executable {
    name = "app";
    sources = [ "main.cc" ];
  };

  # Can override specific defaults
  debugApp = proj.executable {
    name = "debug-app";
    sources = [ "main.cc" ];
    compileFlags = [ "-g" "-O0" ];  # Added after project defaults
    defines = [ "DEBUG" ];  # Add debug define
  };
in { ... }
```

## Extending Defaults

Use `proj.extend` for variant configurations:

```nix
let
  proj = native.project {
    root = ./.;
    compileFlags = [ "-Wall" "-Wextra" ];
  };

  # Debug variant
  debug = proj.extend {
    compileFlags = [ "-g" "-O0" ];
    defines = [ "DEBUG" ];
  };

  # Release variant
  release = proj.extend {
    compileFlags = [ "-O2" "-flto=thin" ];
    linkFlags = [ "-flto=thin" ];
  };

  debugApp = debug.executable { name = "app-debug"; sources = [ "main.cc" ]; };
  releaseApp = release.executable { name = "app"; sources = [ "main.cc" ]; };
in { ... }
```
