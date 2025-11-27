# gRPC example for nixnative
#
# Demonstrates building gRPC services with the built-in gRPC tool plugin.
# Includes both server and client implementations.

{
  description = "gRPC service example for nixnative";

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
        packages // { default = packages.combined; }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
        in
        import ./checks.nix { inherit pkgs native packages; }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages = import ./project.nix { inherit pkgs native; };
          clangd = native.lsps.clangd { targets = [ packages.server packages.client ]; };
        in
        {
          default = pkgs.mkShell {
            packages = clangd.packages ++ [
              pkgs.grpcurl
              (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
            ];
            shellHook = ''
              ${clangd.shellHook}
              echo "gRPC development shell ready"
            '';
          };
        }
      );
    };
}
