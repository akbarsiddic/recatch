#!/usr/bin/env python3
"""Regenerate Resources/AppIcon.icns (and the .iconset) from the brand master.

The icon art is the ReCatch coral mark, kept as Resources/AppIcon-1024.png. This
script only rebuilds the .icns and its per-size variants from that master.
"""
import os
import subprocess


def make_icns(master_png, out_icns):
    iconset = os.path.join(os.path.dirname(master_png), "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
             (256, 1), (256, 2), (512, 1), (512, 2)]
    for base, scale in sizes:
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        subprocess.run(
            ["sips", "-z", str(base * scale), str(base * scale), master_png,
             "--out", os.path.join(iconset, name)],
            check=True, capture_output=True,
        )
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out_icns], check=True)
    print(f"wrote {out_icns}")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.join(here, "..", "Resources")
    make_icns(os.path.join(res, "AppIcon-1024.png"), os.path.join(res, "AppIcon.icns"))
