#!/usr/bin/env python3
"""Bakes a real-world route pack for Torque Shed's adventure mode (experimental).

    python3 tools/route_bake.py --name shodoshima --title "Shodoshima" \\
        --lat 34.5184 --lon 134.2693 --length-km 25 --out data/routes/shodoshima

The route starts at the road nearest the given point and runs for about --length-km along real roads (or to
--end LAT LON, if given), steered by road class so it prefers main roads. The map is baked as a chain of
4 km "legs" the game swaps between as you ride, so a route can be as long as you like. Reads free, openly
licensed data and writes a folder the game loads (scripts/route_pack.gd, scripts/route_journey.gd):

    pack.json            the route: name, credits, legs, hand-over distances
    route.json           the planned route line and its turn-by-turn instructions (for the satnav)
    legs/leg00/...       per leg: heights.u16, roads.json, buildings.json (the land the game builds)

Heights come from Mapterhorn (AWS Terrain Tiles as a fallback), roads and buildings from Overture Maps.
Everything is in the game's frame, +x east, -z north, metres. Leg 0 has the shed at its origin, with the
start point 800 m from it and a short link road from the shed's loop; later legs are centred on the route.

Needs numpy and Pillow; roads and buildings need pyarrow (pip install pyarrow). No API keys.
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

# The game's frame (scripts/world_terrain.gd, scripts/world_layout.gd).
SIZE = 1025
SPACING = 4.0
HALF = 2048.0
SHED_CENTRE = (0.0, -20.0)         # the middle of the shed's yard and loop road
LOOP_EAST = (200.0, -62.0)         # where the loop's east spur leaves it (WorldLayout "east")
START_WORLD = (800.0, -60.0)       # where the start point lands on the map, in leg 0
KEEP_OUT = 380.0                   # no real roads this close to the shed; the terrain blends flat inside
FLAT_FROM, FLAT_TO = 380.0, 800.0  # the real land fades in over this distance from the shed
SNAP_START_M = 500.0               # the start point must be this close to a road
LEG_REACH = 1700.0                 # the route stays within this of a leg's centre, so there is a margin
OVERLAP_M = 300.0                  # consecutive legs share this much route, and hand over in the middle of it

MAPTERHORN = "https://tiles.mapterhorn.com/{z}/{x}/{y}.webp"
AWS = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
OVERTURE_STAC = "https://stac.overturemaps.org/catalog.json"
OVERTURE_BUCKET = "overturemaps-us-west-2"
USER_AGENT = "torque-shed-route-bake/0.2 (https://github.com/Beenster99/torque-shed)"

# Road classes the game rides, best first: class -> (kind, half width m, steepest grade, route cost factor).
CLASSES = {
    "motorway": ("tarmac", 4.5, 0.10, 0.7), "trunk": ("tarmac", 4.0, 0.12, 0.75), "primary": ("tarmac", 3.75, 0.12, 0.8),
    "secondary": ("tarmac", 3.5, 0.13, 0.9), "tertiary": ("tarmac", 3.25, 0.14, 1.0),
    "unclassified": ("tarmac", 3.0, 0.15, 1.15), "residential": ("tarmac", 3.0, 0.15, 1.3),
    "living_street": ("tarmac", 2.75, 0.15, 1.4), "track": ("dirt", 2.0, 0.25, 3.0),
}
RANK = {c: i for i, c in enumerate(CLASSES)}
UNPAVED = {"unpaved", "gravel", "dirt", "ground", "grass", "sand", "mud", "compacted", "fine_gravel", "pebblestone"}
GENERIC_NAMES = {"motorway": "Motorway", "trunk": "Trunk road", "primary": "Main road", "secondary": "B road",
                 "tertiary": "Minor road", "unclassified": "Minor road", "residential": "Street",
                 "living_street": "Street", "track": "Track"}

SEA_ABS = 0.4          # ground this low (metres above sea level) is sea
SEA_DEPTH = 35.0       # how deep the sea floor goes, far from the shore
SEA_SHORE_M = 160.0    # over about this far the floor slopes down from the shore

BUILDING_MIN_AREA = 22.0
BUILDING_MAX_AREA = 2500.0
BUILDING_MAX = 1400            # per leg: the nearest to the route are kept
BUILDING_ROAD_GAP = 3.5        # clear of a road's edge by at least this

CREDITS = [
    "Elevation: Mapterhorn (mapterhorn.com), built from national and global terrain models; sources and "
    "licences are listed at https://download.mapterhorn.com/attribution.json.",
    "Roads and buildings: (c) OpenStreetMap contributors, Overture Maps Foundation (ODbL).",
]


# ---------------------------------------------------------------------------- geodesy

def metres_per_degree(lat):
    """(metres per degree of latitude, of longitude) at `lat` degrees, from the WGS84 series."""
    p = math.radians(lat)
    return (111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p),
            111412.84 * math.cos(p) - 93.5 * math.cos(3 * p) + 0.118 * math.cos(5 * p))


class Frame:
    """Game coordinates for latitude and longitude: x east, z south, with `start` metres for the anchor.

    Every leg's frame uses the anchor's latitude for its scale, so moving between two legs is a pure shift."""

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
        """The frame of a leg whose origin is `origin` in this frame's coordinates."""
        return Frame(self.lat, self.lon, (self.start[0] - origin[0], self.start[1] - origin[1]))


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
    for url in (MAPTERHORN, AWS):
        data = fetch(url.format(z=z, x=x, y=y), cache_dir)
        if data:
            h = decode_terrarium(Image.open(io.BytesIO(data)))
            return h, h.shape[0]
    raise RuntimeError("no elevation tile %d/%d/%d from Mapterhorn or AWS" % (z, x, y))


def sample_dem(frame, cache_dir, spacing=SPACING, size=SIZE, half=HALF, log=print):
    """The ground height in metres at every grid sample of a leg's map: a (size, size) array, [z][x]."""
    ax = np.arange(size) * spacing - half
    gx, gz = np.meshgrid(ax, ax)
    lat, lon = frame.to_geo(gx, gz)
    zoom = tile_zoom(float(np.mean(lat)), spacing)
    px, py = mercator_pixels(lat, lon, zoom, 1)
    tx0, tx1 = int(np.floor(px.min())), int(np.floor(px.max()))
    ty0, ty1 = int(np.floor(py.min())), int(np.floor(py.max()))
    log("  elevation: zoom %d, tiles x %d..%d y %d..%d" % (zoom, tx0, tx1, ty0, ty1))
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


def shape_heights(ground, base, shed=False, spacing=SPACING, size=SIZE, half=HALF):
    """(heights above `base`, sea level above `base` or None): the sea given a floor, the shed's ground level.

    Ground at or under SEA_ABS metres above sea level is sea. Its floor slopes away from the shore so the
    game's water has a beach to lap and some depth to hide the ground in; the sea's surface is at -base."""
    rel = ground - base
    sea_level = None
    sea = ground <= SEA_ABS
    if sea.sum() > 400:
        sea_level = float(-base)
        radius = max(2, int(SEA_SHORE_M / spacing / 2))
        depth = 2.0 + (SEA_DEPTH - 2.0) * np.clip(box_blur(sea.astype(float), radius) * 1.6, 0.0, 1.0)
        rel = np.where(sea, sea_level - depth, rel)
    if shed:
        ax = np.arange(size) * spacing - half
        gx, gz = np.meshgrid(ax, ax)
        d = np.hypot(gx - SHED_CENTRE[0], gz - SHED_CENTRE[1])
        rel = rel * smoothstep(FLAT_FROM, FLAT_TO, d)
    return rel, sea_level


def quantise(heights):
    """(uint16 array, lowest height, metres per step): the heights spread over the whole 16 bits."""
    lo, hi = float(heights.min()), float(heights.max())
    scale = max((hi - lo) / 65535.0, 1e-6)
    return np.round((heights - lo) / scale).astype("<u2"), lo, scale


# ---------------------------------------------------------------------------- Overture data

def latest_release():
    with urllib.request.urlopen(urllib.request.Request(OVERTURE_STAC, headers={"User-Agent": USER_AGENT}),
                                timeout=60) as r:
        cat = json.load(r)
    return cat.get("latest") or sorted(l["href"].split("/")[-2] for l in cat["links"] if l["rel"] == "child")[-1]


def _dataset(release, theme, kind):
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    s3 = pafs.S3FileSystem(anonymous=True, region="us-west-2")
    return ds.dataset("%s/release/%s/theme=%s/type=%s" % (OVERTURE_BUCKET, release, theme, kind),
                      filesystem=s3, format="parquet")


def _in_box(south, west, north, east):
    import pyarrow.compute as pc
    return ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
            & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))


def fetch_segments(south, west, north, east, release, log=print):
    """Overture road segments touching the box, as plain dicts (needs pyarrow)."""
    d = _dataset(release, "transportation", "segment")
    tb = d.to_table(columns=["id", "geometry", "subtype", "class", "connectors", "road_surface", "road_flags",
                             "names", "routes", "bbox"], filter=_in_box(south, west, north, east))
    log("roads: %d segments in the box" % tb.num_rows)
    return tb.to_pylist()


def fetch_buildings(south, west, north, east, release, log=print):
    """Overture building footprints touching the box, as plain dicts."""
    d = _dataset(release, "buildings", "building")
    tb = d.to_table(columns=["id", "geometry", "height", "num_floors", "class", "subtype"],
                    filter=_in_box(south, west, north, east))
    log("  buildings: %d footprints in the box" % tb.num_rows)
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
    """(class, kind, half width, grade) for a road segment the game rides, or None."""
    if seg.get("subtype") != "road" or seg.get("class") not in CLASSES:
        return None
    cls = seg["class"]
    kind, hw, grade, _ = CLASSES[cls]
    for rule in seg.get("road_surface") or []:
        if rule.get("between") is None and str(rule.get("value")) in UNPAVED:
            return cls, "dirt", min(hw, 2.4), max(grade, 0.25)
    return cls, kind, hw, grade


def parse_wkb(wkb):
    """The rings of a WKB LineString, MultiLineString, Polygon or MultiPolygon as lists of (lon, lat).

    Lines come back one list per line; polygons one list per exterior ring (holes are left out)."""
    def read(buf, off):
        order = "<" if buf[off] == 1 else ">"
        kind = struct.unpack_from(order + "I", buf, off + 1)[0] % 1000
        off += 5
        if kind == 2:
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            pts = struct.unpack_from(order + "%dd" % (2 * n), buf, off)
            return [list(zip(pts[0::2], pts[1::2]))], off + 16 * n
        if kind == 3:
            rings = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            out = []
            for k in range(rings):
                n = struct.unpack_from(order + "I", buf, off)[0]
                off += 4
                pts = struct.unpack_from(order + "%dd" % (2 * n), buf, off)
                off += 16 * n
                if k == 0:
                    out.append(list(zip(pts[0::2], pts[1::2])))
            return out, off
        if kind in (5, 6):
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            out = []
            for _ in range(n):
                part, off = read(buf, off)
                out += part
            return out, off
        raise ValueError("unsupported geometry type %d" % kind)
    return read(bytes(wkb), 0)[0]


parse_linestrings = parse_wkb


# ---------------------------------------------------------------------------- the road graph and the route

class Graph:
    """The ridden roads as a graph: nodes are Overture connectors, edges are road segments."""

    def __init__(self, segments, frame):
        self.edges = []     # {a, b, pts [(x, z)] from a to b, cls, label, length}
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
                e = {"a": a, "b": b, "pts": pts, "cls": info[0], "label": segment_label(s), "length": length_of(pts)}
                self.adj.setdefault(a, []).append((b, len(self.edges)))
                self.adj.setdefault(b, []).append((a, len(self.edges)))
                self.edges.append(e)

    def weight(self, ei):
        e = self.edges[ei]
        return e["length"] * CLASSES[e["cls"]][3]

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
    """(points, turns) for a path of (from, edge, to): the route's line and its instructions.

    Each turn is {"d" metres along the line, "x", "z", "turn", "onto" road name, "branches" other roads}."""
    pts = []
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
        pts.extend(line if not pts else line[1:])
    return pts, turns


def resample(pts, step=25.0):
    """The line through `pts` as points `step` metres apart (and its last point), plus cumulative distances."""
    out = [pts[0]]
    dist = [0.0]
    total = 0.0
    carry = 0.0
    for p, q in zip(pts, pts[1:]):
        seg = math.dist(p, q)
        if seg == 0:
            continue
        pos = step - carry
        while pos <= seg:
            t = pos / seg
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
            dist.append(total + pos)
            pos += step
        carry = seg - (pos - step)
        total += seg
    if out[-1] != pts[-1]:
        out.append(pts[-1])
        dist.append(total)
    return out, dist


def plan_legs(route, dist, shed_origin, reach=LEG_REACH, overlap=OVERLAP_M):
    """Splits a route (points and cumulative distances, global metres) into legs.

    Leg 0 is centred on `shed_origin`. Each later leg is centred on the box of the stretch it carries,
    which stays within `reach` of that centre, and starts `overlap` metres before the last leg ended.
    Returns [{"origin" (x, z), "first", "last" point indices, "enter_d", "exit_d"}]."""
    n = len(route)
    legs = []
    first = 0
    origin = shed_origin
    while True:
        last = first
        if not legs:
            while last + 1 < n and abs(route[last + 1][0] - origin[0]) <= reach and abs(route[last + 1][1] - origin[1]) <= reach:
                last += 1
        else:
            lo_x = hi_x = route[first][0]
            lo_z = hi_z = route[first][1]
            while last + 1 < n:
                p = route[last + 1]
                if max(hi_x, p[0]) - min(lo_x, p[0]) > 2 * reach or max(hi_z, p[1]) - min(lo_z, p[1]) > 2 * reach:
                    break
                lo_x, hi_x = min(lo_x, p[0]), max(hi_x, p[0])
                lo_z, hi_z = min(lo_z, p[1]), max(hi_z, p[1])
                last += 1
            origin = ((lo_x + hi_x) / 2.0, (lo_z + hi_z) / 2.0)
        if last == first and last + 1 < n:
            last = first + 1     # always make progress
        legs.append({"origin": origin, "first": first, "last": last, "enter_d": dist[first], "exit_d": dist[last]})
        if last >= n - 1:
            break
        # The next leg starts overlap metres back from where this one ended.
        nxt = last
        while nxt > first and dist[last] - dist[nxt] < overlap:
            nxt -= 1
        first = max(nxt, first + 1)
    return legs


# ---------------------------------------------------------------------------- roads for a leg

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


def length_of(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def build_chains(segments, frame):
    """Joins segments that meet end to end at a two-way connector into longer roads.

    Returns chains: {pts [(x, z)], start_node, end_node, cls, kind, hw, grade, label}. Chains always end at a
    connector where three or more roads meet (or at a dead end), so every junction is a chain end."""
    segs = []
    for s in segments:
        info = segment_kind(s)
        if info is None or not s.get("connectors") or len(s["connectors"]) < 2:
            continue
        cons = sorted(s["connectors"], key=lambda c: c["at"])
        for line in parse_wkb(s["geometry"]):
            if len(line) < 2:
                continue
            lon, lat = zip(*line)
            x, z = frame.to_world(np.array(lat), np.array(lon))
            pts = list(zip(x.tolist(), z.tolist()))
            segs.append({"pts": pts, "a": cons[0]["connector_id"], "b": cons[-1]["connector_id"], "info": info,
                         "label": segment_label(s), "length": length_of(pts)})
    ends = {}
    for i, s in enumerate(segs):
        ends.setdefault(s["a"], []).append(i)
        ends.setdefault(s["b"], []).append(i)
    used = [False] * len(segs)
    chains = []

    def best(i1, i2):
        return i1 if RANK[i1[0]] <= RANK[i2[0]] else i2

    def extend(pts, members, node, info, forward):
        """Follows the road on from `node` while it stays a plain two-way join of the same kind."""
        while True:
            at = ends[node]
            if len(at) != 2:
                return node, info
            other = [j for j in at if not used[j]]
            if len(other) != 1 or segs[other[0]]["info"][1] != info[1]:
                return node, info
            j = other[0]
            used[j] = True
            s = segs[j]
            members.append(j)
            line = s["pts"] if s["a"] == node else s["pts"][::-1]
            nxt = s["b"] if s["a"] == node else s["a"]
            if forward:
                pts.extend(line[1:])
            else:
                pts[:0] = line[:0:-1]
            node = nxt
            info = best(info, s["info"])

    for i, s in enumerate(segs):
        if used[i]:
            continue
        used[i] = True
        pts = list(s["pts"])
        members = [i]
        end_node, info = extend(pts, members, s["b"], s["info"], True)
        start_node, info = extend(pts, members, s["a"], info, False)
        # The chain's name is the one most of its length carries; unnamed roads get their class's.
        votes = {}
        for j in members:
            if segs[j]["label"]:
                votes[segs[j]["label"]] = votes.get(segs[j]["label"], 0.0) + segs[j]["length"]
        label = max(votes, key=votes.get) if votes else GENERIC_NAMES[info[0]]
        chains.append({"pts": pts, "start_node": start_node, "end_node": end_node, "cls": info[0], "kind": info[1],
                       "hw": info[2], "grade": info[3], "label": label})
    return chains


def clip_chain(chain, centre=None, radius=KEEP_OUT, half=HALF - 8.0):
    """Pieces of `chain` inside the map and (when `centre` is given) outside the keep-out circle round the shed."""
    def inside(p):
        if abs(p[0]) > half or abs(p[1]) > half:
            return True
        return centre is not None and math.hypot(p[0] - centre[0], p[1] - centre[1]) < radius
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
        c = dict(chain)
        c["pts"] = pts
        c["start_node"] = chain["start_node"] if from_start else None
        c["end_node"] = chain["end_node"] if pts[-1] == chain["pts"][-1] else None
        out.append(c)
    return out


def link_points(a, b, step=100.0):
    """Control points for a straight link from `a` to `b`."""
    n = max(2, int(math.dist(a, b) / step))
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


def build_roads(chains, start=None, min_length=40.0, simplify=1.5, shed=False):
    """Road definitions for a leg: clipped, thinned, ordered best first, joined at junctions.

    With `shed`, roads stay clear of the shed and a link road runs from its loop to the road point nearest
    `start`. Returns (defs, start_point or None)."""
    pieces = []
    for c in chains:
        for p in clip_chain(c, SHED_CENTRE if shed else None):
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
        d = {"name": name, "label": c["label"], "kind": c["kind"], "hw": c["hw"], "grade": c["grade"],
             "cls": c["cls"], "pts": [[round(x, 2), round(z, 2)] for x, z in c["pts"]]}
        if c["kind"] == "dirt":
            d["hard"] = c["grade"] > 0.3
        for end, node in (("start", c["start_node"]), ("end", c["end_node"])):
            if node is not None and owner[node] != name:
                d[end] = owner[node]
        defs.append(d)
    if not shed:
        return defs, None
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
    defs.append({"name": "link", "label": "Link road", "kind": "tarmac", "hw": 3.5, "grade": 0.12, "cls": "tertiary",
                 "start": "loop", "end": road, "pts": [[round(x, 2), round(z, 2)] for x, z in link]})
    return defs, p


# ---------------------------------------------------------------------------- buildings

def min_rect(pts):
    """The smallest rectangle round a footprint's points (x, z): (centre x, centre z, width, depth, yaw).

    Width is along the rectangle's x axis after turning it by yaw (radians about the map's up, as the game
    turns things): a point at local (lx, lz) is at centre + (lx cos yaw + lz sin yaw, -lx sin yaw + lz cos yaw)."""
    p = np.asarray(pts, dtype=float)
    best = None
    for deg in range(0, 90, 3):
        yaw = math.radians(deg)
        c, s = math.cos(yaw), math.sin(yaw)
        lx = p[:, 0] * c - p[:, 1] * s
        lz = p[:, 0] * s + p[:, 1] * c
        w, d = lx.max() - lx.min(), lz.max() - lz.min()
        if best is None or w * d < best[0]:
            best = (w * d, yaw, (lx.max() + lx.min()) / 2, (lz.max() + lz.min()) / 2, w, d)
    _, yaw, mx, mz, w, d = best
    c, s = math.cos(yaw), math.sin(yaw)
    return (mx * c + mz * s, -mx * s + mz * c, w, d, yaw)


def building_kind(w, d):
    area = w * d
    if area < 32.0:
        return "shed"
    if area > 700.0 or (area > 200.0 and max(w, d) / max(min(w, d), 1.0) > 2.6):
        return "barn"
    return "house"


def make_buildings(rows, frame, roads, route=None):
    """Building records for a leg: footprints turned into the game's boxes, clear of roads, nearest the route first.

    Returns [{x, z, w, d, yaw, h, kind}] in leg coordinates. `roads` are the leg's road definitions."""
    road_pts = []
    for r in roads:
        pts = [tuple(p) for p in r["pts"]]
        for a, b in zip(pts, pts[1:]):
            seg = math.dist(a, b)
            n = max(1, int(seg / 6.0))
            for k in range(n):
                road_pts.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n, r["hw"]))
    cell = 32.0
    grid = {}
    for x, z, hw in road_pts:
        grid.setdefault((int(x // cell), int(z // cell)), []).append((x, z, hw))

    def clearance(cx, cz, reach):
        best = 1e9
        gx, gz = int(cx // cell), int(cz // cell)
        span = int(reach // cell) + 1
        for ix in range(gx - span, gx + span + 1):
            for iz in range(gz - span, gz + span + 1):
                for x, z, hw in grid.get((ix, iz), []):
                    best = min(best, math.hypot(cx - x, cz - z) - hw)
        return best

    out = []
    for row in rows:
        try:
            rings = parse_wkb(row["geometry"])
        except (ValueError, struct.error):
            continue
        for ring in rings:
            if len(ring) < 4:
                continue
            lon, lat = zip(*ring)
            x, z = frame.to_world(np.array(lat), np.array(lon))
            if np.max(np.abs(x)) > HALF - 20 or np.max(np.abs(z)) > HALF - 20:
                continue
            cx, cz, w, d, yaw = min_rect(list(zip(x.tolist(), z.tolist())))
            area = w * d
            if not (BUILDING_MIN_AREA <= area <= BUILDING_MAX_AREA) or min(w, d) < 2.5:
                continue
            half_diag = math.hypot(w, d) / 2.0
            if clearance(cx, cz, half_diag + 8.0) < BUILDING_ROAD_GAP + half_diag * 0.55:
                continue
            floors = row.get("num_floors")
            height = row.get("height")
            h = float(height) if height else (float(floors) * 3.0 if floors else 4.2)
            kind = building_kind(w, d)
            h = min(max(h, 2.8), 9.0) if kind != "barn" else min(max(h, 4.5), 9.0)
            out.append({"x": round(cx, 2), "z": round(cz, 2), "w": round(w, 2), "d": round(d, 2),
                        "yaw": round(yaw, 4), "h": round(h, 2), "kind": kind})
    if route:
        rp = np.array(route)

        def dist_to_route(b):
            return float(np.min(np.hypot(rp[:, 0] - b["x"], rp[:, 1] - b["z"])))
        out.sort(key=dist_to_route)
    return out[:BUILDING_MAX]


def flatten_under(rel, buildings, spacing=SPACING, size=SIZE, half=HALF, margin=2.5, feather=4.0):
    """Levels the ground under each building to its mean height, feathered into the land round it."""
    for b in buildings:
        reach = math.hypot(b["w"], b["d"]) / 2.0 + margin + feather
        i0 = max(0, int((b["x"] - reach + half) / spacing))
        i1 = min(size - 1, int((b["x"] + reach + half) / spacing) + 1)
        j0 = max(0, int((b["z"] - reach + half) / spacing))
        j1 = min(size - 1, int((b["z"] + reach + half) / spacing) + 1)
        if i1 <= i0 or j1 <= j0:
            continue
        gx = np.arange(i0, i1 + 1) * spacing - half
        gz = np.arange(j0, j1 + 1) * spacing - half
        X, Z = np.meshgrid(gx, gz)
        c, s = math.cos(b["yaw"]), math.sin(b["yaw"])
        lx = (X - b["x"]) * c - (Z - b["z"]) * s
        lz = (X - b["x"]) * s + (Z - b["z"]) * c
        outside = np.maximum(np.maximum(np.abs(lx) - b["w"] / 2.0, np.abs(lz) - b["d"] / 2.0), 0.0)
        inner = outside <= 0.0
        block = rel[j0:j1 + 1, i0:i1 + 1]
        if not inner.any():
            continue
        level = float(block[inner].mean())
        weight = 1.0 - smoothstep(margin, margin + feather, outside)
        rel[j0:j1 + 1, i0:i1 + 1] = block * (1.0 - weight) + level * weight
    return rel


# ---------------------------------------------------------------------------- the pack

def write_leg(out, index, heights, roads, buildings, sea_level):
    d = os.path.join(out, "legs", "leg%02d" % index)
    os.makedirs(d, exist_ok=True)
    q, lo, scale = quantise(heights)
    q.tofile(os.path.join(d, "heights.u16"))
    with open(os.path.join(d, "roads.json"), "w") as f:
        json.dump(roads, f, separators=(",", ":"))
    with open(os.path.join(d, "buildings.json"), "w") as f:
        json.dump(buildings, f, separators=(",", ":"))
    return {"dir": "legs/leg%02d" % index, "height": {"min": lo, "scale": scale}, "sea_level": sea_level,
            "road_count": len(roads), "building_count": len(buildings)}


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
    g = Frame(args.lat, args.lon)           # the global frame: metres from the given point
    length_m = args.length_km * 1000.0
    # Roads for the whole area the route could use.
    if args.end:
        ex, ez = g.to_world(args.end[0], args.end[1])
        box = (min(0.0, float(ex)) - 4000.0, min(0.0, float(ez)) - 4000.0, max(0.0, float(ex)) + 4000.0,
               max(0.0, float(ez)) + 4000.0)
    else:
        r = min(length_m * 0.8 + 3000.0, 60000.0)
        box = (-r, -r, r, r)
    lat_n, lon_w = g.to_geo(box[0], box[1])
    lat_s, lon_e = g.to_geo(box[2], box[3])
    segments = fetch_segments(float(lat_s), float(lon_w), float(lat_n), float(lon_e), release, log)
    graph = Graph(segments, g)
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
    cost, length, prev = graph.dijkstra(start)
    if end not in prev and end != start:
        raise SystemExit("the end cannot be reached by road from the start")
    steps = graph.path(prev, start, end)
    route_pts, turns = route_from_path(graph, steps)
    if warn:
        log("WARNING: " + warn)
    s_global = graph.pos[start]
    log("route: %.1f km, %d turns" % (length_of(route_pts) / 1000.0, len(turns)))

    # The shed's leg: its frame origin is where the start would be if it sat at START_WORLD.
    shed_origin = (s_global[0] - START_WORLD[0], s_global[1] - START_WORLD[1])
    pts, dist = resample(route_pts, 25.0)
    legs = plan_legs(pts, dist, shed_origin)
    log("legs: %d" % len(legs))

    # The link from the shed's loop to the start, in leg 0's coordinates, then the same in global metres.
    link_len = 0.0
    legs_meta = []
    all_turns = turns
    for k, leg in enumerate(legs):
        log("leg %d/%d: route %.1f to %.1f km" % (k + 1, len(legs), leg["enter_d"] / 1000.0, leg["exit_d"] / 1000.0))
        frame = g.shifted(leg["origin"])
        # Heights and sea.
        ground = sample_dem(frame, args.cache, log=log)
        ix = int(round(HALF / SPACING))
        base = float(ground[ix, ix]) if k else float(ground[int(round((START_WORLD[1] + HALF) / SPACING)),
                                                          int(round((START_WORLD[0] + HALF) / SPACING))])
        rel, sea_level = shape_heights(ground, base, shed=(k == 0))
        # Roads, then the buildings that fit between them.
        half_box = HALF + 200.0
        lat_n, lon_w = frame.to_geo(-half_box, -half_box)
        lat_s, lon_e = frame.to_geo(half_box, half_box)
        inside = [s for s in segments if s["bbox"]["xmin"] < float(lon_e) and s["bbox"]["xmax"] > float(lon_w)
                  and s["bbox"]["ymin"] < float(lat_n) and s["bbox"]["ymax"] > float(lat_s)]
        chains = build_chains(inside, frame)
        start_local = (s_global[0] - leg["origin"][0], s_global[1] - leg["origin"][1])
        roads, start_point = build_roads(chains, start=start_local, shed=(k == 0))
        buildings = []
        if not args.no_buildings:
            rows = fetch_buildings(float(lat_s), float(lon_w), float(lat_n), float(lon_e), release, log)
            local_route = [(p[0] - leg["origin"][0], p[1] - leg["origin"][1]) for p in pts[leg["first"]:leg["last"] + 1]]
            buildings = make_buildings(rows, frame, roads, local_route)
            rel = flatten_under(rel, buildings)
            log("  %d buildings kept" % len(buildings))
        meta = write_leg(args.out, k, rel, roads, buildings, sea_level)
        meta["origin"] = [round(leg["origin"][0], 2), round(leg["origin"][1], 2)]
        meta["shed"] = k == 0
        meta["base_elev"] = round(base, 2)
        meta["enter_d"] = round(leg["enter_d"], 1)
        meta["exit_d"] = round(leg["exit_d"], 1)
        legs_meta.append(meta)
        if k == 0:
            link = link_points(LOOP_EAST, start_point)
            link_len = length_of(link)
            link_global = [(p[0] + leg["origin"][0], p[1] + leg["origin"][1]) for p in link]
    # Hand-overs: halfway through each overlap; each leg's shift to the next.
    for k, meta in enumerate(legs_meta):
        if k + 1 < len(legs_meta):
            nxt = legs_meta[k + 1]
            meta["hand_over_d"] = round((nxt["enter_d"] + meta["exit_d"]) / 2.0 + link_len, 1)
            meta["to_next"] = [round(meta["origin"][0] - nxt["origin"][0], 2), round(meta["origin"][1] - nxt["origin"][1], 2)]
        else:
            meta["hand_over_d"] = None
            meta["to_next"] = None
    # The route as the satnav reads it: the link, then the roads, distances from the loop.
    route_all = [list(p) for p in link_global[:-1]] + [list(p) for p in route_pts]
    cum = [0.0]
    for a, b in zip(route_all, route_all[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    for t in all_turns:
        t["d"] = round(t["d"] + link_len, 1)
    all_turns.append({"d": round(cum[-1], 1), "x": round(route_all[-1][0], 1), "z": round(route_all[-1][1], 1),
                      "turn": "arrive", "onto": "", "branches": 0})
    with open(os.path.join(args.out, "route.json"), "w") as f:
        json.dump({"points": [[round(p[0], 1), round(p[1], 1)] for p in route_all], "length_m": round(cum[-1], 1),
                   "turns": all_turns}, f, separators=(",", ":"))
    end_geo = g.to_geo(route_all[-1][0], route_all[-1][1])
    meta = {
        "format": 2, "name": args.name, "title": args.title or args.name,
        "anchor": {"lat": args.lat, "lon": args.lon}, "grid": {"size": SIZE, "spacing": SPACING},
        "route": {"length_m": round(cum[-1], 1), "requested_km": None if args.end else args.length_km,
                  "end": {"lat": round(float(end_geo[0]), 6), "lon": round(float(end_geo[1]), 6)},
                  "warning": warn},
        "legs": legs_meta, "sources": {"overture_release": release, "elevation": "Mapterhorn, AWS Terrain Tiles fallback"},
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
    ap.add_argument("--length-km", type=float, default=None, help="how long the route should be (default 20)")
    ap.add_argument("--seed", type=int, default=0, help="breaks ties between equally good ends")
    ap.add_argument("--out", help="folder to write (default data/routes/NAME)")
    ap.add_argument("--no-buildings", action="store_true", help="leave out the buildings (faster)")
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
        args.length_km = 20.0
    args.out = args.out or os.path.join("data", "routes", args.name)
    meta = bake(args)
    print("wrote %s: %d legs, route %.1f km, hash %s" % (args.out, len(meta["legs"]), meta["route"]["length_m"] / 1000.0,
                                                         meta["hash"]))


if __name__ == "__main__":
    sys.exit(main())
