# Test Options

nixnative provides test infrastructure to run executables during the build and verify their output.

## `test`

Runs a test executable during the build.

```nix
native.test {
  name = "my-test";
  executable = myApp;
  args = [ "--verbose" ];
  expectedOutput = "PASSED";    # Optional: verify output contains this
}
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Test name |
| `executable` | Yes | - | The executable target to run |
| `args` | No | `[]` | Command-line arguments |
| `stdin` | No | `""` | Input to pass to stdin |
| `expectedOutput` | No | `null` | String that must appear in stdout |

## Basic Test

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
in {
  checks = { inherit test1; };
}
```

The test:
1. Runs the executable
2. Captures stdout
3. Checks that it contains `expectedOutput`
4. Fails if the output doesn't match

## Test with Arguments

```nix
test2 = native.test {
  name = "test-2";
  executable = app;
  args = [ "World" ];
  expectedOutput = "Hello World";
};
```

## Test with Stdin

```nix
testWithInput = native.test {
  name = "test-stdin";
  executable = app;
  stdin = "input data\n";
  expectedOutput = "Processed: input data";
};
```

## Shell Escaping

Arguments with special characters are properly escaped:

```nix
test3 = native.test {
  name = "test-3";
  executable = app;
  args = [ "it's \"quoted\" & $special" ];
  expectedOutput = "Hello it's \"quoted\" & $special";
};
```

## Testing Build Configurations

### LTO Build Test

```nix
appLto = proj.executable {
  name = "test-app-lto";
  sources = [ "main.cc" ];
  lto = "thin";
};

testLto = native.test {
  name = "test-lto";
  executable = appLto;
  expectedOutput = "Hello Test";
};
```

### Sanitizer Test (Linux)

```nix
appAsan = proj.executable {
  name = "test-app-asan";
  sources = [ "main.cc" ];
  sanitizers = [ "address" "undefined" ];
};

testAsan = native.test {
  name = "test-asan";
  executable = appAsan;
  expectedOutput = "Hello Test";
};
```

## Platform-Conditional Tests

```nix
let
  isLinux = pkgs.stdenv.isLinux;
in {
  checks = {
    inherit test1 test2 test3;
  } // (if isLinux then {
    inherit testAsan;  # Only on Linux
  } else {});
}
```

## Running Tests

```sh
# Run all tests via nix flake check
nix flake check

# Build individual tests
nix build .#checks.x86_64-linux.test1
nix build .#checks.x86_64-linux.test2
```

## Low-Level Variant

`mkTest` is the low-level version with the same interface:

```nix
native.mkTest {
  name = "my-test";
  executable = myApp;
  args = [ "--test" ];
  stdin = "input data";
  expectedOutput = "Success";
}
```
