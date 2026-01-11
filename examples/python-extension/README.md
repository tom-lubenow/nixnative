# Python Extension Example

This example demonstrates building Python C++ extensions using pybind11 and nixnative.

## What This Demonstrates

- Building a shared library for Python module import
- Using pybind11 for C++/Python bindings
- Packaging the extension for Python consumption
- Testing Python extensions with nixnative

## Project Structure

```
python-extension/
├── flake.nix         # Flake configuration
├── project.nix       # Build definitions
├── checks.nix        # Test definitions
└── src/
    └── mathext.cpp   # pybind11 extension module
```

## Build and Run

```sh
# Build the Python package
nix build

# Use the extension in Python
nix develop
python3 -c "import mathext; print(mathext.add(2, 3))"

# Run tests
nix flake check
```

Expected test output:
```
Python extension tests passed!
```

## How It Works

### Building the Shared Library

```nix
let
  python = pkgs.python312;
  pybind11 = python.pkgs.pybind11;

  proj = native.project { root = ./.; };

  mathext = proj.sharedLib {
    name = "mathext";
    sources = [ "src/mathext.cpp" ];
    includeDirs = [
      "${pybind11}/include"
      "${python}/include/python${python.pythonVersion}"
    ];
    compileFlags = [ "-fvisibility=hidden" ];
    languageFlags = { cpp = [ "-std=c++17" ]; };
  };
in { ... }
```

### Packaging for Python

The shared library is wrapped into a Python package:

```nix
pythonPackage = pkgs.stdenv.mkDerivation {
  name = "mathext-python";
  buildInputs = [ mathext.passthru.target ];

  buildPhase = ''
    ext_suffix=$(python3 -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")
    mkdir -p $out/lib/python${python.pythonVersion}/site-packages
    cp ${mathext.passthru.target}/mathext.so \
       $out/lib/python${python.pythonVersion}/site-packages/mathext$ext_suffix
  '';
};
```

## Key Features

### pybind11 Integration

The extension uses pybind11 to expose C++ functions:

```cpp
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

int add(int a, int b) { return a + b; }

PYBIND11_MODULE(mathext, m) {
    m.def("add", &add);
    m.def("multiply", &multiply);
    // ...
}
```

### Visibility Flags

`-fvisibility=hidden` is recommended for pybind11 to avoid symbol conflicts.

## Outputs

| Package | Description |
|---------|-------------|
| `mathext` | Raw shared library |
| `pythonPackage` | Python-installable package |
| `pythonEnv` | Python environment with extension |

## Next Steps

- See `library/` for basic shared library examples
- See `plugins/` for dlopen-based plugin loading
