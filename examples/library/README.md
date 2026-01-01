# Library Example

This example demonstrates building a reusable static library with nixnative.

## What This Demonstrates

- Building static libraries with `native.staticLib`
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
mathLibrary = native.staticLib {
  name = "math-example";
  root = ./.;
  sources = [ "src/math.cc" ];
  includeDirs = [ "include" ];        # For compiling the library itself
  publicIncludeDirs = includeDirs;    # Exposed to consumers
};
```

### Consuming the Library

The `checks.nix` file demonstrates consuming the library:

```nix
# Access the library's public interface
includeFlags = lib.concatMapStringsSep " " (dir: "-I${dir.path}") mathLibrary.public.includeDirs;
linkFlags = lib.concatStringsSep " " mathLibrary.public.linkFlags;

# Compile and link
${toolchain.getCXX} ${includeFlags} main.cc ${linkFlags} -o test
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

To build a shared library instead, use `native.sharedLib`:

```nix
mySharedLib = native.sharedLib {
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
