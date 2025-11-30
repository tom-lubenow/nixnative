# Rust Native Example

This example demonstrates building Rust code **without Cargo**, using `rustc` directly through nixnative.

## What This Shows

- Multi-file Rust project (library with modules)
- Building Rust libraries (`rlib`) for Rust consumers
- Building Rust executables that depend on libraries
- No Cargo, no `Cargo.toml` - just rustc

## Project Structure

```
rust-native/
├── src/
│   ├── lib.rs        # Library entry point
│   ├── math.rs       # Math module
│   ├── geometry.rs   # Geometry module
│   └── main.rs       # Executable entry point
├── project.nix       # Build definitions
├── checks.nix        # Tests
└── flake.nix         # Standalone flake
```

## Building

```bash
# From this directory
nix build

# Or from repository root
nix build .#rustNativeExample

# Run
./result/bin/rust-native-app
```

## How It Works

1. A toolchain is created with Rust support:
   ```nix
   toolchain = native.mkToolchain {
     languages = {
       c = native.compilers.clang.c;
       cpp = native.compilers.clang.cpp;
       rust = native.compilers.rustc.rust;  # Add Rust!
     };
     linker = native.linkers.default;
     bintools = native.compilers.clang.bintools;
   };
   ```

2. The library is built as an `rlib`:
   ```nix
   mylib = native.mkRustLib {
     inherit toolchain;
     name = "mylib";
     root = ./.;
     entry = "src/lib.rs";
   };
   ```

3. The executable depends on the library:
   ```nix
   app = native.mkRustExecutable {
     inherit toolchain;
     name = "app";
     root = ./.;
     entry = "src/main.rs";
     deps = [ mylib ];  # Link against the library
   };
   ```

## When to Use This

- When you want maximum control over Rust compilation
- When integrating Rust with C/C++ in a unified build
- When Cargo's model doesn't fit your needs
- For learning how rustc works under the hood
