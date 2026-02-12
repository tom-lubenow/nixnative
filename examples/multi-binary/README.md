# Multi-Binary Example

This example demonstrates building multiple executables that share common libraries within a single project.

## What This Demonstrates

- Building multiple executables from one flake
- Sharing static libraries across binaries
- Common code organization patterns
- Different binary configurations (CLI, daemon, tests)

## Project Structure

```
multi-binary/
├── flake.nix              # Build definitions for all binaries
├── common/
│   ├── include/
│   │   ├── config.h       # Shared configuration
│   │   ├── logger.h       # Logging interface
│   │   └── database.h     # Database interface
│   ├── config.cc          # Configuration implementation
│   ├── logger.cc          # Logger implementation
│   └── database.cc        # Database implementation
├── cli/
│   └── main.cc            # Command-line tool
├── daemon/
│   └── main.cc            # Background service
└── tests/
    └── main.cc            # Test harness
```

## Build and Run

```sh
# Build all binaries
nix build

# The default output is a combined package
ls result/bin/
# myapp-cli  myapp-daemon  myapp-tests

# Build individual binaries
nix build .#cli
nix build .#daemon
nix build .#tests

# Run each binary
./result/bin/myapp-cli --help
./result/bin/myapp-daemon --check
./result/bin/myapp-tests
```

Expected output from CLI:
```
MyApp CLI v1.0.0
================
Usage: myapp-cli [options]

Options:
  --help     Show this help
  --version  Show version
  --config   Show configuration

Configuration loaded: debug=true, db=:memory:
Logger initialized: level=INFO
Database connected: :memory:
CLI ready!
```

## How It Works

### Shared Library

```nix
let
  proj = native.project { root = ./.; };
  commonSources = native.utils.discoverSources {
    root = ./.;
    patterns = [ "common/*.cc" ];
  };

  # Build common code as a static library
  commonLib = proj.staticLib {
    name = "libmyapp-common";
    sources = commonSources;
    includeDirs = [ "common/include" ];
    publicIncludeDirs = [ "common/include" ];
  };
in { ... }
```

### Multiple Executables

```nix
  # CLI tool
  cli = proj.executable {
    name = "myapp-cli";
    sources = [ "cli/main.cc" ];
    libraries = [ commonLib ];  # Direct reference!
  };

  # Daemon
  daemon = proj.executable {
    name = "myapp-daemon";
    sources = [ "daemon/main.cc" ];
    libraries = [ commonLib ];
    defines = [ "DAEMON_MODE" ];
  };

  # Test binary
  tests = proj.executable {
    name = "myapp-tests";
    sources = [ "tests/main.cc" ];
    libraries = [ commonLib ];
    defines = [ "TEST_MODE" ];
  };
```

### Combined Package

```nix
  # Combine all binaries into one package
  combined = pkgs.symlinkJoin {
    name = "myapp";
    paths = [
      cli.passthru.target
      daemon.passthru.target
      tests.passthru.target
    ];
  };
```

## Key Patterns

### 1. Shared Static Library

All executables link against the same `commonLib`. Changes to common code trigger rebuilds of:
- The library itself
- All dependent executables

But changes to `cli/main.cc` only rebuild the CLI binary.

### 2. Binary-Specific Configuration

Use `defines` to enable binary-specific behavior:

```nix
targets.daemon = {
  type = "executable";
  defines = [ "DAEMON_MODE" "NO_INTERACTIVE" ];
  ...
};
```

```cpp
#ifdef DAEMON_MODE
  daemonize();
#endif
```

### 3. Shared vs Separate Builds

**Shared library approach** (this example):
- Single compilation of common code
- Smaller total build time
- Consistent behavior across binaries

**Separate builds** (alternative):
```nix
# Each binary compiles common code independently
targets.cli = {
  type = "executable";
  sources = [ "cli/main.cc" ] ++ commonSources;
  ...
};
```

### 4. Test Binary Pattern

The test binary includes the same common code but with test-specific configuration:

```nix
tests = proj.executable {
  name = "myapp-tests";
  sources = [ "tests/main.cc" ];
  libraries = [ commonLib ];  # Direct reference!
  defines = [ "TEST_MODE" "ENABLE_MOCKS" ];
  compileFlags = [ "-fsanitize=address" "-g" ];
  linkFlags = [ "-fsanitize=address" ];
};
```

## Incremental Builds

With this structure:

| Change | Rebuilds |
|--------|----------|
| `common/logger.cc` | `commonLib`, `cli`, `daemon`, `tests` |
| `cli/main.cc` | `cli` only |
| `daemon/main.cc` | `daemon` only |
| `common/include/config.h` | Depends on which sources include it |

## Real-World Use Cases

This pattern is common for:

- **CLI + Server**: Command-line client and background server
- **Client + Server**: Network client and server binaries
- **App + Tests**: Main application and test harness
- **Tools + Libraries**: Multiple utilities sharing core functionality

## Exposing Individual Binaries

Each binary is available as a separate flake output:

```sh
# Build only what you need
nix build .#cli
nix build .#daemon

# Reference in other flakes
inputs.myapp.packages.x86_64-linux.cli
```

## Next Steps

- See `library-chain/` for multi-library dependencies
- See `library/` for single library examples
- See `testing/` for test infrastructure
