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
        { default = packages.app; inherit (packages) app; }
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
          clangd = native.lsps.clangd { targets = [ packages.app ]; };
        in
        {
          default = pkgs.mkShell {
            packages = clangd.packages ++ [
              (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
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
