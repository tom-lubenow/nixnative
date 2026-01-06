# Library Chain Example

This example demonstrates multi-library dependencies with transitive dependency handling.

## What This Demonstrates

- Building multiple interdependent static libraries
- Transitive dependency propagation
- Clean separation of concerns across library layers
- How `public` interfaces flow through dependency chains

## Dependency Structure

```
                    ┌─────────────┐
                    │     app     │
                    └──────┬──────┘
                           │ depends on
                    ┌──────▼──────┐
                    │   libmath   │  (polygon math)
                    └──────┬──────┘
                           │ depends on
                    ┌──────▼──────┐
                    │   libcore   │  (Point, Rect types)
                    └──────┬──────┘
                           │ depends on
                    ┌──────▼──────┐
                    │   libutil   │  (formatNumber, clamp)
                    └─────────────┘
```

## Project Structure

```
library-chain/
├── flake.nix
├── main.cc                      # Application
├── libutil/
│   ├── include/util.hpp         # Utility functions
│   └── util.cc
├── libcore/
│   ├── include/core.hpp         # Point, Rect types
│   └── core.cc
└── libmath/
    ├── include/math_ext.hpp     # Polygon operations
    └── math_ext.cc
```

## Build and Run

```sh
nix build
./result/bin/library-chain-demo
```

Expected output:
```
Library Chain Demo
==================

Triangle vertices:
  P0 = (0.00, 0.00)
  P1 = (4.00, 0.00)
  P2 = (2.00, 3.00)

Computed properties:
  Centroid: (2.00, 1.00)
  Bounding box: Rect((0.00, 0.00), 4.00x3.00)
  Perimeter: 11.21
  Area: 6.00

Distance from P0 to P1: 4.00

Library chain working correctly!
```

## How It Works

### Building Each Layer

```nix
targets.libUtil = {
  type = "staticLib";
  name = "libutil";
  sources = [ "libutil/util.cc" ];
  publicIncludeDirs = [ "libutil/include" ];
};

targets.libCore = {
  type = "staticLib";
  name = "libcore";
  sources = [ "libcore/core.cc" ];
  publicIncludeDirs = [ "libcore/include" ];
  libraries = [ { target = "libUtil"; } ];
};

targets.libMath = {
  type = "staticLib";
  name = "libmath_ext";
  sources = [ "libmath/math_ext.cc" ];
  publicIncludeDirs = [ "libmath/include" ];
  libraries = [ { target = "libCore"; } ];
};
```

### Transitive Dependencies

When you declare `libraries = [ { target = "libCore"; } ]`:
- libcore's `publicIncludeDirs` are added to your include paths
- libcore's `publicDefines` are added to your defines
- libcore's link flags (including transitive ones) are collected

This means libmath can `#include "util.hpp"` even though it only
directly depends on libcore, because libcore propagates libutil's
public interface.

### The `public` Attribute

Each library exposes a `public` attribute:

```nix
{
  includeDirs = [ { path = "/nix/store/..."; } ];
  defines = [ "SOME_DEFINE" ];
  compileFlags = [ ];
  linkFlags = [ "/nix/store/.../libutil.a" ];
}
```

When a library depends on another:
1. The dependent's `public.includeDirs` are added to include paths
2. The dependent's `public.linkFlags` are collected for linking
3. This happens recursively for transitive dependencies

## Key Concepts

### Direct vs Transitive Dependencies

- **Direct**: Libraries you `#include` in your code
- **Transitive**: Libraries your dependencies need

You only need to list direct dependencies in `libraries`. Transitive
dependencies are handled automatically.

### Public vs Private Interface

- **publicIncludeDirs**: Headers consumers can include
- **includeDirs**: Headers for compiling this library (internal use)

For most libraries, these are the same. But you might have internal
headers that shouldn't be exposed.

## Building Individual Libraries

```sh
nix build .#libutil   # Just the utility library
nix build .#libcore   # Core + its dependencies
nix build .#libmath   # Math + all transitive dependencies
```

## Next Steps

- See `library/` for a simpler single-library example
- See `header-only/` for libraries without compiled code
- See `app-with-library/` for combining with code generation
