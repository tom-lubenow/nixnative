# Header-Only Library Example

This example demonstrates creating and consuming header-only libraries using module targets.

## What This Demonstrates

- Creating header-only libraries (no compiled sources)
- Using `publicIncludeDirs` to expose headers
- Consuming header-only libraries in executables
- Template-based C++ libraries

## Project Structure

```
header-only/
├── flake.nix           # Build definitions
├── include/
│   └── vec3.hpp        # Header-only library (3D vector math)
└── main.cc             # Demo that uses the library
```

## Build and Run

```sh
nix build
./result/bin/header-only-demo
```

Expected output:
```
a = (1, 2, 3)
b = (4, 5, 6)
a + b = (5, 7, 9)
a . b = 32
a x b = (-3, 6, -3)
|a| = 3.74166
```

## How It Works

### Creating a Header-Only Library

```nix
targets.vec3Lib = {
  type = "headerOnly";
  name = "vec3";
  publicIncludeDirs = [ "include" ];
};
```

This creates a library with:
- No compiled code (no `.a` or `.so` file)
- Include directories propagated to consumers
- A `public` attribute for the dependency system

### Consuming the Library

```nix
targets.demo = {
  type = "executable";
  name = "demo";
  sources = [ "main.cc" ];
  libraries = [ { target = "vec3Lib"; } ];
};
```

The consumer automatically gets:
- `-I` flags for the library's include directories
- Any `publicDefines` as `-D` flags

## Key Concepts

### When to Use Header-Only Libraries

Header-only libraries are ideal for:
- Template-heavy code (like `vec3.hpp`)
- Small utility libraries
- Interface definitions (abstract base classes)
- Compile-time utilities (constexpr functions, type traits)

### `publicIncludeDirs` vs `includeDirs`

For header-only libraries:
- `publicIncludeDirs` (or just `includeDirs`) specifies what consumers see
- There's no distinction since there's no compilation step

### Propagating Configuration

```nix
targets.myLib = {
  type = "headerOnly";
  name = "my-lib";
  publicIncludeDirs = [ "include" ];
  publicDefines = [ "MY_LIB_ENABLED" ];
  publicCompileFlags = [ "-ffast-math" ];
};
```

## Comparison with Static Libraries

| Aspect | Header-Only | Static Library |
|--------|-------------|----------------|
| Compilation | None | Sources compiled to `.o` files |
| Output | No artifacts | `.a` archive |
| Build time | Fast (no compilation) | Slower (compilation step) |
| Binary size | Code inlined in each consumer | Single copy in archive |
| Use case | Templates, small utilities | Larger implementations |

## Next Steps

- See `library/` for static libraries with compiled code
- See `plugins/` for shared libraries
- See `app-with-library/` for combining multiple library types
