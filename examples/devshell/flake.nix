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

          app = native.executable {
            name = "app";
            root = ./.;
            sources = [ "main.cc" ];
          };

          # Configure clangd for the target(s)
          # This extracts compile_commands.json and provides the clangd package
          clangd = native.lsps.clangd {
            targets = [ app ];
            # Can also use: target = app;
          };

        in
        {
          # Users construct their own devShell, using clangd configuration
          default = pkgs.mkShell {
            packages = clangd.packages ++ [
              # Add any other tools you need
              (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
            ];

            shellHook = ''
              ${clangd.shellHook}
              # Add any other shell setup you need
              echo "Development shell ready. clangd configured for: app"
            '';
          };

          # Example with multiple targets
          multi = let
            lib1 = native.staticLib {
              name = "lib1";
              root = ./.;
              sources = [ "main.cc" ];  # reusing main.cc for demo
            };
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
