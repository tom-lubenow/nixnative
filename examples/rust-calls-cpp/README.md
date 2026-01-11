# Rust Calls C++ Example

This example demonstrates Rust code calling into a C++ library using bindgen for FFI.

## What This Demonstrates

- Building a C++ static library with nixnative
- Using bindgen to generate Rust bindings
- Linking Rust code against C++ libraries
- Cross-language project organization

## Project Structure

```
rust-calls-cpp/
├── flake.nix           # Build definitions
├── Cargo.toml          # Rust project manifest
├── Cargo.lock          # Rust dependencies
├── build.rs            # Rust build script (runs bindgen)
├── src/
│   └── main.rs         # Rust application
└── cpp-lib/
    ├── include/
    │   └── mathlib.h   # C++ header (exposed to Rust)
    └── src/
        └── mathlib.cpp # C++ implementation
```

## Build and Run

```sh
# Build the Rust application
nix build

# Run the example
./result/bin/rust-calls-cpp

# Run tests
nix flake check
```

Expected output:
```
cpp_add(5, 3) = 8
cpp_multiply(4, 7) = 28
cpp_fibonacci(20) = 6765
```

## How It Works

### 1. Build the C++ Library

```nix
proj = native.project { root = ./cpp-lib; };

cppLib = proj.staticLib {
  name = "mathlib";
  sources = [ "src/mathlib.cpp" ];
  includeDirs = [ "include" ];
  publicIncludeDirs = [ "include" ];
};
```

### 2. Configure Rust Build

The C++ library paths are passed to Rust via environment variables:

```nix
rustApp = pkgs.rustPlatform.buildRustPackage {
  pname = "rust-calls-cpp";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.rustPlatform.bindgenHook ];

  # Tell build.rs where to find the C++ library
  CPP_LIB_PATH = cppLib.archivePath |> builtins.dirOf;
  CPP_INCLUDE_PATH = ./cpp-lib/include;
};
```

### 3. Generate Bindings (build.rs)

The Rust build script uses bindgen to generate bindings:

```rust
fn main() {
    let lib_path = env::var("CPP_LIB_PATH").unwrap();
    println!("cargo:rustc-link-search=native={}", lib_path);
    println!("cargo:rustc-link-lib=static=mathlib");

    let bindings = bindgen::Builder::default()
        .header("cpp-lib/include/mathlib.h")
        .generate()
        .unwrap();

    bindings.write_to_file(out_path.join("bindings.rs")).unwrap();
}
```

### 4. Use in Rust

```rust
include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

fn main() {
    unsafe {
        println!("cpp_add(5, 3) = {}", cpp_add(5, 3));
    }
}
```

## Key Concepts

### C++ Header for FFI

Use `extern "C"` to prevent name mangling:

```cpp
#ifdef __cplusplus
extern "C" {
#endif

int cpp_add(int a, int b);
int cpp_multiply(int a, int b);
long cpp_fibonacci(int n);

#ifdef __cplusplus
}
#endif
```

### bindgenHook

`pkgs.rustPlatform.bindgenHook` configures environment variables that bindgen needs to find system headers.

## Related Examples

- See `cpp-calls-rust/` for the reverse direction (C++ calling Rust)
- See `c-and-cpp/` for mixed C/C++ projects
- See `library/` for standalone C++ library examples
