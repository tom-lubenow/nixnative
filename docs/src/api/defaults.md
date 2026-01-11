# Default Options

This page covers the common options shared across all target types and how defaults propagate through the project.

## Toolchain Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `compiler` | `"clang"`, `"gcc"`, or object | `"clang"` | C/C++ compiler |
| `linker` | `"lld"`, `"mold"`, `"ld"`, or object | `"lld"` | Linker |

## Warning Levels

| Level | Description |
|-------|-------------|
| `"none"` | Disable all warnings |
| `"default"` | Compiler defaults |
| `"all"` | `-Wall` |
| `"extra"` | `-Wall -Wextra` |
| `"pedantic"` | `-Wall -Wextra -Wpedantic` |

## Optimization Levels

| Level | Flag | Description |
|-------|------|-------------|
| `"0"` | `-O0` | No optimization (fastest compile) |
| `"1"` | `-O1` | Basic optimization |
| `"2"` | `-O2` | Standard optimization |
| `"3"` | `-O3` | Aggressive optimization |
| `"s"` | `-Os` | Optimize for size |
| `"z"` | `-Oz` | Aggressive size optimization |
| `"fast"` | `-Ofast` | Fast math, may break IEEE compliance |

## LTO Options

| Value | Description |
|-------|-------------|
| `false` | Disable LTO |
| `true` | Enable LTO (full) |
| `"thin"` | Thin LTO (faster, good for development) |
| `"full"` | Full LTO (slower, best optimization) |

## Sanitizers

Available sanitizers (can combine multiple):

| Sanitizer | Description |
|-----------|-------------|
| `"address"` | AddressSanitizer - memory errors |
| `"undefined"` | UBSan - undefined behavior |
| `"thread"` | ThreadSanitizer - data races |
| `"memory"` | MemorySanitizer - uninitialized reads |
| `"leak"` | LeakSanitizer - memory leaks |

Example:
```nix
proj.executable {
  name = "test-app";
  sources = [ "test.cc" ];
  sanitizers = [ "address" "undefined" ];
}
```

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
    warnings = "all";       # All targets get -Wall
    optimize = "2";         # All targets get -O2
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
    optimize = "0";         # Override: -O0 instead of -O2
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
    warnings = "all";
  };

  # Debug variant
  debug = proj.extend {
    optimize = "0";
    defines = [ "DEBUG" ];
  };

  # Release variant
  release = proj.extend {
    optimize = "2";
    lto = "thin";
  };

  debugApp = debug.executable { name = "app-debug"; sources = [ "main.cc" ]; };
  releaseApp = release.executable { name = "app"; sources = [ "main.cc" ]; };
in { ... }
```
