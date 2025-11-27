# Multi-binary example for nixnative
#
# Demonstrates building multiple executables that share common libraries.
# A common real-world pattern: CLI tool, daemon service, and test harness.

{
  description = "Multi-binary project example for nixnative";

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
          clangd = native.lsps.clangd { targets = [ packages.cli packages.daemon packages.tests ]; };
        in
        {
          default = pkgs.mkShell {
            packages = clangd.packages ++ [
              (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
            ];
            shellHook = ''
              ${clangd.shellHook}
              echo "Multi-binary dev shell ready"
            '';
          };
        }
      );
    };
}
