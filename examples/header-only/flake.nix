# Header-only library example for nixnative
#
# Demonstrates creating and consuming header-only libraries using native.headerOnly.
# Header-only libraries have no compiled sources - just headers that consumers include.

{
  description = "Header-only library example for nixnative";

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
          packages = import ./project.nix { inherit pkgs native; };
        in
        { default = packages.testApp; inherit (packages) testApp vec3Lib; }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
        in
        import ./checks.nix { inherit pkgs native packages; }
      );
    };
}
