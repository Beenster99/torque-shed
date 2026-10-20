#!/usr/bin/env python3
"""Draws a route pack (see route_bake.py) as shaded height maps with roads, buildings and the route.

    python3 tools/pack_preview.py data/routes/shodoshima out_prefix        # writes out_prefix_leg00.png ...
    python3 tools/pack_preview.py data/routes/shodoshima out.png --leg 2   # one leg
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw


def load_leg(path, meta, k):
    leg = meta["legs"][k]
    d = os.path.join(path, leg["dir"])
    size = meta["grid"]["size"]
    q = np.fromfile(os.path.join(d, "heights.u16"), dtype="<u2").reshape(size, size)
    heights = q * leg["height"]["scale"] + leg["height"]["min"]
    with open(os.path.join(d, "roads.json")) as f:
        roads = json.load(f)
    with open(os.path.join(d, "buildings.json")) as f:
        buildings = json.load(f)
    return leg, heights, roads, buildings


def render(path, out, k):
    with open(os.path.join(path, "pack.json")) as f:
        meta = json.load(f)
    with open(os.path.join(path, "route.json")) as f:
        route = json.load(f)
    leg, h, roads, buildings = load_leg(path, meta, k)
    size, sp = meta["grid"]["size"], meta["grid"]["spacing"]
    gy, gx = np.gradient(h, sp)
    shade = np.clip(0.5 + 0.9 * (gx - gy) / 2.0, 0, 1)
    rel = (h - h.min()) / max(h.max() - h.min(), 1e-6)
    img = np.zeros((size, size, 3))
    img[..., 0] = 0.30 + 0.5 * rel
    img[..., 1] = 0.45 + 0.35 * rel
    img[..., 2] = 0.25 + 0.2 * rel
    img *= (0.55 + 0.6 * shade)[..., None]
    if leg["sea_level"] is not None:
        sea = h <= leg["sea_level"] + 0.05
        img[sea] = np.array([0.12, 0.3, 0.55]) * (0.7 + 0.3 * np.clip(1 + (h[sea] - leg["sea_level"]) / 35.0, 0, 1))[:, None]
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype("uint8"))
    d = ImageDraw.Draw(im)
    half = (size - 1) * sp / 2
    px = lambda p: ((p[0] + half) / sp, (p[1] + half) / sp)
    for r in roads:
        col = (255, 235, 120) if r["kind"] == "tarmac" else (230, 140, 60)
        d.line([px(p) for p in r["pts"]], fill=col, width=2 if r["name"] != "link" else 3)
    for b in buildings:
        x, y = px((b["x"], b["z"]))
        d.rectangle([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=(240, 80, 80))
    ox, oz = leg["origin"]
    local = [px((p[0] - ox, p[1] - oz)) for p in route["points"]]
    d.line(local, fill=(255, 0, 255), width=2)
    if leg["shed"]:
        sx, sz = px((0, -20))
        d.ellipse([sx - 8, sz - 8, sx + 8, sz + 8], outline=(0, 120, 255), width=2)
    im.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("pack")
    ap.add_argument("out")
    ap.add_argument("--leg", type=int)
    a = ap.parse_args()
    with open(os.path.join(a.pack, "pack.json")) as f:
        n = len(json.load(f)["legs"])
    if a.leg is not None:
        render(a.pack, a.out, a.leg)
    else:
        for k in range(n):
            render(a.pack, "%s_leg%02d.png" % (a.out.removesuffix(".png"), k), k)
