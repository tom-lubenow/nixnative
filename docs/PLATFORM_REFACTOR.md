# Platform Layer Specification

This document defines the architecture for platform handling in nixnative. Linux is the primary supported platform. Darwin (macOS) support is best-effort and must not add complexity to core abstractions.

## Core Invariants

1. **Linux-First**: The codebase assumes Linux. Platform conditionals exist only to degrade gracefully on other platforms, not to add features for them.

2. **No Darwin Complexity in Core**: Modules outside `linkers/darwin-ld.nix` must not contain Darwin-specific logic (SDK paths, deployment targets, frameworks, cctools). If Darwin needs special handling, it happens in Darwin-specific modules that are optional.

3. **Toolchain Simplicity**: The toolchain abstraction must not carry platform-specific parameters. No `sdkPath`, no `deploymentTarget`, no `getDarwin*` methods.

4. **Platform Layer is Minimal**: The platform module provides simple queries (extensions, detection). It does not orchestrate complex platform-specific setup.

---

## Module Responsibilities

### `core/platform.nix`

The platform module provides simple queries. It does not orchestrate builds.

**Provides:**

```nix
# Detection
isDarwin : Platform -> Bool
isLinux  : Platform -> Bool

# File extensions
sharedLibExtension  : Platform -> String    # ".so" (Linux), ".dylib" (Darwin)
staticLibExtension  : Platform -> String    # ".a"
executableExtension : Platform -> String    # ""

# Linux compile flags
defaultCompileFlags : Platform -> [String]  # ["-fPIC"] on Linux, [] elsewhere

# Linux link helpers
startLibraryGroup : Platform -> [String]    # ["--start-group"] on Linux
endLibraryGroup   : Platform -> [String]    # ["--end-group"] on Linux
rpathFlag         : Platform -> Path -> [String]
```

**Does not provide:**
- SDK configuration
- Deployment targets
- Framework handling
- Platform-specific runtime inputs

These belong in platform-specific linker/compiler modules, if anywhere.

---

### `core/toolchain.nix`

The toolchain composes compiler + linker + bintools. The interface is platform-agnostic.

**Must not have:**
- `sdkPath` parameter
- `deploymentTarget` parameter
- `getDarwinSDKFlags` method
- `getDarwinDeploymentFlags` method
- Any `darwin` in parameter or method names

**Interface:**

```nix
mkToolchain : {
  name : String;
  compiler : Compiler;
  linker : Linker;
  ar, ranlib, nm, objcopy, strip : Path;
  targetPlatform : Platform;
  runtimeInputs : [Derivation];
  environment : AttrSet;
} -> Toolchain
```

**Methods:**

```nix
{
  getPlatformCompileFlags : [String];  # From platform.defaultCompileFlags
  getPlatformLinkerFlags  : [String];  # From linker.platformFlags
  wrapLibraryFlags : [String] -> [String];  # --start-group/--end-group on Linux
}
```

Platform-specific compile/link flags come from the platform module and linker, not from toolchain parameters.

---

### `compilers/*.nix`

Compiler modules define compiler objects. They produce Linux-compatible output by default.

**Must not have:**
- `isDarwin` checks in core logic
- SDK path resolution
- `darwinCxxFlags`, `darwinEnv`, `darwinRuntimeInputs` variables
- `getDarwinLinkerInfo` or similar exports

**Interface:**

```nix
mkClang : {
  llvmPackages : LLVMPackages;
  name : String;
} -> Compiler
```

Compilers define `defaultCxxFlags` for standard compilation. They do not contain platform-conditional flag lists. If Darwin requires different flags, that is Darwin's problem to solve in its own modules.

---

### `linkers/*.nix`

Linker modules define linker objects.

**Invariants:**
- Generic linkers (`lld.nix`, `mold.nix`, `gold.nix`, `ld.nix`) must not reference Darwin
- `darwin-ld.nix` is quarantined: all Darwin linker complexity lives there and nowhere else
- Linker selection defaults to Linux-compatible linkers (lld, mold, gold, ld)

**Darwin linker (`darwin-ld.nix`):**
- May contain SDK paths, deployment targets, framework flags
- Is only loaded/used when explicitly requested or when platform detection selects it
- Does not leak types or concepts into other modules

---

### `builders/*.nix`

Build logic must be platform-blind. All platform variance arrives via toolchain and platform queries.

**Must not have:**
- `if targetPlatform.isDarwin`
- `if pkgs.stdenv.hostPlatform.isDarwin`
- `pkgs.darwin.cctools` or any `pkgs.darwin.*` references
- Inline `if ... then "dylib" else "so"` expressions

**Must use:**

```nix
# File extensions
platform.sharedLibExtension targetPlatform

# Compile flags (includes -fPIC on Linux)
toolchain.getPlatformCompileFlags

# Link flags
toolchain.getPlatformLinkerFlags

# Library grouping
toolchain.wrapLibraryFlags linkFlags
```

Builders do not make decisions based on platform. They call platform/toolchain functions that encapsulate those decisions.

---

### `utils/pkgconfig.nix`

Provides pkg-config integration for system libraries.

**Must not have:**
- `mkFrameworkLibrary` (Darwin-specific, remove entirely or move to `darwin-ld.nix`)

**Must have:**
- `mkPkgConfigLibrary` only

Framework support is not a core feature. Users on Darwin who need frameworks can construct the flags manually or use a Darwin-specific helper that lives outside core utils.

---

## Darwin Support Policy

Darwin is supported on a best-effort basis with these constraints:

1. **No core complexity**: Darwin quirks do not add parameters, methods, or conditionals to core modules
2. **Quarantined**: All Darwin-specific code lives in `linkers/darwin-ld.nix`
3. **Optional**: Darwin support may break without blocking Linux development
4. **User responsibility**: Darwin users may need to provide additional flags or configuration

If Darwin cannot be supported without adding complexity to core modules, Darwin support is dropped for that feature.

---

## Validation

The refactor is complete when:

```bash
# No Darwin references in core modules (except platform detection)
grep -r "isDarwin" nix/native/core/toolchain.nix        # 0 hits
grep -r "isDarwin" nix/native/builders/                 # 0 hits
grep -r "darwin" nix/native/compilers/clang.nix         # 0 hits
grep -r "darwin" nix/native/compilers/gcc.nix           # 0 hits
grep -r "pkgs.darwin" nix/native/builders/              # 0 hits

# No Darwin-specific parameters in toolchain
grep -r "sdkPath\|deploymentTarget" nix/native/core/   # 0 hits

# Darwin complexity is quarantined
grep -r "isDarwin\|darwin\|Darwin" nix/native/linkers/darwin-ld.nix  # allowed
```

---

## Summary

| Module | Darwin references allowed? |
|--------|---------------------------|
| `core/platform.nix` | Yes (detection only) |
| `core/toolchain.nix` | No |
| `core/compiler.nix` | No |
| `core/linker.nix` | No |
| `compilers/*.nix` | No |
| `linkers/darwin-ld.nix` | Yes (quarantine zone) |
| `linkers/*.nix` (others) | No |
| `builders/*.nix` | No |
| `utils/*.nix` | No |
