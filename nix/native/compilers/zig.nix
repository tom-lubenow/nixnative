# Zig compiler implementation for nixnative
#
# Zig can act as a C/C++ compiler via `zig cc` and `zig c++`.
# This provides cross-compilation capabilities and hermetic builds.
#
{ pkgs, lib, mkCompiler, zigFlagTranslators }:

let
  inherit (lib) optionals optionalAttrs;

  # Helper to create a Zig-based C/C++ compiler
  mkZigCC = { zigPackage, name ? "zig-cc" }:
    let
      zig = zigPackage;
      targetPlatform = pkgs.stdenv.targetPlatform;
      isDarwin = targetPlatform.isDarwin;

      # Zig cc wrapper scripts
      zigCC = pkgs.writeShellScriptBin "zig-cc" ''
        exec ${zig}/bin/zig cc "$@"
      '';

      zigCXX = pkgs.writeShellScriptBin "zig-c++" ''
        exec ${zig}/bin/zig c++ "$@"
      '';

      # Combined wrapper package
      zigWrapper = pkgs.symlinkJoin {
        name = "zig-cc-wrapper";
        paths = [ zigCC zigCXX ];
      };
    in
    mkCompiler {
      inherit name;
      cc = "${zigWrapper}/bin/zig-cc";
      cxx = "${zigWrapper}/bin/zig-c++";
      version = zig.version;

      capabilities = {
        # Zig handles LTO internally in release modes
        lto = { thin = false; full = false; };
        sanitizers = [ "undefined" ];  # Zig has limited sanitizer support via cc
        coverage = false;  # Coverage not directly supported
        modules = false;
        pch = false;  # Zig cc doesn't support PCH
        colorDiagnostics = true;
      };

      flagTranslators = zigFlagTranslators;

      defaultCFlags = [];
      defaultCxxFlags = [
        "-std=c++20"
      ];

      runtimeInputs = [
        zig
        pkgs.coreutils
      ];

      environment = {};

      package = zig;
    };

  # Cross-compilation target helper
  # Zig excels at cross-compilation with its -target flag
  mkZigCross = { zigPackage, target, name ? "zig-cc-${target}" }:
    let
      zig = zigPackage;

      zigCC = pkgs.writeShellScriptBin "zig-cc" ''
        exec ${zig}/bin/zig cc -target ${target} "$@"
      '';

      zigCXX = pkgs.writeShellScriptBin "zig-c++" ''
        exec ${zig}/bin/zig c++ -target ${target} "$@"
      '';

      zigWrapper = pkgs.symlinkJoin {
        name = "zig-cc-wrapper-${target}";
        paths = [ zigCC zigCXX ];
      };
    in
    mkCompiler {
      inherit name;
      cc = "${zigWrapper}/bin/zig-cc";
      cxx = "${zigWrapper}/bin/zig-c++";
      version = zig.version;

      capabilities = {
        lto = { thin = false; full = false; };
        sanitizers = [];
        coverage = false;
        modules = false;
        pch = false;
        colorDiagnostics = true;
      };

      flagTranslators = zigFlagTranslators;

      defaultCFlags = [];
      defaultCxxFlags = [ "-std=c++20" ];

      runtimeInputs = [ zig pkgs.coreutils ];
      environment = {};
      package = zig;
    };

in rec {
  # ==========================================================================
  # Zig CC Compiler Variants
  # ==========================================================================

  # Default Zig CC (native target)
  zigCC = mkZigCC { zigPackage = pkgs.zig; };

  # Alias
  zig = zigCC;

  # ==========================================================================
  # Cross-Compilation Helpers
  # ==========================================================================

  # Create a cross-compiler for a specific target
  # Example targets: "x86_64-linux-gnu", "aarch64-linux-gnu", "x86_64-macos"
  mkCrossCompiler = target: mkZigCross {
    zigPackage = pkgs.zig;
    inherit target;
  };

  # Common cross-compilation targets
  crossTargets = {
    x86_64-linux = mkCrossCompiler "x86_64-linux-gnu";
    aarch64-linux = mkCrossCompiler "aarch64-linux-gnu";
    x86_64-macos = mkCrossCompiler "x86_64-macos";
    aarch64-macos = mkCrossCompiler "aarch64-macos";
    x86_64-windows = mkCrossCompiler "x86_64-windows-gnu";
  };

  # ==========================================================================
  # Helper: Get bintools for Zig
  # ==========================================================================

  # Zig provides its own ar via `zig ar`
  getBintools = compiler:
    let
      zig = pkgs.zig;

      zigAr = pkgs.writeShellScriptBin "zig-ar" ''
        exec ${zig}/bin/zig ar "$@"
      '';

      zigRanlib = pkgs.writeShellScriptBin "zig-ranlib" ''
        exec ${zig}/bin/zig ranlib "$@"
      '';

      wrapper = pkgs.symlinkJoin {
        name = "zig-bintools";
        paths = [ zigAr zigRanlib ];
      };
    in {
      ar = "${wrapper}/bin/zig-ar";
      ranlib = "${wrapper}/bin/zig-ranlib";
      nm = "${pkgs.binutils}/bin/nm";  # Fall back to binutils for nm
      objcopy = "${pkgs.binutils}/bin/objcopy";
      strip = "${pkgs.binutils}/bin/strip";
    };
}
