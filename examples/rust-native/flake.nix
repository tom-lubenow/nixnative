{
  description = "Rust native example - building Rust without Cargo";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixnative.url = "../..";

  outputs =
    {
      nixpkgs,
      nixnative,
      ...
    }:
    let
      system = "aarch64-darwin"; # Adjust for your system
      pkgs = import nixpkgs { inherit system; };
      native = nixnative.lib.native { inherit pkgs; };
      project = import ./project.nix { inherit pkgs native; };
    in
    {
      packages.${system} = {
        inherit (project) mylib app;
        default = project.app;
      };
    };
}
