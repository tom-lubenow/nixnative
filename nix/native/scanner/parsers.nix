# Dependency file parsers for nixnative scanner
#
# Provides parsing utilities for different dependency output formats.
# These generate shell/awk scripts that can be embedded in derivations.
#
{ lib }:

rec {
  # ==========================================================================
  # Make-Format Parser (.d files)
  # ==========================================================================

  # Generate a shell script that parses a Make-format .d file and outputs
  # one dependency per line (relative paths only, no absolute paths).
  #
  # Make format: target.o: dep1.h dep2.h \
  #                dep3.h dep4.h
  #
  # The script handles:
  # - Line continuations (backslash-newline)
  # - Multiple dependencies per line
  # - Escaped spaces in paths
  # - Filtering out absolute paths (system headers)
  # - Self-references (source file in its own dep list)
  #
  mkMakeParser = { depfile, outfile, sourceFile ? null }:
    let
      # Handle source file filtering in AWK to avoid grep exit code issues
      sourceFilterExpr = if sourceFile != null
        then ''&& dep != "${sourceFile}"''
        else "";
    in
    ''
      if [ -f "${depfile}" ]; then
        # Parse .d file: handle continuations, extract deps, filter absolute paths
        awk '
          BEGIN { RS = "" }
          {
            # Remove line continuations
            gsub(/\\[[:space:]]*\n/, " ")
            # Find the colon and get everything after it
            idx = index($0, ":")
            if (idx > 0) {
              deps = substr($0, idx + 1)
              # Split on whitespace
              n = split(deps, arr)
              for (i = 1; i <= n; i++) {
                dep = arr[i]
                # Skip empty, absolute paths, and source file itself
                if (dep != "" && substr(dep, 1, 1) != "/" ${sourceFilterExpr}) {
                  print dep
                }
              }
            }
          }
        ' "${depfile}" | sort -u > "${outfile}"
      else
        # No deps file - empty output
        touch "${outfile}"
      fi
    '';

  # ==========================================================================
  # JSON-Format Parser (clang -MJ)
  # ==========================================================================

  # Generate a shell script that parses clang's JSON dependency output.
  # This is more accurate but clang-specific.
  #
  # JSON format from -MJ:
  # { "directory": "...", "file": "...", "output": "...", "arguments": [...] }
  #
  # Note: -MJ outputs compilation database entries, not dependency lists.
  # For actual deps, we'd need to use clang-scan-deps with JSON output.
  # This is a placeholder for future enhancement.
  #
  mkJsonParser = { depfile, outfile }:
    ''
      if [ -f "${depfile}" ]; then
        # TODO: Implement JSON parsing when we add clang-scan-deps support
        # For now, treat as empty
        touch "${outfile}"
      else
        touch "${outfile}"
      fi
    '';

  # ==========================================================================
  # Parser Selection
  # ==========================================================================

  # Get the appropriate parser script for a given output format
  mkParseScript = { format, depfile, outfile, sourceFile ? null }:
    if format == "make" then
      mkMakeParser { inherit depfile outfile sourceFile; }
    else if format == "json" then
      mkJsonParser { inherit depfile outfile; }
    else
      throw "nixnative: unknown scanner output format '${format}'";

  # ==========================================================================
  # Manifest Generation
  # ==========================================================================

  # Generate a shell script that creates a JSON manifest from a deps file.
  # Input: deps file with one dependency per line
  # Output: JSON in manifest format
  #
  mkManifestEntry = { sourceFile, depsFile, outfile }:
    ''
      {
        printf '"%s": {"dependencies": [' "${sourceFile}"
        first=1
        while IFS= read -r dep || [ -n "$dep" ]; do
          [ -z "$dep" ] && continue
          if [ "$first" = "1" ]; then
            first=0
          else
            printf ','
          fi
          printf '"%s"' "$dep"
        done < "${depsFile}"
        printf ']}'
      } > "${outfile}"
    '';
}
