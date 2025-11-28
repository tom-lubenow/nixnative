// GoogleTest example tests
//
// This file demonstrates basic GoogleTest usage with nixnative.
// The main() function is provided by gtest_main (via testLibs.gtest.withMain).

#include <gtest/gtest.h>

#include <string>
#include <vector>

// Simple test case
TEST(BasicTests, Addition) {
    EXPECT_EQ(2 + 2, 4);
    EXPECT_EQ(0 + 0, 0);
    EXPECT_EQ(-1 + 1, 0);
}

TEST(BasicTests, StringOperations) {
    std::string hello = "Hello";
    std::string world = "World";
    EXPECT_EQ(hello + " " + world, "Hello World");
    EXPECT_EQ(hello.length(), 5);
}

// Test fixture example
class VectorTest : public ::testing::Test {
protected:
    void SetUp() override {
        vec.push_back(1);
        vec.push_back(2);
        vec.push_back(3);
    }

    std::vector<int> vec;
};

TEST_F(VectorTest, Size) {
    EXPECT_EQ(vec.size(), 3);
}

TEST_F(VectorTest, Contents) {
    EXPECT_EQ(vec[0], 1);
    EXPECT_EQ(vec[1], 2);
    EXPECT_EQ(vec[2], 3);
}

TEST_F(VectorTest, PushBack) {
    vec.push_back(4);
    EXPECT_EQ(vec.size(), 4);
    EXPECT_EQ(vec.back(), 4);
}
