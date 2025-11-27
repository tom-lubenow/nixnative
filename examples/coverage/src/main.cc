#include <iostream>
#include <cassert>
#include "calculator.h"

// Simple test framework
int testsRun = 0;
int testsPassed = 0;

#define TEST(name, expr) do { \
    testsRun++; \
    if (expr) { \
        testsPassed++; \
        std::cout << "  [PASS] " << name << "\n"; \
    } else { \
        std::cout << "  [FAIL] " << name << "\n"; \
    } \
} while(0)

void testBasicArithmetic() {
    std::cout << "\nBasic Arithmetic Tests:\n";
    TEST("add(2, 3) == 5", calc::add(2, 3) == 5);
    TEST("add(-1, 1) == 0", calc::add(-1, 1) == 0);
    TEST("subtract(10, 4) == 6", calc::subtract(10, 4) == 6);
    TEST("multiply(3, 4) == 12", calc::multiply(3, 4) == 12);
    TEST("divide(10, 2) == 5", calc::divide(10, 2) == 5);
    TEST("divide(10, 0) == 0 (error case)", calc::divide(10, 0) == 0);
}

void testFactorial() {
    std::cout << "\nFactorial Tests:\n";
    TEST("factorial(0) == 1", calc::factorial(0) == 1);
    TEST("factorial(1) == 1", calc::factorial(1) == 1);
    TEST("factorial(5) == 120", calc::factorial(5) == 120);
    TEST("factorial(-1) == -1 (error case)", calc::factorial(-1) == -1);
}

void testFibonacci() {
    std::cout << "\nFibonacci Tests:\n";
    TEST("fibonacci(0) == 0", calc::fibonacci(0) == 0);
    TEST("fibonacci(1) == 1", calc::fibonacci(1) == 1);
    TEST("fibonacci(10) == 55", calc::fibonacci(10) == 55);
    // Note: We're not testing fibonacci(-1) to demonstrate incomplete coverage
}

void testPrime() {
    std::cout << "\nPrime Tests:\n";
    TEST("isPrime(2) == true", calc::isPrime(2) == true);
    TEST("isPrime(17) == true", calc::isPrime(17) == true);
    TEST("isPrime(4) == false", calc::isPrime(4) == false);
    TEST("isPrime(1) == false", calc::isPrime(1) == false);
    // Note: Not testing all branches to show coverage gaps
}

void testUtility() {
    std::cout << "\nUtility Tests:\n";
    TEST("abs(-5) == 5", calc::abs(-5) == 5);
    TEST("abs(5) == 5", calc::abs(5) == 5);
    TEST("max(3, 7) == 7", calc::max(3, 7) == 7);
    TEST("min(3, 7) == 3", calc::min(3, 7) == 3);
}

int main() {
    std::cout << "Code Coverage Example\n";
    std::cout << "=====================\n";
    std::cout << "\nRunning tests to generate coverage data...\n";

    testBasicArithmetic();
    testFactorial();
    testFibonacci();
    testPrime();
    testUtility();

    std::cout << "\n=====================\n";
    std::cout << "Results: " << testsPassed << "/" << testsRun << " tests passed\n";

    if (testsPassed == testsRun) {
        std::cout << "\nAll tests passed! Coverage data generated.\n";
        return 0;
    } else {
        std::cout << "\nSome tests failed.\n";
        return 1;
    }
}
