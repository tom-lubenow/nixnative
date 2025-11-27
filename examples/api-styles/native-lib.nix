# Native library wrappers - implements three high-level API styles
#
# This file wraps the low-level nixnative API into ergonomic high-level APIs.
# Import this in your project and use whichever style you prefer.
#
{ pkgs }:

let
  # Import the core native module
  native = import ../../nix/native { inherit pkgs; };

  # ============================================================================
  # OPTION A: Namespace-based API
  # ============================================================================
  #
  # Usage: native.clang.executable { name = "app"; sources = [...]; }
  #        native.gcc.staticLib { name = "lib"; sources = [...]; }
  #
  # Pros: Clear compiler choice, discoverable via tab-completion
  # Cons: Verbose when mixing compilers, harder to parameterize
  #
  mkCompilerNamespace = compiler: linker: {
    executable = args: native.mkExecutable (args // {
      toolchain = native.mkToolchain { inherit compiler linker; };
    });

    staticLib = args: native.mkStaticLib (args // {
      toolchain = native.mkToolchain { inherit compiler linker; };
    });

    sharedLib = args: native.mkSharedLib (args // {
      toolchain = native.mkToolchain { inherit compiler linker; };
    });

    headerOnly = args: native.mkHeaderOnly args;

    # Allow overriding linker
    withLinker = newLinker: mkCompilerNamespace compiler newLinker;
  };

  optionA = {
    clang = mkCompilerNamespace native.compilers.clang native.linkers.default;
    gcc = mkCompilerNamespace native.compilers.gcc native.linkers.default;
    zig = mkCompilerNamespace native.compilers.zig native.linkers.lld;

    # Access to underlying native module for advanced usage
    inherit native;
  };

  # ============================================================================
  # OPTION B: Function with compiler param
  # ============================================================================
  #
  # Usage: native.executable { compiler = "clang"; name = "app"; sources = [...]; }
  #        native.staticLib { compiler = "gcc"; linker = "mold"; ... }
  #
  # Pros: Single function per target type, easy to parameterize
  # Cons: More verbose for simple cases
  #
  resolveCompiler = spec:
    if builtins.isString spec then
      native.compilers.${spec} or (throw "Unknown compiler: ${spec}")
    else if builtins.isAttrs spec && spec ? cc then
      spec  # Already a compiler object
    else
      throw "compiler must be a string name or compiler object";

  resolveLinker = spec:
    if spec == null then native.linkers.default
    else if builtins.isString spec then
      native.linkers.${spec} or (throw "Unknown linker: ${spec}")
    else if builtins.isAttrs spec && spec ? driverFlag then
      spec  # Already a linker object
    else
      throw "linker must be a string name or linker object";

  optionB = {
    executable = { compiler ? "clang", linker ? null, ... }@args:
      let
        resolvedCompiler = resolveCompiler compiler;
        resolvedLinker = resolveLinker linker;
        cleanArgs = builtins.removeAttrs args [ "compiler" "linker" ];
      in
      native.mkExecutable (cleanArgs // {
        toolchain = native.mkToolchain {
          compiler = resolvedCompiler;
          linker = resolvedLinker;
        };
      });

    staticLib = { compiler ? "clang", linker ? null, ... }@args:
      let
        resolvedCompiler = resolveCompiler compiler;
        resolvedLinker = resolveLinker linker;
        cleanArgs = builtins.removeAttrs args [ "compiler" "linker" ];
      in
      native.mkStaticLib (cleanArgs // {
        toolchain = native.mkToolchain {
          compiler = resolvedCompiler;
          linker = resolvedLinker;
        };
      });

    sharedLib = { compiler ? "clang", linker ? null, ... }@args:
      let
        resolvedCompiler = resolveCompiler compiler;
        resolvedLinker = resolveLinker linker;
        cleanArgs = builtins.removeAttrs args [ "compiler" "linker" ];
      in
      native.mkSharedLib (cleanArgs // {
        toolchain = native.mkToolchain {
          compiler = resolvedCompiler;
          linker = resolvedLinker;
        };
      });

    headerOnly = native.mkHeaderOnly;

    inherit native;
  };

  # ============================================================================
  # OPTION C: Toolchain-centric API
  # ============================================================================
  #
  # Usage: native.build { toolchain = "clang-lld"; type = "executable"; ... }
  #        native.build { toolchain = myCustomToolchain; type = "staticLib"; ... }
  #
  # Pros: Explicit toolchain, great for multi-toolchain projects
  # Cons: Slightly more verbose, requires knowing toolchain names
  #
  resolveToolchain = spec:
    if builtins.isString spec then
      native.toolchains.${spec} or (throw "Unknown toolchain: ${spec}")
    else if builtins.isAttrs spec && spec ? compiler && spec ? linker then
      spec  # Already a toolchain object
    else
      throw "toolchain must be a string name or toolchain object";

  optionC = {
    build = { toolchain ? "default", type, ... }@args:
      let
        resolvedToolchain = resolveToolchain toolchain;
        cleanArgs = builtins.removeAttrs args [ "toolchain" "type" ];
        builder =
          if type == "executable" then native.mkExecutable
          else if type == "staticLib" || type == "static" then native.mkStaticLib
          else if type == "sharedLib" || type == "shared" then native.mkSharedLib
          else if type == "headerOnly" || type == "header-only" then native.mkHeaderOnly
          else throw "Unknown build type: ${type}. Use: executable, staticLib, sharedLib, headerOnly";
      in
      builder (cleanArgs // { toolchain = resolvedToolchain; });

    # Convenience aliases
    executable = args: optionC.build (args // { type = "executable"; });
    staticLib = args: optionC.build (args // { type = "staticLib"; });
    sharedLib = args: optionC.build (args // { type = "sharedLib"; });
    headerOnly = args: optionC.build (args // { type = "headerOnly"; });

    # Pre-defined toolchains for quick access
    toolchains = native.toolchains;

    inherit native;
  };

in {
  # Export all three options
  inherit optionA optionB optionC;

  # Also export the raw native module
  inherit native;
}
