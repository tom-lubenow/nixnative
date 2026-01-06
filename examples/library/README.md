# Library Example

This example demonstrates building a reusable static library with nixnative.

## What This Demonstrates

- Building static libraries with module targets
- Exposing public headers via `publicIncludeDirs`
- Consuming the library from another build (in `checks.nix`)

## Project Structure

```
library/
├── flake.nix       # Flake boilerplate
├── project.nix     # Library definition
├── checks.nix      # Test that consumes the library
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
native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets.mathLibrary = {
          type = "staticLib";
          name = "libmath-example";
          sources = [ "src/math.cc" ];
          includeDirs = [ "include" ];
          publicIncludeDirs = [ "include" ];
        };

        targets.mathLibraryTest = {
          type = "executable";
          name = "math-library-test";
          root = ./test;
          sources = [ "main.cc" ];
          libraries = [ { target = "mathLibrary"; } ];
        };
      };
    }
  ];
}
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

To build a shared library instead, use `type = "sharedLib"`:

```nix
targets.mySharedLib = {
  type = "sharedLib";
  name = "math-example";
  root = ./.;
  sources = [ "src/math.cc" ];
  publicIncludeDirs = [ "include" ];
};
```

See `examples/install/` for a side-by-side comparison.

## Next Steps

- See `app-with-library/` for using libraries in an executable
- See `install/` for static vs shared library comparison
- See `plugins/` for dlopen-based plugin systems with shared libraries
