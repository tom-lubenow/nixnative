#include "mathlib.h"

extern "C" {

int32_t cpp_add(int32_t a, int32_t b) {
    return a + b;
}

int32_t cpp_multiply(int32_t a, int32_t b) {
    return a * b;
}

uint64_t cpp_fibonacci(uint32_t n) {
    if (n <= 1) return n;
    uint64_t a = 0, b = 1;
    for (uint32_t i = 2; i <= n; i++) {
        uint64_t next = a + b;
        a = b;
        b = next;
    }
    return b;
}

}
