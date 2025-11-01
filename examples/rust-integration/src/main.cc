#include <iostream>

#include "rust_bridge.hpp"

int main() {
  const auto sum = rust_add(21, 21);
  const auto scaled = rust_scale(7, 3);

  std::cout << "rust_add(21, 21) = " << sum << '\n';
  std::cout << "rust_scale(7, 3) = " << scaled << '\n';

  if (sum != 42 || scaled != 21) {
    std::cerr << "unexpected result from Rust interop\n";
    return 1;
  }
  return 0;
}
