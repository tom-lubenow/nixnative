# Development shell example for nixnative
#
# Demonstrates setting up IDE support via native.lsps.clangd.
# This creates a development environment where:
# - clangd can find all headers and compile flags
# - compile_commands.json is automatically symlinked
# - Debuggers and other tools are available

{
  description = "Devshell example using native.lsps.clangd";

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

          # Build target - clangd needs this to extract compile_commands.json
          app = native.executable {
            name = "app";
            root = ./.;
            sources = [ "main.cc" ];
          };

          # Configure clangd for the target
          #
          # This extracts compile_commands.json from the build and provides:
          # - clangd.packages: list of packages to add to the shell
          # - clangd.shellHook: script to symlink compile_commands.json
          clangd = native.lsps.clangd {
            targets = [ app ];
            # Alternative for single target:
            # target = app;
          };

        in
        {
          # Default development shell
          #
          # Users construct their own devShell using the clangd configuration.
          # This gives full control over what tools are included.
          default = pkgs.mkShell {
            packages = clangd.packages ++ [
              # Add debugger (lldb on macOS, gdb on Linux)
              (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
            ];

            shellHook = ''
              ${clangd.shellHook}
              echo "Development shell ready. clangd configured for: app"
            '';
          };

          # Example with multiple targets
          #
          # When you have multiple build targets (app, libraries, etc.),
          # clangd can be configured to understand all of them.
          multi = let
            lib1 = native.staticLib {
              name = "lib1";
              root = ./.;
              sources = [ "main.cc" ];  # Reusing main.cc for demo
            };

            # Configure clangd for multiple targets - their compile_commands.json
            # files are merged together
            multiClangd = native.lsps.clangd {
              targets = [ app lib1 ];
            };
          in pkgs.mkShell {
            packages = multiClangd.packages;
            shellHook = multiClangd.shellHook;
          };
        }
      );
    };
}
