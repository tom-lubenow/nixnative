# Example: Composable Project API
#
# This example demonstrates the new `native.project` API which returns
# scoped builders with shared defaults. Targets are real values that
# can be passed directly to `libraries`, imported from other files,
# or composed with plain Nix functions.
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  inputs.nixnative.url = "../..";

  outputs = { nixpkgs, nixnative, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      native = nixnative.lib.native { inherit pkgs; };

      # Create a project with shared defaults
      proj = native.project {
        root = ./.;
        includeDirs = [ "include" ];
        warnings = "all";
      };

      # Build targets - these are real values, not string references!
      libmath = proj.staticLib {
        name = "libmath";
        sources = [ "src/lib.c" ];
        publicIncludeDirs = [ "include" ];
      };

      app = proj.executable {
        name = "calculator";
        sources = [ "src/main.c" ];
        libraries = [ libmath ];  # Direct reference, not { target = "..."; }
      };

      # Helper pattern for multiple similar targets
      mkTool = name: proj.executable {
        inherit name;
        sources = [ "src/main.c" ];
        libraries = [ libmath ];
        defines = [ "TOOL_NAME=\"${name}\"" ];
      };

      tool1 = mkTool "tool1";
      tool2 = mkTool "tool2";

    in {
      packages.${system} = {
        inherit libmath app tool1 tool2;
        default = app;
      };

      devShells.${system}.default = native.devShell {
        target = app;
      };
    };
}
