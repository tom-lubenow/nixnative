#include <iostream>
#include "version.h"

int main() {
  std::cout << "Simple Tool Example\n";
  std::cout << "===================\n\n";

  std::cout << "Version info (generated at build time):\n";
  std::cout << "  Full version: " << VERSION_STRING << "\n";
  std::cout << "  Major: " << VERSION_MAJOR << "\n";
  std::cout << "  Minor: " << VERSION_MINOR << "\n";
  std::cout << "  Patch: " << VERSION_PATCH << "\n";

  std::cout << "\nCode generation working!\n";
  return 0;
}
