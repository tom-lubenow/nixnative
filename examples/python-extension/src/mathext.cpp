// Python C++ extension using pybind11
//
// Demonstrates building a Python module with nixnative

#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <cmath>
#include <vector>
#include <numeric>

namespace py = pybind11;

// Simple math functions
int add(int a, int b) {
    return a + b;
}

int multiply(int a, int b) {
    return a * b;
}

double power(double base, double exp) {
    return std::pow(base, exp);
}

// Vector operations
double dot_product(const std::vector<double>& a, const std::vector<double>& b) {
    if (a.size() != b.size()) {
        throw std::invalid_argument("Vectors must have the same length");
    }
    return std::inner_product(a.begin(), a.end(), b.begin(), 0.0);
}

std::vector<double> scale_vector(const std::vector<double>& v, double scalar) {
    std::vector<double> result(v.size());
    for (size_t i = 0; i < v.size(); ++i) {
        result[i] = v[i] * scalar;
    }
    return result;
}

// A simple class to demonstrate class bindings
class Calculator {
public:
    Calculator(double initial = 0.0) : value_(initial) {}

    void add(double x) { value_ += x; }
    void subtract(double x) { value_ -= x; }
    void multiply(double x) { value_ *= x; }
    void divide(double x) {
        if (x == 0.0) {
            throw std::runtime_error("Division by zero");
        }
        value_ /= x;
    }

    void reset() { value_ = 0.0; }
    double value() const { return value_; }

private:
    double value_;
};

PYBIND11_MODULE(mathext, m) {
    m.doc() = "A math extension module built with nixnative and pybind11";

    // Basic functions
    m.def("add", &add, "Add two integers",
          py::arg("a"), py::arg("b"));
    m.def("multiply", &multiply, "Multiply two integers",
          py::arg("a"), py::arg("b"));
    m.def("power", &power, "Raise base to exponent",
          py::arg("base"), py::arg("exp"));

    // Vector operations
    m.def("dot_product", &dot_product, "Compute dot product of two vectors",
          py::arg("a"), py::arg("b"));
    m.def("scale_vector", &scale_vector, "Scale a vector by a scalar",
          py::arg("v"), py::arg("scalar"));

    // Calculator class
    py::class_<Calculator>(m, "Calculator")
        .def(py::init<double>(), py::arg("initial") = 0.0)
        .def("add", &Calculator::add)
        .def("subtract", &Calculator::subtract)
        .def("multiply", &Calculator::multiply)
        .def("divide", &Calculator::divide)
        .def("reset", &Calculator::reset)
        .def_property_readonly("value", &Calculator::value)
        .def("__repr__", [](const Calculator& c) {
            return "<Calculator value=" + std::to_string(c.value()) + ">";
        });
}
