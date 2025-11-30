# Checks for mixed C/C++/Rust example
{ pkgs, native }:

let
  project = import ./project.nix { inherit pkgs native; };

  # Test that the application runs and produces expected output
  appTest = pkgs.runCommand "test-mixed-c-cpp-rust" { } ''
    ${project.app}/bin/mixed-app > output.txt
    grep "Mixed C/C++/Rust Example" output.txt
    grep "rust_add(100, 200) = 300" output.txt
    grep "rust_factorial(7) = 5040" output.txt
    grep "c_power(2, 10) = 1024" output.txt
    grep "c_sum_range(1, 100) = 5050" output.txt
    grep "distanceTo(p2) = 5" output.txt
    grep "completed successfully" output.txt
    echo "Mixed C/C++/Rust test passed" > $out
  '';

in
{
  mixedCCppRust = appTest;
}
