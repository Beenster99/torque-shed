#!/usr/bin/env python3
"""The rivers and streams of a cell, as lines: the becks and burns the land cover's water polygons don't hold (they're
mapped as a line down the middle, OpenStreetMap's waterways by way of Overture's base/water), where a road a ride can
take runs near enough to see them. The game draws them as water beside and under the road (RealLand), the land their bed.

    python3 tools/stream_bake.py LAT LON [--release R] [--out FILE]     # the cell at LAT, LON: {"cell", "streams"}
    python3 tools/stream_bake.py --square LAT LON --out DIR [...]       # every cell of a 1 degree square, fetched once
    python3 tools/stream_bake.py --box S W N E --out FILE [...]         # a bundled region's: {"streams"} of its cells

A cell's streams: {"cell": "ROW_COL", "streams": [[kind, lat, lon, dlat, dlon, ...], ...]}, kind 0 a river, 1 a stream,
2 a canal (drains and ditches are left out), each line's first point whole and each after it the step from the one before, in 1e-5 degrees (as the
sketch has its roads, sketch_bake.py). Only the stretches within NEAR_M of a road a ride can take are kept (the rest
never shows), cut to the cell's box and simplified to within TOLERANCE. A cell's go into a file of
their own in the world's store (stream/cROW_COL.json, its hash in the index's "streams"), fetched for a journey on it:
there are far too many for the sketch's blocks the Route planner TV fetches.
"""
import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import sketch_bake  # noqa: E402

KINDS = {"river": 0, "stream": 1, "canal": 2}
# Only the stretches this near (m) a road a ride can take are kept.
NEAR_M = 250.0
# How far (m) the simplified line may stray from Overture's.
TOLERANCE = 4.0
SCALE = sketch_bake.SCALE
# The grid the roads are filed in to find the near ones (m).
GRID_M = 200.0


def fetch_waterways(box, release, bucket=None, filesystem=None):
    """Overture's water lines touching box: [(kind, geometry WKB)]."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    import route_bake as rb
    s3 = filesystem or pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset("%s/release/%s/theme=base/type=water" % (bucket or rb.OVERTURE_BUCKET, release), filesystem=s3,
                   format="parquet")
    south, west, north, east = box
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south)
         & pc.field("class").isin(list(KINDS)))
    rows = d.to_table(columns=["geometry", "class"], filter=f).to_pylist()
    # (only lines: a river mapped as an area is in the land cover's water already)
    return [(KINDS[r["class"]], r["geometry"]) for r in rows if r["geometry"] and r["geometry"][1] in (2, 5)]


def fetch_roads(box, release, bucket=None, filesystem=None):
    """The lines (WKB) of Overture's road segments touching box that a ride can take."""
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
         & (pc.field("subtype") == "road") & pc.field("class").isin(list(rb.CLASSES)))
    return [r["geometry"] for r in d.to_table(columns=["geometry"], filter=f).to_pylist()]


class RoadGrid:
    """The roads' points (and the points along their longer stretches) filed in a grid, to find whether a place is
    within NEAR_M of one."""

    def __init__(self, roads, lat0):
        import route_bake as rb
        self.m_lat, self.m_lon = sketch_bake.metres_per_degree(lat0)
        self.cells = set()
        reach = int(math.ceil(NEAR_M / GRID_M))
        for wkb in roads:
            for line in rb.parse_wkb(wkb) or []:
                for (x0, y0), (x1, y1) in zip(line, line[1:]):
                    seg = math.hypot((x1 - x0) * self.m_lon, (y1 - y0) * self.m_lat)
                    steps = max(1, int(seg / (GRID_M * 0.5)))
                    for k in range(steps + 1):
                        t = k / steps
                        gx, gy = self._cell(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
                        for dy in range(-reach, reach + 1):
                            for dx in range(-reach, reach + 1):
                                self.cells.add((gx + dx, gy + dy))

    def _cell(self, lon, lat):
        return int(math.floor(lon * self.m_lon / GRID_M)), int(math.floor(lat * self.m_lat / GRID_M))

    def near(self, lon, lat):
        return self._cell(lon, lat) in self.cells


def _flat(kind, pts):
    """A line [(lon, lat)] as [kind, lat, lon, dlat, dlon, ...] in 1e-5 degrees, or None when it's a point."""
    out = [kind]
    last = None
    for lon, lat in pts:
        q = (round(lat * SCALE), round(lon * SCALE))
        if last is None:
            out += [q[0], q[1]]
        elif q != last:
            out += [q[0] - last[0], q[1] - last[1]]
        else:
            continue
        last = q
    return out if len(out) >= 5 else None


def cell_streams(waterways, grid, row, col):
    """The streams of cell (row, col) from fetch_waterways' rows round it, near the roads in `grid` (a RoadGrid)."""
    import route_bake as rb
    s, w, n, e = coast_bake.cell_box(row, col)
    lat0 = (s + n) / 2.0
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    out = []
    for kind, wkb in waterways:
        for line in rb.parse_wkb(wkb) or []:
            # The runs of it inside the cell and near a road (each kept with its points either side, so it reaches
            # the cell's edge and doesn't stop short of the road's reach).
            run = []
            for k, (lon, lat) in enumerate(line):
                keep = s <= lat < n and w <= lon < e and grid.near(lon, lat)
                if keep:
                    if not run and k > 0:
                        run.append(line[k - 1])
                    run.append((lon, lat))
                elif run:
                    run.append((lon, lat))
                    out.append((kind, run))
                    run = []
            if len(run) >= 2:
                out.append((kind, run))
    lines = []
    for kind, run in out:
        pts = [(lon * m_lon, lat * m_lat) for lon, lat in run]
        kept = sketch_bake.simplify(pts, TOLERANCE)
        flat = _flat(kind, [(x / m_lon, y / m_lat) for x, y in kept])
        if flat is not None:
            lines.append(flat)
    lines.sort()
    return {"cell": "%d_%d" % (row, col), "streams": lines}


def fetch_square(box, release):
    """What a square's cells' streams are made from (for a backfill, see cell_streams_of): (its roads' RoadGrid, its
    water lines)."""
    pad = 0.01   # (the roads just over the square's edge count too)
    south, west, north, east = box
    grid = RoadGrid(fetch_roads((south - pad, west - pad, north + pad, east + pad), release), (south + north) / 2.0)
    return grid, fetch_waterways(box, release)


def cell_streams_of(fetched, row, col):
    """cell_streams from fetch_square's (grid, waterways)."""
    return cell_streams(fetched[1], fetched[0], row, col)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("lat", type=float, nargs="?")
    ap.add_argument("lon", type=float, nargs="?")
    ap.add_argument("--square", nargs=2, type=float, metavar=("LAT", "LON"), help="every cell of the 1 degree square at LAT, LON")
    ap.add_argument("--box", nargs=4, type=float, metavar=("S", "W", "N", "E"), help="the cells over a box, as one list")
    ap.add_argument("--cells", help="with --square, only these cells (ROW_COL,...)")
    ap.add_argument("--release")
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    import route_bake as rb
    release = args.release or rb.latest_release()
    if args.box:
        south, west, north, east = args.box
        lines = []
        for lat in range(math.floor(south), math.floor(north) + 1):
            for lon in range(math.floor(west), math.floor(east) + 1):
                fetched = fetch_square((lat, lon, lat + 1.0, lon + 1.0), release)
                r0, c0 = coast_bake.cell_of(lat + 1e-9, lon + 1e-9)
                for r in range(r0, r0 + 4):
                    for c in range(c0, c0 + 4):
                        cs, cw, cn, ce = coast_bake.cell_box(r, c)
                        if cs < north and cn > south and cw < east and ce > west:
                            lines += cell_streams_of(fetched, r, c)["streams"]
        lines.sort()
        with open(args.out, "w") as f:
            f.write(json.dumps({"streams": lines}, separators=(",", ":")) + "\n")
        return 0
    if args.square:
        lat, lon = math.floor(args.square[0]), math.floor(args.square[1])
        fetched = fetch_square((lat, lon, lat + 1.0, lon + 1.0), release)
        only = set(args.cells.split(",")) if args.cells else None
        os.makedirs(args.out, exist_ok=True)
        r0, c0 = coast_bake.cell_of(lat + 1e-9, lon + 1e-9)
        for r in range(r0, r0 + 4):
            for c in range(c0, c0 + 4):
                if only is not None and "%d_%d" % (r, c) not in only:
                    continue
                got = cell_streams_of(fetched, r, c)
                with open(os.path.join(args.out, "%s.streams" % got["cell"]), "w") as f:
                    f.write(json.dumps(got, separators=(",", ":")) + "\n")
        return 0
    if args.lat is None or args.lon is None:
        ap.error("a cell's LAT LON, or --square")
    row, col = coast_bake.cell_of(args.lat, args.lon)
    got = cell_streams_of(fetch_square(coast_bake.cell_box(row, col), release), row, col)
    text = json.dumps(got, separators=(",", ":"))
    if args.out:
        with open(args.out, "w") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
