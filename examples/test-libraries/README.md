# Test Libraries Example

This example demonstrates how to use test libraries (GoogleTest, Catch2, doctest) with nixnative.

## Overview

nixnative provides pre-configured test libraries through `native.testLibs`:

- **`gtest`** - GoogleTest
- **`gmock`** - GoogleMock (includes GoogleTest)
- **`catch2`** - Catch2 v3
- **`doctest`** - doctest (header-only)

## Usage Patterns

### GoogleTest / GoogleMock

```nix
# With framework-provided main()
native.executable {
  name = "my-tests";
  sources = [ "tests.cc" ];
  libraries = [ native.testLibs.gtest.withMain ];
};

# With your own main()
native.executable {
  name = "my-tests";
  sources = [ "tests.cc" "main.cc" ];
  libraries = [ native.testLibs.gtest ];
};

# With mocking support
native.executable {
  name = "my-tests";
  sources = [ "tests.cc" ];
  libraries = [ native.testLibs.gmock.withMain ];
};
```

### Catch2

```nix
# With framework-provided main()
native.executable {
  name = "my-tests";
  sources = [ "tests.cc" ];
  libraries = [ native.testLibs.catch2.withMain ];
};
```

### doctest

doctest is header-only. Define `DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN` in one source file:

```nix
native.executable {
  name = "my-tests";
  sources = [ "tests.cc" ];
  libraries = [ native.testLibs.doctest ];
};
```

```cpp
// tests.cc
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

TEST_CASE("example") {
    CHECK(1 + 1 == 2);
}
```

## Custom Test Frameworks

You can create your own test library using `mkTestLib`:

```nix
myTestLib = native.mkTestLib {
  name = "my-framework";
  package = pkgs.myTestFramework;
  includeDirs = [ "${pkgs.myTestFramework}/include" ];
  libraries = [ "${pkgs.myTestFramework}/lib/libmytest.a" ];
  mainLibrary = "${pkgs.myTestFramework}/lib/libmytest_main.a";
};
```

## Building

```bash
# Build all test executables
nix build .#gtestExample
nix build .#catch2Example
nix build .#doctestExample

# Run tests via checks
nix flake check
```

## File Structure

```
test-libraries/
├── flake.nix           # Flake definition
├── project.nix         # Build definitions
├── checks.nix          # Test execution
├── README.md           # This file
└── src/
    ├── gtest_tests.cc  # GoogleTest example
    ├── gmock_tests.cc  # GoogleMock example
    ├── catch2_tests.cc # Catch2 example
    └── doctest_tests.cc # doctest example
```
