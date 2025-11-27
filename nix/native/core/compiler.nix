# Compiler abstraction for nixnative
#
# A compiler is defined by its binaries, capabilities, and flag translators.
# Different compilers (clang, gcc, zig) implement this interface.
#
{ lib, flags }:

rec {
  # ==========================================================================
  # Compiler Factory
  # ==========================================================================

  mkCompiler =
    { name                    # Identifier: "clang18", "gcc14", "zig"
    , cc                      # Path to C compiler binary
    , cxx                     # Path to C++ compiler binary
    , version ? null          # Version string (for display/capability detection)

    # Capability declarations - what features this compiler supports
    , capabilities ? {
        lto = null;           # null = unsupported, { thin = bool; full = bool; }
        sanitizers = [];      # List of supported sanitizers
        coverage = false;
        modules = false;      # C++20 modules
        pch = false;          # Precompiled headers
        colorDiagnostics = false;
      }

    # Flag translators - convert abstract flags to concrete CLI args
    , flagTranslators ? {}

    # Default flags applied to all compilations
    , defaultCFlags ? []
    , defaultCxxFlags ? []

    # Packages needed at build time
    , runtimeInputs ? []

    # Environment variables
    , environment ? {}

    # Optional: reference to the compiler package (for dev shells)
    , package ? null
    }:
    {
      inherit name cc cxx version capabilities flagTranslators;
      inherit defaultCFlags defaultCxxFlags runtimeInputs environment package;

      # =======================================================================
      # Methods
      # =======================================================================

      # Translate a single abstract flag to concrete CLI args
      translateFlag = flag:
        if flagTranslators ? ${flag.type}
        then flagTranslators.${flag.type} flag
        else throw "nixnative: compiler '${name}' does not support flag type '${flag.type}'";

      # Translate multiple flags
      translateFlags = flagList:
        lib.concatMap (f:
          if flagTranslators ? ${f.type}
          then flagTranslators.${f.type} f
          else throw "nixnative: compiler '${name}' does not support flag type '${f.type}'"
        ) flagList;

      # Check if a capability is supported
      hasCapability = cap:
        if cap == "lto" then capabilities.lto or null != null
        else if cap == "sanitizers" then (capabilities.sanitizers or []) != []
        else capabilities.${cap} or false;

      # Get supported sanitizers
      supportedSanitizers = capabilities.sanitizers or [];

      # Check if a specific sanitizer is supported
      supportsSanitizer = san: builtins.elem san (capabilities.sanitizers or []);
    };

  # ==========================================================================
  # Common Flag Translators
  # ==========================================================================

  # Clang-style flag translators (also work for GCC in most cases)
  commonFlagTranslators = {
    lto = flag:
      if flag.value == "thin" then [ "-flto=thin" ]
      else if flag.value == "full" then [ "-flto" ]
      else [];

    sanitizer = flag: [ "-fsanitize=${flag.value}" ];

    coverage = _: [ "--coverage" "-fprofile-arcs" "-ftest-coverage" ];

    optimize = flag: [ "-O${flag.value}" ];

    debug = flag:
      if flag.value == "none" then [ "-g0" ]
      else if flag.value == "line-tables" then [ "-gline-tables-only" ]
      else [ "-g" ];

    standard = flag: [ "-std=${flag.value}" ];

    warnings = flag:
      if flag.value == "none" then [ "-w" ]
      else if flag.value == "default" then []
      else if flag.value == "all" then [ "-Wall" ]
      else if flag.value == "extra" then [ "-Wall" "-Wextra" ]
      else if flag.value == "pedantic" then [ "-Wall" "-Wextra" "-Wpedantic" ]
      else [];

    colorDiagnostics = flag:
      if flag.value then [ "-fdiagnostics-color=always" ]
      else [ "-fdiagnostics-color=never" ];

    pic = _: [ "-fPIC" ];
  };

  # GCC-specific overrides
  gccFlagTranslators = commonFlagTranslators // {
    lto = flag:
      if flag.value == "thin" then [ "-flto=auto" "-fno-fat-lto-objects" ]
      else if flag.value == "full" then [ "-flto" ]
      else [];

    debug = flag:
      if flag.value == "none" then [ "-g0" ]
      else if flag.value == "line-tables" then [ "-g1" ]
      else [ "-g" ];
  };

  # Zig cc flag translators
  zigFlagTranslators = commonFlagTranslators // {
    # Zig handles LTO differently
    lto = _: [];  # LTO is automatic in release modes

    # Zig optimization uses different syntax internally but accepts -O
    optimize = flag:
      let
        zigLevel = {
          "0" = "Debug";
          "1" = "ReleaseSafe";
          "2" = "ReleaseFast";
          "3" = "ReleaseFast";
          "s" = "ReleaseSmall";
          "z" = "ReleaseSmall";
        }.${flag.value} or "Debug";
      in [ "-O${zigLevel}" ];
  };

  # ==========================================================================
  # Validation Helpers
  # ==========================================================================

  # Validate compiler structure
  validateCompiler = compiler:
    let
      required = [ "name" "cc" "cxx" ];
      missing = builtins.filter (f: !(compiler ? ${f})) required;
    in
    if missing != []
    then throw "nixnative: compiler missing required fields: ${lib.concatStringsSep ", " missing}"
    else compiler;
}
