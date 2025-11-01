#include <cmath>
#include <iostream>

#include "rust_crane_bridge.hpp"

int main() {
  const auto dot = rust_crane_dot(2, 5);
  const auto norm = rust_crane_norm(3, 4);

  std::cout << "rust_crane_dot(2, 5) = " << dot << '\n';
  std::cout << "rust_crane_norm(3, 4) = " << norm << '\n';

  if (dot != 10 || std::abs(norm - 5.0) > 1e-9) {
    std::cerr << "unexpected result from Rust (crane) interop\n";
    return 1;
  }
  return 0;
}
