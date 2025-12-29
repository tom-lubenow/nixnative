{ pkgs, native, packages }:

{
  # Verify static archive builds
  # With dynamic derivations, file existence is verified by build success
  installStatic = packages.staticLib;

  # Verify shared library builds
  installShared = packages.sharedLib;
}
