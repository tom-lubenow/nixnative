# Checks for Rust native example
{ pkgs, native }:

let
  project = import ./project.nix { inherit pkgs native; };

  # Test that the application runs and produces expected output
  appTest = pkgs.runCommand "test-rust-native-app" { } ''
    ${project.app}/bin/rust-native-app > output.txt
    grep "Rust Native Example" output.txt
    grep "add(10, 20) = 30" output.txt
    grep "factorial(6) = 720" output.txt
    grep "distance(p1, p2) = 5.0" output.txt
    grep "completed successfully" output.txt
    echo "Rust native test passed" > $out
  '';

in
{
  rustNative = appTest;
}
