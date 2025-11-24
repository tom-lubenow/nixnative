#include "header.h"
#include <iostream>

int main() {
  int a = 10;
  int b = 32;
  int result = zig_add(a, b);

  std::cout << "Calling Zig from C++: " << a << " + " << b << " = " << result
            << std::endl;

  if (result != 42) {
    std::cerr << "Error: Expected 42!" << std::endl;
    return 1;
  }

  return 0;
}
