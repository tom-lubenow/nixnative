#include <iostream>
#include <string>
#include <cstring>

#include "config.h"
#include "logger.h"
#include "database.h"

void printHelp() {
    std::cout << "MyApp CLI v" << myapp::VERSION << "\n";
    std::cout << "================\n";
    std::cout << "Usage: myapp-cli [options]\n\n";
    std::cout << "Options:\n";
    std::cout << "  --help     Show this help\n";
    std::cout << "  --version  Show version\n";
    std::cout << "  --config   Show configuration\n";
    std::cout << "  --demo     Run demo operations\n";
}

void printVersion() {
    std::cout << myapp::APP_NAME << " version " << myapp::VERSION << "\n";
}

void runDemo() {
    auto& db = myapp::Database::instance();

    std::cout << "\nDemo: Database operations\n";
    std::cout << "-------------------------\n";

    db.set("user", "alice");
    db.set("role", "admin");
    db.set("active", "true");

    std::cout << "Stored 3 entries\n";
    std::cout << "Keys: ";
    for (const auto& key : db.keys()) {
        std::cout << key << " ";
    }
    std::cout << "\n";

    if (auto val = db.get("user")) {
        std::cout << "user = " << *val << "\n";
    }

    db.remove("active");
    std::cout << "Removed 'active', size now: " << db.size() << "\n";
}

int main(int argc, char* argv[]) {
    // Initialize from configuration
    const auto& config = myapp::getConfig();
    myapp::Logger::instance().init(config.logLevel);

    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0) {
            printHelp();
            return 0;
        }
        if (std::strcmp(argv[i], "--version") == 0 || std::strcmp(argv[i], "-v") == 0) {
            printVersion();
            return 0;
        }
        if (std::strcmp(argv[i], "--config") == 0) {
            config.print();
            return 0;
        }
        if (std::strcmp(argv[i], "--demo") == 0) {
            myapp::Database::instance().connect(config.databasePath);
            runDemo();
            return 0;
        }
    }

    // Default: show status
    printHelp();
    std::cout << "\n";

    std::cout << "Configuration loaded: debug=" << (config.debugMode ? "true" : "false")
              << ", db=" << config.databasePath << "\n";

    LOG_INFO("Logger initialized: level=" + std::string(myapp::Logger::levelName(myapp::Logger::instance().getLevel())));

    myapp::Database::instance().connect(config.databasePath);
    std::cout << "Database connected: " << myapp::Database::instance().getPath() << "\n";

    std::cout << "CLI ready!\n";
    return 0;
}
