#pragma once

#include <string>

namespace core {

// Core geometry types - depends on libutil
struct Point {
  double x, y;

  Point(double x = 0, double y = 0);
  double distanceTo(const Point& other) const;
  std::string toString(int precision = 2) const;
};

struct Rect {
  Point origin;
  double width, height;

  Rect(Point origin, double width, double height);
  double area() const;
  bool contains(const Point& p) const;
  std::string toString(int precision = 2) const;
};

}  // namespace core
