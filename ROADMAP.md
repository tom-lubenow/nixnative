# nixnative API Improvements Roadmap

## Overview

This document outlines planned improvements to the nixnative API based on real-world usage (particularly the Slurm port). The goal is to reduce boilerplate, improve ergonomics, and simplify maintenance.

---

## Phase 1: Remove Abstract Flags ✓ DONE

**Problem**: The abstract flags system (`{ type = "optimize"; value = "3"; }`) is:
- Verbose compared to just writing `-O3`
- Hard to maintain as compilers evolve
- Incomplete (can't represent all useful flags)
- Not providing enough value to justify the complexity

**Decision**: Remove abstract flags entirely. Users know their compiler and flags.

### Changes Required

1. Remove `nix/native/core/flags.nix`
2. Remove `flags.fromArgs` and ergonomic params (`lto`, `sanitizers`, `coverage`, etc.) from `api.nix`
3. Remove `translateFlags` from toolchain
4. Update all examples to use raw `compileFlags`/`ldflags`
5. Document common flag patterns in README

### What to Keep

- `compileFlags` - raw compile flags for all languages
- `langFlags` - per-language flags `{ c = [...]; cpp = [...]; }`
- `ldflags` - linker flags

### Migration

```nix
# Before (abstract)
flags = [
  { type = "optimize"; value = "3"; }
  { type = "lto"; value = "thin"; }
  { type = "sanitizer"; value = "address"; }
];

# After (raw)
compileFlags = [ "-O3" "-flto=thin" "-fsanitize=address" ];
ldflags = [ "-flto=thin" "-fsanitize=address" ];
```

---

## Phase 2: Project Defaults ✓ DONE

**Problem**: Real projects repeat the same settings across every target:
```nix
# Repeated 15+ times in slurm:
someTarget = native.executable {
  inherit root;
  defines = commonDefines;
  compileFlags = commonCompileFlags;
  langFlags = { c = [ "-std=gnu11" ]; };
  tools = commonTools;
  # ...
};
```

**Solution**: Add a `mkProject` function that creates a scoped builder set with defaults.

### Proposed API

```nix
project = native.mkProject {
  root = ./.;

  # These apply to all targets in this project
  defaults = {
    defines = [ "HAVE_CONFIG_H" "_GNU_SOURCE" ];
    compileFlags = [ "-fPIC" "-Wall" ];
    langFlags = { c = [ "-std=gnu11" ]; cpp = [ "-std=c++17" ]; };
    tools = [ autoconfTool ];
  };
};

# Targets inherit defaults, can override
libcommon = project.staticLib {
  name = "common";
  sources = [ "src/common/*.c" ];
  # No need to repeat defines, compileFlags, langFlags, tools
};

sinfo = project.executable {
  name = "sinfo";
  sources = [ "src/sinfo/*.c" ];
  libraries = [ libcommon ];
  # Adds to defaults:
  tools = [ helpTextTool ];  # Merged with project.defaults.tools
};
```

### Implementation Notes

- `project.staticLib`, `project.executable`, etc. are thin wrappers
- Merge strategy: lists are concatenated, attrs are merged (target wins)
- `root` from project is inherited unless overridden
- Expose `project.defaults` for inspection

---

## Phase 3: Simplify Tool Plugin API ✓ DONE

**Problem**: Creating a custom tool requires ~80 lines of boilerplate with manual management of `headers`, `sources`, `includeDirs`, `public`, `evalInputs`.

**Solution**: Provide a simpler `mkGeneratedSources` helper.

### Proposed API

```nix
# Simple case: derivation that outputs files
versionTool = native.mkGeneratedSources {
  name = "version-header";
  drv = pkgs.runCommand "gen-version" {} ''
    mkdir -p $out
    echo '#define VERSION "1.0.0"' > $out/version.h
  '';
  # Files are auto-discovered, or specify explicitly:
  headers = [ "version.h" ];
};

# Complex case: with sources and custom include path
protobufTool = native.mkGeneratedSources {
  name = "proto-gen";
  drv = myProtobufDerivation;
  headers = [ "foo.pb.h" "bar.pb.h" ];
  sources = [ "foo.pb.cc" "bar.pb.cc" ];
  includeDir = "proto";  # Optional subdirectory
};
```

### Keep Existing Low-Level API

The current manual tool format remains for advanced use cases, but most users should use `mkGeneratedSources`.

---

## Phase 4: Naming Consistency ✓ DONE

**Problem**: Inconsistent naming across the API.

### Proposed Changes

| Current | Proposed | Reason |
|---------|----------|--------|
| `ldflags` | `linkFlags` | Consistent camelCase |
| `langFlags` | `languageFlags` | Clearer |
| `publicIncludeDirs` | Keep | Already clear |
| `cxxFlags` (in public) | `compileFlags` | Match top-level |

### API Tiers

Document clearly:
- **High-level**: `native.executable`, `native.staticLib`, etc. (recommended)
- **Low-level**: `native.mkExecutable`, `native.mkStaticLib`, etc. (explicit toolchain)
- **Internal**: Not for public use

---

## Phase 5: Installation / Packaging ✓ DONE

**Problem**: No standard way to create an installable package with `bin/`, `lib/`, `include/`.

### Proposed API

```nix
native.mkInstallation {
  name = "myproject";
  version = "1.0.0";

  executables = [ app1 app2 ];
  libraries = [ libfoo libbar ];
  headers = [ "include" ];  # Directory to copy

  # Optional
  pkgConfig = true;  # Generate .pc files
  cmakeConfig = true;  # Generate cmake find modules
}
```

---

## Phase 6: Future Considerations

### Maybe: Flake-parts Module

```nix
# In flake.nix
imports = [ nixnative.flakeModules.default ];

nixnative.projects.myapp = {
  root = ./.;
  executables.app = { sources = [ "main.cc" ]; };
};
```

**Status**: Defer until core API is stable.

### Maybe: Overlay Pattern

```nix
native' = native.extend {
  compilers.myClang = ...;
  tools.myTool = ...;
};
```

**Status**: Low priority, current approach works.

---

## Implementation Order

1. **Phase 1** (Remove abstract flags) ✓ Complete
2. **Phase 2** (Project defaults) ✓ Complete
3. **Phase 3** (Tool API) ✓ Complete
4. **Phase 4** (Naming) ✓ Complete
5. **Phase 5** (Installation) ✓ Complete

---

## Notes

- Each phase should be a separate PR
- Update examples after each phase
- Keep backwards compatibility where reasonable (deprecation warnings)
- Update slurm port as a real-world validation
