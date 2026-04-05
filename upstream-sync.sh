#!/usr/bin/env bash
# upstream-sync.sh — Sync Joplin's onenote-converter Rust source into src/
#
# Workflow:
#   main branch        — clean upstream Joplin source (updated by this script)
#   onenote-converter  — our patches on top of main
#
# Usage:
#   ./upstream-sync.sh [joplin-tag]       # e.g. ./upstream-sync.sh v3.5.13
#   ./upstream-sync.sh                    # uses latest tag from GitHub
#
# After this script completes on main, switch to your patch branch and:
#   git merge main          — merge upstream changes in
#   git cherry-pick <sha>   — or cherry-pick individual commits
#   git diff main..HEAD     — or use diff/patch to reapply changes

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

# ── 2. Ensure we are on main ────────────────────────────────────────────────
CURRENT_BRANCH="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "ERROR: Must be on 'main' branch to run this script (currently on '$CURRENT_BRANCH')."
    echo "Switch: git checkout main"
    exit 1
fi

# ── 3. Sparse-clone Joplin into a temp dir ──────────────────────────────────
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Sparse-cloning Joplin $TAG (onenote-converter only)..."
git clone \
    --filter=blob:none \
    --no-checkout \
    --sparse \
    --branch "$TAG" \
    --depth 1 \
    "$JOPLIN_REPO" \
    "$TMPDIR/joplin" 2>&1

pushd "$TMPDIR/joplin" > /dev/null
git sparse-checkout set "$JOPLIN_PKG"
git checkout
popd > /dev/null

UPSTREAM_PKG="$TMPDIR/joplin/$JOPLIN_PKG"
if [[ ! -d "$UPSTREAM_PKG" ]]; then
    echo "ERROR: $JOPLIN_PKG not found in Joplin $TAG"
    exit 1
fi

# ── 4. Copy Rust crates into src/ ───────────────────────────────────────────
echo "Copying Rust source into src/..."
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

for d in parser parser-macros parser-utils renderer; do
    if [[ -d "$UPSTREAM_PKG/$d" ]]; then
        cp -r "$UPSTREAM_PKG/$d" "$SRC_DIR/$d"
    fi
done

# Workspace-level Cargo files
for f in Cargo.toml Cargo.lock; do
    if [[ -f "$UPSTREAM_PKG/$f" ]]; then
        cp "$UPSTREAM_PKG/$f" "$SRC_DIR/$f"
    fi
done

# ── 5. Record the upstream version ──────────────────────────────────────────
echo "$TAG" > "$SRC_DIR/.joplin-version"

# ── 6. Stage and show summary ───────────────────────────────────────────────
git -C "$SCRIPT_DIR" add src/

echo ""
echo "── Upstream sync complete ─────────────────────────────────────────────"
echo "  Joplin version : $TAG"
echo "  Source dir     : src/"
echo ""
echo "Staged changes (src/):"
git -C "$SCRIPT_DIR" diff --stat --cached | head -30

echo ""
echo "Review the changes above, then commit and update your patch branch:"
echo "  git commit -m \"chore: sync upstream Joplin $TAG\""
echo "  git checkout onenote-converter"
echo "  git merge main    # or: git rebase main"
