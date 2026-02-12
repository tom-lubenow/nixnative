# Linker abstraction for nixnative
#
# A linker is defined separately from the compiler, allowing mix-and-match.
# Linkers are invoked via the compiler driver using -fuse-ld=<linker>.
#
{ lib }:

rec {
  # ==========================================================================
  # Linker Factory
  # ==========================================================================

  mkLinker =
    {
      name, # Identifier: "lld", "mold", "ld"
      binary, # Path to linker binary
      driverFlag, # How compiler invokes this: "-fuse-ld=lld"

      # Capability declarations
      capabilities ? {
        lto = false; # Can do LTO
        thinLto = false; # Thin LTO support
        parallelLinking = false;
        icf = false; # Identical Code Folding
        splitDwarf = false; # Split debug info
      },
      # Explicit feature list used for support queries
      # (kept separate from raw capability metadata)
      supports ? null,

      # Platform-specific default flags
      platformFlags ? platform: [ ],

      # How to group libraries (Linux needs --start-group/--end-group)
      groupFlags ?
        platform: libs:
        if platform.isLinux then [ "-Wl,--start-group" ] ++ libs ++ [ "-Wl,--end-group" ] else libs,

      # Packages needed at build time
      runtimeInputs ? [ ],

      # Environment variables
      environment ? { },
    }:
    let
      derivedFeatures = builtins.attrNames (lib.filterAttrs (_: v: v == true) capabilities);
      finalSupports =
        if supports == null then
          { features = derivedFeatures; }
        else
          { features = lib.unique (supports.features or [ ]); };
    in
    {
      inherit
        name
        binary
        driverFlag
        capabilities
        ;
      supports = finalSupports;
      inherit
        platformFlags
        groupFlags
        runtimeInputs
        environment
        ;

      # =======================================================================
      # Methods
      # =======================================================================

      # Check if a capability is supported
      hasCapability = cap: builtins.elem cap finalSupports.features;

      # Get the compiler flag to use this linker
      getDriverFlag = driverFlag;

      # Wrap link flags for this linker/platform
      wrapLinkFlags = { platform, flags }: groupFlags platform flags;
    };

  # ==========================================================================
  # Linker Presets
  # ==========================================================================

  # LLD (LLVM's linker) - fast, good LTO support
  lldCapabilities = {
    lto = true;
    thinLto = true;
    parallelLinking = true;
    icf = true;
    splitDwarf = true;
  };

  # Mold - extremely fast linker
  moldCapabilities = {
    lto = true;
    thinLto = true;
    parallelLinking = true;
    icf = true;
    splitDwarf = true;
  };

  # GNU ld - the classic
  ldCapabilities = {
    lto = true;
    thinLto = false;
    parallelLinking = false;
    icf = false;
    splitDwarf = false;
  };

  # ==========================================================================
  # Platform-Specific Helpers
  # ==========================================================================

  # Linux uses --start-group/--end-group for circular deps
  linuxGroupFlags = _: libs: [ "-Wl,--start-group" ] ++ libs ++ [ "-Wl,--end-group" ];

}
