# Clang compiler implementation for nixnative
#
# Exports language configs for use in toolchains:
#   native.compilers.clang.c   - C compiler
#   native.compilers.clang.cpp - C++ compiler
#
{
  pkgs,
  mkCompiler,
  mkGccStyleScanner,
}:

let
  # Helper to create clang language configs for a specific LLVM version
  mkClang =
    {
      llvmPackages,
      name ? "clang${llvmPackages.release_version}",
    }:
    let
      llvm = llvmPackages;

      sharedRuntimeInputs = [
        llvm.clang
        llvm.lld
        llvm.bintools
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gawk
      ];

      capabilities = {
        lto = {
          thin = true;
          full = true;
        };
        sanitizers = [
          "address"
          "thread"
          "undefined"
          "leak"
          "memory"
        ];
        coverage = true;
        modules = false;
        pch = true;
        colorDiagnostics = true;
      };

    in
    {
      inherit name;
      version = llvm.release_version;
      package = llvm.clang;

      # Bintools for this compiler
      bintools = {
        ar = "${llvm.bintools}/bin/ar";
        ranlib = "${llvm.bintools}/bin/ranlib";
        nm = "${llvm.bintools}/bin/nm";
        objcopy = "${llvm.bintools}/bin/objcopy";
        strip = "${llvm.bintools}/bin/strip";
      };

      # Language configs
      c = {
        name = "${name}-c";
        language = "c";
        compiler = "${llvm.clang}/bin/clang";
        defaultFlags = [ ];
        runtimeInputs = sharedRuntimeInputs;
        environment = { };
        inherit capabilities;
        inherit bintools;

        # Scanner configuration for C files
        scanner = mkGccStyleScanner {
          compiler = "${llvm.clang}/bin/clang";
          runtimeInputs = [ llvm.clang ];
          extraFlags = [ "-fdirectives-only" ];
        };
      };

      cpp = {
        name = "${name}-cpp";
        language = "cpp";
        compiler = "${llvm.clang}/bin/clang++";
        defaultFlags = [
          "-std=c++20"
          "-fdiagnostics-color"
          "-Wall"
          "-Wextra"
        ];
        runtimeInputs = sharedRuntimeInputs;
        environment = { };
        inherit capabilities;
        cxxRuntimeLibPath = "${pkgs.stdenv.cc.cc.lib}/lib";
        inherit bintools;

        # Scanner configuration for C++ files
        scanner = mkGccStyleScanner {
          compiler = "${llvm.clang}/bin/clang++";
          runtimeInputs = [ llvm.clang ];
          extraFlags = [ "-fdirectives-only" ];
        };
      };

      # Bintools for this compiler
      inherit bintools;
    };

in
rec {
  # LLVM 18 (recommended)
  clang18 = mkClang { llvmPackages = pkgs.llvmPackages_18; };

  # LLVM 17
  clang17 = mkClang { llvmPackages = pkgs.llvmPackages_17; };

  # LLVM 19 (if available)
  clang19 = if pkgs ? llvmPackages_19 then mkClang { llvmPackages = pkgs.llvmPackages_19; } else null;

  # Default clang (18)
  clang = clang18;
}
