#!/bin/bash
#
# Validate that the DMG contains the expected app bundle name.
# Usage: ./scripts/validate-dmg.sh <path-to-dmg> [expected-app-name]
#

set -euo pipefail

DMG_PATH="${1:?Usage: $0 <path-to-dmg> [expected-app-name]}"
EXPECTED_APP="${2:-MarkdownPrism.app}"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found: $DMG_PATH"
    exit 1
fi

# hdiutil emits multiple tab-separated rows; only the row with a /Volumes/...
# mount point in the last column is the one we want.
MOUNT_DIR=$(hdiutil attach "$DMG_PATH" -nobrowse -readonly 2>/dev/null \
    | awk -F'\t' '$NF ~ /^\/Volumes\//{print $NF; exit}')

if [ -z "$MOUNT_DIR" ]; then
    echo "Error: Failed to mount DMG"
    exit 1
fi

cleanup() {
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
}
trap cleanup EXIT

if [ -d "$MOUNT_DIR/$EXPECTED_APP" ]; then
    echo "OK: '$EXPECTED_APP' found in DMG"
else
    echo "Error: '$EXPECTED_APP' not found in DMG"
    echo "Contents of DMG:"
    ls "$MOUNT_DIR/"
    exit 1
fi
