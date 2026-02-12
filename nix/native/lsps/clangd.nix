# clangd LSP configuration for nixnative
#
# Provides a function to create a properly-configured clangd setup
# that users can include in their own devShell.
#
# Usage:
#   let
#     clangd = native.lsps.clangd { targets = [ app lib1 ]; };
#   in
#   pkgs.mkShell {
#     packages = [ clangd.package ];
#     shellHook = clangd.shellHook;
#   };
#
{ pkgs, lib }:

let
  # Merge multiple compile_commands.json files into one
  mergeCompileCommands =
    name: compileCommandsList:
    let
      validCommands = builtins.filter (x: x != null) compileCommandsList;
    in
    if builtins.length validCommands == 0 then
      null
    else if builtins.length validCommands == 1 then
      builtins.head validCommands
    else
      pkgs.runCommand "compile_commands-${name}.json"
        {
          nativeBuildInputs = [ pkgs.jq ];
        }
        ''
          # Merge all compile_commands.json arrays into one
          jq -s 'add' ${lib.concatStringsSep " " validCommands} > $out
        '';

  # Extract compile_commands.json from a target
  extractCompileCommands = target: target.compileCommands or target.passthru.compileCommands or null;

in
rec {
  # Create a clangd configuration for one or more targets
  #
  # Arguments:
  #   targets          - List of targets (executables, libraries) to include
  #   target           - Single target (convenience, converted to list)
  #   symlinkName      - Name of the symlink (default: compile_commands.json)
  #   package          - Override clang-tools package
  #
  # Returns:
  #   {
  #     package          - clang-tools package (includes clangd, clang-format, etc.)
  #     compileCommands  - Path to merged compile_commands.json
  #     shellHook        - Shell hook to symlink compile_commands.json
  #   }
  #
  mkClangd =
    {
      targets ? [ ],
      target ? null,
      symlinkName ? "compile_commands.json",
      package ? pkgs.clang-tools,
    }:
    let
      # Normalize targets to a list
      allTargets =
        if target != null then
          [ target ] ++ targets
        else if builtins.length targets > 0 then
          targets
        else
          throw "mkClangd: must provide at least one target or targets";

      # Extract compile commands from all targets
      allCompileCommands = map extractCompileCommands allTargets;

      # Get a name for the merged output
      targetNames = map (t: t.name or "unknown") allTargets;
      mergedName = lib.concatStringsSep "-" targetNames;

      # Merge all compile commands
      compileCommands = mergeCompileCommands mergedName allCompileCommands;

      # Shell hook to symlink compile_commands.json
      shellHook =
        if compileCommands != null then
          ''
            ln -sf "${compileCommands}" "${symlinkName}"
          ''
        else
          "";

    in
    {
      inherit package compileCommands shellHook;

      # Convenience: packages list for mkShell
      packages = [ package ];
    };

  # Alias for convenience
  clangd = mkClangd;
}
