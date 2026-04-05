#!/usr/bin/env bash
# build.sh — Build the onenote-converter WASM package from src/
#
# Uses a local sandbox (.rustup/ + .cargo/ inside the repo dir) so it never
# touches system Rust or any global installation.
# First run bootstraps rustup + wasm-pack automatically.
#
# Usage:
#   ./build.sh              # release build → pkg/
#   ./build.sh --dev        # dev build (faster, larger output)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
PKG_DIR="$SCRIPT_DIR/pkg"

export RUSTUP_HOME="$SCRIPT_DIR/.rustup"
export CARGO_HOME="$SCRIPT_DIR/.cargo"
export PATH="$CARGO_HOME/bin:$PATH"

PROFILE="--release"
[[ "${1:-}" == "--dev" ]] && PROFILE="--dev"

# ── 1. Check src/ ───────────────────────────────────────────────────────────
if [[ ! -d "$SRC_DIR/renderer" ]]; then
    echo "ERROR: src/renderer not found. Run ./upstream-sync.sh first."
    exit 1
fi

# ── 2. Bootstrap Rust if not present ────────────────────────────────────────
if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
    echo "Rust not found in sandbox — installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | RUSTUP_HOME="$RUSTUP_HOME" CARGO_HOME="$CARGO_HOME" \
          sh -s -- -y --no-modify-path --profile minimal
    echo "Adding wasm32 target..."
    rustup target add wasm32-unknown-unknown
fi

# ── 3. Bootstrap wasm-pack if not present ───────────────────────────────────
if [[ ! -x "$CARGO_HOME/bin/wasm-pack" ]]; then
    echo "wasm-pack not found in sandbox — installing..."
    curl --proto '=https' --tlsv1.2 -sSf https://rustwasm.github.io/wasm-pack/installer/init.sh \
        | CARGO_HOME="$CARGO_HOME" sh
fi

# ── 4. Build ─────────────────────────────────────────────────────────────────
echo "Building onenote-converter WASM ($PROFILE)..."
wasm-pack build $PROFILE --target nodejs --out-dir "$PKG_DIR" "$SRC_DIR/renderer"

echo ""
echo "Done. Output in pkg/:"
ls "$PKG_DIR/"
