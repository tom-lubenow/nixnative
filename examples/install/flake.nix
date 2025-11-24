{
  description = "Testing Standard Installation";

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
          
          staticLib = cpp.mkStaticLib {
            name = "mylib-static";
            root = ./.;
            sources = [ "lib.cc" ];
            publicIncludeDirs = [ ./. ];
          };
          
          sharedLib = cpp.mkSharedLib {
            name = "mylib-shared";
            root = ./.;
            sources = [ "lib.cc" ];
            publicIncludeDirs = [ ./. ];
          };

        in
        {
          inherit staticLib sharedLib;
        }
      );
    };
}
