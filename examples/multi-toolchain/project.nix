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
  # COMPILE FLAGS EXAMPLES
  # ============================================================================

  withO3 = native.executable {
    name = "demo-o3";
    inherit root sources;
    compileFlags = [ "-O3" ];
  };

  withLtoThin = native.executable {
    name = "demo-lto-thin";
    inherit root sources;
    compileFlags = [ "-O2" "-flto=thin" ];
    linkFlags = [ "-flto=thin" ];
  };

  withLtoFull = native.executable {
    name = "demo-lto-full";
    inherit root sources;
    compileFlags = [ "-O2" "-flto" ];
    linkFlags = [ "-flto" ];
  };

  withDebug = native.executable {
    name = "demo-debug";
    inherit root sources;
    compileFlags = [ "-g" "-O0" ];
  };

  # Sanitizers (Linux only)
  withAsan = native.executable {
    name = "demo-asan";
    inherit root sources;
    compileFlags = [ "-fsanitize=address,undefined" ];
    linkFlags = [ "-fsanitize=address,undefined" ];
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
      languages = {
        c = native.compilers.clang.c;
        cpp = native.compilers.clang.cpp;
      };
      linker = native.linkers.lld;
      bintools = native.compilers.clang.bintools;
    };
    name = "demo-lowlevel-custom";
    inherit root sources;
    compileFlags = [ "-O2" ];
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
        # GCC doesn't support -fuse-ld=/full/path (only works with linker names)
        # So gcc + any alternative linker doesn't work with our current approach
        if cfg.compiler == "gcc" && cfg.linker != "ld" then false
        else if cfg.compiler == "gcc" then native.compilers.gcc != null
        # mold is Linux-only
        else if cfg.linker == "mold" then isLinux
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
# Note: withGccMold and optimizedGcc removed - GCC doesn't support -fuse-ld=/path
// (if isLinux then {
  inherit withClangMold withAsan;
} else {})
