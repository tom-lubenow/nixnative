// Mixed C/C++/Rust Example
//
// Demonstrates linking Rust (staticlib), C, and C++ code together.

#include <iostream>
#include <string>
#include <cmath>

// C headers
extern "C" {
#include "rustlib.h"
#include "cwrapper.h"
}

// C++ wrapper class for Rust geometry operations
class Point {
public:
    double x, y;

    Point(double x = 0, double y = 0) : x(x), y(y) {}

    double distanceTo(const Point& other) const {
        // Use Rust's distance function
        return rust_distance(x, y, other.x, other.y);
    }

    friend std::ostream& operator<<(std::ostream& os, const Point& p) {
        os << "(" << p.x << ", " << p.y << ")";
        return os;
    }
};

// C++ string reversal using Rust
std::string reverseWithRust(const std::string& s) {
    char* reversed = rust_reverse_string(s.c_str());
    if (reversed == nullptr) {
        return "";
    }
    std::string result(reversed);
    rust_free_string(reversed);
    return result;
}

int main() {
    std::cout << "Mixed C/C++/Rust Example\n";
    std::cout << "========================\n\n";

    // Section 1: Direct Rust calls from C++
    std::cout << "=== Direct Rust Calls from C++ ===\n";
    std::cout << "rust_version(): " << rust_version() << "\n";
    std::cout << "rust_add(100, 200) = " << rust_add(100, 200) << "\n";
    std::cout << "rust_multiply(12, 12) = " << rust_multiply(12, 12) << "\n";
    std::cout << "rust_factorial(7) = " << rust_factorial(7) << "\n\n";

    // Section 2: C wrapper functions (C calling Rust, called from C++)
    std::cout << "=== C Wrapper Functions ===\n";
    c_print_rust_info();
    std::cout << "c_power(2, 10) = " << c_power(2, 10) << "\n";
    std::cout << "c_sum_range(1, 100) = " << c_sum_range(1, 100) << "\n\n";

    // Section 3: C++ class using Rust
    std::cout << "=== C++ Class Using Rust ===\n";
    Point p1(0, 0);
    Point p2(3, 4);
    Point p3(6, 8);

    std::cout << "p1 = " << p1 << "\n";
    std::cout << "p2 = " << p2 << "\n";
    std::cout << "p3 = " << p3 << "\n";
    std::cout << "p1.distanceTo(p2) = " << p1.distanceTo(p2) << " (uses Rust)\n";
    std::cout << "p2.distanceTo(p3) = " << p2.distanceTo(p3) << " (uses Rust)\n\n";

    // Section 4: String operations
    std::cout << "=== String Operations ===\n";
    std::string original = "Hello, mixed languages!";
    std::string reversed = reverseWithRust(original);
    std::cout << "Original: \"" << original << "\"\n";
    std::cout << "Reversed (via Rust): \"" << reversed << "\"\n\n";

    std::cout << "Mixed C/C++/Rust example completed successfully!\n";
    return 0;
}
