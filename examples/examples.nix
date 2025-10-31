{ pkgs, cpp }:

let
  exec = import ./executable/project.nix { inherit pkgs cpp; };
  library = import ./library/project.nix { inherit pkgs cpp; };
  app = import ./app-with-library/project.nix { inherit pkgs cpp; };
  pythonExt = import ./python-extension/project.nix { inherit pkgs cpp; };

  mergeAttrs = attrsList: pkgs.lib.foldl' (acc: attrs: acc // attrs) { } attrsList;

in {
  packages = mergeAttrs [
    exec.packages
    library.packages
    app.packages
    pythonExt.packages
  ] // {
    simple-strict = app.packages.strict;
    simple-scanned = app.packages.scanned;
  };

  checks = mergeAttrs [
    exec.checks
    library.checks
    app.checks
    pythonExt.checks
  ];

  defaults = {
    executable = exec.packages.executableExample;
    library = library.packages.mathLibrary;
    app = app.packages.strict;
    pythonExtension = pythonExt.packages.pythonExtension;
  };

  manifests = {
    appWithLibrary = app.scannedManifest;
  };
}
