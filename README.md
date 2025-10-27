# nixclang

Incremental, deterministic C/C++ builds driven directly by Nix. This repository experiments with the "one derivation per translation unit" approach using clang as the only supported toolchain.

## Highlights

- **Per translation unit derivations.** Each `.cc` file becomes its own derivation that compiles to an object file. Touching a source or header only rebuilds the affected units.
- **Hermetic clang toolchain.** We vendor LLVM 18 from `nixpkgs` so compilation flags and target triple are part of the cache key.
- **Dependency scanner (optional).** A dedicated scanner derivation runs `clang++ -MMD` to discover header/module dependencies and emits a JSON manifest. Keep the JSON in your repo for strict CI builds or import it dynamically via IFD for developer convenience.
- **`compile_commands.json` passthrough.** Every build target exposes a generated compilation database for editor tooling.
- **Structured libraries.** `mkStaticLib`, `mkSharedLib`, and `mkHeaderOnly` propagate link flags and public include directories so downstream targets can consume your outputs without manual `-L/-l` churn.
- **Generator pipeline.** Attach derivations that emit headers/sources (plus manifests) to executables or libraries; include paths, defines, and link flags flow through automatically.

## Repository layout

```
.
├── README.md
├── flake.nix
├── nix/
│   └── cpp/default.nix        # core library (`mkExecutable`, scanners, toolchain)
├── examples/
│   └── simple/                # sample project + tests
│       ├── include/
│       ├── src/
│       ├── deps.json          # strict-mode manifest
│       └── default.nix        # exposes packages/checks used by the flake
└── docs/
    └── ...                    # architectural notes (to be expanded)
```

## Quick start

### Build the example

```sh
nix build .#simple-strict           # uses the checked-in deps.json
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
        depsManifest = ./math.deps.json;
      };

      versionHeaders = pkgs.runCommand "generate-version" { } ''
        set -euo pipefail
        mkdir -p "$out/include/generated"
        cat > "$out/include/generated/version.hpp" <<'EOF'
#pragma once
inline constexpr int generated_version() { return 7; }
EOF
      '';

      versionManifest = pkgs.writeText "version.manifest.json" (builtins.toJSON {
        schema = 1;
        units."src/main.cc".dependencies = [ "generated/version.hpp" ];
      });

      versionGen = {
        drv = versionHeaders;
        manifest = versionManifest;
        headers = [{ rel = "generated/version.hpp"; path = "${versionHeaders}/include/generated/version.hpp"; }];
        public.includeDirs = [{ path = "${versionHeaders}/include"; }];
      };
    in {
      my-app = cpp.mkExecutable {
        name = "my-app";
        root = ./.
        sources = [ "src/main.cc" ];
        includeDirs = [ "include" ];
        depsManifest = ./app.deps.json;  # or scanner = cpp.mkDependencyScanner { ... };
        libraries = [ math ];
        generators = [ versionGen ];
        cxxFlags = [ "-O2" ];
      };
    };
  };
}
```

### Dev shell

```sh
nix develop
clang++ --version
```

The shell provides the pinned clang18 toolchain plus `nix`/`git` for day-to-day editing.

### Sync dependency manifests

Need to refresh a checked-in `deps.json` after a scanner run? Use the helper app:

```sh
nix run .#cpp-sync-manifest -- .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').simpleScanManifest examples/simple/deps.json
```

Pass any additional `nix build` flags after the destination path (for example `--refresh`).

## Dependency manifests

Two workflows coexist:

1. **Strict mode (`depsManifest`).** Commit the JSON manifest under version control (regenerate with `nix run .#cpp-sync-manifest`). CI evaluates without IFD and substitutes pre-built objects from a binary cache.
2. **Scanner mode (`scanner`).** Call `mkDependencyScanner`, which returns a derivation producing `deps.json`. Passing it into `mkExecutable` triggers Import From Derivation (IFD) and yields fully accurate dependency edges without manual updates.

The JSON format is intentionally simple:

```json
{
  "schema": 1,
  "units": {
    "src/main.cc": {
      "dependencies": [
        "src/main.cc",
        "include/foo.hpp"
      ]
    }
  }
}
```

## Current limitations

- Only clang/LLVM 18 is supported. GCC, MSVC, or cross toolchains would require extending `toolchains`.
- Dependency scanning runs `clang++ -MMD`; custom generators or exotic include search paths may need additional hooks.
- System libraries still require manual flags today (`-lfoo`, `-L/path`). Wrappers around pkg-config or framework discovery would improve ergonomics.
- We operate on discrete files. Widely used headers still fan out rebuilds; address this by refactoring headers, introducing modules, or grouping TUs.

## Next steps

- Expose helpers for code generators (e.g. protobuf) so their outputs can slot into the dependency graph automatically.
- Emit richer `compile_commands.json` metadata (e.g. per-file `-working-directory`).
- Ship a `watch` CLI that keeps evaluation warm for sub-second rebuilds during development.

Contributions and feedback welcome—open issues or PRs as you experiment.
