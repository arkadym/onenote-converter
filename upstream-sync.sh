#!/usr/bin/env bash
# upstream-sync.sh — Pull Joplin's onenote-converter Rust source into src/
#
# Clones the specified Joplin tag into a temp dir, copies the 4 Rust crates
# and Cargo workspace files into src/, then stages the result for review.
#
# Workflow:
#   1. Run on master branch:  ./upstream-sync.sh [joplin-tag]
#   2. Review diff, then:   git commit -m "chore: sync upstream Joplin vX.Y.Z"
#   3. Update patch branch: git checkout onenote-converter && git merge master
#
# Usage:
#   ./upstream-sync.sh v3.5.13    # specific tag
#   ./upstream-sync.sh            # latest release tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
JOPLIN_REPO="https://github.com/laurent22/joplin.git"
JOPLIN_PKG="packages/onenote-converter"

# ── 1. Determine target tag ─────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    TAG="$1"
else
    echo "Fetching latest Joplin release tag..."
    TAG="$(git ls-remote --tags --sort=-version:refname "$JOPLIN_REPO" 'refs/tags/v*' \
        | grep -v '\^{}' | head -1 | sed 's|.*refs/tags/||')"
    echo "Latest tag: $TAG"
fi

echo "Syncing Joplin $TAG → src/"

# ── 2. Sparse-clone Joplin into a temp dir ──────────────────────────────────
CLONE_TMP="$(mktemp -d)"
trap 'rm -rf "$CLONE_TMP"' EXIT

echo "Sparse-cloning Joplin $TAG (onenote-converter only)..."
git clone \
    --filter=blob:none \
    --no-checkout \
    --sparse \
    --branch "$TAG" \
    --depth 1 \
    "$JOPLIN_REPO" \
    "$CLONE_TMP/joplin" 2>&1

pushd "$CLONE_TMP/joplin" > /dev/null
git sparse-checkout set "$JOPLIN_PKG"
git checkout
popd > /dev/null

UPSTREAM_PKG="$CLONE_TMP/joplin/$JOPLIN_PKG"
if [[ ! -d "$UPSTREAM_PKG" ]]; then
    echo "ERROR: $JOPLIN_PKG not found in Joplin $TAG"
    exit 1
fi

# ── 3. Copy Rust crates and Cargo workspace files into src/ ─────────────────
echo "Copying Rust source into src/..."
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

for d in parser parser-macros parser-utils renderer; do
    [[ -d "$UPSTREAM_PKG/$d" ]] && cp -r "$UPSTREAM_PKG/$d" "$SRC_DIR/$d"
done

for f in Cargo.toml Cargo.lock; do
    [[ -f "$UPSTREAM_PKG/$f" ]] && cp "$UPSTREAM_PKG/$f" "$SRC_DIR/$f"
done

# Record which upstream version src/ was taken from
echo "$TAG" > "$SRC_DIR/.joplin-version"

# ── 4. Stage and show summary ───────────────────────────────────────────────
git -C "$SCRIPT_DIR" add src/

echo ""
echo "── Upstream sync complete ─────────────────────────────────────────────"
echo "  Joplin version : $TAG"
echo "  Source dir     : src/"
echo ""
echo "Staged changes:"
git -C "$SCRIPT_DIR" diff --stat --cached | head -40

echo ""
echo "Next steps:"
echo "  git commit -m \"chore: sync upstream Joplin $TAG\""
echo "  git checkout onenote-converter && git merge master"
