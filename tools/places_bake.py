#!/usr/bin/env python3
"""The places worth riding to (places plan, stage 1: know what is there), from OpenStreetMap: every feature with a
Wikipedia or Wikidata tag, and the notable kinds without one (castles, stone circles, monuments, churches, towers,
lighthouses, windmills, dams, viewpoints and the like), each with what it is, its name, its Wikidata id, where it is,
its outline where it is an area or a line, and its height and material where mapped.

    python3 tools/places_bake.py --pbf CUT.osm.pbf --cell ROW COL --out FILE
    python3 tools/places_bake.py --pbf CUT.osm.pbf --square LAT LON --out DIR      # a 1 degree square's cells
    python3 tools/places_bake.py --count DIR [DIR ...]                             # how many of each kind

The game's info panel asks Wikipedia for nearby articles and each one's Wikidata id; it finds the place here by that
id (else the nearest row of a fitting kind, logged), so a waypoint to "Ribblehead Viaduct" or "Castlerigg stone
circle" knows what it is going to, and the recipes (World/WorldRidePlaces.cpp) build it.

A cell's file, places/cROW_COL.json (FORMAT 1):

    {"format": 1, "cell": "ROW_COL", "release": R, "osm": "extract's timestamp", "kinds": KINDS,
     "places": [[kind, name, wikidata, lat, lon, height, material, sub, outline], ...]}

kind an index into KINDS; name "" where it has none; wikidata "Q123" or ""; lat, lon its middle in 1e-5 degrees;
height (m) 0 where not mapped; material the map's building:material (or material) or ""; sub what the map says more
about its kind (a tower's tower:type, a memorial's memorial, a church's denomination, a castle's castle_type, "ruins"),
or ""; outline [lat, lon, dlat, dlon, ...] in 1e-5 degrees (a closed way's ring without its last point, or a line's
points: a dam's crest), [] for a point. A place is in the cell its middle is in. OpenStreetMap is ODbL. Needs pyosmium.
"""
import argparse
import glob
import json
import math
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import sketch_bake  # noqa: E402

FORMAT = 1
SCALE = sketch_bake.SCALE
# An outline is thinned to points at least this far apart (m), and to MAX_OUTLINE points.
OUTLINE_STEP = 1.0
MAX_OUTLINE = 160

KINDS = ["stone_circle", "standing_stone", "cross", "obelisk", "monument", "memorial", "church", "cathedral",
         "abbey", "castle", "castle_ruin", "ruin", "tower", "lighthouse", "windmill", "watermill", "chimney", "mast",
         "water_tower", "dam", "quarry", "pier", "hillfort", "ancient_site", "historic_house", "battlefield",
         "industrial_heritage", "bridge", "viewpoint", "museum", "attraction", "park", "peak", "waterfall", "cave",
         "natural", "station", "airfield", "settlement", "building", "other"]
# Kinds kept even without a Wikipedia or Wikidata tag: what a rider would stop for, mapped in their thousands.
NOTABLE = {"stone_circle", "standing_stone", "cross", "obelisk", "monument", "church", "cathedral", "abbey", "castle",
           "castle_ruin", "ruin", "tower", "lighthouse", "windmill", "watermill", "dam", "pier", "hillfort",
           "viewpoint", "waterfall"}
PLACES = {"city", "town", "village", "hamlet", "suburb", "quarter", "neighbourhood", "isolated_dwelling", "locality"}
# Things with a Wikidata tag that are no place to ride to: roads, rivers, borders, railway lines, the sea.
NOT_PLACES = ("highway", "boundary", "route", "admin_level", "waterway_river", "railway_line", "power")


def classify(tags):
    """(kind, sub) for a feature's tags, or (None, "")."""
    g = tags.get
    hist = g("historic") or ""
    mm = g("man_made") or ""
    ruins = g("ruins") == "yes" or hist == "ruins"
    if hist == "castle" or g("building") == "castle":
        ct = g("castle_type") or ""
        return ("castle_ruin" if ruins or ct == "ruins" else "castle"), ct
    if hist == "archaeological_site":
        st, mt = g("site_type") or "", g("megalith_type") or ""
        if mt == "stone_circle" or st == "stone_circle":
            return "stone_circle", mt
        if st == "megalith" or mt in ("menhir", "standing_stone", "dolmen", "chambered_cairn", "passage_grave"):
            return "standing_stone", mt
        if st in ("fortification", "hillfort") or g("fortification_type") in ("hill_fort", "hillfort"):
            return "hillfort", st
        return "ancient_site", st
    if hist in ("stone", "standing_stone", "menhir"):
        return "standing_stone", hist
    if hist == "stone_circle":
        return "stone_circle", ""
    if hist == "hillfort" or hist == "fort" and g("fortification_type") == "hill_fort":
        return "hillfort", ""
    if hist in ("wayside_cross", "high_cross", "cross") or mm == "cross" or hist == "memorial" and g("memorial") == "cross":
        return "cross", g("memorial") or hist
    if mm == "obelisk" or hist == "memorial" and g("memorial") == "obelisk":
        return "obelisk", ""
    if hist == "monument":
        return "monument", g("monument") or ""
    if hist == "memorial":
        return "memorial", g("memorial") or ""
    if hist in ("abbey", "monastery", "priory") or g("amenity") == "monastery":
        return "abbey", "ruins" if ruins else ""
    if mm == "lighthouse":
        return "lighthouse", ""
    if mm == "windmill":
        return "windmill", g("windmill:type") or ""
    if mm == "watermill":
        return "watermill", ""
    if mm in ("tower",) or hist in ("folly", "tower"):
        tt = g("tower:type") or hist
        if tt in ("communication", "transmitter"):
            return "mast", tt
        return "tower", tt
    if mm == "chimney":
        return "chimney", ""
    if mm in ("mast", "communications_tower"):
        return "mast", ""
    if mm == "water_tower":
        return "water_tower", ""
    if g("waterway") == "dam" or mm == "dam":
        return "dam", ""
    if mm == "pier":
        return "pier", ""
    if g("landuse") == "quarry":
        return "quarry", ""
    if ruins and hist:
        return "ruin", hist
    b = g("building") or ""
    if b == "cathedral":
        return "cathedral", g("denomination") or ""
    if g("amenity") == "place_of_worship" or b in ("church", "chapel"):
        return "church", g("denomination") or g("religion") or ""
    if hist in ("manor", "house", "building", "country_house", "palace") or b in ("manor", "palace"):
        return "historic_house", hist
    if hist == "battlefield":
        return "battlefield", ""
    if hist in ("mine", "mine_shaft", "industrial", "kiln", "lime_kiln", "mill", "railway"):
        return "industrial_heritage", hist
    if hist == "bridge" or (g("bridge") and g("wikidata")):
        return "bridge", ""
    if g("waterway") == "waterfall" or g("natural") == "waterfall":
        return "waterfall", ""
    t = g("tourism") or ""
    if t == "viewpoint":
        return "viewpoint", ""
    if t == "museum":
        return "museum", ""
    if t in ("attraction", "theme_park", "zoo"):
        return "attraction", t
    if g("leisure") in ("park", "garden", "nature_reserve"):
        return "park", g("leisure")
    if g("natural") in ("peak", "hill", "volcano"):
        return "peak", ""
    if g("natural") == "cave_entrance":
        return "cave", ""
    if g("natural"):
        return "natural", g("natural")
    if g("railway") in ("station", "halt"):
        return "station", ""
    if g("aeroway") == "aerodrome":
        return "airfield", ""
    if g("place") in PLACES:
        return "settlement", g("place")
    if hist:
        return "ruin" if ruins else "monument", hist
    if b:
        return "building", b
    return "other", ""


def wanted(tags):
    """(kind, sub) for a feature worth keeping, else None."""
    wiki = bool(tags.get("wikidata") or tags.get("wikipedia"))
    if tags.get("highway") or tags.get("boundary") or tags.get("route") or tags.get("power") \
            or tags.get("waterway") in ("river", "stream", "canal") or tags.get("railway") in ("rail", "abandoned", "disused") \
            or tags.get("natural") in ("water", "coastline", "bay", "strait") or tags.get("place") in ("county", "region", "state", "island", "sea"):
        return None
    if not wiki and not any(tags.get(k) for k in ("historic", "man_made", "amenity", "tourism", "waterway", "building",
                                                 "natural", "landuse")):
        return None
    kind, sub = classify(tags)
    if kind is None or (not wiki and kind not in NOTABLE):
        return None
    # (a place of worship without a name or a wiki tag is mostly a meeting room: the named ones are the churches)
    if not wiki and kind == "church" and not tags.get("name"):
        return None
    return kind, sub


def number(v):
    if not v:
        return 0.0
    s = str(v).strip().lower().replace(",", ".")
    num = ""
    for ch in s:
        if ch.isdigit() or ch == "." and "." not in num:
            num += ch
        elif num:
            break
    try:
        h = float(num)
    except ValueError:
        return 0.0
    if "ft" in s or "'" in s:
        h *= 0.3048
    return round(h, 1) if 0 < h < 1000 else 0.0


def thin(pts):
    """A polyline or ring kept to points OUTLINE_STEP apart, at most MAX_OUTLINE."""
    if not pts:
        return []
    mx = 111320.0 * math.cos(math.radians(pts[0][0]))
    out = [pts[0]]
    for p in pts[1:]:
        if math.hypot((p[1] - out[-1][1]) * mx, (p[0] - out[-1][0]) * 110540.0) >= OUTLINE_STEP:
            out.append(p)
    if len(out) > MAX_OUTLINE:
        step = len(out) / MAX_OUTLINE
        out = [out[int(i * step)] for i in range(MAX_OUTLINE)]
    return out


def flat(pts):
    out = []
    plat = plon = 0
    for i, (lat, lon) in enumerate(pts):
        a, b = int(round(lat * SCALE)), int(round(lon * SCALE))
        out += [a, b] if i == 0 else [a - plat, b - plon]
        plat, plon = a, b
    return out


def middle(pts):
    if len(pts) == 1:
        return pts[0]
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def row_of(tags, pts, closed):
    """A place's row (KINDS index first), or None."""
    w = wanted(tags)
    if w is None or not pts:
        return None
    kind, sub = w
    ring = pts[:-1] if closed and len(pts) > 2 and pts[0] == pts[-1] else pts
    at = middle(ring)
    outline = thin(ring) if len(ring) >= 2 else []
    height = number(tags.get("height")) or number(tags.get("building:height")) or number(tags.get("est_height"))
    material = tags.get("building:material") or tags.get("material") or ""
    name = tags.get("name:en") or tags.get("name") or ""
    qid = tags.get("wikidata") or ""
    if not qid.startswith("Q"):
        qid = ""
    return [KINDS.index(kind), name, qid, int(round(at[0] * SCALE)), int(round(at[1] * SCALE)), height, material,
            ("ruins" if tags.get("ruins") == "yes" and not sub else sub), flat(outline)]


class PlaceCut:
    """The places in an extract (or a cut of one): rows with their middles."""

    def __init__(self):
        self.rows = []
        self.timestamp = ""

    @classmethod
    def read(cls, path, box=None):
        import osmium
        out = cls()
        try:
            hdr = osmium.io.Reader(path, osmium.osm.osm_entity_bits.NOTHING).header()
            out.timestamp = hdr.get("osmosis_replication_timestamp") or hdr.get("timestamp") or ""
        except Exception:   # noqa: BLE001
            out.timestamp = ""
        seen_ways = set()
        fp = osmium.FileProcessor(path).with_locations().with_areas().with_filter(osmium.filter.EmptyTagFilter())
        for o in fp:
            if o.is_node():
                tags = {t.k: t.v for t in o.tags}
                if wanted(tags) is None or not o.location.valid():
                    continue
                r = row_of(tags, [(o.location.lat, o.location.lon)], False)
            elif o.is_way():
                tags = {t.k: t.v for t in o.tags}
                if wanted(tags) is None:
                    continue
                pts = [(n.lat, n.lon) for n in o.nodes if n.location.valid()]
                closed = len(o.nodes) > 2 and o.nodes[0].ref == o.nodes[-1].ref
                seen_ways.add(o.id)
                r = row_of(tags, pts, closed)
            elif o.is_area():
                # (a multipolygon relation's outer ring; a closed way's area is the way, already kept)
                if o.from_way() and o.orig_id() in seen_ways:
                    continue
                tags = {t.k: t.v for t in o.tags}
                if wanted(tags) is None:
                    continue
                pts = []
                for ring in o.outer_rings():
                    pts = [(n.lat, n.lon) for n in ring if n.location.valid()]
                    break
                r = row_of(tags, pts, True)
            else:
                continue
            if r is None:
                continue
            lat, lon = r[3] / SCALE, r[4] / SCALE
            if box is None or (box[0] <= lat < box[2] and box[1] <= lon < box[3]):
                out.rows.append(r)
        return out


def bake_cell(row, col, cut, release=""):
    s, w, n, e = coast_bake.cell_box(row, col)
    rows = [r for r in cut.rows if s <= r[3] / SCALE < n and w <= r[4] / SCALE < e]
    # (one row per Wikidata id: a castle mapped as a point and as its outline is one castle, its outline kept)
    best = {}
    out = []
    for r in rows:
        if not r[2]:
            out.append(r)
            continue
        have = best.get(r[2])
        if have is None or len(r[8]) > len(have[8]):
            best[r[2]] = r
    out += best.values()
    out.sort(key=lambda r: (r[0], r[3], r[4], r[1]))
    return {"format": FORMAT, "cell": "%d_%d" % (row, col), "release": release, "osm": cut.timestamp, "kinds": KINDS,
            "places": out}


def bake_cells(pbf, cells, release, log=print):
    boxes = [coast_bake.cell_box(r, c) for r, c in cells]
    whole = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    cut = PlaceCut.read(pbf, box=whole)
    log("places: %d in the cut" % len(cut.rows))
    return [bake_cell(r, c, cut, release) for r, c in cells]


def count(paths):
    """{kind: (all, with a Wikidata id)} over the places files at paths."""
    all_, wiki = Counter(), Counter()
    for p in paths:
        with open(p) as f:
            d = json.load(f)
        for r in d["places"]:
            k = d["kinds"][r[0]]
            all_[k] += 1
            wiki[k] += 1 if r[2] else 0
    return {k: (all_[k], wiki[k]) for k in all_}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--pbf")
    ap.add_argument("--cell", nargs=2, type=int, metavar=("ROW", "COL"))
    ap.add_argument("--square", nargs=2, type=float, metavar=("LAT", "LON"))
    ap.add_argument("--release", default="")
    ap.add_argument("--out")
    ap.add_argument("--count", nargs="+")
    a = ap.parse_args()
    if a.count:
        paths = [p for d in a.count for p in sorted(glob.glob(os.path.join(d, "*.json")))]
        for k, (n, q) in sorted(count(paths).items(), key=lambda kv: -kv[1][1]):
            print("%-20s %7d  (%d with Wikidata)" % (k, n, q))
        return
    if a.cell:
        cells = [tuple(a.cell)]
    elif a.square:
        r0, c0 = coast_bake.cell_of(math.floor(a.square[0]) + 1e-9, math.floor(a.square[1]) + 1e-9)
        n = int(round(1.0 / coast_bake.CELL_DEG))
        cells = [(r0 + i, c0 + j) for i in range(n) for j in range(n)]
    else:
        ap.error("--cell, --square or --count")
    for baked in bake_cells(a.pbf, cells, a.release):
        path = a.out if a.cell and not os.path.isdir(a.out) else os.path.join(a.out, "c%s.json" % baked["cell"])
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w") as f:
            json.dump(baked, f, separators=(",", ":"), ensure_ascii=False)
        print("%s: %d places, %d KB" % (baked["cell"], len(baked["places"]), os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
