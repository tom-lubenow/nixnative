# project.nix - Build definition demonstrating content-addressed derivations
#
# Content-addressed (CA) derivations enable better incrementality by deduplicating
# outputs based on their content rather than their inputs. This is particularly
# useful for the scanner, where changing one source file won't invalidate
# scan results for other files (if their outputs are identical).
#
# Requirements:
#   - Nix with 'ca-derivations' experimental feature enabled
#   - Add to ~/.config/nix/nix.conf or /etc/nix/nix.conf:
#       experimental-features = nix-command flakes ca-derivations
#
# Benefits:
#   - Per-file scanner derivations are deduplicated if outputs match
#   - Faster incremental builds when only some files change
#   - Better cache hit rates in distributed builds
#

{ pkgs, native }:

let
  root = ./.;

  includeDirs = [ "include" ];

  sources = [
    "src/main.cc"
    "src/greeter.cc"
    "src/utils.cc"
  ];

  # Build with content-addressed derivations enabled
  # This affects scanner derivations (and potentially others in the future)
  executable = native.executable {
    name = "ca-example";
    inherit root includeDirs sources;

    # Enable content-addressed derivations
    # Scanner derivations will use CA mode, enabling better incrementality
    contentAddressed = true;

    # You can also use scanMode to control scanning behavior:
    # scanMode = "per-file";  # Default: per-file scanner derivations
    # scanMode = "batch";     # Legacy: single scanner derivation
  };

  # For comparison: same build without CA mode
  executableNoCA = native.executable {
    name = "ca-example-no-ca";
    inherit root includeDirs sources;
    contentAddressed = false;  # Default
  };

in
{
  # Main example with CA enabled
  caExample = executable;

  # Comparison build without CA
  caExampleNoCA = executableNoCA;
}
