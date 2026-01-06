{ pkgs, native }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  root = ./.;
  sources = [ "src/main.cc" ];

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

      mkBuild = cfg: {
        name = "matrix-${cfg.name}";
        value = {
          type = "executable";
          name = "demo-${cfg.name}";
          inherit root sources;
          inherit (cfg) compiler linker;
        };
      };
    in
    builtins.listToAttrs (map mkBuild availableConfigs);

in
native.project {
  modules = [
    {
      native = {
        root = root;

        targets = {
          default = {
            type = "executable";
            name = "demo-default";
            inherit sources;
          };

          withGcc = {
            type = "executable";
            name = "demo-gcc";
            inherit sources;
            compiler = "gcc";
          };

          withO3 = {
            type = "executable";
            name = "demo-o3";
            inherit sources;
            compileFlags = [ "-O3" ];
          };

          withLtoThin = {
            type = "executable";
            name = "demo-lto-thin";
            inherit sources;
            compileFlags = [ "-O2" "-flto=thin" ];
            linkFlags = [ "-flto=thin" ];
          };

          withLtoFull = {
            type = "executable";
            name = "demo-lto-full";
            inherit sources;
            compileFlags = [ "-O2" "-flto" ];
            linkFlags = [ "-flto" ];
          };

          withDebug = {
            type = "executable";
            name = "demo-debug";
            inherit sources;
            compileFlags = [ "-g" "-O0" ];
          };

          lowLevelDefault = {
            type = "executable";
            name = "demo-lowlevel-default";
            inherit sources;
            toolchain = native.toolchains.default;
          };

          lowLevelCustom = {
            type = "executable";
            name = "demo-lowlevel-custom";
            inherit sources;
            toolchain = native.mkToolchain {
              languages = {
                c = native.compilers.clang.c;
                cpp = native.compilers.clang.cpp;
              };
              linker = native.linkers.lld;
              bintools = native.compilers.clang.bintools;
            };
            compileFlags = [ "-O2" ];
          };
        }
        // buildMatrixTargets
        // (if isLinux then {
          withClangMold = {
            type = "executable";
            name = "demo-clang-mold";
            inherit sources;
            compiler = "clang";
            linker = "mold";
          };

          withAsan = {
            type = "executable";
            name = "demo-asan";
            inherit sources;
            compileFlags = [ "-fsanitize=address,undefined" ];
            linkFlags = [ "-fsanitize=address,undefined" ];
          };
        } else { });

        tests = {
          multiToolchainDefault = {
            executable = "default";
            expectedOutput = "Compiler:";
          };

          multiToolchainO3 = {
            executable = "withO3";
            expectedOutput = "compute(100)";
          };
        };
      };
    }
  ];
}
