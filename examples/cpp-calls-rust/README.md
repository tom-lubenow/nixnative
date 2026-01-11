# C++ Calls Rust Example

This example demonstrates C++ code calling into a Rust static library using FFI.

## What This Demonstrates

- Building a Rust static library with `crate-type = ["staticlib"]`
- Creating a C header for Rust functions
- Linking C++ code against Rust libraries
- Manual library interface wrapping for nixnative

## Project Structure

```
cpp-calls-rust/
├── flake.nix           # Build definitions
├── include/
│   └── rust_math.h     # C header for Rust functions
├── src/
│   └── main.cpp        # C++ application
└── rust-lib/
    ├── Cargo.toml      # Rust library manifest
    ├── Cargo.lock      # Rust dependencies
    └── src/
        └── lib.rs      # Rust library implementation
```

## Build and Run

```sh
# Build the C++ application
nix build

# Run the example
./result/bin/cpp-calls-rust

# Run tests
nix flake check
```

Expected output:
```
rust_add(3, 4) = 7
rust_multiply(5, 6) = 30
rust_factorial(10) = 3628800
```

## How It Works

### 1. Build the Rust Library

```nix
rustLib = pkgs.rustPlatform.buildRustPackage {
  pname = "rust_math";
  version = "0.1.0";
  src = ./rust-lib;
  cargoLock.lockFile = ./rust-lib/Cargo.lock;
  buildType = "release";
};
```

### 2. Create Library Interface

Wrap the Rust library as a nixnative-compatible library:

```nix
rustMathLib = {
  public = {
    includeDirs = [ { path = ./include; } ];
    defines = [ ];
    compileFlags = [ ];
    linkFlags = [
      "${rustLib}/lib/librust_math.a"
      "-lpthread"
      "-ldl"
      "-lm"
    ];
  };
};
```

### 3. Build C++ Application

```nix
proj = native.project { root = ./.; };

app = proj.executable {
  name = "cpp-calls-rust";
  sources = [ "src/main.cpp" ];
  libraries = [ rustMathLib ];  # Direct reference!
};
```

## Rust Side

### Cargo.toml

```toml
[lib]
crate-type = ["staticlib"]
```

### lib.rs

Use `#[no_mangle]` and `extern "C"` for FFI:

```rust
#[no_mangle]
pub extern "C" fn rust_add(a: i32, b: i32) -> i32 {
    a + b
}

#[no_mangle]
pub extern "C" fn rust_multiply(a: i32, b: i32) -> i32 {
    a * b
}
```

## C++ Side

### rust_math.h

```cpp
#pragma once

extern "C" {
    int rust_add(int a, int b);
    int rust_multiply(int a, int b);
    long rust_factorial(int n);
}
```

### main.cpp

```cpp
#include <iostream>
#include "rust_math.h"

int main() {
    std::cout << "rust_add(3, 4) = " << rust_add(3, 4) << std::endl;
    return 0;
}
```

## Key Concepts

### Rust Static Library Dependencies

Rust static libraries often need additional system libraries:

```nix
linkFlags = [
  "${rustLib}/lib/librust_math.a"
  "-lpthread"  # Threading
  "-ldl"       # Dynamic loading
  "-lm"        # Math library
];
```

### Manual Library Wrapper

When integrating external build systems (Cargo, CMake, etc.), create a library interface manually with the `public` attribute:

```nix
externalLib = {
  public = {
    includeDirs = [ ... ];
    linkFlags = [ ... ];
  };
};
```

## Related Examples

- See `rust-calls-cpp/` for the reverse direction (Rust calling C++)
- See `c-and-cpp/` for mixed C/C++ projects
- See `library/` for standalone C++ library examples
