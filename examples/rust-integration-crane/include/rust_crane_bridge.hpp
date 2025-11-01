#pragma once

#include <cstdint>

extern "C" {
std::int64_t rust_crane_dot(std::int64_t lhs, std::int64_t rhs);
double rust_crane_norm(std::int64_t x, std::int64_t y);
}
