#pragma once

#include <cstdint>

extern "C" {
std::int64_t rust_add(std::int64_t lhs, std::int64_t rhs);
std::int64_t rust_scale(std::int64_t value, std::int64_t factor);
}
