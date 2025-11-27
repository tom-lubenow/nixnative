#pragma once

// C++ wrapper around the C library
// Provides a more idiomatic C++ interface

#include "clib.h"
#include <string>
#include <ostream>

namespace wrapper {

// C++ class wrapping the C Vec2 struct
class Vector2D {
public:
  Vector2D() : vec_(vec2_create(0, 0)) {}
  Vector2D(double x, double y) : vec_(vec2_create(x, y)) {}
  explicit Vector2D(Vec2 v) : vec_(v) {}

  double x() const { return vec_.x; }
  double y() const { return vec_.y; }
  double length() const { return vec2_length(vec_); }
  double dot(const Vector2D& other) const { return vec2_dot(vec_, other.vec_); }

  Vector2D operator+(const Vector2D& other) const {
    return Vector2D(vec2_add(vec_, other.vec_));
  }

  Vector2D operator*(double scalar) const {
    return Vector2D(vec2_scale(vec_, scalar));
  }

  // Allow access to underlying C struct for interop
  const Vec2& raw() const { return vec_; }

private:
  Vec2 vec_;
};

inline std::ostream& operator<<(std::ostream& os, const Vector2D& v) {
  return os << "(" << v.x() << ", " << v.y() << ")";
}

// C++ string wrapper using the C functions
inline std::string reverse(const std::string& s) {
  std::string result = s;
  clib_reverse(&result[0]);
  return result;
}

}  // namespace wrapper
