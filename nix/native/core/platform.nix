# Platform detection and utilities for nixnative
#
# Provides helpers for platform-specific logic in toolchains and builders.
# Currently Linux-only.
#
{ lib }:

rec {
  # ==========================================================================
  # Platform Detection
  # ==========================================================================

  # Check if a platform is Linux
  isLinux = platform: platform.isLinux or false;

  # ==========================================================================
  # Architecture Detection
  # ==========================================================================

  # Check if platform is x86_64
  isX86_64 = platform: platform.isx86_64 or false;

  # Check if platform is aarch64 (ARM64)
  isAarch64 = platform: platform.isAarch64 or false;

  # Check if platform is 64-bit
  is64Bit = platform: platform.is64bit or false;

  # ==========================================================================
  # Platform-Specific Defaults
  # ==========================================================================

  # Get default shared library extension
  sharedLibExtension = _platform: ".so";

  # Get default static library extension
  staticLibExtension = _: ".a";

  # Get default executable extension
  executableExtension = _platform: "";

  # Get default object file extension
  objectExtension = _: ".o";

  # ==========================================================================
  # Platform-Specific Compiler Flags
  # ==========================================================================

  # Get platform-specific flags required for compilation
  #
  # Linux: -fPIC is required for:
  #   - Shared libraries (.so files)
  #   - Static libraries that may be linked into PIE executables
  #   - Code using dlopen/dlsym
  # On x86_64, -fPIC has essentially zero performance overhead.
  # Modern Linux distributions enable PIE by default for security (ASLR).
  #
  defaultCompileFlags = platform: if isLinux platform then [ "-fPIC" ] else [ ];

  # Get platform-specific flags required for linking (beyond linker defaults)
  defaultLinkFlags = _platform: [ ];

  # ==========================================================================
  # Linux-Specific Helpers
  # ==========================================================================

  # Get rpath flag syntax
  rpathFlag = _platform: path: [ "-Wl,-rpath,${path}" ];

  # Linux library group flags (for circular dependencies)
  startLibraryGroup = platform: if isLinux platform then [ "-Wl,--start-group" ] else [ ];

  endLibraryGroup = platform: if isLinux platform then [ "-Wl,--end-group" ] else [ ];

  # ==========================================================================
  # Cross-Compilation Helpers
  # ==========================================================================

  # Check if we're cross-compiling
  isCrossCompiling = buildPlatform: targetPlatform: buildPlatform.system != targetPlatform.system;

  # Get target triple for compiler
  getTargetTriple = platform: platform.config or platform.system;

  # ==========================================================================
  # Platform Info
  # ==========================================================================

  # Get a human-readable platform description
  describePlatform =
    platform:
    let
      os = if isLinux platform then "Linux" else "Unknown";
      arch =
        if isX86_64 platform then
          "x86_64"
        else if isAarch64 platform then
          "aarch64"
        else
          platform.parsed.cpu.name or "unknown";
    in
    "${os} (${arch})";
}
