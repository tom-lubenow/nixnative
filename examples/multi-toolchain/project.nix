{ pkgs, native }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  root = ./.;
  sources = [ "src/main.cc" ];

  # ============================================================================
  # HIGH-LEVEL API EXAMPLES
  # ============================================================================

  # Default: clang + platform default linker
  default = native.executable {
    name = "demo-default";
    inherit root sources;
  };

  # Explicit compiler selection
  withGcc = native.executable {
    compiler = "gcc";
    name = "demo-gcc";
    inherit root sources;
  };

  # Compiler + linker selection (mold is Linux-only)
  withClangMold = native.executable {
    compiler = "clang";
    linker = "mold";
    name = "demo-clang-mold";
    inherit root sources;
  };

  withGccMold = native.executable {
    compiler = "gcc";
    linker = "mold";
    name = "demo-gcc-mold";
    inherit root sources;
  };

  # ============================================================================
  # ABSTRACT FLAGS EXAMPLES
  # ============================================================================

  withO3 = native.executable {
    name = "demo-o3";
    inherit root sources;
    flags = [
      { type = "optimize"; value = "3"; }
    ];
  };

  withLtoThin = native.executable {
    name = "demo-lto-thin";
    inherit root sources;
    flags = [
      { type = "lto"; value = "thin"; }
      { type = "optimize"; value = "2"; }
    ];
  };

  withLtoFull = native.executable {
    name = "demo-lto-full";
    inherit root sources;
    flags = [
      { type = "lto"; value = "full"; }
      { type = "optimize"; value = "2"; }
    ];
  };

  withDebug = native.executable {
    name = "demo-debug";
    inherit root sources;
    flags = [
      { type = "debug"; value = "full"; }
      { type = "optimize"; value = "0"; }
    ];
  };

  # Sanitizers (Linux only)
  withAsan = native.executable {
    name = "demo-asan";
    inherit root sources;
    flags = [
      { type = "sanitizer"; value = "address"; }
      { type = "sanitizer"; value = "undefined"; }
    ];
  };

  # Combined: GCC + mold + LTO + O3
  optimizedGcc = native.executable {
    compiler = "gcc";
    linker = "mold";
    name = "demo-optimized-gcc";
    inherit root sources;
    flags = [
      { type = "lto"; value = "full"; }
      { type = "optimize"; value = "3"; }
    ];
  };

  # ============================================================================
  # LOW-LEVEL API EXAMPLES
  # ============================================================================

  lowLevelDefault = native.mkExecutable {
    toolchain = native.toolchains.default;
    name = "demo-lowlevel-default";
    inherit root sources;
  };

  lowLevelCustom = native.mkExecutable {
    toolchain = native.mkToolchain {
      compiler = native.compilers.clang;
      linker = native.linkers.lld;
    };
    name = "demo-lowlevel-custom";
    inherit root sources;
    flags = [
      { type = "optimize"; value = "2"; }
    ];
  };

  # ============================================================================
  # BUILD MATRIX
  # ============================================================================

  buildMatrix =
    let
      configs = [
        { name = "clang-lld"; compiler = "clang"; linker = "lld"; }
        { name = "clang-mold"; compiler = "clang"; linker = "mold"; }
        { name = "gcc-lld"; compiler = "gcc"; linker = "lld"; }
        { name = "gcc-mold"; compiler = "gcc"; linker = "mold"; }
      ];

      availableConfigs = builtins.filter (cfg:
        if cfg.linker == "mold" then isLinux
        else if cfg.compiler == "gcc" then native.compilers.gcc != null
        else true
      ) configs;

      mkBuild = cfg: {
        name = "matrix-${cfg.name}";
        value = native.executable {
          inherit (cfg) compiler linker;
          name = "demo-${cfg.name}";
          inherit root sources;
        };
      };
    in
    builtins.listToAttrs (map mkBuild availableConfigs);

in
# Cross-platform packages
{
  inherit default withGcc withO3 withLtoThin withLtoFull withDebug;
  inherit lowLevelDefault lowLevelCustom;
}
// buildMatrix
# Linux-only packages
// (if isLinux then {
  inherit withClangMold withGccMold withAsan optimizedGcc;
} else {})
