#!/usr/bin/env bash
# Build a Developer ID signed, notarized and stapled release zip in dist/.
# Needs signing.local.env (see signing.local.env.example), a "Developer ID Application" certificate
# in the login keychain and notarytool credentials stored under $NOTARY_PROFILE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source signing.local.env
: "${TEAM_ID:?set TEAM_ID in signing.local.env}" "${NOTARY_PROFILE:?set NOTARY_PROFILE in signing.local.env}"

APP_NAME="IFCQuickLook"
VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?/\1/p' project.yml)"
BUILT="build/Build/Products/Release/${APP_NAME}.app"
ZIP="dist/${APP_NAME}-${VERSION}.zip"

[[ -f IFCPreview/Web/vendor/web-ifc.wasm ]] || scripts/fetch-vendor.sh

echo "== build $VERSION"
xcodegen generate --quiet
rm -rf "$BUILT" dist
mkdir -p dist
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" -configuration Release -derivedDataPath build SYMROOT="$ROOT/build/Build/Products" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" build -quiet
codesign --verify --deep --strict --verbose=2 "$BUILT"

echo "== notarize"
ditto -c -k --keepParent "$BUILT" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$BUILT"
rm "$ZIP"
ditto -c -k --keepParent "$BUILT" "$ZIP"

echo "== check"
spctl --assess --type execute --verbose=2 "$BUILT"
shasum -a 256 "$ZIP"
echo "done: $ZIP"
