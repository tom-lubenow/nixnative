{ pkgs }:

let
  utils = import ./utils.nix { inherit pkgs; };
  toolchain = import ./toolchain.nix { inherit pkgs; inherit (pkgs) lib; };
  inherit (toolchain) clangToolchain;
  
  scanner = import ./scanner.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    inherit utils clangToolchain;
  };
  
  builders = import ./builders.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    inherit utils clangToolchain scanner;
  };

  pkgconfig = import ./pkgconfig.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    inherit utils;
  };
in
{
  inherit (toolchain) clangToolchain;
  inherit (scanner) mkDependencyScanner mkManifest;
  inherit (builders)
    compileTranslationUnit
    linkExecutable
    generateCompileCommands
    mkBuildContext
    mkExecutable
    mkStaticLib
    mkSharedLib
    mkPythonExtension
    mkHeaderOnly
    mkTest
    mkDoc
    mkDevShell;
  
  pkgConfig = {
    makeLibrary = pkgconfig.mkPkgConfigLibrary;
  };
  
  inherit (utils)
    sanitizeName
    sanitizePath
    toPathLike
    normalizeIncludeDir
    emptyPublic
    mergePublic
    libraryPublic
    collectPublic
    normalizeSources
    headerSet
    mkSourceTree
    toIncludeFlags
    toDefineFlags;
}
