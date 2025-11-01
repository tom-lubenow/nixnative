{
  description = "Template: build a C++ executable linking a Rust static library via crane and nixclang";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixclang.url = "path:../..";
  inputs.crane.url = "github:ipetkov/crane/v0.16.1";
  inputs.crane.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, nixclang, crane }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          let
            pkgs = import nixpkgs { inherit system; };
            cpp = nixclang.lib.cpp { inherit pkgs; };
            craneLib = crane.lib.${system};
            packages = import ./project.nix { inherit pkgs cpp craneLib; };
            checks = import ./checks.nix { inherit pkgs packages; };
          in
          f { inherit pkgs packages checks; }
        );
    in
    {
      packages = forAllSystems ({ packages, ... }:
        packages // {
          default = packages.rustCraneInterop;
        });

      checks = forAllSystems ({ checks, ... }: checks);
    };
}
