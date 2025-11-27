# Cross-Compilation Example

This example demonstrates cross-compilation patterns with nixnative, targeting different architectures from a single build host.

## What This Demonstrates

- Building for different target architectures
- Using Zig as a cross-compilation toolchain
- Creating multi-architecture packages
- Understanding cross-compilation in Nix

## Project Structure

```
cross-compile/
├── flake.nix     # Cross-compilation build definitions
├── src/
│   └── main.cc   # Platform-aware source code
└── README.md
```

## Current Status

**Note**: Full cross-compilation support in nixnative is experimental. This example demonstrates the patterns and available approaches.

## Build and Test

```sh
# Build for current architecture (always works)
nix build

# Build for specific targets (when cross-compilation is available)
nix build .#native        # Current platform
nix build .#aarch64-linux # ARM64 Linux (from x86_64 Linux)
nix build .#x86_64-linux  # x86_64 Linux (from ARM64)
```

## Cross-Compilation Approaches

### Approach 1: Nix Cross-Compilation (Recommended)

Use Nix's built-in cross-compilation by importing nixpkgs with `crossSystem`:

```nix
# Cross-compile to aarch64-linux
pkgsCross = import nixpkgs {
  system = "x86_64-linux";
  crossSystem = { config = "aarch64-unknown-linux-gnu"; };
};

# Use native with cross-compiled packages
nativeCross = nixnative.lib.native { pkgs = pkgsCross; };

crossApp = nativeCross.executable {
  name = "app-aarch64";
  sources = [ "src/main.cc" ];
};
```

**Pros**:
- Leverages Nix's mature cross-compilation infrastructure
- Works with all existing nixpkgs packages
- Proper sysroot handling

**Cons**:
- Some packages don't cross-compile cleanly
- Can be slow for complex dependency graphs

### Approach 2: Zig Cross-Compiler

Zig includes a cross-compiler that can target many platforms:

```nix
# Build a Zig-based cross toolchain
zigCross = pkgs.runCommand "zig-cross" {
  nativeBuildInputs = [ pkgs.zig ];
} ''
  mkdir -p $out/bin

  # Create wrapper script for cross-compilation
  cat > $out/bin/zig-cc-aarch64 << 'EOF'
  #!/bin/sh
  exec zig cc -target aarch64-linux-gnu "$@"
  EOF
  chmod +x $out/bin/zig-cc-aarch64
'';
```

**Pros**:
- Single toolchain for many targets
- Self-contained, no sysroot needed for musl targets
- Fast compilation

**Cons**:
- Limited C++ library support
- May not work with all code

### Approach 3: Multi-Platform Builds

Build natively on each platform using Nix's remote builders:

```nix
# In flake.nix
packages = {
  x86_64-linux = { ... };   # Built on x86_64-linux
  aarch64-linux = { ... };  # Built on aarch64-linux
  aarch64-darwin = { ... }; # Built on aarch64-darwin
};
```

**Pros**:
- Native builds, no cross-compilation issues
- Full platform support

**Cons**:
- Requires remote builders for each architecture
- Slower for multi-arch CI

## Platform Detection in Code

```cpp
#include <iostream>

int main() {
    std::cout << "Built for: ";

#if defined(__x86_64__)
    std::cout << "x86_64";
#elif defined(__aarch64__)
    std::cout << "aarch64";
#elif defined(__arm__)
    std::cout << "arm";
#elif defined(__i386__)
    std::cout << "i386";
#else
    std::cout << "unknown";
#endif

#if defined(__linux__)
    std::cout << "-linux";
#elif defined(__APPLE__)
    std::cout << "-darwin";
#elif defined(_WIN32)
    std::cout << "-windows";
#endif

    std::cout << std::endl;
    return 0;
}
```

## Nix Cross-Compilation Matrix

| Host | Target | Support |
|------|--------|---------|
| x86_64-linux | aarch64-linux | Good |
| x86_64-linux | armv7l-linux | Good |
| aarch64-linux | x86_64-linux | Good |
| x86_64-darwin | aarch64-darwin | Partial |
| aarch64-darwin | x86_64-darwin | Partial |
| Linux | Windows (mingw) | Experimental |

## Setting Up Remote Builders

For true multi-architecture CI, configure Nix remote builders:

```nix
# /etc/nix/machines
ssh://aarch64-builder aarch64-linux - 4 1 big-parallel
ssh://x86_64-builder x86_64-linux - 4 1 big-parallel
```

## Future Work

nixnative aims to provide:

1. **Seamless cross-toolchain selection**:
   ```nix
   native.mkToolchain {
     compiler = native.compilers.clang;
     target = "aarch64-linux-gnu";
   };
   ```

2. **Zig backend integration**:
   ```nix
   native.compilers.zig {
     target = "aarch64-linux-musl";
   };
   ```

3. **Automatic sysroot management**:
   ```nix
   native.mkCrossToolchain {
     host = "x86_64-linux";
     target = "aarch64-linux";
     libc = "glibc";  # or "musl"
   };
   ```

## Workaround: Shell-Based Cross-Compilation

For immediate needs, use a shell with cross-compilation tools:

```nix
devShells.cross = pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.zig
    pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc
  ];

  shellHook = ''
    export CC="zig cc -target aarch64-linux-gnu"
    export CXX="zig c++ -target aarch64-linux-gnu"
    echo "Cross-compilation shell ready"
    echo "Target: aarch64-linux-gnu"
  '';
};
```

## Next Steps

- See `interop/` for Zig integration patterns
- See the Nix manual on cross-compilation
- See Zig documentation for supported targets
