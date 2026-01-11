# Target Options

Targets are the core build outputs: executables, static libraries, shared libraries, and header-only libraries.

## `executable`

Builds an executable binary.

```nix
native.executable {
  name = "my-app";              # Required: output name
  root = ./.;                   # Required: project root directory
  sources = [ "src/main.cc" ];  # Required: list of source files (relative to root)

  # Optional: toolchain selection (defaults to clang + lld)
  compiler = "clang";           # "clang", "gcc", or compiler object
  linker = "lld";               # "lld", "mold", "ld", or linker object

  # Optional build configuration
  includeDirs = [ "include" ];  # Include directories
  defines = [ "DEBUG" ];        # Preprocessor definitions
  compileFlags = [ "-O2" ];     # Additional compiler flags
  languageFlags = { cpp = [ "-std=c++20" ]; };  # Per-language flags
  linkFlags = [ "-lm" ];        # Additional linker flags
  libraries = [ myLib ];        # Library dependencies
  tools = [ myTool ];           # Tool plugins (protobuf, jinja, etc.)

  # Ergonomic optimization flags
  lto = "thin";                 # false, true, "thin", or "full"
  sanitizers = [ "address" ];   # [ "address" "undefined" "thread" "memory" "leak" ]
  coverage = false;             # Enable code coverage
  optimize = "2";               # "0", "1", "2", "3", "s", "z", "fast"
  warnings = "all";             # "none", "default", "all", "extra", "pedantic"
}
```

## `staticLib`

Builds a static library with public interface.

```nix
native.staticLib {
  name = "libmylib";                  # Output: libmylib.a
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ];  # Headers exposed to consumers
  publicDefines = [ "MY_LIB=1" ];     # Defines propagated to consumers
  # ... same options as executable
}
```

**Note:** The `name` is used exactly as specified for the output filename. Include the `lib` prefix for standard libraries (e.g., `name = "libfoo"` produces `libfoo.a`). For plugins loaded via `dlopen()`, omit the prefix (e.g., `name = "my-plugin"` produces `my-plugin.so`).

## `sharedLib`

Builds a shared library (`.so`/`.dylib`).

```nix
native.sharedLib {
  name = "libmylib";                  # Output: libmylib.so
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ];
  # ... same options as staticLib
}
```

## `headerOnly`

Defines a header-only library (no compilation).

```nix
native.headerOnly {
  name = "my-headers";
  root = ./.;
  publicIncludeDirs = [ "include" ];
  publicDefines = [ "HEADER_ONLY=1" ];
}
```

## Common Parameters

All target types share these parameters:

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Output name |
| `root` | Yes | - | Project root directory |
| `sources` | Varies | `[]` | Source files (not for headerOnly) |
| `includeDirs` | No | `[]` | Include directories |
| `defines` | No | `[]` | Preprocessor definitions |
| `compileFlags` | No | `[]` | Additional compiler flags |
| `languageFlags` | No | `{}` | Per-language flags (`{ c = [...]; cpp = [...]; }`) |
| `linkFlags` | No | `[]` | Additional linker flags |
| `libraries` | No | `[]` | Library dependencies |
| `tools` | No | `[]` | Code generators |

## Library-Specific Parameters

| Parameter | Description |
|-----------|-------------|
| `publicIncludeDirs` | Include directories exposed to consumers |
| `publicDefines` | Preprocessor definitions propagated to consumers |
| `publicCompileFlags` | Compiler flags propagated to consumers |
| `publicLinkFlags` | Linker flags propagated to consumers |

## Public Attribute Schema

Libraries expose a `public` attribute that propagates flags to dependents:

```nix
{
  includeDirs = [ ];   # List of include directories
  defines = [ ];       # List of preprocessor definitions
  compileFlags = [ ];  # List of compiler flags
  linkFlags = [ ];     # List of linker flags
}
```

## Low-Level Variants

For explicit toolchain control, use the `mk*` variants:

- `mkExecutable` - Requires explicit `toolchain` parameter
- `mkStaticLib` - Requires explicit `toolchain` parameter
- `mkSharedLib` - Requires explicit `toolchain` parameter
- `mkHeaderOnly` - No toolchain needed

```nix
native.mkExecutable {
  name = "my-app";
  root = ./.;
  sources = [ "src/main.cc" ];
  toolchain = native.mkToolchain {
    compiler = native.compilers.clang;
    linker = native.linkers.mold;
  };
}
```
