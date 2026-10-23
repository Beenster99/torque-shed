#!/usr/bin/env python3
"""The world map the Route planner TV shows between the globe and the cells: coastlines, lakes, rivers, the borders
between countries and the world's towns and cities, from Natural Earth (public domain), simplified and written small.

    python3 tools/world_bake.py --out data/world

Writes `world.tsw`, the land and lines (see below), and `places.json`, [[name, lat, lon, population, country], ...] the
most important first (as Natural Earth's own maps name them: capitals and great cities first).

world.tsw (little-endian): b"TSW2", then a u32 count of layers, each: a u8 name length and the name (ascii), a u8 kind,
then for kind 0 (areas to fill, already cut into triangles) a u32 count of points, the points, a u32 count of corners
and the corners (u32 indices into the points, three a triangle); for kind 1 (lines) a u32 count of lines and each line a
u32 count of points and the points. A point is an i32 pair (longitude, latitude) in 1e-5 degrees. Layers: "land_low"
(the 1:50m coast, for the globe), "land" (1:10m), "lakes", "rivers", "borders".

Needs numpy and mapbox_earcut (pip install mapbox-earcut)."""
import argparse
import json
import os
import struct
import sys
import urllib.request

import mapbox_earcut
import numpy as np

NE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/%s.geojson"
USER_AGENT = "TorqueShed world_bake (+https://github.com/Beenster99/torque-shed)"
SCALE = 1e5
# Each layer: (name, Natural Earth file, kind (0 areas, 1 lines), how far (degrees) a line may stray from the original,
# a filter on the feature's properties).
LAYERS = [
    ("land_low", "ne_50m_land", 0, 0.02, None),
    ("land", "ne_10m_land", 0, 0.004, None),
    ("lakes", "ne_10m_lakes", 0, 0.004, lambda p: (p.get("scalerank") or 0) <= 6),
    ("rivers", "ne_10m_rivers_lake_centerlines", 1, 0.004, lambda p: (p.get("scalerank") or 0) <= 6),
    ("borders", "ne_10m_admin_0_boundary_lines_land", 1, 0.004, None),
]
PLACES = "ne_10m_populated_places_simple"


def fetch(name, cache):
    path = os.path.join(cache, name + ".geojson")
    if not os.path.exists(path):
        os.makedirs(cache, exist_ok=True)
        req = urllib.request.Request(NE % name, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=120) as r, open(path + ".part", "wb") as f:
            f.write(r.read())
        os.replace(path + ".part", path)
    with open(path) as f:
        return json.load(f)


def simplify(pts, tol):
    """Douglas-Peucker: the points of line `pts` (N x 2) to keep so it strays no more than `tol` from the original."""
    n = len(pts)
    if n < 3:
        return pts
    keep = np.zeros(n, dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        seg = pts[b] - pts[a]
        rel = pts[a + 1:b] - pts[a]
        length = np.hypot(*seg)
        if length < 1e-12:
            d = np.hypot(rel[:, 0], rel[:, 1])
        else:
            d = np.abs(seg[0] * rel[:, 1] - seg[1] * rel[:, 0]) / length
        i = int(np.argmax(d))
        if d[i] > tol:
            m = a + 1 + i
            keep[m] = True
            stack.append((a, m))
            stack.append((m, b))
    return pts[keep]


def polygons_of(geom):
    """A GeoJSON geometry's polygons, each [outer ring, holes...]."""
    if geom["type"] == "Polygon":
        return [geom["coordinates"]]
    if geom["type"] == "MultiPolygon":
        return geom["coordinates"]
    return []


def lines_of(geom):
    if geom["type"] == "LineString":
        return [geom["coordinates"]]
    if geom["type"] == "MultiLineString":
        return geom["coordinates"]
    return []


def simple_ring(ring, tol):
    """A closed ring, simplified, without its last point (the first again); None when too little is left."""
    pts = np.asarray([p[:2] for p in ring], dtype=float)
    if len(pts) > 1 and np.allclose(pts[0], pts[-1]):
        pts = pts[:-1]
    # Simplified as two halves, so the ring's two ends (the same point) stay put.
    half = len(pts) // 2
    if half >= 2:
        pts = np.vstack([simplify(pts[:half + 1], tol)[:-1], simplify(np.vstack([pts[half:], pts[:1]]), tol)[:-1]])
    pts = np.round(pts * SCALE) / SCALE
    return pts if len(pts) >= 3 else None


def bake_areas(fc, tol, keep):
    """The areas of a layer cut into triangles: (points N x 2 in 1e-5 degrees, corner indices)."""
    verts = []
    corners = []
    base = 0
    for feat in fc["features"]:
        if keep is not None and not keep(feat.get("properties") or {}):
            continue
        geom = feat.get("geometry")
        if not geom:
            continue
        for poly in polygons_of(geom):
            rings = [r for r in (simple_ring(r, tol) for r in poly) if r is not None]
            if not rings or len(rings[0]) < 3 or simple_ring(poly[0], tol) is None:
                continue
            pts = np.vstack(rings)
            ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
            tri = mapbox_earcut.triangulate_float64(pts, ends)
            if len(tri) == 0:
                continue
            verts.append(np.round(pts * SCALE).astype(np.int32))
            corners.append(tri.astype(np.uint32) + base)
            base += len(pts)
    if not verts:
        return np.zeros((0, 2), np.int32), np.zeros(0, np.uint32)
    return np.vstack(verts), np.concatenate(corners)


def bake_lines(fc, tol, keep):
    out = []
    for feat in fc["features"]:
        if keep is not None and not keep(feat.get("properties") or {}):
            continue
        geom = feat.get("geometry")
        if not geom:
            continue
        for line in lines_of(geom):
            pts = simplify(np.asarray([p[:2] for p in line], dtype=float), tol)
            if len(pts) >= 2:
                out.append(np.round(pts * SCALE).astype(np.int32))
    return out


def write_bin(path, layers):
    with open(path, "wb") as f:
        f.write(b"TSW2")
        f.write(struct.pack("<I", len(layers)))
        for name, kind, data in layers:
            f.write(struct.pack("<B", len(name)) + name.encode("ascii"))
            f.write(struct.pack("<B", kind))
            if kind == 0:
                pts, tri = data
                f.write(struct.pack("<I", len(pts)) + pts.astype("<i4").tobytes())
                f.write(struct.pack("<I", len(tri)) + tri.astype("<u4").tobytes())
            else:
                f.write(struct.pack("<I", len(data)))
                for line in data:
                    f.write(struct.pack("<I", len(line)) + line.astype("<i4").tobytes())


def bake_places(fc):
    out = []
    for feat in fc["features"]:
        p = feat["properties"]
        name = p.get("name") or p.get("nameascii")
        if not name:
            continue
        lon, lat = feat["geometry"]["coordinates"][:2]
        rank = float(p.get("min_zoom") or 10.0)
        out.append((rank, [name, round(lat, 5), round(lon, 5), int(p.get("pop_max") or 0), p.get("adm0name") or ""]))
    # In the order Natural Earth's own maps name them (the zoom each first shows at: capitals and great cities first),
    # then the biggest.
    out.sort(key=lambda r: (r[0], -r[1][3], r[1][0]))
    return [r[1] for r in out]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default="data/world")
    ap.add_argument("--cache", default=os.path.join(os.path.expanduser("~"), ".cache", "torque_shed", "natural_earth"))
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    layers = []
    for name, src, kind, tol, keep in LAYERS:
        fc = fetch(src, args.cache)
        if kind == 0:
            data = bake_areas(fc, tol, keep)
            print("%s: %d points, %d triangles" % (name, len(data[0]), len(data[1]) // 3))
        else:
            data = bake_lines(fc, tol, keep)
            print("%s: %d lines, %d points" % (name, len(data), sum(len(r) for r in data)))
        layers.append((name, kind, data))
    write_bin(os.path.join(args.out, "world.tsw"), layers)
    places = bake_places(fetch(PLACES, args.cache))
    with open(os.path.join(args.out, "places.json"), "w", encoding="utf-8") as f:
        json.dump(places, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print("places: %d" % len(places))
    print("world.tsw %.1f MB, places.json %.1f MB" % (os.path.getsize(os.path.join(args.out, "world.tsw")) / 1e6,
                                                      os.path.getsize(os.path.join(args.out, "places.json")) / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
