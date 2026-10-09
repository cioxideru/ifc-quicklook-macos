#!/usr/bin/env bash
# Build the app, install it to /Applications, register the Quick Look extension, verify.
# Usage: scripts/install.sh [path/to/sample.ifc]
#   Signing (optional): TEAM_ID=XXXXXXXXXX scripts/install.sh, or put TEAM_ID in signing.local.env.
#   Without TEAM_ID the app is signed ad-hoc, which is enough on the machine that built it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -f signing.local.env ]] && source signing.local.env

APP_NAME="IFCQuickLook"
APP="/Applications/${APP_NAME}.app"
SAMPLE="${1:-}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

SIGN_ARGS=()
if [[ -n "${TEAM_ID:-}" ]]; then
  SIGN_ARGS=(CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Apple Development")
fi

echo "== xcodegen"
xcodegen generate --quiet

echo "== build"
BUILT="build/Build/Products/Release/${APP_NAME}.app"
# Remove the previous product first: otherwise a failed build leaves it in place and the
# existence check below would pass, installing a stale binary as if it were the new one.
rm -rf "$BUILT"
set +e
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath build SYMROOT="$ROOT/build/Build/Products" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} build | grep -E 'error|warning: |BUILD'
BUILD_STATUS=${PIPESTATUS[0]}
set -e
[[ $BUILD_STATUS -eq 0 ]] || { echo "build failed (xcodebuild exited $BUILD_STATUS)"; exit 1; }
[[ -d "$BUILT" ]] || { echo "build failed: $BUILT missing"; exit 1; }

echo "== install to $APP"
rm -rf "$APP"
cp -R "$BUILT" "$APP"

echo "== register"
open -a "$APP"
sleep 2
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$APP"
pluginkit -a "$APP/Contents/PlugIns/IFCPreview.appex" 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
sleep 1

echo "== verify"
codesign -dvv "$APP/Contents/PlugIns/IFCPreview.appex" 2>&1 | grep -E 'Signature|TeamIdentifier|Identifier=' || true
pluginkit -m -p com.apple.quicklook.preview -v 2>/dev/null | grep -i ifcpreview || echo "!! extension not listed by pluginkit"
if [[ -n "$SAMPLE" ]]; then
  mdls -name kMDItemContentType "$SAMPLE"
  echo "run:  qlmanage -p \"$SAMPLE\""
fi
