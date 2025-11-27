{ pkgs
, native
, system ? pkgs.stdenv.hostPlatform.system
, craneLib ? null
}:

let
  materialize = pkg:
    if pkgs.lib.isAttrs pkg && pkg ? drv then pkg.drv else pkg;
  materializeSet = set: pkgs.lib.mapAttrs (_: materialize) set;

  execPackagesRaw = import ./executable/project.nix { inherit pkgs native; };
  execChecks = import ./executable/checks.nix { inherit pkgs; packages = execPackagesRaw; };
  execPackages = materializeSet execPackagesRaw;

  libraryPackagesRaw = import ./library/project.nix { inherit pkgs native; };
  libraryChecks = import ./library/checks.nix { inherit pkgs; packages = libraryPackagesRaw; };
  libraryPackages = materializeSet libraryPackagesRaw;

  appPackagesRaw = import ./app-with-library/project.nix { inherit pkgs native; };
  appChecks = import ./app-with-library/checks.nix { inherit pkgs; packages = appPackagesRaw; };
  appPackages = {
    simple-strict = appPackagesRaw.strict;
    simple-scanned = appPackagesRaw.scanned;
    mathLib = materialize appPackagesRaw.mathLib;
  };

  rustPackagesRaw = import ./rust-integration/project.nix { inherit pkgs native; };
  rustChecks = import ./rust-integration/checks.nix { inherit pkgs; packages = rustPackagesRaw; };
  rustPackages = materializeSet rustPackagesRaw;

  rustCranePackagesRaw =
    if craneLib != null then
      import ./rust-integration-crane/project.nix { inherit pkgs native craneLib; }
    else
      { };
  rustCraneChecks =
    if craneLib != null then
      import ./rust-integration-crane/checks.nix { inherit pkgs; packages = rustCranePackagesRaw; }
    else
      { };
  rustCranePackages = materializeSet rustCranePackagesRaw;

  mergeAttrs = attrsList: pkgs.lib.foldl' (acc: attrs: acc // attrs) { } attrsList;

in {
  packages = mergeAttrs [
    execPackages
    libraryPackages
    appPackages
    rustPackages
    rustCranePackages
  ];

  checks = mergeAttrs [
    execChecks
    libraryChecks
    appChecks
    rustChecks
    rustCraneChecks
  ];

  defaults = {
    executable = materialize execPackagesRaw.executableExample;
    library = materialize libraryPackagesRaw.mathLibrary;
    app = appPackagesRaw.strict;
    rustInterop = materialize rustPackagesRaw.rustInteropExample;
    rustInteropCrane =
      if rustCranePackagesRaw ? rustCraneInterop then materialize rustCranePackagesRaw.rustCraneInterop
      else null;
  };
}
