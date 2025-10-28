#include <Python.h>

#include <string>

namespace {

PyObject* hello_ext_greet(PyObject*, PyObject* args) {
  const char* name = nullptr;
  if (!PyArg_ParseTuple(args, "s", &name)) {
    return nullptr;
  }
  std::string message = "hello, ";
  message += name;
  message += "!";
  return PyUnicode_FromStringAndSize(message.c_str(), static_cast<Py_ssize_t>(message.size()));
}

PyMethodDef kMethods[] = {
  {"greet", hello_ext_greet, METH_VARARGS, PyDoc_STR("Return a friendly greeting string." )},
  {nullptr, nullptr, 0, nullptr},
};

PyModuleDef kModule = {
  PyModuleDef_HEAD_INIT,
  "hello_ext",
  "Example C++ extension built with nixclang.",
  -1,
  kMethods,
};

}  // namespace

PyMODINIT_FUNC PyInit_hello_ext(void) {
  return PyModule_Create(&kModule);
}
