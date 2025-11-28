# Platform detection and utilities for nixnative
#
# Provides helpers for platform-specific logic in toolchains and builders.
#
{ lib }:

rec {
  # ==========================================================================
  # Platform Detection
  # ==========================================================================

  # Check if a platform is Darwin (macOS)
  isDarwin = platform: platform.isDarwin or false;

  # Check if a platform is Linux
  isLinux = platform: platform.isLinux or false;

  # Check if a platform is Windows
  isWindows = platform: platform.isWindows or false;

  # Check if a platform is BSD (FreeBSD, OpenBSD, etc.)
  isBSD = platform: platform.isBSD or false;

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
  sharedLibExtension =
    platform:
    if isDarwin platform then
      ".dylib"
    else if isWindows platform then
      ".dll"
    else
      ".so";

  # Get default static library extension
  staticLibExtension = _: ".a";

  # Get default executable extension
  executableExtension = platform: if isWindows platform then ".exe" else "";

  # Get default object file extension
  objectExtension = _: ".o";

  # ==========================================================================
  # Darwin-Specific Helpers
  # ==========================================================================

  # Get default deployment target for Darwin
  defaultDeploymentTarget =
    platform: if isDarwin platform then if isAarch64 platform then "11.0" else "10.15" else null;

  # Framework search path flag
  frameworkSearchPath = path: [
    "-F"
    path
  ];

  # Link a framework
  linkFramework = name: [
    "-framework"
    name
  ];

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
  # Darwin: Position independence is handled differently via Mach-O format
  # and doesn't require explicit -fPIC for most use cases.
  #
  defaultCompileFlags = platform: if isLinux platform then [ "-fPIC" ] else [ ];

  # Get platform-specific flags required for linking (beyond linker defaults)
  # Reserved for future platform-specific link requirements
  defaultLinkFlags = _platform: [ ];

  # ==========================================================================
  # Linux-Specific Helpers
  # ==========================================================================

  # Get rpath flag syntax
  rpathFlag =
    platform: path: if isDarwin platform then [ "-Wl,-rpath,${path}" ] else [ "-Wl,-rpath,${path}" ];

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
      os =
        if isDarwin platform then
          "macOS"
        else if isLinux platform then
          "Linux"
        else if isWindows platform then
          "Windows"
        else if isBSD platform then
          "BSD"
        else
          "Unknown";
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
