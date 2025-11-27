# Python Extension Example

This example demonstrates building Python C/C++ extension modules using nixnative.

## What This Demonstrates

- Building Python extension modules (`.so`/`.pyd`)
- Proper Python include paths and linking
- Packaging for use with Python's import system
- Using `native.sharedLib` with Python-specific configuration

## Project Structure

```
python-extension/
├── flake.nix           # Build definitions
├── src/
│   ├── mathmodule.cc   # C++ extension implementation
│   └── mathmodule.h    # Header file
├── test_math.py        # Python test script
└── README.md
```

## Build and Test

```sh
# Build the extension
nix build

# Test with Python
nix develop
python3 test_math.py
```

Expected output:
```
Testing mathext module...
add(2, 3) = 5
multiply(4, 5) = 20
factorial(6) = 720
fibonacci(10) = 55
All tests passed!
```

## How It Works

### 1. Create the Extension Source

```cpp
// src/mathmodule.cc
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* mathext_add(PyObject* self, PyObject* args) {
    int a, b;
    if (!PyArg_ParseTuple(args, "ii", &a, &b)) {
        return NULL;
    }
    return PyLong_FromLong(a + b);
}

static PyMethodDef MathMethods[] = {
    {"add", mathext_add, METH_VARARGS, "Add two numbers"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef mathmodule = {
    PyModuleDef_HEAD_INIT,
    "mathext",
    "Math extension module",
    -1,
    MathMethods
};

PyMODINIT_FUNC PyInit_mathext(void) {
    return PyModule_Create(&mathmodule);
}
```

### 2. Build as Shared Library

```nix
# Wrap Python for include paths
pythonLib = native.pkgConfig.makeLibrary {
  name = "python";
  packages = [ pkgs.python3 ];
  modules = [ "python3" ];
};

# Build the extension
mathext = native.sharedLib {
  name = "mathext";
  root = ./.;
  sources = [ "src/mathmodule.cc" ];
  libraries = [ pythonLib ];

  # Python extensions have specific naming requirements
  extraLdflags = if pkgs.stdenv.isDarwin
    then [ "-undefined" "dynamic_lookup" ]
    else [ ];
};
```

### 3. Create a Python Package

```nix
# Wrap for Python import
pythonPackage = pkgs.runCommand "mathext-python" {} ''
  mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages
  cp ${mathext.sharedLibrary} $out/lib/python${pkgs.python3.pythonVersion}/site-packages/mathext${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
'';
```

## Python C API Basics

### Parsing Arguments

```cpp
// Parse two integers
int a, b;
if (!PyArg_ParseTuple(args, "ii", &a, &b)) {
    return NULL;
}

// Format codes:
// i - int
// l - long
// d - double
// s - string (char*)
// O - PyObject*
```

### Returning Values

```cpp
// Return integer
return PyLong_FromLong(42);

// Return float
return PyFloat_FromDouble(3.14);

// Return string
return PyUnicode_FromString("hello");

// Return None
Py_RETURN_NONE;

// Return tuple
return Py_BuildValue("(ii)", 1, 2);
```

### Error Handling

```cpp
if (error_condition) {
    PyErr_SetString(PyExc_ValueError, "Error message");
    return NULL;
}
```

## Module Definition

```cpp
// Method table
static PyMethodDef ModuleMethods[] = {
    {"func_name", func_impl, METH_VARARGS, "Docstring"},
    {"func2", func2_impl, METH_VARARGS | METH_KEYWORDS, "With kwargs"},
    {NULL, NULL, 0, NULL}  // Sentinel
};

// Module definition
static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "module_name",        // Module name
    "Module docstring",   // Module docstring
    -1,                   // Per-interpreter state size (-1 = global)
    ModuleMethods
};

// Initialization function
PyMODINIT_FUNC PyInit_module_name(void) {
    return PyModule_Create(&module);
}
```

## Platform Notes

### Linux

Extensions use `.so` suffix and link normally.

### macOS

Extensions use `.so` suffix (not `.dylib`) and require:
```nix
extraLdflags = [ "-undefined" "dynamic_lookup" ];
```

This allows the extension to find Python symbols at runtime.

### Naming Convention

Python expects specific file names:
- Linux: `modulename.cpython-311-x86_64-linux-gnu.so` or `modulename.so`
- macOS: `modulename.cpython-311-darwin.so` or `modulename.so`

For simplicity, this example uses `modulename.so`.

## Alternative: pybind11

For C++ extensions, pybind11 provides a cleaner interface:

```cpp
#include <pybind11/pybind11.h>

int add(int a, int b) {
    return a + b;
}

PYBIND11_MODULE(mathext, m) {
    m.def("add", &add, "Add two numbers");
}
```

```nix
pybind11Lib = native.pkgConfig.makeLibrary {
  name = "pybind11";
  packages = [ pkgs.python3Packages.pybind11 pkgs.python3 ];
  modules = [ "pybind11" "python3" ];
};
```

## Integration with Nix Python

```nix
# Create a Python with the extension
pythonWithExt = pkgs.python3.withPackages (ps: [
  pythonPackage
  ps.numpy  # Other dependencies
]);

# Test script
testScript = pkgs.writeShellScriptBin "test-ext" ''
  ${pythonWithExt}/bin/python3 -c "import mathext; print(mathext.add(1, 2))"
'';
```

## Next Steps

- See Python C API documentation: https://docs.python.org/3/c-api/
- See pybind11 documentation: https://pybind11.readthedocs.io/
- See `library/` for static/shared library basics
- See `pkg-config/` for system library integration
