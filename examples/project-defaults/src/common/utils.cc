#include "utils.h"
#include <sstream>

// Stringify helper
#define STRINGIFY2(x) #x
#define STRINGIFY(x) STRINGIFY2(x)

#ifdef PROJECT_VERSION
#define VERSION_STR STRINGIFY(PROJECT_VERSION)
#else
#define VERSION_STR "unknown"
#endif

namespace common {

std::string getVersion() {
    return VERSION_STR;
}

std::string formatMessage(const std::string& msg) {
    return "[" + getVersion() + "] " + msg;
}

}  // namespace common
