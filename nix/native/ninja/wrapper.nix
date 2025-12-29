# nix-ninja wrapper derivation for nixnative
#
# Creates a derivation that invokes nix-ninja with a generated build.ninja file.
# nix-ninja handles creating per-file derivations with proper incrementality.
#
{ pkgs, lib, nix-ninja, nix-ninja-task, nixPackage }:

let
  inherit (lib) concatStringsSep;

in
{
  # Create a derivation that invokes nix-ninja
  #
  # This produces a content-addressed text-mode derivation with dynamic outputs.
  # The actual target is accessed via builtins.outputOf on the derivation.
  #
  mkNinjaDerivation = {
    name,
    ninjaContent,   # String content of build.ninja
    target,         # Target to build (e.g., "myapp" or "libfoo.a")
    sourceInputs,   # List of store paths containing source files
    toolInputs,     # List of store paths containing tools (compiler, linker, etc.)
    outputType,     # "executable" | "staticLib" | "sharedLib"
    libraryInputs ? [],  # List of library wrapper derivations (for dependency tracking)
  }:
    let
      # Normalize target name for use as output name (replace / with -)
      normalizedTarget = builtins.replaceStrings ["/"] ["-"] target;

      # Write ninja content to a file in the store
      ninjaFile = pkgs.writeText "${name}-build.ninja" ninjaContent;

      # The wrapper derivation that runs nix-ninja
      ninjaDrv = pkgs.stdenv.mkDerivation {
        name = "${name}.drv";

        # Content-addressed output (text mode for dynamic derivations)
        __contentAddressed = true;
        outputHashMode = "text";
        outputHashAlgo = "sha256";

        # Required for nix-ninja to create derivations
        requiredSystemFeatures = [ "recursive-nix" ];

        nativeBuildInputs = [
          nix-ninja
          nix-ninja-task
          nixPackage.out  # Need .out to get the nix binary, not .dev
          pkgs.coreutils
          pkgs.patchelf  # Required by nix-ninja
        ] ++ toolInputs;

        # Pass source inputs and library dependencies for nix-ninja to reference
        # Library inputs ensure their dynamic outputs are available for linking
        buildInputs = sourceInputs ++ libraryInputs;

        # stdenv adds a -rpath with a self reference but self references are not
        # allowed by text output mode (patched nix-ninja with bash fix)
        NIX_NO_SELF_RPATH = true;

        # Enable nix-ninja derivation mode
        preConfigure = ''
          export NIX_NINJA_DRV="true"
          export NINJA="${nix-ninja}/bin/nix-ninja"
          export NIX_CONFIG="extra-experimental-features = nix-command ca-derivations dynamic-derivations"
        '';

        # Run nix-ninja to build the target
        buildPhase = ''
          runHook preBuild

          # Copy ninja file to build directory
          cp ${ninjaFile} build.ninja

          # Run nix-ninja
          nix-ninja ${target}

          runHook postBuild
        '';

        # Don't run standard phases - nix-ninja handles everything
        dontUnpack = true;
        dontInstall = true;
        dontFixup = true;
        dontUseMesonInstall = true;
        dontUseMesonCheck = true;

        passthru = {
          # Access the target output via builtins.outputOf
          target = builtins.outputOf ninjaDrv.outPath normalizedTarget;
          inherit ninjaContent outputType;
          ninja = ninjaFile;
        };
      };
    in
    ninjaDrv;

  # Create a test derivation that runs an executable built with nix-ninja
  mkNinjaTest = {
    name,
    executable,      # Derivation from mkNinjaDerivation
    args ? [],       # Command-line arguments
    expectedOutput ? null,  # Expected output substring
  }:
    pkgs.stdenv.mkDerivation {
      name = "test-${name}";

      __contentAddressed = true;
      outputHashMode = "text";
      outputHashAlgo = "sha256";

      requiredSystemFeatures = [ "recursive-nix" ];

      nativeBuildInputs = [ nixPackage.out pkgs.coreutils ];

      dontUnpack = true;
      dontConfigure = true;
      dontInstall = true;
      dontFixup = true;

      buildPhase = ''
        runHook preBuild

        export NIX_CONFIG="extra-experimental-features = nix-command ca-derivations dynamic-derivations"

        # Realize the executable derivation
        exe_path=$(nix build --no-link --print-out-paths ${executable})

        # Run the test
        echo "Running: $exe_path/bin/${name} ${concatStringsSep " " args}"
        output=$("$exe_path/bin/${name}" ${concatStringsSep " " args} 2>&1) || true

        echo "Output: $output"

        ${lib.optionalString (expectedOutput != null) ''
          if echo "$output" | grep -q "${expectedOutput}"; then
            echo "Test passed: found expected output"
          else
            echo "Test failed: expected '${expectedOutput}' not found"
            exit 1
          fi
        ''}

        echo "Test passed" > "$out"

        runHook postBuild
      '';
    };
}
