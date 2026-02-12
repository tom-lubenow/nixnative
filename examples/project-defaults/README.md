# Project Defaults Example

This example demonstrates how project-level defaults reduce boilerplate by defining common settings once.

## What This Demonstrates

- Setting project-wide compile flags and defines
- Per-language flags (e.g., C++ standard)
- Default inheritance and overriding
- Creating debug vs release variants

## Project Structure

```
project-defaults/
├── flake.nix          # Flake configuration
├── project.nix        # Build definitions
├── checks.nix         # Test definitions
└── src/
    ├── common/        # Shared library code
    ├── cli/           # CLI application
    └── daemon/        # Daemon application
```

## Build and Run

```sh
# Build all packages
nix build .#cli
nix build .#daemon
nix build .#cli-debug

# Run tests
nix flake check
```

## How It Works

### Define Project Defaults

```nix
proj = native.project {
  root = ./.;
  defines = [ "PROJECT_VERSION=100" ];
  compileFlags = [ "-Wall" "-Wextra" ];
  languageFlags = { cpp = [ "-std=c++17" ]; };
  includeDirs = [ "src/common" ];
};
```

Every target gets these settings automatically:
- `PROJECT_VERSION=100` preprocessor define
- Warning flags `-Wall -Wextra`
- C++17 standard for C++ files
- Include path for common headers

### Targets Inherit Defaults

```nix
cli = proj.executable {
  name = "cli";
  sources = [ "src/cli/main.cc" ];
  libraries = [ libcommon ];
  # Inherits: defines, compileFlags, languageFlags, includeDirs
};

daemon = proj.executable {
  name = "daemon";
  sources = [ "src/daemon/main.cc" ];
  libraries = [ libcommon ];
  defines = [ "DAEMON_MODE" ];  # Added to project defines
};
```

### Override Defaults

Targets can override specific defaults:

```nix
cliDebug = proj.executable {
  name = "cli-debug";
  sources = [ "src/cli/main.cc" ];
  libraries = [ libcommon ];
  compileFlags = [ "-g" "-O0" ];  # Override optimization
  defines = [ "DEBUG" ];          # Add debug define
};
```

## Default Inheritance Rules

| Setting | Behavior |
|---------|----------|
| `defines` | Target defines added to project defines |
| `compileFlags` | Target flags added to project flags |
| `languageFlags` | Merged by language |
| `includeDirs` | Target dirs added to project dirs |
| `linkFlags` | Target flags added to project flags |

## Pattern: Build Variants

Create debug and release configurations:

```nix
let
  proj = native.project {
    root = ./.;
    compileFlags = [ "-Wall" "-Wextra" ];
  };

  # Extend for different configurations
  debug = proj.extend {
    compileFlags = [ "-g" "-O0" ];
    defines = [ "DEBUG" ];
  };

  release = proj.extend {
    compileFlags = [ "-O2" "-flto=thin" ];
    linkFlags = [ "-flto=thin" ];
  };
in {
  app-debug = debug.executable { ... };
  app-release = release.executable { ... };
}
```

## Testing with Defaults

Tests can verify that defaults are applied:

```nix
testCli = native.test {
  name = "test-cli";
  executable = cli;
  expectedOutput = "[100] CLI tool running";  # Verifies PROJECT_VERSION
};
```

## Related Examples

- See `composable-project/` for the basic project API
- See `multi-binary/` for multiple executables
- See `multi-toolchain/` for compiler/linker configuration
