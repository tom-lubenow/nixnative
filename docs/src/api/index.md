# API Overview

nixnative provides multiple API layers for different use cases:

| API Level | Functions | When to Use |
|-----------|-----------|-------------|
| **Composable** | `project` | Recommended - scoped builders with shared defaults |
| **High-level** | `executable`, `staticLib`, `sharedLib`, `headerOnly`, `devShell`, `shell`, `test` | Direct builders |
| **Module-based** | `evalProject` | Typed options, module composition |
| **Low-level** | `mkExecutable`, `mkStaticLib`, `mkSharedLib`, etc. | Explicit toolchain control |

## Key Differences

- **Composable API** returns scoped builders; targets are real Nix values
- **High-level API** accepts `compiler`/`linker` as strings (e.g., `"gcc"`, `"mold"`)
- **Module-based API** uses `{ target = "name"; }` string references
- **Low-level API** requires explicit `toolchain` object
- All APIs use `tools` parameters for code generation

## Quick Example

```nix
let
  proj = native.project {
    root = ./.;
    includeDirs = [ "include" ];
    compileFlags = [ "-Wall" "-Wextra" ];
  };

  myLib = proj.staticLib {
    name = "libmylib";
    sources = [ "src/lib.cc" ];
    publicIncludeDirs = [ "include" ];
  };

  myApp = proj.executable {
    name = "my-app";
    sources = [ "src/main.cc" ];
    libraries = [ myLib ];  # Direct reference!
  };
in {
  packages = { inherit myLib myApp; };
  devShells.default = native.devShell { target = myApp; };
}
```

## API Sections

- [Project Options](project.md) - Project-level configuration and scoped builders
- [Target Options](targets.md) - Executable, static library, shared library, header-only
- [Default Options](defaults.md) - Common build options and defaults
- [Test Options](tests.md) - Test infrastructure
- [Shell Options](shells.md) - Development shells
