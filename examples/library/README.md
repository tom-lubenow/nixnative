# Library Example

This example demonstrates building a reusable static library with nixnative.

## What This Demonstrates

- Building static libraries with the composable project API
- Exposing public headers via `publicIncludeDirs`
- Consuming the library from another target

## Project Structure

```
library/
├── flake.nix       # Flake boilerplate
├── project.nix     # Library definition
├── test/
│   └── main.cc     # Test that consumes the library
├── src/
│   └── math.cc     # Implementation
└── include/
    └── math.hpp    # Public header
```

## Build

```sh
nix build
```

The output contains:
- `$out/lib/libmath-example.a` - The static archive
- `$out/include/math.hpp` - The public header

## How It Works

### Building the Library

```nix
let
  proj = native.project {
    root = ./.;
  };

  mathLibrary = proj.staticLib {
    name = "libmath-example";
    sources = [ "src/math.cc" ];
    includeDirs = [ "include" ];
    publicIncludeDirs = [ "include" ];
  };

  mathLibraryTest = proj.executable {
    name = "math-library-test";
    root = ./test;
    sources = [ "main.cc" ];
    libraries = [ mathLibrary ];  # Direct reference!
  };
in { ... }
```

## Key Concepts

### `publicIncludeDirs` vs `includeDirs`

- **`includeDirs`**: Used when compiling the library's own sources
- **`publicIncludeDirs`**: Installed to `$out/include` and propagated to dependents

### The `public` Attribute

Libraries expose a `public` attribute containing:
- `includeDirs` - Include paths for consumers
- `defines` - Preprocessor definitions to propagate
- `compileFlags` - Compiler flags to propagate
- `linkFlags` - Linker flags (includes the library itself)

## Shared Library Variant

To build a shared library instead, use `proj.sharedLib`:

```nix
mySharedLib = proj.sharedLib {
  name = "math-example";
  sources = [ "src/math.cc" ];
  publicIncludeDirs = [ "include" ];
};
```

## Next Steps

- See `app-with-library/` for using libraries in an executable
- See `plugins/` for dlopen-based plugin systems with shared libraries
