# Mixed C/C++ example for nixnative
#
# Demonstrates building projects with both C (.c) and C++ (.cc) sources.
# Shows proper extern "C" usage for C/C++ interoperability.

{
  description = "Mixed C/C++ project example for nixnative";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nixPackage = nixnative.inputs.nix.packages.${system}.default;
          ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
          native = nixnative.lib.native {
            inherit pkgs nixPackage;
            inherit (ninjaPackages) nix-ninja nix-ninja-task;
          };
          packages = import ./project.nix { inherit pkgs native; };
        in
        packages // { default = packages.mixedApp; }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nixPackage = nixnative.inputs.nix.packages.${system}.default;
          ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
          native = nixnative.lib.native {
            inherit pkgs nixPackage;
            inherit (ninjaPackages) nix-ninja nix-ninja-task;
          };
          packages = import ./project.nix { inherit pkgs native; };
        in
        import ./checks.nix { inherit pkgs native packages; }
      );
    };
}
