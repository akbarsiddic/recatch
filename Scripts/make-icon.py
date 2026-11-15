#!/usr/bin/env python3
"""Generate the ReCatch app icon: a deep-teal rounded square with a white waveform.

No dependencies — writes PNG bytes directly (zlib + struct). macOS Big Sur shape:
full-bleed rounded rect, ~22.5% corner radius, subtle vertical gradient.
"""
import math
import os
import struct
import subprocess
import sys
import zlib

SIZE = 1024
CORNER = 0.225 * SIZE  # Apple's icon grid
ACCENT = (0.04, 0.52, 0.51)   # Brand.accent #0A8582
DEEP = (0.02, 0.33, 0.33)     # darker stop
WHITE = (1.0, 1.0, 1.0)


def rounded_rect_sd(x, y, cx, cy, hw, hh, r):
    """Signed distance to a rounded rect (negative inside)."""
    dx = abs(x - cx) - (hw - r)
    dy = abs(y - cy) - (hh - r)
    ax, ay = max(dx, 0.0), max(dy, 0.0)
    return math.hypot(ax, ay) + min(max(dx, dy), 0.0) - r


def lerp(a, b, t):
    return a + (b - a) * t


def main(out_path):
    px = bytearray()
    bars = [0.30, 0.58, 0.92, 0.52, 0.26]   # relative heights, symmetric waveform
    bar_w = 0.085 * SIZE
    gap = 0.052 * SIZE
    total_w = len(bars) * bar_w + (len(bars) - 1) * gap
    start_x = (SIZE - total_w) / 2 + bar_w / 2

    for y in range(SIZE):
        px.append(0)  # PNG filter type: none
        for x in range(SIZE):
            # background
            d = rounded_rect_sd(x + 0.5, y + 0.5, SIZE / 2, SIZE / 2, SIZE / 2, SIZE / 2, CORNER)
            bg_cov = min(1.0, max(0.0, 0.5 - d))
            if bg_cov <= 0.0:
                px.extend((0, 0, 0, 0))
                continue
            t = y / SIZE
            col = [lerp(ACCENT[i], DEEP[i], t * 0.85) for i in range(3)]

            # waveform bars
            for i, h in enumerate(bars):
                bh = h * SIZE * 0.62
                cx = start_x + i * (bar_w + gap)
                db = rounded_rect_sd(x + 0.5, y + 0.5, cx, SIZE / 2, bar_w / 2, bh / 2, bar_w / 2)
                cov = min(1.0, max(0.0, 0.5 - db))
                if cov > 0:
                    for c in range(3):
                        col[c] = lerp(col[c], WHITE[c], cov)

            # soft highlight in the top-left for depth
            hx, hy = SIZE * 0.30, SIZE * 0.22
            dist = math.hypot(x - hx, y - hy) / (SIZE * 0.62)
            glow = max(0.0, 1.0 - dist) ** 3 * 0.16
            for c in range(3):
                col[c] = min(1.0, col[c] + glow)

            px.extend((int(col[0] * 255), int(col[1] * 255), int(col[2] * 255), int(bg_cov * 255)))

    raw = bytes(px)
    png = b"\x89PNG\r\n\x1a\n"
    png += _chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += _chunk(b"IDAT", zlib.compress(raw, 9))
    png += _chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(png)
    print(f"wrote {out_path} ({len(png)} bytes)")


def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def make_icns(master_png, out_icns):
    iconset = os.path.join(os.path.dirname(master_png), "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    for base, scale in sizes:
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        subprocess.run(["sips", "-z", str(base * scale), str(base * scale), master_png,
                        "--out", os.path.join(iconset, name)],
                       check=True, capture_output=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out_icns], check=True)
    print(f"wrote {out_icns}")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.join(here, "..", "Resources")
    master = os.path.join(res, "AppIcon-1024.png")
    main(master)
    make_icns(master, os.path.join(res, "AppIcon.icns"))
