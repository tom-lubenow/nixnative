#include <iostream>

#include "math.hpp"
#include "generated/version.hpp"

int main() {
  std::cout << "2 + 3 = " << add(2, 3) << "\n";
  std::cout << "4 * 5 = " << mul(4, 5) << "\n";
  std::cout << "generated version = " << generated_version() << "\n";
  return 0;
}
