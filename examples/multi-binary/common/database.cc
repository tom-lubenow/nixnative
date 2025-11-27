#include "database.h"
#include "logger.h"
#include <algorithm>

namespace myapp {

Database& Database::instance() {
    static Database db;
    return db;
}

bool Database::connect(std::string_view path) {
    if (connected_) {
        LOG_WARN("Already connected, disconnecting first");
        disconnect();
    }

    path_ = std::string(path);
    connected_ = true;
    LOG_INFO("Database connected: " + path_);
    return true;
}

void Database::disconnect() {
    if (connected_) {
        LOG_INFO("Database disconnected");
        connected_ = false;
        path_.clear();
        data_.clear();
    }
}

bool Database::isConnected() const {
    return connected_;
}

std::string_view Database::getPath() const {
    return path_;
}

void Database::set(std::string_view key, std::string_view value) {
    if (!connected_) {
        LOG_ERROR("Not connected");
        return;
    }

    // Update existing or add new
    for (auto& [k, v] : data_) {
        if (k == key) {
            v = std::string(value);
            return;
        }
    }
    data_.emplace_back(std::string(key), std::string(value));
}

std::optional<std::string> Database::get(std::string_view key) const {
    if (!connected_) {
        return std::nullopt;
    }

    for (const auto& [k, v] : data_) {
        if (k == key) {
            return v;
        }
    }
    return std::nullopt;
}

bool Database::remove(std::string_view key) {
    if (!connected_) {
        return false;
    }

    auto it = std::remove_if(data_.begin(), data_.end(),
        [&key](const auto& kv) { return kv.first == key; });

    if (it != data_.end()) {
        data_.erase(it, data_.end());
        return true;
    }
    return false;
}

std::vector<std::string> Database::keys() const {
    std::vector<std::string> result;
    result.reserve(data_.size());
    for (const auto& [k, v] : data_) {
        result.push_back(k);
    }
    return result;
}

size_t Database::size() const {
    return data_.size();
}

}  // namespace myapp
