#!/usr/bin/env python3
"""The coast of a cell, for the Route planner TV close in: where the land is, from Overture's land (class "land": the
OpenStreetMap coastline's land, cut into tiles), clipped to the cell's own box and simplified to within 15 m. Natural
Earth's coast, which the TV draws further out, is a kilometre or more out beside the roads.

    python3 tools/coast_bake.py LAT LON [--release R] [--out FILE]     # the cell at LAT, LON: {"cell", "land"}
    python3 tools/coast_bake.py --square LAT LON --out DIR [...]       # every cell of a 1 degree square, fetched once

A cell's coast: {"cell": "ROW_COL", "land": "all" (no sea in it), "none" (all sea) or {"rings": [ring, ...], "holes":
[ring, ...]}}, each ring [lat, lon, dlat, dlon, ...] in 1e-5 degrees as the sketch has its lines (sketch_bake.py), the
first point whole and each after it the step from the one before. Holes are sea inside the land. It goes into the
cell's block of the sketch (sketch_bake.py --coast), beside its main roads.
"""
import argparse
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sketch_bake  # noqa: E402

CELL_DEG = 0.25
# How far (m) the simplified coast may stray from Overture's.
TOLERANCE = 15.0
# Rings smaller than this (square metres) are left out: rocks in the sea.
MIN_AREA = 2000.0
SCALE = sketch_bake.SCALE


def cell_box(row, col):
    """(south, west, north, east) of cell (row, col)."""
    s = row * CELL_DEG - 90.0
    w = col * CELL_DEG - 180.0
    return (s, w, s + CELL_DEG, w + CELL_DEG)


def cell_of(lat, lon):
    return (int(math.floor((lat + 90.0) / CELL_DEG)), int(math.floor((lon + 180.0) / CELL_DEG)))


def fetch_land(box, release, bucket=None, filesystem=None):
    """Overture's coastline land touching box, as WKB geometries."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    import route_bake as rb
    s3 = filesystem or pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset("%s/release/%s/theme=base/type=land" % (bucket or rb.OVERTURE_BUCKET, release), filesystem=s3, format="parquet")
    south, west, north, east = box
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south)
         & (pc.field("subtype") == "land") & (pc.field("class") == "land"))
    return [r["geometry"] for r in d.to_table(columns=["geometry"], filter=f).to_pylist()]


def clip(ring, box):
    """Sutherland-Hodgman: ring [(lon, lat)] cut to box (south, west, north, east), [] if nothing is left."""
    s, w, n, e = box
    edges = [(lambda p: p[0] >= w, lambda a, b: _at_x(a, b, w)), (lambda p: p[0] <= e, lambda a, b: _at_x(a, b, e)),
             (lambda p: p[1] >= s, lambda a, b: _at_y(a, b, s)), (lambda p: p[1] <= n, lambda a, b: _at_y(a, b, n))]
    out = list(ring)
    if len(out) > 1 and out[0] == out[-1]:
        out = out[:-1]
    for inside, cross in edges:
        if not out:
            break
        src, out = out, []
        prev = src[-1]
        for p in src:
            if inside(p):
                if not inside(prev):
                    out.append(cross(prev, p))
                out.append(p)
            elif inside(prev):
                out.append(cross(prev, p))
            prev = p
    return out if len(out) >= 3 else []


def _at_x(a, b, x):
    t = (x - a[0]) / (b[0] - a[0])
    return (x, a[1] + t * (b[1] - a[1]))


def _at_y(a, b, y):
    t = (y - a[1]) / (b[1] - a[1])
    return (a[0] + t * (b[0] - a[0]), y)


def _metres(ring, lat0):
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    return [(lon * m_lon, lat * m_lat) for lon, lat in ring]


def area(pts):
    """The area (square units) of ring pts [(x, y)]."""
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i - 1]
        x1, y1 = pts[i]
        a += x0 * y1 - x1 * y0
    return abs(a) / 2.0


def _flat(ring):
    """A ring [(lon, lat)] as [lat, lon, dlat, dlon, ...] in 1e-5 degrees (each point after the first a step)."""
    flat = []
    last = None
    for lon, lat in ring:
        q = (round(lat * SCALE), round(lon * SCALE))
        if last is None:
            flat += [q[0], q[1]]
        elif q != last:
            flat += [q[0] - last[0], q[1] - last[1]]
        else:
            continue
        last = q
    return flat if len(flat) >= 6 else None


def cell_coast(geometries, row, col):
    """The coast of cell (row, col) from Overture's land geometries (WKB) round it."""
    import land_bake
    box = cell_box(row, col)
    lat0 = (box[0] + box[2]) / 2.0
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    box_area = (box[2] - box[0]) * m_lat * (box[3] - box[1]) * m_lon
    rings, holes = [], []
    land_area = 0.0
    for wkb in geometries:
        try:
            polys = land_bake.parse_geometry(wkb)
        except (ValueError, struct.error):
            continue
        for poly in polys:
            for k, ring in enumerate(poly):
                cut = clip(ring, box)
                if not cut:
                    continue
                pts = _metres(cut, lat0)
                a = area(pts)
                if a < MIN_AREA:
                    continue
                kept = sketch_bake.simplify(pts + [pts[0]], TOLERANCE)[:-1]
                if len(kept) < 3:
                    continue
                back = [(x / m_lon, y / m_lat) for x, y in kept]
                flat = _flat(back)
                if flat is None:
                    continue
                if k == 0:
                    rings.append(flat)
                    land_area += a
                else:
                    holes.append(flat)
                    land_area -= a
    cell = "%d_%d" % (row, col)
    if not rings:
        return {"cell": cell, "land": "none"}
    if not holes and land_area > box_area * 0.9995:
        return {"cell": cell, "land": "all"}
    return {"cell": cell, "land": {"rings": rings, "holes": holes}}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("lat", type=float, nargs="?")
    ap.add_argument("lon", type=float, nargs="?")
    ap.add_argument("--square", nargs=2, type=float, metavar=("LAT", "LON"), help="every cell of the 1 degree square at LAT, LON")
    ap.add_argument("--cells", help="with --square, only these cells (ROW_COL,...)")
    ap.add_argument("--release")
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    import route_bake as rb
    release = args.release or rb.latest_release()
    if args.square:
        lat, lon = math.floor(args.square[0]), math.floor(args.square[1])
        geoms = fetch_land((lat, lon, lat + 1.0, lon + 1.0), release)
        only = set(args.cells.split(",")) if args.cells else None
        os.makedirs(args.out, exist_ok=True)
        r0, c0 = cell_of(lat + 1e-9, lon + 1e-9)
        for r in range(r0, r0 + 4):
            for c in range(c0, c0 + 4):
                if only is not None and "%d_%d" % (r, c) not in only:
                    continue
                coast = cell_coast(geoms, r, c)
                with open(os.path.join(args.out, "%s.coast" % coast["cell"]), "w") as f:
                    f.write(json.dumps(coast, separators=(",", ":")) + "\n")
        return 0
    if args.lat is None or args.lon is None:
        ap.error("a cell's LAT LON, or --square")
    row, col = cell_of(args.lat, args.lon)
    coast = cell_coast(fetch_land(cell_box(row, col), release), row, col)
    text = json.dumps(coast, separators=(",", ":"))
    if args.out:
        with open(args.out, "w") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
