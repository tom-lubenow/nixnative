{
  description = "Multi-toolchain example: comparing compilers, linkers, and build configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          isLinux = pkgs.stdenv.hostPlatform.isLinux;

          # ====================================================================
          # HIGH-LEVEL API EXAMPLES
          # ====================================================================
          #
          # The high-level API uses sensible defaults and accepts `compiler`
          # and `linker` as optional string parameters.

          # Default: clang + platform default linker
          default = native.executable {
            name = "demo-default";
            root = ./.;
            sources = [ "src/main.cc" ];
          };

          # Explicit compiler selection
          withGcc = native.executable {
            compiler = "gcc";
            name = "demo-gcc";
            root = ./.;
            sources = [ "src/main.cc" ];
          };

          # Compiler + linker selection (mold is Linux-only)
          withClangMold = native.executable {
            compiler = "clang";
            linker = "mold";
            name = "demo-clang-mold";
            root = ./.;
            sources = [ "src/main.cc" ];
          };

          withGccMold = native.executable {
            compiler = "gcc";
            linker = "mold";
            name = "demo-gcc-mold";
            root = ./.;
            sources = [ "src/main.cc" ];
          };

          # ====================================================================
          # ABSTRACT FLAGS EXAMPLES
          # ====================================================================
          #
          # The `flags` parameter accepts abstract build flags that get
          # translated to compiler-specific CLI arguments.

          # Optimization flags
          withO3 = native.executable {
            name = "demo-o3";
            root = ./.;
            sources = [ "src/main.cc" ];
            flags = [
              { type = "optimize"; value = "3"; }
            ];
          };

          # LTO (Link-Time Optimization)
          withLtoThin = native.executable {
            name = "demo-lto-thin";
            root = ./.;
            sources = [ "src/main.cc" ];
            flags = [
              { type = "lto"; value = "thin"; }
              { type = "optimize"; value = "2"; }
            ];
          };

          withLtoFull = native.executable {
            name = "demo-lto-full";
            root = ./.;
            sources = [ "src/main.cc" ];
            flags = [
              { type = "lto"; value = "full"; }
              { type = "optimize"; value = "2"; }
            ];
          };

          # Debug build
          withDebug = native.executable {
            name = "demo-debug";
            root = ./.;
            sources = [ "src/main.cc" ];
            flags = [
              { type = "debug"; value = "full"; }
              { type = "optimize"; value = "0"; }
            ];
          };

          # Sanitizers (Linux only - ASan has issues on macOS with Nix)
          withAsan = native.executable {
            name = "demo-asan";
            root = ./.;
            sources = [ "src/main.cc" ];
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
            root = ./.;
            sources = [ "src/main.cc" ];
            flags = [
              { type = "lto"; value = "full"; }  # GCC only supports full LTO
              { type = "optimize"; value = "3"; }
            ];
          };

          # ====================================================================
          # LOW-LEVEL API EXAMPLES
          # ====================================================================
          #
          # The low-level API (`mkExecutable`) requires an explicit toolchain.
          # Use this when you need full control or are building custom toolchains.

          # Using a pre-built toolchain
          lowLevelDefault = native.mkExecutable {
            toolchain = native.toolchains.default;
            name = "demo-lowlevel-default";
            root = ./.;
            sources = [ "src/main.cc" ];
          };

          # Building a custom toolchain inline
          lowLevelCustom = native.mkExecutable {
            toolchain = native.mkToolchain {
              compiler = native.compilers.clang;
              linker = native.linkers.lld;
            };
            name = "demo-lowlevel-custom";
            root = ./.;
            sources = [ "src/main.cc" ];
            flags = [
              { type = "optimize"; value = "2"; }
            ];
          };

          # ====================================================================
          # BUILD MATRIX
          # ====================================================================
          #
          # Generate builds for multiple toolchain configurations.

          buildMatrix =
            let
              configs = [
                { name = "clang-lld"; compiler = "clang"; linker = "lld"; }
                { name = "clang-mold"; compiler = "clang"; linker = "mold"; }
                { name = "gcc-lld"; compiler = "gcc"; linker = "lld"; }
                { name = "gcc-mold"; compiler = "gcc"; linker = "mold"; }
              ];

              # Filter configs based on platform availability
              availableConfigs = builtins.filter (cfg:
                # mold is Linux-only
                if cfg.linker == "mold" then isLinux
                # gcc may not be available on all platforms
                else if cfg.compiler == "gcc" then native.compilers.gcc != null
                else true
              ) configs;

              mkBuild = cfg: {
                name = "matrix-${cfg.name}";
                value = native.executable {
                  inherit (cfg) compiler linker;
                  name = "demo-${cfg.name}";
                  root = ./.;
                  sources = [ "src/main.cc" ];
                };
              };
            in
            builtins.listToAttrs (map mkBuild availableConfigs);

          # ====================================================================
          # PACKAGE SET
          # ====================================================================

        in
        {
          # High-level API examples
          inherit default withGcc withO3 withLtoThin withLtoFull withDebug;

          # Low-level API examples
          inherit lowLevelDefault lowLevelCustom;

          # Build matrix
          inherit buildMatrix;
        }
        # Platform-specific packages
        // (if isLinux then {
          inherit withClangMold withGccMold withAsan optimizedGcc;
        } else {})
      );

      # Expose checks
      checks = forAllSystems (system:
        let
          packages' = self.packages.${system};
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
        in
        {
          # Test that default builds and runs
          test-default = native.test {
            name = "test-default";
            executable = packages'.default;
            expectedOutput = "Compiler:";
          };

          # Test optimized build
          test-o3 = native.test {
            name = "test-o3";
            executable = packages'.withO3;
            expectedOutput = "compute(100)";
          };
        }
      );
    };
}
