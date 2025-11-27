# Simple tool example for nixnative
#
# Demonstrates the simplest possible custom code generator using the
# generator schema directly. This is a good starting point before
# moving to the more sophisticated mkTool infrastructure.

{
  description = "Simple code generator example for nixnative";

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
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };

          # ================================================================
          # Method 1: Inline generator (simplest approach)
          # ================================================================
          #
          # A generator is just an attrset with headers/sources that
          # the build system incorporates. This is the minimal way to
          # add generated code.

          # Read version from a file
          versionStr = builtins.readFile ./version.txt;
          versionParts = builtins.filter (x: x != "")
            (builtins.split "\\." (pkgs.lib.removeSuffix "\n" versionStr));

          # Generate the version header
          versionHeader = pkgs.writeText "version.h" ''
            #pragma once

            #define VERSION_MAJOR ${builtins.elemAt versionParts 0}
            #define VERSION_MINOR ${builtins.elemAt versionParts 1}
            #define VERSION_PATCH ${builtins.elemAt versionParts 2}
            #define VERSION_STRING "${pkgs.lib.removeSuffix "\n" versionStr}"
          '';

          # The generator attrset - this is the interface nixnative expects
          versionGenerator = {
            name = "version-generator";

            # Generated headers with their "virtual" paths
            headers = [
              {
                rel = "version.h";       # Path used in #include "version.h"
                path = versionHeader;    # Actual file location
              }
            ];

            # Include directory for the generated header
            includeDirs = [ { path = builtins.dirOf versionHeader; } ];
          };

          # App using the inline generator
          appInline = native.executable {
            name = "simple-tool-inline";
            root = ./.;
            sources = [ "main.cc" ];

            # Pass generators via the 'tools' parameter
            tools = [ versionGenerator ];
          };

          # ================================================================
          # Method 2: Generator derivation (more flexible)
          # ================================================================
          #
          # When you need to run actual commands (sed, awk, python, etc.),
          # create a derivation that produces the generated files.

          # Derivation that generates multiple files
          generatorDrv = pkgs.runCommand "my-generator" {
            version = pkgs.lib.removeSuffix "\n" versionStr;
          } ''
            mkdir -p $out/include

            # Generate a more complex header
            cat > $out/include/config.h <<EOF
            #pragma once

            // Generated configuration
            #define APP_NAME "simple-tool"
            #define APP_VERSION "$version"
            #define BUILD_TYPE "release"

            namespace config {
              constexpr const char* name = APP_NAME;
              constexpr const char* version = APP_VERSION;
            }
            EOF
          '';

          # Generator from the derivation
          configGenerator = {
            name = "config-generator";
            headers = [
              { rel = "config.h"; path = "${generatorDrv}/include/config.h"; }
            ];
            includeDirs = [ { path = "${generatorDrv}/include"; } ];
          };

          # ================================================================
          # Method 3: Using native.tools.jinja (built-in)
          # ================================================================
          #
          # For template-based generation, use the built-in Jinja tool.
          # See app-with-library/ for a complete example.

        in
        {
          default = appInline;
          inherit appInline;
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages' = self.packages.${system};
        in
        {
          app = native.test {
            name = "simple-tool";
            executable = packages'.appInline;
            expectedOutput = "Code generation working";
          };
        }
      );
    };
}
