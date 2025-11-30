/* C wrapper header */

#ifndef CWRAPPER_H
#define CWRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

/* Higher-level C functions that use the Rust library */
int c_power(int base, int exp);
int c_sum_range(int start, int end);
void c_print_rust_info(void);

#ifdef __cplusplus
}
#endif

#endif /* CWRAPPER_H */
