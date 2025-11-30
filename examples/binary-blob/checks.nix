{ pkgs, packages }:

{
  # Test that the binary blob example runs correctly
  binary-blob-runs = pkgs.runCommand "check-binary-blob" { } ''
    ${packages.app}/bin/binary-blob-example > output.txt
    grep -q "Binary blob example" output.txt
    grep -q "Usage size:" output.txt
    grep -q "License size:" output.txt
    touch $out
  '';

  # Test that --help shows the embedded usage text
  binary-blob-help = pkgs.runCommand "check-binary-blob-help" { } ''
    ${packages.app}/bin/binary-blob-example --help > output.txt
    grep -q "Usage: myapp" output.txt
    grep -q "Options:" output.txt
    touch $out
  '';

  # Test that --license shows the embedded license
  binary-blob-license = pkgs.runCommand "check-binary-blob-license" { } ''
    ${packages.app}/bin/binary-blob-example --license > output.txt
    grep -q "MIT License" output.txt
    touch $out
  '';
}
