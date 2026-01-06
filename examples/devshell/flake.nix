# Development shell example for nixnative
#
# Demonstrates setting up IDE support via native.lsps.clangd.
# This creates a development environment where:
# - clangd can find all headers and compile flags
# - compile_commands.json is automatically symlinked
# - Debuggers and other tools are available

{
  description = "Devshell example using native.lsps.clangd";

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
          project = import ./project.nix { inherit pkgs native; };
          packages = project.packages;
        in
        { default = packages.app; inherit (packages) app; }
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
          project = import ./project.nix { inherit pkgs native; };
        in
        project.checks
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nixPackage = nixnative.inputs.nix.packages.${system}.default;
          ninjaPackages = nixnative.inputs.nix-ninja.packages.${system};
          native = nixnative.lib.native {
            inherit pkgs nixPackage;
            inherit (ninjaPackages) nix-ninja nix-ninja-task;
          };
          project = import ./project.nix { inherit pkgs native; };
          packages = project.packages;
          clangd = native.lsps.clangd { targets = [ packages.app ]; };
        in
        {
          default = pkgs.mkShell {
            packages = clangd.packages ++ [
              pkgs.gdb
            ];
            shellHook = ''
              ${clangd.shellHook}
              echo "Development shell ready. clangd configured for: app"
            '';
          };
        }
      );
    };
}
