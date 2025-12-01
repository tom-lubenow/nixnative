#pragma once

#include <string>

namespace ca_example {

class Greeter {
public:
    explicit Greeter(const std::string& name);
    std::string greet() const;

private:
    std::string name_;
};

}  // namespace ca_example
