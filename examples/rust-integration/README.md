# Rust interop example

This template demonstrates how to link a C++ executable built with
`nixnative` against a Rust static library without requiring any Rust-specific
support in the core library.

## What it does

- Compiles a tiny `no_std` Rust crate to `libnixnative_rust.a` using `rustc`.
- Exposes the Rust functions via a C ABI and declares them in a C++ header.
- Links the C++ translation unit against the static archive via the standard
  `libraries` mechanism.

## Usage

```sh
nix build
./result/bin/rust-integration
```

Expected output:

```
rust_add(21, 21) = 42
rust_scale(7, 3) = 21
```

The example’s flake stays self-contained: all Rust tooling is pulled in
through the example itself, so your project can adopt a different workflow
if desired.
