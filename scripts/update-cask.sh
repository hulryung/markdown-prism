#!/bin/bash
#
# Update the Homebrew cask definition from a DMG.
# Reads the actual app name from the DMG to prevent name mismatch issues.
#
# Usage: ./scripts/update-cask.sh <path-to-dmg> [version]
#
# The version defaults to MARKETING_VERSION in project.yml, the single source
# of truth the Info.plists are generated from, so the cask cannot drift from
# what was built.
#

set -euo pipefail

DMG_PATH="${1:?Usage: $0 <path-to-dmg> [version]}"
PROJECT_YML="$(dirname "$0")/../project.yml"
VERSION="${2:-$(awk -F'"' '/^ *MARKETING_VERSION:/{print $2; exit}' "$PROJECT_YML")}"

if [ -z "$VERSION" ]; then
    echo "Error: no version given and MARKETING_VERSION not found in $PROJECT_YML"
    exit 1
fi

TAP_CASK="/opt/homebrew/Library/Taps/hulryung/homebrew-tap/Casks/markdown-prism.rb"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found: $DMG_PATH"
    exit 1
fi

if [ ! -f "$TAP_CASK" ]; then
    echo "Error: Cask file not found: $TAP_CASK"
    echo "Run: brew tap hulryung/tap"
    exit 1
fi

# Calculate SHA256
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')

# Mount DMG and find the .app name.
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

APP_NAME=$(ls "$MOUNT_DIR/" | grep '\.app$' | head -1)

if [ -z "$APP_NAME" ]; then
    echo "Error: No .app found in DMG"
    exit 1
fi

echo "Version:  $VERSION"
echo "SHA256:   $SHA256"
echo "App name: $APP_NAME"

# Generate cask file
cat > "$TAP_CASK" << EOF
cask "markdown-prism" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/hulryung/markdown-prism/releases/download/v#{version}/MarkdownPrism-#{version}.dmg"
  name "Markdown Prism"
  desc "Native macOS Markdown viewer and editor with live preview"
  homepage "https://prism.huconn.xyz"

  depends_on macos: :sonoma

  app "$APP_NAME"

  zap trash: [
    "~/Library/Containers/com.markdownprism.app",
    "~/Library/Saved Application State/com.markdownprism.app.savedState",
  ]
end
EOF

echo ""
echo "Updated: $TAP_CASK"
echo "Next steps:"
echo "  cd $(dirname $TAP_CASK) && git add . && git commit -m 'Update markdown-prism to v$VERSION' && git push"
