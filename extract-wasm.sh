#!/usr/bin/env bash
# extract-wasm.sh — Extract the OneNote converter WASM package from a Joplin AppImage.
#
# Usage:
#   ./extract-wasm.sh [/path/to/Joplin-X.Y.Z.appimage]
#
# If no path is given, the script looks for *.appimage in /opt/apps/AppImage/.
# Output: ./pkg/  (renderer.js, renderer_bg.wasm, snippets/)
#
# Requirements: npx (Node.js), file, bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$SCRIPT_DIR/pkg"

# ── 1. Find the AppImage ────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    APPIMAGE="$1"
else
    APPIMAGE="$(find /opt/apps/AppImage -maxdepth 1 -iname "joplin-*.appimage" 2>/dev/null | sort -V | tail -1)"
fi

if [[ -z "$APPIMAGE" || ! -f "$APPIMAGE" ]]; then
    echo "ERROR: Joplin AppImage not found. Pass path as argument or place in /opt/apps/AppImage/."
    exit 1
fi

echo "Using AppImage: $APPIMAGE"

# ── 2. Extract AppImage to a temp dir ──────────────────────────────────────
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Extracting asar from AppImage..."
# Selective extract is much faster than full --appimage-extract
pushd "$TMPDIR" > /dev/null
"$APPIMAGE" --appimage-extract 'resources/app.asar' > /dev/null 2>&1
popd > /dev/null

SQUASH="$TMPDIR/squashfs-root"
ASAR="$SQUASH/resources/app.asar"

if [[ ! -f "$ASAR" ]]; then
    echo "ERROR: app.asar not found at expected path: $ASAR"
    exit 1
fi

# ── 3. List the asar to find the renderer package ──────────────────────────
echo "Scanning asar for onenote-converter renderer package..."
RENDERER_ASAR_PATH="$(npx --yes asar list "$ASAR" 2>/dev/null | grep 'onenote-converter.*renderer_bg\.wasm' | head -1 | sed 's|/renderer_bg\.wasm||')"

if [[ -z "$RENDERER_ASAR_PATH" ]]; then
    echo "ERROR: Could not find onenote-converter renderer in asar."
    echo "The Joplin version may not include the onenote-converter."
    exit 1
fi

echo "Found renderer at: $RENDERER_ASAR_PATH"

# ── 4. Extract the renderer package from the asar ──────────────────────────
# npx asar extract-file is broken in asar v3 — use full extract instead.
ASAR_EXTRACT="$TMPDIR/asar_contents"
echo "Extracting asar contents..."
npx asar extract "$ASAR" "$ASAR_EXTRACT"

RENDERER_SRC="$ASAR_EXTRACT${RENDERER_ASAR_PATH}"
if [[ ! -d "$RENDERER_SRC" ]]; then
    echo "ERROR: Renderer directory not found after asar extract: $RENDERER_SRC"
    exit 1
fi

EXTRACT_TMP="$TMPDIR/extracted"
cp -r "$RENDERER_SRC" "$EXTRACT_TMP"

# ── 5. Fix stray leading bytes (asar boundary artifacts) ───────────────────
# renderer.js may start with a stray '}', renderer_bg.wasm with a stray '\n'
# node_functions.js may start with a stray 'e' (end of previous file)
echo "Fixing asar boundary artifacts..."

fix_js() {
    local file="$1"
    # If file starts with a single non-JS-start character before the real content
    local first
    first="$(head -c 1 "$file" | od -An -tx1 | tr -d ' ')"
    # Valid JS starts: '/', 'l', '"', '(', 'i', etc. — NOT '}' or random bytes
    # We check: if first char is '}', drop it
    if [[ "$first" == "7d" ]]; then
        echo "  Stripping leading '}' from $(basename "$file")"
        tail -c +2 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    elif python3 -c "
import sys
data = open('$file','rb').read(4)
# If it starts with a real JS keyword or comment, it's fine
if data[:2] in (b'le', b'co', b'//') or data[0:1] in (b'l',b'c',b'\"',b\"'\",b'(',b'i',b'f',b'e',b'r',b'n',b's',b'v',b'[',b'{',b'/',b'*'):
    sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
        # Unknown leading byte — just in case strip 1 byte
        echo "  Stripping unknown leading byte from $(basename "$file")"
        tail -c +2 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    fi
}

fix_wasm() {
    local file="$1"
    local magic
    magic="$(head -c 4 "$file" | od -An -tx1 | tr -d ' ')"
    if [[ "$magic" != "0061736d" ]]; then
        # WASM magic is \0asm. If it starts with 0a (newline), strip it.
        local first
        first="$(head -c 1 "$file" | od -An -tx1 | tr -d ' ')"
        if [[ "$first" == "0a" ]]; then
            echo "  Stripping leading newline byte from $(basename "$file")"
            tail -c +2 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        else
            echo "  WARNING: Unexpected WASM magic bytes: $magic"
        fi
    fi
}

[[ -f "$EXTRACT_TMP/renderer.js" ]]      && fix_js   "$EXTRACT_TMP/renderer.js"
[[ -f "$EXTRACT_TMP/renderer_bg.wasm" ]] && fix_wasm "$EXTRACT_TMP/renderer_bg.wasm"
for js in "$EXTRACT_TMP"/snippets/**/*.js "$EXTRACT_TMP"/snippets/*.js; do
    [[ -f "$js" ]] && fix_js "$js"
done

# ── 6. Verify ──────────────────────────────────────────────────────────────
WASM_MAGIC="$(head -c 4 "$EXTRACT_TMP/renderer_bg.wasm" | od -An -tx1 | tr -d ' ')"
if [[ "$WASM_MAGIC" != "0061736d" ]]; then
    echo "ERROR: renderer_bg.wasm has wrong magic: $WASM_MAGIC (expected 0061736d)"
    exit 1
fi

# ── 7. Install into pkg/ ───────────────────────────────────────────────────
rm -rf "$PKG_DIR"
cp -r "$EXTRACT_TMP" "$PKG_DIR"

echo ""
echo "Success! pkg/ is ready:"
find "$PKG_DIR" -type f | sort | sed "s|$SCRIPT_DIR/||"
