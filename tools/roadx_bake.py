#!/usr/bin/env python3
"""The road itself, from OpenStreetMap (OSM stage 5, "the road itself"): what a cell's roads are like close up, which
Overture leaves out (lane counts, the roundabout flag, traffic lights, crossings, humps, passing places, lit roads,
pavements, parking, crash barriers), joined to the roads the cell's other files already have.

    python3 tools/roadx_bake.py --pbf CUT.osm.pbf --cell ROW COL --out FILE [--release R]
    python3 tools/roadx_bake.py --pbf CUT.osm.pbf --square LAT LON --out DIR [--release R]   # a 1 degree square's cells

CUT is an OpenStreetMap extract (Geofabrik's Great Britain one, cut to the square with `osmium extract`: the
torque-shed-world workflow does that once a run). The Overture road segments of the cells are read too, for their ids
and the OSM way each came from (its "sources"), because the game knows a road edge by its Overture segment ("g" in a
cell's roads, region_bake.py) and not by the way.

A cell's file, roadx/cROW_COL.json (FORMAT 1):

    {"format": 1, "cell": "ROW_COL", "release": R, "osm": "extract's timestamp", "matched": [ways found, segments],
     "edge_cols": EDGE_COLS, "edges": [[g, lanes, fwd, bwd, width_dm, flags, park_l, park_r,
                                        maxheight_dm, maxwidth_dm, maxweight_dt, half], ...],
     "kinds": KINDS, "points": [[kind, lat, lon, heading, flags], ...],
     "lines": [[kind, lat, lon, dlat, dlon, ...], ...]}

An edge row is there only where the map says something the game's rules would not (a road with nothing tagged leaves
the game to its rules: by class and the built-up rule). g is the segment's short id (region_bake.short_id); lanes,
fwd and bwd the lane counts (0: not mapped); width_dm the recorded width in decimetres (0 none); flags EDGE_FLAGS bits;
park_l and park_r PARKING (index, 0 not mapped) on the left and right as the segment runs; the limits in decimetres
and tenths of a tonne (0 none: shown on the planner, never enforced); half the g of the other half of a dual
carriageway ("" none): the one-way road of the same number or name running the other way within HALF_M.

A point is a thing on the road at a node: kind an index into KINDS, lat and lon in 1e-5 degrees, heading the
direction (degrees from north, clockwise) of the traffic it governs where the map says (a stop line's, a light's: -1
where it doesn't), flags POINT_FLAGS. The game snaps each to its nearest road edge within SNAP_M; a point is in the
cell it stands in. A line (crash barriers, guard rails) is cut to the cell's box, its points after the first the step
from the one before, as feature_bake.py's are.

Mapped first, rule second, never both: the game draws a mapped edge's lanes, lamps and crossings and keeps its own
rules off it. OpenStreetMap is ODbL. Needs pyosmium (and pyarrow for the Overture read). No API keys.
"""
import argparse
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import region_bake  # noqa: E402
import sketch_bake  # noqa: E402

FORMAT = 1
SCALE = sketch_bake.SCALE
# A dual carriageway's halves are never paired further apart than this (m): two separate roads with ground between
# are acceptable, a wrong pair is not.
HALF_M = 40.0
# How far (m) the game snaps a point to an edge (documented here, used there).
SNAP_M = 3.0

EDGE_COLS = ["g", "lanes", "fwd", "bwd", "width_dm", "flags", "park_l", "park_r", "maxheight_dm", "maxwidth_dm",
             "maxweight_dt", "half"]
EDGE_FLAGS = {"roundabout": 1, "lit": 2, "unlit": 4, "pave_left": 8, "pave_right": 16, "pave_none": 32,
              "embankment": 64, "cutting": 128, "private": 256, "bus_lane": 512, "cycle_lane": 1024, "turn_lanes": 2048,
              "building": 4096, "oneway": 8192}
PARKING = ["", "none", "bays", "no_parking", "no_stopping"]
KINDS = ["traffic_signals", "crossing_zebra", "crossing_signals", "crossing_plain", "crossing_unmarked",
         "mini_roundabout", "passing_place", "turning_circle", "stop", "give_way",
         "hump", "bump", "table", "cushion", "chicane", "narrowing", "rumble_strip", "island",
         "guard_rail", "concrete_barrier"]
POINT_FLAGS = {"island": 1, "both_ways": 2}
CALMING = {"hump": "hump", "bump": "bump", "table": "table", "cushion": "cushion", "chicane": "chicane",
           "choker": "narrowing", "rumble_strip": "rumble_strip", "island": "island", "yes": "hump"}
BARRIERS = {"guard_rail": "guard_rail", "jersey_barrier": "concrete_barrier"}
POINT_HIGHWAY = {"traffic_signals", "crossing", "mini_roundabout", "passing_place", "turning_circle", "stop",
                 "give_way"}
# The roads a ride can take (OSM's highway values): ways of other kinds are read only for their barriers.
ROADS = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street",
         "service", "track", "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link", "road"}
SEGMENT_COLUMNS = ["id", "geometry", "subtype", "sources"]


# ---------------------------------------------------------------------------- reading tags

def way_of(sources):
    """The OSM way id an Overture segment came from (its sources' record_id "w123@4"), or None."""
    for s in sources or ():
        rid = (s or {}).get("record_id") or ""
        m = re.match(r"w(\d+)", rid)
        if m and (s.get("dataset") or "OpenStreetMap") == "OpenStreetMap":
            return int(m.group(1))
    return None


def number(v, unit_scale=None):
    """A tag's number ("7.3", "7.3 m", "6'6\"", "7.5 t", "4 lanes"), or None. Feet and inches are turned to metres."""
    if v is None:
        return None
    s = str(v).strip().lower()
    m = re.match(r"^(\d+)\s*'\s*(\d+(?:\.\d+)?)?\s*\"?$", s)   # 6'6"
    if m:
        return round(int(m.group(1)) * 0.3048 + float(m.group(2) or 0) * 0.0254, 2)
    m = re.match(r"^(\d+(?:\.\d+)?)\s*(ft|feet)$", s)
    if m:
        return round(float(m.group(1)) * 0.3048, 2)
    m = re.match(r"^(\d+(?:[.,]\d+)?)", s)
    if not m:
        return None
    return float(m.group(1).replace(",", "."))


def lanes_of(tags):
    """(lanes, forward, backward) from the tags; 0 where not mapped."""
    total = int(number(tags.get("lanes")) or 0)
    fwd = int(number(tags.get("lanes:forward")) or 0)
    bwd = int(number(tags.get("lanes:backward")) or 0)
    if oneway_of(tags) != 0 and total and not fwd:
        fwd = total
    if not total and (fwd or bwd):
        total = fwd + bwd
    return min(total, 12), min(fwd, 12), min(bwd, 12)


def oneway_of(tags):
    """1 the way's own direction, -1 against it, 0 both ways (a roundabout and a motorway are one-way)."""
    v = (tags.get("oneway") or "").lower()
    if v in ("yes", "true", "1"):
        return 1
    if v in ("-1", "reverse"):
        return -1
    if v == "no":
        return 0
    if tags.get("junction") in ("roundabout", "circular") or tags.get("highway") == "motorway":
        return 1
    return 0


def parking_side(tags, side):
    """PARKING index for one side ("left" or "right"), from the current and the older parking schemes."""
    def get(*keys):
        for k in keys:
            v = tags.get(k)
            if v:
                return v.lower()
        return ""
    restriction = get("parking:%s:restriction" % side, "parking:both:restriction",
                      "parking:condition:%s" % side, "parking:condition:both")
    kind = get("parking:%s" % side, "parking:both", "parking:lane:%s" % side, "parking:lane:both")
    if restriction in ("no_stopping", "no_standing") or kind in ("no_stopping", "no_standing"):
        return PARKING.index("no_stopping")
    if restriction == "no_parking" or kind == "no_parking":
        return PARKING.index("no_parking")
    if kind in ("lane", "street_side", "on_kerb", "half_on_kerb", "shoulder", "yes", "parallel", "diagonal",
                "perpendicular", "marked"):
        return PARKING.index("bays")
    if kind in ("no", "separate"):
        return PARKING.index("none")
    return 0


def edge_flags(tags):
    f = 0
    if tags.get("junction") in ("roundabout", "circular"):
        f |= EDGE_FLAGS["roundabout"]
    lit = (tags.get("lit") or "").lower()
    if lit in ("yes", "24/7", "automatic", "sunset-sunrise", "limited", "interval"):
        f |= EDGE_FLAGS["lit"]
    elif lit == "no":
        f |= EDGE_FLAGS["unlit"]
    side = (tags.get("sidewalk") or tags.get("footway") or "").lower()
    left = tags.get("sidewalk:left") or tags.get("sidewalk:both")
    right = tags.get("sidewalk:right") or tags.get("sidewalk:both")
    if side in ("both", "left") or left in ("yes", "separate"):
        f |= EDGE_FLAGS["pave_left"]
    if side in ("both", "right") or right in ("yes", "separate"):
        f |= EDGE_FLAGS["pave_right"]
    if side in ("no", "none") or (left == "no" and right == "no"):
        f |= EDGE_FLAGS["pave_none"]
    if tags.get("embankment") in ("yes", "both", "left", "right"):
        f |= EDGE_FLAGS["embankment"]
    if tags.get("cutting") in ("yes", "both", "left", "right"):
        f |= EDGE_FLAGS["cutting"]
    if (tags.get("access") or "").lower() in ("private", "no") or (tags.get("motor_vehicle") or "").lower() in ("private", "no"):
        f |= EDGE_FLAGS["private"]
    if any(tags.get(k) for k in ("busway", "busway:left", "busway:right", "busway:both", "lanes:bus", "bus:lanes")):
        f |= EDGE_FLAGS["bus_lane"]
    if any((tags.get(k) or "") in ("lane", "track", "share_busway") for k in ("cycleway", "cycleway:left", "cycleway:right", "cycleway:both")):
        f |= EDGE_FLAGS["cycle_lane"]
    if any(tags.get(k) for k in ("turn:lanes", "turn:lanes:forward", "turn:lanes:backward")):
        f |= EDGE_FLAGS["turn_lanes"]
    if tags.get("highway") == "construction":
        f |= EDGE_FLAGS["building"]
    if oneway_of(tags) != 0:
        f |= EDGE_FLAGS["oneway"]
    return f


def edge_row(g, tags, reverse=False):
    """An edge's row (EDGE_COLS, half filled in later), or None when the map says nothing the rules wouldn't. reverse:
    the segment runs against its way (its left is the way's right)."""
    lanes, fwd, bwd = lanes_of(tags)
    if reverse:
        fwd, bwd = bwd, fwd
    width = number(tags.get("width") or tags.get("width:carriageway"))
    width_dm = int(round(width * 10)) if width and 1.5 <= width <= 40 else 0
    flags = edge_flags(tags)
    pl, pr = parking_side(tags, "left"), parking_side(tags, "right")
    if reverse:
        pl, pr = pr, pl
        a, b = flags & EDGE_FLAGS["pave_left"], flags & EDGE_FLAGS["pave_right"]
        flags &= ~(EDGE_FLAGS["pave_left"] | EDGE_FLAGS["pave_right"])
        flags |= (EDGE_FLAGS["pave_right"] if a else 0) | (EDGE_FLAGS["pave_left"] if b else 0)
    mh = number(tags.get("maxheight"))
    mw = number(tags.get("maxwidth"))
    mwt = number(tags.get("maxweight"))
    row = [g, lanes, fwd, bwd, width_dm, flags, pl, pr, int(round((mh or 0) * 10)) if mh and mh < 10 else 0,
           int(round((mw or 0) * 10)) if mw and mw < 10 else 0, int(round((mwt or 0) * 10)) if mwt and mwt < 100 else 0, ""]
    if not any(row[1:11]) or row[1:11] == [0, 0, 0, 0, EDGE_FLAGS["oneway"], 0, 0, 0, 0, 0]:
        return None
    return row


def point_kind(tags):
    """KINDS name for a tagged node, or None."""
    hw = tags.get("highway")
    if hw == "crossing" or (hw == "traffic_signals" and tags.get("crossing") == "traffic_signals"
                            and tags.get("traffic_signals") == "crossing"):
        c = (tags.get("crossing") or "").lower()
        ref = (tags.get("crossing_ref") or "").lower()
        if ref == "zebra" or c == "zebra":
            return "crossing_zebra"
        if c == "traffic_signals" or ref in ("pelican", "puffin", "toucan", "pegasus", "tiger"):
            return "crossing_signals"
        if c in ("unmarked", "no", "informal"):
            return "crossing_unmarked"
        return "crossing_plain"
    if hw in POINT_HIGHWAY:
        return hw
    calm = tags.get("traffic_calming")
    if calm:
        return CALMING.get(calm.lower())
    return None


def point_flags(tags):
    f = 0
    if (tags.get("crossing:island") or "").lower() == "yes" or tags.get("traffic_calming") == "island":
        f |= POINT_FLAGS["island"]
    if (tags.get("direction") or tags.get("traffic_signals:direction") or "").lower() == "both":
        f |= POINT_FLAGS["both_ways"]
    return f


# ---------------------------------------------------------------------------- geometry

def metres(lat0):
    """(m per degree of lon, of lat) at lat0."""
    return 111320.0 * math.cos(math.radians(lat0)), 110540.0


def bearing(a, b):
    """Degrees from north, clockwise, from (lat, lon) a to b."""
    mx, my = metres(a[0])
    return math.degrees(math.atan2((b[1] - a[1]) * mx, (b[0] - a[0]) * my)) % 360.0


def dist_to_line(p, line):
    """Least distance (m) from (lat, lon) p to a polyline of (lat, lon)."""
    mx, my = metres(p[0])
    best = float("inf")
    px, py = p[1] * mx, p[0] * my
    for a, b in zip(line, line[1:]):
        ax, ay, bx, by = a[1] * mx, a[0] * my, b[1] * mx, b[0] * my
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy
        t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
        best = min(best, math.hypot(ax + t * dx - px, ay + t * dy - py))
    if len(line) == 1:
        best = math.hypot(line[0][1] * mx - px, line[0][0] * my - py)
    return best


def midpoint(line):
    """The point halfway along a polyline of (lat, lon)."""
    mx, my = metres(line[0][0])
    seg = [math.hypot((b[1] - a[1]) * mx, (b[0] - a[0]) * my) for a, b in zip(line, line[1:])]
    half = sum(seg) / 2.0
    for (a, b), s in zip(zip(line, line[1:]), seg):
        if half <= s and s > 0:
            t = half / s
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        half -= s
    return line[len(line) // 2]


def general_bearing(line):
    return bearing(line[0], line[-1])


def angle_between(a, b):
    d = abs(a - b) % 360.0
    return 360.0 - d if d > 180.0 else d


def wkb_line(wkb):
    """A WKB linestring as [(lat, lon)] (feature_bake's reader, turned round)."""
    import feature_bake
    pts, lines, _ = feature_bake.parse_any(wkb)
    line = lines[0] if lines else pts
    return [(lat, lon) for lon, lat in line]


def inside(p, box):
    s, w, n, e = box
    return s <= p[0] < n and w <= p[1] < e


# ---------------------------------------------------------------------------- the map

class OsmCut:
    """What the bake needs from an extract: road ways (tags, node ids, points), tagged nodes, barrier lines."""

    def __init__(self):
        self.ways = {}        # id: (tags, [node id], [(lat, lon)])
        self.nodes = {}       # id: (tags, (lat, lon))
        self.barriers = []    # (kind, [(lat, lon)])
        self.not_roads = set()   # the ids of ways for walkers and riders (footways, paths, cycleways): not a road's
        self.timestamp = ""

    @classmethod
    def read(cls, path, box=None, way_ids=None):
        """Reads an .osm.pbf (or .osm) file. box (S, W, N, E) keeps only what touches it; way_ids keeps only those
        road ways (and every barrier)."""
        import osmium
        out = cls()
        try:
            hdr = osmium.io.Reader(path, osmium.osm.osm_entity_bits.NOTHING).header()
            out.timestamp = hdr.get("osmosis_replication_timestamp") or hdr.get("timestamp") or ""
        except Exception:   # noqa: BLE001 (a header without a stamp: the bake still stands)
            out.timestamp = ""
        fp = osmium.FileProcessor(path).with_locations().with_filter(osmium.filter.EmptyTagFilter())
        for o in fp:
            if o.is_node():
                tags = {t.k: t.v for t in o.tags}
                if point_kind(tags) is None:
                    continue
                p = (o.location.lat, o.location.lon)
                if box is None or inside(p, box):
                    out.nodes[o.id] = (tags, p)
            elif o.is_way():
                hw = o.tags.get("highway")
                barrier = o.tags.get("barrier")
                if barrier in BARRIERS:
                    pts = [(n.lat, n.lon) for n in o.nodes if n.location.valid()]
                    if len(pts) >= 2 and (box is None or any(inside(p, box) for p in pts)):
                        out.barriers.append((BARRIERS[barrier], pts))
                    continue
                if hw not in ROADS and hw != "construction":
                    if hw:
                        out.not_roads.add(o.id)
                    continue
                if way_ids is not None and o.id not in way_ids:
                    continue
                tags = {t.k: t.v for t in o.tags}
                refs = [n.ref for n in o.nodes]
                pts = [(n.lat, n.lon) if n.location.valid() else None for n in o.nodes]
                out.ways[o.id] = (tags, refs, pts)
        return out


# ---------------------------------------------------------------------------- the bake

def node_heading(way, node_id, forward=True):
    """The direction (degrees) a way runs through one of its nodes, or turned round."""
    tags, refs, pts = way
    try:
        i = refs.index(node_id)
    except ValueError:
        return None
    a = pts[max(0, i - 1)]
    b = pts[min(len(pts) - 1, i + 1)]
    if a is None or b is None or a == b:
        return None
    h = bearing(a, b)
    return h if forward else (h + 180.0) % 360.0


def ways_by_node(ways):
    out = {}
    for wid, (tags, refs, _) in ways.items():
        for r in refs:
            out.setdefault(r, []).append(wid)
    return out


def point_heading(tags, node_id, on_ways, ways):
    """Which way a stop line, give-way line or light faces: the direction of the traffic it governs (-1 unknown)."""
    d = (tags.get("direction") or tags.get("traffic_signals:direction") or "").lower()
    if d not in ("forward", "backward"):
        try:
            return int(round(float(d))) % 360 if d else -1
        except ValueError:
            return -1
    for wid in on_ways.get(node_id, ()):
        h = node_heading(ways[wid], node_id, d == "forward")
        if h is not None:
            return int(round(h)) % 360
    return -1


def pair_halves(segs):
    """The other half of each dual carriageway segment: {g: g of the other half}. segs: [(g, tags, line)] of the
    one-way road segments. A pair has the same road number (else name), runs the other way, and lies within HALF_M."""
    keyed = {}
    for g, tags, line in segs:
        if oneway_of(tags) == 0 or len(line) < 2:
            continue
        key = (tags.get("ref") or "").replace(" ", "").upper() or ("n:" + tags["name"] if tags.get("name") else "")
        if key and not tags.get("junction"):
            keyed.setdefault(key, []).append((g, line, general_bearing(line) if oneway_of(tags) > 0 else (general_bearing(line) + 180.0) % 360.0))
    halves = {}
    for key, group in keyed.items():
        for g, line, h in group:
            mid = midpoint(line)
            best, best_d = "", HALF_M
            for g2, line2, h2 in group:
                if g2 == g or angle_between(h, h2) < 150.0:
                    continue
                d = dist_to_line(mid, line2)
                if d < best_d:
                    best, best_d = g2, d
            if best:
                halves[g] = best
    return halves


def flat_line(pts):
    """[lat, lon, dlat, dlon, ...] in 1e-5 degrees (feature_bake's style)."""
    out = []
    plat = plon = 0
    for i, (lat, lon) in enumerate(pts):
        a, b = int(round(lat * SCALE)), int(round(lon * SCALE))
        out += [a, b] if i == 0 else [a - plat, b - plon]
        plat, plon = a, b
    return out


def clip_to(pts, box):
    """The pieces of a polyline inside box (by whole steps: a step with either end in is kept)."""
    pieces, cur = [], []
    for a, b in zip(pts, pts[1:]):
        if inside(a, box) or inside(b, box):
            if not cur:
                cur = [a]
            cur.append(b)
        elif cur:
            pieces.append(cur)
            cur = []
    if cur:
        pieces.append(cur)
    return pieces


def bake_cell(row, col, segments, osm, release=""):
    """A cell's roadx (FORMAT 1). segments: Overture rows (id, geometry WKB or "line" [(lat, lon)], sources) touching
    the cell; osm an OsmCut over it."""
    box = coast_bake.cell_box(row, col)
    edges = []
    one_way_segs = []
    matched = 0
    seen = set()
    for s in segments:
        g = region_bake.short_id(s["id"])
        if g in seen:
            continue
        seen.add(g)
        wid = way_of(s.get("sources"))
        way = osm.ways.get(wid) if wid is not None else None
        if way is None:
            if wid in osm.not_roads:
                seen.discard(g)   # (a footway's: the share matched counts the roads alone)
            continue
        matched += 1
        tags, refs, pts = way
        line = s.get("line") or (wkb_line(s["geometry"]) if s.get("geometry") else [])
        good = [p for p in pts if p is not None]
        reverse = False
        if len(line) >= 2 and len(good) >= 2:
            reverse = angle_between(general_bearing(line), general_bearing(good)) > 90.0
        r = edge_row(g, tags, reverse)
        if r is not None:
            edges.append(r)
        if len(line) >= 2:
            t = dict(tags)
            if reverse and oneway_of(tags) != 0:
                t["oneway"] = "-1" if oneway_of(tags) > 0 else "yes"
            one_way_segs.append((g, t, line))
    halves = pair_halves(one_way_segs)
    by_g = {r[0]: r for r in edges}
    for g, h in sorted(halves.items()):
        if g not in by_g:
            seg_tags = next(t for gg, t, _ in one_way_segs if gg == g)
            r = [g, 0, 0, 0, 0, edge_flags(seg_tags), 0, 0, 0, 0, 0, ""]
            edges.append(r)
            by_g[g] = r
        by_g[g][11] = h
    edges.sort(key=lambda r: r[0])

    on_ways = ways_by_node(osm.ways)
    points = []
    for nid, (tags, p) in sorted(osm.nodes.items()):
        if not inside(p, box):
            continue
        kind = point_kind(tags)
        if kind is None or nid not in on_ways and kind not in ("passing_place", "turning_circle", "mini_roundabout"):
            continue   # (a crossing on a footway alone, a hump on a car park: not on a road the ride can take)
        heading = point_heading(tags, nid, on_ways, osm.ways) if kind in ("stop", "give_way", "traffic_signals") else -1
        points.append([KINDS.index(kind), int(round(p[0] * SCALE)), int(round(p[1] * SCALE)), heading, point_flags(tags)])
    lines = []
    for kind, pts in osm.barriers:
        for piece in clip_to(pts, box):
            if len(piece) >= 2:
                lines.append([KINDS.index(kind)] + flat_line(piece))
    lines.sort()
    return {"format": FORMAT, "cell": "%d_%d" % (row, col), "release": release, "osm": osm.timestamp,
            "matched": [matched, len(seen)], "edge_cols": EDGE_COLS, "edges": edges, "kinds": KINDS,
            "points": points, "lines": lines}


def report(baked):
    """One line on what a cell's bake holds (how much each rule will have to carry)."""
    e = baked["edges"]
    k = baked["kinds"]
    count = lambda name: sum(1 for p in baked["points"] if k[p[0]] == name)  # noqa: E731
    m, n = baked["matched"]
    return ("%s: %d of %d segments matched (%.0f%%), %d edges tagged: %d with lanes, %d widths, %d roundabout, "
            "%d lit, %d pavements, %d dual halves; points: %d lights, %d crossings, %d mini-roundabouts, %d passing "
            "places, %d humps etc; %d barrier lines" % (
                baked["cell"], m, n, 100.0 * m / max(1, n), len(e), sum(1 for r in e if r[1]),
                sum(1 for r in e if r[4]), sum(1 for r in e if r[5] & EDGE_FLAGS["roundabout"]),
                sum(1 for r in e if r[5] & EDGE_FLAGS["lit"]),
                sum(1 for r in e if r[5] & (EDGE_FLAGS["pave_left"] | EDGE_FLAGS["pave_right"])),
                sum(1 for r in e if r[11]), count("traffic_signals"),
                sum(count(c) for c in ("crossing_zebra", "crossing_signals", "crossing_plain", "crossing_unmarked")),
                count("mini_roundabout"), count("passing_place"),
                sum(count(c) for c in ("hump", "bump", "table", "cushion", "rumble_strip")), len(baked["lines"])))


# ---------------------------------------------------------------------------- Overture

def fetch_segments(box, release, log=print):
    """Overture's road segments touching box, with their ids, lines and sources (needs pyarrow)."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    import route_bake
    s3 = pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset("%s/release/%s/theme=transportation/type=segment" % (route_bake.OVERTURE_BUCKET, release),
                   filesystem=s3, format="parquet")
    south, west, north, east = box
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south) & (pc.field("subtype") == "road"))
    tb = d.to_table(columns=SEGMENT_COLUMNS + ["bbox"], filter=f)
    log("roadx: %d road segments in the box" % tb.num_rows)
    return tb.to_pylist()


def segments_in(rows, box):
    s, w, n, e = box
    return [r for r in rows if r["bbox"]["xmin"] < e and r["bbox"]["xmax"] > w and r["bbox"]["ymin"] < n and r["bbox"]["ymax"] > s]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--pbf", required=True)
    ap.add_argument("--cell", nargs=2, type=int, metavar=("ROW", "COL"))
    ap.add_argument("--square", nargs=2, type=float, metavar=("LAT", "LON"))
    ap.add_argument("--release", default="")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    import route_bake
    release = a.release or route_bake.latest_release()
    if a.cell:
        cells = [tuple(a.cell)]
    elif a.square:
        lat0, lon0 = math.floor(a.square[0]), math.floor(a.square[1])
        r0, c0 = coast_bake.cell_of(lat0 + 1e-9, lon0 + 1e-9)
        n = int(round(1.0 / coast_bake.CELL_DEG))
        cells = [(r0 + i, c0 + j) for i in range(n) for j in range(n)]
    else:
        ap.error("--cell or --square")
    for baked in bake_cells(a.pbf, cells, release):
        if a.cell and not os.path.isdir(a.out):
            path = a.out
        else:
            os.makedirs(a.out, exist_ok=True)
            path = os.path.join(a.out, "c%s.json" % baked["cell"])
        with open(path, "w") as f:
            json.dump(baked, f, separators=(",", ":"))
        print(report(baked) + ", %d KB" % (os.path.getsize(path) // 1024))


def bake_cells(pbf, cells, release, log=print):
    """The roadx of cells [(row, col)] (one square's, say), from the extract at pbf: Overture's segments are fetched
    once over all of them."""
    boxes = [coast_bake.cell_box(r, c) for r, c in cells]
    whole = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    for attempt in range(4):
        try:
            rows = fetch_segments(whole, release, log=log)
            break
        except OSError:
            if attempt == 3:
                raise
    ways = {way_of(r.get("sources")) for r in rows} - {None}
    osm = OsmCut.read(pbf, box=(whole[0] - 0.01, whole[1] - 0.01, whole[2] + 0.01, whole[3] + 0.01), way_ids=ways)
    log("roadx: %d of %d ways found in the extract, %d points, %d barriers" % (len(osm.ways), len(ways), len(osm.nodes),
                                                                               len(osm.barriers)))
    return [bake_cell(r, c, segments_in(rows, box), osm, release) for (r, c), box in zip(cells, boxes)]


if __name__ == "__main__":
    main()
