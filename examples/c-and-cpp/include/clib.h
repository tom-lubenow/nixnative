/* C library header - pure C interface */
#ifndef CLIB_H
#define CLIB_H

#ifdef __cplusplus
extern "C" {
#endif

/* Structure for 2D vectors */
typedef struct {
  double x;
  double y;
} Vec2;

/* Vector operations */
Vec2 vec2_create(double x, double y);
Vec2 vec2_add(Vec2 a, Vec2 b);
Vec2 vec2_scale(Vec2 v, double scalar);
double vec2_dot(Vec2 a, Vec2 b);
double vec2_length(Vec2 v);

/* String operations */
int clib_strlen(const char* str);
void clib_reverse(char* str);

#ifdef __cplusplus
}
#endif

#endif /* CLIB_H */
