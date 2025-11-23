{
  description = "WASM example for nixclang using Emscripten";

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
          
          # Import our custom toolchain
          emscriptenToolchain = import ../../nix/toolchains/emscripten.nix { inherit pkgs; };

        in
        {
          default = cpp.mkExecutable {
            name = "wasm-example.js"; # Emscripten outputs .js by default (which loads the .wasm)
            root = ./.;
            sources = [ "main.cc" ];
            toolchain = emscriptenToolchain;
          };
        }
      );
    };
}
