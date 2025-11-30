/* C wrapper that uses the Rust library */

#include "rustlib.h"
#include "cwrapper.h"
#include <stdio.h>
#include <string.h>

/* Compute power using repeated multiplication from Rust */
int c_power(int base, int exp) {
    int result = 1;
    for (int i = 0; i < exp; i++) {
        result = rust_multiply(result, base);
    }
    return result;
}

/* Sum a range of integers using Rust add */
int c_sum_range(int start, int end) {
    int sum = 0;
    for (int i = start; i <= end; i++) {
        sum = rust_add(sum, i);
    }
    return sum;
}

/* Print Rust library info */
void c_print_rust_info(void) {
    printf("Rust library version: %s\n", rust_version());
    printf("Calling Rust functions from C:\n");
    printf("  rust_add(10, 20) = %d\n", rust_add(10, 20));
    printf("  rust_multiply(6, 7) = %d\n", rust_multiply(6, 7));
    printf("  rust_factorial(5) = %d\n", rust_factorial(5));
}
