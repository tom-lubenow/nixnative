# Library Installation Example

This example demonstrates building and installing both static and shared libraries.

## What This Demonstrates

- Building static libraries with `native.staticLib`
- Building shared libraries with `native.sharedLib`
- Library output structure and installation paths
- Public headers via `publicIncludeDirs`

## Project Structure

```
install/
├── flake.nix    # Build definitions
├── lib.h        # Public header
└── lib.cc       # Implementation
```

## Build

```sh
# Build static library
nix build .#staticLib
tree result/
# result/
# ├── include/
# │   └── lib.h
# └── lib/
#     └── libmylib-static.a

# Build shared library
nix build .#sharedLib
tree result/
# result/
# ├── include/
# │   └── lib.h
# └── lib/
#     └── libmylib-shared.so  (or .dylib on macOS)
```

## How It Works

### Static Library

```nix
staticLib = native.staticLib {
  name = "mylib-static";
  root = ./.;
  sources = [ "lib.cc" ];
  publicIncludeDirs = [ ./. ];  # Install lib.h to $out/include
};
```

Output structure:
- `$out/lib/libmylib-static.a` - Static archive
- `$out/include/lib.h` - Public header

### Shared Library

```nix
sharedLib = native.sharedLib {
  name = "mylib-shared";
  root = ./.;
  sources = [ "lib.cc" ];
  publicIncludeDirs = [ ./. ];
};
```

Output structure:
- `$out/lib/libmylib-shared.so` (Linux) or `.dylib` (macOS)
- `$out/include/lib.h` - Public header

## Key Differences

| Aspect | Static Library | Shared Library |
|--------|---------------|----------------|
| Extension | `.a` | `.so` / `.dylib` |
| Linking | Copied into executable | Loaded at runtime |
| Size | Larger executables | Smaller executables |
| Deployment | Self-contained | Requires library at runtime |
| Build function | `native.staticLib` | `native.sharedLib` |

## Consuming Installed Libraries

### From Another Nix Derivation

```nix
myApp = native.executable {
  name = "my-app";
  root = ./.;
  sources = [ "main.cc" ];
  libraries = [ staticLib ];  # or sharedLib
};
```

### From pkg-config (if installed)

Libraries can be wrapped with pkg-config for system-wide discovery:

```nix
# In another project
myLib = native.pkgConfig.makeLibrary {
  name = "mylib";
  packages = [ installedLib ];
};
```

## The `public` Attribute

Both library types expose a `public` attribute for dependents:

```nix
{
  includeDirs = [ { path = "${lib}/include"; } ];
  defines = [ ];
  cxxFlags = [ ];
  linkFlags = [ "${lib}/lib/libname.a" ];  # or path to .so
}
```

## Best Practices

1. **Use static libraries** for internal project dependencies
2. **Use shared libraries** for plugins or when binary size matters
3. **Always set `publicIncludeDirs`** so consumers can find headers
4. **Use `publicDefines`** to propagate feature flags to consumers

## Next Steps

- See `library/` for consuming libraries in tests
- See `plugins/` for dlopen-based shared library usage
- See `app-with-library/` for complete application with libraries
