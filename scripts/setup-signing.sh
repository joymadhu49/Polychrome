#!/usr/bin/env bash
# One-time setup: create a persistent self-signed code-signing cert in the login keychain.
# Without this, every rebuild produces a different signature, so macOS TCC asks for
# Accessibility / Screen Recording / etc. permission again every time.
#
# Run once:
#   bash scripts/setup-signing.sh
#
# Then build.sh will sign with this stable identity and macOS will remember
# Polychrome's permissions across rebuilds.

set -euo pipefail

CERT_NAME="${POLYCHROME_SIGNING_IDENTITY:-Polychrome Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "==> Signing identity '$CERT_NAME' already installed."
    exit 0
fi

echo "==> Creating self-signed code-signing identity: $CERT_NAME"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext

[dn]
CN = $CERT_NAME

[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -config "$TMP/cert.cnf" 2>/dev/null

PASS="polychrome"
# Build a PKCS#12 with legacy (PBE-SHA1) encryption — modern openssl defaults break security CLI
openssl pkcs12 -export -legacy \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" \
    -name "$CERT_NAME" -passout "pass:$PASS" 2>/dev/null

security import "$TMP/cert.p12" -f pkcs12 -P "$PASS" -k "$KEYCHAIN" \
    -T /usr/bin/codesign -T /usr/bin/security -A >/dev/null

# Authorize codesign to use the private key without a UI prompt
security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

# Mark the private key as accessible to codesign without prompt
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "==> Installed. Test with:"
echo "    security find-identity -v -p codesigning | grep '$CERT_NAME'"
echo
echo "Next steps:"
echo "  1. Reset existing Polychrome TCC grants (signature changed):"
echo "       tccutil reset Accessibility com.joymadhu.polychrome"
echo "  2. Rebuild + relaunch:"
echo "       bash scripts/build.sh"
echo "  3. Grant Accessibility once. Future rebuilds keep the grant."
