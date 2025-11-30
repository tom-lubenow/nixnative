# Mixed C/C++/Rust Example

This example demonstrates **linking C, C++, and Rust code together** in a single application, all built with nixnative.

## What This Shows

- Rust library with C-compatible FFI (`#[no_mangle]`, `extern "C"`)
- Rust compiled to `staticlib` for linking with C/C++
- C code calling Rust functions
- C++ code calling both C and Rust functions
- All three languages linked into a single executable

## Project Structure

```
mixed-c-cpp-rust/
├── include/
│   ├── rustlib.h      # C header for Rust FFI
│   └── cwrapper.h     # C wrapper header
├── src/
│   ├── rustlib.rs     # Rust library with C FFI
│   ├── cwrapper.c     # C wrapper using Rust
│   └── main.cc        # C++ main program
├── project.nix        # Build definitions
├── checks.nix         # Tests
└── flake.nix          # Standalone flake
```

## Building

```bash
# From this directory
nix build

# Or from repository root
nix build .#mixedCCppRustExample

# Run
./result/bin/mixed-app
```

## How It Works

1. **Rust library** is compiled as a `staticlib`:
   ```nix
   rustLib = native.mkRustStaticLib {
     inherit toolchain;
     name = "rustlib";
     entry = "src/rustlib.rs";
   };
   ```

2. **C wrapper** links against Rust:
   ```nix
   cLib = native.mkStaticLib {
     inherit toolchain;
     sources = [ "src/cwrapper.c" ];
     includeDirs = [ "include" ];
   };
   ```

3. **C++ app** links everything together:
   ```nix
   app = native.mkExecutable {
     inherit toolchain;
     sources = [ "src/main.cc" ];
     libraries = [ cLib ];
     ldflags = [ rustLib.libraryPath ];
   };
   ```

## FFI Conventions

The Rust library uses standard FFI conventions:

```rust
#[no_mangle]
pub extern "C" fn rust_add(a: c_int, b: c_int) -> c_int {
    a + b
}
```

With corresponding C header:

```c
int rust_add(int a, int b);
```

## When to Use This Pattern

- When you want Rust's safety guarantees for performance-critical code
- When you have existing C/C++ code and want to add Rust
- When different parts of your codebase are best suited to different languages
- For gradual migration from C/C++ to Rust
