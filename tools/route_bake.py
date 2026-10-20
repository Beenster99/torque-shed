#!/usr/bin/env python3
"""Bakes a real-world route pack for Torque Shed's adventure-mode proof of concept.

    python3 tools/route_bake.py --name shodoshima --title "Shodoshima, Kankakei" \\
        --lat 34.5237 --lon 134.2698 --out data/routes/shodoshima

Reads free, openly licensed data and writes a folder the game loads (see scripts/route_pack.gd):

    pack.json     name, anchor, grid, height scaling, credits
    heights.u16   little-endian uint16 heights, SIZE x SIZE, row-major (z then x)
    roads.json    road definitions in the same shape as WorldLayout.ROADS

Heights come from Mapterhorn (AWS Terrain Tiles as a fallback), roads from Overture Maps. The pack is in
the game's own frame: +x east, -z north, the map is 4096 m square about the world origin where the shed
stands, and the start point is placed START_WORLD metres from it. Heights are metres above the start
point, blended down to level ground round the shed so the yard and its loop road are undisturbed.
A short "link" road joins the shed's loop to the real road nearest the start point.

Needs numpy and Pillow; roads need pyarrow (pip install pyarrow). No API keys.
"""
import argparse
import hashlib
import io
import json
import math
import os
import struct
import sys
import urllib.request

import numpy as np

# The game's frame (scripts/world_terrain.gd, scripts/world_layout.gd).
SIZE = 1025
SPACING = 4.0
HALF = 2048.0
SHED_CENTRE = (0.0, -20.0)         # the middle of the shed's yard and loop road
LOOP_EAST = (200.0, -62.0)         # where the loop's east spur leaves it (WorldLayout "east")
START_WORLD = (800.0, -60.0)       # where the start point lands on the map
KEEP_OUT = 380.0                   # no real roads this close to the shed; the terrain blends flat inside
FLAT_FROM, FLAT_TO = 380.0, 800.0  # the real land fades in over this distance from the shed
SNAP_START_M = 150.0               # the start point must be this close to a road

MAPTERHORN = "https://tiles.mapterhorn.com/{z}/{x}/{y}.webp"
AWS = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
OVERTURE_STAC = "https://stac.overturemaps.org/catalog.json"
OVERTURE_BUCKET = "overturemaps-us-west-2"
USER_AGENT = "torque-shed-route-bake/0.1 (https://github.com/Beenster99/torque-shed)"

# Road classes the game rides, best first: class -> (kind, half width m, steepest grade).
CLASSES = {
    "motorway": ("tarmac", 4.5, 0.10), "trunk": ("tarmac", 4.0, 0.12), "primary": ("tarmac", 3.75, 0.12),
    "secondary": ("tarmac", 3.5, 0.13), "tertiary": ("tarmac", 3.25, 0.14), "unclassified": ("tarmac", 3.0, 0.15),
    "residential": ("tarmac", 3.0, 0.15), "living_street": ("tarmac", 2.75, 0.15), "track": ("dirt", 2.0, 0.25),
}
RANK = {c: i for i, c in enumerate(CLASSES)}
UNPAVED = {"unpaved", "gravel", "dirt", "ground", "grass", "sand", "mud", "compacted", "fine_gravel", "pebblestone"}

CREDITS = [
    "Elevation: Mapterhorn (mapterhorn.com), built from national and global terrain models; sources and "
    "licences are listed at https://download.mapterhorn.com/attribution.json.",
    "Roads: (c) OpenStreetMap contributors, Overture Maps Foundation (ODbL).",
]


# ---------------------------------------------------------------------------- geodesy

def metres_per_degree(lat):
    """(metres per degree of latitude, of longitude) at `lat` degrees, from the WGS84 series."""
    p = math.radians(lat)
    return (111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p),
            111412.84 * math.cos(p) - 93.5 * math.cos(3 * p) + 0.118 * math.cos(5 * p))


class Frame:
    """Game coordinates for latitude and longitude about an anchor: x east, z south, start at START_WORLD."""

    def __init__(self, lat, lon, start=START_WORLD):
        self.lat, self.lon, self.start = lat, lon, start
        self.m_lat, self.m_lon = metres_per_degree(lat)

    def to_world(self, lat, lon):
        return (self.start[0] + (np.asarray(lon) - self.lon) * self.m_lon,
                self.start[1] - (np.asarray(lat) - self.lat) * self.m_lat)

    def to_geo(self, x, z):
        return (self.lat - (np.asarray(z) - self.start[1]) / self.m_lat,
                self.lon + (np.asarray(x) - self.start[0]) / self.m_lon)


# ---------------------------------------------------------------------------- heights

def tile_zoom(lat, spacing=SPACING, size=512, max_zoom=15):
    """Smallest web-mercator zoom whose tile pixels are no coarser than `spacing` metres at `lat`."""
    c = 40075016.686 * math.cos(math.radians(lat))
    return int(min(max_zoom, max(0, math.ceil(math.log2(c / (size * spacing))))))


def decode_terrarium(im):
    a = np.asarray(im.convert("RGB")).astype(np.float64)
    return a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0


def mercator_pixels(lat, lon, zoom, size):
    """Fractional pixel position in the world pixel grid of tiles `size` px square at `zoom`."""
    n = (2 ** zoom) * size
    x = (np.asarray(lon) + 180.0) / 360.0 * n
    s = np.sin(np.radians(np.clip(lat, -85.05, 85.05)))
    y = (0.5 - np.log((1 + s) / (1 - s)) / (4 * math.pi)) * n
    return x, y


def fetch(url, cache_dir):
    """The bytes at `url`, kept under `cache_dir`; None when the server has no such tile."""
    path = None
    if cache_dir:
        path = os.path.join(cache_dir, hashlib.sha1(url.encode()).hexdigest())
        if os.path.exists(path):
            with open(path, "rb") as f:
                return f.read() or None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
    except urllib.error.HTTPError as e:
        if e.code in (403, 404):
            data = b""
        else:
            raise
    if path:
        os.makedirs(cache_dir, exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    return data or None


def load_dem_tile(z, x, y, cache_dir):
    """(heights, pixel size) of one terrain tile, Mapterhorn first and AWS if it has none."""
    from PIL import Image
    for url, size in ((MAPTERHORN, 512), (AWS, 256)):
        data = fetch(url.format(z=z, x=x, y=y), cache_dir)
        if data:
            im = Image.open(io.BytesIO(data))
            h = decode_terrarium(im)
            return h, h.shape[0]
    raise RuntimeError("no elevation tile %d/%d/%d from Mapterhorn or AWS" % (z, x, y))


def sample_dem(frame, cache_dir, spacing=SPACING, size=SIZE, half=HALF, log=print):
    """The ground height in metres at every grid sample of the game map: a (size, size) array, [z][x]."""
    ax = np.arange(size) * spacing - half
    gx, gz = np.meshgrid(ax, ax)
    lat, lon = frame.to_geo(gx, gz)
    zoom = tile_zoom(float(np.mean(lat)), spacing)
    # Tiles are fetched at whatever size the server gives; the zoom decides the area each covers.
    px, py = mercator_pixels(lat, lon, zoom, 1)
    tx0, tx1 = int(np.floor(px.min())), int(np.floor(px.max()))
    ty0, ty1 = int(np.floor(py.min())), int(np.floor(py.max()))
    log("elevation: zoom %d, tiles x %d..%d y %d..%d" % (zoom, tx0, tx1, ty0, ty1))
    rows = []
    tile_px = None
    for ty in range(ty0, ty1 + 1):
        row = []
        for tx in range(tx0, tx1 + 1):
            h, tile_px = load_dem_tile(zoom, tx, ty, cache_dir)
            row.append(h)
        rows.append(np.concatenate(row, axis=1))
    mosaic = np.concatenate(rows, axis=0)
    # Pixel centres sit half a pixel in from the tile corner.
    fx = (px - tx0) * tile_px - 0.5
    fy = (py - ty0) * tile_px - 0.5
    return bilinear(mosaic, fx, fy)


def bilinear(a, fx, fy):
    """`a` sampled at fractional columns fx and rows fy (clamped to the array's edge)."""
    h, w = a.shape
    fx = np.clip(fx, 0, w - 1.0001)
    fy = np.clip(fy, 0, h - 1.0001)
    x0 = np.floor(fx).astype(int)
    y0 = np.floor(fy).astype(int)
    tx = fx - x0
    ty = fy - y0
    return (a[y0, x0] * (1 - tx) * (1 - ty) + a[y0, x0 + 1] * tx * (1 - ty)
            + a[y0 + 1, x0] * (1 - tx) * ty + a[y0 + 1, x0 + 1] * tx * ty)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def relative_heights(ground, spacing=SPACING, size=SIZE, half=HALF, start=START_WORLD):
    """Heights above the start point, faded to level ground round the shed so the yard is undisturbed."""
    ax = np.arange(size) * spacing - half
    gx, gz = np.meshgrid(ax, ax)
    ix = int(round((start[0] + half) / spacing))
    iz = int(round((start[1] + half) / spacing))
    rel = ground - ground[iz, ix]
    d = np.hypot(gx - SHED_CENTRE[0], gz - SHED_CENTRE[1])
    return rel * smoothstep(FLAT_FROM, FLAT_TO, d)


def quantise(heights):
    """(uint16 array, lowest height, metres per step): the heights spread over the whole 16 bits."""
    lo, hi = float(heights.min()), float(heights.max())
    scale = max((hi - lo) / 65535.0, 1e-6)
    return np.round((heights - lo) / scale).astype("<u2"), lo, scale


# ---------------------------------------------------------------------------- roads

def parse_linestrings(wkb):
    """The lines of a WKB LineString or MultiLineString as lists of (lon, lat)."""
    def read(buf, off):
        order = "<" if buf[off] == 1 else ">"
        kind = struct.unpack_from(order + "I", buf, off + 1)[0] % 1000
        off += 5
        if kind == 2:
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            pts = struct.unpack_from(order + "%dd" % (2 * n), buf, off)
            return [list(zip(pts[0::2], pts[1::2]))], off + 16 * n
        if kind == 5:
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            out = []
            for _ in range(n):
                lines, off = read(buf, off)
                out += lines
            return out, off
        raise ValueError("unsupported geometry type %d" % kind)
    return read(bytes(wkb), 0)[0]


def latest_release():
    with urllib.request.urlopen(urllib.request.Request(OVERTURE_STAC, headers={"User-Agent": USER_AGENT}),
                                timeout=60) as r:
        cat = json.load(r)
    return cat.get("latest") or sorted(l["href"].split("/")[-2] for l in cat["links"] if l["rel"] == "child")[-1]


def fetch_segments(south, west, north, east, release=None, log=print):
    """Overture road segments touching the box, as plain dicts (needs pyarrow)."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    release = release or latest_release()
    log("roads: Overture release %s" % release)
    s3 = pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset("%s/release/%s/theme=transportation/type=segment" % (OVERTURE_BUCKET, release),
                   filesystem=s3, format="parquet")
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))
    tb = d.to_table(columns=["id", "geometry", "subtype", "class", "connectors", "road_surface", "road_flags"],
                    filter=f)
    return tb.to_pylist(), release


def segment_kind(seg):
    """(class, kind, half width, grade) for a road segment the game rides, or None."""
    if seg.get("subtype") != "road" or seg.get("class") not in CLASSES:
        return None
    cls = seg["class"]
    kind, hw, grade = CLASSES[cls]
    for rule in seg.get("road_surface") or []:
        if rule.get("between") is None and str(rule.get("value")) in UNPAVED:
            return cls, "dirt", min(hw, 2.4), max(grade, 0.25)
    return cls, kind, hw, grade


def rdp(pts, tol):
    """Ramer-Douglas-Peucker: `pts` (list of (x, z)) thinned so no point is more than `tol` off the line."""
    if len(pts) < 3:
        return list(pts)
    a, b = np.array(pts[0]), np.array(pts[-1])
    p = np.array(pts[1:-1])
    ab = b - a
    n2 = float(ab @ ab)
    if n2 < 1e-9:
        d = np.hypot(*(p - a).T)
    else:
        t = np.clip(((p - a) @ ab) / n2, 0, 1)
        d = np.hypot(*(p - (a + np.outer(t, ab))).T)
    i = int(np.argmax(d))
    if d[i] <= tol:
        return [pts[0], pts[-1]]
    return rdp(pts[:i + 2], tol)[:-1] + rdp(pts[i + 1:], tol)


def build_chains(segments, frame):
    """Joins segments that meet end to end at a two-way connector into longer roads.

    Returns chains: {pts [(x, z)], start_node, end_node, cls, kind, hw, grade}. Chains always end at a
    connector where three or more roads meet (or at a dead end), so every junction is a chain end.
    """
    segs = []
    for s in segments:
        info = segment_kind(s)
        if info is None or not s.get("connectors") or len(s["connectors"]) < 2:
            continue
        # Bridges and tunnels have no geometry of their own in the game yet; they ride as plain road.
        cons = sorted(s["connectors"], key=lambda c: c["at"])
        for line in parse_linestrings(s["geometry"]):
            if len(line) < 2:
                continue
            lon, lat = zip(*line)
            x, z = frame.to_world(np.array(lat), np.array(lon))
            segs.append({"pts": list(zip(x.tolist(), z.tolist())), "a": cons[0]["connector_id"],
                         "b": cons[-1]["connector_id"], "info": info})
    ends = {}
    for i, s in enumerate(segs):
        ends.setdefault(s["a"], []).append(i)
        ends.setdefault(s["b"], []).append(i)
    used = [False] * len(segs)
    chains = []

    def extend(pts, node, info, forward):
        """Follows the road on from `node` while it stays a plain two-way join of the same kind."""
        while True:
            at = ends[node]
            if len(at) != 2:
                return node
            other = [j for j in at if not used[j]]
            if len(other) != 1 or segs[other[0]]["info"][1] != info[1]:
                return node
            j = other[0]
            used[j] = True
            s = segs[j]
            line = s["pts"] if s["a"] == node else s["pts"][::-1]
            nxt = s["b"] if s["a"] == node else s["a"]
            if forward:
                pts.extend(line[1:])
            else:
                pts[:0] = line[:0:-1]
            node = nxt
            if nxt == s["a"] and nxt == s["b"]:   # a loop closing on itself
                return node
            info = _best(info, s["info"])

    def _best(i1, i2):
        return i1 if RANK[i1[0]] <= RANK[i2[0]] else i2

    for i, s in enumerate(segs):
        if used[i]:
            continue
        used[i] = True
        pts = list(s["pts"])
        info = s["info"]
        end_node = extend(pts, s["b"], info, True)
        start_node = extend(pts, s["a"], info, False)
        chains.append({"pts": pts, "start_node": start_node, "end_node": end_node, "info": info})
    # A chain's class is the best of its segments; its width and grade follow that class.
    out = []
    for c in chains:
        cls, kind, hw, grade = c["info"]
        out.append({"pts": c["pts"], "start_node": c["start_node"], "end_node": c["end_node"],
                    "cls": cls, "kind": kind, "hw": hw, "grade": grade})
    return out


def clip_chain(chain, centre=SHED_CENTRE, radius=KEEP_OUT, half=HALF - 8.0):
    """Pieces of `chain` outside the keep-out circle round the shed and inside the map."""
    def inside(p):
        return math.hypot(p[0] - centre[0], p[1] - centre[1]) < radius or abs(p[0]) > half or abs(p[1]) > half
    pieces, cur, cur_from_start = [], [], False
    for i, p in enumerate(chain["pts"]):
        if inside(p):
            if len(cur) >= 2:
                pieces.append((cur, cur_from_start))
            cur = []
            continue
        if not cur:
            cur_from_start = i == 0
        cur.append(p)
    if len(cur) >= 2:
        pieces.append((cur, cur_from_start))
    out = []
    for pts, from_start in pieces:
        to_end = pts[-1] == chain["pts"][-1]
        c = dict(chain)
        c["pts"] = pts
        c["start_node"] = chain["start_node"] if from_start else None
        c["end_node"] = chain["end_node"] if to_end else None
        out.append(c)
    return out


def length_of(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def build_roads(chains, start=START_WORLD, min_length=40.0, simplify=1.5):
    """Road definitions for the game: clipped, thinned, ordered best first, joined at junctions, plus the link.

    Returns (defs, start_point) where start_point is the road point nearest the start the link runs to.
    """
    pieces = []
    for c in chains:
        for p in clip_chain(c):
            p["pts"] = rdp(p["pts"], simplify)
            if length_of(p["pts"]) >= min_length:
                pieces.append(p)
    pieces.sort(key=lambda c: (RANK[c["cls"]], -length_of(c["pts"])))
    names = ["r%03d" % i for i in range(len(pieces))]
    owner = {}   # junction connector -> the first road in the list that touches it
    for name, c in zip(names, pieces):
        for node in (c["start_node"], c["end_node"]):
            if node is not None:
                owner.setdefault(node, name)
    defs = []
    for name, c in zip(names, pieces):
        d = {"name": name, "label": name, "kind": c["kind"], "hw": c["hw"], "grade": c["grade"],
             "pts": [[round(x, 2), round(z, 2)] for x, z in c["pts"]]}
        if c["kind"] == "dirt":
            d["hard"] = c["grade"] > 0.3
        for end, node in (("start", c["start_node"]), ("end", c["end_node"])):
            if node is not None and owner[node] != name:
                d[end] = owner[node]
        defs.append(d)
    # The start: the road point nearest it. The link runs from the shed's loop to there.
    best = None
    for d in defs:
        for p in d["pts"]:
            dist = math.dist(p, start)
            if best is None or dist < best[0]:
                best = (dist, d["name"], p)
    if best is None or best[0] > SNAP_START_M:
        raise SystemExit("no road within %d m of the start point; move it onto a road" % SNAP_START_M)
    _, road, p = best
    link = link_points(LOOP_EAST, p)
    defs.append({"name": "link", "label": "Link road", "kind": "tarmac", "hw": 3.5, "grade": 0.12,
                 "start": "loop", "end": road, "pts": [[round(x, 2), round(z, 2)] for x, z in link]})
    return defs, p


def link_points(a, b, step=100.0):
    """Control points for a straight link from `a` to `b`."""
    n = max(2, int(math.dist(a, b) / step))
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


# ---------------------------------------------------------------------------- the pack

def write_pack(out, name, title, frame, heights, roads, start_point, release, end_world=None):
    os.makedirs(out, exist_ok=True)
    q, lo, scale = quantise(heights)
    q.tofile(os.path.join(out, "heights.u16"))
    with open(os.path.join(out, "roads.json"), "w") as f:
        json.dump(roads, f, separators=(",", ":"))
    h = hashlib.sha256()
    for fn in ("heights.u16", "roads.json"):
        with open(os.path.join(out, fn), "rb") as f:
            h.update(f.read())
    meta = {
        "format": 1, "name": name, "title": title,
        "anchor": {"lat": frame.lat, "lon": frame.lon},
        "start_world": list(frame.start), "start_road_point": [round(start_point[0], 2), round(start_point[1], 2)],
        "end_world": end_world,
        "grid": {"size": SIZE, "spacing": SPACING},
        "height": {"min": lo, "scale": scale},
        "road_count": len(roads), "road_length_m": round(sum(length_of(d["pts"]) for d in roads), 1),
        "sources": {"overture_release": release, "elevation": "Mapterhorn, AWS Terrain Tiles fallback"},
        "credits": CREDITS, "hash": h.hexdigest()[:16],
    }
    with open(os.path.join(out, "pack.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--name", required=True, help="short id, used as the folder name")
    ap.add_argument("--title", default="", help="the issue's name for the title screen")
    ap.add_argument("--lat", type=float, required=True, help="start point latitude (put it on a road)")
    ap.add_argument("--lon", type=float, required=True, help="start point longitude")
    ap.add_argument("--end", type=float, nargs=2, metavar=("LAT", "LON"), help="the route's end point (recorded)")
    ap.add_argument("--out", required=True, help="folder to write")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/torque-shed-bake"), help="download cache")
    ap.add_argument("--release", help="Overture release, default the latest")
    args = ap.parse_args(argv)

    frame = Frame(args.lat, args.lon)
    ground = sample_dem(frame, args.cache)
    heights = relative_heights(ground)
    print("heights: %.0f to %.0f m about the start, ground %.0f m there" % (
        heights.min(), heights.max(), ground[int(round((START_WORLD[1] + HALF) / SPACING)),
                                             int(round((START_WORLD[0] + HALF) / SPACING))]))
    # The map spans the game's +-HALF about the shed, not about the start: ask for that box.
    lat_n, lon_w = frame.to_geo(-HALF, -HALF)
    lat_s, lon_e = frame.to_geo(HALF, HALF)
    segments, release = fetch_segments(float(lat_s), float(lon_w), float(lat_n), float(lon_e), args.release)
    print("roads: %d segments in the box" % len(segments))
    roads, start_point = build_roads(build_chains(segments, frame))
    end_world = None
    if args.end:
        ex, ez = frame.to_world(args.end[0], args.end[1])
        end_world = [round(float(ex), 1), round(float(ez), 1)]
    meta = write_pack(args.out, args.name, args.title, frame, heights, roads, start_point, release, end_world)
    print("wrote %s: %d roads, %.1f km, hash %s" % (args.out, meta["road_count"], meta["road_length_m"] / 1000,
                                                    meta["hash"]))


if __name__ == "__main__":
    sys.exit(main())
