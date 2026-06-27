#!/bin/sh
# Package notchmate.app into a distributable .dmg (drag-to-Applications).
# Reuses build.sh for the build+sign recipe; only hdiutil is needed (no deps).
#
#   ./package-dmg.sh
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./package-dmg.sh  -> passes through to build.sh
#
# Output: dist/notchmate-<version>.dmg
set -e

APP="build/Build/Products/Release/notchmate.app"

# 1. Build + sign (ad-hoc by default; honors SIGN_IDENTITY if set).
./build.sh

# 2. Version from the built app's Info.plist.
VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")

# 3. Stage: just the app + an /Applications symlink for drag-install.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 4. Build the compressed DMG.
mkdir -p dist
DMG="dist/notchmate-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "notchmate" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# 5. Ad-hoc sign the DMG (tidy; harmless without a real identity).
codesign --force --sign "${SIGN_IDENTITY:--}" "$DMG"

echo "==> Created $DMG"
echo "    Open it, drag notchmate to Applications, launch from there."
