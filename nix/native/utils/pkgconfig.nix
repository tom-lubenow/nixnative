# pkg-config integration for nixnative
#
# Provides utilities to wrap pkg-config libraries for use with nixnative.
#
{ pkgs, lib }:

let
  inherit (lib) concatMap concatStringsSep;

  # Create a library wrapper from pkg-config modules
  #
  # Arguments:
  #   name     - Library name (for identification)
  #   packages - Nix packages that provide the library
  #   modules  - pkg-config module names (defaults to [ name ])
  #
  # Returns an attribute set with `public` that can be used as a library dependency.
  #
  mkPkgConfigLibrary =
    {
      name,
      packages,
      modules ? [ name ],
    }:
    let
      # Build PKG_CONFIG_PATH from provided package roots
      pkgDirs = concatMap (
        pkg:
        let
          candidate = if builtins.isString pkg then pkg else "${pkg}";
        in
        map (suffix: "${candidate}/${suffix}") [
          "lib/pkgconfig"
          "lib64/pkgconfig"
          "share/pkgconfig"
        ]
      ) packages;
      pkgConfigPath = concatStringsSep ":" pkgDirs;
      moduleArgs = concatStringsSep " " (map lib.escapeShellArg modules);

      # Run pkg-config once and emit a Nix file describing public flags
      nixDrv =
        pkgs.runCommand "pkg-config-${name}.nix"
          {
            buildInputs = [
              pkgs.pkg-config
              pkgs.python3
            ]
            ++ packages;
            PKG_CONFIG_PATH = pkgConfigPath;
          }
          ''
                        set -euo pipefail
                        cflags=$(${pkgs.pkg-config}/bin/pkg-config --cflags ${moduleArgs})
                        libs=$(${pkgs.pkg-config}/bin/pkg-config --libs ${moduleArgs})
            ${pkgs.python3}/bin/python - "$cflags" "$libs" "$out" <<'PY'
            import shlex
            import sys

            cflags = shlex.split(sys.argv[1])
            libs = shlex.split(sys.argv[2])
            out_path = sys.argv[3]

            include_dirs = []
            defines = []
            compile_flags = []
            for token in cflags:
                if token.startswith('-I'):
                    include_dirs.append(token[2:])
                elif token.startswith('-D'):
                    defines.append(token[2:])
                else:
                    compile_flags.append(token)

            link_flags = []
            rpath_dirs = []
            for token in libs:
                if token.startswith('-L'):
                    link_flags.append(token)
                    # Extract the directory path and add rpath for runtime library lookup
                    rpath_dirs.append(token[2:])
                elif token.startswith('-l') or token.startswith('-Wl'):
                    link_flags.append(token)
                else:
                    link_flags.append(token)

            # Add rpath flags for each library directory (needed on Linux for runtime)
            for rpath_dir in rpath_dirs:
                link_flags.append(f'-Wl,-rpath,{rpath_dir}')

            def dedup(seq):
                out = []
                seen = set()
                for item in seq:
                    if item not in seen:
                        seen.add(item)
                        out.append(item)
                return out

            include_dirs = dedup(include_dirs)
            defines = dedup(defines)
            compile_flags = dedup(compile_flags)
            link_flags = dedup(link_flags)

            def quote(s):
                return s.replace('\\\\', '\\\\\\\\').replace('"', '\\\\"')

            with open(out_path, 'w') as fh:
                fh.write("{\n")
                fh.write("  includeDirs = [\n")
                for dir in include_dirs:
                    fh.write(f'    (builtins.toPath "{quote(dir)}")\n')
                fh.write("  ];\n")
                fh.write("  defines = [\n")
                for define in defines:
                    fh.write(f'    "{quote(define)}"\n')
                fh.write("  ];\n")
                fh.write("  compileFlags = [\n")
                for flag in compile_flags:
                    fh.write(f'    "{quote(flag)}"\n')
                fh.write("  ];\n")
                fh.write("  linkFlags = [\n")
                for flag in link_flags:
                    fh.write(f'    "{quote(flag)}"\n')
                fh.write("  ];\n")
                fh.write("}\n")
            PY
          '';

      info = import nixDrv;
      includeDirAttrs = map (dir: { path = dir; }) info.includeDirs;
      definesList = info.defines;
    in
    {
      inherit name nixDrv;
      drv = nixDrv;
      public = {
        includeDirs = includeDirAttrs;
        defines = definesList;
        compileFlags = info.compileFlags;
        linkFlags = info.linkFlags;
      };
      # Expose all package outputs as evalInputs so scanner can add them to buildInputs
      # This ensures store paths (including .dev outputs with headers) are available in the sandbox
      # pkg.all gives all outputs; fallback to just pkg if .all doesn't exist
      evalInputs = concatMap (
        pkg:
        if pkg ? all then
          pkg.all
        else if pkg ? dev then
          [
            pkg
            pkg.dev
          ]
        else
          [ pkg ]
      ) packages;
      passthru = {
        inherit packages modules info;
      };
    };

in
{
  inherit mkPkgConfigLibrary;

  # Convenience alias matching old cpp API
  makeLibrary = mkPkgConfigLibrary;
}
