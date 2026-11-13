#!/usr/bin/env python3
"""The ground between the roads in a cell (OSM stage 4 of the Unreal port's Ride UK plan): water as true shapes (lakes,
ponds, reservoirs, river banks, basins) and the ditches and drains beside the roads, beaches, sand, dunes and mud,
the outlines of woods, scrub, heath and wetland, single trees and tree rows, the ground's use between buildings
(gardens, yards, farmyards, building sites), parks, playgrounds and pitches, car parks, and the national parks and
reserves a ride passes through. The cell's land cover grid (land_bake.py) blurs these into its squares; this keeps
their shapes, so the game can lay the ground to them.

    python3 tools/ground_bake.py LAT LON [--release R] [--out FILE]     # the cell at LAT, LON

A cell's ground (FORMAT 1):

    {"format": 1, "cell": "ROW_COL", "release": R, "classes": CLASSES_HASH,
     "kinds": [kind, ...], "names": ["", name, ...], "words": ["", word, ...],
     "areas":  [[kind, word, name, lat, lon, dlat, dlon, ...], ...],
     "lines":  [[kind, width, word, lat, lon, dlat, dlon, ...], ...],
     "points": [[kind, word, lat, lon], ...]}

kind is an index into "kinds" (CLASSES' names, the same in every cell), name into "names" (0 none: only parks, water
and protected land keep theirs), word into "words" (0 none): a pitch's sport, a tree's species (or genus, or leaf
type), a car park's surface. width is metres where the map gives it, else null. lat and lon are in 1e-5 degrees,
each point after a line's or an area's first the step from the one before (as feature_bake.py's). An area is its
outer ring, without its holes or its last point, cut to the cell's box; a line is cut to the box; a point is in the
cell it stands in.

Each kind is kept within its REACH of a road a ride can take (None: wherever it is in the cell), its shape kept to
within its TOLERANCE metres, water only above WATER_MIN_M2. The protected areas keep only a coarse outline and a
name: the game names them on the planner.

classes is the hash of CLASSES and FORMAT: the world's store bakes a cell's ground again only when it or the Overture
release changes. A cell's goes into a file of its own in the world's store (ground/cROW_COL.json, its hash in the
index's "grounds").

Overture Maps is ODbL (OpenStreetMap's data by way of it, and others'). Needs numpy and pyarrow. No API keys.
"""
import argparse
import hashlib
import json
import math
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import feature_bake as fb  # noqa: E402
import sketch_bake  # noqa: E402

FORMAT = 1
SCALE = sketch_bake.SCALE
# Overture (theme, type, column) -> {class: (kind, reach m or None, tolerance m, geometry: "area" | "line" | "point")}.
CLASSES = {
    ("base", "water", "class"): {
        "lake": ("lake", None, 1.5, "area"), "pond": ("pond", None, 1.0, "area"),
        "reservoir": ("reservoir", None, 1.5, "area"), "river": ("river", None, 1.5, "area"),
        "riverbank": ("river", None, 1.5, "area"), "basin": ("basin", None, 1.0, "area"),
        "canal": ("canal", None, 1.0, "area"), "dock": ("basin", None, 1.0, "area"),
        "ditch": ("ditch", 100.0, 1.5, "line"), "drain": ("drain", 100.0, 1.5, "line"),
    },
    ("base", "land", "class"): {
        "beach": ("beach", None, 2.0, "area"), "sand": ("sand", None, 2.0, "area"), "dune": ("dune", None, 2.0, "area"),
        "shingle": ("shingle", None, 2.0, "area"), "mud": ("mud", None, 3.0, "area"),
        "forest": ("wood", 500.0, 3.0, "area"), "wood": ("wood", 500.0, 3.0, "area"),
        "scrub": ("scrub", 500.0, 3.0, "area"), "heath": ("heath", 500.0, 3.0, "area"),
        "wetland": ("wetland", 500.0, 3.0, "area"), "marsh": ("wetland", 500.0, 3.0, "area"),
        "swamp": ("wetland", 500.0, 3.0, "area"), "bog": ("wetland", 500.0, 3.0, "area"),
        "reedbed": ("wetland", 500.0, 3.0, "area"), "tree": ("tree", 60.0, 0.5, "point"),
        "tree_row": ("tree_row", 80.0, 1.0, "line"),
    },
    ("base", "land_use", "class"): {
        "residential": ("residential", 300.0, 4.0, "area"), "retail": ("retail", 300.0, 3.0, "area"),
        "commercial": ("commercial", 300.0, 3.0, "area"), "industrial": ("industrial", 300.0, 3.0, "area"),
        "farmyard": ("farmyard", 300.0, 3.0, "area"), "construction": ("construction", 300.0, 3.0, "area"),
        "brownfield": ("brownfield", 300.0, 3.0, "area"),
        "park": ("park", 300.0, 2.0, "area"), "playground": ("playground", 300.0, 1.5, "area"),
        "pitch": ("pitch", 300.0, 1.0, "area"), "recreation_ground": ("recreation_ground", 300.0, 2.0, "area"),
        "village_green": ("village_green", 300.0, 2.0, "area"),
        "national_park": ("national_park", None, 50.0, "area"), "nature_reserve": ("nature_reserve", None, 50.0, "area"),
        "protected_landscape_area": ("protected_landscape", None, 50.0, "area"), "common": ("common", None, 20.0, "area"),
    },
    ("base", "infrastructure", "class"): {
        "parking": ("car_park", 150.0, 1.0, "area"), "parking_lot": ("car_park", 150.0, 1.0, "area"),
        "multi-storey": ("car_park", 150.0, 1.0, "area"),
    },
}
KINDS = sorted({v[0] for table in CLASSES.values() for v in table.values()})
# (a private garden is left out: thousands in a city, and the residential ground round it is lawn already)
# The kinds that keep their names (the rest are many, and nothing names them).
NAMED = {"lake", "reservoir", "river", "canal", "park", "recreation_ground", "village_green", "national_park",
         "nature_reserve", "protected_landscape", "common"}
# A water shape smaller than this (m2) is left out: a garden pond, a puddle someone mapped.
WATER_MIN_M2 = 100.0
WATER_KINDS = {"lake", "pond", "reservoir", "river", "basin", "canal"}
# The source tags that give a kind its word, in order.
WORD_TAGS = {"pitch": ("sport",), "tree": ("species", "genus", "leaf_type"), "tree_row": ("species", "genus", "leaf_type"),
             "wood": ("leaf_type",), "car_park": ("surface", "parking")}
COLUMNS = ["id", "geometry", "subtype", "class", "names", "source_tags"]
FIELD_M = 50.0   # (the roads' reach is worked out on a grid of squares this big)


def classes_hash():
    blob = json.dumps({"format": FORMAT, "classes": {"/".join(k): v for k, v in sorted(CLASSES.items())},
                       "water_min": WATER_MIN_M2}, sort_keys=True)
    return hashlib.sha1(blob.encode()).hexdigest()[:12]


class RoadField:
    """How far each FIELD_M square of a box is from the nearest road a ride can take (about: counted in squares, the
    diagonal as one), out to `reach` metres: whether a place is within a kind's REACH of one."""

    def __init__(self, roads, box, reach=500.0):
        import route_bake as rb
        s, w, n, e = box
        self.box = box
        self.m_lat, self.m_lon = sketch_bake.metres_per_degree((s + n) / 2.0)
        self.nx = int(math.ceil((e - w) * self.m_lon / FIELD_M)) + 1
        self.nz = int(math.ceil((n - s) * self.m_lat / FIELD_M)) + 1
        steps = int(math.ceil(reach / FIELD_M)) + 1
        self.far = steps + 1
        dist = np.full((self.nz, self.nx), self.far, dtype=np.int16)
        on = np.zeros((self.nz, self.nx), dtype=bool)
        for wkb in roads:
            for line in rb.parse_wkb(wkb) or []:
                for (x0, y0), (x1, y1) in zip(line, line[1:]):
                    seg = math.hypot((x1 - x0) * self.m_lon, (y1 - y0) * self.m_lat)
                    k = max(1, int(seg / (FIELD_M * 0.5)))
                    t = np.linspace(0.0, 1.0, k + 1)
                    gx, gz = self._square(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
                    ok = (gx >= 0) & (gx < self.nx) & (gz >= 0) & (gz < self.nz)
                    on[gz[ok], gx[ok]] = True
        dist[on] = 0
        grown = on.copy()
        for d in range(1, steps + 1):
            g = grown.copy()
            g[1:, :] |= grown[:-1, :]
            g[:-1, :] |= grown[1:, :]
            g[:, 1:] |= grown[:, :-1]
            g[:, :-1] |= grown[:, 1:]
            g[1:, 1:] |= grown[:-1, :-1]
            g[:-1, :-1] |= grown[1:, 1:]
            g[1:, :-1] |= grown[:-1, 1:]
            g[:-1, 1:] |= grown[1:, :-1]
            dist[g & ~grown] = d
            grown = g
        self.dist = dist

    def _square(self, lon, lat):
        s, w, _, _ = self.box
        return (np.floor((np.asarray(lon) - w) * self.m_lon / FIELD_M).astype(int),
                np.floor((np.asarray(lat) - s) * self.m_lat / FIELD_M).astype(int))

    def near(self, pts, reach):
        """Whether any of pts [(lon, lat)] is within about `reach` m of a road (None: always)."""
        if reach is None:
            return True
        if not pts:
            return False
        a = np.asarray(pts, dtype=float)
        gx, gz = self._square(a[:, 0], a[:, 1])
        ok = (gx >= 0) & (gx < self.nx) & (gz >= 0) & (gz < self.nz)
        if not ok.any():
            return False
        return bool((self.dist[gz[ok], gx[ok]] * FIELD_M <= reach).any())


def kind_of(key, row):
    """(kind, reach, tolerance, geometry) of a row, or None."""
    return CLASSES.get(key, {}).get(str(row.get("class")))


def word_of(kind, row):
    tags = dict(row.get("source_tags") or [])
    for t in WORD_TAGS.get(kind, ()):
        if tags.get(t):
            return str(tags[t]).split(";")[0].strip().lower()
    return ""


def width_of(row):
    return fb.number(dict(row.get("source_tags") or []).get("width"))


def simple(pts, lat0, tol, closed=False):
    """pts [(lon, lat)] simplified to within tol metres (a ring as two halves, so its ends stay put)."""
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    xy = [(lon * m_lon, lat * m_lat) for lon, lat in pts]
    if closed and len(xy) > 4:
        half = len(xy) // 2
        kept = sketch_bake.simplify(xy[:half + 1], tol)[:-1] + sketch_bake.simplify(xy[half:] + xy[:1], tol)[:-1]
    else:
        kept = sketch_bake.simplify(xy, tol)
    return [(x / m_lon, y / m_lat) for x, y in kept]


def ring_area_m2(ring, lat0):
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    a = 0.0
    for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1]):
        a += (x0 * m_lon) * (y1 * m_lat) - (x1 * m_lon) * (y0 * m_lat)
    return abs(a) * 0.5


def fetch(box, release, bucket=None, filesystem=None, log=print):
    """Every row of CLASSES touching box: [(source key, row)]."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    import route_bake as rb
    s3 = filesystem or pafs.S3FileSystem(anonymous=True, region="us-west-2")
    south, west, north, east = box
    out = []
    for key in sorted(CLASSES):
        theme, kind, column = key
        d = ds.dataset("%s/release/%s/theme=%s/type=%s" % (bucket or rb.OVERTURE_BUCKET, release, theme, kind),
                       filesystem=s3, format="parquet")
        f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
             & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south)
             & pc.field(column).isin(sorted(CLASSES[key])))
        cols = [c for c in COLUMNS if c in d.schema.names]
        n = 0
        for batch in d.to_batches(columns=cols, filter=f, batch_size=fb.BATCH, **fb.READ):
            for r in batch.to_pylist():
                if r.get("geometry"):
                    tags = r.get("source_tags")
                    if tags:
                        r["source_tags"] = [(k, v) for k, v in tags if k in ("sport", "species", "genus", "leaf_type",
                                                                            "surface", "parking", "width")]
                    out.append((key, r))
                    n += 1
        log("ground: %s/%s %d rows" % (theme, kind, n))
    return out


def cell_ground(rows, field, row, col, release=""):
    """The ground of cell (row, col) from fetch's rows round it, the near kinds only near the roads in `field` (a
    RoadField, or None: no roads, so none of them)."""
    box = coast_bake.cell_box(row, col)
    lat0 = (box[0] + box[2]) / 2.0
    kind_ids = {k: i for i, k in enumerate(KINDS)}
    names, words = [""], [""]

    def index(table, v):
        if not v:
            return 0
        if v not in table:
            table.append(v)
        return table.index(v)

    def near(pts, reach):
        return reach is None or (field is not None and field.near(pts, reach))

    areas, lines, points = [], [], []
    for key, r in rows:
        got = kind_of(key, r)
        if got is None:
            continue
        kind, reach, tol, geom = got
        try:
            pts, lns, rings = fb.parse_any(r["geometry"])
        except (ValueError, struct.error):
            continue
        k = kind_ids[kind]
        word = word_of(kind, r)
        name = fb.english_or_primary(r.get("names")) if kind in NAMED else None
        if geom == "point":
            for lon, lat in pts:
                if fb.inside(lon, lat, box) and near([(lon, lat)], reach):
                    points.append([k, word, round(lat * SCALE), round(lon * SCALE)])
        elif geom == "line":
            for line in lns:
                for run in fb.clip_line(line, box):
                    if not near(run, reach):
                        continue
                    f = fb.flat(simple(run, lat0, tol))
                    if len(f) >= 4:
                        lines.append([k, width_of(r), word] + f)
        else:
            for ring in rings:
                if kind in WATER_KINDS and ring_area_m2(ring, lat0) < WATER_MIN_M2:
                    continue
                cut = coast_bake.clip(ring, box)
                if not cut or not near(cut, reach):
                    continue
                f = fb.flat(simple(cut, lat0, tol, closed=True))
                if len(f) >= 6:
                    areas.append([k, word, name or ""] + f)
    # In a fixed order (the same data bakes to the same bytes), the words and names numbered in it.
    areas.sort(key=lambda a: (a[0], a[3:], a[1], a[2]))
    lines.sort(key=lambda ln: (ln[0], ln[3:], ln[2], -1 if ln[1] is None else ln[1]))
    points.sort(key=lambda p: (p[0], p[2], p[3], p[1]))
    for a in areas:
        a[1] = index(words, a[1])
        a[2] = index(names, a[2])
    for ln in lines:
        ln[2] = index(words, ln[2])
    for p in points:
        p[1] = index(words, p[1])
    return {"format": FORMAT, "cell": "%d_%d" % (row, col), "release": release, "classes": classes_hash(),
            "kinds": KINDS, "names": names, "words": words, "areas": areas, "lines": lines, "points": points}


def counts(got):
    out = {}
    for group in ("areas", "lines", "points"):
        for r in got[group]:
            k = got["kinds"][r[0]]
            out[k] = out.get(k, 0) + 1
    return out


def bake_cell(row, col, release, log=print):
    import stream_bake
    box = coast_bake.cell_box(row, col)
    pad = 0.01
    roads = stream_bake.fetch_roads((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad), release)
    field = RoadField(roads, box, max(r for t in CLASSES.values() for _, r, _, _ in t.values() if r is not None)) if roads else None
    return cell_ground(fetch(box, release, log=log), field, row, col, release)


def write(path, got):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        json.dump(got, f, separators=(",", ":"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("lat", type=float)
    ap.add_argument("lon", type=float)
    ap.add_argument("--release", help="Overture release, default the latest")
    ap.add_argument("--out", help="file to write (default ground/cROW_COL.json)")
    args = ap.parse_args(argv)
    import route_bake as rb
    release = args.release or rb.latest_release()
    row, col = coast_bake.cell_of(args.lat, args.lon)
    got = bake_cell(row, col, release)
    out = args.out or os.path.join("ground", "c%d_%d.json" % (row, col))
    write(out, got)
    print("wrote %s: %.2f MB, %s" % (out, os.path.getsize(out) / 1e6, counts(got)))


if __name__ == "__main__":
    sys.exit(main())
