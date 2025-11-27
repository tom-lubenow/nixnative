#include "logger.h"
#include <iostream>
#include <ctime>

namespace myapp {

Logger& Logger::instance() {
    static Logger logger;
    return logger;
}

void Logger::setLevel(LogLevel level) {
    level_ = level;
}

LogLevel Logger::getLevel() const {
    return level_;
}

void Logger::init(int level) {
    level_ = static_cast<LogLevel>(level);
}

const char* Logger::levelName(LogLevel level) {
    switch (level) {
        case LogLevel::DEBUG: return "DEBUG";
        case LogLevel::INFO:  return "INFO";
        case LogLevel::WARN:  return "WARN";
        case LogLevel::ERROR: return "ERROR";
        default: return "UNKNOWN";
    }
}

static void logMessage(LogLevel level, std::string_view msg) {
    // Get current time
    std::time_t now = std::time(nullptr);
    char timeStr[20];
    std::strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", std::localtime(&now));

    std::cout << "[" << timeStr << "] "
              << "[" << Logger::levelName(level) << "] "
              << msg << "\n";
}

void Logger::debug(std::string_view msg) {
    if (level_ <= LogLevel::DEBUG) {
        logMessage(LogLevel::DEBUG, msg);
    }
}

void Logger::info(std::string_view msg) {
    if (level_ <= LogLevel::INFO) {
        logMessage(LogLevel::INFO, msg);
    }
}

void Logger::warn(std::string_view msg) {
    if (level_ <= LogLevel::WARN) {
        logMessage(LogLevel::WARN, msg);
    }
}

void Logger::error(std::string_view msg) {
    if (level_ <= LogLevel::ERROR) {
        logMessage(LogLevel::ERROR, msg);
    }
}

}  // namespace myapp
