# Language detection and registry for nixnative
#
# Defines supported languages and their file extension mappings.
# Languages are first-class concepts - adding a new language is just
# adding an entry here, then providing compiler support in the toolchain.
#
{ lib }:

let
  inherit (lib) hasSuffix findFirst;

in
rec {
  # ==========================================================================
  # Language Definitions
  # ==========================================================================

  # Each language defines:
  #   name       - Canonical name used as key in toolchain.languages
  #   extensions - File extensions that map to this language
  #
  # Note: Languages here are just identity + extension mapping.
  # The actual compiler/flags come from the toolchain.

  c = {
    name = "c";
    extensions = [ ".c" ];
    headerExtensions = [ ".h" ];
  };

  cpp = {
    name = "cpp";
    extensions = [ ".cc" ".cpp" ".cxx" ".C" ];
    headerExtensions = [ ".hpp" ".hxx" ".hh" ".H" ];
  };

  rust = {
    name = "rust";
    extensions = [ ".rs" ];
    headerExtensions = [ ];
  };

  # Future languages can be added here:
  # objc = {
  #   name = "objc";
  #   extensions = [ ".m" ];
  # };
  #
  # objcpp = {
  #   name = "objcpp";
  #   extensions = [ ".mm" ];
  # };
  #
  # zig = {
  #   name = "zig";
  #   extensions = [ ".zig" ];
  # };
  #
  # asm = {
  #   name = "asm";
  #   extensions = [ ".s" ".S" ".asm" ];
  # };

  # ==========================================================================
  # Language Registry
  # ==========================================================================

  # All known languages
  all = [ c cpp rust ];

  # ==========================================================================
  # Language Detection
  # ==========================================================================

  # Check if a filename has a given extension
  hasExtension = ext: filename: hasSuffix ext filename;

  # Check if a filename matches any of a language's extensions
  matchesLanguage = lang: filename:
    builtins.any (ext: hasExtension ext filename) lang.extensions;

  # Detect language from filename
  # Returns the language attrset or null if unknown
  detectLanguage = filename:
    findFirst (lang: matchesLanguage lang filename) null all;

  # Detect language name from filename
  # Returns the language name string or throws if unknown
  detectLanguageName = filename:
    let
      lang = detectLanguage filename;
    in
    if lang == null then
      throw "nixnative: unknown source file extension for '${filename}'. Supported: ${
        lib.concatStringsSep ", " (lib.concatMap (l: l.extensions) all)
      }"
    else
      lang.name;

  # ==========================================================================
  # Utilities
  # ==========================================================================

  # Get all supported source extensions
  allExtensions = lib.concatMap (l: l.extensions) all;

  # Get all supported header extensions
  allHeaderExtensions = lib.concatMap (l: l.headerExtensions or []) all;

  # Check if a file is a supported source file (needs compilation)
  isSourceFile = filename:
    builtins.any (ext: hasExtension ext filename) allExtensions;

  # Check if a file is a header file (included, not compiled)
  isHeaderFile = filename:
    builtins.any (ext: hasExtension ext filename) allHeaderExtensions;
}
