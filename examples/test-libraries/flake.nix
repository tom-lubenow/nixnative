{
  description = "Example: using test libraries (gtest, catch2, doctest) with nixnative";

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
       
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
            nixPackage = nixnative.inputs.nix.packages.${system}.default;
          ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
          native = nixnative.lib.native {
            inherit pkgs nixPackage;
            inherit (ninjaPackages) nix-ninja nix-ninja-task;
          };
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
          default = packages.gtestExample;
        }
      );

      checks = forAllSystems ({ checks, ... }: checks);
    };
}
