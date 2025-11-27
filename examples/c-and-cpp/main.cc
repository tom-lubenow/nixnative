#include <iostream>
#include <iomanip>

// Include both C and C++ headers
#include "clib.h"         // C interface
#include "cppwrapper.hpp" // C++ wrapper

int main() {
  std::cout << "Mixed C/C++ Example\n";
  std::cout << "===================\n\n";

  // Using the C library directly from C++
  std::cout << "=== Direct C API usage ===\n";
  Vec2 a = vec2_create(3.0, 4.0);
  Vec2 b = vec2_create(1.0, 2.0);
  Vec2 sum = vec2_add(a, b);

  std::cout << "a = (" << a.x << ", " << a.y << ")\n";
  std::cout << "b = (" << b.x << ", " << b.y << ")\n";
  std::cout << "a + b = (" << sum.x << ", " << sum.y << ")\n";
  std::cout << "|a| = " << vec2_length(a) << "\n";

  // Using the C string function
  char str[] = "Hello";
  std::cout << "\nOriginal string: " << str << "\n";
  clib_reverse(str);
  std::cout << "Reversed (C): " << str << "\n";

  // Using the C++ wrapper
  std::cout << "\n=== C++ wrapper usage ===\n";
  wrapper::Vector2D v1(3.0, 4.0);
  wrapper::Vector2D v2(1.0, 2.0);

  std::cout << "v1 = " << v1 << "\n";
  std::cout << "v2 = " << v2 << "\n";
  std::cout << "v1 + v2 = " << (v1 + v2) << "\n";
  std::cout << "v1 * 2 = " << (v1 * 2.0) << "\n";
  std::cout << "v1 . v2 = " << v1.dot(v2) << "\n";
  std::cout << "|v1| = " << v1.length() << "\n";

  // C++ string reversal
  std::string cppStr = "World";
  std::cout << "\nOriginal string: " << cppStr << "\n";
  std::cout << "Reversed (C++): " << wrapper::reverse(cppStr) << "\n";

  std::cout << "\nMixed C/C++ working correctly!\n";
  return 0;
}
