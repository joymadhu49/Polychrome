#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Polychrome"
DEFAULT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Bundle/Info.plist 2>/dev/null || echo 1.0.0)"
VERSION="${1:-$DEFAULT_VERSION}"
APP="build/${APP_NAME}.app"
DMG="build/${APP_NAME}-${VERSION}.dmg"

if [[ ! -d "$APP" ]]; then
    echo "App bundle not found at $APP — running build.sh first..."
    bash scripts/build.sh
fi

STAGE="$(mktemp -d)/${APP_NAME}"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
echo "==> creating $DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null

ls -lh "$DMG"
echo "==> Done: $DMG"
