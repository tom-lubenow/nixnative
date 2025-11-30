/* Rust library FFI header */

#ifndef RUSTLIB_H
#define RUSTLIB_H

#ifdef __cplusplus
extern "C" {
#endif

/* Math operations */
int rust_add(int a, int b);
int rust_multiply(int a, int b);
int rust_factorial(int n);

/* Geometry */
double rust_distance(double x1, double y1, double x2, double y2);

/* String operations */
char* rust_reverse_string(const char* s);
void rust_free_string(char* s);

/* Version info */
const char* rust_version();

#ifdef __cplusplus
}
#endif

#endif /* RUSTLIB_H */
