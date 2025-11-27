{
  description = "nixnative API examples";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f { pkgs = import nixpkgs { inherit system; }; }
      );
    in
    {
      packages = forAllSystems ({ pkgs }:
        let
          # Official API (recommended)
          build = import ./build.nix { inherit pkgs; };

          # Legacy comparison files (for reference)
          optionA = import ./build-option-a.nix { inherit pkgs; };
          optionB = import ./build-option-b.nix { inherit pkgs; };
          optionC = import ./build-option-c.nix { inherit pkgs; };
        in
        {
          # Official API examples
          default = build.app;
          app = build.app;
          app-gcc = build.appGcc;
          app-gcc-mold = build.appGccMold;
          app-clang-mold = build.appClangMold;
          lib = build.mathLib;

          # Legacy: API comparison (kept for reference)
          option-a = optionA.app;
          option-b = optionB.app;
          option-c = optionC.app;
        }
      );

      devShells = forAllSystems ({ pkgs }:
        let
          build = import ./build.nix { inherit pkgs; };
        in
        {
          default = build.devShell;
        }
      );
    };
}
