# Dynamic derivations checks
#
# With dynamic derivations, we verify the build completes successfully.
# The wrapper derivation produces a .drv file that can be built separately.
#
{ pkgs, native, packages }:

{
  # Verify that the parallel example builds (produces link wrapper)
  dynamicDerivationsRuns = packages.parallelExample;
}
