#include "core.hpp"
#include "util.hpp"
#include <cmath>

namespace core {

Point::Point(double x, double y) : x(x), y(y) {}

double Point::distanceTo(const Point& other) const {
  double dx = x - other.x;
  double dy = y - other.y;
  return std::sqrt(dx * dx + dy * dy);
}

std::string Point::toString(int precision) const {
  return "(" + util::formatNumber(x, precision) + ", " +
         util::formatNumber(y, precision) + ")";
}

Rect::Rect(Point origin, double width, double height)
    : origin(origin), width(width), height(height) {}

double Rect::area() const {
  return width * height;
}

bool Rect::contains(const Point& p) const {
  return p.x >= origin.x && p.x <= origin.x + width &&
         p.y >= origin.y && p.y <= origin.y + height;
}

std::string Rect::toString(int precision) const {
  return "Rect(" + origin.toString(precision) + ", " +
         util::formatNumber(width, precision) + "x" +
         util::formatNumber(height, precision) + ")";
}

}  // namespace core
