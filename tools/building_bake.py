#!/usr/bin/env python3
"""Every building in a cell with its true outline and height (towns stage 3): what the cells' buildings.json keeps of
each (the smallest rectangle round it, nearest a road first, up to 60,000) is enough for a village, not for a town a
rider should know again. This keeps them all, from Overture's buildings theme, as their outlines simplified to within
OUTLINE_M, with what the map says of their height, floors, roof and walls. The tall and the big (feature_bake.py's
towers: TOWER_M tall or BIG_M2 big) are left to the features' "towers", which the game draws as its skyline.

A building belongs to the cell its outline's middle is in, and to the tile of TILES x TILES in that cell its middle is
in, so the game can read a town a tile at a time. The file (JSON):

    {"v": 1, "release": RELEASE, "cell": "ROW_COL", "tiles": TILES, "classes": hash of the rules here,
     "words": ["", word, ...],
     "rows": {"TX_TZ": [building, ...], ...}}

TX counts east from the cell's west edge, TZ north from its south edge. A building is a list:

    [height_dm, min_height_dm, floors, class, roof_shape, roof_material, roof_colour, facade_material, facade_colour,
     lat, lon, dlat, dlon, dlat, dlon, ...]

heights in decimetres (-1 where the map has none: the game assumes one by class and size), floors (-1 for none),
the words as indexes into "words" (0 where the map says nothing), then the outline's points: the first in 1e-6
degrees, each next one as the step from the one before; counter-clockwise, not closed, at least three.

    python3 tools/building_bake.py ROW_COL --out FILE [--release RELEASE]"""
import argparse
import hashlib
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402
import feature_bake as fb  # noqa: E402
import sketch_bake  # noqa: E402

VERSION = 1
TILES = 8                 # a cell's tiles each way (0.03125 degrees: about 3.5 km by 2 km in Britain)
OUTLINE_M = 0.3           # how far (m) an outline may stray from the map's (corners kept; a curve's points thinned)
OUTLINE_SCALE = 1e6       # outline points in 1e-6 degrees (0.1 m)
MIN_AREA = 4.0            # m2: smaller is a shed's lean-to, a kiosk, a mapping slip
CLASS_WORDS = ("class", "roof_shape", "roof_material", "roof_color", "facade_material", "facade_color")


def classes_hash():
    """What the rules here are, so a change to them makes every cell's file again."""
    said = json.dumps({"v": VERSION, "tiles": TILES, "outline": OUTLINE_M, "min_area": MIN_AREA,
                       "towers": [fb.TOWER_M, fb.TOWER_FLOORS, fb.BIG_M2, fb.STOREY_M]}, sort_keys=True)
    return hashlib.sha256(said.encode()).hexdigest()[:12]


def outline(ring, lat0):
    """A ring [(lon, lat)] simplified to within OUTLINE_M, open, counter-clockwise; [] if too small."""
    if len(ring) > 3 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return []
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    xy = [(lon * m_lon, lat * m_lat) for lon, lat in ring]
    if len(xy) > 4:
        half = len(xy) // 2
        kept = sketch_bake.simplify(xy[:half + 1], OUTLINE_M)[:-1] + sketch_bake.simplify(xy[half:] + xy[:1], OUTLINE_M)[:-1]
    else:
        kept = xy
    if len(kept) < 3:
        return []
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(kept, kept[1:] + kept[:1])) * 0.5
    if abs(area) < MIN_AREA:
        return []
    if area < 0:
        kept = kept[::-1]
    return [(x / m_lon, y / m_lat) for x, y in kept]


def decimetres(v):
    return -1 if v is None else max(0, int(round(v * 10.0)))


class Words:
    """The words of the cell's buildings, each once ("" first: the map says nothing)."""

    def __init__(self):
        self.words = [""]
        self.at = {"": 0}

    def __call__(self, v):
        if v is None or v == "":
            return 0
        if v not in self.at:
            self.at[v] = len(self.words)
            self.words.append(v)
        return self.at[v]


def building_row(r, box, words):
    """Overture building row r as (tile key, row) if it is the cell's (its middle in box) and not a tower, else None."""
    try:
        _, _, rings = fb.parse_any(r["geometry"])
    except (ValueError, struct.error, KeyError, TypeError):
        return None
    if not rings or r.get("is_underground"):
        return None
    ring = max(rings, key=lambda q: abs(fb._ring_area(q)))
    lon, lat = fb._ring_middle(ring)
    south, west, north, east = box
    if not (south <= lat < north and west <= lon < east):
        return None
    if fb.towers_from([r], []):   # (the skyline's: drawn from the features' towers)
        return None
    kept = outline(ring, lat)
    if not kept:
        return None
    h = fb.number(r.get("height"))
    floors = fb.number(r.get("num_floors"))
    low = fb.number(r.get("min_height"))
    if low is None and fb.number(r.get("min_floor")):
        low = fb.number(r.get("min_floor")) * fb.STOREY_M
    said = [words(fb._look_word(c, r.get(c))) for c in CLASS_WORDS]
    pts = []
    last = None
    for p_lon, p_lat in kept:
        q = (round(p_lat * OUTLINE_SCALE), round(p_lon * OUTLINE_SCALE))
        if last is None:
            pts += [q[0], q[1]]
        elif q != last:
            pts += [q[0] - last[0], q[1] - last[1]]
        last = q
    if len(pts) < 6:
        return None
    tx = min(TILES - 1, int((lon - west) / (east - west) * TILES))
    tz = min(TILES - 1, int((lat - south) / (north - south) * TILES))
    row = [decimetres(h), max(0, decimetres(low)), -1 if floors is None else int(floors)] + said + pts
    return ("%d_%d" % (tx, tz), row)


def cell_buildings(rows, row, col, release=""):
    """The cell's file (see above) from Overture building rows (dicts with the theme's columns)."""
    box = cb.cell_box(row, col)
    words = Words()
    tiles = {}
    for r in rows:
        got = building_row(r, box, words)
        if got is not None:
            tiles.setdefault(got[0], []).append(got[1])
    for k in tiles:   # (the same file from the same map, whatever order the rows came in)
        tiles[k].sort(key=lambda b: (b[9], b[10]))
    return {"v": VERSION, "release": release, "cell": "%d_%d" % (row, col), "tiles": TILES, "classes": classes_hash(),
            "words": words.words, "rows": dict(sorted(tiles.items()))}


def fetch(box, release, bucket=None, filesystem=None, log=print):
    """Overture's building rows touching box, a batch at a time."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import route_bake as rb
    south, west, north, east = box
    root = "%s/release/%s/theme=buildings/type=building" % (bucket or rb.OVERTURE_BUCKET, release)
    if filesystem is None:
        import pyarrow.fs as pafs
        filesystem = pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset(root, filesystem=filesystem, format="parquet")
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))
    cols = [c for c in ["id", "geometry", "class", "height", "num_floors", "min_height", "min_floor", "is_underground",
                        "has_parts", "names"] + list(CLASS_WORDS[1:]) if c in d.schema.names]
    n = 0
    for batch in d.to_batches(columns=cols, filter=f, batch_size=fb.BATCH, **fb.READ):
        for r in batch.to_pylist():
            n += 1
            yield r
    log("buildings: %d rows read" % n)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cell", help="ROW_COL")
    ap.add_argument("--out", required=True)
    ap.add_argument("--release", required=True)
    args = ap.parse_args(argv)
    row, col = (int(v) for v in args.cell.split("_"))
    got = cell_buildings(fetch(cb.cell_box(row, col), args.release, log=lambda m: print(m, file=sys.stderr)), row, col,
                         args.release)
    with open(args.out, "w") as f:
        json.dump(got, f, separators=(",", ":"))
    print("%s: %d buildings in %d tiles" % (args.cell, sum(len(v) for v in got["rows"].values()), len(got["rows"])))


if __name__ == "__main__":
    main()
