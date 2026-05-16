#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Polychrome"
SRC_BIN_NAME="ChromeProfiles"   # SPM target name; stays internal

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
EXEC="${BIN_PATH}/${SRC_BIN_NAME}"
if [[ ! -x "$EXEC" ]]; then
    echo "Binary not found at $EXEC"; exit 1
fi

APP_DIR="build/${APP_NAME}.app"
echo "==> bundling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${EXEC}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Bundle/Info.plist" "${APP_DIR}/Contents/Info.plist"
if [[ -f "Bundle/AppIcon.icns" ]]; then
    cp "Bundle/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

xattr -cr "${APP_DIR}" 2>/dev/null || true
codesign --force --deep --sign - "${APP_DIR}" || true

echo "==> Built ${APP_DIR}"
echo "Open with: open ${APP_DIR}"
