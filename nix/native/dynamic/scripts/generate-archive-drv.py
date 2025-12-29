#!/usr/bin/env python3
"""Generate a static archive derivation in Nix JSON format.

This script creates a JSON representation of a Nix derivation that
creates a static archive (.a) from object files using ar/ranlib.
"""

import argparse
import json
import os
import sys
import hashlib


def nixbase32_encode(data: bytes) -> str:
    """Encode bytes to Nix's base32 format."""
    alphabet = "0123456789abcdfghijklmnpqrsvwxyz"
    num = int.from_bytes(data, byteorder='little')
    result = []
    for _ in range(52):
        result.append(alphabet[num % 32])
        num //= 32
    return ''.join(reversed(result))


def nixbase32_encode_20(data: bytes) -> str:
    """Encode 20 bytes to Nix's base32 format."""
    alphabet = "0123456789abcdfghijklmnpqrsvwxyz"
    num = int.from_bytes(data, byteorder='little')
    result = []
    for _ in range(32):
        result.append(alphabet[num % 32])
        num //= 32
    return ''.join(reversed(result))


def nixbase32_decode(encoded: str) -> bytes:
    """Decode a Nix base32 string back to bytes."""
    alphabet = "0123456789abcdfghijklmnpqrsvwxyz"
    num = 0
    for c in encoded:
        num = num * 32 + alphabet.index(c)
    return num.to_bytes(32, byteorder='little')


def compress_hash(hash_bytes: bytes, new_size: int) -> bytes:
    """Compress a hash by XORing bytes."""
    if len(hash_bytes) == 0:
        return b''
    result = bytearray(new_size)
    for i, byte in enumerate(hash_bytes):
        result[i % new_size] ^= byte
    return bytes(result)


def compute_standard_placeholder(output_name: str) -> str:
    """Compute the standard placeholder for an output."""
    clear_text = f"nix-output:{output_name}"
    digest = hashlib.sha256(clear_text.encode()).digest()
    return "/" + nixbase32_encode(digest)


def output_path_name(drv_name: str, output_name: str) -> str:
    """Format an output path name according to Nix conventions."""
    if output_name == "out":
        return drv_name
    else:
        return f"{drv_name}-{output_name}"


def compute_placeholder(drv_path: str, output_name: str) -> str:
    """Compute the nix-upstream-output placeholder for a CA derivation output."""
    basename = os.path.basename(drv_path)
    if basename.endswith('.drv'):
        basename = basename[:-4]
    parts = basename.split('-', 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid drv path: {drv_path}")
    hash_part = parts[0]
    drv_name = parts[1]
    path_name = output_path_name(drv_name, output_name)
    clear_text = f"nix-upstream-output:{hash_part}:{path_name}"
    digest = hashlib.sha256(clear_text.encode()).digest()
    return "/" + nixbase32_encode(digest)


def compute_dynamic_placeholder(upstream_placeholder: str, output_name: str) -> str:
    """Compute the nix-computed-output placeholder for a dynamic derivation output."""
    if upstream_placeholder.startswith('/'):
        upstream_placeholder = upstream_placeholder[1:]
    hash_bytes = nixbase32_decode(upstream_placeholder)
    compressed = compress_hash(hash_bytes, 20)
    compressed_str = nixbase32_encode_20(compressed)
    clear_text = f"nix-computed-output:{compressed_str}:{output_name}"
    digest = hashlib.sha256(clear_text.encode()).digest()
    return "/" + nixbase32_encode(digest)


def generate_archive_derivation(
    name: str,
    wrapper_info: list,
    archive_config: dict,
    system: str,
) -> dict:
    """Generate an archive derivation JSON."""

    bash_path = archive_config.get("bashPath", "/bin/sh")
    coreutils_path = archive_config.get("coreutilsPath", "")
    ar = archive_config.get("ar", "ar")
    ranlib = archive_config.get("ranlib", "ranlib")

    # Build inputDrvs with dynamicOutputs
    input_drvs = {}
    object_paths = []

    for wrapper in wrapper_info:
        wrapper_drv = wrapper["wrapper_drv"]
        object_name = wrapper["object_name"]

        # Add wrapper to inputDrvs with dynamicOutputs
        input_drvs[wrapper_drv] = {
            "outputs": [],
            "dynamicOutputs": {
                "out": {
                    "dynamicOutputs": {},
                    "outputs": ["out"]
                }
            }
        }

        # Compute placeholder for the compile derivation's output
        wrapper_out_placeholder = compute_placeholder(wrapper_drv, "out")
        compile_out_placeholder = compute_dynamic_placeholder(wrapper_out_placeholder, "out")
        object_paths.append(f"{compile_out_placeholder}/{object_name}")

    # Input sources
    input_srcs = []
    if coreutils_path:
        input_srcs.append(coreutils_path)

    # Extract store paths from ar and ranlib
    for tool in [ar, ranlib]:
        if tool and tool.startswith("/nix/store/"):
            parts = tool.split("/")
            if len(parts) >= 4:
                input_srcs.append("/".join(parts[:4]))

    # Build archive script
    archive_name = f"lib{name}.a"
    objects_expr = " ".join(object_paths)

    ar_bin_dir = os.path.dirname(ar) if ar else ""
    ranlib_cmd = f'{ranlib} "$out/lib/{archive_name}"' if ranlib else ""
    path_dirs = ":".join(filter(None, [ar_bin_dir, f"{coreutils_path}/bin"]))

    builder_script = f"""
export PATH="{path_dirs}:$PATH"
set -eo pipefail
mkdir -p "$out/lib"
{ar} rcs "$out/lib/{archive_name}" {objects_expr}
{ranlib_cmd}
"""

    # Standard placeholder for CA derivations
    standard_placeholder = compute_standard_placeholder("out")

    drv = {
        "name": f"archive-{name}.drv",
        "system": system,
        "builder": bash_path,
        "args": ["-c", builder_script.strip()],
        "env": {
            "name": f"archive-{name}.drv",
            "out": standard_placeholder,
        },
        "inputDrvs": input_drvs,
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
    parser = argparse.ArgumentParser(description="Generate an archive derivation JSON")
    parser.add_argument("--name", required=True, help="Archive name")
    parser.add_argument("--wrapper-info", required=True, help="JSON file with wrapper info")
    parser.add_argument("--archive-config", required=True, help="JSON file with archive config")
    parser.add_argument("--system", required=True, help="System (e.g., x86_64-linux)")
    parser.add_argument("--output", required=True, help="Output JSON file path")

    args = parser.parse_args()

    with open(args.wrapper_info, "r") as f:
        wrapper_info = json.load(f)

    with open(args.archive_config, "r") as f:
        archive_config = json.load(f)

    drv = generate_archive_derivation(
        name=args.name,
        wrapper_info=wrapper_info,
        archive_config=archive_config,
        system=args.system,
    )

    with open(args.output, "w") as f:
        json.dump(drv, f, indent=2)

    print(f"Generated: {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
