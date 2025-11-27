{
  description = "Testing mkDevShell";

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
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };

          app = native.executable {
            name = "app";
            root = ./.;
            sources = [ "main.cc" ];
          };

        in
        {
          default = native.devShell {
            target = app;
            includeTools = true;
          };
        }
      );
    };
}
