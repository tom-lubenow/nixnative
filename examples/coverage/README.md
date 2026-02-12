# Code Coverage Example

This example demonstrates code coverage instrumentation using explicit compiler and linker flags.

## What This Demonstrates

- Enabling code coverage with `compileFlags` and `linkFlags`
- Building coverage-instrumented binaries
- Generating coverage reports with lcov/gcov
- Comparing coverage vs non-coverage builds

## Project Structure

```
coverage/
├── flake.nix         # Build definitions with coverage variants
├── src/
│   ├── main.cc       # Test driver
│   ├── calculator.cc # Implementation to measure
│   └── calculator.h  # Interface
└── README.md
```

## Build and Run

```sh
# Build with coverage instrumentation
nix build

# Run the coverage-enabled binary
./result/bin/coverage-example

# Build without coverage (for comparison)
nix build .#appNoCoverage
```

## Generating Coverage Reports

After running the coverage-enabled binary:

```sh
# Enter the development shell (has lcov)
nix develop

# Run the binary to generate .gcda files
./result/bin/coverage-example

# Generate coverage report
lcov --capture --directory . --output-file coverage.info
genhtml coverage.info --output-directory coverage-report

# Open the report
xdg-open coverage-report/index.html
```

## How It Works

### Enabling Coverage

```nix
targets.appWithCoverage = {
  type = "executable";
  name = "coverage-example";
  sources = [ "src/main.cc" "src/calculator.cc" ];
  includeDirs = [ "src" ];
  compileFlags = [ "--coverage" "-g" "-O0" ];
  linkFlags = [ "--coverage" ];
};
```

### What Coverage Does

The coverage flag adds compiler flags to instrument the code:

| Compiler | Flags Added |
|----------|-------------|
| Clang | `--coverage` (equivalent to `-fprofile-arcs -ftest-coverage`) |
| GCC | `-fprofile-arcs -ftest-coverage` |

This instrumentation:
1. **At compile time**: Generates `.gcno` files with control flow information
2. **At runtime**: Creates `.gcda` files with execution counts
3. **Post-run**: Tools like `gcov` or `lcov` process these files into reports

### Coverage Report Contents

The generated report shows:
- **Line coverage**: Which lines of code were executed
- **Function coverage**: Which functions were called
- **Branch coverage**: Which conditional branches were taken

## Build Configurations

### Coverage Build (Recommended Settings)

```nix
compileFlags = [ "--coverage" "-g" "-O0" ];
linkFlags = [ "--coverage" ];
```

### Production Build (No Coverage)

```nix
compileFlags = [ "-O2" ];
```

## Platform Notes

Coverage works out of the box with both Clang and GCC on Linux.

## Interpreting Results

| Metric | Good | Needs Attention |
|--------|------|-----------------|
| Line Coverage | > 80% | < 60% |
| Function Coverage | > 90% | < 70% |
| Branch Coverage | > 70% | < 50% |

## Common Issues

### "No coverage data found"

Ensure you:
1. Built with coverage flags enabled
2. Actually ran the binary
3. Are looking in the right directory for `.gcda` files

### Inaccurate line numbers

Build with:
```nix
compileFlags = [ "--coverage" "-g" "-O0" ];
linkFlags = [ "--coverage" ];
```

### Missing files in report

The coverage tools need access to source files. Ensure the paths in `.gcno` files match your current directory structure.

## Integration with CI

```yaml
# Example GitHub Actions workflow
- name: Build with coverage
  run: nix build .#appWithCoverage

- name: Run tests
  run: ./result/bin/coverage-example

- name: Generate coverage report
  run: |
    lcov --capture --directory . --output-file coverage.info
    lcov --remove coverage.info '/nix/store/*' --output-file coverage.info

- name: Upload to Codecov
  uses: codecov/codecov-action@v3
  with:
    files: coverage.info
```

## Next Steps

- See `testing/` for test infrastructure
- See `multi-toolchain/` for other build flag examples
- See `multi-toolchain/` for additional explicit flag combinations (sanitizers, LTO, etc.)
