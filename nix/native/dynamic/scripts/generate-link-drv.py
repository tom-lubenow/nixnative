#!/usr/bin/env python3
"""Generate a link derivation in Nix JSON format.

This script creates a JSON representation of a Nix derivation that
links object files from compilation derivations into a final executable
or library. The JSON can be passed to `nix derivation add` to create a .drv file.

Uses the standard JSON derivation format with inputSrcs and inputDrvs.
Compilation derivations are referenced via dynamicOutputs.

Usage:
    python generate-link-drv.py \
        --name myapp \
        --output-type executable \
        --compile-drvs /path/to/compile_drvs.json \
        --link-config /path/to/link_config.json \
        --system x86_64-linux \
        --output /tmp/link.json
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional
import hashlib


def nixbase32_encode(data: bytes) -> str:
    """Encode bytes to Nix's base32 format.

    Nix uses a custom base32 alphabet and encoding:
    - Little-endian byte interpretation
    - LSB-first digit extraction
    - Result is REVERSED at the end
    """
    # Nix uses a custom base32 alphabet
    alphabet = "0123456789abcdfghijklmnpqrsvwxyz"

    # Convert to integer (little-endian)
    num = int.from_bytes(data, byteorder='little')

    # Encode
    result = []
    for _ in range(52):  # 256 bits = 52 base32 chars
        result.append(alphabet[num % 32])
        num //= 32

    # CRITICAL: Nix reverses the result
    return ''.join(reversed(result))


def compute_standard_placeholder(output_name: str) -> str:
    """Compute the standard placeholder for an output.

    For CA derivations, the placeholder is:
    sha256("nix-output:<output_name>")
    """
    clear_text = f"nix-output:{output_name}"
    digest = hashlib.sha256(clear_text.encode()).digest()
    return "/" + nixbase32_encode(digest)


def compute_placeholder(drv_path: str, output_name: str) -> str:
    """Compute the nix-upstream-output placeholder for a CA derivation output.

    For CA derivations, the placeholder is computed as:
    sha256("nix-upstream-output:<hash-part>:<name>-<output>")
    """
    # Extract hash part and name from drv path
    # /nix/store/<hash>-<name>.drv -> hash, name
    basename = os.path.basename(drv_path)
    if basename.endswith('.drv'):
        basename = basename[:-4]

    parts = basename.split('-', 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid drv path: {drv_path}")

    hash_part = parts[0]
    drv_name = parts[1]

    # Compute the placeholder
    clear_text = f"nix-upstream-output:{hash_part}:{drv_name}-{output_name}"
    digest = hashlib.sha256(clear_text.encode()).digest()
    encoded = nixbase32_encode(digest)

    return f"/{encoded}"


def compute_dynamic_placeholder(upstream_placeholder: str, output_name: str) -> str:
    """Compute the nix-computed-output placeholder for a dynamic derivation output.

    For dynamic derivations, we need to reference the output of a derivation
    that is itself an output of another derivation.
    """
    # Take first 20 bytes of the hash
    # The placeholder starts with /
    if upstream_placeholder.startswith('/'):
        upstream_placeholder = upstream_placeholder[1:]

    # Decode the base32 to get the hash bytes
    alphabet = "0123456789abcdfghijklmnpqrsvwxyz"
    num = 0
    for c in reversed(upstream_placeholder):
        num = num * 32 + alphabet.index(c)

    # Convert to bytes (little-endian, 32 bytes)
    hash_bytes = num.to_bytes(32, byteorder='little')

    # Take first 20 bytes
    compressed = hash_bytes[:20]

    # Compute the placeholder
    clear_text = f"nix-computed-output:{compressed.hex()}:{output_name}"
    digest = hashlib.sha256(clear_text.encode()).digest()
    encoded = nixbase32_encode(digest)

    return f"/{encoded}"


def generate_link_derivation(
    name: str,
    output_type: str,
    compile_drvs: List[Dict],
    link_config: Dict,
    system: str,
) -> dict:
    """Generate a link derivation JSON.

    Args:
        name: Target name
        output_type: "executable", "sharedLibrary", or "staticArchive"
        compile_drvs: List of {drv_path, object_name} for compilation derivations
        link_config: Link configuration from driver
        system: System type (e.g., x86_64-linux)
    """

    # Get paths from environment
    bash_path = os.environ.get("BASH_PATH", "/bin/sh")
    coreutils_path = os.environ.get("COREUTILS_PATH", "")

    # Extract link configuration
    compiler = link_config.get("compiler", link_config.get("cppCompiler", ""))
    linker_driver_flag = link_config.get("linkerDriverFlag", "")
    link_flags = link_config.get("linkFlags", [])
    driver_flags = link_config.get("driverFlags", [])
    ar = link_config.get("ar", "ar")
    ranlib = link_config.get("ranlib")
    linker_inputs = link_config.get("linkerInputs", [])

    # Build input derivations:
    # Compile derivations have already been built by the driver,
    # so we use their actual output paths directly
    input_drvs = {}  # Map from drv path -> {outputs: [...], dynamicOutputs: {}}
    object_paths = []

    for compile_drv in compile_drvs:
        drv_path = compile_drv["drv"]
        object_name = compile_drv["object"]
        out_path = compile_drv.get("out", "")

        # Add to inputDrvs (John Ericson's Nix format: {outputs: [...], dynamicOutputs: {}})
        if drv_path not in input_drvs:
            input_drvs[drv_path] = {"outputs": ["out"], "dynamicOutputs": {}}

        # Use actual output path from built compile derivation
        if out_path:
            object_paths.append(f"{out_path}/{object_name}")
        else:
            # Fallback to placeholder if output path not provided
            placeholder = compute_placeholder(drv_path, "out")
            object_paths.append(f"{placeholder}/{object_name}")

    # Input sources - include all store paths the link step needs
    input_srcs = []
    if coreutils_path:
        input_srcs.append(coreutils_path)

    # Extract store path from compiler (e.g., /nix/store/xxx-clang/bin/clang++ -> /nix/store/xxx-clang)
    if compiler:
        # The compiler path is like /nix/store/hash-name/bin/clang++
        # We need to extract /nix/store/hash-name
        parts = compiler.split("/")
        if len(parts) >= 4 and parts[1] == "nix" and parts[2] == "store":
            compiler_store_path = "/".join(parts[:4])
            input_srcs.append(compiler_store_path)

    # Also add ar and ranlib store paths if used
    if ar and ar.startswith("/nix/store/"):
        parts = ar.split("/")
        if len(parts) >= 4:
            input_srcs.append("/".join(parts[:4]))

    if ranlib and ranlib.startswith("/nix/store/"):
        parts = ranlib.split("/")
        if len(parts) >= 4:
            input_srcs.append("/".join(parts[:4]))

    # Add linker runtime inputs (e.g., lld package)
    for linker_input in linker_inputs:
        if linker_input.startswith("/nix/store/"):
            input_srcs.append(linker_input)

    # Build the link command based on output type
    objects_expr = " ".join(object_paths)
    link_flags_str = " ".join(link_flags) if isinstance(link_flags, list) else link_flags
    driver_flags_str = " ".join(driver_flags) if isinstance(driver_flags, list) else driver_flags
    linker_flag = f"{linker_driver_flag} " if linker_driver_flag else ""

    # Extract compiler bin directory for PATH
    compiler_bin_dir = os.path.dirname(compiler) if compiler else ""
    # Add linker bin directories to PATH (for lld, etc.)
    linker_bin_dirs = ":".join(f"{p}/bin" for p in linker_inputs if p)
    path_dirs = ":".join(filter(None, [compiler_bin_dir, linker_bin_dirs, f"{coreutils_path}/bin"]))

    if output_type == "executable":
        builder_script = f"""
export PATH="{path_dirs}:$PATH"
set -eo pipefail
unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET
mkdir -p "$out/bin"
{compiler} {linker_flag}{driver_flags_str} {objects_expr} {link_flags_str} -o "$out/bin/{name}"
"""
    elif output_type == "sharedLibrary":
        lib_name = f"lib{name}.so"
        builder_script = f"""
export PATH="{path_dirs}:$PATH"
set -eo pipefail
unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET
mkdir -p "$out/lib"
{compiler} -shared {linker_flag}{driver_flags_str} {objects_expr} {link_flags_str} -o "$out/lib/{lib_name}"
"""
    elif output_type == "staticArchive":
        lib_name = f"lib{name}.a"
        ranlib_cmd = f'{ranlib} "$out/lib/{lib_name}"' if ranlib else ""
        ar_bin_dir = os.path.dirname(ar) if ar else ""
        ar_path_dirs = ":".join(filter(None, [ar_bin_dir, f"{coreutils_path}/bin"]))
        builder_script = f"""
export PATH="{ar_path_dirs}:$PATH"
set -eo pipefail
mkdir -p "$out/lib"
{ar} rcs "$out/lib/{lib_name}" {objects_expr}
{ranlib_cmd}
"""
    else:
        raise ValueError(f"Unknown output type: {output_type}")

    # Use CA derivations with the standard placeholder for 'out'
    # For CA derivations, Nix substitutes sha256("nix-output:out") at build time
    standard_placeholder = compute_standard_placeholder("out")

    drv = {
        "name": f"link-{name}",
        "system": system,
        "builder": bash_path,
        "args": ["-c", builder_script.strip()],
        "env": {
            "name": f"link-{name}",
            "out": standard_placeholder,
        },
        "inputDrvs": input_drvs,
        "inputSrcs": sorted(set(input_srcs)),  # Full store paths
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
        description="Generate a link derivation JSON"
    )
    parser.add_argument("--name", required=True, help="Target name")
    parser.add_argument("--output-type", required=True,
                        choices=["executable", "sharedLibrary", "staticArchive"],
                        help="Output type")
    parser.add_argument("--compile-drvs", required=True,
                        help="JSON file with compilation derivation info")
    parser.add_argument("--link-config", required=True,
                        help="JSON file with link configuration")
    parser.add_argument("--system", required=True,
                        help="System (e.g., x86_64-linux)")
    parser.add_argument("--output", required=True, help="Output JSON file path")

    args = parser.parse_args()

    # Load compile derivations info
    with open(args.compile_drvs, "r") as f:
        compile_drvs = json.load(f)

    # Load link configuration
    with open(args.link_config, "r") as f:
        link_config = json.load(f)

    drv = generate_link_derivation(
        name=args.name,
        output_type=args.output_type,
        compile_drvs=compile_drvs,
        link_config=link_config,
        system=args.system,
    )

    with open(args.output, "w") as f:
        json.dump(drv, f, indent=2)

    print(f"Generated: {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
