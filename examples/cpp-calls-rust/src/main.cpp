#include <iostream>
#include "rust_math.h"

int main() {
    std::cout << "C++ calling Rust functions:\n";
    std::cout << "  rust_add(3, 4) = " << rust_add(3, 4) << "\n";
    std::cout << "  rust_multiply(6, 7) = " << rust_multiply(6, 7) << "\n";
    std::cout << "  rust_factorial(10) = " << rust_factorial(10) << "\n";
    return 0;
}
