#include <iostream>
#include <string>
#include <cassert>

#include "config.h"
#include "logger.h"
#include "database.h"

// Simple test framework
static int testsRun = 0;
static int testsPassed = 0;

#define TEST(name, expr) do { \
    testsRun++; \
    if (expr) { \
        testsPassed++; \
        std::cout << "  [PASS] " << name << "\n"; \
    } else { \
        std::cout << "  [FAIL] " << name << "\n"; \
    } \
} while(0)

#define TEST_SECTION(name) std::cout << "\n" << name << ":\n"

void testConfig() {
    TEST_SECTION("Configuration Tests");

    const auto& config = myapp::getConfig();

    TEST("App name is set", !config.appName.empty());
    TEST("Version is set", !config.version.empty());
    TEST("Database path is set", !config.databasePath.empty());
    TEST("Log level is valid", config.logLevel >= 0 && config.logLevel <= 3);
}

void testLogger() {
    TEST_SECTION("Logger Tests");

    auto& logger = myapp::Logger::instance();

    logger.setLevel(myapp::LogLevel::DEBUG);
    TEST("Can set log level to DEBUG", logger.getLevel() == myapp::LogLevel::DEBUG);

    logger.setLevel(myapp::LogLevel::ERROR);
    TEST("Can set log level to ERROR", logger.getLevel() == myapp::LogLevel::ERROR);

    TEST("DEBUG level name", std::string(myapp::Logger::levelName(myapp::LogLevel::DEBUG)) == "DEBUG");
    TEST("INFO level name", std::string(myapp::Logger::levelName(myapp::LogLevel::INFO)) == "INFO");

    // Reset for other tests
    logger.setLevel(myapp::LogLevel::WARN);
}

void testDatabase() {
    TEST_SECTION("Database Tests");

    auto& db = myapp::Database::instance();

    TEST("Initially not connected", !db.isConnected());

    db.connect(":memory:");
    TEST("Can connect", db.isConnected());
    TEST("Path is set", db.getPath() == ":memory:");

    db.set("key1", "value1");
    db.set("key2", "value2");
    TEST("Size after inserts", db.size() == 2);

    auto val = db.get("key1");
    TEST("Can get value", val.has_value() && *val == "value1");

    auto missing = db.get("nonexistent");
    TEST("Missing key returns nullopt", !missing.has_value());

    db.set("key1", "updated");
    val = db.get("key1");
    TEST("Can update value", val.has_value() && *val == "updated");

    db.remove("key2");
    TEST("Can remove key", db.size() == 1);

    auto keys = db.keys();
    TEST("Keys list correct", keys.size() == 1 && keys[0] == "key1");

    db.disconnect();
    TEST("Can disconnect", !db.isConnected());
}

void testDatabaseEdgeCases() {
    TEST_SECTION("Database Edge Cases");

    auto& db = myapp::Database::instance();

    // Operations on disconnected database
    auto val = db.get("anything");
    TEST("Get on disconnected returns nullopt", !val.has_value());

    bool removed = db.remove("anything");
    TEST("Remove on disconnected returns false", !removed);

    // Reconnect for cleanup
    db.connect(":memory:");
    TEST("Can reconnect", db.isConnected());
    db.disconnect();
}

int main(int argc, char* argv[]) {
    std::cout << "MyApp Test Suite v" << myapp::VERSION << "\n";
    std::cout << "==================================\n";

#ifdef TEST_MODE
    std::cout << "Built with TEST_MODE enabled\n";
#endif

    // Run all tests
    testConfig();
    testLogger();
    testDatabase();
    testDatabaseEdgeCases();

    // Summary
    std::cout << "\n==================================\n";
    std::cout << "Results: " << testsPassed << "/" << testsRun << " tests passed\n";

    if (testsPassed == testsRun) {
        std::cout << "\nAll tests passed!\n";
        return 0;
    } else {
        std::cout << "\nSome tests failed!\n";
        return 1;
    }
}
