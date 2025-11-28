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
    { name                    # Identifier: "lld", "mold", "gold", "ld"
    , binary                  # Path to linker binary
    , driverFlag              # How compiler invokes this: "-fuse-ld=lld"

    # Capability declarations
    , capabilities ? {
        lto = false;          # Can do LTO
        thinLto = false;      # Thin LTO support
        parallelLinking = false;
        icf = false;          # Identical Code Folding
        splitDwarf = false;   # Split debug info
      }

    # Platform-specific default flags
    , platformFlags ? platform: []

    # How to group libraries (Linux needs --start-group/--end-group)
    , groupFlags ? platform: libs:
        if platform.isLinux
        then [ "-Wl,--start-group" ] ++ libs ++ [ "-Wl,--end-group" ]
        else libs

    # Packages needed at build time
    , runtimeInputs ? []

    # Environment variables
    , environment ? {}
    }:
    {
      inherit name binary driverFlag capabilities;
      inherit platformFlags groupFlags runtimeInputs environment;

      # =======================================================================
      # Methods
      # =======================================================================

      # Check if a capability is supported
      hasCapability = cap: capabilities.${cap} or false;

      # Get the compiler flag to use this linker
      getDriverFlag = driverFlag;

      # Wrap link flags for this linker/platform
      wrapLinkFlags = { platform, flags }:
        groupFlags platform flags;
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

  # Gold (GNU gold) - faster than GNU ld
  goldCapabilities = {
    lto = true;
    thinLto = false;
    parallelLinking = true;
    icf = true;
    splitDwarf = false;
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
  linuxGroupFlags = _: libs:
    [ "-Wl,--start-group" ] ++ libs ++ [ "-Wl,--end-group" ];

  # ==========================================================================
  # Validation Helpers
  # ==========================================================================

  validateLinker = linker:
    let
      required = [ "name" "binary" "driverFlag" ];
      missing = builtins.filter (f: !(linker ? ${f})) required;
    in
    if missing != []
    then throw "nixnative: linker missing required fields: ${lib.concatStringsSep ", " missing}"
    else linker;
}
