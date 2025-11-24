{ pkgs, lib, utils }:
let
  inherit (lib) concatMap concatStringsSep;
  inherit (utils) toPathLike;

  mkPkgConfigLibrary =
    { name
    , packages
    , modules ? [ name ]
    }:
    let
      # Build PKG_CONFIG_PATH from provided package roots
      pkgDirs = concatMap
        (pkg:
          let candidate = toPathLike pkg;
          in map (suffix: "${candidate}/${suffix}")
            [ "lib/pkgconfig" "lib64/pkgconfig" "share/pkgconfig" ]
        )
        packages;
      pkgConfigPath = concatStringsSep ":" pkgDirs;
      moduleArgs = concatStringsSep " " (map lib.escapeShellArg modules);

      # Run pkg-config once and emit a Nix file describing public flags
      nixDrv =
        pkgs.runCommand "pkg-config-${name}.nix"
          {
            buildInputs = [ pkgs.pkg-config pkgs.python3 ] ++ packages;
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
cxx_flags = []
for token in cflags:
    if token.startswith('-I'):
        include_dirs.append(token[2:])
    elif token.startswith('-D'):
        defines.append(token[2:])
    else:
        cxx_flags.append(token)

link_flags = []
for token in libs:
    if token.startswith('-L') or token.startswith('-l') or token.startswith('-Wl'):
        link_flags.append(token)
    else:
        link_flags.append(token)

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
cxx_flags = dedup(cxx_flags)
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
    fh.write("  cxxFlags = [\n")
    for flag in cxx_flags:
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
        cxxFlags = info.cxxFlags;
        linkFlags = info.linkFlags;
      };
      passthru = {
        inherit packages modules info;
      };
    };
in
{
  inherit mkPkgConfigLibrary;
}
