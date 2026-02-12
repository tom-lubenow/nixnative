# Installation packaging for nixnative
#
# Provides mkInstallation for creating standard installable packages
# with proper bin/, lib/, include/ directory structure.
#
# Usage:
#   native.mkInstallation {
#     name = "myproject";
#     version = "1.0.0";
#     executables = [ app1 app2 ];
#     libraries = [ libfoo libbar ];
#     headers = [ "include" ];  # Directory to copy
#   };
#
{
  pkgs,
  lib,
}:

let
  # Get the actual output from a nixnative target
  realizeTarget = pkg:
    if pkg ? target
    then pkg.target
    else if pkg ? passthru && pkg.passthru ? target
    then pkg.passthru.target
    else pkg;

in
{
  # Create an installable package with standard directory structure
  #
  # Arguments:
  #   name         - Package name
  #   version      - Package version (optional)
  #   executables  - List of executable targets to install to bin/
  #   libraries    - List of library targets to install to lib/
  #   headers      - List of header directories/files to install to include/
  #   extraFiles   - Additional files to copy { src, dest }
  #   pkgConfig    - Generate .pc file (true/false or config attrs)
  #
  mkInstallation =
    {
      name,
      version ? "0.0.0",
      executables ? [],
      libraries ? [],
      headers ? [],
      extraFiles ? [],
      pkgConfig ? false,
      ...
    }:
    let
      # Realize all targets
      realizedExecutables = map (exe:
        let
          target = realizeTarget exe;
          binaryPath = exe.executablePath or null;
        in {
          name = exe.name or (builtins.baseNameOf (toString target));
          path = target;
          inherit binaryPath;
        }
      ) executables;

      realizedLibraries = map (lib:
        let
          target = realizeTarget lib;
          libName = lib.name or "unknown";
        in {
          name = libName;
          path = target;
          archivePath = lib.archivePath or "${target}/${libName}.a";
          sharedPath = lib.sharedLibrary or null;
          publicIncludeDirs = lib.public.includeDirs or [];
        }
      ) libraries;

      # Generate pkg-config file if requested
      pkgConfigFile = if pkgConfig != false then
        let
          cfg = if builtins.isAttrs pkgConfig then pkgConfig else {};
          description = cfg.description or "${name} library";
          libNames = map (l: "-l${l.name}") realizedLibraries;
        in
        pkgs.writeText "${name}.pc" ''
          prefix=@out@
          exec_prefix=''${prefix}
          libdir=''${prefix}/lib
          includedir=''${prefix}/include

          Name: ${name}
          Description: ${description}
          Version: ${version}
          Libs: -L''${libdir} ${lib.concatStringsSep " " libNames}
          Cflags: -I''${includedir}
        ''
      else null;

      # Build script for installation
      installScript = ''
        mkdir -p $out/bin $out/lib $out/include

        # Install executables
        ${lib.concatMapStringsSep "\n" (exe: ''
          ${if exe.binaryPath != null then ''
            if [ -f "${exe.binaryPath}" ]; then
              cp "${exe.binaryPath}" $out/bin/${exe.name}
            elif [ -d "${exe.path}/bin" ]; then
              cp -r "${exe.path}/bin/"* $out/bin/
            elif [ -f "${exe.path}/${exe.name}" ]; then
              cp "${exe.path}/${exe.name}" $out/bin/${exe.name}
            elif [ -f "${exe.path}" ]; then
              cp "${exe.path}" $out/bin/${exe.name}
            fi
          '' else ''
            if [ -d "${exe.path}/bin" ]; then
              cp -r "${exe.path}/bin/"* $out/bin/
            elif [ -f "${exe.path}/${exe.name}" ]; then
              cp "${exe.path}/${exe.name}" $out/bin/${exe.name}
            elif [ -f "${exe.path}" ]; then
              cp "${exe.path}" $out/bin/${exe.name}
            fi
          ''}
        '') realizedExecutables}

        # Install libraries
        ${lib.concatMapStringsSep "\n" (l: ''
          # Copy archive if it exists
          if [ -f "${l.archivePath}" ]; then
            cp "${l.archivePath}" $out/lib/
          fi
          # Copy shared library if it exists
          ${if l.sharedPath != null then ''
            if [ -f "${l.sharedPath}" ]; then
              cp "${l.sharedPath}" $out/lib/
            fi
          '' else ""}
        '') realizedLibraries}

        # Install headers
        ${lib.concatMapStringsSep "\n" (h:
          if builtins.isString h then
            # It's a directory path relative to some root
            ''
              if [ -d "${h}" ]; then
                cp -r "${h}"/* $out/include/ 2>/dev/null || true
              elif [ -f "${h}" ]; then
                cp "${h}" $out/include/
              fi
            ''
          else if builtins.isAttrs h && h ? path then
            ''
              if [ -d "${h.path}" ]; then
                cp -r "${h.path}"/* $out/include/ 2>/dev/null || true
              fi
            ''
          else
            ""
        ) headers}

        # Also copy public includes from libraries
        ${lib.concatMapStringsSep "\n" (l:
          lib.concatMapStringsSep "\n" (inc:
            if inc ? path then ''
              if [ -d "${inc.path}" ]; then
                cp -r "${inc.path}"/* $out/include/ 2>/dev/null || true
              fi
            '' else ""
          ) l.publicIncludeDirs
        ) realizedLibraries}

        # Install extra files
        ${lib.concatMapStringsSep "\n" (f: ''
          mkdir -p "$(dirname "$out/${f.dest}")"
          cp -r "${f.src}" "$out/${f.dest}"
        '') extraFiles}

        # Install pkg-config file
        ${if pkgConfigFile != null then ''
          mkdir -p $out/lib/pkgconfig
          sed "s|@out@|$out|g" ${pkgConfigFile} > $out/lib/pkgconfig/${name}.pc
        '' else ""}
      '';

      # Dependencies for the derivation
      deps = (map (e: e.path) realizedExecutables)
        ++ (map (l: l.path) realizedLibraries);

    in
    pkgs.runCommand "${name}-${version}" {
      inherit version;
      buildInputs = deps;
    } installScript;
}
