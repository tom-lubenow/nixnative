# project.nix - Build definition for the multi-toolchain example
#
# Demonstrates building with different compilers, linkers, and optimization flags.

{ pkgs, native }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  root = ./.;
  sources = [ "src/main.cc" ];

  proj = native.project {
    inherit root;
  };

  # Build matrix helper
  buildMatrixTargets =
    let
      configs = [
        { name = "clang-lld"; compiler = "clang"; linker = "lld"; }
        { name = "clang-mold"; compiler = "clang"; linker = "mold"; }
        { name = "gcc-lld"; compiler = "gcc"; linker = "lld"; }
        { name = "gcc-mold"; compiler = "gcc"; linker = "mold"; }
      ];

      availableConfigs = builtins.filter (cfg:
        if cfg.compiler == "gcc" && cfg.linker != "ld" then false
        else if cfg.compiler == "gcc" then native.compilers.gcc != null
        else if cfg.linker == "mold" then isLinux
        else true
      ) configs;

      mkBuild = cfg: proj.executable {
        name = "demo-${cfg.name}";
        inherit root sources;
        inherit (cfg) compiler linker;
      };
    in
    builtins.listToAttrs (map (cfg: { name = "matrix-${cfg.name}"; value = mkBuild cfg; }) availableConfigs);

  default = proj.executable {
    name = "demo-default";
    inherit sources;
  };

  withGcc = proj.executable {
    name = "demo-gcc";
    inherit sources;
    compiler = "gcc";
  };

  withO3 = proj.executable {
    name = "demo-o3";
    inherit sources;
    compileFlags = [ "-O3" ];
  };

  withLtoThin = proj.executable {
    name = "demo-lto-thin";
    inherit sources;
    compileFlags = [ "-O2" "-flto=thin" ];
    linkFlags = [ "-flto=thin" ];
  };

  withLtoFull = proj.executable {
    name = "demo-lto-full";
    inherit sources;
    compileFlags = [ "-O2" "-flto" ];
    linkFlags = [ "-flto" ];
  };

  withDebug = proj.executable {
    name = "demo-debug";
    inherit sources;
    compileFlags = [ "-g" "-O0" ];
  };

  lowLevelDefault = proj.executable {
    name = "demo-lowlevel-default";
    inherit sources;
    toolchain = native.toolchains.default;
  };

  lowLevelCustom = proj.executable {
    name = "demo-lowlevel-custom";
    inherit sources;
    toolchain = native.mkToolchain {
      toolset = native.mkToolset {
        languages = {
          c = native.compilers.clang.c;
          cpp = native.compilers.clang.cpp;
        };
        linker = native.linkers.lld;
        bintools = native.compilers.clang.bintools;
      };
      policy = native.mkPolicy { };
    };
    compileFlags = [ "-O2" ];
  };

  withClangMold = if isLinux then proj.executable {
    name = "demo-clang-mold";
    inherit sources;
    compiler = "clang";
    linker = "mold";
  } else null;

  withAsan = if isLinux then proj.executable {
    name = "demo-asan";
    inherit sources;
    compileFlags = [ "-fsanitize=address,undefined" ];
    linkFlags = [ "-fsanitize=address,undefined" ];
  } else null;

  testDefault = native.test {
    name = "test-default";
    executable = default;
    expectedOutput = "Compiler:";
  };

  testO3 = native.test {
    name = "test-o3";
    executable = withO3;
    expectedOutput = "compute(100)";
  };

in {
  packages = {
    inherit default withGcc withO3 withLtoThin withLtoFull withDebug lowLevelDefault lowLevelCustom;
  } // buildMatrixTargets
    // (if isLinux then { inherit withClangMold withAsan; } else { });

  checks = {
    inherit testDefault testO3;
  };
}
