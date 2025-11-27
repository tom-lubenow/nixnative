# Library installation example for nixnative
#
# Demonstrates building both static and shared libraries with proper
# installation layout (headers in $out/include, libraries in $out/lib).

{
  description = "Testing Standard Installation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };

          # Static library
          #
          # Output:
          #   $out/lib/libmylib-static.a
          #   $out/include/lib.h
          staticLib = native.staticLib {
            name = "mylib-static";
            root = ./.;
            sources = [ "lib.cc" ];
            publicIncludeDirs = [ ./. ];  # Installs lib.h to $out/include
          };

          # Shared library
          #
          # Output:
          #   $out/lib/libmylib-shared.so (or .dylib on macOS)
          #   $out/include/lib.h
          sharedLib = native.sharedLib {
            name = "mylib-shared";
            root = ./.;
            sources = [ "lib.cc" ];
            publicIncludeDirs = [ ./. ];
          };

        in
        {
          inherit staticLib sharedLib;
        }
      );
    };
}
