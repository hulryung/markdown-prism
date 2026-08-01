#!/bin/bash
#
# Build a signed Release app and package it as a distributable DMG.
#
# Usage: ./scripts/build-dmg.sh [output-dir]
#
# The version comes from MARKETING_VERSION in project.yml, the same source the
# Info.plists are generated from, so the DMG name cannot drift from the build.
#
# Environment:
#   SIGN_IDENTITY    codesign identity (default: the Developer ID Application
#                    identity in the keychain)
#   NOTARY_PROFILE   notarytool keychain profile. When set, the DMG is
#                    submitted for notarization and stapled. Create one with:
#                      xcrun notarytool store-credentials <profile> \
#                        --apple-id <id> --team-id <team> --password <app-specific-password>
#

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
APP_NAME="MarkdownPrism.app"
VOLUME_NAME="Markdown Prism"

VERSION="$(awk -F'"' '/^ *MARKETING_VERSION:/{print $2; exit}' "$ROOT/project.yml")"
if [ -z "$VERSION" ]; then
    echo "Error: MARKETING_VERSION not found in project.yml"
    exit 1
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" \
        | head -1 \
        | sed -E 's/.*"(.*)"/\1/')
fi

if [ -z "$SIGN_IDENTITY" ]; then
    echo "Error: no Developer ID Application identity found; set SIGN_IDENTITY"
    exit 1
fi

DERIVED="$OUT_DIR/DerivedData"
STAGING="$OUT_DIR/dmg-staging"
DMG_PATH="$OUT_DIR/MarkdownPrism-$VERSION.dmg"

echo "Version:  $VERSION"
echo "Identity: $SIGN_IDENTITY"
echo "Output:   $DMG_PATH"
echo

# Release builds start clean: an incremental build reuses the previous
# signature, so signing flag changes would silently not apply.
rm -rf "$STAGING" "$DMG_PATH" "$DERIVED"
mkdir -p "$STAGING"

echo "==> Generating Xcode project"
(cd "$ROOT" && xcodegen generate)

echo "==> Building Release"
xcodebuild \
    -project "$ROOT/MarkdownPrism.xcodeproj" \
    -scheme MarkdownPrism \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"
if [ ! -d "$BUILT_APP" ]; then
    echo "Error: build produced no app at $BUILT_APP"
    exit 1
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

# A plain `xcodebuild build` does not add a secure timestamp the way the
# archive/export flow does, and the notary service rejects the upload without
# one — after the several minutes it takes to find out. Catch it here instead.
for bundle in \
    "$BUILT_APP" \
    "$BUILT_APP/Contents/PlugIns/MarkdownPrismQuickLook.appex"
do
    # Captured rather than piped to grep: under `set -o pipefail` a `grep -q`
    # that exits on the first match kills codesign with SIGPIPE and the
    # pipeline reports failure even when the timestamp is there.
    signature=$(codesign -dvv "$bundle" 2>&1 || true)
    case "$signature" in
        *"Timestamp="*) ;;
        *)
            echo "Error: $bundle is signed without a secure timestamp; notarization would fail"
            exit 1
            ;;
    esac
done
echo "Secure timestamp present on app and extension"

echo "==> Staging"
cp -R "$BUILT_APP" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
else
    echo
    echo "Not notarized (NOTARY_PROFILE unset). Gatekeeper will reject this DMG"
    echo "on other Macs until you run:"
    echo "  xcrun notarytool submit \"$DMG_PATH\" --keychain-profile <profile> --wait"
    echo "  xcrun stapler staple \"$DMG_PATH\""
fi

echo
echo "==> Done: $DMG_PATH"
echo "Next:"
echo "  ./scripts/validate-dmg.sh \"$DMG_PATH\""
echo "  ./scripts/update-cask.sh \"$DMG_PATH\""
