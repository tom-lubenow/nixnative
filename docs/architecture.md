# Architecture Notes

This implementation mirrors the plan outlined in the original discussion:

## Build graph generation

1. **Translation unit normalization**
   - Inputs: `root`, list of relative source paths.
   - Each source emits an attrset `{ relNorm, store, objectName }` where `store` is a content-addressed path for the file.

2. **Dependency capture**
   - `mkDependencyScanner`: materialises a temporary tree, runs `clang++ -MMD`, and collapses the `.d` files into JSON.
   - `depsManifest`: read-only JSON variant for strict builds. The format is stable and versioned (`schema = 1`).

3. **Source projection**
   - For each TU we create a `linkFarm` containing:
     - The TU source file.
     - Every declared dependency (headers, generated files).
   - This keeps the build input surface minimal while preserving directory layout for `-I` lookup.

4. **Compilation derivations**
   - Each TU compiles inside its own derivation via `clang++ -c` with:
     - Toolchain default flags (`-std=c++20`, warnings, colour output).
     - User-specified `cxxFlags`, `defines`, and `includeDirs` (resolved relative to the TU farm).
   - Objects are exported as `$out/<tu-name>.o` and captured in `passthru.objectInfos` for downstream tooling.

5. **Link step**
   - A thin wrapper around `clang++` that links all object derivations with additional `ldflags`/`libraries`.
   - Library helpers (`mkStaticLib`, `mkSharedLib`, `mkHeaderOnly`) expose `public` metadata (include dirs, defines, link flags) so executables and dependent libraries consume them without manual flag wiring.

## Tooling outputs

- `compile_commands.json` is generated directly from the normalized TU metadata so editors can plug into clangd without extra configuration.
- `mkDevShell` consumes any build target (library/executable/etc.) and spawns a shell with the matching toolchain, linking the target’s `compile_commands.json` automatically so `clangd` sees the right flags.
- Each build target exposes:
  - `passthru.objectInfos`: introspection (headers, include flags, TU source roots).
  - `passthru.manifest`: the manifest JSON used for the build (helpful when comparing scanner output vs. checked-in data).
  - `passthru.public`: propagated compile/link knobs inherited by downstream dependants.
  - `passthru.generators`: the generator attrsets that fed generated headers/sources into the build.
- The flake also publishes `nix run .#cpp-sync-manifest`, which copies a manifest derivation back into the workspace for strict mode updates.

## IFD considerations

- Scanner mode performs Import From Derivation, so Hydra-style CI clusters may need to permit IFD. The strict mode (`depsManifest`) avoids IFD entirely by reading the checked-in JSON.
- The JSON output is deterministic and stable, which makes it straightforward to check in or diff.

## Extensibility hooks

Future features can slot into the same shape:

- **Code generators** plug in via the `generators` array. Supply attrsets with `manifest`, `headers`, `sources`, etc.; the simple example demonstrates a Jinja-based renderer, but any derivation that produces files can participate.
- **CPython extensions** compile through `mkPythonExtension`, which wraps the shared-library path and site-packages layout so the resulting `.so` can be imported without setuptools.
- **Toolchains** are pluggable. All builders accept an optional `toolchain` attribute, so you can swap in a custom clang/LLVM package while keeping the per-TU graph intact.
- **ThinLTO / PGO**: treat IR bitcode as another per-TU artefact, followed by a final optimization derivation.
- **Batching**: group translation units by coarse granularity if derivation counts become excessive—`linkFarm` already supports merging multiple files per derivation.

## Incremental builds

A core design goal is true per-file incremental compilation: changing one source file should only rebuild that file's object derivation plus downstream link steps.

### Content-addressed source capture

Each source file is captured individually using `builtins.path`, making it content-addressed:

```nix
# Each source file is independently content-addressed
store = builtins.path { path = "${rootHost}/${relNorm}"; };
```

This means:
- Changing `src/foo.cc` only invalidates `foo.o`, not `bar.o`
- The link step depends on object files, so it rebuilds when any object changes
- Unchanged objects are fetched from the Nix store cache

### Tool plugin file capture

**Critical anti-pattern**: Using `builtins.path { path = root; }` captures the _entire_ directory. Any file change invalidates all derivations that depend on it, defeating incremental builds.

The `mkTool` infrastructure automatically captures only the specified input files:

```nix
# Inside mkTool.run:
capturedRoot = utils.captureFiles {
  inherit root;
  files = normalizedFiles;  # Only the inputFiles, not everything
  name = "${name}-inputs";
};
```

For custom tools that don't use `mkTool`, use `utils.captureFiles` or explicit `builtins.path` on individual files:

```nix
# Good: capture only needed files
templateFiles = utils.captureFiles {
  root = ./.;
  files = [ "templates/a.j2" "templates/b.j2" ];
};

# Also good: capture individual file
singleFile = builtins.path { path = ./config.json; };

# BAD: captures entire directory
rootStore = builtins.path { path = root; };  # Don't do this!
```

### Dependency manifest role

The dependency manifest (`depsManifest`) declares which headers each source file depends on. This allows the build system to create minimal source trees for each translation unit:

```nix
# Each TU gets only its declared dependencies
srcTree = mkSourceTree { inherit tu headers; };
```

Changes to headers not in the manifest don't invalidate the TU's compilation.

## Known gaps

- Windows/MSVC backend is out-of-scope for this iteration; WSL + clang is the recommended path for now.
- System library discovery: pkg-config is supported via `cpp.pkgConfig.makeLibrary`, but framework discovery (e.g. macOS `-framework`) still needs manual flags.
- Error reporting from the scanner currently surfaces raw clang warnings (e.g., unused linker flags). We can tailor the toolchain wrapper to silence or adjust these diagnostics.
