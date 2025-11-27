#!/usr/bin/env python3
"""Test script for the mathext extension module."""

import sys


def main():
    print("Testing mathext module...")
    print()

    try:
        import mathext
    except ImportError as e:
        print(f"Error: Could not import mathext: {e}")
        print("Make sure you're running this from the dev shell or have the module in PYTHONPATH")
        sys.exit(1)

    # Test version
    print(f"mathext version: {mathext.version()}")
    print()

    # Test basic operations
    tests_passed = 0
    tests_failed = 0

    def test(name, result, expected):
        nonlocal tests_passed, tests_failed
        if result == expected:
            print(f"  [PASS] {name}: {result}")
            tests_passed += 1
        else:
            print(f"  [FAIL] {name}: got {result}, expected {expected}")
            tests_failed += 1

    print("Basic operations:")
    test("add(2, 3)", mathext.add(2, 3), 5)
    test("add(-1, 1)", mathext.add(-1, 1), 0)
    test("multiply(4, 5)", mathext.multiply(4, 5), 20)
    test("multiply(-3, 7)", mathext.multiply(-3, 7), -21)

    print()
    print("Factorial:")
    test("factorial(0)", mathext.factorial(0), 1)
    test("factorial(1)", mathext.factorial(1), 1)
    test("factorial(5)", mathext.factorial(5), 120)
    test("factorial(6)", mathext.factorial(6), 720)

    print()
    print("Fibonacci:")
    test("fibonacci(0)", mathext.fibonacci(0), 0)
    test("fibonacci(1)", mathext.fibonacci(1), 1)
    test("fibonacci(10)", mathext.fibonacci(10), 55)
    test("fibonacci(15)", mathext.fibonacci(15), 610)

    print()
    print("Prime checking:")
    test("is_prime(2)", mathext.is_prime(2), True)
    test("is_prime(17)", mathext.is_prime(17), True)
    test("is_prime(4)", mathext.is_prime(4), False)
    test("is_prime(1)", mathext.is_prime(1), False)
    test("is_prime(97)", mathext.is_prime(97), True)

    print()
    print("Error handling:")
    try:
        mathext.factorial(-1)
        print("  [FAIL] factorial(-1) should raise ValueError")
        tests_failed += 1
    except ValueError as e:
        print(f"  [PASS] factorial(-1) correctly raised ValueError: {e}")
        tests_passed += 1

    try:
        mathext.fibonacci(-1)
        print("  [FAIL] fibonacci(-1) should raise ValueError")
        tests_failed += 1
    except ValueError as e:
        print(f"  [PASS] fibonacci(-1) correctly raised ValueError: {e}")
        tests_passed += 1

    # Summary
    print()
    print("=" * 40)
    print(f"Results: {tests_passed} passed, {tests_failed} failed")

    if tests_failed == 0:
        print()
        print("All tests passed!")
        return 0
    else:
        print()
        print("Some tests failed!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
