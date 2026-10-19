#!/usr/bin/env bash
# patch-atuin-ai-indent.sh
# Builds the atuin client from the EXACT commit your installed binary was built
# from, with one change:
#   crates/atuin-ai/src/tui/view/mod.rs : padding_left: Cells::from(2) -> Cells::from(0)
# Removes the 2-column left indent on Atuin AI messages so copied text is clean.
# Refuses to touch your installed binary without explicit confirmation.
#
# A companion script pinned to a specific newer commit (atuin 18.24.1,
# .pad_left(2) API) is kept as:
#   patch-atuin-ai-indent_c5f85ed664c8d825b1c3241431a9ff9ec9a25177.sh
set -euo pipefail

# --- Resolve the commit of the installed binary ------------------------------
VER_LINE="$(atuin --version 2>/dev/null || true)"
echo "Installed: $VER_LINE"
COMMIT="$(printf '%s\n' "$VER_LINE" | grep -oE '\([0-9a-f]{40}\)' | tr -d '()')"
VERSION="$(printf '%s\n' "$VER_LINE" | awk '{print $2}')"

if [[ -z "$COMMIT" ]]; then
  echo "No commit hash in 'atuin --version'; falling back to tag v$VERSION"
  REFSPEC="v$VERSION"
else
  REFSPEC="$COMMIT"
  echo "Will build from exact commit: $COMMIT"
fi

# --- Clone at that exact ref --------------------------------------------------
WORKDIR="$(mktemp -d /tmp/atuin-ai-indent.XXXXXX)"
echo "[1/4] Cloning atuin @ $REFSPEC..."
git init -q "$WORKDIR/repo"
git -C "$WORKDIR/repo" remote add origin https://github.com/atuinsh/atuin
git -C "$WORKDIR/repo" fetch -q --depth 1 origin "$REFSPEC"
git -C "$WORKDIR/repo" checkout -q FETCH_HEAD
echo "      Checked out $(git -C "$WORKDIR/repo" rev-parse --short HEAD)"

FILE="$WORKDIR/repo/crates/atuin-ai/src/tui/view/mod.rs"
if ! grep -qF 'padding_left: Cells::from(2)' "$FILE"; then
  echo "ERROR: 'padding_left: Cells::from(2)' not found in $FILE — layout changed, aborting."
  echo "Source kept at $WORKDIR/repo for inspection."
  exit 1
fi

echo "[2/4] Patching $FILE  (sed: padding_left: Cells::from(2) -> Cells::from(0))"
sed -i 's/padding_left: Cells::from(2)/padding_left: Cells::from(0)/g' "$FILE"
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
