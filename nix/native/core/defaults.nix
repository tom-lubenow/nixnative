# Baseline defaults and merge metadata for project-facing APIs.
#
# This centralizes baseline target defaults so high-level, legacy, and
# module-first entry points share one source of truth.
{
  project = {
    includeDirs = [ ];
    defines = [ ];
    compileFlags = [ ];
    languageFlags = { };
    linkFlags = [ ];
    libraries = [ ];
    tools = [ ];
    publicIncludeDirs = [ ];
    publicDefines = [ ];
    publicCompileFlags = [ ];
    publicLinkFlags = [ ];
  };

  # Non-flag list fields merged via concatenation + dedupe (where possible).
  projectListFields = [
    "includeDirs"
    "defines"
    "libraries"
    "tools"
    "publicIncludeDirs"
    "publicDefines"
  ];

  # Flag fields merged through policy-aware flag-set utilities.
  projectFlagFields = [
    "compileFlags"
    "linkFlags"
    "languageFlags"
    "publicCompileFlags"
    "publicLinkFlags"
  ];
}
