#include <iostream>
#include <vector>

#include "math_ext.hpp"
#include "core.hpp"
#include "util.hpp"

int main() {
  std::cout << "Library Chain Demo\n";
  std::cout << "==================\n\n";

  // Create a triangle
  std::vector<core::Point> triangle = {
    core::Point(0, 0),
    core::Point(4, 0),
    core::Point(2, 3)
  };

  std::cout << "Triangle vertices:\n";
  for (size_t i = 0; i < triangle.size(); ++i) {
    std::cout << "  P" << i << " = " << triangle[i].toString() << "\n";
  }

  // Use libmath (which uses libcore which uses libutil)
  auto center = math_ext::centroid(triangle);
  auto bbox = math_ext::boundingBox(triangle);
  double perim = math_ext::perimeter(triangle);
  double area = math_ext::polygonArea(triangle);

  std::cout << "\nComputed properties:\n";
  std::cout << "  Centroid: " << center.toString() << "\n";
  std::cout << "  Bounding box: " << bbox.toString() << "\n";
  std::cout << "  Perimeter: " << util::formatNumber(perim, 2) << "\n";
  std::cout << "  Area: " << util::formatNumber(area, 2) << "\n";

  // Direct libcore usage
  std::cout << "\nDistance from P0 to P1: "
            << util::formatNumber(triangle[0].distanceTo(triangle[1]), 2) << "\n";

  std::cout << "\nLibrary chain working correctly!\n";
  return 0;
}
