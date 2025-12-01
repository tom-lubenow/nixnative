#include <iostream>
#include "greeter.h"
#include "utils.h"

int main() {
    ca_example::Greeter greeter("world");
    std::cout << greeter.greet() << std::endl;

    std::cout << "Lowercase: " << ca_example::make_lowercase("HELLO") << std::endl;
    std::cout << "Uppercase: " << ca_example::make_uppercase("hello") << std::endl;

    return 0;
}
