#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Bundle/AppIcon.png"
if [[ ! -f "$SRC" ]]; then
    echo "Missing $SRC — drop a square PNG (ideally 1024×1024) at that path."
    exit 1
fi

ICONSET="Bundle/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "Bundle/AppIcon.icns"
echo "Built Bundle/AppIcon.icns"
