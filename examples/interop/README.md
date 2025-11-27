# Zig Interop Example

This example demonstrates linking C++ code with a Zig library, similar to the Rust integration examples.

## What This Demonstrates

- Building Zig libraries for C/C++ consumption
- Wrapping foreign static libraries for nixnative
- C ABI interop between languages

## Project Structure

```
interop/
├── flake.nix    # Build definition with Zig integration
├── lib.zig      # Zig library source
├── header.h     # C header declaring the Zig functions
└── main.cc      # C++ code calling Zig functions
```

## Build and Run

```sh
nix build
./result/bin/interop-example
```

Expected output:
```
Calling Zig from C++: 10 + 32 = 42
```

## How It Works

### 1. Write the Zig Library

```zig
// lib.zig
export fn zig_add(a: i32, b: i32) i32 {
    return a + b;
}
```

The `export` keyword generates C-compatible symbols.

### 2. Build the Zig Static Library

```nix
zigLibDrv = pkgs.runCommand "zig-lib" {
  nativeBuildInputs = [ pkgs.zig ];
} ''
  mkdir -p $out/lib
  export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
  export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
  zig build-lib ${./lib.zig}
  find . -name "*.a" -exec mv {} $out/lib/libmath.a \;
'';
```

### 3. Create a C Header

```c
// header.h
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

int zig_add(int a, int b);

#ifdef __cplusplus
}
#endif
```

### 4. Wrap as a nixnative Library

```nix
zigLib = {
  name = "zig-math";
  staticLibrary = "${zigLibDrv}/lib/libmath.a";
  includeDirs = [ ./. ];
  public = {
    linkFlags = [ "${zigLibDrv}/lib/libmath.a" ];
    cxxFlags = [];
    defines = [];
    includeDirs = [ ./. ];
  };
};
```

### 5. Link with C++ Executable

```nix
native.executable {
  name = "interop-example";
  root = ./.;
  sources = [ "main.cc" ];
  libraries = [ zigLib ];
};
```

## Library Wrapper Pattern

This pattern works for any language that produces static libraries:

```nix
foreignLib = {
  name = "foreign-lib";
  staticLibrary = "${foreignLibDrv}/lib/libforeign.a";
  includeDirs = [ ./include ];  # Where headers live
  public = {
    linkFlags = [ "${foreignLibDrv}/lib/libforeign.a" ];
    cxxFlags = [];
    defines = [];
    includeDirs = [ ./include ];
  };
};
```

Key requirements:
1. The library must use C ABI (C linkage)
2. Provide a C header declaring the functions
3. The `public.linkFlags` must include the library path

## Comparison with Rust Integration

| Aspect | Zig | Rust |
|--------|-----|------|
| C ABI | `export` keyword | `#[no_mangle] extern "C"` |
| Build command | `zig build-lib` | `rustc --crate-type staticlib` |
| No-std | Default | Requires `#![no_std]` |

## Next Steps

- See `rust-integration/` for Rust static library interop
- See `rust-integration-crane/` for Cargo-based Rust builds
- See `library/` for pure C++ static libraries
