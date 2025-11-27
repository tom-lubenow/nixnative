#include <iostream>
#include <string>

// Detect compiler at compile time
#if defined(__clang__)
  #define COMPILER_NAME "clang"
  #define COMPILER_VERSION __clang_major__
#elif defined(__GNUC__)
  #define COMPILER_NAME "gcc"
  #define COMPILER_VERSION __GNUC__
#else
  #define COMPILER_NAME "unknown"
  #define COMPILER_VERSION 0
#endif

// Detect optimization level
#if defined(__OPTIMIZE__)
  #if __OPTIMIZE__ >= 3
    #define OPT_LEVEL "O3"
  #elif __OPTIMIZE__ >= 2
    #define OPT_LEVEL "O2"
  #elif __OPTIMIZE__ >= 1
    #define OPT_LEVEL "O1"
  #else
    #define OPT_LEVEL "O0"
  #endif
#else
  #define OPT_LEVEL "O0"
#endif

// Simple function to prevent everything being optimized away
int compute(int n) {
    int result = 0;
    for (int i = 0; i < n; ++i) {
        result += i * i;
    }
    return result;
}

int main(int argc, char* argv[]) {
    std::cout << "Compiler: " << COMPILER_NAME << " " << COMPILER_VERSION << "\n";
    std::cout << "Optimization: " << OPT_LEVEL << "\n";

    int n = (argc > 1) ? std::stoi(argv[1]) : 100;
    std::cout << "compute(" << n << ") = " << compute(n) << "\n";

    return 0;
}
