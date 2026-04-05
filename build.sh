#!/usr/bin/env bash
# build.sh — Build the onenote-converter WASM package from src/
#
# Requires: wasm-pack (https://rustwasm.github.io/wasm-pack/)
#           Rust + wasm32-unknown-unknown target
#
# Usage:
#   ./build.sh              # release build → pkg/
#   ./build.sh --dev        # dev build (faster, larger output)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
PKG_DIR="$SCRIPT_DIR/pkg"
PROFILE="--release"

if [[ "${1:-}" == "--dev" ]]; then
    PROFILE="--dev"
fi

if [[ ! -d "$SRC_DIR/renderer" ]]; then
    echo "ERROR: src/renderer not found. Run ./upstream-sync.sh first."
    exit 1
fi

if ! command -v wasm-pack &>/dev/null; then
    echo "ERROR: wasm-pack not found. Install from https://rustwasm.github.io/wasm-pack/"
    exit 1
fi

echo "Building onenote-converter WASM ($PROFILE)..."
wasm-pack build $PROFILE --target nodejs --out-dir "$PKG_DIR" "$SRC_DIR/renderer"

echo ""
echo "Done. Output in pkg/:"
ls "$PKG_DIR/"
