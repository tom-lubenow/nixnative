# Dependency manifest handling for nixnative
#
# Manifests track which headers each source file depends on.
# This enables minimal rebuilds when only some headers change.
#
{ lib, utils }:

let
  inherit (lib) unique;
  inherit (utils) toPathLike showValue;

in
rec {
  # ==========================================================================
  # Manifest Loading
  # ==========================================================================

  # Load a manifest from various sources (path, JSON file, Nix file, or attrset)
  mkManifest =
    manifestSpec:
    let
      load =
        spec:
        if builtins.isAttrs spec && spec ? units then
          spec
        else
          let
            path = toPathLike spec;
            pathStr = builtins.toString path;
          in
          if lib.hasSuffix ".nix" pathStr then import path else builtins.fromJSON (builtins.readFile path);
      manifest = load manifestSpec;
    in
    if manifest ? units then
      manifest
    else
      throw "nixnative: dependency manifest must contain a 'units' attribute. Got: ${showValue manifest}. Expected format: { schema = 1; units = { \"src/file.cc\" = { dependencies = [...]; }; }; }";

  # ==========================================================================
  # Empty Manifest
  # ==========================================================================

  emptyManifest = {
    schema = 1;
    units = { };
  };

  # ==========================================================================
  # Manifest Merging
  # ==========================================================================

  # Merge two manifests, combining dependencies for overlapping units
  mergeManifests =
    base: addition:
    let
      baseUnits = base.units or { };
      additionUnits = addition.units or { };
      schema =
        if base ? schema then
          base.schema
        else if addition ? schema then
          addition.schema
        else
          1;
      keys = unique ((builtins.attrNames baseUnits) ++ (builtins.attrNames additionUnits));

      mergeEntry =
        baseEntry: additionEntry:
        if baseEntry == null then
          additionEntry
        else if additionEntry == null then
          baseEntry
        else
          let
            baseDeps = baseEntry.dependencies or [ ];
            additionDeps = additionEntry.dependencies or [ ];
          in
          baseEntry
          // additionEntry
          // {
            dependencies = unique (baseDeps ++ additionDeps);
          };

      mergedUnits = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = mergeEntry (baseUnits.${name} or null) (additionUnits.${name} or null);
        }) keys
      );
    in
    {
      inherit schema;
      units = mergedUnits;
    };
}
