#include "math_ext.hpp"
#include "util.hpp"
#include <limits>
#include <cmath>

namespace math_ext {

core::Point centroid(const std::vector<core::Point>& points) {
  if (points.empty()) {
    return core::Point(0, 0);
  }

  double sumX = 0, sumY = 0;
  for (const auto& p : points) {
    sumX += p.x;
    sumY += p.y;
  }

  return core::Point(sumX / points.size(), sumY / points.size());
}

core::Rect boundingBox(const std::vector<core::Point>& points) {
  if (points.empty()) {
    return core::Rect(core::Point(0, 0), 0, 0);
  }

  double minX = std::numeric_limits<double>::max();
  double minY = std::numeric_limits<double>::max();
  double maxX = std::numeric_limits<double>::lowest();
  double maxY = std::numeric_limits<double>::lowest();

  for (const auto& p : points) {
    minX = std::min(minX, p.x);
    minY = std::min(minY, p.y);
    maxX = std::max(maxX, p.x);
    maxY = std::max(maxY, p.y);
  }

  return core::Rect(core::Point(minX, minY), maxX - minX, maxY - minY);
}

double perimeter(const std::vector<core::Point>& points) {
  if (points.size() < 2) {
    return 0;
  }

  double total = 0;
  for (size_t i = 0; i < points.size(); ++i) {
    size_t next = (i + 1) % points.size();
    total += points[i].distanceTo(points[next]);
  }

  return total;
}

double polygonArea(const std::vector<core::Point>& points) {
  if (points.size() < 3) {
    return 0;
  }

  // Shoelace formula
  double area = 0;
  for (size_t i = 0; i < points.size(); ++i) {
    size_t next = (i + 1) % points.size();
    area += points[i].x * points[next].y;
    area -= points[next].x * points[i].y;
  }

  return std::abs(area) / 2.0;
}

}  // namespace math_ext
