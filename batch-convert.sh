#!/usr/bin/env bash
# batch-convert.sh — Convert all .onepkg files (or a directory of .one files)
# to HTML using the Joplin WASM OneNote converter.
#
# Usage:
#   ./batch-convert.sh <input_dir_or_file> <output_dir>
#
# Examples:
#   ./batch-convert.sh ~/Notes/OneNote/    ./output/
#   ./batch-convert.sh ~/Notes/Work.onepkg ./output/work/
#
# Each .onepkg is extracted with cabextract, then each .one section inside is
# converted individually. Each .one that is directly passed is converted as-is.
# Converted HTML ends up in:  <output_dir>/<section_name>/
# (the converter creates the section folder automatically)
#
# Requirements: node, cabextract
# Run ./extract-wasm.sh first to populate pkg/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input_dir_or_file> <output_dir>"
    exit 1
fi

INPUT="$(realpath "$1")"
OUTPUT="$(realpath "$2")"

# ── Checks ──────────────────────────────────────────────────────────────────
if [[ ! -f "$SCRIPT_DIR/pkg/renderer.js" ]]; then
    echo "ERROR: pkg/renderer.js not found. Run ./extract-wasm.sh first."
    exit 1
fi

if ! command -v cabextract &>/dev/null; then
    echo "ERROR: cabextract is required. Install with:  sudo apt install cabextract"
    exit 1
fi

# ── Helper: convert a single .one file ─────────────────────────────────────
convert_one() {
    local one_file="$1"
    local section_name
    section_name="$(basename "$one_file" .one)"
    mkdir -p "$OUTPUT"
    echo "  Converting [$section_name] → $OUTPUT/"
    node "$SCRIPT_DIR/convert.js" "$one_file" "$OUTPUT" 2>&1 | \
        grep -E '(ERROR|Warning|Done\.|MISSING PAGE|FAILED PAGE|BROKEN ASSETS)' | \
        sed 's/^/    /' || true
    [[ -f "$OUTPUT/Errors.html" ]] && mv "$OUTPUT/Errors.html" "$OUTPUT/${section_name}-Errors.html"
}

# ── Helper: convert a .onepkg (CAB archive containing .one files) ───────────
convert_onepkg() {
    local onepkg="$1"
    local notebook_name
    notebook_name="$(basename "$onepkg" .onepkg)"
    local extract_dir="$OUTPUT/.extracted/$notebook_name"

    echo ""
    echo "=== Notebook: $notebook_name ==="

    # Show contents
    echo "  Sections in archive:"
    cabextract -l "$onepkg" 2>/dev/null | grep '\.one$' | awk '{print "    " $NF}' || true

    # Extract all .one files flat into extract_dir
    mkdir -p "$extract_dir"
    cabextract -q -d "$extract_dir" "$onepkg" 2>/dev/null || {
        echo "  WARNING: cabextract reported errors (some files may be truncated)"
    }

    # Convert each .one — converter creates <output_dir>/<section_name>/ automatically
    local count=0
    local errors=0
    while IFS= read -r -d '' one_file; do
        local section_name
        section_name="$(basename "$one_file" .one)"
        echo "  Converting [$section_name] → $OUTPUT/"
        node "$SCRIPT_DIR/convert.js" "$one_file" "$OUTPUT" 2>&1 | \
            grep -E '(ERROR|Converter ERROR|MISSING PAGE|FAILED PAGE|BROKEN ASSETS)' | sed 's/^/    /' || true
        [[ -f "$OUTPUT/Errors.html" ]] && mv "$OUTPUT/Errors.html" "$OUTPUT/${section_name}-Errors.html"
        ((count++)) || true
    done < <(find "$extract_dir" -name "*.one" -print0)

    echo "  Done: $count section(s) converted, $errors error(s)"
}

# ── Main ────────────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT"

if [[ -f "$INPUT" ]]; then
    # Single file
    case "${INPUT,,}" in
        *.onepkg) convert_onepkg "$INPUT" ;;
        *.one)    convert_one    "$INPUT" ;;
        *) echo "ERROR: Unknown file type: $INPUT"; exit 1 ;;
    esac
elif [[ -d "$INPUT" ]]; then
    # Directory — process all .onepkg and .one files found
    echo "Scanning $INPUT ..."
    found=0

    while IFS= read -r -d '' pkg; do
        convert_onepkg "$pkg"
        ((found++)) || true
    done < <(find "$INPUT" -maxdepth 1 -iname "*.onepkg" -print0 | sort -z)

    while IFS= read -r -d '' one; do
        convert_one "$one"
        ((found++)) || true
    done < <(find "$INPUT" -maxdepth 1 -iname "*.one" -print0 | sort -z)

    if [[ $found -eq 0 ]]; then
        echo "No .onepkg or .one files found in $INPUT"
        exit 1
    fi
else
    echo "ERROR: Input not found: $INPUT"
    exit 1
fi

echo ""
echo "All done. Output in: $OUTPUT"
echo ""
node "$SCRIPT_DIR/generate-summary.js" "$OUTPUT"
