# Dynamic derivations example
#
# Demonstrates using dynamic derivations to avoid IFD (Import From Derivation).
# Requires Nix with experimental features: dynamic-derivations, ca-derivations
#
{ pkgs, native }:

{
  # Simple executable using dynamic derivations
  dynamicExample = native.executable {
    name = "dynamic-example";
    root = ./.;
    sources = [ "src/*.cc" ];
    dynamic = true;  # Use dynamic derivations instead of IFD
  };
}
