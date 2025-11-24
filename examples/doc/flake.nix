{
  description = "Testing mkDoc";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixclang.url = "path:../../";
  };

  outputs = { self, nixpkgs, nixclang }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          cpp = nixclang.lib.cpp { inherit pkgs; };
          
          docs = cpp.mkDoc {
            name = "my-docs";
            root = ./.;
            sources = [ "main.cc" ];
          };

        in
        {
          default = docs;
        }
      );
    };
}
