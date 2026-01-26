  High‑impact improvements

  - [x] Object name collisions in ninja builds: normalizeSourceForNinja sanitizes relNorm by replacing / and . with -, which can
    collide (foo/bar.cc vs foo-bar.cc). This can silently overwrite object outputs. Consider including a short hash of the
    full relative path or use a reversible escaping scheme. nix/native/builders/helpers.nix:104-110.
  - [x] Tool dependency linkFlags shape: mkTool builds public.linkFlags via a map that can return lists for non‑string deps, which
    yields list‑of‑lists (not flattened). It works for the bundled tools (strings), but breaks for attrset deps. Either
    enforce string deps or flatten. nix/native/core/tool.nix:78-90.
  - [x] LTO validation checks only compiler caps: linker capability isn’t checked, so LTO can be accepted and fail later. Add a
    linker check in applyErgonomicFlags using toolchain.linker caps. nix/native/builders/api.nix:284-300.

  Toolchain ergonomics / assumptions

  - [x] Default bintools inference now uses the first language; however attrset ordering is lexical, not intent. If the first
    language is not C/C++ (future Rust, etc.), you may get surprising bintools. Consider:
      - Prefer cpp/c bintools if present, otherwise require explicit bintools for non‑C/C++ toolchains (fail fast instead of
        silently using clang).
  - Compiler defaults vs ergonomic flags: clang/gcc defaults already include -Wall -Wextra, but warnings = "all"/"extra"
    duplicates them. It’s harmless but noisy; consider deduping compileFlags or removing defaults in compiler configs and
    relying on the ergonomic flags.
  - Naming clarity: passthru.tus is opaque. Rename to translationUnits or drop if unused. nix/native/builders/helpers.nix:404-
    408.

  API consistency

  - Dedup behavior is now aligned (module system and project helper), but consider documenting that lists of strings/paths are
    deduped and attrset lists are not. This can surprise users expecting stable list ordering/duplicates.
  - mkNinjaTest takes wrapper but doesn’t use it. Either remove the parameter or add it to buildInputs so the wrapper is an
    explicit dependency. nix/native/ninja/wrapper.nix:101-118.

  Dead code / cleanup candidates

  - [x] validateCompiler, validateLinker, validateTool, validateToolOutput, validateTestLib are defined but unused and not
    exported. Either wire them into constructors or remove them to reduce maintenance surface.
  - [x] listDirs and captureFile are unused in utils; remove or use them somewhere.

  Potentially awkward or surprising behavior

  - mkToolchain name generation uses the first language name; with multiple languages it may not be intuitive (e.g., c- vs
    cpp-). Maybe prefer cpp if present, or require explicit name for multi‑lang toolchains.
  - Header‑only path capture: mkHeaderOnly uses sanitizePath (captures entire root) while compiled targets use header‑only
    capture. This is consistent with “no compilation” but can be a perf surprise. Consider documenting it or adopting the
    header‑only filter there too.
