#include "config.h"
#include <iostream>
#include <cstdlib>

namespace myapp {

static Config globalConfig;
static bool configLoaded = false;

Config Config::load() {
    Config cfg;
    cfg.appName = std::string(APP_NAME);
    cfg.version = std::string(VERSION);

    // Check environment variables
    const char* debug = std::getenv("MYAPP_DEBUG");
    cfg.debugMode = (debug != nullptr && std::string(debug) == "1");

    const char* dbPath = std::getenv("MYAPP_DB");
    cfg.databasePath = dbPath ? dbPath : ":memory:";

    const char* logLevelStr = std::getenv("MYAPP_LOG_LEVEL");
    cfg.logLevel = logLevelStr ? std::atoi(logLevelStr) : 1;  // Default: INFO

    return cfg;
}

void Config::print() const {
    std::cout << "Configuration:\n";
    std::cout << "  App: " << appName << " v" << version << "\n";
    std::cout << "  Debug: " << (debugMode ? "enabled" : "disabled") << "\n";
    std::cout << "  Database: " << databasePath << "\n";
    std::cout << "  Log Level: " << logLevel << "\n";
}

const Config& getConfig() {
    if (!configLoaded) {
        globalConfig = Config::load();
        configLoaded = true;
    }
    return globalConfig;
}

}  // namespace myapp
