#pragma once

#include <string>
#include <string_view>

namespace myapp {

enum class LogLevel {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
};

class Logger {
public:
    static Logger& instance();

    void setLevel(LogLevel level);
    LogLevel getLevel() const;

    void debug(std::string_view msg);
    void info(std::string_view msg);
    void warn(std::string_view msg);
    void error(std::string_view msg);

    // Initialize with configuration
    void init(int level);

    // Get level name
    static const char* levelName(LogLevel level);

private:
    Logger() = default;
    LogLevel level_ = LogLevel::INFO;
};

// Convenience macros
#define LOG_DEBUG(msg) myapp::Logger::instance().debug(msg)
#define LOG_INFO(msg) myapp::Logger::instance().info(msg)
#define LOG_WARN(msg) myapp::Logger::instance().warn(msg)
#define LOG_ERROR(msg) myapp::Logger::instance().error(msg)

}  // namespace myapp
