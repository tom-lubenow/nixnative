#ifndef MATHLIB_H
#define MATHLIB_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Add two integers
int32_t cpp_add(int32_t a, int32_t b);

// Multiply two integers
int32_t cpp_multiply(int32_t a, int32_t b);

// Compute fibonacci number
uint64_t cpp_fibonacci(uint32_t n);

#ifdef __cplusplus
}
#endif

#endif // MATHLIB_H
