#!/usr/bin/env python3
"""Generate a compilation derivation in Nix JSON format.

This script creates a JSON representation of a Nix derivation that
compiles a single source file. The JSON can be passed to `nix derivation add`
to create a .drv file.

Uses the standard JSON derivation format with inputSrcs and inputDrvs
(not the version 4 format).

Usage:
    python generate-compile-drv.py \
        --source-rel src/main.cc \
        --object-name main.o \
        --source-tree /nix/store/...-src-main.cc \
        --compiler /nix/store/.../bin/clang++ \
        --default-flags "-std=c++17" \
        --compile-flags "-O2 -fPIC" \
        --include-flags "-I/path/to/include" \
        --define-flags "-DFOO=1" \
        --lang-flags "" \
        --linker-flag "-fuse-ld=lld" \
        --system x86_64-linux \
        --output /tmp/compile.json
"""

import argparse
import json
import os
import sys
from pathlib import Path


def sanitize_name(name: str) -> str:
    """Sanitize a name for use in a Nix derivation name."""
    # Replace problematic characters
    result = name.replace("/", "_").replace(".", "-")
    # Remove any remaining invalid characters
    result = "".join(c if c.isalnum() or c in "-_" else "_" for c in result)
    return result


def generate_derivation(
    source_rel: str,
    object_name: str,
    source_tree: str,
    compiler: str,
    default_flags: str,
    compile_flags: str,
    include_flags: str,
    define_flags: str,
    lang_flags: str,
    linker_flag: str,
    system: str,
) -> dict:
    """Generate a derivation JSON for compiling a source file."""

    # Derivation name - use normalized output name like nix-ninja
    name = f"compile-{sanitize_name(source_rel)}"

    # Build the compile command
    # Order: default flags, compile flags, lang flags, linker flag, includes, defines
    all_flags = " ".join(
        filter(
            None,
            [
                default_flags,
                compile_flags,
                lang_flags,
                linker_flag,
                include_flags,
                define_flags,
            ],
        )
    )

    # Get paths from environment (these are set by the driver derivation)
    bash_path = os.environ.get("BASH_PATH", "/bin/sh")
    coreutils_path = os.environ.get("COREUTILS_PATH", "")

    # The builder script
    # Include PATH setup to find coreutils (mkdir, etc.)
    # Note: Don't use 'set -u' as $out is set by Nix at runtime
    builder_script = f"""
export PATH="{coreutils_path}/bin:$PATH"
set -eo pipefail
unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET
mkdir -p "$out"
{compiler} {all_flags} -c {source_tree}/{source_rel} -o "$out/{object_name}"
"""

    # Collect input sources (full store paths for inputSrcs)
    input_srcs = [source_tree]
    if coreutils_path:
        input_srcs.append(coreutils_path)

    # Standard JSON derivation format (not version 4)
    # This format uses inputSrcs (full paths) and inputDrvs
    drv = {
        "name": name,
        "system": system,
        "builder": bash_path,
        "args": ["-c", builder_script.strip()],
        "env": {
            "name": name,
        },
        "inputDrvs": {},
        "inputSrcs": sorted(set(input_srcs)),
        "outputs": {
            "out": {
                "hashAlgo": "sha256",
                "method": "nar",
            }
        },
    }

    return drv


def main():
    parser = argparse.ArgumentParser(
        description="Generate a compilation derivation JSON"
    )
    parser.add_argument("--source-rel", required=True, help="Relative source path")
    parser.add_argument("--object-name", required=True, help="Output object file name")
    parser.add_argument(
        "--source-tree", required=True, help="Store path of source tree"
    )
    parser.add_argument("--compiler", required=True, help="Compiler path")
    parser.add_argument("--default-flags", default="", help="Default compiler flags")
    parser.add_argument("--compile-flags", default="", help="Compile flags")
    parser.add_argument("--include-flags", default="", help="Include flags")
    parser.add_argument("--define-flags", default="", help="Define flags")
    parser.add_argument("--lang-flags", default="", help="Per-language flags")
    parser.add_argument("--linker-flag", default="", help="Linker driver flag")
    parser.add_argument("--system", required=True, help="System (e.g., x86_64-linux)")
    parser.add_argument("--output", required=True, help="Output JSON file path")

    args = parser.parse_args()

    drv = generate_derivation(
        source_rel=args.source_rel,
        object_name=args.object_name,
        source_tree=args.source_tree,
        compiler=args.compiler,
        default_flags=args.default_flags,
        compile_flags=args.compile_flags,
        include_flags=args.include_flags,
        define_flags=args.define_flags,
        lang_flags=args.lang_flags,
        linker_flag=args.linker_flag,
        system=args.system,
    )

    with open(args.output, "w") as f:
        json.dump(drv, f, indent=2)

    print(f"Generated: {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
