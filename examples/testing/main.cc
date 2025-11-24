#include <iostream>
#include <string>

int main(int argc, char *argv[]) {
  if (argc > 1) {
    std::cout << "Hello " << argv[1] << std::endl;
  } else {
    std::cout << "Hello Test" << std::endl;
  }
  return 0;
}
