#include <iostream>
#include "math.h"

int main() {
    std::cout << "Math Library Demo\n";
    std::cout << "=================\n";
    std::cout << "5 + 3 = " << math::add(5, 3) << "\n";
    std::cout << "5 * 3 = " << math::multiply(5, 3) << "\n";
    std::cout << "5! = " << math::factorial(5) << "\n";
    return 0;
}
