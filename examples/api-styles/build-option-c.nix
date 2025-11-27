# Option C: Toolchain-centric API
#
# Style:  native.build { toolchain = "clang-lld"; type = "executable"; ... }
#         native.executable { toolchain = "gcc-mold"; ... }
#
# Toolchain is explicit and first-class. Great for projects that need
# to build the same code with multiple toolchains.
#
{ pkgs }:

let
  lib = import ./native-lib.nix { inherit pkgs; };
  native = lib.optionC;
in
rec {
  # Build the math library
  mathLib = native.staticLib {
    toolchain = "default";
    name = "math";
    root = ./.;
    sources = [ "lib/math.cc" ];
    publicIncludeDirs = [ "lib" ];
  };

  # Build the main executable
  app = native.executable {
    toolchain = "clang-lld";
    name = "demo";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Alternative: Use the generic build function
  appGeneric = native.build {
    toolchain = "clang-lld";
    type = "executable";
    name = "demo-generic";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Alternative: GCC with Mold
  appGccMold = native.executable {
    toolchain = "gcc-mold";
    name = "demo-gcc-mold";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "lib" ];
    libraries = [ mathLib ];
  };

  # Build matrix: same code with multiple toolchains
  buildMatrix =
    let
      mkBuild = toolchain: native.executable {
        inherit toolchain;
        name = "demo-${toolchain}";
        root = ./.;
        sources = [ "src/main.cc" ];
        includeDirs = [ "lib" ];
        libraries = [ mathLib ];
      };

      # Filter out null toolchains (platform-specific)
      availableToolchains = builtins.filter
        (name: native.toolchains.${name} != null)
        [ "clang-lld" "clang-mold" "gcc-mold" "gcc-lld" ];
    in
    builtins.listToAttrs (map (tc: {
      name = tc;
      value = mkBuild tc;
    }) availableToolchains);

  default = app;
}
