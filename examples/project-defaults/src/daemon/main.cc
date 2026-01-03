#include <iostream>
#include "utils.h"

#ifdef DAEMON_MODE
#define MODE_STR "daemon"
#else
#define MODE_STR "foreground"
#endif

int main() {
    std::cout << common::formatMessage("Running in " MODE_STR " mode") << std::endl;
    return 0;
}
