# Rust builders for nixnative
#
# Build Rust crates without Cargo. Supports:
# - Pure Rust executables
# - Rust libraries (rlib for Rust consumers)
# - Static libraries for C/C++ linking
# - Dynamic libraries for C/C++ linking
#
# NOTE: Rust crates compile as a unit (not per-file like C/C++).
# The entry point (lib.rs/main.rs) includes other files via `mod`.
#
{
  pkgs,
  lib,
  utils,
  platform,
}:

let
  inherit (lib) concatStringsSep optional optionalString replaceStrings;
  inherit (utils) sanitizePath sanitizeName;

  # Rust crate names cannot have hyphens, convert to underscores
  sanitizeCrateName = name: replaceStrings [ "-" ] [ "_" ] name;

in
rec {
  # ==========================================================================
  # Rust Crate Compilation
  # ==========================================================================

  # Compile a Rust crate
  #
  # Arguments:
  #   toolchain    - Toolchain with Rust support
  #   name         - Crate name
  #   root         - Source root directory
  #   entry        - Crate entry point (e.g., "src/lib.rs" or "src/main.rs")
  #   crateType    - Crate type: "bin", "lib", "rlib", "staticlib", "cdylib"
  #   edition      - Rust edition: "2015", "2018", "2021", "2024"
  #   optimize     - Optimization level: "0", "1", "2", "3", "s", "z"
  #   debug        - Debug info: "none", "line-tables", "full"
  #   lto          - LTO mode: null, "thin", "full"
  #   features     - List of feature flags to enable
  #   extraFlags   - Additional rustc flags
  #   deps         - Rust crate dependencies (from other mkRustLib calls)
  #   cDeps        - C/C++ library dependencies (for linking)
  #
  mkRustCrate =
    {
      toolchain,
      name,
      root,
      entry,
      crateType ? "bin",
      edition ? "2021",
      optimize ? "2",
      debug ? "none",
      lto ? null,
      features ? [ ],
      extraFlags ? [ ],
      deps ? [ ],
      cDeps ? [ ],
    }:
    let
      tc = toolchain;

      # Sanitize the crate name (Rust doesn't allow hyphens)
      crateName = sanitizeCrateName name;

      # Ensure toolchain has Rust
      rustConfig = tc.getRustConfig;
      rustc = rustConfig.compiler;

      # Build source tree
      srcRoot = sanitizePath { path = root; };

      # Edition flag
      editionFlag = [ "--edition=${edition}" ];

      # Crate type flag
      typeFlags = rustConfig.crateTypeFlags.${crateType} or
        (throw "Unknown Rust crate type: ${crateType}");

      # Optimization flags
      optFlags = rustConfig.optimizeFlags.${optimize} or [ ];

      # Debug flags
      dbgFlags =
        if debug == "none" then [ ]
        else if debug == "line-tables" then [ "-C" "debuginfo=1" ]
        else if debug == "full" then [ "-C" "debuginfo=2" ]
        else [ ];

      # LTO flags
      ltoFlags =
        if lto == null then [ ]
        else rustConfig.ltoFlags.${lto} or [ ];

      # Feature flags
      featureFlags = map (f: "--cfg=feature=\"${f}\"") features;

      # Collect extern crate paths from Rust dependencies
      externFlags = lib.concatMap (dep: [
        "--extern"
        "${dep.crateName}=${dep.rlib}"
      ]) deps;

      # Collect -L paths for Rust dependencies
      searchPaths = map (dep: "-L" + (builtins.dirOf dep.rlib)) deps;

      # Collect link flags from C dependencies
      cLinkFlags = lib.concatMap (dep:
        if dep ? public && dep.public ? linkFlags then
          dep.public.linkFlags
        else
          [ ]
      ) cDeps;

      # Output filename (use crateName for rlib since that's how Rust names them)
      outputName =
        if crateType == "bin" then name
        else if crateType == "staticlib" then "lib${crateName}.a"
        else if crateType == "cdylib" then
          "lib${crateName}${platform.sharedLibExtension tc.targetPlatform}"
        else if crateType == "rlib" || crateType == "lib" then "lib${crateName}.rlib"
        else if crateType == "dylib" then
          "lib${crateName}${platform.sharedLibExtension tc.targetPlatform}"
        else name;

      # Output directory
      outputDir =
        if crateType == "bin" then "bin"
        else "lib";

      # All flags combined
      allFlags =
        editionFlag
        ++ typeFlags
        ++ optFlags
        ++ dbgFlags
        ++ ltoFlags
        ++ featureFlags
        ++ externFlags
        ++ searchPaths
        ++ extraFlags;

      # Runtime inputs
      buildInputs = tc.runtimeInputs ++ (lib.concatMap (dep: dep.evalInputs or [ ]) deps);

      # Build the crate
      drv = pkgs.runCommand "${sanitizeName name}-rust"
        ({
          inherit buildInputs;
          src = srcRoot;
        } // tc.environment)
        ''
          set -euo pipefail
          mkdir -p "$out/${outputDir}"

          ${rustc} \
            ${concatStringsSep " " allFlags} \
            --crate-name ${crateName} \
            -o "$out/${outputDir}/${outputName}" \
            "$src/${entry}" \
            ${optionalString (cLinkFlags != [ ]) (concatStringsSep " " (map (f: "-C link-arg=${f}") cLinkFlags))}
        '';

    in
    drv // {
      inherit name crateName;
      artifactType = "rust-${crateType}";

      # Paths for consumers
      rlib = "${drv}/${outputDir}/${outputName}";
      executablePath = if crateType == "bin" then "${drv}/bin/${name}" else null;
      libraryPath = if crateType != "bin" then "${drv}/lib/${outputName}" else null;

      # For C/C++ consumers of staticlib/cdylib
      public = if crateType == "staticlib" || crateType == "cdylib" then {
        includeDirs = [ ];
        defines = [ ];
        cxxFlags = [ ];
        linkFlags = [ "${drv}/lib/${outputName}" ];
      } else null;

      # Passthru for introspection
      passthru = {
        inherit toolchain entry crateType edition;
        inherit deps cDeps;
      };
    };

  # ==========================================================================
  # High-Level Rust Builders
  # ==========================================================================

  # Build a Rust executable
  mkRustExecutable =
    args:
    mkRustCrate (args // { crateType = "bin"; });

  # Build a Rust library (rlib for Rust consumers)
  mkRustLib =
    args:
    mkRustCrate (args // { crateType = "rlib"; });

  # Build a static library for C/C++ linking
  mkRustStaticLib =
    args:
    mkRustCrate (args // { crateType = "staticlib"; });

  # Build a dynamic library for C/C++ linking
  mkRustDylib =
    args:
    mkRustCrate (args // { crateType = "cdylib"; });
}
