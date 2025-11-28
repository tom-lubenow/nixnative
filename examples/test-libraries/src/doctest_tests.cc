// doctest example tests
//
// This file demonstrates basic doctest usage with nixnative.
// doctest is header-only; DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN provides main().

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <string>
#include <vector>

// Simple test case
TEST_CASE("Basic arithmetic") {
    CHECK(2 + 2 == 4);
    CHECK(0 + 0 == 0);
    CHECK(-1 + 1 == 0);
}

TEST_CASE("String operations") {
    std::string hello = "Hello";
    std::string world = "World";

    CHECK(hello + " " + world == "Hello World");
    CHECK(hello.length() == 5);
}

// Subcases work similarly to Catch2's sections
TEST_CASE("Vector operations") {
    std::vector<int> vec;

    REQUIRE(vec.empty());

    SUBCASE("adding elements") {
        vec.push_back(1);
        vec.push_back(2);

        CHECK(vec.size() == 2);
        CHECK(vec[0] == 1);
        CHECK(vec[1] == 2);

        SUBCASE("adding more elements") {
            vec.push_back(3);
            CHECK(vec.size() == 3);
        }

        SUBCASE("clearing") {
            vec.clear();
            CHECK(vec.empty());
        }
    }

    SUBCASE("reserving capacity") {
        vec.reserve(10);
        CHECK(vec.capacity() >= 10);
        CHECK(vec.empty());
    }
}

// Test suite grouping
TEST_SUITE("Math Suite") {
    TEST_CASE("multiplication") {
        CHECK(3 * 3 == 9);
        CHECK(0 * 100 == 0);
    }

    TEST_CASE("division") {
        CHECK(10 / 2 == 5);
        CHECK(9 / 3 == 3);
    }
}

// Parameterized-like tests using subcases
TEST_CASE("Factorial") {
    auto factorial = [](int n) {
        int result = 1;
        for (int i = 2; i <= n; ++i) {
            result *= i;
        }
        return result;
    };

    SUBCASE("factorial of 0") { CHECK(factorial(0) == 1); }
    SUBCASE("factorial of 1") { CHECK(factorial(1) == 1); }
    SUBCASE("factorial of 5") { CHECK(factorial(5) == 120); }
}
