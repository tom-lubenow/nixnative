/* C library implementation - compiled as C */
#include "clib.h"
#include <math.h>
#include <string.h>

Vec2 vec2_create(double x, double y) {
  Vec2 v;
  v.x = x;
  v.y = y;
  return v;
}

Vec2 vec2_add(Vec2 a, Vec2 b) {
  return vec2_create(a.x + b.x, a.y + b.y);
}

Vec2 vec2_scale(Vec2 v, double scalar) {
  return vec2_create(v.x * scalar, v.y * scalar);
}

double vec2_dot(Vec2 a, Vec2 b) {
  return a.x * b.x + a.y * b.y;
}

double vec2_length(Vec2 v) {
  return sqrt(vec2_dot(v, v));
}

int clib_strlen(const char* str) {
  int len = 0;
  while (str[len] != '\0') {
    len++;
  }
  return len;
}

void clib_reverse(char* str) {
  int len = clib_strlen(str);
  for (int i = 0; i < len / 2; i++) {
    char tmp = str[i];
    str[i] = str[len - 1 - i];
    str[len - 1 - i] = tmp;
  }
}
