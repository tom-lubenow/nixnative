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
    evalInputs ? [],     # Additional build inputs (pkg-config, tool deps, headers)
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

        # Library dependencies for linking (setup hooks, pkg-config, etc.)
        # Source files are NOT included here - they're tracked via string context
        # in ninjaContent, which flows through ninjaFile to this derivation.
        buildInputs = libraryInputs ++ evalInputs;

        # stdenv adds a -rpath with a self reference but self references are not
        # allowed by text output mode (patched nix-ninja with bash fix)
        NIX_NO_SELF_RPATH = true;

        # Enable nix-ninja derivation mode
        preConfigure = ''
          export NIX_NINJA_DRV="true"
          export NIX_SYSTEM="${pkgs.stdenv.hostPlatform.system}"
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
    target,          # builtins.outputOf reference to the actual target
    executableName,  # Actual executable name (from wrapper.name)
    args ? [],       # Command-line arguments
    expectedOutput ? null,  # Expected output substring
  }:
    let
      escapedArgs = concatStringsSep " " (map lib.escapeShellArg args);
    in
    pkgs.stdenv.mkDerivation {
      name = "test-${name}";

      # The target placeholder ensures Nix builds the wrapper and then the dynamic output
      buildInputs = [ target ];

      dontUnpack = true;
      dontConfigure = true;
      dontInstall = true;
      dontFixup = true;

      buildPhase = ''
        runHook preBuild

        # The target is now directly accessible as a path
        exe_path="${target}"

        # nix-ninja outputs executables at root, not in bin/
        exe="$exe_path/${executableName}"

        # Run the test
        echo "Running: $exe ${escapedArgs}"
        set +e
        output=$("$exe" ${escapedArgs} 2>&1)
        status=$?
        set -e

        echo "Output: $output"

        if [ "$status" -ne 0 ]; then
          echo "Test failed: executable exited with status $status"
          exit "$status"
        fi

        ${lib.optionalString (expectedOutput != null) ''
          # Use grep -F for fixed string matching (no regex interpretation)
          # Write expected to file to avoid all shell escaping issues
          cat > expected.txt <<'EXPECTED_EOF'
${expectedOutput}
EXPECTED_EOF
          if grep -qF -f expected.txt <<< "$output"; then
            echo "Test passed: found expected output"
          else
            echo "Test failed: expected output not found"
            echo "Expected: $(cat expected.txt)"
            echo "Got: $output"
            exit 1
          fi
        ''}

        mkdir -p $out
        echo "Test passed" > $out/result

        runHook postBuild
      '';
    };
}
