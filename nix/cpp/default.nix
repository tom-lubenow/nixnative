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
