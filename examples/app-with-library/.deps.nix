{
  schema = 1;
  units = {
    "generated/build_info.cc" = {
      dependencies = [
        "generated/build_info.cc"
        "generated/build_info.hpp"
      ];
    };
    "src/main.cc" = {
      dependencies = [
        "src/main.cc"
        "include/math.hpp"
      ];
    };
    "src/math.cc" = {
      dependencies = [
        "src/math.cc"
        "include/math.hpp"
      ];
    };
  };
}
