{ pkgs, native, packages }:

{
  # Verify static library exists
  installStatic = pkgs.runCommand "install-static-check" {} ''
    test -f ${packages.staticLib}/lib/libmylib-static.a
    touch $out
  '';

  # Verify shared library exists
  installShared = pkgs.runCommand "install-shared-check" {} ''
    test -f ${packages.sharedLib}/lib/libmylib-shared${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
    touch $out
  '';
}
