# nixnative

A modular, extensible system for defining minimal, incremental C/C++ build graphs natively in Nix.

## Why nixnative?

Traditional C++ build systems (CMake, Meson, Bazel) sit outside Nix and fight against it—wrapping them loses granularity and reproducibility. nixnative takes a different approach: **the build graph is pure Nix**. Each source file becomes a derivation, dependencies flow through attribute sets, and toolchains are just composable Nix functions.

This gives you:

- **True incrementality.** Change one file, rebuild one derivation. Nix's content-addressed store does the rest.
- **Full toolchain control.** Compilers, linkers, and flags are explicit inputs—no hidden state, no "works on my machine."
- **Composability.** Mix compilers (clang, gcc, zig), linkers (lld, mold, gold), and custom tools in a single project.
- **Extensibility.** Adding a new compiler or code generator is just writing a Nix function.

## Features

- **Modular toolchains.** Compilers and linkers are independent, composable pieces. Use clang with mold, gcc with lld, or define your own combinations.
- **Abstract flags.** Write `{ type = "lto"; value = "thin"; }` once—nixnative translates it to the right CLI flags for each compiler.
- **Automatic dependency scanning.** Omit the manifest and nixnative discovers header dependencies automatically. Or commit a checked-in manifest for CI without IFD.
- **Tool plugins.** Code generators (protobuf, Jinja templates, etc.) integrate cleanly—generated sources, headers, and link flags flow through automatically.
- **Structured libraries.** Static, shared, and header-only libraries propagate their public interface (includes, defines, link flags) to dependents.
- **IDE integration.** Every target exports `compile_commands.json` for clangd/LSP.

## Repository layout

```
.
├── README.md
├── flake.nix     # Top level flake used for internal CI and public API
├── nix/          # core library (compilers, linkers, toolchains, builders)
└── examples/     # Various examples to demonstrate and test functionality
```

## Quick start

### Example flakes

Each directory under `examples/` contains a self-contained flake template. You can copy any of them into a new repository (or run them in place) and simply replace the sources while reusing the nixnative library. For example:

- `examples/executable` – minimal executable that relies on the dependency scanner.
- `examples/library` – static library exposing public headers and a smoke-test that links against it.
- `examples/app-with-library` – executable + internal library + generated sources with a checked-in `.deps.nix` manifest (mirrors `.#simple-strict`/`.#simple-scanned`).
- `examples/rust-integration` – executable that links against a Rust static library built via a minimal `rustc` invocation.
- `examples/rust-integration-crane` – same idea, but the Rust library is built with `crane` for a Cargo-first workflow.
- `examples/multi-toolchain` – demonstrates using different compiler/linker combinations and abstract flags.

To build one of them directly:

```sh
cd examples/executable
nix build
./result/bin/executable-example
```

Back at the root flake the same packages are exposed as `.#executableExample`, `.#mathLibrary`, `.#simple-strict`, etc.

### Build the example

```sh
nix build .#simple-strict           # uses the checked-in .deps.nix
./result/bin/simple-strict
```

You can also exercise the scanner-based flow:

```sh
nix build .#simple-scanned          # auto-scans dependencies via IFD
./result/bin/simple-scanned
```

Run the full test suite (builds both variants and runs smoke tests):

```sh
nix flake check
```

## On naming

This project is called "Nix Native" to emphasize that the build graphs are written in pure nix, as opposed to delegating to another tool.
This is an imperfect naming as it could collide with other interpretations of the word "native", however to that end I would stress that
all are welcome. The initial implementation of this library includes native support for C and C++, however other languages are welcome to
implement native build graph support as well via PR. The north star is simply "minimal, incremental builds implemented natively in nix"
and any compilation toolchain that can satisfy that should be welcome.
