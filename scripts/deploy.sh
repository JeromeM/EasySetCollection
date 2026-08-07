#!/usr/bin/env bash
# Deploy the EasySetCollection addon folder into your WoW retail AddOns directory.
# A symlink can't be used here because WoW (a Windows process) cannot follow a
# link into the WSL ext4 filesystem, so we copy. Re-run after editing the addon
# (and after `node scripts/build-sets.mjs`).
#
# Usage: scripts/deploy.sh ["/path/to/Interface/AddOns"]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../EasySetCollection"
DEST="${1:-/mnt/d/Games/World of Warcraft/_retail_/Interface/AddOns}"

if [ ! -d "$SRC" ]; then echo "Addon source not found: $SRC" >&2; exit 1; fi
if [ ! -d "$DEST" ]; then echo "AddOns dir not found: $DEST" >&2; exit 1; fi

rm -rf "$DEST/EasySetCollection"
cp -r "$SRC" "$DEST/EasySetCollection"
echo "Deployed to: $DEST/EasySetCollection"
