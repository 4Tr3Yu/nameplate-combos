"""Generate the trapezoid pip textures for NameplateCombos.

Writes two 64x32 32-bit TGA files into NameplateCombos/media/:
  trapezoid_a.tga - wide top, narrow bottom
  trapezoid_b.tga - narrow top, wide bottom
Placed alternately (A, B, A, ...) and offset by (W - SLANT) they interlock
into one continuous bar.

The shape is white (tinted in game with SetVertexColor) with a dark outline
and a light-to-dark vertical gradient. Both shapes get the same top-lit
gradient, which is why B is its own file instead of a flipped A.

Also writes glow_a.tga / glow_b.tga: 128x64 soft halos around the same
shapes (shape centered, 32px padding left/right, 16px top/bottom), drawn 2x
the pip size behind each pip when at max combo points.

Usage: python3 tools/make_textures.py
"""

import os
import struct

W, H = 64, 32      # texture size (must be powers of two)
SLANT = 12         # horizontal inset of the narrow edge, in texture pixels
OUTLINE = 2.5      # outline thickness, in texture pixels
SS = 4             # supersamples per axis (anti-aliasing)
TOP_SHADE, BOTTOM_SHADE = 1.0, 0.72

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "NameplateCombos", "media")


def edges(wide_top):
    """Return the 4 corners (clockwise, y down) of the trapezoid."""
    if wide_top:
        return [(0, 0), (W, 0), (W - SLANT, H), (SLANT, H)]
    return [(SLANT, 0), (W - SLANT, 0), (W, H), (0, H)]


def edge_distances(px, py, corners):
    """Signed distances to each edge; all positive means inside."""
    out = []
    n = len(corners)
    for i in range(n):
        (x1, y1), (x2, y2) = corners[i], corners[(i + 1) % n]
        ex, ey = x2 - x1, y2 - y1
        length = (ex * ex + ey * ey) ** 0.5
        # inward normal for clockwise winding in y-down coordinates
        nx, ny = -ey / length, ex / length
        out.append((px - x1) * nx + (py - y1) * ny)
    return out


def render(wide_top):
    corners = edges(wide_top)
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            inside = 0
            r_sum = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px = x + (sx + 0.5) / SS
                    py = y + (sy + 0.5) / SS
                    d = edge_distances(px, py, corners)
                    if min(d) < 0:
                        continue
                    inside += 1
                    if min(d) < OUTLINE:
                        r_sum += 0.0  # outline: black, ignores tint
                    else:
                        t = py / H
                        r_sum += TOP_SHADE + (BOTTOM_SHADE - TOP_SHADE) * t
            alpha = inside / (SS * SS)
            v = r_sum / inside if inside else 0.0
            c = int(round(v * 255))
            row.append((c, c, c, int(round(alpha * 255))))
        rows.append(row)
    return rows


GW, GH = 128, 64          # glow texture size
GLOW_PAD_X, GLOW_PAD_Y = 32, 16
GLOW_RADIUS = 14.0        # falloff distance in texture pixels


def render_glow(wide_top):
    corners = [(x + GLOW_PAD_X, y + GLOW_PAD_Y) for x, y in edges(wide_top)]
    rows = []
    for y in range(GH):
        row = []
        for x in range(GW):
            d = min(edge_distances(x + 0.5, y + 0.5, corners))
            if d >= 0:
                a = 1.0
            else:
                t = max(0.0, 1.0 + d / GLOW_RADIUS)
                a = t * t
            row.append((255, 255, 255, int(round(a * 255))))
        rows.append(row)
    return rows


def write_tga(path, rows):
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,      # id length
        0,      # no color map
        2,      # uncompressed true-color
        0, 0, 0,  # color map spec
        0, 0,   # origin
        len(rows[0]), len(rows),
        32,     # bits per pixel
        0x28,   # 8 alpha bits + top-left origin
    )
    data = bytearray()
    for row in rows:
        for r, g, b, a in row:
            data += bytes((b, g, r, a))  # TGA stores BGRA
    with open(path, "wb") as f:
        f.write(header)
        f.write(data)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, wide_top in (("trapezoid_a", True), ("trapezoid_b", False)):
        path = os.path.normpath(os.path.join(OUT_DIR, name + ".tga"))
        write_tga(path, render(wide_top))
        print("wrote", path)
    for name, wide_top in (("glow_a", True), ("glow_b", False)):
        path = os.path.normpath(os.path.join(OUT_DIR, name + ".tga"))
        write_tga(path, render_glow(wide_top))
        print("wrote", path)


if __name__ == "__main__":
    main()
