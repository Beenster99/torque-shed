#!/usr/bin/env python3
"""The trees of a cell: how tall they stand and how thick they grow, on a grid of about 16 m squares near the roads a
ride can take, and what leaves they have where the map says. The game plants its trees from it (AdventureChunk), the
hedgerow oak and the lone ash where they really are, and the woods as tall as they really grow.

    python3 tools/tree_bake.py LAT LON [--release R] [--cache DIR] [--out FILE]   # the cell at LAT, LON
    python3 tools/tree_bake.py --square LAT LON --out DIR [...]                   # every cell of a 1 degree square
    python3 tools/tree_bake.py --box S W N E --out FILE [...]                     # a bundled region's: {"cells": [...]}

The heights are Meta and the World Resources Institute's canopy height map (1 m, from satellite pictures and lidar,
CC BY 4.0: https://registry.opendata.aws/dataforgood-fb-forests/), read from its tiles (z9 squares of web mercator,
65536 pixels a side, a byte a pixel: the canopy's height in metres) in Meta's open bucket. The leaves are OpenStreetMap's
leaf_type on its woods (by way of Overture's base/land and land_use, their source_tags), where it is mapped.

A cell's trees: {"cell": "ROW_COL", "rows": R, "cols": C, "trees": base64(zlib(R x C bytes)), "leaf": base64(zlib(R x
C bytes))}, the rows from the cell's north edge down and the columns from its west edge, each a CELL_DEG / R by
CELL_DEG / C degree square. A trees byte is the canopy's height in HEIGHT_STEP metres (its low 5 bits: the tallest in
the square) and how much of the square is under trees, in eighths (its top 3 bits: 0 none, 7 all of it); 0 where
there are no trees, or the square is further than NEAR_M from a road a ride can take (it never shows). A leaf byte is
LEAVES' id, 0 where it isn't mapped. A cell's go into a file of their own in the world's store (tree/cROW_COL.json,
its hash in the index's "trees"), fetched for a journey on it, as its streams are (stream_bake.py).
"""
import argparse
import base64
import json
import math
import os
import struct
import sys
import threading
import urllib.error
import urllib.request
import zlib

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import sketch_bake  # noqa: E402

CHM_URL = "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/%s.tif"
USER_AGENT = "TorqueShed tree_bake (+https://github.com/Beenster99/torque-shed)"
# The canopy tiles' zoom, and the web mercator world's width (m).
CHM_ZOOM = 9
WORLD_M = 40075016.685578488
# A square of the grid is about this many metres a side.
SAMPLE_M = 16.0
# Squares further than this (m) from a road a ride can take are left empty (the game scatters trees 260 m out).
NEAR_M = 300.0
# A pixel this tall (m) or more is a tree's.
TREE_MIN = 3
# The height's step (m) in the trees byte.
HEIGHT_STEP = 2.0
LEAVES = {"broadleaved": 1, "needleleaved": 2, "mixed": 3}
# What Overture's land and land_use call a wood.
WOODS = {"forest", "wood", "forestry"}


# ---------------------------------------------------------------------------- canopy tiles

def quadkey(tx, ty, zoom=CHM_ZOOM):
    """The quadkey that names tile (tx, ty) at `zoom`."""
    out = ""
    for i in range(zoom, 0, -1):
        m = 1 << (i - 1)
        out += str((1 if tx & m else 0) + (2 if ty & m else 0))
    return out


def merc(lat, lon):
    """Web mercator (x east, y down from the north edge of the world), metres."""
    x = (lon + 180.0) / 360.0 * WORLD_M
    s = math.sin(math.radians(max(-85.05, min(85.05, lat))))
    y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * WORLD_M
    return x, y


def tiles_over(box, zoom=CHM_ZOOM):
    """The tiles (tx, ty) at `zoom` that box (south, west, north, east) touches."""
    s, w, n, e = box
    size = WORLD_M / (1 << zoom)
    x0, y0 = merc(n, w)
    x1, y1 = merc(s, e)
    return [(tx, ty) for ty in range(int(y0 // size), int(y1 // size) + 1) for tx in range(int(x0 // size), int(x1 // size) + 1)]


class Tiff:
    """A striped, deflated, byte-a-pixel TIFF (as the canopy tiles are), read a row at a time without holding it all."""

    def __init__(self, path):
        self.f = open(path, "rb")
        head = self.f.read(16)
        order = "<" if head[:2] == b"II" else ">"
        big = struct.unpack_from(order + "H", head, 2)[0] == 43
        off = struct.unpack_from(order + ("Q" if big else "I"), head, 8 if big else 4)[0]
        self.f.seek(off)
        count = struct.unpack(order + ("Q" if big else "H"), self.f.read(8 if big else 2))[0]
        size = 20 if big else 12
        ifd = self.f.read(count * size)
        types = {3: "H", 4: "I", 16: "Q"}
        tags = {}
        for k in range(count):
            tag, typ = struct.unpack_from(order + "HH", ifd, k * size)
            n = struct.unpack_from(order + ("Q" if big else "I"), ifd, k * size + 4)[0]
            if typ not in types:
                continue
            fmt = order + "%d%s" % (n, types[typ])
            nbytes = struct.calcsize(fmt)
            if nbytes <= (8 if big else 4):
                vals = struct.unpack_from(fmt, ifd, k * size + (12 if big else 8))
            else:
                at = struct.unpack_from(order + ("Q" if big else "I"), ifd, k * size + (12 if big else 8))[0]
                here = self.f.tell()
                self.f.seek(at)
                vals = struct.unpack(fmt, self.f.read(nbytes))
                self.f.seek(here)
            tags[tag] = vals
        self.width = tags[256][0]
        self.height = tags[257][0]
        self.rows_per_strip = tags.get(278, (self.height,))[0]
        self.offsets = tags[273]
        self.counts = tags[279]
        self.predictor = tags.get(317, (1,))[0]
        if tags.get(259, (1,))[0] not in (8, 32946) or tags.get(258, (8,))[0] != 8:
            raise ValueError("not a deflated byte-a-pixel tiff")
        self._strip = (-1, None)

    def rows(self, y0, y1):
        """Rows y0 to y1 (not included), as a (y1 - y0) x width array of bytes."""
        out = np.empty((y1 - y0, self.width), np.uint8)
        for y in range(y0, y1):
            k = y // self.rows_per_strip
            if self._strip[0] != k:
                self.f.seek(self.offsets[k])
                a = np.frombuffer(zlib.decompress(self.f.read(self.counts[k])), np.uint8).reshape(-1, self.width)
                if self.predictor == 2:
                    a = np.cumsum(a, axis=1, dtype=np.uint8)
                self._strip = (k, a)
            out[y - y0] = self._strip[1][y - k * self.rows_per_strip]
        return out


class Tiles:
    """The canopy tiles, fetched into `cache` the first time each is wanted (None where there is none: the sea). Safe to
    share between threads; drop() lets go of tiles no longer wanted (they're about 170 MB each)."""

    def __init__(self, cache, log=print):
        self.cache = cache
        self.log = log
        self.open = {}
        self.locks = {}
        self.lock = threading.Lock()

    def __call__(self, tx, ty):
        with self.lock:
            lock = self.locks.setdefault((tx, ty), threading.Lock())
        with lock:
            if (tx, ty) in self.open:
                return self.open[(tx, ty)]
            key = quadkey(tx, ty)
            path = os.path.join(self.cache, key + ".tif")
            if not os.path.exists(path) and not os.path.exists(path + ".none"):
                os.makedirs(self.cache, exist_ok=True)
                self.log("fetching canopy tile %s" % key)
                try:
                    req = urllib.request.Request(CHM_URL % key, headers={"User-Agent": USER_AGENT})
                    with urllib.request.urlopen(req, timeout=600) as r, open(path + ".part", "wb") as f:
                        while True:
                            b = r.read(1 << 20)
                            if not b:
                                break
                            f.write(b)
                    os.replace(path + ".part", path)
                except urllib.error.HTTPError as e:
                    if e.code not in (403, 404):
                        raise
                    open(path + ".none", "w").close()
            got = TileReader(path) if os.path.exists(path) else None
            self.open[(tx, ty)] = got
            return got

    def drop(self, keys):
        """Lets go of tiles `keys` [(tx, ty)] and deletes them from the cache."""
        for k in keys:
            with self.lock:
                lock = self.locks.setdefault(k, threading.Lock())
            with lock:
                got = self.open.pop(k, None)
                if got is not None:
                    got.close()
                path = os.path.join(self.cache, quadkey(*k) + ".tif")
                if os.path.exists(path):
                    os.remove(path)


class TileReader:
    """A Tiff read by several threads at once: each its own handle."""

    def __init__(self, path):
        self.path = path
        self.local = threading.local()
        first = self._tiff()
        self.width = first.width
        self.height = first.height
        self.all = [first]

    def _tiff(self):
        t = getattr(self.local, "tiff", None)
        if t is None:
            t = Tiff(self.path)
            self.local.tiff = t
            if hasattr(self, "all"):
                self.all.append(t)
        return t

    def rows(self, y0, y1):
        return self._tiff().rows(y0, y1)

    def close(self):
        for t in self.all:
            t.f.close()


# ---------------------------------------------------------------------------- the grid

def grid_of(row, col):
    """Cell (row, col)'s grid: (rows, cols)."""
    s, w, n, e = coast_bake.cell_box(row, col)
    m_lat, m_lon = sketch_bake.metres_per_degree((s + n) / 2.0)
    return max(1, round((n - s) * m_lat / SAMPLE_M)), max(1, round((e - w) * m_lon / SAMPLE_M))


def road_mask(roads, box, rows, cols, near=NEAR_M):
    """The squares of a grid over box within `near` (m) of a road (WKB lines): a rows x cols bool array."""
    import route_bake as rb
    s, w, n, e = box
    m_lat, _ = sketch_bake.metres_per_degree((s + n) / 2.0)
    px_m = (n - s) * m_lat / rows
    r = near / px_m
    img = Image.new("L", (cols, rows), 0)
    d = ImageDraw.Draw(img)
    for wkb in roads:
        for line in rb.parse_wkb(wkb) or []:
            pts = [((lon - w) / (e - w) * cols, (n - lat) / (n - s) * rows) for lon, lat in line]
            if not any(-r <= x <= cols + r and -r <= y <= rows + r for x, y in pts):
                continue
            d.line(pts, fill=1, width=max(1, int(round(2 * r))))
            for x, y in pts:
                d.ellipse((x - r, y - r, x + r, y + r), fill=1)
    return np.asarray(img, dtype=bool)


def canopy(box, rows, cols, tiles, mask):
    """The trees bytes of a grid over box (see the module's notes) from the canopy tiles (`tiles`: (tx, ty) -> Tiff or
    None), only where `mask` is set."""
    s, w, n, e = box
    size = WORLD_M / (1 << CHM_ZOOM)
    tallest = np.zeros((rows, cols), np.uint8)
    under = np.zeros((rows, cols), np.float64)
    seen = np.zeros((rows, cols), np.float64)
    lat_edges = [n - (n - s) * k / rows for k in range(rows + 1)]
    lon_edges = [w + (e - w) * k / cols for k in range(cols + 1)]
    xs = [merc(0.0, lon)[0] for lon in lon_edges]
    ys = [merc(lat, 0.0)[1] for lat in lat_edges]
    for tx, ty in tiles_over(box):
        tif = tiles(tx, ty)
        if tif is None:
            continue
        px = tif.width / size
        # Each column's pixels in this tile: [p0, p1).
        cx = [int(round((x - tx * size) * px)) for x in xs]
        c_in = [k for k in range(cols) if cx[k + 1] > 0 and cx[k] < tif.width]
        if not c_in:
            continue
        for r in range(rows):
            if not mask[r].any():
                continue
            y0 = int(round((ys[r] - ty * size) * px))
            y1 = int(round((ys[r + 1] - ty * size) * px))
            y0, y1 = max(0, y0), min(tif.height, y1)
            if y1 <= y0:
                continue
            ks = [k for k in c_in if mask[r, k]]
            if not ks:
                continue
            p0 = max(0, cx[ks[0]])
            p1 = min(tif.width, cx[ks[-1] + 1])
            band = tif.rows(y0, y1)[:, p0:p1]
            top = band.max(axis=0)
            trees = (band >= TREE_MIN).sum(axis=0)
            for k in ks:
                a = max(0, cx[k]) - p0
                b = min(tif.width, cx[k + 1]) - p0
                if b <= a:
                    continue
                tallest[r, k] = max(tallest[r, k], int(top[a:b].max()))
                under[r, k] += float(trees[a:b].sum())
                seen[r, k] += float((b - a) * (y1 - y0))
    share = np.divide(under, seen, out=np.zeros_like(under), where=seen > 0)
    eighths = np.clip(np.round(share * 7.0), 0, 7).astype(np.uint8)
    height = np.clip(np.round(tallest / HEIGHT_STEP), 1, 31).astype(np.uint8)
    out = np.where((eighths > 0) & mask, height | (eighths << 5), 0).astype(np.uint8)
    return out


def leaf_grid(woods, box, rows, cols):
    """The leaf bytes of a grid over box from woods [(LEAVES id, geometry WKB)]."""
    import land_bake
    s, w, n, e = box
    img = Image.new("L", (cols, rows), 0)
    d = ImageDraw.Draw(img)
    for code, wkb in woods:
        for poly in land_bake.parse_geometry(wkb):
            for k, ring in enumerate(poly):
                pts = [((lon - w) / (e - w) * cols, (n - lat) / (n - s) * rows) for lon, lat in ring]
                if len(pts) >= 3:
                    d.polygon(pts, fill=code if k == 0 else 0)
    return np.asarray(img, dtype=np.uint8)


def pack(a):
    return base64.b64encode(zlib.compress(a.tobytes(), 9)).decode("ascii")


def cell_trees(row, col, tiles, roads, woods):
    """Cell (row, col)'s trees (see the module's notes) from the canopy tiles, the roads near it (WKB lines) and its
    woods with their leaves mapped [(LEAVES id, WKB)]."""
    box = coast_bake.cell_box(row, col)
    rows, cols = grid_of(row, col)
    mask = road_mask(roads, box, rows, cols)
    trees = canopy(box, rows, cols, tiles, mask) if mask.any() else np.zeros((rows, cols), np.uint8)
    leaf = np.where(trees > 0, leaf_grid(woods, box, rows, cols), 0).astype(np.uint8)
    return {"cell": "%d_%d" % (row, col), "rows": rows, "cols": cols, "trees": pack(trees), "leaf": pack(leaf)}


# ---------------------------------------------------------------------------- the data

def fetch_woods(box, release, bucket=None, filesystem=None):
    """Overture's woods touching box whose leaves OpenStreetMap has: [(LEAVES id, geometry WKB)]."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    import route_bake as rb
    s3 = filesystem or pafs.S3FileSystem(anonymous=True, region="us-west-2")
    south, west, north, east = box
    out = []
    for kind in ("land", "land_use"):
        d = ds.dataset("%s/release/%s/theme=base/type=%s" % (bucket or rb.OVERTURE_BUCKET, release, kind), filesystem=s3,
                       format="parquet")
        f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
             & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south)
             & (pc.field("class").isin(list(WOODS)) | pc.field("subtype").isin(list(WOODS))))
        for r in d.to_table(columns=["geometry", "source_tags"], filter=f).to_pylist():
            code = LEAVES.get(dict(r.get("source_tags") or []).get("leaf_type"))
            if code and r["geometry"]:
                out.append((code, r["geometry"]))
    return out


def fetch_square(box, release, cache, log=print, roads_box=None):
    """What a square's cells' trees are made from: (its canopy Tiles, its roads (those of `roads_box` if given), its
    woods)."""
    import stream_bake
    pad = 0.01   # (the roads just over the square's edge count too)
    south, west, north, east = roads_box or box
    roads = stream_bake.fetch_roads((south - pad, west - pad, north + pad, east + pad), release)
    return Tiles(cache, log), roads, fetch_woods(box, release)


def cell_trees_of(fetched, row, col):
    """cell_trees from fetch_square's (tiles, roads, woods)."""
    return cell_trees(row, col, fetched[0], fetched[1], fetched[2])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("lat", type=float, nargs="?")
    ap.add_argument("lon", type=float, nargs="?")
    ap.add_argument("--square", nargs=2, type=float, metavar=("LAT", "LON"), help="every cell of the 1 degree square at LAT, LON")
    ap.add_argument("--box", nargs=4, type=float, metavar=("S", "W", "N", "E"), help="the cells over a box, as one list")
    ap.add_argument("--cells", help="with --square, only these cells (ROW_COL,...)")
    ap.add_argument("--release")
    ap.add_argument("--cache", default=os.path.join(os.path.expanduser("~"), ".cache", "torque-shed", "canopy"),
                    help="where the canopy tiles are kept (about 170 MB each)")
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    import route_bake as rb
    release = args.release or rb.latest_release()
    if args.box:
        south, west, north, east = args.box
        r0, c0 = coast_bake.cell_of(south, west)
        r1, c1 = coast_bake.cell_of(north, east)
        # (only the box's roads: those are the ones a ride on the bundled region can take)
        fetched = fetch_square((r0 * 0.25 - 90.0, c0 * 0.25 - 180.0, (r1 + 1) * 0.25 - 90.0, (c1 + 1) * 0.25 - 180.0),
                               release, args.cache, roads_box=tuple(args.box))
        cells = [cell_trees_of(fetched, r, c) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)]
        with open(args.out, "w") as f:
            f.write(json.dumps({"cells": cells}, separators=(",", ":")) + "\n")
        return 0
    if args.square:
        lat, lon = math.floor(args.square[0]), math.floor(args.square[1])
        fetched = fetch_square((lat, lon, lat + 1.0, lon + 1.0), release, args.cache)
        only = set(args.cells.split(",")) if args.cells else None
        os.makedirs(args.out, exist_ok=True)
        r0, c0 = coast_bake.cell_of(lat + 1e-9, lon + 1e-9)
        for r in range(r0, r0 + 4):
            for c in range(c0, c0 + 4):
                if only is not None and "%d_%d" % (r, c) not in only:
                    continue
                got = cell_trees_of(fetched, r, c)
                with open(os.path.join(args.out, "%s.trees" % got["cell"]), "w") as f:
                    f.write(json.dumps(got, separators=(",", ":")) + "\n")
        return 0
    if args.lat is None or args.lon is None:
        ap.error("a cell's LAT LON, or --square")
    row, col = coast_bake.cell_of(args.lat, args.lon)
    got = cell_trees_of(fetch_square(coast_bake.cell_box(row, col), release, args.cache), row, col)
    text = json.dumps(got, separators=(",", ":"))
    if args.out:
        with open(args.out, "w") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
