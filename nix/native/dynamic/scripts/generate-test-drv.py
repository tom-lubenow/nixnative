#!/usr/bin/env python3
"""Generate a test derivation in Nix JSON format.

This script creates a JSON representation of a Nix derivation that
runs an executable and verifies its output.
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


def generate_test_derivation(
    name: str,
    link_wrapper_drv: str,
    exec_name: str,
    test_config: dict,
    system: str,
) -> dict:
    """Generate a test derivation JSON."""

    bash_path = test_config.get("bashPath", "/bin/sh")
    coreutils_path = test_config.get("coreutilsPath", "")
    gcc_lib_path = test_config.get("gccLibPath", "")
    args = test_config.get("args", [])
    expected_output = test_config.get("expectedOutput", None)
    stdin_path = test_config.get("stdinPath", None)

    # Build inputDrvs with dynamicOutputs for the link wrapper
    # We need TWO levels:
    # 1. link_wrapper^out = the link.drv file
    # 2. link_wrapper^out^out = the actual executable
    input_drvs = {
        link_wrapper_drv: {
            "outputs": [],
            "dynamicOutputs": {
                "out": {
                    "dynamicOutputs": {},
                    "outputs": ["out"]
                }
            }
        }
    }

    # Compute placeholders for the executable
    wrapper_out_placeholder = compute_placeholder(link_wrapper_drv, "out")
    exec_placeholder = compute_dynamic_placeholder(wrapper_out_placeholder, "out")
    exec_path = f"{exec_placeholder}/bin/{exec_name}"

    # Input sources
    input_srcs = []
    if coreutils_path:
        input_srcs.append(coreutils_path)
    if gcc_lib_path:
        input_srcs.append(gcc_lib_path)
    if stdin_path:
        input_srcs.append(stdin_path)

    # Build test script
    args_str = " ".join(f'"{arg}"' for arg in args)

    stdin_cmd = ""
    if stdin_path:
        stdin_cmd = f'cat "{stdin_path}" | '

    expected_check = ""
    if expected_output:
        # Escape for shell
        escaped = expected_output.replace("'", "'\\''")
        expected_check = f'''
expected='{escaped}'
if ! grep -qF "$expected" output.log; then
  echo "Test failed: Expected output not found."
  echo "Expected: $expected"
  echo "Got:"
  cat output.log
  exit 1
fi
'''

    builder_script = f"""
export PATH="{coreutils_path}/bin:$PATH"
export LD_LIBRARY_PATH="{gcc_lib_path}/lib:$LD_LIBRARY_PATH"
set -eo pipefail
mkdir -p "$out"

echo "Running test: {exec_path}"
{stdin_cmd}"{exec_path}" {args_str} > output.log 2>&1 || {{
  echo "Test failed with exit code $?"
  cat output.log
  exit 1
}}

cat output.log
{expected_check}
cp output.log "$out/test.log"
echo "Test passed!" > "$out/result"
"""

    # Standard placeholder for CA derivations
    standard_placeholder = compute_standard_placeholder("out")

    drv = {
        "name": f"test-{name}.drv",
        "system": system,
        "builder": bash_path,
        "args": ["-c", builder_script.strip()],
        "env": {
            "name": f"test-{name}.drv",
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
    parser = argparse.ArgumentParser(description="Generate a test derivation JSON")
    parser.add_argument("--name", required=True, help="Test name")
    parser.add_argument("--link-wrapper-drv", required=True, help="Link wrapper derivation path")
    parser.add_argument("--exec-name", required=True, help="Executable name")
    parser.add_argument("--test-config", required=True, help="JSON file with test config")
    parser.add_argument("--system", required=True, help="System (e.g., x86_64-linux)")
    parser.add_argument("--output", required=True, help="Output JSON file path")

    args = parser.parse_args()

    with open(args.test_config, "r") as f:
        test_config = json.load(f)

    drv = generate_test_derivation(
        name=args.name,
        link_wrapper_drv=args.link_wrapper_drv,
        exec_name=args.exec_name,
        test_config=test_config,
        system=args.system,
    )

    with open(args.output, "w") as f:
        json.dump(drv, f, indent=2)

    print(f"Generated: {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
