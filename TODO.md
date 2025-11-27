# nixnative Examples TODO

## Completed

- [x] Add READMEs to all examples (executable, library, protobuf, plugins, testing, devshell, install, interop)
- [x] Add comments to project.nix and flake.nix files
- [x] Create examples/README.md with progression guide and feature matrix
- [x] Fix protobuf example to use native.tools.protobuf (not generators import)

---

## Missing Examples (Documented but Not Demonstrated)

| Feature                  | API                                      | Status            |
|--------------------------|------------------------------------------|-------------------|
| Header-only libraries    | native.headerOnly or native.mkHeaderOnly | Not demonstrated  |
| Python extensions        | native.mkPythonExtension                 | Not demonstrated  |
| Documentation            | native.mkDoc (Doxygen)                   | Not demonstrated  |
| Coverage instrumentation | flags = [{ type = "coverage"; ... }]     | Not demonstrated  |
| macOS frameworks         | native.pkgConfig.mkFrameworkLibrary      | Not demonstrated  |
| pkg-config (standalone)  | native.pkgConfig.makeLibrary             | Only shown inline |
| Cross-compilation        | Mentioned in docs                        | Not demonstrated  |
| Multi-library chains     | A → B → C dependencies                   | Not demonstrated  |
| Mixed C/C++              | C + C++ sources together                 | Not demonstrated  |

---

## Recommended New Examples

### Priority 1: Fill Documentation Gaps

1. **header-only/** - Demonstrates `native.headerOnly`
   - Shows: header-only libraries, publicDefines

2. **python-extension/** - Demonstrates `native.mkPythonExtension`
   - Shows: building CPython extensions, linking Python

3. **coverage/** - Demonstrates coverage instrumentation
   - Shows: `flags = [{ type = "coverage"; value = true; }]`, lcov integration

4. **pkg-config/** - Standalone pkg-config example
   - Shows: makeLibrary, mkFrameworkLibrary (macOS)

### Priority 2: Common Use Cases

5. **library-chain/** - Multi-library dependencies
   - app → libmath → libcore → libutil

6. **c-and-cpp/** - Mixed C/C++ project
   - Shows: .c files alongside .cc, C headers, extern "C"

7. **simple-tool/** - Minimal code generator
   - Shows: mkTool with simplest possible Python script
   - Better entry point than app-with-library's complex tool

### Priority 3: Advanced Scenarios

8. **cross-compile/** - Cross-compilation (even if experimental)
   - Shows: targeting different architecture

9. **monorepo/** - Multiple targets sharing code
   - Shows: internal libraries, multiple executables, test targets

---

## Structural Improvements (Lower Priority)

1. Standardize structure:
   - All examples should have: flake.nix, project.nix, checks.nix, README.md
   - Currently some inline everything in flake.nix

2. Consolidate or differentiate interop examples:
   - rust-integration + rust-integration-crane are good (different approaches)
   - interop (Zig) could be expanded with more Zig-specific features
