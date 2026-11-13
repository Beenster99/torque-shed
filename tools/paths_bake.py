#!/usr/bin/env python3
"""The ways beside the roads that are seen but not ridden, in a cell (OSM stage 4 of the Unreal port's Ride UK plan):
footpaths and pavements' own ways, bridleways, cycleways, pedestrian streets and steps, kept within REACH_M of a road
a ride can take. The game draws them as ribbons on the ground; its route planner never knows them.

    python3 tools/paths_bake.py LAT LON [--release R] [--out FILE]     # the cell at LAT, LON

A cell's paths (FORMAT 1):

    {"format": 1, "cell": "ROW_COL", "release": R, "classes": CLASSES_HASH,
     "kinds": [kind, ...], "surfaces": ["", surface, ...],
     "lines": [[kind, width, surface, lat, lon, dlat, dlon, ...], ...]}

kind is an index into "kinds" (the same in every cell), surface into "surfaces" (0 the map says nothing; the game
takes the kind's own), width metres where the map gives it, else null. lat and lon are in 1e-5 degrees, each point
after a line's first the step from the one before, every line cut to the cell's box (as feature_bake.py's).

classes is the hash of CLASSES and FORMAT: the world's store bakes a cell's paths again only when it or the Overture
release changes. A cell's go into a file of their own in the world's store (paths/cROW_COL.json, its hash in the
index's "paths").

Overture Maps is ODbL (OpenStreetMap's data by way of it, and others'). Needs numpy and pyarrow. No API keys.
"""
import argparse
import hashlib
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import feature_bake as fb  # noqa: E402
import ground_bake as gb  # noqa: E402
import sketch_bake  # noqa: E402

FORMAT = 1
SCALE = sketch_bake.SCALE
# Overture road classes (transportation/segment, subtype road) -> the kind drawn.
CLASSES = {"footway": "footway", "path": "path", "bridleway": "bridleway", "cycleway": "cycleway",
           "pedestrian": "pedestrian", "steps": "steps"}
KINDS = sorted(set(CLASSES.values()))
# Kept within this far (m) of a road a ride can take.
REACH_M = 120.0
TOLERANCE = 1.5
# A sidewalk mapped as its own way runs beside its road the whole way: the game draws the road's own pavement there.
SKIP_SUBCLASSES = {"sidewalk"}


def classes_hash():
    blob = json.dumps({"format": FORMAT, "classes": CLASSES, "reach": REACH_M, "skip": sorted(SKIP_SUBCLASSES)},
                      sort_keys=True)
    return hashlib.sha1(blob.encode()).hexdigest()[:12]


def fetch(box, release, bucket=None, filesystem=None, log=print):
    """Overture's path segments touching box, as plain dicts."""
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
         & (pc.field("subtype") == "road") & pc.field("class").isin(sorted(CLASSES)))
    cols = [c for c in ("id", "geometry", "class", "subclass", "road_surface", "width_rules", "source_tags") if c in d.schema.names]
    rows = d.to_table(columns=cols, filter=f).to_pylist()
    log("paths: %d segments in the box" % len(rows))
    return rows


def surface_of(row):
    for rule in row.get("road_surface") or []:
        if rule.get("between") is None and rule.get("value"):
            return str(rule["value"])
    return ""


def width_of(row):
    for rule in row.get("width_rules") or []:
        if rule.get("between") is None and fb.number(rule.get("value")) is not None:
            return fb.number(rule.get("value"))
    return fb.number(dict(row.get("source_tags") or []).get("width"))


def cell_paths(rows, field, row, col, release=""):
    """The paths of cell (row, col) from fetch's rows round it, only those near the roads in `field` (a
    ground_bake.RoadField, or None: no roads, so none)."""
    box = coast_bake.cell_box(row, col)
    lat0 = (box[0] + box[2]) / 2.0
    kind_ids = {k: i for i, k in enumerate(KINDS)}
    lines = []
    for r in rows:
        kind = CLASSES.get(str(r.get("class")))
        if kind is None or str(r.get("subclass") or "") in SKIP_SUBCLASSES or field is None:
            continue
        try:
            _, lns, _ = fb.parse_any(r["geometry"])
        except (ValueError, struct.error):
            continue
        for line in lns:
            for run in fb.clip_line(line, box):
                if not field.near(run, REACH_M):
                    continue
                f = fb.flat(gb.simple(run, lat0, TOLERANCE))
                if len(f) >= 4:
                    lines.append([kind_ids[kind], width_of(r), surface_of(r)] + f)
    lines.sort(key=lambda ln: (ln[0], ln[3:], ln[2], -1 if ln[1] is None else ln[1]))
    surfaces = [""]
    for ln in lines:
        if ln[2] and ln[2] not in surfaces:
            surfaces.append(ln[2])
        ln[2] = surfaces.index(ln[2]) if ln[2] else 0
    return {"format": FORMAT, "cell": "%d_%d" % (row, col), "release": release, "classes": classes_hash(),
            "kinds": KINDS, "surfaces": surfaces, "lines": lines}


def bake_cell(row, col, release, log=print):
    import stream_bake
    box = coast_bake.cell_box(row, col)
    pad = 0.01
    roads = stream_bake.fetch_roads((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad), release)
    field = gb.RoadField(roads, box, REACH_M) if roads else None
    return cell_paths(fetch(box, release, log=log), field, row, col, release)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("lat", type=float)
    ap.add_argument("lon", type=float)
    ap.add_argument("--release", help="Overture release, default the latest")
    ap.add_argument("--out", help="file to write (default paths/cROW_COL.json)")
    args = ap.parse_args(argv)
    import route_bake as rb
    release = args.release or rb.latest_release()
    row, col = coast_bake.cell_of(args.lat, args.lon)
    got = bake_cell(row, col, release)
    out = args.out or os.path.join("paths", "c%d_%d.json" % (row, col))
    gb.write(out, got)
    kinds = {}
    for ln in got["lines"]:
        kinds[got["kinds"][ln[0]]] = kinds.get(got["kinds"][ln[0]], 0) + 1
    print("wrote %s: %.2f MB, %s" % (out, os.path.getsize(out) / 1e6, kinds))


if __name__ == "__main__":
    sys.exit(main())
