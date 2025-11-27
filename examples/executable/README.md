# Executable Example

This is the simplest nixnative example - a minimal executable that demonstrates the high-level API.

**Start here** if you're new to nixnative.

## What This Demonstrates

- Basic `native.executable` usage
- Project structure: `flake.nix`, `project.nix`, `checks.nix`
- Automatic dependency scanning (no manifest needed)
- Multiple source files with headers

## Project Structure

```
executable/
├── flake.nix       # Flake boilerplate
├── project.nix     # Build definition
├── checks.nix      # Test that verifies the build works
├── src/
│   ├── main.cc     # Entry point
│   └── hello.cc    # Implementation
└── include/
    └── hello.hpp   # Header file
```

## Build and Run

```sh
nix build
./result/bin/executable-example
```

Expected output:
```
Hello from nixnative executable example
```

## Key Points

1. **High-level API**: `native.executable` handles toolchain selection automatically
2. **Sources**: List source files relative to `root`
3. **Include directories**: Headers are found via `includeDirs`
4. **Dependency scanning**: nixnative automatically discovers header dependencies

## Next Steps

- See `library/` for building reusable static libraries
- See `multi-toolchain/` for choosing different compilers/linkers
- See `app-with-library/` for a more complete example with libraries and code generation
