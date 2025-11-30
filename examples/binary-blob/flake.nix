{
  description = "Binary blob embedding example - objcopy replacement";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixnative.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixnative }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          native = nixnative.lib.native { inherit pkgs; };
          project = import ./project.nix { inherit pkgs native; };
        in project // { default = project.app; }
      );

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          packages = self.packages.${system};
        in import ./checks.nix { inherit pkgs packages; }
      );

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          native = nixnative.lib.native { inherit pkgs; };
        in {
          default = native.devShell {
            target = self.packages.${system}.app;
          };
        }
      );
    };
}
