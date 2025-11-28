// GoogleMock example tests
//
// This file demonstrates basic GoogleMock usage with nixnative.
// GMock is useful for mocking interfaces in unit tests.

#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <string>

// Interface to mock
class Database {
public:
    virtual ~Database() = default;
    virtual bool connect(const std::string& host) = 0;
    virtual std::string query(const std::string& sql) = 0;
    virtual void disconnect() = 0;
};

// Mock implementation
class MockDatabase : public Database {
public:
    MOCK_METHOD(bool, connect, (const std::string& host), (override));
    MOCK_METHOD(std::string, query, (const std::string& sql), (override));
    MOCK_METHOD(void, disconnect, (), (override));
};

// Class under test that uses the database
class UserService {
public:
    explicit UserService(Database& db) : db_(db) {}

    std::string getUserName(int id) {
        if (!db_.connect("localhost")) {
            return "connection_failed";
        }
        auto result = db_.query("SELECT name FROM users WHERE id = " + std::to_string(id));
        db_.disconnect();
        return result;
    }

private:
    Database& db_;
};

// Tests using the mock
TEST(UserServiceTest, GetUserNameSuccess) {
    MockDatabase mockDb;

    EXPECT_CALL(mockDb, connect("localhost"))
        .WillOnce(testing::Return(true));
    EXPECT_CALL(mockDb, query(testing::HasSubstr("SELECT name")))
        .WillOnce(testing::Return("Alice"));
    EXPECT_CALL(mockDb, disconnect())
        .Times(1);

    UserService service(mockDb);
    EXPECT_EQ(service.getUserName(1), "Alice");
}

TEST(UserServiceTest, GetUserNameConnectionFailed) {
    MockDatabase mockDb;

    EXPECT_CALL(mockDb, connect("localhost"))
        .WillOnce(testing::Return(false));

    UserService service(mockDb);
    EXPECT_EQ(service.getUserName(1), "connection_failed");
}
