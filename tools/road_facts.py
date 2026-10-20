"""What is on and beside a baked road: its speed limits, its junctions and the real places to stop.

Used by route_bake.py (stage 3 of docs/real_world_plan.md). All from Overture Maps (ODbL):

    junctions.json  [{k, type, arms: [{side, skew, cls, name, w, surf}], ri, ro}, ...]  where side roads join the road
    pois.json       [{kind, name, x, z, k, lat, conf}, ...]  filling stations, cafes, pubs, inns, campsites, lay-bys
    route.json      each chunk's row gains its speed limit in km/h (chunk_limits)

The data decides where things are and what kind they are; the game decides how they look and what to do about them.
It has no traffic signals and no roundabout flag, so a roundabout is found from the road's shape (a short ring of
road the route goes round) and there are no real traffic lights: the game keeps making its own in villages.
"""
import math
import struct

import numpy as np

# Speed limits (km/h) where the data has none: by road class, in the country the road is in; built-up ground is lower.
LIMITS = {
    "uk": {"motorway": 112, "trunk": 96, "primary": 96, "secondary": 96, "tertiary": 96, "unclassified": 96,
           "residential": 48, "living_street": 32, "track": 48, "built_up": 48},
    "jp": {"motorway": 100, "trunk": 60, "primary": 60, "secondary": 50, "tertiary": 40, "unclassified": 40,
           "residential": 30, "living_street": 20, "track": 30, "built_up": 40},
    "world": {"motorway": 110, "trunk": 90, "primary": 80, "secondary": 80, "tertiary": 70, "unclassified": 60,
              "residential": 40, "living_street": 20, "track": 30, "built_up": 50},
}
# Rough boxes: (south, west, north, east).
REGIONS = {"uk": (49.8, -8.7, 60.9, 1.8), "jp": (24.0, 122.9, 45.6, 146.0)}

# Branch angles (degrees off the road's direction) that are a side road, not a fork or a merge.
SIDE_MIN = 35.0
SIDE_MAX = 145.0
ARM_WIDTH = {"motorway": 7.4, "trunk": 7.4, "primary": 7.4, "secondary": 6.0, "tertiary": 6.0, "unclassified": 4.6,
             "residential": 4.6, "living_street": 4.6, "track": 3.3}
# A ring of road this short, made of edges this short, is a roundabout.
RING_EDGE_M = 90.0
RING_TOTAL_M = 260.0
RING_MAX_EDGES = 8
RING_ROUNDNESS = 0.18   # the spread of a ring's radius over its mean: a circle is 0, a square about 0.1, a long thin loop 0.5
MINI_RING_M = 12.0     # a ring of about this radius or less is a mini roundabout

# Real places the adventure's stops can adopt (Overture basic_category -> the stop's kind). `fuel`: where the
# adventure's fuel stations go; the others are what AdventureStops makes up (cafes and pubs are food).
POI_KINDS = {
    "gas_station": "fuel",
    "cafe": "cafe", "coffee_shop": "cafe", "bakery": "cafe", "restaurant": "cafe", "casual_eatery": "cafe",
    "fast_food_restaurant": "cafe", "bar": "pub", "pub": "pub",
    "hotel": "inn", "inn": "inn", "lodging": "inn", "private_lodging": "inn", "bed_and_breakfast": "inn",
    "campground": "campsite", "rv_park": "campsite",
    "parking": "layby", "public_restroom": "layby", "beach": "viewpoint", "scenic_viewpoint": "viewpoint",
    "observation_deck": "viewpoint",
}
# How far from the road (m) a place may be to be a stop on it.
POI_REACH = {"fuel": 120.0, "cafe": 100.0, "pub": 100.0, "inn": 120.0, "campsite": 150.0, "layby": 60.0, "viewpoint": 150.0}
MIN_CONFIDENCE = 0.5


# ---------------------------------------------------------------------------- speed limits

def region_of(lat, lon):
    for name, (s, w, n, e) in REGIONS.items():
        if s <= lat <= n and w <= lon <= e:
            return name
    return "world"


def segment_limit(rules):
    """The posted limit (km/h) of an Overture segment's speed_limits rules, or None: the first rule that always applies."""
    for rule in rules or []:
        if rule.get("when") or not rule.get("max_speed"):
            continue
        m = rule["max_speed"]
        value = float(m.get("value", 0))
        if value <= 0:
            continue
        return int(round(value * (1.609344 if str(m.get("unit", "km/h")).lower().startswith("mph") else 1.0)))
    return None


def default_limit(cls, region, built_up=False):
    table = LIMITS.get(region, LIMITS["world"])
    limit = table.get(cls, table["unclassified"])
    return min(limit, table["built_up"]) if built_up else limit


def chunk_limits(chunks, edge_limits, built_up, region):
    """Each chunk's limit (km/h): the posted one where the edge under it has one, else the region's default for its
    class, lower where it is built up. `chunks` are chunk_attributes' rows; `edge_limits[i]` is chunk i's posted
    limit or None; `built_up[i]` whether it is built up."""
    out = []
    for i, c in enumerate(chunks):
        posted = edge_limits[i]
        out.append(int(posted) if posted else default_limit(c["cls"], region, bool(built_up[i])))
    return out


def built_up_chunks(n_chunks, buildings, chunk_len=128.0, per_chunk=8):
    """Which chunks are built up: those with at least `per_chunk` buildings whose nearest road knot is in them."""
    count = [0] * n_chunks
    for b in buildings:
        c = int(b[7] * 4.0 // chunk_len)
        if 0 <= c < n_chunks:
            count[c] += 1
    return [c >= per_chunk for c in count]


# ---------------------------------------------------------------------------- junctions

def bearing(dx, dz):
    """Heading in the game's convention (radians, 0 north, + clockwise as seen on the map: +x east, -z north)."""
    return math.atan2(dx, -dz)


def wrap_deg(a):
    return (a + 180.0) % 360.0 - 180.0


def point_along(line, d):
    """The point `d` metres along a polyline (or its end)."""
    run = 0.0
    for a, b in zip(line, line[1:]):
        seg = math.dist(a, b)
        if run + seg >= d and seg > 0:
            t = (d - run) / seg
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        run += seg
    return line[-1]


def edge_line_from(graph, ei, node):
    e = graph.edges[ei]
    return e["pts"] if e["a"] == node else e["pts"][::-1]


def find_ring(graph, start_edge, max_edges=RING_MAX_EDGES):
    """The nodes of a short ring of road through edge `start_edge` ([] when it is on none, or it is not round): a path
    of short edges from one end of it back to the other, no longer than RING_TOTAL_M all told, whose road is about a
    circle (a cluster of short links at a junction is not a roundabout)."""
    e0 = graph.edges[start_edge]
    if e0["length"] > RING_EDGE_M:
        return []
    goal = e0["b"]
    stack = [(e0["a"], [e0["a"]], [start_edge], e0["length"])]
    best = None
    while stack:
        node, nodes, used, total = stack.pop()
        if node == goal and len(used) > 2:
            if best is None or len(used) < len(best[1]):
                best = (nodes, used)
            continue
        if len(used) >= max_edges:
            continue
        for other, ei in graph.adj.get(node, []):
            if ei in used or graph.edges[ei]["length"] > RING_EDGE_M or total + graph.edges[ei]["length"] > RING_TOTAL_M:
                continue
            stack.append((other, nodes + [other], used + [ei], total + graph.edges[ei]["length"]))
    if best is None or not is_round(graph, best[1]):
        return []
    return best[0]


def is_round(graph, edge_ids):
    """Whether the road along these edges lies about a circle: its points' distances from their middle vary by under
    RING_ROUNDNESS of their mean, and the circle is a plausible size."""
    pts = np.array([p for ei in edge_ids for p in graph.edges[ei]["pts"]])
    centre = pts.mean(axis=0)
    r = np.hypot(pts[:, 0] - centre[0], pts[:, 1] - centre[1])
    return 4.0 <= float(r.mean()) <= 45.0 and float(r.std()) <= RING_ROUNDNESS * float(r.mean())


def arm_of(graph, ei, node, route_heading_deg, here):
    """A side road leaving `node` along edge `ei` as an arm, or None when it runs on with the road (a fork, a merge)."""
    line = edge_line_from(graph, ei, node)
    end = point_along(line, 25.0)
    rel = wrap_deg(math.degrees(bearing(end[0] - here[0], end[1] - here[1])) - route_heading_deg)
    if abs(rel) < SIDE_MIN or abs(rel) > SIDE_MAX:
        return None
    e = graph.edges[ei]
    side = 1 if rel > 0 else -1
    return {"side": side, "skew": round(max(-60.0, min(60.0, rel - side * 90.0)), 1), "cls": e["cls"],
            "name": e["label"] or "", "w": ARM_WIDTH[e["cls"]], "surf": e["surface"], "rel": rel}


def junctions_along(graph, steps, knots):
    """The junctions the route passes: [{k (the nearest road knot), type, arms, ri, ro}] in order along the road.

    A node of the route with side roads is a "tee" (side roads on one side) or a "cross" (both); a short ring of road
    the route goes round is a "roundabout" (or a "mini" if it is tiny), its arms those of the ring's other nodes."""
    out = []
    used = set()
    ringed = set()   # every node of a ring found: the junctions there are the roundabout's
    nsteps = len(steps)
    hd = np.degrees(np.arctan2(np.diff(knots[:, 0]), -np.diff(knots[:, 1])))

    def knot_at(p):
        return int(np.argmin(np.hypot(knots[:, 0] - p[0], knots[:, 1] - p[1])))

    i = 1
    while i < nsteps:
        n0, ei, n1 = steps[i]
        if i in used:
            i += 1
            continue
        ring = find_ring(graph, ei)
        if ring:
            ring_set = set(ring)
            ringed |= ring_set
            # the route's steps that stay on the ring
            j = i
            while j < nsteps and steps[j][0] in ring_set and steps[j][2] in ring_set:
                j += 1
            pts = np.array([graph.pos[n] for n in ring_set])
            centre = pts.mean(axis=0)
            radius = float(np.mean(np.hypot(pts[:, 0] - centre[0], pts[:, 1] - centre[1])))
            k = knot_at(centre)
            h = float(hd[min(k, len(hd) - 1)])
            arms = []
            ring_edges = set()
            for n in ring_set:
                for other, ej in graph.adj.get(n, []):
                    if other in ring_set:
                        ring_edges.add(ej)
            path_edges = {s[1] for s in steps[max(0, i - 1):j + 1]}
            for n in ring_set:
                for other, ej in graph.adj.get(n, []):
                    if ej in ring_edges or ej in path_edges:
                        continue
                    arm = arm_of(graph, ej, n, h, graph.pos[n])
                    if arm:
                        arms.append(arm)
            ri = max(4.0, min(9.0, radius - 5.0))
            kind = "mini" if radius <= MINI_RING_M else "roundabout"
            out.append({"k": k, "type": kind, "arms": _one_per_side(arms), "ri": round(ri, 1), "ro": round(ri + 6.8, 1)})
            used.update(range(i, j))
            i = j
            continue
        # An ordinary junction at the node the route enters (n0 of this step): side roads other than the ring's.
        node = n0
        if node not in ringed and len(graph.adj.get(node, [])) > 2:
            prev_edge = steps[i - 1][1]
            k = knot_at(graph.pos[node])
            h = float(hd[min(k, len(hd) - 1)])
            arms = []
            for other, ej in graph.adj[node]:
                if ej in (prev_edge, ei):
                    continue
                arm = arm_of(graph, ej, node, h, graph.pos[node])
                if arm:
                    arms.append(arm)
            arms = _one_per_side(arms)
            if arms:
                out.append({"k": k, "type": "cross" if len(arms) > 1 else "tee", "arms": arms})
        i += 1
    out.sort(key=lambda j: j["k"])
    return out


def _one_per_side(arms):
    """At most one arm a side: the biggest road (then the squarest)."""
    order = ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "track"]
    best = {}
    for a in arms:
        cur = best.get(a["side"])
        if cur is None or (order.index(a["cls"]), abs(a["skew"])) < (order.index(cur["cls"]), abs(cur["skew"])):
            best[a["side"]] = a
    return [{k: v for k, v in a.items() if k != "rel"} for _, a in sorted(best.items())]


def thin_junctions(junctions, min_gap_knots=100):
    """The junctions kept apart (the game keeps its sites clear of each other): the biggest (roundabouts first) wins."""
    rank = {"roundabout": 0, "mini": 1, "cross": 2, "tee": 3}
    kept = []
    for j in sorted(junctions, key=lambda j: (rank[j["type"]], j["k"])):
        if all(abs(j["k"] - o["k"]) >= min_gap_knots for o in kept):
            kept.append(j)
    return sorted(kept, key=lambda j: j["k"])


# ---------------------------------------------------------------------------- places

def parse_point(wkb):
    """(lon, lat) of a WKB point, or None."""
    buf = bytes(wkb)
    order = "<" if buf[0] == 1 else ">"
    if struct.unpack_from(order + "I", buf, 1)[0] % 1000 != 1:
        return None
    return struct.unpack_from(order + "2d", buf, 5)


def english_name(names):
    """A name the game can print: English, else a Latin-script one, else the primary if plain ASCII, else ''."""
    if not names:
        return ""
    common = dict(names.get("common") or {})
    for key in ("en", "ja-Latn", "ja_latn"):
        if common.get(key):
            return str(common[key])
    primary = str(names.get("primary") or "")
    return primary if primary.isascii() else ""


def make_pois(places, frame, knots):
    """Real places to stop at beside the road: [{kind, name, x, z, k, lat, conf}] sorted along the road.

    `lat` is metres to the right of the road (+) or left (-) at the nearest knot."""
    cell = 64.0
    grid = {}
    for k in range(0, len(knots), 2):
        grid.setdefault((int(knots[k][0] // cell), int(knots[k][1] // cell)), []).append(k)
    span = int(max(POI_REACH.values()) // cell) + 1
    out = []
    for row in places:
        kind = POI_KINDS.get(str(row.get("basic_category")))
        if kind is None or float(row.get("confidence") or 0.0) < MIN_CONFIDENCE:
            continue
        ll = parse_point(row["geometry"])
        if ll is None:
            continue
        x, z = frame.to_world(ll[1], ll[0])
        x, z = float(x), float(z)
        best, bk = 1e9, 0
        gx, gz = int(x // cell), int(z // cell)
        for ix in range(gx - span, gx + span + 1):
            for iz in range(gz - span, gz + span + 1):
                for k in grid.get((ix, iz), ()):
                    d = math.hypot(x - knots[k][0], z - knots[k][1])
                    if d < best:
                        best, bk = d, k
        if best > POI_REACH[kind]:
            continue
        k2 = min(bk + 1, len(knots) - 1)
        h = bearing(knots[k2][0] - knots[bk][0], knots[k2][1] - knots[bk][1])
        lat = (x - knots[bk][0]) * math.cos(h) + (z - knots[bk][1]) * math.sin(h)
        out.append({"kind": kind, "name": english_name(row.get("names")), "x": round(x, 1), "z": round(z, 1), "k": bk,
                    "lat": round(lat, 1), "conf": round(float(row.get("confidence") or 0.0), 2)})
    out.sort(key=lambda p: (p["k"], p["kind"], p["x"]))
    return out
