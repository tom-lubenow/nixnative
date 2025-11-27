#pragma once

#include <string>

namespace util {

// Simple utility functions at the bottom of the dependency chain
std::string formatNumber(double value, int precision);
double clamp(double value, double min, double max);

}  // namespace util
