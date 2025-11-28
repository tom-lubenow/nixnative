{ pkgs, packages }:

{
  # Run GoogleTest tests
  gtestExample = pkgs.runCommand "gtest-example-check" { } ''
    set -euo pipefail
    echo "Running GoogleTest tests..."
    ${packages.gtestExample}/bin/gtest-example
    mkdir -p "$out"
    echo "gtest tests passed" > "$out/result.txt"
  '';

  # Run GoogleMock tests
  gmockExample = pkgs.runCommand "gmock-example-check" { } ''
    set -euo pipefail
    echo "Running GoogleMock tests..."
    ${packages.gmockExample}/bin/gmock-example
    mkdir -p "$out"
    echo "gmock tests passed" > "$out/result.txt"
  '';

  # Run Catch2 tests
  catch2Example = pkgs.runCommand "catch2-example-check" { } ''
    set -euo pipefail
    echo "Running Catch2 tests..."
    ${packages.catch2Example}/bin/catch2-example
    mkdir -p "$out"
    echo "catch2 tests passed" > "$out/result.txt"
  '';

  # Run doctest tests
  doctestExample = pkgs.runCommand "doctest-example-check" { } ''
    set -euo pipefail
    echo "Running doctest tests..."
    ${packages.doctestExample}/bin/doctest-example
    mkdir -p "$out"
    echo "doctest tests passed" > "$out/result.txt"
  '';
}
