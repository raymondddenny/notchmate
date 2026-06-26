#!/bin/sh
# Build + sign notchmate. One source of truth for the two-step recipe.
#
#   ./build.sh                                  -> ad-hoc (default)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build.sh  -> Developer ID
#
# Why two flavors (see AGENTS.md "Signing flavors"):
#  - keychain-access-groups is a RESTRICTED entitlement. On macOS 26 it validates only
#    against a real Apple certificate chain. Ad-hoc has none, so shipping it makes AMFI
#    kill the app at launch (RBS Code=5 / POSIX 163). Ad-hoc therefore uses the trimmed
#    entitlements + the login keychain (ADHOC_SIGNING compile flag, set in the project).
#  - Developer ID has a cert chain, so it uses the full entitlements (data-protection
#    keychain, no per-rebuild prompt) and compiles WITHOUT ADHOC_SIGNING.
set -e

PROJECT="notchmate.xcodeproj"
SCHEME="notchmate"
APP="build/Build/Products/Release/notchmate.app"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Developer ID build: $SIGN_IDENTITY"
    ENTITLEMENTS="notchmate/notchmate-devid.entitlements"
    # Drop ADHOC_SIGNING so the data-protection keychain path compiles in.
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
        SWIFT_ACTIVE_COMPILATION_CONDITIONS="" build
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" "$APP"
else
    echo "==> Ad-hoc build"
    ENTITLEMENTS="notchmate/notchmate.entitlements"
    # Project default already sets ADHOC_SIGNING (login keychain path).
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
        --sign - "$APP"
fi

echo "==> Signed $APP with $ENTITLEMENTS"
echo "    Run: open $APP"
