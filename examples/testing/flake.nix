{
  description = "Testing mkTest";

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
          
          app = cpp.mkExecutable {
            name = "test-app";
            root = ./.;
            sources = [ "main.cc" ];
          };
          
          test1 = cpp.mkTest {
            name = "basic-test";
            executable = app;
            expectedOutput = "Hello Test";
          };
          
          test2 = cpp.mkTest {
            name = "arg-test";
            executable = app;
            args = [ "World" ];
            expectedOutput = "Hello World";
          };

        in
        {
          default = app;
          inherit test1 test2;
        }
      );
    };
}
