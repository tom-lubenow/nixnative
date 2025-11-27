#include <iostream>
#include "vec3.hpp"

int main() {
  math::Vec3f a(1.0f, 2.0f, 3.0f);
  math::Vec3f b(4.0f, 5.0f, 6.0f);

  auto sum = a + b;
  auto dot = a.dot(b);
  auto cross = a.cross(b);

  std::cout << "a = (" << a.x << ", " << a.y << ", " << a.z << ")\n";
  std::cout << "b = (" << b.x << ", " << b.y << ", " << b.z << ")\n";
  std::cout << "a + b = (" << sum.x << ", " << sum.y << ", " << sum.z << ")\n";
  std::cout << "a . b = " << dot << "\n";
  std::cout << "a x b = (" << cross.x << ", " << cross.y << ", " << cross.z << ")\n";
  std::cout << "|a| = " << a.length() << "\n";

  return 0;
}
