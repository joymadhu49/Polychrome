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

rm -f "$DMG"
echo "==> creating $DMG"

# Preferred: a styled installer window (background art, positioned icons,
# volume icon) via create-dmg — `brew install create-dmg`. The layout matches
# Bundle/dmg-background.png (regenerate with scripts/make-dmg-background.py):
# 600x420 pt window, app icon at (150,190), Applications at (450,190).
styled_dmg() {
    command -v create-dmg >/dev/null 2>&1 || return 1
    local stage
    stage="$(mktemp -d)/styled"
    mkdir -p "$stage"
    cp -R "$APP" "$stage/"
    local args=(
        --volname "$APP_NAME"
        --background "Bundle/dmg-background.png"
        --window-pos 200 120
        --window-size 600 420
        --icon-size 128
        --text-size 12
        --icon "${APP_NAME}.app" 150 190
        --app-drop-link 450 190
        --hide-extension "${APP_NAME}.app"
        --no-internet-enable
    )
    [[ -f "Bundle/AppIcon.icns" ]] && args+=(--volicon "Bundle/AppIcon.icns")
    create-dmg "${args[@]}" "$DMG" "$stage"
}

# Fallback: plain (unstyled) DMG via hdiutil — always works, even without
# create-dmg or when Finder scripting is unavailable on a CI runner.
plain_dmg() {
    local stage
    stage="$(mktemp -d)/${APP_NAME}"
    mkdir -p "$stage"
    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$stage" \
        -ov \
        -format UDZO \
        -fs HFS+ \
        "$DMG" >/dev/null
}

if styled_dmg; then
    echo "==> styled DMG (create-dmg)"
else
    echo "==> create-dmg unavailable or failed — falling back to plain hdiutil DMG"
    rm -f "$DMG" rw.*.dmg 2>/dev/null || true
    plain_dmg
fi

ls -lh "$DMG"
echo "==> Done: $DMG"
