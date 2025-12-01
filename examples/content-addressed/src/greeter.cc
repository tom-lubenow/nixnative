#include "greeter.h"
#include "utils.h"

namespace ca_example {

Greeter::Greeter(const std::string& name) : name_(name) {}

std::string Greeter::greet() const {
    return "Hello, " + make_uppercase(name_) + "!";
}

}  // namespace ca_example
