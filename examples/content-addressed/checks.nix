# checks.nix - Test definitions for the content-addressed example

{ pkgs, packages }:

{
  caExample = pkgs.runCommand "ca-example-check" { } ''
    ${packages.caExample}/bin/ca-example > output.txt
    grep -q "Hello, WORLD!" output.txt
    grep -q "Lowercase: hello" output.txt
    grep -q "Uppercase: HELLO" output.txt
    echo "Content-addressed example passed!"
    mkdir -p $out
    cp output.txt $out/
  '';

  caExampleNoCA = pkgs.runCommand "ca-example-no-ca-check" { } ''
    ${packages.caExampleNoCA}/bin/ca-example-no-ca > output.txt
    grep -q "Hello, WORLD!" output.txt
    echo "Non-CA example passed!"
    mkdir -p $out
    cp output.txt $out/
  '';
}
