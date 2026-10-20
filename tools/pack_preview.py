#!/usr/bin/env python3
"""Draws a route pack (see route_bake.py) as a shaded height map with its roads, to check a bake by eye.

    python3 tools/pack_preview.py data/routes/shodoshima preview.png
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw


def load(path):
    with open(os.path.join(path, "pack.json")) as f:
        meta = json.load(f)
    size = meta["grid"]["size"]
    q = np.fromfile(os.path.join(path, "heights.u16"), dtype="<u2").reshape(size, size)
    heights = q * meta["height"]["scale"] + meta["height"]["min"]
    with open(os.path.join(path, "roads.json")) as f:
        roads = json.load(f)
    return meta, heights, roads


def render(path, out, scale=1):
    meta, h, roads = load(path)
    size, sp = meta["grid"]["size"], meta["grid"]["spacing"]
    gy, gx = np.gradient(h, sp)
    shade = np.clip(0.5 + 0.9 * (gx - gy) / 2.0, 0, 1)
    rel = (h - h.min()) / max(h.max() - h.min(), 1e-6)
    img = np.zeros((size, size, 3))
    img[..., 0] = 0.30 + 0.5 * rel
    img[..., 1] = 0.45 + 0.35 * rel
    img[..., 2] = 0.25 + 0.2 * rel
    img *= (0.55 + 0.6 * shade)[..., None]
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype("uint8")).resize((size * scale, size * scale))
    d = ImageDraw.Draw(im)
    half = (size - 1) * sp / 2
    px = lambda p: ((p[0] + half) / sp * scale, (p[1] + half) / sp * scale)
    for r in roads:
        col = (255, 235, 120) if r["kind"] == "tarmac" else (230, 140, 60)
        d.line([px(p) for p in r["pts"]], fill=col, width=2 if r["name"] != "link" else 3)
    sx, sz = px(meta["start_world"])
    d.ellipse([sx - 6, sz - 6, sx + 6, sz + 6], outline=(255, 0, 0), width=2)
    ox, oz = px((0, -20))
    d.ellipse([ox - 8, oz - 8, ox + 8, oz + 8], outline=(0, 120, 255), width=2)
    im.save(out)


if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2])
