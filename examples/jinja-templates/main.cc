#include <iostream>
#include <string>

#include "config.h"
#include "messages.h"
#include "Status.h"

int main() {
    std::cout << "Jinja Templates Example\n";
    std::cout << "=======================\n\n";

    // Using generated configuration
    std::cout << "Configuration:\n";
    std::cout << "  App Name: " << config::APP_NAME << "\n";
    std::cout << "  Version: " << config::VERSION << "\n";
    std::cout << "  Debug: " << (config::DEBUG_ENABLED ? "enabled" : "disabled") << "\n";
    std::cout << "  Max Connections: " << config::MAX_CONNECTIONS << "\n";

    // Using generated messages
    std::cout << "\nMessages:\n";
    std::cout << "  WELCOME: " << messages::WELCOME << "\n";
    std::cout << "  GOODBYE: " << messages::GOODBYE << "\n";
    std::cout << "  ERROR: " << messages::ERROR_MSG << "\n";

    // Using generated enum
    std::cout << "\nStatus enum values: ";
    std::cout << "IDLE, RUNNING, PAUSED, STOPPED\n";

    // Verify enum works
    app::Status status = app::Status::RUNNING;
    (void)status;  // Suppress unused warning

    std::cout << "\nAll templates working correctly!\n";
    return 0;
}
