# GCC compiler implementation for nixnative
#
# Exports language configs for use in toolchains:
#   native.compilers.gcc.c   - C compiler
#   native.compilers.gcc.cpp - C++ compiler
#
{
  pkgs,
  mkCompiler,
  mkGccStyleScanner,
}:

let
  # Helper to create GCC language configs for a specific version
  mkGCC =
    {
      gccPackage,
      name ? "gcc${gccPackage.version}",
    }:
    let
      gcc = gccPackage;

      sharedRuntimeInputs = [
        gcc
        pkgs.binutils
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gawk
      ];

      capabilities = {
        lto = {
          thin = false;
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

      bintools = {
        ar = "${pkgs.binutils}/bin/ar";
        ranlib = "${pkgs.binutils}/bin/ranlib";
        nm = "${pkgs.binutils}/bin/nm";
        objcopy = "${pkgs.binutils}/bin/objcopy";
        strip = "${pkgs.binutils}/bin/strip";
      };
    in
    {
      inherit name;
      version = gcc.version;
      package = gcc;

      # Bintools for this compiler
      inherit bintools;

      # Language configs
      c = {
        name = "${name}-c";
        language = "c";
        compiler = "${gcc}/bin/gcc";
        defaultFlags = [ ];
        runtimeInputs = sharedRuntimeInputs;
        environment = { };
        inherit capabilities;
        inherit bintools;

        # Scanner configuration for C files
        scanner = mkGccStyleScanner {
          compiler = "${gcc}/bin/gcc";
          runtimeInputs = [ gcc ];
          extraFlags = [ "-fdirectives-only" ];
        };
      };

      cpp = {
        name = "${name}-cpp";
        language = "cpp";
        compiler = "${gcc}/bin/g++";
        defaultFlags = [
          "-std=c++20"
          "-fdiagnostics-color=always"
          "-Wall"
          "-Wextra"
        ];
        runtimeInputs = sharedRuntimeInputs;
        environment = { };
        inherit capabilities;
        cxxRuntimeLibPath = "${gcc.cc.lib}/lib";
        inherit bintools;

        # Scanner configuration for C++ files
        scanner = mkGccStyleScanner {
          compiler = "${gcc}/bin/g++";
          runtimeInputs = [ gcc ];
          extraFlags = [ "-fdirectives-only" ];
        };
      };

    };

in
rec {
  # GCC 13
  gcc13 = mkGCC { gccPackage = pkgs.gcc13; };

  # GCC 14 (if available)
  gcc14 = if pkgs ? gcc14 then mkGCC { gccPackage = pkgs.gcc14; } else null;

  # GCC 12
  gcc12 = mkGCC { gccPackage = pkgs.gcc12; };

  # Default GCC (13)
  gcc = gcc13;
}
