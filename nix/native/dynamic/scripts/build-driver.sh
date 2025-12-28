#!/usr/bin/env bash
# Build driver script for nixnative dynamic derivations
#
# This script runs at build time and:
# 1. Scans each source file for header dependencies
# 2. Creates a minimal source tree for each compilation
# 3. Generates compilation derivation JSON
# 4. Uses `nix derivation add` to create .drv files
# 5. Generates a link derivation that depends on all compilation derivations
# 6. Outputs the link .drv file to $out (text mode output)
#
# Environment variables:
#   DRIVER_CONFIG - Path to JSON config file
#   WORK_DIR - Working directory with source tree
#   GENERATE_DRV_SCRIPT - Path to Python script for generating compile drv JSON
#   GENERATE_LINK_DRV_SCRIPT - Path to Python script for generating link drv JSON

set -euo pipefail

# Read configuration
config=$(cat "$DRIVER_CONFIG")

# Extract configuration values
name=$(echo "$config" | jq -r '.name')
output_type=$(echo "$config" | jq -r '.outputType')
system=$(echo "$config" | jq -r '.system')
cpp_compiler=$(echo "$config" | jq -r '.compilers.cpp')
c_compiler=$(echo "$config" | jq -r '.compilers.c')

# Build flags strings
include_flags=$(echo "$config" | jq -r '.includeDirs | join(" ")')
define_flags=$(echo "$config" | jq -r '.defines | join(" ")')
compile_flags=$(echo "$config" | jq -r '.compileFlags | join(" ")')

# Default flags per language
cpp_default_flags=$(echo "$config" | jq -r '.defaultFlags.cpp | join(" ")')
c_default_flags=$(echo "$config" | jq -r '.defaultFlags.c | join(" ")')

# Per-language raw flags
cpp_lang_flags=$(echo "$config" | jq -r '.langFlags.cpp | join(" ")')
c_lang_flags=$(echo "$config" | jq -r '.langFlags.c | join(" ")')

# Link configuration
link_config=$(echo "$config" | jq '.linkConfig')
linker_driver_flag=$(echo "$link_config" | jq -r '.linkerDriverFlag')

# Create working directories
mkdir -p "$TMPDIR/deps"
mkdir -p "$TMPDIR/drvs"
mkdir -p "$TMPDIR/trees"

# Function to get compiler for language
get_compiler() {
  local lang="$1"
  case "$lang" in
    cpp|c++) echo "$cpp_compiler" ;;
    c) echo "$c_compiler" ;;
    *) echo "$cpp_compiler" ;;  # Default to C++
  esac
}

# Function to get default flags for language
get_default_flags() {
  local lang="$1"
  case "$lang" in
    cpp|c++) echo "$cpp_default_flags" ;;
    c) echo "$c_default_flags" ;;
    *) echo "$cpp_default_flags" ;;
  esac
}

# Function to get per-language flags
get_lang_flags() {
  local lang="$1"
  case "$lang" in
    cpp|c++) echo "$cpp_lang_flags" ;;
    c) echo "$c_lang_flags" ;;
    *) echo "" ;;
  esac
}

# Function to scan a single source file
scan_source() {
  local rel="$1"
  local lang="$2"
  local depfile="$TMPDIR/deps/$(echo "$rel" | tr '/' '_').d"

  local compiler
  compiler=$(get_compiler "$lang")
  local default_flags
  default_flags=$(get_default_flags "$lang")

  # Run preprocessor to generate dependency file
  # Use -E for preprocessor only, -fdirectives-only for speed
  $compiler \
    -E -fdirectives-only \
    -MMD -MF "$depfile" \
    $default_flags \
    $compile_flags \
    $include_flags \
    $define_flags \
    "$WORK_DIR/$rel" \
    -o /dev/null 2>/dev/null || true

  echo "$depfile"
}

# Function to parse dependency file and extract relative headers
parse_deps() {
  local depfile="$1"
  local source_rel="$2"

  if [[ ! -f "$depfile" ]]; then
    # No deps file - just return the source
    echo "$source_rel"
    return
  fi

  # Parse .d file format: target: dep1 dep2 ...
  # Handle line continuations
  awk 'BEGIN { RS = "" }
  {
    # Remove line continuations
    gsub(/\\[[:space:]]*\n/, " ")
    # Extract deps after colon
    idx = index($0, ":")
    if (idx > 0) {
      deps = substr($0, idx + 1)
      n = split(deps, arr)
      for (i = 1; i <= n; i++) {
        dep = arr[i]
        # Skip empty, absolute paths
        if (dep != "" && substr(dep, 1, 1) != "/") {
          print dep
        }
      }
    }
  }' "$depfile" | sort -u
}

# Function to create source tree derivation
create_source_tree() {
  local source_rel="$1"
  local deps_file="$2"
  local tree_dir="$TMPDIR/trees/$(echo "$source_rel" | tr '/' '_')"

  mkdir -p "$tree_dir"

  # Copy source file
  mkdir -p "$tree_dir/$(dirname "$source_rel")"
  cp "$WORK_DIR/$source_rel" "$tree_dir/$source_rel"

  # Copy dependencies
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    if [[ -f "$WORK_DIR/$dep" ]]; then
      mkdir -p "$tree_dir/$(dirname "$dep")"
      cp "$WORK_DIR/$dep" "$tree_dir/$dep"
    fi
  done < "$deps_file"

  echo "$tree_dir"
}

# Array to track compilation derivations
compile_drvs_json="$TMPDIR/compile_drvs.json"
echo "[]" > "$compile_drvs_json"

# Process each source file
echo "Processing source files..."
echo "$config" | jq -c '.sources[]' | while read -r source_json; do
  rel=$(echo "$source_json" | jq -r '.rel')
  object_name=$(echo "$source_json" | jq -r '.objectName')
  lang=$(echo "$source_json" | jq -r '.lang')

  echo "Processing: $rel (lang=$lang)"

  # Scan for dependencies
  depfile=$(scan_source "$rel" "$lang")

  # Parse dependencies
  deps_list="$TMPDIR/deps/$(echo "$rel" | tr '/' '_').list"
  parse_deps "$depfile" "$rel" > "$deps_list"

  # Create source tree
  tree_dir=$(create_source_tree "$rel" "$deps_list")

  # Add source tree to nix store
  tree_store_path=$(nix store add-path "$tree_dir" --name "src-$(echo "$rel" | tr '/' '_')")

  # Get compiler and flags for this file
  compiler=$(get_compiler "$lang")
  default_flags=$(get_default_flags "$lang")
  lang_flags=$(get_lang_flags "$lang")

  # Generate compilation derivation JSON
  drv_json="$TMPDIR/drvs/compile-$(echo "$rel" | tr '/' '_').json"

  # Build argument list, only including non-empty flags
  args=(
    --source-rel "$rel"
    --object-name "$object_name"
    --source-tree "$tree_store_path"
    --compiler "$compiler"
    --system "$system"
    --output "$drv_json"
  )

  # Add optional flags using = syntax to avoid argparse issues with values starting with -
  if [[ -n "$default_flags" ]]; then
    args+=("--default-flags=$default_flags")
  fi
  if [[ -n "$compile_flags" ]]; then
    args+=("--compile-flags=$compile_flags")
  fi
  if [[ -n "$include_flags" ]]; then
    args+=("--include-flags=$include_flags")
  fi
  if [[ -n "$define_flags" ]]; then
    args+=("--define-flags=$define_flags")
  fi
  if [[ -n "$lang_flags" ]]; then
    args+=("--lang-flags=$lang_flags")
  fi
  if [[ -n "$linker_driver_flag" ]]; then
    args+=("--linker-flag=$linker_driver_flag")
  fi

  python3 "$GENERATE_DRV_SCRIPT" "${args[@]}"

  # Add derivation to store
  drv_path=$(nix derivation add < "$drv_json")
  echo "Created: $drv_path"

  # Add to compile_drvs array
  jq --arg drv "$drv_path" --arg obj "$object_name" \
    '. += [{"drv": $drv, "object": $obj}]' \
    "$compile_drvs_json" > "$compile_drvs_json.tmp"
  mv "$compile_drvs_json.tmp" "$compile_drvs_json"
done

echo "All compilation derivations created."

# Save link configuration
link_config_json="$TMPDIR/link_config.json"
echo "$config" | jq '.linkConfig + {cppCompiler: .compilers.cpp}' > "$link_config_json"

# Generate link derivation
echo "Generating link derivation..."
link_drv_json="$TMPDIR/link.json"

python3 "$GENERATE_LINK_DRV_SCRIPT" \
  --name "$name" \
  --output-type "$output_type" \
  --compile-drvs "$compile_drvs_json" \
  --link-config "$link_config_json" \
  --system "$system" \
  --output "$link_drv_json"

# Add link derivation to store
link_drv_path=$(nix derivation add < "$link_drv_json")
echo "Created link derivation: $link_drv_path"

# Output the link .drv file to $out
# Since we're in text output mode, $out is the path where we write the .drv content
# We copy the .drv file content to $out
cp "$link_drv_path" "$out"

echo "Driver complete. Output: $out"
