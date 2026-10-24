#!/usr/bin/env python3
"""The bridges and tunnels of a cell: where a road is carried over a valley or a river, or under a hill, as spans
from one end to the other (Overture's road_flags is_bridge and is_tunnel, which cover part of a segment or all of it).
The game lays a planned road's bridges level between their ends, over the land rather than on a bank of it.

    python3 tools/span_bake.py LAT LON [--release R] [--out FILE]     # the cell at LAT, LON: {"cell", "spans"}
    python3 tools/span_bake.py --square LAT LON --out DIR [...]       # every cell of a 1 degree square, fetched once

A cell's spans: {"cell": "ROW_COL", "spans": [[kind, lat0, lon0, lat1, lon1], ...]}, kind 0 a bridge, 1 a tunnel, the
ends in 1e-5 degrees; the spans of the segments that start in the cell (so each is had once), MIN_M long or more (a
culvert's bridge of a couple of metres is ridden as road). They go into the cell's block of the sketch
(sketch_bake.py --spans) as "spans".
"""
import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import sketch_bake  # noqa: E402

KINDS = {"is_bridge": 0, "is_tunnel": 1}
# Spans shorter than this (m) are left out.
MIN_M = 10.0
SCALE = sketch_bake.SCALE


def fetch_segments(box, release, bucket=None, filesystem=None):
    """Overture's road segments touching box that a ride can take, with a bridge or a tunnel on them: [(geometry WKB,
    road_flags)]."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    import route_bake as rb
    s3 = filesystem or pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset("%s/release/%s/theme=transportation/type=segment" % (bucket or rb.OVERTURE_BUCKET, release),
                   filesystem=s3, format="parquet")
    south, west, north, east = box
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south)
         & (pc.field("subtype") == "road") & pc.field("road_flags").is_valid())
    rows = d.to_table(columns=["geometry", "road_flags", "class"], filter=f).to_pylist()
    # (only the roads a ride can take: a footbridge or a cycle path's tunnel never lies under a planned road)
    return [(r["geometry"], r["road_flags"]) for r in rows if r.get("class") in rb.CLASSES]


def _along(line, lat0):
    """Cumulative distance (m) along line [(lon, lat)]."""
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    cum = [0.0]
    for (x0, y0), (x1, y1) in zip(line, line[1:]):
        cum.append(cum[-1] + math.hypot((x1 - x0) * m_lon, (y1 - y0) * m_lat))
    return cum


def _at(line, cum, d):
    """The point (lon, lat) d metres along line."""
    for i in range(len(line) - 1):
        if cum[i + 1] >= d:
            seg = cum[i + 1] - cum[i]
            t = (d - cum[i]) / seg if seg > 0 else 0.0
            return (line[i][0] + (line[i + 1][0] - line[i][0]) * t, line[i][1] + (line[i + 1][1] - line[i][1]) * t)
    return line[-1]


def spans_of(geometry, flags):
    """The bridge and tunnel spans of one segment: [(kind, (lon0, lat0), (lon1, lat1), length m)]."""
    import route_bake as rb
    lines = rb.parse_wkb(geometry)
    if not lines:
        return []
    line = [p for ln in lines for p in ln]
    if len(line) < 2:
        return []
    cum = _along(line, line[0][1])
    total = cum[-1]
    out = []
    for flag in flags or []:
        between = flag.get("between") or [0.0, 1.0]
        for value in flag.get("values") or []:
            if value not in KINDS:
                continue
            d0, d1 = float(between[0]) * total, float(between[1]) * total
            if d1 - d0 < MIN_M:
                continue
            out.append((KINDS[value], _at(line, cum, d0), _at(line, cum, d1), d1 - d0))
    return out


def cell_spans(rows, row, col):
    """The spans that start in cell (row, col), from fetch_segments' rows round it."""
    s, w, n, e = coast_bake.cell_box(row, col)
    out = []
    for geometry, flags in rows:
        for kind, a, b, _ in spans_of(geometry, flags):
            if s <= a[1] < n and w <= a[0] < e:
                out.append([kind, round(a[1] * SCALE), round(a[0] * SCALE), round(b[1] * SCALE), round(b[0] * SCALE)])
    out.sort()
    return {"cell": "%d_%d" % (row, col), "spans": out}


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
        rows = fetch_segments((lat, lon, lat + 1.0, lon + 1.0), release)
        only = set(args.cells.split(",")) if args.cells else None
        os.makedirs(args.out, exist_ok=True)
        r0, c0 = coast_bake.cell_of(lat + 1e-9, lon + 1e-9)
        for r in range(r0, r0 + 4):
            for c in range(c0, c0 + 4):
                if only is not None and "%d_%d" % (r, c) not in only:
                    continue
                spans = cell_spans(rows, r, c)
                with open(os.path.join(args.out, "%s.spans" % spans["cell"]), "w") as f:
                    f.write(json.dumps(spans, separators=(",", ":")) + "\n")
        return 0
    if args.lat is None or args.lon is None:
        ap.error("a cell's LAT LON, or --square")
    row, col = coast_bake.cell_of(args.lat, args.lon)
    spans = cell_spans(fetch_segments(coast_bake.cell_box(row, col), release), row, col)
    text = json.dumps(spans, separators=(",", ":"))
    if args.out:
        with open(args.out, "w") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
