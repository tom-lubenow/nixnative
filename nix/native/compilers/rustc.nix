# Rust compiler implementation for nixnative
#
# Exports language config for use in toolchains:
#   native.compilers.rustc.rust - Rust compiler
#
# Rust compilation differs from C/C++:
# - Crates compile as a unit (not per-file)
# - Dependencies are handled via modules, not header includes
# - For FFI, use staticlib or cdylib crate types
#
{ pkgs, lib }:

let
  mkRustc =
    {
      rustPackage ? pkgs.rustc,
      name ? "rustc",
    }:
    let
      rustc = rustPackage;

      sharedRuntimeInputs = [
        rustc
        pkgs.coreutils
      ];
    in
    {
      inherit name;
      version = rustc.version or "unknown";
      package = rustc;

      # Language config
      rust = {
        name = "${name}-rust";
        language = "rust";
        compiler = "${rustc}/bin/rustc";
        defaultFlags = [
          "--edition=2021"
        ];
        runtimeInputs = sharedRuntimeInputs;
        environment = { };

        # Rust-specific configuration
        crateTypeFlags = {
          bin = [ "--crate-type=bin" ];
          lib = [ "--crate-type=lib" ];
          rlib = [ "--crate-type=rlib" ];
          staticlib = [ "--crate-type=staticlib" ];
          cdylib = [ "--crate-type=cdylib" ];
          dylib = [ "--crate-type=dylib" ];
        };

        optimizeFlags = {
          "0" = [ "-C" "opt-level=0" ];
          "1" = [ "-C" "opt-level=1" ];
          "2" = [ "-C" "opt-level=2" ];
          "3" = [ "-C" "opt-level=3" ];
          "s" = [ "-C" "opt-level=s" ];
          "z" = [ "-C" "opt-level=z" ];
        };

        debugFlags = {
          none = [ ];
          line-tables = [ "-C" "debuginfo=1" ];
          full = [ "-C" "debuginfo=2" ];
        };

        ltoFlags = {
          thin = [ "-C" "lto=thin" ];
          full = [ "-C" "lto=fat" ];
        };

        capabilities = {
          lto = {
            thin = true;
            full = true;
          };
          editions = [ "2015" "2018" "2021" "2024" ];
        };
      };

      # No bintools needed for Rust (uses system linker)
      bintools = { };
    };

in
rec {
  # Default rustc from nixpkgs
  rustc = mkRustc { };

  # Factory for custom Rust versions
  inherit mkRustc;
}
