#!/usr/bin/env bash
# Compile wrapper script for nixnative dynamic derivations
#
# This script runs at build time for EACH source file and:
# 1. Scans the source for header dependencies
# 2. Creates a minimal source tree with only needed files
# 3. Generates a compilation derivation JSON
# 4. Uses `nix derivation add` to create a .drv file
# 5. Outputs the .drv file path to $out (text mode output)
#
# This allows Nix to build all compile wrappers in parallel!
#
# Environment variables (set by Nix):
#   SOURCE_REL       - Relative path of source file
#   OBJECT_NAME      - Output object file name
#   LANG             - Language (c, cpp)
#   COMPILER         - Full path to compiler
#   DEFAULT_FLAGS    - Default compiler flags for this language
#   COMPILE_FLAGS    - Additional compile flags
#   INCLUDE_FLAGS    - Include directory flags
#   DEFINE_FLAGS     - Preprocessor defines
#   LANG_FLAGS       - Per-language raw flags
#   LINKER_FLAG      - Linker driver flag (for consistency)
#   SYSTEM           - Target system
#   src              - Source root store path
#   GENERATE_DRV_SCRIPT - Path to Python script for generating drv JSON
#   NIX_BIN          - Path to nix binary
#   BASH_PATH        - Path to bash
#   COREUTILS_PATH   - Path to coreutils

set -euo pipefail

# Unset Nix wrapper environment variables
unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET

# Set up working directory
work="$TMPDIR/work"
mkdir -p "$work"
mkdir -p "$TMPDIR/deps"

# Copy source tree to work directory
cp -r "$src"/* "$work/" || true
chmod -R u+w "$work"

# Apply header overrides from tools
if [[ -n "${headerOverridesPath:-}" && -f "$headerOverridesPath" ]]; then
  # Read with || true to handle files without trailing newlines
  while IFS='=' read -r rel target || [[ -n "$rel" ]]; do
    [[ -z "$rel" ]] && continue
    mkdir -p "$work/$(dirname "$rel")"
    cp "$target" "$work/$rel"
  done < "$headerOverridesPath"
fi

# Apply source overrides from tools
if [[ -n "${sourceOverridesPath:-}" && -f "$sourceOverridesPath" ]]; then
  # Read with || true to handle files without trailing newlines
  while IFS='=' read -r rel target || [[ -n "$rel" ]]; do
    [[ -z "$rel" ]] && continue
    mkdir -p "$work/$(dirname "$rel")"
    cp "$target" "$work/$rel"
  done < "$sourceOverridesPath"
fi

cd "$work"

# Function to scan source file for dependencies
scan_source() {
  local rel="$1"
  local depfile="$TMPDIR/deps/$(echo "$rel" | tr '/' '_').d"

  # Run preprocessor to generate dependency file
  $COMPILER \
    -E -fdirectives-only \
    -MMD -MF "$depfile" \
    $DEFAULT_FLAGS \
    $COMPILE_FLAGS \
    $INCLUDE_FLAGS \
    $DEFINE_FLAGS \
    "$work/$rel" \
    -o /dev/null 2>/dev/null || true

  echo "$depfile"
}

# Function to parse dependency file and extract relative headers
parse_deps() {
  local depfile="$1"
  local source_rel="$2"

  if [[ ! -f "$depfile" ]]; then
    echo "$source_rel"
    return
  fi

  awk 'BEGIN { RS = "" }
  {
    gsub(/\\[[:space:]]*\n/, " ")
    idx = index($0, ":")
    if (idx > 0) {
      deps = substr($0, idx + 1)
      n = split(deps, arr)
      for (i = 1; i <= n; i++) {
        dep = arr[i]
        if (dep != "" && substr(dep, 1, 1) != "/") {
          print dep
        }
      }
    }
  }' "$depfile" | sort -u
}

# Function to create minimal source tree
create_source_tree() {
  local source_rel="$1"
  local deps_file="$2"
  local tree_dir="$TMPDIR/tree"

  mkdir -p "$tree_dir"

  # Copy source file
  mkdir -p "$tree_dir/$(dirname "$source_rel")"
  cp "$work/$source_rel" "$tree_dir/$source_rel"

  # Copy dependencies
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    if [[ -f "$work/$dep" ]]; then
      mkdir -p "$tree_dir/$(dirname "$dep")"
      cp "$work/$dep" "$tree_dir/$dep"
    fi
  done < "$deps_file"

  echo "$tree_dir"
}

echo "Scanning: $SOURCE_REL (lang=$LANG)"

# Scan for dependencies
depfile=$(scan_source "$SOURCE_REL")

# Parse dependencies
deps_list="$TMPDIR/deps/$(echo "$SOURCE_REL" | tr '/' '_').list"
parse_deps "$depfile" "$SOURCE_REL" > "$deps_list"

# Create minimal source tree
tree_dir=$(create_source_tree "$SOURCE_REL" "$deps_list")

# Add source tree to nix store
tree_store_path=$($NIX_BIN store add-path "$tree_dir" --name "src-$(echo "$SOURCE_REL" | tr '/' '_')")

# Generate compilation derivation JSON
drv_json="$TMPDIR/compile.json"

args=(
  --source-rel "$SOURCE_REL"
  --object-name "$OBJECT_NAME"
  --source-tree "$tree_store_path"
  --compiler "$COMPILER"
  --system "$SYSTEM"
  --bash-path "$BASH_PATH"
  --coreutils-path "$COREUTILS_PATH"
  --output "$drv_json"
)

# Add optional flags
if [[ -n "${DEFAULT_FLAGS:-}" ]]; then
  args+=("--default-flags=$DEFAULT_FLAGS")
fi
if [[ -n "${COMPILE_FLAGS:-}" ]]; then
  args+=("--compile-flags=$COMPILE_FLAGS")
fi
if [[ -n "${INCLUDE_FLAGS:-}" ]]; then
  args+=("--include-flags=$INCLUDE_FLAGS")
fi
if [[ -n "${DEFINE_FLAGS:-}" ]]; then
  args+=("--define-flags=$DEFINE_FLAGS")
fi
if [[ -n "${LANG_FLAGS:-}" ]]; then
  args+=("--lang-flags=$LANG_FLAGS")
fi
if [[ -n "${LINKER_FLAG:-}" ]]; then
  args+=("--linker-flag=$LINKER_FLAG")
fi

python3 "$GENERATE_DRV_SCRIPT" "${args[@]}"

# Create the derivation
drv_path=$($NIX_BIN derivation add < "$drv_json")

echo "Created: $drv_path"

# Output the .drv file to $out (text mode)
cp "$drv_path" "$out"

echo "Wrapper complete: $out"
