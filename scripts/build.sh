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

# Prefer the persistent self-signed identity if installed (set up via scripts/setup-signing.sh).
# Falls back to ad-hoc, which causes macOS to ask for permissions again on every rebuild.
SIGNING_IDENTITY="${POLYCHROME_SIGNING_IDENTITY:-Polychrome Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
    echo "==> Signing with '$SIGNING_IDENTITY' (stable, preserves TCC grants)"
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "${APP_DIR}" || true
else
    echo "==> No persistent identity found; using ad-hoc (run scripts/setup-signing.sh to fix re-prompts)"
    codesign --force --deep --sign - "${APP_DIR}" || true
fi

echo "==> Built ${APP_DIR}"
echo "Open with: open ${APP_DIR}"
