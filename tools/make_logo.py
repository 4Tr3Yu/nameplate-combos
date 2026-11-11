"""Generate the Nameplate Combos logo.

Three interlocking trapezoid pips (yellow -> orange -> red, the last one
glowing) on a dark rounded badge with a thin gold border.

Writes:
  docs/logo.png                   256x256, for the README / GitHub
  NameplateCombos/media/icon.tga  64x64, minimap button + AddOns list icon

Usage: python3 tools/make_logo.py
"""

import math
import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(__file__), "..")
SS = 4  # supersamples per axis

# Layout in unit coordinates (0..1, y down)
PIP_W, PIP_H = 0.30, 0.22
SLANT = PIP_W * 12 / 64          # same slant ratio as the in-game pips
GAP = 0.012
OUTLINE = 0.014
STEP = PIP_W - SLANT + GAP
BAR_W = 2 * STEP + PIP_W
BAR_X = (1 - BAR_W) / 2
BAR_Y = (1 - PIP_H) / 2

PIP_COLORS = [(1.0, 0.85, 0.1), (1.0, 0.55, 0.1), (1.0, 0.25, 0.1)]
GLOW_COLOR = (1.0, 0.35, 0.1)
GLOW_RADIUS = 0.09

BG_TOP, BG_BOTTOM = (0.17, 0.15, 0.20), (0.07, 0.06, 0.09)
BORDER_COLOR = (0.78, 0.63, 0.29)
CORNER_R = 0.18
BORDER_W = 0.028


def trapezoid(i):
    x0 = BAR_X + i * STEP
    y0, y1 = BAR_Y, BAR_Y + PIP_H
    if i % 2 == 0:  # wide top
        return [(x0, y0), (x0 + PIP_W, y0), (x0 + PIP_W - SLANT, y1), (x0 + SLANT, y1)]
    return [(x0 + SLANT, y0), (x0 + PIP_W - SLANT, y0), (x0 + PIP_W, y1), (x0, y1)]


PIPS = [trapezoid(i) for i in range(3)]


def poly_dist(px, py, corners):
    """Min signed distance to the edges (positive inside, convex polygon)."""
    best = float("inf")
    n = len(corners)
    for i in range(n):
        (x1, y1), (x2, y2) = corners[i], corners[(i + 1) % n]
        ex, ey = x2 - x1, y2 - y1
        length = math.hypot(ex, ey)
        d = ((px - x1) * -ey + (py - y1) * ex) / length
        best = min(best, d)
    return best


def rounded_rect_dist(px, py):
    """Signed distance to the badge edge (positive inside)."""
    qx = abs(px - 0.5) - (0.5 - CORNER_R)
    qy = abs(py - 0.5) - (0.5 - CORNER_R)
    outside = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0)
    return CORNER_R - outside


def over(dst, src, a):
    return tuple(d * (1 - a) + s * a for d, s in zip(dst, src))


def sample(px, py):
    """Return (r, g, b, a) for one point."""
    bd = rounded_rect_dist(px, py)
    if bd < 0:
        return (0, 0, 0, 0)

    t = py
    col = tuple(a + (b - a) * t for a, b in zip(BG_TOP, BG_BOTTOM))

    # glow around the last pip
    gd = poly_dist(px, py, PIPS[2])
    if gd < 0:
        g = max(0.0, 1 + gd / GLOW_RADIUS) ** 2
        col = over(col, GLOW_COLOR, 0.85 * g)

    for color, corners in zip(PIP_COLORS, PIPS):
        d = poly_dist(px, py, corners)
        if d >= 0:
            if d < OUTLINE:
                col = (0.0, 0.0, 0.0)
            else:
                shade = 1.0 - 0.28 * (py - BAR_Y) / PIP_H
                col = tuple(c * shade for c in color)
            break

    if bd < BORDER_W:
        col = BORDER_COLOR
    return (*col, 1.0)


def render(size):
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    r, g, b, a = sample((x + (sx + 0.5) / SS) / size,
                                        (y + (sy + 0.5) / SS) / size)
                    acc[0] += r * a
                    acc[1] += g * a
                    acc[2] += b * a
                    acc[3] += a
            n = SS * SS
            a = acc[3] / n
            if a > 0:
                rgb = [int(round(c / acc[3] * 255)) for c in acc[:3]]
            else:
                rgb = [0, 0, 0]
            row.append((*rgb, int(round(a * 255))))
        rows.append(row)
    return rows


def write_png(path, rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def write_tga(path, rows):
    h, w = len(rows), len(rows[0])
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    data = bytes(c for row in rows for (r, g, b, a) in row for c in (b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + data)


def main():
    png = os.path.normpath(os.path.join(ROOT, "docs", "logo.png"))
    tga = os.path.normpath(os.path.join(ROOT, "NameplateCombos", "media", "icon.tga"))
    os.makedirs(os.path.dirname(png), exist_ok=True)
    write_png(png, render(256))
    print("wrote", png)
    write_tga(tga, render(64))
    print("wrote", tga)


if __name__ == "__main__":
    main()
