# Dynamic derivations checks
{ pkgs, native, packages }:

{
  dynamicDerivationsRuns = pkgs.runCommand "dynamic-derivations-runs" { } ''
    ${packages.dynamicExample}/bin/dynamic-example > $out
    grep -q "Hello from dynamic derivations" $out
  '';
}
