# LLD (LLVM linker) implementation for nixnative
#
# LLD is the LLVM project's linker - fast and feature-rich.
#
{
  pkgs,
  lib,
  mkLinker,
  lldCapabilities,
}:

let
  inherit (lib) optionals;
  targetPlatform = pkgs.stdenv.targetPlatform;

  # Helper to create LLD for a specific LLVM version
  mkLLD =
    {
      llvmPackages,
      name ? "lld${llvmPackages.release_version}",
    }:
    let
      llvm = llvmPackages;
    in
    mkLinker {
      inherit name;
      binary = "${llvm.lld}/bin/ld.lld";
      driverFlag = "-fuse-ld=lld";

      capabilities = lldCapabilities;

      platformFlags =
        platform:
        if platform.isLinux then
          [
            # Enable new-style dtags for rpath
            "-Wl,--enable-new-dtags"
          ]
        else
          [ ];

      runtimeInputs = [ llvm.lld ];
      environment = { };
    };

in
rec {
  # ==========================================================================
  # LLD Linker Variants
  # ==========================================================================

  # LLVM 18
  lld18 = mkLLD { llvmPackages = pkgs.llvmPackages_18; };

  # LLVM 17
  lld17 = mkLLD { llvmPackages = pkgs.llvmPackages_17; };

  # LLVM 19 (if available)
  lld19 = if pkgs ? llvmPackages_19 then mkLLD { llvmPackages = pkgs.llvmPackages_19; } else null;

  # Default LLD (18)
  lld = lld18;
}
