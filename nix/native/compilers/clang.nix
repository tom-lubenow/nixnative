# Clang compiler implementation for nixnative
#
# Provides clang variants using the mkCompiler factory.
#
{ pkgs, lib, mkCompiler, commonFlagTranslators }:

let
  inherit (lib) optionals optionalAttrs;

  # Helper to create a clang compiler for a specific LLVM version
  mkClang = { llvmPackages, name ? "clang${llvmPackages.release_version}" }:
    let
      llvm = llvmPackages;
      libcxx = llvm.libcxx;
      libcxxDev = llvm.libcxx.dev;
      targetPlatform = pkgs.stdenv.targetPlatform;
      isDarwin = targetPlatform.isDarwin;

      # Darwin SDK setup
      sdkRoot =
        if isDarwin then
          pkgs.apple-sdk.sdkroot
        else
          null;

      deploymentTarget =
        if isDarwin then
          targetPlatform.darwinMinVersion or "11.0"
        else
          null;

      darwinLibcxxInclude =
        if isDarwin then
          "${libcxxDev}/include/c++/v1"
        else
          null;

      # Darwin-specific C++ flags
      darwinCxxFlags =
        if isDarwin then [
          "-isysroot" (builtins.toString sdkRoot)
          "-isystem" darwinLibcxxInclude
        ]
        else [];

      # Darwin-specific environment
      darwinEnv =
        if isDarwin then {
          SDKROOT = builtins.toString sdkRoot;
          MACOSX_DEPLOYMENT_TARGET = deploymentTarget;
        }
        else {};

      # Darwin-specific runtime inputs
      darwinRuntimeInputs =
        if isDarwin then [
          pkgs.stdenv.cc.bintools.bintools
          pkgs.darwin.cctools
          pkgs.apple-sdk
          libcxx
          libcxxDev
        ]
        else [];
    in
    mkCompiler {
      inherit name;
      cc = "${llvm.clang}/bin/clang";
      cxx = "${llvm.clang}/bin/clang++";
      version = llvm.release_version;

      capabilities = {
        lto = { thin = true; full = true; };
        sanitizers = [ "address" "thread" "undefined" "leak" ]
          ++ optionals (!isDarwin) [ "memory" ];  # memory sanitizer not on Darwin
        coverage = true;
        modules = false;  # C++20 modules still experimental
        pch = true;
        colorDiagnostics = true;
      };

      flagTranslators = commonFlagTranslators // {
        # Clang-specific overrides if needed
        colorDiagnostics = flag:
          if flag.value then [ "-fcolor-diagnostics" ]
          else [ "-fno-color-diagnostics" ];
      };

      defaultCFlags = [];
      defaultCxxFlags = [
        "-std=c++20"
        "-fdiagnostics-color"
        "-Wall"
        "-Wextra"
      ] ++ darwinCxxFlags;

      runtimeInputs = [
        llvm.clang
        llvm.lld
        llvm.bintools
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gawk
      ] ++ darwinRuntimeInputs;

      environment = darwinEnv;

      package = llvm.clang;
    };

in rec {
  # ==========================================================================
  # Clang Compiler Variants
  # ==========================================================================

  # LLVM 18 (recommended)
  clang18 = mkClang { llvmPackages = pkgs.llvmPackages_18; };

  # LLVM 17
  clang17 = mkClang { llvmPackages = pkgs.llvmPackages_17; };

  # LLVM 19 (if available)
  clang19 =
    if pkgs ? llvmPackages_19
    then mkClang { llvmPackages = pkgs.llvmPackages_19; }
    else null;

  # Default clang (18)
  clang = clang18;

  # ==========================================================================
  # Helper: Get bintools for a clang version
  # ==========================================================================

  getBintools = compiler:
    let
      # Extract LLVM version from compiler name
      versionMatch = builtins.match "clang([0-9]+)" compiler.name;
      version = if versionMatch != null then builtins.head versionMatch else "18";
      llvmPkgs = pkgs."llvmPackages_${version}" or pkgs.llvmPackages_18;
    in {
      ar = "${llvmPkgs.bintools}/bin/ar";
      ranlib = "${llvmPkgs.bintools}/bin/ranlib";
      nm = "${llvmPkgs.bintools}/bin/nm";
      objcopy = "${llvmPkgs.bintools}/bin/objcopy";
      strip = "${llvmPkgs.bintools}/bin/strip";
    };

  # ==========================================================================
  # Darwin-specific linker info
  # ==========================================================================

  getDarwinLinkerInfo = { compiler }:
    let
      isDarwin = pkgs.stdenv.targetPlatform.isDarwin;
    in
    if isDarwin then {
      # On Darwin, use system ld64
      binary = "${pkgs.stdenv.cc.bintools.bintools}/bin/ld";
      driverFlag = "";  # No special flag needed, it's the default
    }
    else null;
}
