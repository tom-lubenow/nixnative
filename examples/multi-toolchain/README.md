# Multi-Toolchain Example

Demonstrates nixnative's compiler and linker flexibility with various configurations.

## Available Builds

### All Platforms

| Package | Compiler | Linker | Description |
|---------|----------|--------|-------------|
| `default` | clang | platform default | Basic build |
| `withGcc` | gcc | platform default | GCC compiler |
| `withO3` | clang | platform default | Optimization level 3 |
| `withLtoThin` | clang | lld | Thin LTO |
| `withLtoFull` | clang | lld | Full LTO |
| `withDebug` | clang | platform default | Debug symbols |
| `lowLevelDefault` | clang | lld | Using low-level API |
| `lowLevelCustom` | clang | lld | Custom toolchain |
| `matrix-clang-lld` | clang | lld | Build matrix entry |

### Linux Only

| Package | Compiler | Linker | Description |
|---------|----------|--------|-------------|
| `withClangMold` | clang | mold | Fast mold linker |
| `withAsan` | clang | lld | AddressSanitizer |
| `matrix-clang-mold` | clang | mold | Build matrix entry |

## Usage

```sh
# Build with default toolchain
nix build

# Build with specific compiler
nix build .#withGcc

# Build with fast linker
nix build .#withClangMold  # Linux only

# Build optimized
nix build .#withLtoThin
nix build .#withO3
```

## Notes

- **Mold linker**: Significantly faster than lld for large projects. Linux-only.
- **Explicit flags**: Use `compileFlags` and `linkFlags` directly for optimization, LTO, sanitizers, and coverage settings.
