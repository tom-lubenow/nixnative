# Compiler abstraction for nixnative
#
# A compiler is defined by its binaries, capabilities, and flag translators.
# Different compilers (clang, gcc) implement this interface.
#
# Language configs also include a scanner configuration that encapsulates
# how to scan source files for header dependencies. This keeps compiler-specific
# details (flags, tools, output formats) encapsulated within the compiler layer.
#
# Scanner Interface:
# ------------------
# Each language config should provide a `scanner` attribute:
#
#   scanner = {
#     # Generate the shell command to scan a single file for dependencies.
#     # The command should write dependency information to `depfile`.
#     # Arguments:
#     #   file    - path to source file (relative to working directory)
#     #   depfile - path where dependency output should be written
#     #   flags   - compiler flags string (includes, defines, extras)
#     # Returns: shell command string
#     mkScanCommand : { file, depfile, flags } -> string
#
#     # Output format produced by the scan command.
#     # Supported values:
#     #   "make" - Make-format .d files (target: dep1 dep2 ...)
#     #   "json" - JSON format (e.g., clang -MJ)
#     outputFormat : string
#
#     # Packages required in the build environment for scanning.
#     runtimeInputs : [package]
#   };
#
{ lib, flags }:

rec {
  # ==========================================================================
  # Compiler Factory
  # ==========================================================================

  mkCompiler =
    {
      name, # Identifier: "clang18", "gcc14"
      cc, # Path to C compiler binary
      cxx, # Path to C++ compiler binary
      version ? null, # Version string (for display/capability detection)

      # Capability declarations - what features this compiler supports
      capabilities ? {
        lto = null; # null = unsupported, { thin = bool; full = bool; }
        sanitizers = [ ]; # List of supported sanitizers
        coverage = false;
        modules = false; # C++20 modules
        pch = false; # Precompiled headers
        colorDiagnostics = false;
      },

      # Flag translators - convert abstract flags to concrete CLI args
      flagTranslators ? { },

      # Default flags applied to all compilations
      defaultCFlags ? [ ],
      defaultCxxFlags ? [ ],

      # Packages needed at build time
      runtimeInputs ? [ ],

      # Environment variables
      environment ? { },

      # Optional: reference to the compiler package (for dev shells)
      package ? null,

      # Path to C++ runtime library (for rpath on Linux)
      cxxRuntimeLibPath ? null,
    }:
    {
      inherit
        name
        cc
        cxx
        version
        capabilities
        flagTranslators
        ;
      inherit
        defaultCFlags
        defaultCxxFlags
        runtimeInputs
        environment
        package
        ;
      inherit cxxRuntimeLibPath;

      # =======================================================================
      # Methods
      # =======================================================================

      # Translate a single abstract flag to concrete CLI args
      translateFlag =
        flag:
        if flagTranslators ? ${flag.type} then
          flagTranslators.${flag.type} flag
        else
          throw "nixnative: compiler '${name}' does not support flag type '${flag.type}'";

      # Translate multiple flags
      translateFlags =
        flagList:
        lib.concatMap (
          f:
          if flagTranslators ? ${f.type} then
            flagTranslators.${f.type} f
          else
            throw "nixnative: compiler '${name}' does not support flag type '${f.type}'"
        ) flagList;

      # Check if a capability is supported
      hasCapability =
        cap:
        if cap == "lto" then
          capabilities.lto or null != null
        else if cap == "sanitizers" then
          (capabilities.sanitizers or [ ]) != [ ]
        else
          capabilities.${cap} or false;

      # Get supported sanitizers
      supportedSanitizers = capabilities.sanitizers or [ ];

      # Check if a specific sanitizer is supported
      supportsSanitizer = san: builtins.elem san (capabilities.sanitizers or [ ]);
    };

  # ==========================================================================
  # Common Flag Translators
  # ==========================================================================

  # Clang-style flag translators (also work for GCC in most cases)
  commonFlagTranslators = {
    lto =
      flag:
      if flag.value == "thin" then
        [ "-flto=thin" ]
      else if flag.value == "full" then
        [ "-flto" ]
      else
        [ ];

    sanitizer = flag: [ "-fsanitize=${flag.value}" ];

    coverage = _: [
      "--coverage"
      "-fprofile-arcs"
      "-ftest-coverage"
    ];

    optimize = flag: [ "-O${flag.value}" ];

    debug =
      flag:
      if flag.value == "none" then
        [ "-g0" ]
      else if flag.value == "line-tables" then
        [ "-gline-tables-only" ]
      else
        [ "-g" ];

    standard = flag: [ "-std=${flag.value}" ];

    warnings =
      flag:
      if flag.value == "none" then
        [ "-w" ]
      else if flag.value == "default" then
        [ ]
      else if flag.value == "all" then
        [ "-Wall" ]
      else if flag.value == "extra" then
        [
          "-Wall"
          "-Wextra"
        ]
      else if flag.value == "pedantic" then
        [
          "-Wall"
          "-Wextra"
          "-Wpedantic"
        ]
      else
        [ ];

    colorDiagnostics =
      flag: if flag.value then [ "-fdiagnostics-color=always" ] else [ "-fdiagnostics-color=never" ];

    pic = _: [ "-fPIC" ];
  };

  # GCC-specific overrides
  gccFlagTranslators = commonFlagTranslators // {
    lto =
      flag:
      if flag.value == "thin" then
        [
          "-flto=auto"
          "-fno-fat-lto-objects"
        ]
      else if flag.value == "full" then
        [ "-flto" ]
      else
        [ ];

    debug =
      flag:
      if flag.value == "none" then
        [ "-g0" ]
      else if flag.value == "line-tables" then
        [ "-g1" ]
      else
        [ "-g" ];
  };

  # ==========================================================================
  # Validation Helpers
  # ==========================================================================

  # Validate compiler structure
  validateCompiler =
    compiler:
    let
      required = [
        "name"
        "cc"
        "cxx"
      ];
      missing = builtins.filter (f: !(compiler ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: compiler missing required fields: ${lib.concatStringsSep ", " missing}"
    else
      compiler;

  # ==========================================================================
  # Scanner Helpers
  # ==========================================================================

  # Validate a scanner configuration
  validateScanner =
    { scanner, context ? "unknown" }:
    let
      required = [ "mkScanCommand" "outputFormat" "runtimeInputs" ];
      missing = builtins.filter (f: !(scanner ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: scanner for '${context}' missing required fields: ${lib.concatStringsSep ", " missing}"
    else if !(builtins.elem scanner.outputFormat [ "make" "json" ]) then
      throw "nixnative: scanner for '${context}' has invalid outputFormat '${scanner.outputFormat}'. Must be 'make' or 'json'."
    else
      scanner;

  # Create a scanner configuration for GCC-style compilers (-MMD -MF)
  # This is the common pattern for clang and gcc.
  mkGccStyleScanner =
    {
      compiler,       # Path to compiler binary
      runtimeInputs,  # Packages to include
      extraFlags ? [], # Additional flags (e.g., -fdirectives-only)
    }:
    {
      mkScanCommand = { file, depfile, flags }:
        let
          allFlags = lib.concatStringsSep " " (extraFlags ++ [ flags ]);
        in
        ''
          ${compiler} \
            -E ${allFlags} \
            -MMD -MF ${depfile} \
            -w \
            ${file} \
            -o /dev/null 2>/dev/null || true
        '';

      outputFormat = "make";
      inherit runtimeInputs;
    };
}
