#include <iostream>
#include <string>
#include <cstring>
#include <thread>
#include <chrono>
#include <atomic>
#include <csignal>

#include "config.h"
#include "logger.h"
#include "database.h"

// Global flag for shutdown
static std::atomic<bool> running{true};

void signalHandler(int) {
    running = false;
}

void printHelp() {
    std::cout << "MyApp Daemon v" << myapp::VERSION << "\n";
    std::cout << "==================\n";
    std::cout << "Usage: myapp-daemon [options]\n\n";
    std::cout << "Options:\n";
    std::cout << "  --help       Show this help\n";
    std::cout << "  --check      Check configuration and exit\n";
    std::cout << "  --foreground Run in foreground (don't daemonize)\n";
}

void runDaemon() {
    auto& db = myapp::Database::instance();
    const auto& config = myapp::getConfig();

    LOG_INFO("Daemon starting...");

    if (!db.connect(config.databasePath)) {
        LOG_ERROR("Failed to connect to database");
        return;
    }

    LOG_INFO("Daemon running. Press Ctrl+C to stop.");

    int iteration = 0;
    while (running) {
        // Simulate daemon work
        iteration++;
        db.set("daemon_iteration", std::to_string(iteration));
        db.set("daemon_status", "running");

        if (config.debugMode) {
            LOG_DEBUG("Daemon iteration " + std::to_string(iteration));
        }

        // Check every second
        for (int i = 0; i < 10 && running; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        // For demo purposes, stop after a few iterations
        if (iteration >= 3) {
            LOG_INFO("Demo complete, stopping daemon");
            break;
        }
    }

    db.set("daemon_status", "stopped");
    LOG_INFO("Daemon stopped after " + std::to_string(iteration) + " iterations");
    db.disconnect();
}

int main(int argc, char* argv[]) {
    // Initialize
    const auto& config = myapp::getConfig();
    myapp::Logger::instance().init(config.logLevel);

    bool checkOnly = false;
    bool foreground = true;  // Default to foreground for demo

    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0) {
            printHelp();
            return 0;
        }
        if (std::strcmp(argv[i], "--check") == 0) {
            checkOnly = true;
        }
        if (std::strcmp(argv[i], "--foreground") == 0 || std::strcmp(argv[i], "-f") == 0) {
            foreground = true;
        }
    }

    std::cout << "MyApp Daemon v" << myapp::VERSION << "\n";

    if (checkOnly) {
        std::cout << "\nConfiguration check:\n";
        config.print();
        std::cout << "\nConfiguration OK!\n";
        return 0;
    }

    // Setup signal handlers
    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);

#ifdef DAEMON_MODE
    std::cout << "Built with DAEMON_MODE enabled\n";
#endif

    if (foreground) {
        std::cout << "Running in foreground mode\n";
    }

    runDaemon();

    std::cout << "Daemon exited cleanly\n";
    return 0;
}
