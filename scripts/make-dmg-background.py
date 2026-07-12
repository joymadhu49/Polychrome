#!/usr/bin/env python3
"""Generate Bundle/dmg-background.png — the DMG installer window backdrop.

Dependency-free (zlib + struct only) so it can run anywhere. The image is
1200x840 px with a 144 dpi pHYs chunk, so Finder renders it as a crisp
600x420 pt retina background. Layout matches scripts/make-dmg.sh:
app icon centered at (150,190) pt, Applications at (450,190) pt, 128 pt icons.
Regenerate with:  python3 scripts/make-dmg-background.py
"""
import struct
import zlib

W, H = 1200, 840  # @2x pixels for a 600x420 pt window


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def smooth(d, soft=1.5):
    """1 inside the shape, 0 outside, soft antialiased edge from an SDF."""
    return clamp(0.5 - d / (2 * soft), 0.0, 1.0)


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = clamp((wx * vx + wy * vy) / (vx * vx + vy * vy), 0.0, 1.0)
    dx, dy = wx - t * vx, wy - t * vy
    return (dx * dx + dy * dy) ** 0.5


def rrect_dist(px, py, cx, cy, hw, hh, rad):
    """SDF of a rounded rectangle centered at (cx,cy): negative inside."""
    qx = abs(px - cx) - (hw - rad)
    qy = abs(py - cy) - (hh - rad)
    ox, oy = max(qx, 0.0), max(qy, 0.0)
    outside = (ox * ox + oy * oy) ** 0.5
    inside = min(max(qx, qy), 0.0)
    return outside + inside - rad


def tri_dist(px, py, tri):
    """Signed-ish distance to a triangle: negative inside, edge distance outside."""
    (x0, y0), (x1, y1), (x2, y2) = tri
    inside = True
    edge = 1e9
    pts = [(x0, y0), (x1, y1), (x2, y2)]
    for i in range(3):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % 3]
        cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
        if cross > 0:
            inside = False
        edge = min(edge, seg_dist(px, py, ax, ay, bx, by))
    return -edge if inside else edge


# Layout in @2x pixels (points * 2)
APP_CX, APP_CY = 300, 380
DEST_CX, DEST_CY = 900, 380
WELL_HALF = 160          # half-size of the square well behind each icon
WELL_CORNER = 44         # rounded-box corner radius (matches app-icon curvature)
ARROW_Y = 380
SHAFT_X0, SHAFT_X1 = 500, 660
SHAFT_HALF = 7
HEAD = [(660, ARROW_Y - 26), (660, ARROW_Y + 26), (708, ARROW_Y)]

rows = []
for y in range(H):
    t = y / (H - 1)
    # vertical gradient: #232530 -> #15161c
    base_r = 0x23 + (0x15 - 0x23) * t
    base_g = 0x25 + (0x16 - 0x25) * t
    base_b = 0x30 + (0x1C - 0x30) * t
    row = bytearray()
    row.append(0)  # PNG filter: none
    for x in range(W):
        # gentle radial glow around the action area
        gx, gy = (x - 600) / 900.0, (y - 360) / 700.0
        glow = max(0.0, 1.0 - (gx * gx + gy * gy)) * 14
        r, g, b = base_r + glow, base_g + glow, base_b + glow * 1.3

        # soft rounded-box "wells" behind both icons
        for cx, cy in ((APP_CX, APP_CY), (DEST_CX, DEST_CY)):
            d = rrect_dist(x, y, cx, cy, WELL_HALF, WELL_HALF, WELL_CORNER)
            fill = smooth(d, 2.0) * 10                # faint panel
            ring = smooth(abs(d) - 1.6, 1.4) * 26     # hairline outline
            r += fill + ring
            g += fill + ring
            b += fill + ring * 1.1

        # arrow: rounded shaft + triangular head
        a = smooth(seg_dist(x, y, SHAFT_X0, ARROW_Y, SHAFT_X1, ARROW_Y) - SHAFT_HALF)
        a = max(a, smooth(tri_dist(x, y, HEAD)))
        if a > 0:
            lift = 72 * a
            r += lift
            g += lift
            b += lift * 1.05

        row += bytes((int(clamp(r, 0, 255)), int(clamp(g, 0, 255)), int(clamp(b, 0, 255))))
    rows.append(bytes(row))


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)  # 8-bit RGB
dpi144 = struct.pack(">IIB", 5669, 5669, 1)          # 144 dpi in px/metre -> retina
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", ihdr)
       + chunk(b"pHYs", dpi144)
       + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
       + chunk(b"IEND", b""))

out = "Bundle/dmg-background.png"
with open(out, "wb") as f:
    f.write(png)
print(f"wrote {out}: {W}x{H} @144dpi ({len(png)} bytes)")
