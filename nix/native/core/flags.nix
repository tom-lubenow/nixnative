# Abstract flag system for nixnative
#
# Flags are represented as typed objects that compilers translate
# to their specific command-line syntax via flagTranslators.
#
{ lib }:

rec {
  # ==========================================================================
  # Abstract Flag Constructors
  # ==========================================================================

  # Link-Time Optimization
  # mode: "thin", "full", or true (defaults to thin)
  lto = mode: {
    type = "lto";
    value = if mode == true then "thin" else mode;
  };

  # Sanitizer flags
  # name: "address", "thread", "undefined", "memory", "leak"
  sanitizer = name: {
    type = "sanitizer";
    value = name;
  };

  # Code coverage instrumentation
  coverage = {
    type = "coverage";
    value = true;
  };

  # Optimization level
  # level: "0", "1", "2", "3", "s", "z", "fast"
  optimize = level: {
    type = "optimize";
    value = level;
  };

  # Debug information level
  # level: "none", "line-tables", "full"
  debug = level: {
    type = "debug";
    value = level;
  };

  # Language standard
  # std: "c++17", "c++20", "c++23", "c11", "c17", "c23"
  standard = std: {
    type = "standard";
    value = std;
  };

  # Warning level
  # level: "none", "default", "all", "extra", "pedantic"
  warnings = level: {
    type = "warnings";
    value = level;
  };

  # Color diagnostics
  colorDiagnostics = enable: {
    type = "colorDiagnostics";
    value = enable;
  };

  # Position Independent Code (for shared libs)
  pic = {
    type = "pic";
    value = true;
  };

  # ==========================================================================
  # Flag Utilities
  # ==========================================================================

  # Check if a flag is of a specific type
  isType = type: flag: flag.type == type;

  # Extract flags of a specific type from a list
  filterByType = type: flags: builtins.filter (isType type) flags;

  # Translate a list of abstract flags using a compiler's translators
  translateFlags = { compiler, flags }:
    lib.concatMap (flag:
      if compiler.flagTranslators ? ${flag.type}
      then compiler.flagTranslators.${flag.type} flag
      else throw "nixnative: compiler '${compiler.name}' does not support flag type '${flag.type}'"
    ) flags;

  # Build abstract flags from builder arguments
  # This converts the ergonomic API (lto = "thin") to abstract flags
  fromArgs = args:
    let
      optionalFlag = cond: flag: if cond then [ flag ] else [ ];
    in
    # LTO
    (optionalFlag (args.lto or false != false) (lto args.lto))
    # Sanitizers
    ++ (map sanitizer (args.sanitizers or []))
    # Coverage
    ++ (optionalFlag (args.coverage or false) coverage)
    # Optimization (only if explicitly set)
    ++ (optionalFlag (args ? optimize) (optimize args.optimize))
    # Debug (only if explicitly set)
    ++ (optionalFlag (args ? debug) (debug args.debug))
    # Standard (only if explicitly set)
    ++ (optionalFlag (args ? standard) (standard args.standard))
    # Warnings
    ++ (optionalFlag (args ? warnings) (warnings args.warnings))
    # PIC
    ++ (optionalFlag (args.pic or false) pic);

  # ==========================================================================
  # Capability Checking
  # ==========================================================================

  # Check if a compiler supports a specific flag
  compilerSupports = { compiler, flag }:
    let
      cap = compiler.capabilities or {};
    in
    if flag.type == "lto" then
      cap.lto or null != null &&
      (flag.value == "thin" -> cap.lto.thin or false) &&
      (flag.value == "full" -> cap.lto.full or false)
    else if flag.type == "sanitizer" then
      builtins.elem flag.value (cap.sanitizers or [])
    else if flag.type == "coverage" then
      cap.coverage or false
    else
      # Other flags assumed to be universally supported
      true;

  # Validate all flags against compiler capabilities
  validateFlags = { compiler, flags }:
    let
      unsupported = builtins.filter (f: !compilerSupports { inherit compiler; flag = f; }) flags;
      formatFlag = f: "${f.type}=${toString f.value}";
    in
    if unsupported == [] then flags
    else throw "nixnative: compiler '${compiler.name}' does not support flags: ${lib.concatMapStringsSep ", " formatFlag unsupported}";
}
