#pragma once

#include "core.hpp"
#include <vector>

namespace math_ext {

// Extended math operations - depends on libcore (and transitively libutil)

// Calculate the centroid of a set of points
core::Point centroid(const std::vector<core::Point>& points);

// Calculate the bounding box of a set of points
core::Rect boundingBox(const std::vector<core::Point>& points);

// Calculate the perimeter of a polygon defined by points
double perimeter(const std::vector<core::Point>& points);

// Calculate the area of a polygon using the shoelace formula
double polygonArea(const std::vector<core::Point>& points);

}  // namespace math_ext
