# Rust Native Example
#
# Demonstrates building Rust code without Cargo, using rustc directly.
# Shows multifile projects with library and executable.
#
{ pkgs, native }:

let
  # Create a toolchain with Rust support
  toolchain = native.mkToolchain {
    languages = {
      c = native.compilers.clang.c;
      cpp = native.compilers.clang.cpp;
      rust = native.compilers.rustc.rust;
    };
    linker = native.linkers.default;
    bintools = native.compilers.clang.bintools;
  };

  # Build the library as an rlib (for Rust consumers)
  mylib = native.mkRustLib {
    inherit toolchain;
    name = "mylib";
    root = ./.;
    entry = "src/lib.rs";
    edition = "2021";
  };

  # Build the executable, depending on the library
  app = native.mkRustExecutable {
    inherit toolchain;
    name = "rust-native-app";
    root = ./.;
    entry = "src/main.rs";
    edition = "2021";
    deps = [ mylib ];
  };

in
{
  inherit mylib app toolchain;

  # Default is the application
  default = app;
}
