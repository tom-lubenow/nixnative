# Rust interop (crane)

This template mirrors `examples/rust-integration` but relies on
[`crane`](https://github.com/ipetkov/crane) to build the Rust crate. It
showcases a more idiomatic workflow for teams that already manage Rust
dependencies with Cargo.

## Highlights

- Pulls in `nixpkgs` 25.05 and `crane` inside the flake so the example stays
  self-contained.
- Uses `craneLib.buildPackage` to produce a `staticlib` archive from the
  Cargo project.
- Links the resulting archive into a C++ executable via `nixnative`'s
  `libraries` interface—no extra Rust support needed in the core library.

## Usage

```sh
nix build
./result/bin/rust-crane-integration
```

Expected output:

```
rust_crane_dot(2, 5) = 10
rust_crane_norm(3, 4) = 5
```

Feel free to adapt the Cargo project—for example by adding dependencies or
multiple crates—while keeping the C++ integration unchanged.
