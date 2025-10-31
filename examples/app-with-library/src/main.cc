#include <iostream>
#include <string>

#include <zlib.h>

#include "generated/build_info.hpp"
#include "math.hpp"

int main() {
  std::cout << "2 + 3 = " << add(2, 3) << "\n";
  std::cout << "4 * 5 = " << mul(4, 5) << "\n";
  std::cout << "build summary: " << generated::build_summary() << "\n";
  std::cout << "zlib version: " << zlibVersion() << "\n";
  return 0;
}
