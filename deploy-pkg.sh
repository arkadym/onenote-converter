#!/usr/bin/env bash
# deploy-pkg.sh — Copy freshly built WASM pkg into the converter toolkit and smoke-test.
#
# Usage:
#   ./deploy-pkg.sh [<pkg_source_dir>]
#
# Default source: ../onenote-converter-dev/pkg
# (i.e. the sandbox built with wasm-pack next to this toolkit)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$SCRIPT_DIR/../onenote-converter-dev/pkg}"
DST="$SCRIPT_DIR/pkg"

SRC="$(realpath "$SRC")"

if [[ ! -f "$SRC/renderer.js" || ! -f "$SRC/renderer_bg.wasm" ]]; then
    echo "ERROR: $SRC does not look like a wasm-pack output (missing renderer.js / renderer_bg.wasm)"
    echo "  Build first:  cd onenote-converter-dev/joplin/packages/onenote-converter/renderer"
    echo "                wasm-pack build --target nodejs --out-dir \$SANDBOX/pkg"
    exit 1
fi

echo "Source : $SRC"
echo "Dest   : $DST"

# Back up current pkg
BACKUP="$SCRIPT_DIR/pkg.bak"
if [[ -d "$DST" ]]; then
    rm -rf "$BACKUP"
    cp -r "$DST" "$BACKUP"
    echo "Backup : $BACKUP"
fi

# Copy
rm -rf "$DST"
cp -r "$SRC" "$DST"
echo "Copied."

# Smoke-test: find any small .one file we can use
TEST_ONE=""
for candidate in \
    "$SCRIPT_DIR/output/.extracted"/*/НН.one \
    "$SCRIPT_DIR/output/.extracted"/*/Видео.one \
    "$SCRIPT_DIR/output/.extracted"/*/*.one; do
    if [[ -f "$candidate" ]]; then
        TEST_ONE="$candidate"
        break
    fi
done

if [[ -z "$TEST_ONE" ]]; then
    echo "WARNING: No .one file found for smoke test — skipping."
    echo "Done."
    exit 0
fi

echo "Smoke-testing with: $(basename "$TEST_ONE")"
OUT=$(mktemp -d)
if node "$SCRIPT_DIR/convert.js" "$TEST_ONE" "$OUT" 2>&1 | grep -E '(Done\.|ERROR|FAILED PAGE)' | sed 's/^/  /'; then
    :
fi
rm -rf "$OUT"

echo ""
echo "Done. New pkg active."
