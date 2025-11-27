# pkg-config integration example for nixnative
#
# Demonstrates using system libraries via pkg-config and macOS frameworks.

{
  description = "pkg-config integration example for nixnative";

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
          # Wrapping System Libraries with pkg-config
          # ================================================================

          # zlib - compression library
          #
          # mkPkgConfigLibrary runs pkg-config to extract:
          # - Include paths (-I flags)
          # - Defines (-D flags)
          # - Link flags (-l and -L flags)
          zlibLib = native.pkgConfig.makeLibrary {
            name = "zlib";
            packages = [ pkgs.zlib ];
            # modules defaults to [ name ], i.e. [ "zlib" ]
          };

          # curl - HTTP client library
          #
          # Some libraries have different pkg-config module names
          curlLib = native.pkgConfig.makeLibrary {
            name = "curl";
            packages = [ pkgs.curl ];
            modules = [ "libcurl" ];  # pkg-config module name
          };

          # ================================================================
          # macOS Frameworks (Darwin only)
          # ================================================================

          # On macOS, many system APIs are in frameworks rather than
          # traditional libraries. mkFrameworkLibrary handles the
          # -framework flag and SDK path.
          frameworkLibs =
            if pkgs.stdenv.isDarwin then [
              (native.pkgConfig.mkFrameworkLibrary {
                name = "CoreFoundation";
              })
              (native.pkgConfig.mkFrameworkLibrary {
                name = "Security";
              })
            ]
            else [];

          # ================================================================
          # Building with pkg-config Libraries
          # ================================================================

          demo = native.executable {
            name = "pkgconfig-demo";
            root = ./.;
            sources = [ "main.cc" ];

            # Use pkg-config wrapped libraries just like any other library
            libraries = [ zlibLib curlLib ] ++ frameworkLibs;
          };

        in
        {
          default = demo;
          inherit demo zlibLib curlLib;
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          native = nixnative.lib.native { inherit pkgs; };
          packages' = self.packages.${system};
        in
        {
          demo = native.test {
            name = "pkgconfig-demo";
            executable = packages'.demo;
            expectedOutput = "All libraries working correctly";
          };
        }
      );
    };
}
