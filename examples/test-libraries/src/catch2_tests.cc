// Catch2 example tests
//
// This file demonstrates basic Catch2 v3 usage with nixnative.
// The main() function is provided by Catch2Main (via testLibs.catch2.withMain).

#include <catch2/catch_test_macros.hpp>

#include <string>
#include <vector>

// Simple test case
TEST_CASE("Basic arithmetic", "[math]") {
    REQUIRE(2 + 2 == 4);
    REQUIRE(0 + 0 == 0);
    REQUIRE(-1 + 1 == 0);
}

TEST_CASE("String operations", "[string]") {
    std::string hello = "Hello";
    std::string world = "World";

    REQUIRE(hello + " " + world == "Hello World");
    REQUIRE(hello.length() == 5);
}

// Sections allow multiple test paths in one test case
TEST_CASE("Vector operations", "[vector]") {
    std::vector<int> vec;

    REQUIRE(vec.empty());

    SECTION("adding elements") {
        vec.push_back(1);
        vec.push_back(2);

        REQUIRE(vec.size() == 2);
        REQUIRE(vec[0] == 1);
        REQUIRE(vec[1] == 2);

        SECTION("adding more elements") {
            vec.push_back(3);
            REQUIRE(vec.size() == 3);
        }

        SECTION("clearing") {
            vec.clear();
            REQUIRE(vec.empty());
        }
    }

    SECTION("reserving capacity") {
        vec.reserve(10);
        REQUIRE(vec.capacity() >= 10);
        REQUIRE(vec.empty());
    }
}

// BDD-style tests
SCENARIO("Vectors can be sized and resized", "[vector][bdd]") {
    GIVEN("An empty vector") {
        std::vector<int> v;

        REQUIRE(v.size() == 0);

        WHEN("an element is added") {
            v.push_back(42);

            THEN("the size increases") {
                REQUIRE(v.size() == 1);
            }

            AND_THEN("the element can be retrieved") {
                REQUIRE(v[0] == 42);
            }
        }

        WHEN("capacity is reserved") {
            v.reserve(10);

            THEN("capacity increases but size stays the same") {
                REQUIRE(v.capacity() >= 10);
                REQUIRE(v.size() == 0);
            }
        }
    }
}
