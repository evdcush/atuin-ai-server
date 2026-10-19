#!/usr/bin/env bash
# patch-atuin-ai-indent_c5f85ed664c8d825b1c3241431a9ff9ec9a25177.sh
# Builds the atuin client from the EXACT main-branch HEAD commit at the time
# this script was written:
#   c5f85ed664c8d825b1c3241431a9ff9ec9a25177  (atuin 18.24.1, Oct 2026)
# with one change:
#   crates/atuin-ai/src/tui/view/mod.rs : .pad_left(2) -> .pad_left(0)
# Removes the 2-column left indent on Atuin AI messages so copied text is clean.
#
# Intended for use after upgrading the installed client to a version near
# this commit. Refuses to touch your installed binary without confirmation.
#
# NOTE: if you have since upgraded to a much newer client, re-derive the patch
# for that version instead — see patch-atuin-ai-indent.sh (resolves your
# installed commit automatically).
set -euo pipefail

COMMIT="c5f85ed664c8d825b1c3241431a9ff9ec9a25177"

# --- Clone at that exact commit ------------------------------------------------
WORKDIR="$(mktemp -d /tmp/atuin-ai-indent.XXXXXX)"
echo "[1/4] Cloning atuin @ $COMMIT"
git init -q "$WORKDIR/repo"
git -C "$WORKDIR/repo" remote add origin https://github.com/atuinsh/atuin
git -C "$WORKDIR/repo" fetch -q --depth 1 origin "$COMMIT"
git -C "$WORKDIR/repo" checkout -q FETCH_HEAD
echo "      Checked out $(git -C "$WORKDIR/repo" rev-parse --short HEAD)"

FILE="$WORKDIR/repo/crates/atuin-ai/src/tui/view/mod.rs"
if ! grep -qF '.pad_left(2)' "$FILE"; then
  echo "ERROR: '.pad_left(2)' not found in $FILE — layout changed, aborting."
  echo "Source kept at $WORKDIR/repo for inspection."
  exit 1
fi

echo "[2/4] Patching $FILE  (sed: .pad_left(2) -> .pad_left(0))"
sed -i 's/\.pad_left(2)/.pad_left(0)/g' "$FILE"
echo "      Full diff of the change:"
git -C "$WORKDIR/repo" diff -- "crates/atuin-ai/src/tui/view/mod.rs"

read -r -p "Proceed to build and replace your installed atuin binary? [y/N] " ans
if ! [[ "$ans" =~ ^[Yy]$ ]]; then
  echo "Aborted. Source kept at $WORKDIR/repo (safe to delete)."
  exit 0
fi

echo "[3/4] cargo build --release --bin atuin (takes several minutes)..."
cargo build --manifest-path "$WORKDIR/repo/Cargo.toml" --release --bin atuin

BIN="$(command -v atuin || true)"
BUILT="$WORKDIR/repo/target/release/atuin"
if [[ -z "$BIN" ]]; then
  echo "No existing atuin on PATH; built binary is at: $BUILT"
  exit 0
fi

BACKUP="$BIN.atuin-backup.$(date +%Y%m%d%H%M%S)"
echo "[4/4] Replacing $BIN (backup saved to $BACKUP)"
cp "$BIN" "$BACKUP"
if ! install -m 0755 "$BUILT" "$BIN" 2>/dev/null; then
  echo "ERROR: could not write to $BIN (permissions?)."
  echo "Built binary is at: $BUILT — copy it somewhere on PATH manually."
  exit 1
fi
echo "Done. Verify with: atuin --version"
echo "Roll back with: cp '$BACKUP' '$BIN'"
