# NixClang API Reference

This document describes the public API exposed by `nixclang.lib.cpp`.

## Core Builders

### `mkExecutable`
Builds an executable binary.

```nix
mkExecutable {
  name = "my-app";
  root = ./.;
  sources = [ "src/main.cc" ];
  # Optional arguments
  includeDirs = [ "include" ];
  defines = [ "DEBUG" ];
  cxxFlags = [ "-O2" ];
  ldflags = [ "-lm" ];
  libraries = [ myLib ];
  generators = [ myGenerator ];
  toolchain = clangToolchain;
}
```

### `mkStaticLib`
Builds a static library (`.a`) and installs headers.

```nix
mkStaticLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ]; # Installed to $out/include
  # ... standard build args
}
```

### `mkSharedLib`
Builds a shared library (`.so` / `.dylib`) and installs headers.

```nix
mkSharedLib {
  name = "my-lib";
  root = ./.;
  sources = [ "src/lib.cc" ];
  publicIncludeDirs = [ "include" ];
  # ... standard build args
}
```

### `mkHeaderOnly`
Defines a header-only library interface.

```nix
mkHeaderOnly {
  name = "my-headers";
  publicIncludeDirs = [ "include" ];
  publicDefines = [ "MY_LIB_ENABLED" ];
}
```

### `mkPythonExtension`
Builds a CPython extension module.

```nix
mkPythonExtension {
  name = "my_ext";
  root = ./.;
  sources = [ "src/bindings.cc" ];
  # ... standard build args
}
```

## Testing & Documentation

### `mkTest`
Runs a test executable during the build.

```nix
mkTest {
  name = "my-test";
  executable = myApp;
  args = [ "--test" ];
  stdin = "input data";
  expectedOutput = "Success";
}
```

### `mkDoc`
Generates documentation using Doxygen.

```nix
mkDoc {
  name = "my-docs";
  root = ./.;
  sources = [ "src" "include" ];
}
```

## Development

### `mkDevShell`
Creates a development shell with tools and environment variables.

```nix
mkDevShell {
  target = myApp;
  includeTools = true; # Adds clang-tools, lldb/gdb
}
```

## Advanced

### `mkDependencyScanner`
Creates a derivation that scans source files for dependencies using `clang -MMD`. Used internally by builders when no manifest is provided.

### `mkBuildContext`
(Internal) Prepares the build context (sources, flags, headers) for all builder types.
