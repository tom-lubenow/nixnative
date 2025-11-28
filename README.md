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

### Use the library in another flake

```nix
# flake.nix snippet
{
  outputs = { self, nixpkgs, nixnative }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    native = nixnative.lib.native { inherit pkgs; };
  in {
    packages.x86_64-linux = let
      math = native.staticLib {
        name = "math";
        root = ./.;
        sources = [ "src/math.cc" ];
        includeDirs = [ "include" ];
      };

      zlib = native.pkgConfig.makeLibrary {
        name = "zlib";
        packages = [ pkgs.zlib ];
        modules = [ "zlib" ];
      };
    in {
      my-app = native.executable {
        name = "my-app";
        root = ./.;
        sources = [ "src/main.cc" ];
        includeDirs = [ "include" ];
        libraries = [ math zlib ];
        # High-level API: specify compiler/linker by name
        compiler = "clang";  # or "gcc", "zig"
        linker = "lld";      # or "mold", "gold", "ld64"
      };

      # Or use abstract flags
      optimized = native.executable {
        name = "my-app-optimized";
        root = ./.;
        sources = [ "src/main.cc" ];
        flags = [
          { type = "lto"; value = "thin"; }
          { type = "optimize"; value = "3"; }
        ];
      };
    };
  };
}
```

See `examples/app-with-library/project.nix` for a full example with code generation.


### Dev shell

```sh
nix develop
clang++ --version
ls -l compile_commands.json
```

`nix develop` now uses `native.devShell`, which:

- Drops you into a shell with the toolchain associated with the default app.
- Automatically symlinks `compile_commands.json` to the selected target's database so `clangd` works out of the box.
- Lets you target a different derivation by calling `native.devShell { target = …; }` in your own flake (add `extraPackages` for editors, etc.).

### Sync dependency manifests

Need to refresh a checked-in `.deps.nix` after a scanner run? Use the helper app:

```sh
system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
nix run .#sync-manifest -- .#checks.${system}.simpleScanManifest examples/app-with-library/.deps.nix
```

Pass any additional `nix build` flags after the destination path (for example `--refresh`).

## Dependency manifests

You can operate in three complementary modes:

1. **Strict mode (`depsManifest`).** Commit a `.deps.nix` file that mirrors the scanner output. CI avoids IFD while still reusing the per-TU cache. Regenerate with `nix run .#sync-manifest`.
2. **Scanner mode (`scanner`).** Omit `depsManifest` (the default) and nixnative will automatically run `mkDependencyScanner` and import the produced manifest via IFD so developers never have to touch the manifest manually. You can still pass your own scanner derivation if you want to reuse the same scan across multiple targets or tweak the invocation.
3. **Hybrid workflow.** Run the scanner locally, commit the materialized `.deps.nix`, and let developers opt into IFD by pointing their build at the scanner instead of the checked-in file.

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

## Troubleshooting

### Build is slow / rebuilding too much

**Symptom:** Changing one file triggers many recompilations.

**Causes and solutions:**
1. **Widely-included headers**: If a header is included by many sources, changing it rebuilds all of them. Consider:
   - Splitting large headers into smaller, focused ones
   - Using forward declarations where possible
   - Moving implementation details to `.cc` files

2. **Missing or stale manifest**: If using strict mode, ensure your `.deps.nix` is up to date:
   ```sh
   nix run .#sync-manifest -- .#checks.${system}.yourScanManifest path/to/.deps.nix
   ```

3. **Too many translation units**: Each source file becomes a separate derivation. For very large codebases (100+ files), consider grouping related sources.

### clangd / LSP not working

**Symptom:** Editor shows errors or can't find headers.

**Solutions:**
1. Ensure `compile_commands.json` is symlinked in your project root:
   ```sh
   nix develop  # Auto-symlinks compile_commands.json
   ls -la compile_commands.json
   ```

2. If the symlink is stale or missing, rebuild:
   ```sh
   nix build .#yourTarget
   ln -sf $(nix build .#yourTarget --no-link --print-out-paths)/compile_commands.json .
   ```

3. Restart your LSP server after updating the compilation database.

### Scanner fails with "source not found"

**Symptom:** Error like `nixnative: source 'src/foo.cc' not found at /nix/store/.../src/foo.cc`

**Solutions:**
1. Check that the file exists at the specified path relative to `root`
2. Ensure `root` points to the correct directory
3. If using generators, verify the generator's `sources` entries have correct `rel` and `path` attributes

### Generator errors

**Symptom:** Error mentioning generator headers/sources/public attributes.

**Solutions:**
1. Check that all `headers` entries have both `rel` and `path`/`store` attributes
2. Check that all `sources` entries have both `rel` and `path`/`store` attributes
3. If providing `public`, ensure all fields are lists (not strings):
   ```nix
   # Wrong:
   public = { linkFlags = "-lfoo"; };
   # Right:
   public = { linkFlags = [ "-lfoo" ]; includeDirs = []; defines = []; cxxFlags = []; };
   ```

### LTO / sanitizer issues

**Symptom:** Build fails with LTO or sanitizer flags.

**Solutions:**
1. LTO requires all objects to be compiled with the same LTO mode
2. Sanitizers may require runtime libraries; ensure they're available
3. Some sanitizers are mutually exclusive (e.g., AddressSanitizer and MemorySanitizer)

### macOS-specific issues

**Symptom:** Build fails on macOS with SDK or framework errors.

**Solutions:**
1. Ensure `apple-sdk` is available in your nixpkgs
2. For framework issues, use `native.pkgConfig.mkFrameworkLibrary`:
   ```nix
   CoreFoundation = native.pkgConfig.mkFrameworkLibrary { name = "CoreFoundation"; };
   ```
3. Check that `SDKROOT` and `MACOSX_DEPLOYMENT_TARGET` are set (automatic in dev shells)

## Current limitations

- Dependency scanning uses the compiler's `-MMD` flag; custom generators or exotic include search paths may need additional hooks.
- System libraries: pkg-config is supported via `native.pkgConfig.makeLibrary`; Apple frameworks can be added with `native.pkgConfig.mkFrameworkLibrary`, but other non-pkg-config discovery still needs manual flags (`-L/path`, etc.).
- We operate on discrete files. Widely used headers still fan out rebuilds; address this by refactoring headers, introducing modules, or grouping TUs.
- C++20 modules are not yet supported (scanner uses traditional `-MMD` dependency discovery).
- Precompiled headers (PCH) are not supported.
- Cross-compilation is experimental (Zig cross targets available but not fully tested).

## Next steps

- Expand the generator toolkit (the Jinja helper is a start; protoc/FlatBuffers adapters would round things out).
- Emit richer `compile_commands.json` metadata (e.g. per-file `-working-directory`).
- Ship a `watch` CLI that keeps evaluation warm for sub-second rebuilds during development.

Contributions and feedback welcome—open issues or PRs as you experiment.
