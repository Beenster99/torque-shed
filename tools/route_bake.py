#!/usr/bin/env python3
"""Bakes a real-world road for Torque Shed's adventure mode: a route pack the game rides as an adventure.

    python3 tools/route_bake.py --name shodoshima --title "Shodoshima" \\
        --lat 34.5184 --lon 134.2693 --length-km 25 --out data/routes/shodoshima

The route starts at the road nearest the given point and runs for about --length-km along real roads (or to
--end LAT LON), steered by road class so it prefers main roads. Reads free, openly licensed data and writes a
folder the game loads (scripts/real_pack.gd):

    pack.json        name, credits, hash, the height grid and where the sea is
    route.json       the road as knots every 4 m (x, z, height), per 128 m chunk its class, surface, width and name,
                     and the turn-by-turn instructions
    tiles/TX_TZ.u16  the land's heights in 512 m tiles down the corridor either side of the road
    tiles/TX_TZ.cov  the same tiles' land cover (land_bake.COVER), one byte a height sample
    buildings.json   the buildings beside the road, boxes of a kind; landmarks.json named peaks, lighthouses and the like

Everything is in the adventure mode's route frame: metres from the start, +x east, -z north, heights in metres above
sea level (the sea is at 0). Heights come from Mapterhorn (AWS Terrain Tiles as a fallback), roads from Overture Maps.

Needs numpy and Pillow; the roads need pyarrow (pip install pyarrow). No API keys.
"""
import argparse
import hashlib
import heapq
import io
import json
import math
import os
import struct
import sys
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import land_bake  # noqa: E402

STEP = 4.0                    # metres between knots: AdventureRoute.STEP
CHUNK = 128.0                 # metres per chunk: AdventureRoute.CHUNK_LEN
RUN_OUT = 600.0               # baked past the requested length, for the adventure's run-out beyond the finish
TILE_M = 512.0                # a height tile's side
TILE_N = 128                  # its samples along a side (4 m apart)
CORRIDOR_M = 1300.0           # heights are baked this far either side of the road
HEIGHT_MIN = -256.0           # tiles store uint16 heights: min + q * scale
HEIGHT_SCALE = 0.0625
SNAP_START_M = 500.0          # the start point must be this close to a road
MIN_RADIUS = 10.0             # the road's tightest bend after smoothing, metres (the adventure's own hairpins are 12 to 17)
MAX_GRADE = 0.15              # the steepest the road may climb: a little under AdventureRoute.MAX_GRADE

MAPTERHORN = "https://tiles.mapterhorn.com/{z}/{x}/{y}.webp"
AWS = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
OVERTURE_STAC = "https://stac.overturemaps.org/catalog.json"
OVERTURE_BUCKET = "overturemaps-us-west-2"
USER_AGENT = "torque-shed-route-bake/0.3 (https://github.com/Beenster99/torque-shed)"

# Road classes the adventure rides, best first: class -> (road width in metres, route cost factor per metre).
# Widths are what AdventureRoute.WIDTHS has: two_lane 7.4, road 6.0, narrow 4.6, single 3.3.
CLASSES = {
    "motorway": (7.4, 0.7), "trunk": (7.4, 0.75), "primary": (7.4, 0.8), "secondary": (6.0, 0.9),
    "tertiary": (6.0, 1.0), "unclassified": (4.6, 1.15), "residential": (4.6, 1.3), "living_street": (4.6, 1.4),
    "track": (3.3, 3.0),
}
UNPAVED = {"unpaved", "gravel", "dirt", "ground", "grass", "sand", "mud", "compacted", "fine_gravel", "pebblestone"}
GENERIC_NAMES = {"motorway": "Motorway", "trunk": "Trunk road", "primary": "Main road", "secondary": "B road",
                 "tertiary": "Minor road", "unclassified": "Minor road", "residential": "Street",
                 "living_street": "Street", "track": "Track"}

SEA_ABS = 0.4          # ground this low (metres above sea level) is sea
SEA_DEPTH = 35.0       # how deep the sea floor goes, far from the shore
SEA_SHORE_M = 160.0    # over about this far the floor slopes down from the shore

CREDITS = [
    "Elevation: Mapterhorn (mapterhorn.com), built from national and global terrain models; sources and "
    "licences are listed at https://download.mapterhorn.com/attribution.json.",
    "Roads, buildings, land cover and places: (c) OpenStreetMap contributors and others, Overture Maps Foundation (ODbL).",
]


# ---------------------------------------------------------------------------- geodesy

def metres_per_degree(lat):
    """(metres per degree of latitude, of longitude) at `lat` degrees, from the WGS84 series."""
    p = math.radians(lat)
    return (111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p),
            111412.84 * math.cos(p) - 93.5 * math.cos(3 * p) + 0.118 * math.cos(5 * p))


class Frame:
    """Route-frame coordinates for latitude and longitude: x east, z south, `start` metres at the anchor."""

    def __init__(self, lat, lon, start=(0.0, 0.0)):
        self.lat, self.lon, self.start = lat, lon, tuple(start)
        self.m_lat, self.m_lon = metres_per_degree(lat)

    def to_world(self, lat, lon):
        return (self.start[0] + (np.asarray(lon) - self.lon) * self.m_lon,
                self.start[1] - (np.asarray(lat) - self.lat) * self.m_lat)

    def to_geo(self, x, z):
        return (self.lat - (np.asarray(z) - self.start[1]) / self.m_lat,
                self.lon + (np.asarray(x) - self.start[0]) / self.m_lon)

    def shifted(self, origin):
        """The frame whose origin is `origin` in this frame's coordinates (same scale, so a pure translation)."""
        return Frame(self.lat, self.lon, (self.start[0] - origin[0], self.start[1] - origin[1]))


# ---------------------------------------------------------------------------- heights

def tile_zoom(lat, spacing=STEP, size=512, max_zoom=15):
    """Smallest web-mercator zoom whose tile pixels are no coarser than `spacing` metres at `lat`."""
    c = 40075016.686 * math.cos(math.radians(lat))
    return int(min(max_zoom, max(0, math.ceil(math.log2(c / (size * spacing))))))


def decode_terrarium(im):
    a = np.asarray(im.convert("RGB")).astype(np.float64)
    return a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0


def mercator_pixels(lat, lon, zoom, size=1):
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


class Dem:
    """Ground heights anywhere, from terrain tiles fetched on demand and kept decoded (Mapterhorn, else AWS)."""

    def __init__(self, cache_dir, lat, log=print):
        self.cache_dir = cache_dir
        self.zoom = tile_zoom(lat)
        self.tiles = {}
        self.log = log

    def _tile(self, x, y):
        key = (x, y)
        if key not in self.tiles:
            from PIL import Image
            h = None
            for url in (MAPTERHORN, AWS):
                data = fetch(url.format(z=self.zoom, x=x, y=y), self.cache_dir)
                if data:
                    h = decode_terrarium(Image.open(io.BytesIO(data))).astype(np.float32)
                    break
            if h is None:
                raise RuntimeError("no elevation tile %d/%d/%d from Mapterhorn or AWS" % (self.zoom, x, y))
            if len(self.tiles) > 64:
                self.tiles.pop(next(iter(self.tiles)))
            self.tiles[key] = h
        return self.tiles[key]

    def heights(self, lat, lon):
        """Ground heights in metres at arrays of latitude and longitude (same shape out)."""
        px, py = mercator_pixels(lat, lon, self.zoom)
        out = np.zeros(np.shape(px), dtype=np.float64)
        tx, ty = np.floor(px).astype(int), np.floor(py).astype(int)
        for key in {(int(a), int(b)) for a, b in zip(np.ravel(tx), np.ravel(ty))}:
            mask = (tx == key[0]) & (ty == key[1])
            t = self._tile(*key)
            size = t.shape[0]
            out[mask] = bilinear(t, (px[mask] - key[0]) * size - 0.5, (py[mask] - key[1]) * size - 0.5)
        return out


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def box_blur(a, radius):
    """`a` blurred with a (2 radius + 1) square box, twice, edges padded with their own values."""
    out = a.astype(np.float64)
    for _ in range(2):
        for axis in (0, 1):
            pad = [(0, 0), (0, 0)]
            pad[axis] = (radius + 1, radius)
            c = np.cumsum(np.pad(out, pad, mode="edge"), axis=axis)
            n = out.shape[axis]
            hi = np.take(c, np.arange(2 * radius + 1, 2 * radius + 1 + n), axis=axis)
            lo = np.take(c, np.arange(0, n), axis=axis)
            out = (hi - lo) / (2 * radius + 1)
    return out


def shape_sea(ground, spacing=STEP):
    """`ground` with the sea given a floor: ground at or under SEA_ABS metres is sea, a pond is not.

    The floor slopes away from the shore to SEA_DEPTH metres under, so the game's water has a beach to lap and
    depth to hide the ground in. Returns (heights, whether there is sea)."""
    sea = ground <= SEA_ABS
    if sea.sum() <= 400:
        return ground, False
    radius = max(2, int(SEA_SHORE_M / spacing / 2))
    depth = 2.0 + (SEA_DEPTH - 2.0) * np.clip(box_blur(sea.astype(float), radius) * 1.6, 0.0, 1.0)
    return np.where(sea, -depth, ground), True


def quantise(heights):
    """heights as uint16 steps of HEIGHT_SCALE over HEIGHT_MIN."""
    return np.clip(np.round((heights - HEIGHT_MIN) / HEIGHT_SCALE), 0, 65535).astype("<u2")


# ---------------------------------------------------------------------------- Overture data

def latest_release():
    with urllib.request.urlopen(urllib.request.Request(OVERTURE_STAC, headers={"User-Agent": USER_AGENT}),
                                timeout=60) as r:
        cat = json.load(r)
    return cat.get("latest") or sorted(l["href"].split("/")[-2] for l in cat["links"] if l["rel"] == "child")[-1]


def fetch_segments(south, west, north, east, release, log=print):
    """Overture road segments touching the box, as plain dicts (needs pyarrow)."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    s3 = pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset("%s/release/%s/theme=transportation/type=segment" % (OVERTURE_BUCKET, release),
                   filesystem=s3, format="parquet")
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))
    tb = d.to_table(columns=["id", "geometry", "subtype", "class", "connectors", "road_surface", "road_flags",
                             "names", "routes"], filter=f)
    log("roads: %d segments in the box" % tb.num_rows)
    return tb.to_pylist()


def _as_dict(v):
    if isinstance(v, dict):
        return v
    return dict(v) if v else {}


def segment_label(seg):
    """A name for a road: its English name, else its route number, else its own name, else None."""
    names = seg.get("names") or {}
    en = _as_dict(names.get("common")).get("en")
    if en:
        return str(en)
    for r in seg.get("routes") or []:
        if r.get("ref"):
            return "Route %s" % r["ref"]
    return names.get("primary") or None


def segment_kind(seg):
    """(class, surface) of a road segment the adventure rides ("tarmac" or "gravel"), or None."""
    if seg.get("subtype") != "road" or seg.get("class") not in CLASSES:
        return None
    cls = seg["class"]
    surface = "gravel" if cls == "track" else "tarmac"
    for rule in seg.get("road_surface") or []:
        if rule.get("between") is None and str(rule.get("value")) in UNPAVED:
            surface = "gravel"
    return cls, surface


def parse_wkb(wkb):
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
                part, off = read(buf, off)
                out += part
            return out, off
        raise ValueError("unsupported geometry type %d" % kind)
    return read(bytes(wkb), 0)[0]


# ---------------------------------------------------------------------------- the road graph and the route

def length_of(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


class Graph:
    """The ridden roads as a graph: nodes are Overture connectors, edges are road segments."""

    def __init__(self, segments, frame):
        self.edges = []     # {a, b, pts [(x, z)] from a to b, cls, surface, label, length}
        self.pos = {}       # connector id -> (x, z)
        self.adj = {}       # connector id -> [(other id, edge index)]
        for s in segments:
            info = segment_kind(s)
            cons = s.get("connectors") or []
            if info is None or len(cons) < 2:
                continue
            cons = sorted(cons, key=lambda c: c["at"])
            for line in parse_wkb(s["geometry"]):
                if len(line) < 2:
                    continue
                lon, lat = zip(*line)
                x, z = frame.to_world(np.array(lat), np.array(lon))
                pts = list(zip(x.tolist(), z.tolist()))
                a, b = cons[0]["connector_id"], cons[-1]["connector_id"]
                if a == b:
                    continue
                self.pos.setdefault(a, pts[0])
                self.pos.setdefault(b, pts[-1])
                e = {"a": a, "b": b, "pts": pts, "cls": info[0], "surface": info[1], "label": segment_label(s),
                     "length": length_of(pts)}
                self.adj.setdefault(a, []).append((b, len(self.edges)))
                self.adj.setdefault(b, []).append((a, len(self.edges)))
                self.edges.append(e)

    def weight(self, ei):
        e = self.edges[ei]
        return e["length"] * CLASSES[e["cls"]][1]

    def nearest_node(self, p, within):
        best, bd = None, within
        for n, q in self.pos.items():
            d = math.dist(p, q)
            if d < bd:
                best, bd = n, d
        return best

    def dijkstra(self, start):
        """(weighted cost, real length, previous (node, edge)) of every node reachable from `start`."""
        cost, length, prev = {start: 0.0}, {start: 0.0}, {}
        heap = [(0.0, start)]
        done = set()
        while heap:
            c, n = heapq.heappop(heap)
            if n in done:
                continue
            done.add(n)
            for m, ei in self.adj.get(n, []):
                w = c + self.weight(ei)
                if m not in cost or w < cost[m] - 1e-9:
                    cost[m] = w
                    length[m] = length[n] + self.edges[ei]["length"]
                    prev[m] = (n, ei)
                    heapq.heappush(heap, (w, m))
        return cost, length, prev

    def path(self, prev, start, end):
        """The edges from `start` to `end`, as [(from node, edge index, to node)]."""
        out = []
        n = end
        while n != start:
            p, ei = prev[n]
            out.append((p, ei, n))
            n = p
        return out[::-1]


def choose_end(graph, start, length_m, seed=0):
    """The node to end a route of about `length_m` at, from `start`: far enough, and on the nicest roads.

    Returns (node, warning or None). Among nodes whose route is within 0.9 to 1.15 of the length, the one with
    the lowest cost per metre (more main road) wins, ties broken by `seed`."""
    cost, length, prev = graph.dijkstra(start)
    ok = [n for n, l in length.items() if 0.9 * length_m <= l <= 1.15 * length_m]
    if ok:
        def score(n):
            return (round(cost[n] / max(length[n], 1.0), 3), hashlib.sha1(("%s%d" % (n, seed)).encode()).hexdigest())
        return min(ok, key=score), None
    far = max(length, key=lambda n: length[n])
    return far, "the roads here do not run for %.1f km; the longest route from the start is %.1f km" % (
        length_m / 1000.0, length[far] / 1000.0)


def heading(a, b):
    """Compass heading in degrees from point a to b (north is -z)."""
    return math.degrees(math.atan2(b[0] - a[0], -(b[1] - a[1]))) % 360.0


def point_at(pts, dist, from_end=False):
    """The point `dist` metres along `pts` from its start, or its end when `from_end`."""
    seq = pts[::-1] if from_end else pts
    left = dist
    for p, q in zip(seq, seq[1:]):
        seg = math.dist(p, q)
        if seg >= left and seg > 0:
            t = left / seg
            return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)
        left -= seg
    return seq[-1]


def classify_turn(angle):
    """Instruction word for a turn of `angle` degrees (positive is to the right)."""
    a = abs(angle)
    side = "right" if angle > 0 else "left"
    if a < 25:
        return "straight"
    if a < 60:
        return "slight_" + side
    if a < 135:
        return side
    return "sharp_" + side


def route_from_path(graph, steps):
    """(points, edge index of each point, turns) for a path of (from, edge, to).

    Each turn is {"d" metres along the line, "x", "z", "turn", "onto" road name, "branches" other roads}."""
    pts = []
    owner = []
    turns = []
    for i, (n0, ei, n1) in enumerate(steps):
        e = graph.edges[ei]
        line = e["pts"] if e["a"] == n0 else e["pts"][::-1]
        if i > 0:
            prev = steps[i - 1]
            pe = graph.edges[prev[1]]
            pline = pe["pts"] if pe["a"] == prev[0] else pe["pts"][::-1]
            incoming = heading(point_at(pline, 25.0, from_end=True), pline[-1])
            outgoing = heading(line[0], point_at(line, 25.0))
            branches = len(graph.adj[n0]) - 2
            if branches >= 1:
                ang = (outgoing - incoming + 540.0) % 360.0 - 180.0
                turns.append({"d": round(length_of(pts), 1), "x": round(line[0][0], 1), "z": round(line[0][1], 1),
                              "turn": classify_turn(ang), "onto": e["label"] or GENERIC_NAMES[e["cls"]],
                              "branches": branches})
        new = line if not pts else line[1:]
        pts.extend(new)
        owner.extend([ei] * len(new))
    return pts, owner, turns


# ---------------------------------------------------------------------------- the road as knots

def resample(pts, step, exact=False):
    """The line through `pts` (N x 2) as points `step` metres apart along it (and its last point)."""
    pts = np.asarray(pts, dtype=float)
    seg = np.hypot(*np.diff(pts, axis=0).T)
    keep = np.concatenate([[True], seg > 1e-9])
    pts = pts[keep]
    seg = np.hypot(*np.diff(pts, axis=0).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    total = cum[-1]
    s = np.arange(0.0, total, step)
    if exact:
        s = s[:-1] if len(s) and total - s[-1] < 1e-6 else s
    else:
        s = np.append(s, total) if total - s[-1] > step * 0.25 else np.append(s[:-1], total)
    return np.stack([np.interp(s, cum, pts[:, 0]), np.interp(s, cum, pts[:, 1])], axis=1), cum, total


def curvature(p):
    """Signed-free curvature (1 / radius) at each interior point of a line from its neighbours."""
    a, b, c = p[:-2], p[1:-1], p[2:]
    ab, bc, ac = np.hypot(*(b - a).T), np.hypot(*(c - b).T), np.hypot(*(c - a).T)
    cross = np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0]))
    return 2.0 * cross / np.maximum(ab * bc * ac, 1e-9)


def smooth_line(pts, step=STEP, min_radius=MIN_RADIUS, max_rounds=20000):
    """A smooth road through `pts`: knots `step` apart, no bend tighter than `min_radius` metres.

    Only the bends tighter than the limit are touched: each round pulls the points of such a bend (and a few
    either side) towards the middle of their neighbours, until none is too tight. The line's ends stay put and
    gentle roads are left exactly as mapped. Returns the knots as an N x 2 array."""
    fine, _, _ = resample(pts, 2.0)
    p = fine.copy()
    limit = 1.0 / min_radius
    for _ in range(max_rounds):
        if len(p) < 7:
            break
        k = np.zeros(len(p))
        a, b, c = p[:-4], p[2:-2], p[4:]
        ab, bc, ac = np.hypot(*(b - a).T), np.hypot(*(c - b).T), np.hypot(*(c - a).T)
        cross = np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0]))
        k[2:-2] = 2.0 * cross / np.maximum(ab * bc * ac, 1e-9)
        bad = k > limit
        if not bad.any():
            break
        wide = bad.copy()
        for shift in (1, 2, 3):
            wide[shift:] |= bad[:-shift]
            wide[:-shift] |= bad[shift:]
        wide[:2] = False
        wide[-2:] = False
        idx = np.nonzero(wide)[0]
        avg = (p[idx - 1] + p[idx + 1]) / 2.0
        p[idx] += (avg - p[idx]) * 0.6
    knots, _, _ = resample(p, step, exact=True)
    return knots


def grade_limit(e, step=STEP, max_grade=MAX_GRADE):
    """Heights `e` with no climb steeper than `max_grade`: the road is cut and filled to stay within it."""
    e = np.array(e, dtype=float)
    lim = max_grade * step
    for _ in range(3):
        for i in range(1, len(e)):
            e[i] = min(max(e[i], e[i - 1] - lim), e[i - 1] + lim)
        for i in range(len(e) - 2, -1, -1):
            e[i] = min(max(e[i], e[i + 1] - lim), e[i + 1] + lim)
    return e


def smooth_heights(h, window=9):
    """Ground heights along the road averaged over `window` knots, so the road rides over bumps and ruts."""
    k = window // 2
    padded = np.concatenate([np.full(k, h[0]), h, np.full(k, h[-1])])
    return np.convolve(padded, np.ones(window) / window, mode="valid")


def chunk_attributes(knots_len, edge_of_s, graph):
    """Per 128 m chunk: [{surface, width, cls, name}] from the road edges under it (by most length)."""
    chunks = []
    n_chunks = int(math.ceil((knots_len - 1) * STEP / CHUNK))
    for c in range(n_chunks):
        votes = {}
        for s in np.arange(c * CHUNK, min((c + 1) * CHUNK, (knots_len - 1) * STEP), STEP):
            ei = edge_of_s(s)
            votes[ei] = votes.get(ei, 0) + 1
        ei = max(votes, key=votes.get)
        e = graph.edges[ei]
        chunks.append({"surface": e["surface"], "width": CLASSES[e["cls"]][0], "cls": e["cls"],
                       "name": e["label"] or GENERIC_NAMES[e["cls"]]})
    return chunks


def corridor_tiles(knots, reach=CORRIDOR_M, tile=TILE_M):
    """The (tx, tz) of every height tile within `reach` metres of the road (tile (tx, tz) covers tx*512..)."""
    tiles = set()
    n = int(math.ceil(reach / tile))
    for x, z in knots[::4]:
        cx, cz = int(math.floor(x / tile)), int(math.floor(z / tile))
        for dx in range(-n, n + 1):
            for dz in range(-n, n + 1):
                tx, tz = cx + dx, cz + dz
                # the tile's nearest point to the knot is within reach
                nx = min(max(x, tx * tile), (tx + 1) * tile)
                nz = min(max(z, tz * tile), (tz + 1) * tile)
                if math.hypot(nx - x, nz - z) <= reach:
                    tiles.add((tx, tz))
    return sorted(tiles)


def tile_heights(dem, frame, tx, tz, pad=24):
    """One tile's heights (TILE_N x TILE_N, the sea given a floor) from the DEM; and whether it has sea."""
    n = TILE_N + 2 * pad
    ax = tx * TILE_M + (np.arange(n) - pad) * STEP
    az = tz * TILE_M + (np.arange(n) - pad) * STEP
    gx, gz = np.meshgrid(ax, az)
    lat, lon = frame.to_geo(gx, gz)
    ground = dem.heights(lat, lon)
    shaped, sea = shape_sea(ground)
    return shaped[pad:pad + TILE_N, pad:pad + TILE_N], sea


# ---------------------------------------------------------------------------- the pack

def pack_hash(out):
    h = hashlib.sha256()
    for root, _, files in sorted(os.walk(out)):
        for fn in sorted(files):
            if fn == "pack.json":
                continue
            with open(os.path.join(root, fn), "rb") as f:
                h.update(f.read())
    return h.hexdigest()[:16]


def bake(args, log=print):
    release = args.release or latest_release()
    log("Overture release %s" % release)
    g0 = Frame(args.lat, args.lon)            # provisional: metres from the given point
    length_m = (args.length_km * 1000.0) + RUN_OUT
    if args.end:
        ex, ez = g0.to_world(args.end[0], args.end[1])
        box = (min(0.0, float(ex)) - 4000.0, min(0.0, float(ez)) - 4000.0, max(0.0, float(ex)) + 4000.0,
               max(0.0, float(ez)) + 4000.0)
    else:
        r = min(length_m * 0.8 + 3000.0, 60000.0)
        box = (-r, -r, r, r)
    lat_n, lon_w = g0.to_geo(box[0], box[1])
    lat_s, lon_e = g0.to_geo(box[2], box[3])
    segments = fetch_segments(float(lat_s), float(lon_w), float(lat_n), float(lon_e), release, log)
    graph = Graph(segments, g0)
    start = graph.nearest_node((0.0, 0.0), SNAP_START_M)
    if start is None:
        raise SystemExit("no road within %d m of the start point; move it onto a road" % SNAP_START_M)
    warn = None
    if args.end:
        end = graph.nearest_node((float(ex), float(ez)), SNAP_START_M)
        if end is None:
            raise SystemExit("no road within %d m of the end point" % SNAP_START_M)
    else:
        end, warn = choose_end(graph, start, length_m, args.seed)
    _, _, prev = graph.dijkstra(start)
    if end not in prev and end != start:
        raise SystemExit("the end cannot be reached by road from the start")
    steps = graph.path(prev, start, end)
    route_pts, owner, turns = route_from_path(graph, steps)
    if warn:
        log("WARNING: " + warn)
    log("route: %.1f km, %d turns" % (length_of(route_pts) / 1000.0, len(turns)))

    # The route frame: the start is the origin.
    s0 = graph.pos[start]
    frame = g0.shifted(s0)
    shift = np.array(s0)
    raw = np.array(route_pts) - shift
    knots = smooth_line(raw)
    for t in turns:
        t["x"], t["z"] = round(t["x"] - s0[0], 1), round(t["z"] - s0[1], 1)
    log("road: %d knots (%.1f km)" % (len(knots), (len(knots) - 1) * STEP / 1000.0))

    # The height profile: the DEM under the road, smoothed and graded.
    dem = Dem(args.cache, args.lat, log)
    lat, lon = frame.to_geo(knots[:, 0], knots[:, 1])
    ground = dem.heights(lat, lon)
    elev = grade_limit(smooth_heights(np.maximum(ground, 0.0)))

    # Per chunk: surface, width, class and name, from the edges the road came along.
    cum_raw = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(raw, axis=0).T))])
    scale = cum_raw[-1] / max((len(knots) - 1) * STEP, 1e-9)
    owner_arr = np.array(owner)

    def edge_of_s(s):
        i = int(np.searchsorted(cum_raw, s * scale, side="right")) - 1
        return int(owner_arr[min(max(i, 0), len(owner_arr) - 1)])
    chunks = chunk_attributes(len(knots), edge_of_s, graph)
    names = sorted({c["name"] for c in chunks})
    chunk_rows = [[c["surface"], c["width"], c["cls"], names.index(c["name"])] for c in chunks]

    # The land: height tiles down the corridor.
    tiles = corridor_tiles(knots)
    log("land: %d tiles" % len(tiles))
    os.makedirs(os.path.join(args.out, "tiles"), exist_ok=True)
    land = land_bake.bake_land(OVERTURE_BUCKET, release, frame, knots, tiles, args.out, log)
    has_sea = False
    for i, (tx, tz) in enumerate(tiles):
        h, sea = tile_heights(dem, frame, tx, tz)
        has_sea = has_sea or sea
        h = land_bake.level_ground(h, tx, tz, land["buildings"])
        quantise(h).tofile(os.path.join(args.out, "tiles", "%d_%d.u16" % (tx, tz)))
        if (i + 1) % 25 == 0:
            log("  %d / %d" % (i + 1, len(tiles)))

    turns.append({"d": round((len(knots) - 1) * STEP, 1), "x": round(float(knots[-1][0]), 1), "z": round(float(knots[-1][1]), 1),
                  "turn": "arrive", "onto": "", "branches": 0})
    with open(os.path.join(args.out, "route.json"), "w") as f:
        json.dump({"step": STEP, "n": len(knots), "x": [round(float(v), 2) for v in knots[:, 0]],
                   "z": [round(float(v), 2) for v in knots[:, 1]], "e": [round(float(v), 2) for v in elev],
                   "chunks": chunk_rows, "names": names, "turns": turns}, f, separators=(",", ":"))
    end_geo = frame.to_geo(knots[-1][0], knots[-1][1])
    start_geo = frame.to_geo(0.0, 0.0)
    meta = {
        "format": 4, "name": args.name, "title": args.title or args.name,
        "start": {"lat": round(float(start_geo[0]), 6), "lon": round(float(start_geo[1]), 6)},
        "end": {"lat": round(float(end_geo[0]), 6), "lon": round(float(end_geo[1]), 6)},
        "length_m": round((len(knots) - 1) * STEP, 1), "run_out_m": RUN_OUT,
        "tile": {"size_m": TILE_M, "n": TILE_N, "spacing": STEP}, "height": {"min": HEIGHT_MIN, "scale": HEIGHT_SCALE},
        "tile_count": len(tiles), "cover": land_bake.COVER, "building_kinds": land_bake.BUILDING_KINDS,
        "building_count": len(land["buildings"]), "landmark_count": len(land["landmarks"]), "sea": has_sea, "theme": "coastal" if has_sea else "hills", "warning": warn,
        "sources": {"overture_release": release, "elevation": "Mapterhorn, AWS Terrain Tiles fallback"},
        "credits": CREDITS,
    }
    meta["hash"] = pack_hash(args.out)
    with open(os.path.join(args.out, "pack.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--issue", help="a JSON file with name, title, start {lat, lon}, end {lat, lon} and length_km")
    ap.add_argument("--name", help="short id, used as the folder name")
    ap.add_argument("--title", default="", help="the issue's name for the title screen")
    ap.add_argument("--lat", type=float, help="start point latitude (put it near a road)")
    ap.add_argument("--lon", type=float, help="start point longitude")
    ap.add_argument("--end", type=float, nargs=2, metavar=("LAT", "LON"), help="end the route here instead of by length")
    ap.add_argument("--length-km", type=float, default=None, help="the longest ride the pack offers (default 25)")
    ap.add_argument("--seed", type=int, default=0, help="breaks ties between equally good ends")
    ap.add_argument("--out", help="folder to write (default data/routes/NAME)")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/torque-shed-bake"), help="download cache")
    ap.add_argument("--release", help="Overture release, default the latest")
    args = ap.parse_args(argv)
    if args.issue:
        with open(args.issue) as f:
            issue = json.load(f)
        args.name = args.name or issue.get("name")
        args.title = args.title or issue.get("title", "")
        args.lat = args.lat if args.lat is not None else issue["start"]["lat"]
        args.lon = args.lon if args.lon is not None else issue["start"]["lon"]
        if not args.end and issue.get("end"):
            args.end = [issue["end"]["lat"], issue["end"]["lon"]]
        if args.length_km is None:
            args.length_km = issue.get("length_km")
        args.seed = args.seed or int(issue.get("seed", 0))
    if args.lat is None or args.lon is None or not args.name:
        ap.error("give --name, --lat and --lon (or --issue)")
    if args.length_km is None:
        args.length_km = 25.0
    args.out = args.out or os.path.join("data", "routes", args.name)
    meta = bake(args)
    print("wrote %s: route %.1f km, %d tiles, hash %s" % (args.out, meta["length_m"] / 1000.0, meta["tile_count"], meta["hash"]))


if __name__ == "__main__":
    sys.exit(main())
