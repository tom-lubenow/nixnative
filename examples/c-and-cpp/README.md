# Mixed C/C++ Example

This example demonstrates building projects with both C and C++ sources.

## What This Demonstrates

- Mixing `.c` and `.cc` files in a single project
- Proper `extern "C"` linkage for C/C++ interoperability
- Building C libraries consumed by C++ code
- C++ wrappers around C APIs

## Project Structure

```
c-and-cpp/
├── flake.nix
├── include/
│   ├── clib.h           # C header with extern "C"
│   └── cppwrapper.hpp   # C++ wrapper class
├── clib.c               # C implementation
└── main.cc              # C++ application
```

## Build and Run

```sh
# Build with mixed sources in one target
nix build
./result/bin/mixed-app

# Or build C library separately
nix build .#cppApp
./result/bin/cpp-app
```

Expected output:
```
Mixed C/C++ Example
===================

=== Direct C API usage ===
a = (3, 4)
b = (1, 2)
a + b = (4, 6)
|a| = 5

Original string: Hello
Reversed (C): olleH

=== C++ wrapper usage ===
v1 = (3, 4)
v2 = (1, 2)
v1 + v2 = (4, 6)
v1 * 2 = (6, 8)
v1 . v2 = 11
|v1| = 5

Original string: World
Reversed (C++): dlroW

Mixed C/C++ working correctly!
```

## How It Works

### C Headers for C++ Compatibility

```c
// clib.h
#ifndef CLIB_H
#define CLIB_H

#ifdef __cplusplus
extern "C" {
#endif

// C declarations here
Vec2 vec2_add(Vec2 a, Vec2 b);

#ifdef __cplusplus
}
#endif

#endif
```

The `extern "C"` block:
- Has no effect when compiled as C
- Tells the C++ compiler to use C linkage (no name mangling)

### Mixed Sources in One Target

```nix
targets.mixedApp = {
  type = "executable";
  name = "mixed-app";
  sources = [
    "clib.c"    # Compiled with CC (C compiler)
    "main.cc"   # Compiled with CXX (C++ compiler)
  ];
};
```

nixnative automatically selects the compiler based on file extension:
- `.c` → C compiler (`$CC`)
- `.cc`, `.cpp`, `.cxx` → C++ compiler (`$CXX`)

### C Library as Dependency

```nix
targets.cLib = {
  type = "staticLib";
  name = "clib";
  sources = [ "clib.c" ];
  publicIncludeDirs = [ "include" ];
};

targets.cppApp = {
  type = "executable";
  name = "cpp-app";
  sources = [ "main.cc" ];
  libraries = [ { target = "cLib"; } ];
};
```

Benefits of this approach:
- C library can be reused by multiple consumers
- Clear separation between C and C++ code
- C library can be tested independently

## Key Concepts

### Name Mangling

C++ compilers "mangle" function names to encode type information:
- `vec2_add` in C++ might become `_Z8vec2_add4Vec2S_`
- C compilers don't mangle names

`extern "C"` prevents mangling, allowing C++ to call C functions.

### Include Guard Patterns

```c
// C-style include guard
#ifndef MYHEADER_H
#define MYHEADER_H
// ...
#endif

// C++ pragma (also works in most C compilers)
#pragma once
```

### Mixing Standards

You can specify different standards for C and C++:

```nix
targets.mixedApp = {
  type = "executable";
  sources = [ "legacy.c" "modern.cc" ];
  languageFlags = {
    c = [ "-std=c11" ];
    cpp = [ "-std=c++20" ];
  };
};
```

## Common Patterns

### C++ Wrapper Class

```cpp
class Vector2D {
public:
  Vector2D(double x, double y) : vec_(vec2_create(x, y)) {}

  Vector2D operator+(const Vector2D& other) const {
    return Vector2D(vec2_add(vec_, other.vec_));
  }

private:
  Vec2 vec_;  // C struct
};
```

### RAII Wrappers for C Resources

```cpp
class FileHandle {
public:
  FileHandle(const char* path) : handle_(c_open_file(path)) {}
  ~FileHandle() { if (handle_) c_close_file(handle_); }

  // Prevent copying
  FileHandle(const FileHandle&) = delete;
  FileHandle& operator=(const FileHandle&) = delete;

private:
  CFileHandle* handle_;
};
```

## Next Steps

- See `library/` for building standalone libraries
- See `rust-integration/` for another FFI example
- See `interop/` for Zig integration
