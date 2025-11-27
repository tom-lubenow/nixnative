#pragma once

#include <string>
#include <string_view>

namespace myapp {

struct Config {
    std::string appName;
    std::string version;
    bool debugMode;
    std::string databasePath;
    int logLevel;

    // Load configuration (from environment or defaults)
    static Config load();

    // Print configuration
    void print() const;
};

// Global configuration access
const Config& getConfig();

// Version info
constexpr std::string_view VERSION = "1.0.0";
constexpr std::string_view APP_NAME = "myapp";

}  // namespace myapp
