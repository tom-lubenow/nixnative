#pragma once

#include <string>
#include <string_view>
#include <vector>
#include <optional>

namespace myapp {

// Simple mock database for demonstration
class Database {
public:
    static Database& instance();

    // Connection management
    bool connect(std::string_view path);
    void disconnect();
    bool isConnected() const;
    std::string_view getPath() const;

    // Simple key-value operations
    void set(std::string_view key, std::string_view value);
    std::optional<std::string> get(std::string_view key) const;
    bool remove(std::string_view key);
    std::vector<std::string> keys() const;

    // Statistics
    size_t size() const;

private:
    Database() = default;

    bool connected_ = false;
    std::string path_;
    std::vector<std::pair<std::string, std::string>> data_;
};

}  // namespace myapp
