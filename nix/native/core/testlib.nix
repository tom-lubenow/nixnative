# Test library abstraction for nixnative
#
# A test library wraps a testing framework (gtest, catch2, doctest) and
# exposes it as a library that can be used in the `libraries` parameter.
#
# Users can implement their own test frameworks by using mkTestLib:
#
#   myTestLib = native.mkTestLib {
#     name = "my-framework";
#     package = pkgs.myTestFramework;
#     libraries = [ "${pkgs.myTestFramework}/lib/libmytest.a" ];
#     mainLibrary = "${pkgs.myTestFramework}/lib/libmytest_main.a";
#   };
#
{ lib }:

rec {
  # ==========================================================================
  # Test Library Factory
  # ==========================================================================

  # Create a test library from a testing framework package
  #
  # Arguments:
  #   name         - Identifier: "gtest", "catch2", "doctest"
  #   package      - The nix package providing the framework
  #   includeDirs  - Include directories (default: package/include)
  #   libraries    - Libraries to link (without main)
  #   mainLibrary  - Library providing main() (optional)
  #   defines      - Preprocessor defines
  #   cxxFlags     - Additional C++ flags
  #
  mkTestLib =
    {
      name,
      package,
      includeDirs ? [ "${package}/include" ],
      libraries ? [ ],
      mainLibrary ? null,
      defines ? [ ],
      cxxFlags ? [ ],
      # Additional packages needed in sandbox (e.g., dev outputs for headers)
      extraEvalInputs ? [ ],
    }:
    let
      basePublic = {
        includeDirs = map (d: { path = d; }) includeDirs;
        inherit defines cxxFlags;
        linkFlags = libraries;
      };

      # evalInputs ensures packages are available in the sandbox during scanning
      # Include both main package and any extra inputs (like dev outputs)
      baseEvalInputs = [ package ] ++ extraEvalInputs;

      self = {
        inherit name package;
        artifactType = "test-library";
        public = basePublic;
        evalInputs = baseEvalInputs;

        # Variant with framework-provided main()
        #
        # Use this when you don't want to write your own main():
        #   libraries = [ native.testLibs.gtest.withMain ];
        #
        withMain =
          if mainLibrary != null then
            self
            // {
              public = basePublic // {
                linkFlags = libraries ++ [ mainLibrary ];
              };
              evalInputs = baseEvalInputs;
            }
          else
            throw "nixnative: test library '${name}' does not provide a main()";
      };
    in
    self;

  # ==========================================================================
  # Validation
  # ==========================================================================

  validateTestLib =
    testLib:
    let
      required = [
        "name"
        "package"
        "public"
      ];
      missing = builtins.filter (f: !(testLib ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: test library missing required fields: ${lib.concatStringsSep ", " missing}"
    else
      testLib;
}
