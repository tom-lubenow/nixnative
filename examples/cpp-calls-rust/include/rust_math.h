#ifndef RUST_MATH_H
#define RUST_MATH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t rust_add(int32_t a, int32_t b);
int32_t rust_multiply(int32_t a, int32_t b);
uint64_t rust_factorial(uint32_t n);

#ifdef __cplusplus
}
#endif

#endif // RUST_MATH_H
