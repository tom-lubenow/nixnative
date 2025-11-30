# Mixed C/C++/Rust Example
#
# Demonstrates linking Rust (staticlib), C, and C++ code together.
#
{ pkgs, native }:

let
  # Create a toolchain with C, C++, and Rust support
  toolchain = native.mkToolchain {
    languages = {
      c = native.compilers.clang.c;
      cpp = native.compilers.clang.cpp;
      rust = native.compilers.rustc.rust;
    };
    linker = native.linkers.default;
    bintools = native.compilers.clang.bintools;
  };

  # Build the Rust library as a staticlib (for C/C++ linking)
  rustLib = native.mkRustStaticLib {
    inherit toolchain;
    name = "rustlib";
    root = ./.;
    entry = "src/rustlib.rs";
    edition = "2021";
  };

  # Build the C wrapper library
  cLib = native.mkStaticLib {
    inherit toolchain;
    name = "cwrapper";
    root = ./.;
    sources = [ "src/cwrapper.c" ];
    includeDirs = [ "include" ];
    publicIncludeDirs = [ "include" ];
  };

  # Build the C++ application
  app = native.mkExecutable {
    inherit toolchain;
    name = "mixed-app";
    root = ./.;
    sources = [ "src/main.cc" ];
    includeDirs = [ "include" ];
    libraries = [ cLib ];
    # Link against the Rust staticlib
    ldflags = [ rustLib.libraryPath ];
  };

in
{
  inherit rustLib cLib app toolchain;

  # Default is the application
  default = app;
}
