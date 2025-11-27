// Python extension module demonstrating C++ integration
//
// This module provides basic math functions to Python.

#define PY_SSIZE_T_CLEAN
#include <Python.h>

// ==========================================================================
// Implementation Functions
// ==========================================================================

static long factorial_impl(int n) {
    if (n < 0) return -1;
    if (n <= 1) return 1;
    return n * factorial_impl(n - 1);
}

static long fibonacci_impl(int n) {
    if (n < 0) return -1;
    if (n <= 1) return n;
    return fibonacci_impl(n - 1) + fibonacci_impl(n - 2);
}

static bool is_prime_impl(int n) {
    if (n <= 1) return false;
    if (n <= 3) return true;
    if (n % 2 == 0 || n % 3 == 0) return false;
    for (int i = 5; i * i <= n; i += 6) {
        if (n % i == 0 || n % (i + 2) == 0) return false;
    }
    return true;
}

// ==========================================================================
// Python-Callable Functions
// ==========================================================================

// Add two integers
static PyObject* mathext_add(PyObject* self, PyObject* args) {
    int a, b;
    if (!PyArg_ParseTuple(args, "ii", &a, &b)) {
        return NULL;
    }
    return PyLong_FromLong(a + b);
}

// Multiply two integers
static PyObject* mathext_multiply(PyObject* self, PyObject* args) {
    int a, b;
    if (!PyArg_ParseTuple(args, "ii", &a, &b)) {
        return NULL;
    }
    return PyLong_FromLong(a * b);
}

// Compute factorial
static PyObject* mathext_factorial(PyObject* self, PyObject* args) {
    int n;
    if (!PyArg_ParseTuple(args, "i", &n)) {
        return NULL;
    }

    if (n < 0) {
        PyErr_SetString(PyExc_ValueError, "factorial not defined for negative numbers");
        return NULL;
    }

    return PyLong_FromLong(factorial_impl(n));
}

// Compute fibonacci number
static PyObject* mathext_fibonacci(PyObject* self, PyObject* args) {
    int n;
    if (!PyArg_ParseTuple(args, "i", &n)) {
        return NULL;
    }

    if (n < 0) {
        PyErr_SetString(PyExc_ValueError, "fibonacci not defined for negative numbers");
        return NULL;
    }

    return PyLong_FromLong(fibonacci_impl(n));
}

// Check if number is prime
static PyObject* mathext_is_prime(PyObject* self, PyObject* args) {
    int n;
    if (!PyArg_ParseTuple(args, "i", &n)) {
        return NULL;
    }

    if (is_prime_impl(n)) {
        Py_RETURN_TRUE;
    } else {
        Py_RETURN_FALSE;
    }
}

// Get version info
static PyObject* mathext_version(PyObject* self, PyObject* args) {
    return PyUnicode_FromString("1.0.0");
}

// ==========================================================================
// Module Definition
// ==========================================================================

static PyMethodDef MathextMethods[] = {
    {"add", mathext_add, METH_VARARGS,
     "add(a, b) -> int\n\nAdd two integers."},

    {"multiply", mathext_multiply, METH_VARARGS,
     "multiply(a, b) -> int\n\nMultiply two integers."},

    {"factorial", mathext_factorial, METH_VARARGS,
     "factorial(n) -> int\n\nCompute n! (factorial)."},

    {"fibonacci", mathext_fibonacci, METH_VARARGS,
     "fibonacci(n) -> int\n\nCompute the nth Fibonacci number."},

    {"is_prime", mathext_is_prime, METH_VARARGS,
     "is_prime(n) -> bool\n\nCheck if n is a prime number."},

    {"version", mathext_version, METH_NOARGS,
     "version() -> str\n\nReturn the module version."},

    {NULL, NULL, 0, NULL}  // Sentinel
};

static struct PyModuleDef mathextmodule = {
    PyModuleDef_HEAD_INIT,
    "mathext",                              // Module name
    "Math extension module for nixnative",  // Module docstring
    -1,                                     // Per-interpreter state size
    MathextMethods                          // Method table
};

// Module initialization function
// Must be named PyInit_<module_name>
PyMODINIT_FUNC PyInit_mathext(void) {
    return PyModule_Create(&mathextmodule);
}
