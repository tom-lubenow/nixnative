{
  description = "Template: build a standalone executable with nixnative";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixnative.url = "path:../..";

  outputs =
    {
      self,
      nixpkgs,
      nixnative,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
            native = nixnative.lib.native { inherit pkgs; };
            packages = import ./project.nix { inherit pkgs native; };
            checks = import ./checks.nix { inherit pkgs packages; };
          in
          f {
            inherit
              pkgs
              native
              packages
              checks
              ;
          }
        );
    in
    {
      packages = forAllSystems (
        { packages, ... }:
        packages
        // {
          default = packages.executableExample;
        }
      );

      checks = forAllSystems ({ checks, ... }: checks);
    };
}
