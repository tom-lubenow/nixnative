# Testing Example

This example demonstrates nixnative's test infrastructure using module-defined tests.

## What This Demonstrates

- Defining tests under `native.tests`
- Passing arguments to test executables
- Verifying expected output
- Testing edge cases (special characters, LTO builds, sanitizers)
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
nix build .#test1          # Basic test
nix build .#test2          # Test with arguments
nix build .#test3          # Special characters test
nix build .#testLto        # LTO build test
nix build .#testAsan       # AddressSanitizer test (Linux only)
```

## How It Works

### Basic Test

```nix
tests.test1 = {
  executable = "app";
  expectedOutput = "Hello Test";
};
```

The test:
1. Runs the executable
2. Captures stdout
3. Checks that it contains `expectedOutput`
4. Fails if the output doesn't match

### Test with Arguments

```nix
tests.test2 = {
  executable = "app";
  args = [ "World" ];
  expectedOutput = "Hello World";
};
```

### Shell Escaping Test

```nix
tests.test3 = {
  executable = "app";
  args = [ "it's \"quoted\" & $special" ];
  expectedOutput = "Hello it's \"quoted\" & $special";
};
```

This verifies that arguments with special shell characters are properly escaped.

### Testing Build Configurations

#### LTO Build

```nix
targets.appLto = {
  type = "executable";
  name = "test-app-lto";
  sources = [ "main.cc" ];
  lto = "thin";
};

tests.testLto = {
  executable = "appLto";
  expectedOutput = "Hello Test";
};
```

#### AddressSanitizer (Linux Only)

```nix
targets.appAsan = {
  type = "executable";
  name = "test-app-asan";
  sources = [ "main.cc" ];
  sanitizers = [ "address" "undefined" ];
};
```

### Minimal Configuration Test

```nix
targets.appMinimal = {
  type = "executable";
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
tests = {
  inherit test1 test2 test3 testLto testMinimal;
}
// (if pkgs.stdenv.hostPlatform.isLinux then {
  inherit testAsan;
} else { });
```

This pattern allows tests that only work on certain platforms.

## Test Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `name` | No | Test name (defaults to the attribute name) |
| `executable` | Yes | The executable to run |
| `args` | No | Command-line arguments |
| `stdin` | No | Input to pass to stdin |
| `expectedOutput` | No | String that must appear in stdout |

## Next Steps

- See `multi-toolchain/` for more build flag examples
- See `executable/` for basic executable building
- See `devshell/` for development environment setup
