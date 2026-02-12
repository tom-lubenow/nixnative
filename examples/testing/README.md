# Testing Example

This example demonstrates nixnative's test infrastructure using `native.test`.

## What This Demonstrates

- Defining tests with `native.test`
- Passing arguments to test executables
- Verifying expected output
- Testing edge cases (special characters, explicit LTO/sanitizer flags)
- Platform-conditional tests

## Project Structure

```
testing/
├── flake.nix    # Test definitions
└── main.cc      # Simple test program
```

## Build and Run Tests

```sh
# Run all tests via nix flake check
nix flake check

# Build individual tests
nix build .#checks.x86_64-linux.test1   # Basic test
nix build .#checks.x86_64-linux.test2   # Test with arguments
```

## How It Works

### Basic Test

```nix
let
  proj = native.project { root = ./.; };

  app = proj.executable {
    name = "test-app";
    sources = [ "main.cc" ];
  };

  test1 = native.test {
    name = "test-1";
    executable = app;  # Direct reference!
    expectedOutput = "Hello Test";
  };
in { ... }
```

The test:
1. Runs the executable
2. Captures stdout
3. Checks that it contains `expectedOutput`
4. Fails if the output doesn't match

### Test with Arguments

```nix
test2 = native.test {
  name = "test-2";
  executable = app;
  args = [ "World" ];
  expectedOutput = "Hello World";
};
```

### Shell Escaping Test

```nix
test3 = native.test {
  name = "test-3";
  executable = app;
  args = [ "it's \"quoted\" & $special" ];
  expectedOutput = "Hello it's \"quoted\" & $special";
};
```

This verifies that arguments with special shell characters are properly escaped.

### Testing Build Configurations

#### LTO Build

```nix
appLto = proj.executable {
  name = "test-app-lto";
  sources = [ "main.cc" ];
  compileFlags = [ "-flto=thin" ];
  linkFlags = [ "-flto=thin" ];
};

testLto = native.test {
  name = "test-lto";
  executable = appLto;
  expectedOutput = "Hello Test";
};
```

#### AddressSanitizer (Linux Only)

```nix
appAsan = if isLinux then proj.executable {
  name = "test-app-asan";
  sources = [ "main.cc" ];
  compileFlags = [ "-fsanitize=address,undefined" ];
  linkFlags = [ "-fsanitize=address,undefined" ];
} else null;
```

### Minimal Configuration Test

```nix
appMinimal = proj.executable {
  name = "test-app-minimal";
  sources = [ "main.cc" ];
  includeDirs = [ ];
  defines = [ ];
  compileFlags = [ ];
  libraries = [ ];
  tools = [ ];
};
```

This verifies that empty optional lists work correctly.

## Platform-Conditional Tests

```nix
checks = {
  inherit test1 test2 test3 testLto testMinimal;
} // (if isLinux then { inherit testAsan; } else { });
```

This pattern allows tests that only work on certain platforms.

## Test Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `name` | Yes | Test name |
| `executable` | Yes | The executable target to run |
| `args` | No | Command-line arguments |
| `stdin` | No | Input to pass to stdin |
| `expectedOutput` | No | String that must appear in stdout |

## Next Steps

- See `multi-toolchain/` for more build flag examples
- See `executable/` for basic executable building
- See `devshell/` for development environment setup
