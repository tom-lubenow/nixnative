# Official nixnative API example
#
# This demonstrates the recommended way to use nixnative.
# The high-level API uses sensible defaults (clang + platform linker)
# but allows overriding compiler/linker as needed.
#
{ pkgs }:

let
  native = import ../../nix/native { inherit pkgs; };
in
rec {
  # ==========================================================================
  # Basic usage - just works with defaults (clang + platform linker)
  # ==========================================================================

  mathLib = native.staticLib {
    name = "math";
    root = ./.;
    sources = [ "lib/math.cc" ];
    publicIncludeDirs = [ "lib" ];
  };

  app = native.executable {
    name = "demo";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # ==========================================================================
  # Override compiler
  # ==========================================================================

  appGcc = native.executable {
    compiler = "gcc";
    name = "demo-gcc";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # ==========================================================================
  # Override both compiler and linker
  # ==========================================================================

  appGccMold = native.executable {
    compiler = "gcc";
    linker = "mold";
    name = "demo-gcc-mold";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  appClangMold = native.executable {
    compiler = "clang";
    linker = "mold";
    name = "demo-clang-mold";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # ==========================================================================
  # Parameterized builds - easy to create variants
  # ==========================================================================

  mkApp = { compiler ? "clang", linker ? null, suffix ? "" }:
    native.executable {
      inherit compiler linker;
      name = "demo${suffix}";
      root = ./.;
      sources = [ "src/main.cc" ];
      includeDirs = [ "lib" ];
      libraries = [ mathLib ];
    };

  # Generate variants
  appVariants = {
    clang = mkApp { suffix = "-clang"; };
    gcc = mkApp { compiler = "gcc"; suffix = "-gcc"; };
    clang-lld = mkApp { linker = "lld"; suffix = "-clang-lld"; };
  };

  # ==========================================================================
  # Advanced: Pass a pre-built toolchain directly
  # ==========================================================================

  appCustomToolchain = native.executable {
    toolchain = native.mkToolchain {
      compiler = native.compilers.clang;
      linker = native.linkers.lld;
    };
    name = "demo-custom";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # ==========================================================================
  # Development shell
  # ==========================================================================

  devShell = native.devShell {
    target = app;
    extraPackages = [ pkgs.cmake ];
  };

  default = app;
}
