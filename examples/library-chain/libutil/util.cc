#include "util.hpp"
#include <sstream>
#include <iomanip>

namespace util {

std::string formatNumber(double value, int precision) {
  std::ostringstream oss;
  oss << std::fixed << std::setprecision(precision) << value;
  return oss.str();
}

double clamp(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

}  // namespace util
