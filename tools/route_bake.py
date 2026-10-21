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
import fork_bake  # noqa: E402
import land_bake  # noqa: E402
import road_facts  # noqa: E402
import levels  # noqa: E402

STEP = 4.0                    # metres between knots: AdventureRoute.STEP
CHUNK = 128.0                 # metres per chunk: AdventureRoute.CHUNK_LEN
RUN_OUT = 600.0               # baked past the requested length, for the adventure's run-out beyond the finish
TILE_M = levels.FINE.size_m   # the fine level's tile side (see levels.py for the others)
TILE_N = levels.FINE.n
HEIGHT_MIN = levels.MIN
HEIGHT_SCALE = levels.FINE.scale
FEATHER = {"fine": 16, "coarse": 8}   # samples over which a level's edge blends into the next coarser one
RIDGE_LOWER_M = 90.0          # the ridge level is pushed down this far near the road, hidden under the land mesh
RIDGE_NEAR_M = 700.0          # ...out to here, easing back up to the real height by RIDGE_FAR_M: about where the land
RIDGE_FAR_M = 1000.0          # mesh's own real heights end (AdventureChunk.LAND_OUT), so the two meet and never gap
RIDGE_SEA_M = -3.0            # and where it is sea, just under the water
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

    def __init__(self, cache_dir, lat, log=print, spacing=STEP):
        self.cache_dir = cache_dir
        self.zoom = tile_zoom(lat, spacing)
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


def quantise(heights, level=levels.FINE):
    """heights as uint16 steps of the level's scale over levels.MIN."""
    return level.quantise(heights)


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
                             "names", "routes", "speed_limits"], filter=f)
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


def cut_at_connectors(pts, cons):
    """A segment's polyline cut at its connectors (Overture `at`: the fraction of its length each is along):
    [(connector, next connector, points between)] for each consecutive pair."""
    seg = [math.dist(p, q) for p, q in zip(pts, pts[1:])]
    total = sum(seg)
    cum = [0.0]
    for d in seg:
        cum.append(cum[-1] + d)

    def at(frac):
        d = min(max(frac, 0.0), 1.0) * total
        for i in range(len(seg)):
            if cum[i + 1] >= d:
                t = (d - cum[i]) / seg[i] if seg[i] > 0 else 0.0
                return i, (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
        return len(seg) - 1, pts[-1]
    out = []
    for c0, c1 in zip(cons, cons[1:]):
        i0, p0 = at(float(c0["at"]))
        i1, p1 = at(float(c1["at"]))
        sub = [p0] + [pts[k] for k in range(i0 + 1, i1 + 1)] + [p1]
        out.append((c0["connector_id"], c1["connector_id"], sub))
    return out


class Graph:
    """The ridden roads as a graph: nodes are Overture connectors, edges are road segments."""

    def __init__(self, segments, frame, avoid=()):
        self.edges = []     # {a, b, pts [(x, z)] from a to b, cls, surface, label, length}
        self.pos = {}       # connector id -> (x, z)
        self.adj = {}       # connector id -> [(other id, edge index)]
        for s in segments:
            info = segment_kind(s)
            cons = s.get("connectors") or []
            if info is None or len(cons) < 2 or info[0] in avoid:
                continue
            cons = sorted(cons, key=lambda c: c["at"])
            lines = parse_wkb(s["geometry"])
            for line in lines:
                if len(line) < 2:
                    continue
                lon, lat = zip(*line)
                x, z = frame.to_world(np.array(lat), np.array(lon))
                pts = list(zip(x.tolist(), z.tolist()))
                # A segment can be joined to others part-way along (a connector with an `at` between 0 and 1): the
                # road graph needs an edge between each pair of connectors, so cut it there.
                parts = [(cons[0]["connector_id"], cons[-1]["connector_id"], pts)]
                if len(lines) == 1 and len(cons) > 2:
                    parts = cut_at_connectors(pts, cons)
                for a, b, sub in parts:
                    if a == b or len(sub) < 2:
                        continue
                    self.pos.setdefault(a, sub[0])
                    self.pos.setdefault(b, sub[-1])
                    e = {"a": a, "b": b, "pts": sub, "cls": info[0], "surface": info[1], "label": segment_label(s),
                         "length": length_of(sub), "limit": road_facts.segment_limit(s.get("speed_limits"))}
                    self.adj.setdefault(a, []).append((b, len(self.edges)))
                    self.adj.setdefault(b, []).append((a, len(self.edges)))
                    self.edges.append(e)

    def weight(self, ei):
        e = self.edges[ei]
        return e["length"] * CLASSES[e["cls"]][1]

    def component_of(self, node):
        """The nodes reachable from `node` (its connected piece of the road graph): a via or end point snaps to one of
        these, not to a stray bit of road that leads nowhere."""
        if not hasattr(self, "_comps"):
            self._comps = {}
        if node not in self._comps:
            comp, stack = {node}, [node]
            while stack:
                n = stack.pop()
                for m, _ in self.adj.get(n, []):
                    if m not in comp:
                        comp.add(m)
                        stack.append(m)
            for n in comp:
                self._comps[n] = comp
        return self._comps[node]

    def nearest_node(self, p, within, component=None):
        """The node nearest `p` within `within` metres (and in `component`, a set of nodes, when given), or None."""
        best, bd = None, within
        for n, q in self.pos.items():
            if component is not None and n not in component:
                continue
            d = math.dist(p, q)
            if d < bd:
                best, bd = n, d
        return best

    def nearest_connected(self, p, within, min_nodes=200):
        """The node nearest `p` within `within` metres that is part of a road network of at least `min_nodes` junctions
        (not a stray bit of road), or None."""
        near = sorted((math.dist(p, q), n) for n, q in self.pos.items() if math.dist(p, q) <= within)
        for _, n in near:
            if len(self.component_of(n)) >= min_nodes:
                return n
        return near[0][1] if near else None

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

    def shortest(self, start, goal, banned=frozenset(), max_cost=float("inf")):
        """The cheapest path from `start` to `goal` as [(from, edge, to)] that uses none of the edges in `banned` and
        costs no more than `max_cost`, or None."""
        cost, prev = {start: 0.0}, {}
        heap = [(0.0, start)]
        done = set()
        while heap:
            c, n = heapq.heappop(heap)
            if n in done:
                continue
            if n == goal:
                return self.path(prev, start, goal) if goal != start else []
            if c > max_cost:
                return None
            done.add(n)
            for m, ei in self.adj.get(n, []):
                if ei in banned:
                    continue
                w = c + self.weight(ei)
                if m not in cost or w < cost[m] - 1e-9:
                    cost[m] = w
                    prev[m] = (n, ei)
                    heapq.heappush(heap, (w, m))
        return None

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


def road_summary(chunks, names_by_chunk, elev, issue):
    """What the magazine says about the road from the data: where from and to (the issue's own words), the named roads
    it follows (longest first), and how much it climbs: {from, to, roads, climb_m, top_m, low_m}."""
    generic = set(GENERIC_NAMES.values())
    metres = {}
    for c in chunks:
        if c["name"] not in generic:
            metres[c["name"]] = metres.get(c["name"], 0.0) + CHUNK
    roads = [n for n, _ in sorted(metres.items(), key=lambda kv: (-kv[1], kv[0]))[:4]]
    e = np.asarray(elev, dtype=float)
    climb = float(np.maximum(np.diff(e), 0.0).sum())
    return {"from": issue.get("from", ""), "to": issue.get("to", ""), "roads": roads, "climb_m": int(round(climb)),
            "top_m": int(round(float(e.max()))), "low_m": int(round(float(e.min())))}


def strip_spurs(steps):
    """The path with every out-and-back along the same road taken out (a via point on a dead-end street would make the
    route drive in and turn round): steps are (from, edge, to)."""
    out = []
    for st in steps:
        if out and out[-1][1] == st[1] and out[-1][2] == st[0] and out[-1][0] == st[2]:
            out.pop()
        else:
            out.append(st)
    return out


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
                       "name": e["label"] or GENERIC_NAMES[e["cls"]], "limit": e.get("limit")})
    return chunks


def corridor_tiles(knots, reach=levels.FINE.reach, tile=TILE_M):
    """The (tx, tz) of every tile of side `tile` within `reach` metres of the road (tile (tx, tz) covers tx * tile..)."""
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


def level_heights(dem, frame, level, tx, tz, pad=24):
    """One tile's heights (n x n, the sea given a floor) at `level` from the DEM; and whether it has sea."""
    n = level.n + 2 * pad
    ax = tx * level.size_m + (np.arange(n) - pad) * level.spacing
    az = tz * level.size_m + (np.arange(n) - pad) * level.spacing
    gx, gz = np.meshgrid(ax, az)
    lat, lon = frame.to_geo(gx, gz)
    ground = dem.heights(lat, lon)
    shaped, sea = shape_sea(ground, level.spacing)
    return shaped[pad:pad + level.n, pad:pad + level.n], sea


def tile_heights(dem, frame, tx, tz, pad=24):
    """One fine tile's heights (the sea given a floor) from the DEM; and whether it has sea."""
    return level_heights(dem, frame, levels.FINE, tx, tz, pad)


class LevelField:
    """A level's baked heights as the game reads them: bilinear over the quantised tiles, NaN where a sample is missing."""

    def __init__(self, level, tiles):
        self.level = level
        self.tiles = tiles   # (tx, tz) -> float array as dequantised

    def heights(self, x, z):
        lv = self.level
        fx = np.asarray(x, dtype=np.float64) / lv.spacing
        fz = np.asarray(z, dtype=np.float64) / lv.spacing
        ix = np.floor(fx).astype(int)
        iz = np.floor(fz).astype(int)
        tx, tz = fx - ix, fz - iz

        def cell(cx, cz):
            out = np.full(np.shape(cx), np.nan)
            key_x, key_z = np.floor_divide(cx, lv.n), np.floor_divide(cz, lv.n)
            for key in {(int(a), int(b)) for a, b in zip(np.ravel(key_x), np.ravel(key_z))}:
                t = self.tiles.get(key)
                if t is None:
                    continue
                m = (key_x == key[0]) & (key_z == key[1])
                out[m] = t[np.mod(cz, lv.n)[m], np.mod(cx, lv.n)[m]]
            return out
        a, b, c, d = cell(ix, iz), cell(ix + 1, iz), cell(ix, iz + 1), cell(ix + 1, iz + 1)
        return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz


def blend_edges(h, level, tx, tz, present, coarser, feather):
    """The tile's heights eased into `coarser`'s over `feather` samples at each side that has no neighbour tile in
    `present`: where a level ends it meets the next one's own heights, so there is no step to see or ride over."""
    n = level.n
    idx = np.arange(n, dtype=np.float64)
    weight = np.zeros((n, n))
    for dx, dz, edge in ((-1, 0, "w"), (1, 0, "e"), (0, -1, "n"), (0, 1, "s")):
        if (tx + dx, tz + dz) in present:
            continue
        dist = {"w": idx[None, :], "e": (n - 1 - idx)[None, :], "n": idx[:, None], "s": (n - 1 - idx)[:, None]}[edge]
        wgt = 1.0 - smoothstep(0.0, float(feather), dist)
        weight = np.maximum(weight, np.broadcast_to(wgt, (n, n)))
    # A corner whose diagonal neighbour is missing is a free edge too: the game's bilinear needs that tile's sample.
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        if (tx + dx, tz + dz) in present:
            continue
        cx = idx[None, :] if dx < 0 else (n - 1 - idx)[None, :]
        cz = idx[:, None] if dz < 0 else (n - 1 - idx)[:, None]
        weight = np.maximum(weight, 1.0 - smoothstep(0.0, float(feather), np.maximum(cx, cz)))
    if not weight.any():
        return h
    gx, gz = np.meshgrid(tx * level.size_m + idx * level.spacing, tz * level.size_m + idx * level.spacing)
    other = coarser.heights(gx, gz)
    ok = ~np.isnan(other)
    return np.where(ok, h * (1.0 - weight) + other * weight, h)


def road_distance(points, knots, block=256):
    """The distance from each of `points` (n, 2) to the nearest of `knots` (m, 2)."""
    out = np.empty(len(points))
    for i in range(0, len(points), block):
        d = points[i:i + block, None, :] - knots[None, :, :]
        out[i:i + block] = np.sqrt((d ** 2).sum(axis=2)).min(axis=1)
    return out


def ridge_tile(h, tx, tz, knots):
    """The ridge level's heights for a tile: pushed down near the road (it is drawn as a mesh of its own, and the
    land mesh must hide it there), and just under the water where it is sea."""
    lv = levels.RIDGE
    idx = np.arange(lv.n)
    gx, gz = np.meshgrid(tx * lv.size_m + idx * lv.spacing, tz * lv.size_m + idx * lv.spacing)
    pts = np.column_stack([gx.ravel(), gz.ravel()])
    near = road_distance(pts, knots[::16]).reshape(lv.n, lv.n)
    lowered = h - RIDGE_LOWER_M * (1.0 - smoothstep(RIDGE_NEAR_M, RIDGE_FAR_M, near))
    return np.where(h <= 0.0, np.minimum(lowered, RIDGE_SEA_M), lowered)


def bake_terrain(out, frame, knots, dems, land_fn, log=print):
    """Bakes every level's height tiles under `out` (see levels.py), coarsest first so each finer level can blend its
    edges into the one above; `dems` is {level name: Dem}; `land_fn({level name: tiles})` bakes the cover and returns
    the land (with its buildings, to level the fine ground under). Returns ({level name: [(tx, tz)]}, whether there is
    sea, the land)."""
    tiles = {lv.name: corridor_tiles(knots, lv.reach, lv.size_m) for lv in levels.LEVELS}
    for name, t in tiles.items():
        log("land: %d %s tiles" % (len(t), name))
    land = land_fn({lv.name: tiles[lv.name] for lv in levels.COVER_LEVELS})
    has_sea = False
    fields = {}
    for k in range(len(levels.LEVELS) - 1, -1, -1):
        lv = levels.LEVELS[k]
        os.makedirs(os.path.join(out, lv.folder), exist_ok=True)
        present = set(tiles[lv.name])
        coarser = fields[levels.LEVELS[k + 1].name] if k + 1 < len(levels.LEVELS) else None
        quantised = {}
        for i, (tx, tz) in enumerate(tiles[lv.name]):
            h, sea = level_heights(dems[lv.name], frame, lv, tx, tz)
            has_sea = has_sea or (sea and lv is not levels.RIDGE)
            if lv is levels.FINE:
                h = land_bake.level_ground(h, tx, tz, land["buildings"])
            if lv is levels.RIDGE:
                h = ridge_tile(h, tx, tz, knots)
            if coarser is not None:
                h = blend_edges(h, lv, tx, tz, present, coarser, FEATHER[lv.name])
            q = lv.quantise(h)
            with open(os.path.join(out, lv.folder, "%d_%d.u16z" % (tx, tz)), "wb") as f:
                f.write(levels.encode_heights(q.reshape(lv.n, lv.n)))
            quantised[(tx, tz)] = lv.dequantise(q).reshape(lv.n, lv.n)
            if (i + 1) % 50 == 0:
                log("  %s %d / %d" % (lv.name, i + 1, len(tiles[lv.name])))
        fields[lv.name] = LevelField(lv, quantised)
    return tiles, has_sea, land


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
    via = [g0.to_world(v[0], v[1]) for v in (getattr(args, "via", None) or [])]
    if args.end:
        ex, ez = g0.to_world(args.end[0], args.end[1])
        xs = [0.0, float(ex)] + [float(v[0]) for v in via]
        zs = [0.0, float(ez)] + [float(v[1]) for v in via]
        box = (min(xs) - 4000.0, min(zs) - 4000.0, max(xs) + 4000.0, max(zs) + 4000.0)
    else:
        r = min(length_m * 0.8 + 3000.0, 60000.0)
        box = (-r, -r, r, r)
    lat_n, lon_w = g0.to_geo(box[0], box[1])
    lat_s, lon_e = g0.to_geo(box[2], box[3])
    segments = fetch_segments(float(lat_s), float(lon_w), float(lat_n), float(lon_e), release, log)
    avoid = set(getattr(args, "avoid", None) or [])
    graph = Graph(segments, g0, avoid)
    start = graph.nearest_connected((0.0, 0.0), SNAP_START_M)
    if start is None:
        raise SystemExit("no road within %d m of the start point; move it onto a road" % SNAP_START_M)
    warn = None
    if args.end:
        end = graph.nearest_node((float(ex), float(ez)), SNAP_START_M, graph.component_of(start))
        if end is None:
            raise SystemExit("no road within %d m of the end point" % SNAP_START_M)
    else:
        end, warn = choose_end(graph, start, length_m, args.seed)
    # The path: start to each via point in turn, and on to the end.
    stops = [start]
    for v in via:
        node = graph.nearest_node((float(v[0]), float(v[1])), SNAP_START_M, graph.component_of(start))
        if node is None:
            raise SystemExit("no road within %d m of a via point" % SNAP_START_M)
        stops.append(node)
    stops.append(end)
    steps = []
    for a, b in zip(stops, stops[1:]):
        _, _, prev = graph.dijkstra(a)
        if b not in prev and b != a:
            raise SystemExit("the end cannot be reached by road from the start (or a via point)")
        steps += graph.path(prev, a, b)
    steps = strip_spurs(steps)
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
    # (the chunks' rows are made after the land, which says which are built up: see below)

    # Forks: the second-best way between two junctions of the route, a road of its own.
    region = road_facts.region_of(args.lat, args.lon)
    forks = fork_bake.find_forks(sys.modules[__name__], graph, steps, knots, shift, args.seed) if args.forks else []
    ways = [fork_bake.build_way(sys.modules[__name__], graph, fk, knots, shift, elev, dem, frame, edge_of_s, region)
            for fk in forks]
    fork_rows = fork_bake.fork_rows(sys.modules[__name__], forks, ways, chunks)
    os.makedirs(args.out, exist_ok=True)
    log("forks: %d (%s)" % (len(forks), ", ".join("%d to %d km, other way %.1f km" % (
        fk["i0"] * STEP / 1000, fk["i1"] * STEP / 1000, w["length"] / 1000.0) for fk, w in zip(forks, ways))))
    with open(os.path.join(args.out, "forks.json"), "w") as f:
        json.dump(fork_rows, f, separators=(",", ":"))
    all_knots = np.vstack([knots] + [np.column_stack([w["x"], w["z"]]) for w in ways])

    # The land: height tiles at each level down the corridor (the other ways' too).
    os.makedirs(args.out, exist_ok=True)
    dems = {lv.name: (dem if lv is levels.FINE else Dem(args.cache, args.lat, log, lv.spacing)) for lv in levels.LEVELS}
    tiles, has_sea, land = bake_terrain(
        args.out, frame, all_knots, dems,
        lambda cover_tiles: land_bake.bake_land(OVERTURE_BUCKET, release, frame, knots, cover_tiles, args.out, log,
                                                box_knots=all_knots), log)

    # Speed limits: posted where the data has them, else the country's default for the class, lower where built up.
    limits = road_facts.chunk_limits(chunks, [c["limit"] for c in chunks],
                                     road_facts.built_up_chunks(len(chunks), land["buildings"]), region)
    chunk_rows = [[c["surface"], c["width"], c["cls"], names.index(c["name"]), limits[i]] for i, c in enumerate(chunks)]
    summary = road_summary(chunks, names_by_chunk=None, elev=elev, issue=getattr(args, "places", None) or {})
    # Where side roads join: the route's junctions (the graph is in the start-point frame, the knots in the route's).
    junctions = road_facts.thin_junctions(road_facts.junctions_along(graph, steps, knots + shift))
    with open(os.path.join(args.out, "junctions.json"), "w") as f:
        json.dump(junctions, f, separators=(",", ":"))
    log("junctions: %d (%s)" % (len(junctions), ", ".join("%d %s" % (sum(1 for j in junctions if j["type"] == t), t)
                                                         for t in ("tee", "cross", "roundabout", "mini"))))
    turns.append({"d": round((len(knots) - 1) * STEP, 1), "x": round(float(knots[-1][0]), 1), "z": round(float(knots[-1][1]), 1),
                  "turn": "arrive", "onto": "", "branches": 0})
    with open(os.path.join(args.out, "route.json"), "w") as f:
        json.dump({"step": STEP, "n": len(knots), "x": [round(float(v), 2) for v in knots[:, 0]],
                   "z": [round(float(v), 2) for v in knots[:, 1]], "e": [round(float(v), 2) for v in elev],
                   "chunks": chunk_rows, "names": names, "turns": turns}, f, separators=(",", ":"))
    end_geo = frame.to_geo(knots[-1][0], knots[-1][1])
    start_geo = frame.to_geo(0.0, 0.0)
    meta = {
        "format": 7, "name": args.name, "title": args.title or args.name,
        "start": {"lat": round(float(start_geo[0]), 6), "lon": round(float(start_geo[1]), 6)},
        "end": {"lat": round(float(end_geo[0]), 6), "lon": round(float(end_geo[1]), 6)},
        "length_m": round((len(knots) - 1) * STEP, 1), "run_out_m": RUN_OUT,
        "levels": [lv.meta() for lv in levels.LEVELS], "tile_counts": {k: len(v) for k, v in tiles.items()},
        "cover": land_bake.COVER, "building_kinds": land_bake.BUILDING_KINDS,
        "building_count": len(land["buildings"]), "region": region, "junction_count": len(junctions), "fork_count": len(forks), "summary": summary,
        "poi_count": len(land["pois"]), "landmark_count": len(land["landmarks"]), "sea": has_sea, "theme": "coastal" if has_sea else "hills", "warning": warn,
        "sources": {"overture_release": release, "elevation": "Mapterhorn, AWS Terrain Tiles fallback"},
        "credits": CREDITS,
    }
    meta["hash"] = pack_hash(args.out)
    with open(os.path.join(args.out, "pack.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--issue", help="a JSON file with name, title, start {lat, lon}, end {lat, lon}, length_km, and optionally via [{lat, lon}], avoid [class] and forks (false for none)")
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
    ap.add_argument("--via", type=float, nargs=2, action="append", metavar=("LAT", "LON"),
                    help="a point the route passes (repeat for more), between the start and the end")
    ap.add_argument("--avoid", default="", help="road classes to leave out, comma-separated (e.g. motorway,trunk)")
    ap.add_argument("--no-forks", dest="forks", action="store_false", help="bake no second ways for the crew to vote on")
    args = ap.parse_args(argv)
    args.avoid = [c for c in str(args.avoid).split(",") if c]
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
        if not args.via and issue.get("via"):
            args.via = [[v["lat"], v["lon"]] for v in issue["via"]]
        if not args.avoid and issue.get("avoid"):
            args.avoid = list(issue["avoid"])
        if issue.get("forks") is False:
            args.forks = False
        args.places = {"from": issue.get("from", ""), "to": issue.get("to", "")}
    if args.lat is None or args.lon is None or not args.name:
        ap.error("give --name, --lat and --lon (or --issue)")
    if args.length_km is None:
        args.length_km = 25.0
    args.out = args.out or os.path.join("data", "routes", args.name)
    meta = bake(args)
    print("wrote %s: route %.1f km, tiles %s, hash %s" % (args.out, meta["length_m"] / 1000.0, meta["tile_counts"], meta["hash"]))


if __name__ == "__main__":
    sys.exit(main())
