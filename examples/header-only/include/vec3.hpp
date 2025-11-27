#pragma once

#include <cmath>

namespace math {

// A simple 3D vector class - entirely in the header
template<typename T>
struct Vec3 {
  T x, y, z;

  constexpr Vec3() : x(0), y(0), z(0) {}
  constexpr Vec3(T x, T y, T z) : x(x), y(y), z(z) {}

  constexpr Vec3 operator+(const Vec3& other) const {
    return Vec3(x + other.x, y + other.y, z + other.z);
  }

  constexpr Vec3 operator-(const Vec3& other) const {
    return Vec3(x - other.x, y - other.y, z - other.z);
  }

  constexpr Vec3 operator*(T scalar) const {
    return Vec3(x * scalar, y * scalar, z * scalar);
  }

  constexpr T dot(const Vec3& other) const {
    return x * other.x + y * other.y + z * other.z;
  }

  constexpr Vec3 cross(const Vec3& other) const {
    return Vec3(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x
    );
  }

  T length() const {
    return std::sqrt(dot(*this));
  }

  Vec3 normalized() const {
    T len = length();
    return len > 0 ? (*this) * (T(1) / len) : Vec3();
  }
};

// Common type aliases
using Vec3f = Vec3<float>;
using Vec3d = Vec3<double>;
using Vec3i = Vec3<int>;

}  // namespace math
