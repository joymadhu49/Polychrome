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

# Two signing modes, selected by POLYCHROME_SIGNING_IDENTITY:
#
#   RELEASE  — set POLYCHROME_SIGNING_IDENTITY="Developer ID Application" (or the full
#              "Developer ID Application: NAME (TEAMID)"). Signs with the hardened runtime,
#              a secure Apple timestamp, and the entitlements file — the exact combination
#              Apple's notary service requires. This is what CI uses to produce a downloadable
#              DMG that does NOT trigger Gatekeeper's "move to Trash". Signing failures are FATAL.
#
#   DEV      — default "Polychrome Dev" (self-signed, see scripts/setup-signing.sh). A stable
#              local identity so the Accessibility/TCC grant survives rebuilds. Never notarizable;
#              first launch still needs right-click > Open. Signing failures are non-fatal.
#
# IMPORTANT: `find-identity -v` only lists VALID (trusted) code-signing identities. A
# self-signed cert imported but never marked "Always Trust" shows up under `find-identity`
# (no -v) as CSSMERR_TP_NOT_TRUSTED and is skipped by the valid-only form, so we fall through
# to the untrusted branch rather than silently re-adhoc-signing (which would kill the TCC grant).
SIGNING_IDENTITY="${POLYCHROME_SIGNING_IDENTITY:-Polychrome Dev}"
ENTITLEMENTS="Bundle/Polychrome.entitlements"

case "$SIGNING_IDENTITY" in
  "Developer ID"*)
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
        echo "ERROR: release signing requested ('$SIGNING_IDENTITY') but no 'Developer ID Application'" >&2
        echo "       certificate is installed in the keychain. See scripts/notarize.sh header." >&2
        exit 1
    fi
    echo "==> Signing with '$SIGNING_IDENTITY' (Developer ID: hardened runtime + secure timestamp, notarization-ready)"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" "${APP_DIR}"
    codesign --verify --strict --verbose=2 "${APP_DIR}"
    ;;
  *)
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
        echo "==> Signing with '$SIGNING_IDENTITY' (stable dev identity, preserves TCC grants)"
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "${APP_DIR}" || true
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
        # Cert exists but isn't "Always Trust" (CSSMERR_TP_NOT_TRUSTED). codesign signs fine with the
        # private key regardless of trust, and the designated requirement is keyed to bundle id + cert
        # leaf (stable across rebuilds), so the TCC grant persists. Missing trust only affects Gatekeeper
        # on first launch (right-click > Open), not TCC matching.
        echo "==> Signing with '$SIGNING_IDENTITY' (untrusted self-signed, but stable — preserves TCC grants)"
        echo "    Optional: Keychain Access > '$SIGNING_IDENTITY' > Get Info > Trust > Code Signing: Always Trust to silence Gatekeeper."
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "${APP_DIR}" || true
    else
        echo "==> No persistent identity '$SIGNING_IDENTITY' found; using ad-hoc (run scripts/setup-signing.sh to fix re-prompts)"
        echo "    For a distributable build, set POLYCHROME_SIGNING_IDENTITY='Developer ID Application'."
        codesign --force --sign - "${APP_DIR}" || true
    fi
    ;;
esac

echo "==> Built ${APP_DIR}"
echo "Open with: open ${APP_DIR}"
