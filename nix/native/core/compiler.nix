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
{ lib }:

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
      # Explicit feature list used for support queries
      supports ? null,

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
    let
      ltoCaps = capabilities.lto or null;
      derivedFeatures =
        lib.unique (
          (if ltoCaps != null then [ "lto" ] else [ ])
          ++ (if ltoCaps != null && (ltoCaps.thin or false) then [ "thinLto" ] else [ ])
          ++ (if (capabilities.sanitizers or [ ]) != [ ] then [ "sanitizers" ] else [ ])
          ++ (if capabilities.coverage or false then [ "coverage" ] else [ ])
          ++ (if capabilities.modules or false then [ "modules" ] else [ ])
          ++ (if capabilities.pch or false then [ "pch" ] else [ ])
          ++ (if capabilities.colorDiagnostics or false then [ "colorDiagnostics" ] else [ ])
        );

      finalSupports =
        if supports == null then
          { features = derivedFeatures; }
        else
          { features = lib.unique (supports.features or [ ]); };
    in
    {
      inherit
        name
        cc
        cxx
        version
        capabilities
        ;
      supports = finalSupports;
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

      # Check if a capability is supported
      hasCapability =
        cap: builtins.elem cap finalSupports.features;

      # Get supported sanitizers
      supportedSanitizers =
        if builtins.elem "sanitizers" finalSupports.features then
          capabilities.sanitizers or [ ]
        else
          [ ];

      # Check if a specific sanitizer is supported
      supportsSanitizer = san: builtins.elem san (capabilities.sanitizers or [ ]);
    };

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
