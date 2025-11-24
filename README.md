# nixclang

Incremental, deterministic C/C++ builds driven directly by Nix. This repository experiments with the "one derivation per translation unit" approach using clang as the only supported toolchain.

## Highlights

- **Per translation unit derivations.** Each `.cc` file becomes its own derivation that compiles to an object file. Touching a source or header only rebuilds the affected units.
- **Hermetic clang toolchain.** We vendor LLVM 18 from `nixpkgs` so compilation flags and target triple are part of the cache key.
- **Dependency scanner (automatic).** When you omit a manifest nixclang spins up a dedicated `clang++ -MMD` scanner derivation to discover header/module dependencies. Use it directly (IFD) or materialize the result into `.clang-deps.nix` for strict CI.
- **`compile_commands.json` passthrough.** Every build target exposes a generated compilation database for editor tooling.
- **Structured libraries.** `mkStaticLib`, `mkSharedLib`, and `mkHeaderOnly` propagate link flags and public include directories so downstream targets can consume your outputs without manual `-L/-l` churn.
- **Generator pipeline.** Attach derivations (for example the Jinja renderer shown in `examples/app-with-library/`) that emit headers/sources (plus manifests) to executables or libraries; include paths, defines, and link flags flow through automatically.
- **Pluggable toolchains.** Pass `toolchain = myClang;` into any builder to swap in a different clang/LLVM bundle while keeping the per-TU graph intact.
- **Python extensions.** `mkPythonExtension` compiles CPython modules to the right site-packages layout with zero distutils glue, so you can `import` them straight from the Nix store.

## Repository layout

```
.
├── README.md
├── flake.nix
├── nix/
│   └── cpp/default.nix        # core library (`mkExecutable`, scanners, toolchain)
├── examples/
│   ├── app-with-library/      # executable + static lib + generated sources
│   ├── executable/            # minimal executable target
│   ├── library/               # reusable static library
│   └── python-extension/      # CPython module built with mkPythonExtension
└── docs/
    └── ...                    # architectural notes (to be expanded)
```

## Quick start

### Example flakes

Each directory under `examples/` contains a self-contained flake template. You can copy any of them into a new repository (or run them in place) and simply replace the sources/generators while reusing the nixclang library. For example:

- `examples/executable` – minimal executable that relies on the dependency scanner.
- `examples/library` – static library exposing public headers and a smoke-test that links against it.
- `examples/app-with-library` – executable + internal library + generated sources with a checked-in `.clang-deps.nix` manifest (mirrors `.#simple-strict`/`.#simple-scanned`).
- `examples/python-extension` – CPython extension module built via `mkPythonExtension`.
- `examples/rust-integration` – executable that links against a Rust static library built via a minimal `rustc` invocation.
- `examples/rust-integration-crane` – same idea, but the Rust library is built with `crane` for a Cargo-first workflow using nixpkgs 25.05.

To build one of them directly:

```sh
cd examples/executable
nix build
./result/bin/executable-example
```

Back at the root flake the same packages are exposed as `.#executableExample`, `.#mathLibrary`, `.#simple-strict`, `.#pythonExtension`, etc.

### Build the example

```sh
nix build .#simple-strict           # uses the checked-in .clang-deps.nix
./result/bin/simple-strict
```

You can also exercise the scanner-based flow:

```sh
nix build .#simple-scanned          # runs clang's -MMD scanner via IFD
./result/bin/simple-scanned
```

Run the full test suite (builds both variants and runs smoke tests):

```sh
nix flake check
```

### Build the Python extension example

```sh
# build the CPython module
nix build .#pythonExtension

# import it with the right PYTHONPATH
storePath=$(nix build .#pythonExtension --no-link --print-out-paths)
STORE_PATH=$storePath python - <<'PY'
import os, pathlib, sys, sysconfig
store = pathlib.Path(os.environ['STORE_PATH'])
site_packages = store / sysconfig.get_paths()['platlib']
sys.path.insert(0, str(site_packages))
import hello_ext
print(hello_ext.greet('Nix'))
PY
```

### Use the library in another flake

```nix
# flake.nix snippet
{
  outputs = { self, nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    cpp = import ./nix/cpp { inherit pkgs; };
  in {
    packages.x86_64-linux = let
      math = cpp.mkStaticLib {
        name = "math";
        root = ./.
        sources = [ "src/math.cc" ];
        includeDirs = [ "include" ];
      };

      buildInfo = import ./nix/build-info-generator.nix {
        inherit pkgs;
        mode = "strict";
      }; # returns { manifest, headers, sources, includeDirs, public, evalInputs }

      zlib = cpp.pkgConfig.makeLibrary {
        name = "zlib";
        packages = [ pkgs.zlib ];
        modules = [ "zlib" ];
      };
    in {
      my-app = cpp.mkExecutable {
        name = "my-app";
        root = ./.
        sources = [ "src/main.cc" ];
        includeDirs = [ "include" ];
        libraries = [ math zlib ];
        generators = [ buildInfo ];
        cxxFlags = [ "-O2" ];
        # toolchain = myCustomClang; # optional override
      };
    };
  };
}
```

`nix/build-info-generator.nix` should return an attrset matching the generator shape (`manifest`, `headers`, `sources`, `includeDirs`, `public`, `evalInputs`). See `examples/app-with-library/project.nix` for a full Jinja-based implementation.


### Dev shell

```sh
nix develop
clang++ --version
ls -l compile_commands.json
```

`nix develop` now uses `cpp.mkDevShell`, which:

- Drops you into a shell with the toolchain associated with the default app (`examples.defaults.app`).
- Automatically symlinks `compile_commands.json` to the selected target’s database so `clangd` works out of the box.
- Lets you target a different derivation by calling `cpp.mkDevShell { target = …; }` in your own flake (add `extraPackages` for editors, etc.).

### Sync dependency manifests

Need to refresh a checked-in `.clang-deps.nix` after a scanner run? Use the helper app:

```sh
system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
nix run .#cpp-sync-manifest -- .#checks.${system}.simpleScanManifest examples/app-with-library/.clang-deps.nix
```

Pass any additional `nix build` flags after the destination path (for example `--refresh`).

## Dependency manifests

You can operate in three complementary modes:

1. **Strict mode (`depsManifest`).** Commit a `.clang-deps.nix` file that mirrors the scanner output. CI avoids IFD while still reusing the per-TU cache. Regenerate with `nix run .#cpp-sync-manifest`.
2. **Scanner mode (`scanner`).** Omit `depsManifest` (the default) and nixclang will automatically run `mkDependencyScanner` and import the produced manifest via IFD so developers never have to touch the manifest manually. You can still pass your own scanner derivation if you want to reuse the same scan across multiple targets or tweak the invocation.
3. **Hybrid workflow.** Run the scanner locally, commit the materialized `.clang-deps.nix`, and let developers opt into IFD by pointing their build at the scanner instead of the checked-in file.

Manifests share a simple schema:

```nix
{
  schema = 1;
  units = {
    "src/main.cc" = {
      dependencies = [
        "src/main.cc"
        "include/foo.hpp"
      ];
    };
  };
}
```

## Current limitations

- Only clang/LLVM 18 is supported. GCC, MSVC, or cross toolchains would require extending `toolchains`.
- Dependency scanning runs `clang++ -MMD`; custom generators or exotic include search paths may need additional hooks.
- System libraries: pkg-config is supported via `cpp.pkgConfig.makeLibrary`, but Apple frameworks and non-pkg-config discovery still need manual flags (`-framework Foo`, `-L/path`, etc.).
- We operate on discrete files. Widely used headers still fan out rebuilds; address this by refactoring headers, introducing modules, or grouping TUs.

## Next steps

- Expand the generator toolkit (the Jinja helper is a start; protoc/FlatBuffers adapters would round things out).
- Emit richer `compile_commands.json` metadata (e.g. per-file `-working-directory`).
- Ship a `watch` CLI that keeps evaluation warm for sub-second rebuilds during development.

Contributions and feedback welcome—open issues or PRs as you experiment.
