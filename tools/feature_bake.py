#!/usr/bin/env python3
"""The things worth stopping for in a cell (Ride Anywhere v2, phase D): wind turbines and pylons, towers and lifts,
railways and their viaducts, dams, falls and harbours, peaks, cliffs and glaciers, vineyards and quarries, walls and
gates, borders and runways, as points, lines and areas, from the Overture Maps themes the other bakers don't read. The
game places a model for each from its kit library (data/scenery_kits.json, scripts/scenery_streamer.gd): the data
decides where and what, the game how it looks.

    python3 tools/feature_bake.py LAT LON [--release R] [--out FILE]     # the cell at LAT, LON
    python3 tools/feature_bake.py --square LAT LON --out DIR [...]       # every cell of a 1 degree square, fetched once
    python3 tools/feature_bake.py --box S W N E --out FILE [...]         # a bundled region's: one file over its cells

A cell's features (FORMAT 1):

    {"format": 1, "cell": "ROW_COL", "release": R, "classes": CLASSES_HASH,
     "kinds": [kind, ...], "names": ["", name, ...],
     "points": [[kind, lat, lon, height, elevation, heading, name, id], ...],
     "lines":  [[kind, height, width, flags, name, id, lat, lon, dlat, dlon, ...], ...],
     "areas":  [[kind, height, elevation, name, id, lat, lon, dlat, dlon, ...], ...],
     "words": ["", word, ...], "buildings": [[dlat, dlon, class, roof_shape, roof_color, roof_material,
                                              facade_material, facade_color], ...]}

"words" and "buildings" are there only where a building's look is mapped (a game that doesn't read them reads the rest
as before): each building the map says something about (LOOKS, BUILDING_CLASSES), at its outline's middle, each of
lat and lon the step from the building before (the first from 0), the rest indexes into "words" (0: the map says
nothing). The game matches them to the cell's buildings.json by where they stand (scripts/building_looks.gd), so a
town's roofs are its own without a cell being baked again.

"towers" (and "words" with it) is there only where a cell has a building TOWER_M tall or more, or BIG_M2 big:

     "towers": [[height, min_height, name, id, group, class, roof_shape, roof_color, roof_material, facade_material,
                 facade_color, lat, lon, dlat, dlon, ...], ...]

each its whole outline (not cut at the cell's edge: it's in the cell its middle is in), its height (m, null where the
map gives none: a big one), where it starts above the ground (m, 0 for most: a part over another), its name, its id and
its building's (group: the same for a tall building's parts, which stand in for it), and the words as the looks' are.

kind is an index into "kinds" (the names CLASSES gives, the same every cell bakes them), name an index into "names" (0
none). lat and lon are in 1e-5 degrees, each point of a line or an area after its first the step from the one before
(as the streams have them, stream_bake.py). height (m: a tower's, a turbine's hub, a dam's), elevation (m above sea
level: a peak's, a pass's) and width (m) are what the map says, null where it says nothing; heading is degrees from
north, clockwise, where the map gives a direction, else null (the game turns it to the road). flags is a line's
FLAGS bits (a railway's bridges and tunnels are lines of their own). id is the first 12 hex digits of the SHA-1 of its
Overture id, null for the small things kept only near a road (there are many, and nothing asks which one is which). An area is its outer ring, without its holes or its last point (the first again).

Every line and area is cut to the cell's box, so a power line or a wall over several cells is in each in pieces that
meet at the edges, never twice; a point is in the cell it stands in. The kinds marked near in CLASSES (the small
things: poles, gates, walls, benches) are kept only within about NEAR_M of a road a ride can take, the rest
(turbines, pylons, peaks, dams) wherever they are in the cell: they are seen from miles off.

classes is the hash of CLASSES and FORMAT: the world's store bakes a cell's features again only when it or the
Overture release changes (torque-shed-world's scripts/feature_backfill.py), so adding a kind costs one incremental
pass. A cell's go into a file of their own in the world's store (feature/cROW_COL.json, its hash in the index's
"features"), fetched for a journey on it as its streams and trees are; a bundled region has a features.json of its
cells beside its roads.json.

Overture Maps is ODbL (OpenStreetMap's data by way of it, and others'). Needs numpy and pyarrow. No API keys.
"""
import argparse
import hashlib
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake  # noqa: E402
import sketch_bake  # noqa: E402

FORMAT = 1
SCALE = sketch_bake.SCALE
# How far (m) a simplified line or ring may stray from Overture's.
TOLERANCE = 1.5
# The small things (CLASSES' near ones) are kept within about this far (m) of a road a ride can take: seen from it.
NEAR_M = 80.0
NEAR_GRID_M = 40.0
# A line's flags.
BRIDGE, TUNNEL, DISUSED, BUILDING = 1, 2, 4, 8
RAIL_FLAGS = {"is_bridge": BRIDGE, "is_tunnel": TUNNEL, "is_abandoned": DISUSED, "is_disused": DISUSED,
              "is_under_construction": BUILDING}

# What is kept, by where it comes from: (theme, type, the column that names its class) -> {class: (kind, near)}. kind
# is the game's name for it (data/scenery_kits.json's), near whether it is kept only near a road. The classes are the
# phase D plan's rounds' (D1 skyline, D2 rail, D3 water, D4 wild, D5 fields, D6 history, D7 ferries, D8 journey marks,
# D9 furniture): a round adds models and kit rows, and only a row here when the map has something new.
CLASSES = {
    ("base", "infrastructure", "class"): {
        # D1 skyline: power, towers, utilities and lifts.
        "generator": ("generator", False), "power_line": ("power_line", False), "minor_line": ("minor_line", True),
        "cable": ("power_cable", False), "power_tower": ("power_tower", False), "power_pole": ("power_pole", True),
        "portal": ("power_portal", False), "substation": ("substation", False), "plant": ("power_plant", False),
        "cooling": ("cooling_tower", False), "communication_tower": ("communication_tower", False),
        "mobile_phone_tower": ("mobile_phone_tower", False), "communication_line": ("communication_line", True),
        "bell_tower": ("bell_tower", False), "minaret": ("minaret", False), "observation": ("observation_tower", False),
        "lighting": ("lighting_tower", True), "radar": ("radar_tower", False), "watchtower": ("watchtower", False),
        "defensive": ("defensive_tower", False), "silo": ("silo", False), "storage_tank": ("storage_tank", True),
        "water_tower": ("water_tower", False), "gasometer": ("gasometer", False),
        "aerialway_station": ("aerialway_station", False), "cable_car": ("cable_car", False),
        "gondola": ("gondola", False), "chair_lift": ("chair_lift", False), "mixed_lift": ("mixed_lift", False),
        "drag_lift": ("drag_lift", False), "t-bar": ("drag_lift", False), "j-bar": ("drag_lift", False),
        "platter": ("drag_lift", False), "rope_tow": ("drag_lift", False), "goods": ("goods_lift", False),
        "zip_line": ("zip_line", False), "pylon": ("aerialway_pylon", False),
        # D2 rail.
        "viaduct": ("viaduct", False), "railway_station": ("railway_station", False),
        "railway_halt": ("railway_halt", False), "level_crossing": ("level_crossing", False),
        "railway_crossing": ("level_crossing", False), "catenary_mast": ("catenary_mast", True),
        # D3 water and coast.
        "dam": ("dam", False), "weir": ("weir", False), "lock_gate": ("lock_gate", False),
        "breakwater": ("breakwater", False), "groyne": ("groyne", False), "pier": ("pier", False),
        "quay": ("quay", False), "aqueduct": ("aqueduct", False), "fish_pass": ("fish_pass", False),
        "boardwalk": ("boardwalk", False),
        # D5 land texture: the lines fields are walled, fenced and hedged by.
        "fence": ("fence", True), "wall": ("wall", True), "hedge": ("hedge", True),
        "retaining_wall": ("retaining_wall", True),
        # D6 history.
        "city_wall": ("city_wall", False), "sally_port": ("sally_port", False), "artwork": ("artwork", False),
        "viewpoint": ("viewpoint", False), "milestone": ("milestone", True), "fountain": ("fountain", True),
        "information": ("information", True),
        # D7 ferries.
        "ferry_terminal": ("ferry_terminal", False),
        # D8 borders, tolls and airfields.
        "border_control": ("border_control", False), "toll_booth": ("toll_booth", False),
        "runway": ("runway", False), "taxiway": ("taxiway", False), "apron": ("apron", False),
        "helipad": ("helipad", False), "airstrip": ("airstrip", False), "airport": ("airport", False),
        "international_airport": ("airport", False), "regional_airport": ("airport", False),
        "municipal_airport": ("airport", False), "private_airport": ("airfield", False),
        "aerodrome": ("airfield", False), "military_airport": ("airport", False),
        # D9 street furniture.
        "street_lamp": ("street_lamp", True), "bench": ("bench", True), "picnic_table": ("picnic_table", True),
        "post_box": ("post_box", True), "bus_stop": ("bus_stop", True), "charging_station": ("charging_station", True),
        "cattle_grid": ("cattle_grid", True), "gate": ("gate", True), "kissing_gate": ("kissing_gate", True),
        "stile": ("stile", True), "bollard": ("bollard", True), "lift_gate": ("lift_gate", True),
        "swing_gate": ("gate", True),
    },
    ("base", "land", "class"): {
        # D4 mountains and wild ground.
        "peak": ("peak", False), "saddle": ("saddle", False), "ridge": ("ridge", False), "volcano": ("volcano", False),
        "volcanic_caldera_rim": ("caldera_rim", False), "crater": ("crater", False), "glacier": ("glacier", False),
        "cliff": ("cliff", False), "scree": ("scree", False), "cave_entrance": ("cave_entrance", False),
        "dune": ("dune", False), "shingle": ("shingle", False), "reef": ("reef", False),
    },
    ("base", "water", "class"): {
        # D3 water and coast.
        "waterfall": ("waterfall", False), "rapids": ("rapids", False), "reservoir": ("reservoir", False),
        "dock": ("dock", False), "lock": ("canal_lock", False), "hot_spring": ("hot_spring", False),
        "geyser": ("geyser", False), "blowhole": ("blowhole", False), "moat": ("moat", False),
        "canal": ("canal", False),
    },
    ("base", "land_use", "class"): {
        # D1 skyline: pistes.
        "piste": ("piste", False), "downhill": ("piste", False), "nordic": ("nordic_piste", False),
        "winter_sports": ("winter_sports", False),
        # D3: marinas.
        "marina": ("marina", False),
        # D5 land texture.
        "vineyard": ("vineyard", False), "orchard": ("orchard", False), "plant_nursery": ("plant_nursery", False),
        "greenhouse_horticulture": ("greenhouses", False), "allotments": ("allotments", False),
        "salt_pond": ("salt_pond", False), "aquaculture": ("aquaculture", False), "quarry": ("quarry", False),
        "works": ("works", False), "military": ("military", False), "range": ("range", False),
        "danger_area": ("danger_area", False), "cemetery": ("cemetery", False), "grave_yard": ("grave_yard", False),
        "golf_course": ("golf_course", False), "fairway": ("golf_fairway", False), "green": ("golf_green", False),
        "bunker": ("golf_bunker", False), "tee": ("golf_tee", False), "track": ("race_track", False),
        "raceway": ("race_track", False), "theme_park": ("theme_park", False), "zoo": ("zoo", False),
        "roller_coaster": ("roller_coaster", False),
        # D5: farmland near the roads (paddies, where the place is hot and wet: the game decides by its climate).
        "farmland": ("farmland", True),
    },
    ("transportation", "segment", "class"): {
        # D2 rail (a road segment is never kept: the roads are roads.json's).
        "standard_gauge": ("railway", False), "narrow_gauge": ("narrow_gauge", False),
        "light_rail": ("light_rail", False), "subway": ("subway", False), "tram": ("tram", False),
        "funicular": ("funicular", False), "monorail": ("monorail", False), "unknown": ("railway", False),
        # D7 ferries (water segments).
        "ferry": ("ferry", False),
    },
    ("divisions", "division_boundary", "subtype"): {
        # D8: borders between countries and between regions.
        "country": ("country_border", False), "region": ("region_border", False),
    },
    ("places", "place", "taxonomy"): {
        # D6 history: the named places worth a board (their taxonomy's primary category; only those the map is fairly
        # sure of, PLACE_CONFIDENCE). "historic_site" is left out: it names holiday lets as often as ruins.
        "monument": ("monument", False), "sculpture_statue": ("monument", False), "memorial_site": ("monument", False),
        "castle": ("castle", False), "palace": ("castle", False), "fort": ("castle", False),
    },
}
# A place (Overture's places theme) is kept only when the map is at least this sure of it.
PLACE_CONFIDENCE = 0.6
# D6: what the map says a building looks like, beside the cell's own buildings.json (which the game matches them to
# by where they stand: BuildingLooks). A building is kept when it has any of LOOKS or a class in BUILDING_CLASSES (the
# classes the game draws as their own: a church, a hangar, a trullo), as its middle and the words for each.
LOOKS = ("roof_shape", "roof_color", "roof_material", "facade_material", "facade_color")
BUILDING_CLASSES = ("cathedral", "chapel", "church", "mosque", "temple", "synagogue", "shrine", "monastery", "religious",
                    "presbytery", "hangar", "silo", "stadium", "grandstand", "greenhouse", "glasshouse", "bunker",
                    "train_station", "transportation", "trullo", "ger", "stilt_house", "beach_hut", "boathouse",
                    "pavilion", "castle", "fort", "lighthouse", "windmill", "kiosk", "cabin", "hut",
                    "transformer_tower", "storage_tank", "slurry_tank", "grain_silo", "military", "guardhouse")
# Towers (city buildings): a building at least TOWER_M tall (or TOWER_FLOORS floors), or with a footprint of BIG_M2 or
# more, is kept whole as a tower row: its outline, height, where it starts above the ground and its look, so the game
# draws the city's real skyline (the cells' buildings.json keeps a building no taller than 40 m, nor bigger than
# 2,500 m2). A tall building made of parts (Overture's building_part: a podium, its setbacks, a spire) is kept as its
# parts instead. A big one under TOWER_M (a station, a shopping centre) only near a road a ride can take.
TOWER_M = 40.0
TOWER_FLOORS = 12
BIG_M2 = 2500.0
STOREY_M = 3.2
TOWER_KIND = "tower"   # (the game makes a tower row an area of this kind, or "skyscraper" from 100 m: scripts/scenery/towers.gd)
TOWER_PART_AREA = 12.0   # (a part smaller than this, m2, is a detail: a spire's finial, a lift motor room)
# D8: a border line is named for the divisions either side of it, "LEFT|RIGHT" (facing along the line: Overture's
# division_ids order), each a country's ISO code (a region's ISO 3166-2 code for a region's border; "" where the map
# doesn't say), so the game switches kit and driving side at the line itself rather than by cell.
BORDER_SIDES = 1
# Kinds Overture carries only in a row's OpenStreetMap tags: {source key: {class: [(tag, value, kind), ...]}}, the
# first that matches (a class here and not in CLASSES is fetched only for these). Its name is the tag NAME_TAGS says
# where the row's own is the waterway's.
TAGGED = {
    ("base", "water", "class"): {
        # D3: a canal's locks are its lines tagged lock=yes, and the water in them polygons tagged water=lock.
        "canal": [("lock", "yes", "canal_lock")], "water": [("water", "lock", "canal_lock")],
    },
    ("base", "land_use", "class"): {
        # D5: rice fields, wherever they are (the farmland the map says grows rice).
        "farmland": [("crop", "rice", "paddy"), ("produce", "rice", "paddy")],
    },
}
NAME_TAGS = {"canal_lock": ("lock_name", "lock:name:flight")}
# Overture's subtype for the segments kept (rail and water: never a road), and for a water segment its kind whatever
# its class.
SEGMENT_SUBTYPES = ("rail", "water")
# The kinds a generator becomes, by what drives it (kind_of).
GENERATORS = {"wind": "wind_turbine", "solar": "solar", "photovoltaic": "solar"}
# The kinds in the order every file names them.
KINDS = sorted({k for table in CLASSES.values() for k, _ in table.values()} | set(GENERATORS.values())
               | {t[2] for table in TAGGED.values() for rules in table.values() for t in rules} | {TOWER_KIND, "skyscraper"})


def classes_hash():
    """The hash of what is kept: a cell baked with another is baked again."""
    rows = {"%s/%s/%s" % key: {c: list(v) for c, v in sorted(table.items())} for key, table in sorted(CLASSES.items())}
    tagged = {"%s/%s/%s" % key: {c: [list(t) for t in v] for c, v in sorted(table.items())}
              for key, table in sorted(TAGGED.items())}
    text = json.dumps({"format": FORMAT, "classes": rows, "tagged": tagged, "name_tags": NAME_TAGS, "subtypes": SEGMENT_SUBTYPES, "generators": GENERATORS,
                       "tolerance": TOLERANCE, "near": NEAR_M, "place_confidence": PLACE_CONFIDENCE,
                       "looks": LOOKS, "building_classes": BUILDING_CLASSES, "border_sides": BORDER_SIDES,
                       "towers": [TOWER_M, TOWER_FLOORS, BIG_M2, STOREY_M, TOWER_PART_AREA]},
                      sort_keys=True)
    return hashlib.sha1(text.encode()).hexdigest()[:12]


def short_id(overture_id):
    return hashlib.sha1(str(overture_id).encode()).hexdigest()[:12]


# ---------------------------------------------------------------------------- geometry

def parse_any(wkb):
    """A WKB geometry as (points [(lon, lat)], lines [[(lon, lat)]], rings [[(lon, lat)]]: the outer ring of each
    polygon)."""
    pts, lines, rings = [], [], []

    def read(buf, off):
        order = "<" if buf[off] == 1 else ">"
        kind = struct.unpack_from(order + "I", buf, off + 1)[0] % 1000
        off += 5
        if kind == 1:
            pts.append(struct.unpack_from(order + "2d", buf, off))
            return off + 16
        if kind == 2:
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            p = struct.unpack_from(order + "%dd" % (2 * n), buf, off)
            lines.append(list(zip(p[0::2], p[1::2])))
            return off + 16 * n
        if kind == 3:
            nr = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            for r in range(nr):
                n = struct.unpack_from(order + "I", buf, off)[0]
                off += 4
                p = struct.unpack_from(order + "%dd" % (2 * n), buf, off)
                off += 16 * n
                if r == 0:
                    rings.append(list(zip(p[0::2], p[1::2])))
            return off
        if kind in (4, 5, 6, 7):
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            for _ in range(n):
                off = read(buf, off)
            return off
        raise ValueError("unsupported geometry type %d" % kind)

    read(bytes(wkb), 0)
    return pts, lines, rings


def inside(lon, lat, box):
    s, w, n, e = box
    return s <= lat < n and w <= lon < e


def clip_line(line, box):
    """The runs of line [(lon, lat)] inside box (south, west, north, east), each cut where it crosses the box's edge
    (Liang-Barsky on each step): [[(lon, lat)], ...]."""
    s, w, n, e = box
    runs = []
    run = []
    for a, b in zip(line, line[1:]):
        got = _clip_step(a, b, w, s, e, n)
        if got is None:
            if len(run) >= 2:
                runs.append(run)
            run = []
            continue
        p, q = got
        if run and run[-1] != p:
            if len(run) >= 2:
                runs.append(run)
            run = []
        if not run:
            run.append(p)
        run.append(q)
        if q != b:   # (it leaves the box here)
            if len(run) >= 2:
                runs.append(run)
            run = []
    if len(run) >= 2:
        runs.append(run)
    return runs


def _clip_step(a, b, x0, y0, x1, y1):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
        if p == 0.0:
            if q < 0.0:
                return None
            continue
        t = q / p
        if p < 0.0:
            if t > t1:
                return None
            t0 = max(t0, t)
        else:
            if t < t0:
                return None
            t1 = min(t1, t)
    if t0 > t1 or (t0 == t1 and (dx or dy)):
        return None
    pa = a if t0 == 0.0 else (a[0] + t0 * dx, a[1] + t0 * dy)
    pb = b if t1 == 1.0 else (a[0] + t1 * dx, a[1] + t1 * dy)
    return pa, pb


def split_by(line, ranges):
    """Line [(lon, lat)] cut at the fractions of its length `ranges` ([(t0, t1, flags)]) start and end at: [(flags,
    run)], each run's flags those of the ranges over its middle."""
    if not ranges:
        return [(0, line)]
    cum = [0.0]
    for a, b in zip(line, line[1:]):
        cum.append(cum[-1] + math.hypot(b[0] - a[0], (b[1] - a[1])))
    total = cum[-1]
    if total <= 0.0:
        return [(0, line)]
    cuts = sorted({0.0, 1.0} | {min(1.0, max(0.0, t)) for r in ranges for t in r[:2]})
    out = []
    for t0, t1 in zip(cuts, cuts[1:]):
        if t1 - t0 < 1e-9:
            continue
        mid = (t0 + t1) / 2.0
        flags = 0
        for r0, r1, f in ranges:
            if r0 <= mid <= r1:
                flags |= f
        run = [_at(line, cum, t0 * total)]
        run += [p for p, c in zip(line, cum) if t0 * total < c < t1 * total]
        run.append(_at(line, cum, t1 * total))
        if out and out[-1][0] == flags:
            out[-1] = (flags, out[-1][1] + run[1:])
        else:
            out.append((flags, run))
    return out


def _at(line, cum, d):
    for k in range(1, len(line)):
        if cum[k] >= d:
            span = cum[k] - cum[k - 1]
            t = 0.0 if span <= 0.0 else (d - cum[k - 1]) / span
            a, b = line[k - 1], line[k]
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    return line[-1]


def rail_ranges(rail_flags):
    """Overture rail_flags as [(t0, t1, FLAGS bits)]."""
    out = []
    for rule in rail_flags or []:
        bits = 0
        for v in rule.get("values") or []:
            bits |= RAIL_FLAGS.get(v, 0)
        if bits:
            between = rule.get("between") or [0.0, 1.0]
            out.append((float(between[0]), float(between[1]), bits))
    return out


def simple(pts, lat0, closed=False):
    """pts [(lon, lat)] simplified to within TOLERANCE metres (a ring as two halves, so its ends stay put)."""
    m_lat, m_lon = sketch_bake.metres_per_degree(lat0)
    xy = [(lon * m_lon, lat * m_lat) for lon, lat in pts]
    if closed and len(xy) > 4:
        half = len(xy) // 2
        kept = sketch_bake.simplify(xy[:half + 1], TOLERANCE)[:-1] + sketch_bake.simplify(xy[half:] + xy[:1], TOLERANCE)[:-1]
    else:
        kept = sketch_bake.simplify(xy, TOLERANCE)
    return [(x / m_lon, y / m_lat) for x, y in kept]


def flat(pts):
    """[(lon, lat)] as [lat, lon, dlat, dlon, ...] in 1e-5 degrees, repeats dropped."""
    out = []
    last = None
    for lon, lat in pts:
        q = (round(lat * SCALE), round(lon * SCALE))
        if last is None:
            out += [q[0], q[1]]
        elif q != last:
            out += [q[0] - last[0], q[1] - last[1]]
        else:
            continue
        last = q
    return out


# ---------------------------------------------------------------------------- what the map says

def number(v):
    """A mapped number (a height "12", "12 m", "12.5") as a float to 0.1, or None."""
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return round(float(v), 1) if math.isfinite(float(v)) else None
    text = str(v).strip().lower().replace(",", ".")
    for unit in ("m", "metres", "meters"):
        if text.endswith(unit):
            text = text[:-len(unit)].strip()
    try:
        f = float(text)
    except ValueError:
        return None
    return round(f, 1) if math.isfinite(f) else None


def heading(tags):
    """A mapped direction (degrees, or a compass point) as degrees from north, or None."""
    v = tags.get("direction")
    if v is None:
        return None
    points = {"N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5, "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5, "S": 180,
              "SSW": 202.5, "SW": 225, "WSW": 247.5, "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5}
    if str(v).upper() in points:
        return float(points[str(v).upper()])
    f = number(v)
    return None if f is None else round(f % 360.0, 1)


def kind_of(key, row):
    """The game's kind for Overture row `row` of source `key` (None to leave it out), and whether it's kept only near
    a road."""
    table = CLASSES[key]
    if key[1] == "segment":
        if row.get("subtype") not in SEGMENT_SUBTYPES:
            return None, False
        if row.get("subtype") == "water":
            return table["ferry"]
    cls = place_class(row) if key[0] == "places" else str(row.get(key[2]))
    if key[0] == "places" and float(row.get("confidence") or 0.0) < PLACE_CONFIDENCE:
        return None, False
    if cls in TAGGED.get(key, {}):
        tags = dict(row.get("source_tags") or [])
        for tag, value, kind in TAGGED[key][cls]:
            if tags.get(tag) == value:
                return kind, False
    got = table.get(cls)
    if got is None:
        return None, False
    kind, near = got
    if kind == "generator":
        tags = dict(row.get("source_tags") or [])
        source = str(tags.get("generator:source", "")) + "|" + str(tags.get("generator:method", ""))
        for word, becomes in GENERATORS.items():
            if word in source:
                kind = becomes
                break
    return kind, near


def place_class(row):
    """A place's class: its taxonomy's primary category ("" for none)."""
    tax = row.get("taxonomy") or {}
    return str(tax.get("primary") or "") if isinstance(tax, dict) else ""


def english_or_primary(names):
    """A feature's name: English where there's one, else its own (any script: the game's signs can print it)."""
    if not names:
        return ""
    common = dict(names.get("common") or {})
    if common.get("en"):
        return str(common["en"])
    return str(names.get("primary") or "")


# ---------------------------------------------------------------------------- fetching

COLUMNS = ["id", "geometry", "subtype", "class", "names", "source_tags", "height", "elevation", "rail_flags",
           "taxonomy", "confidence", "division_ids"]
# The OpenStreetMap tags anything here reads (kind_of, heading, cell_features): a row keeps only these, so a city's
# hundreds of thousands of poles and benches don't each carry every tag they were mapped with.
TAGS_READ = ({"direction", "height", "ele", "width", "generator:source", "generator:method"}
             | {t for tags in NAME_TAGS.values() for t in tags}
             | {t[0] for table in TAGGED.values() for rules in table.values() for t in rules})


def slim(row):
    """Row `row` with only what is read of it: the OpenStreetMap tags in TAGS_READ, its name (english_or_primary's) as
    its only one, and nothing the map left empty."""
    tags = row.get("source_tags")
    if tags:
        row["source_tags"] = [(k, v) for k, v in tags if k in TAGS_READ]
    if row.get("names"):
        name = english_or_primary(row["names"])
        row["names"] = {"primary": name} if name else None
    return {k: v for k, v in row.items() if v is not None and v != []}


def near_filter(grid):
    """A keep(key, row) for fetch: leaves out a row this baker would leave out of every cell anyway (no kind of ours,
    or a near-only one nowhere near a road in `grid`), as it's read."""
    def keep(key, row):
        kind, only_near = kind_of(key, row)
        if kind is None:
            return False
        if not only_near:
            return True
        if grid is None:
            return False
        try:
            pts, lns, rings = parse_any(row["geometry"])
        except (ValueError, struct.error):
            return False
        every = list(pts) + [p for ln in lns for p in ln] + [p for ring in rings for p in ring]
        return any(grid.near(lon, lat) for lon, lat in every)
    return keep


def fetch(box, release, bucket=None, filesystem=None, log=print, keep=None):
    """Every row of the kept classes touching box (south, west, north, east): [(source key, row)], read a batch at a
    time, each row slimmed to the tags read (slim) and, with `keep` (near_filter), only those it keeps."""
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
             & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))
        if kind == "segment":
            f = f & pc.field("subtype").isin(list(SEGMENT_SUBTYPES))
        elif theme == "places":
            f = f & pc.field("taxonomy", "primary").isin(sorted(CLASSES[key])) & (pc.field("confidence") >= PLACE_CONFIDENCE)
        else:
            f = f & pc.field(column).isin(sorted(set(CLASSES[key]) | set(TAGGED.get(key, {}))))
        cols = [c for c in COLUMNS if c in d.schema.names]
        n = kept = 0
        for batch in d.to_batches(columns=cols, filter=f, batch_size=BATCH):
            for r in batch.to_pylist():
                n += 1
                if r.get("geometry") and (keep is None or keep(key, r)):
                    out.append((key, slim(r)))
                    kept += 1
        log("features: %s/%s %d rows, %d kept" % (theme, kind, n, kept))
    borders = [r for key, r in out if key[0] == "divisions"]
    if borders:
        codes = fetch_division_codes(box, release, bucket, s3, log)
        for r in borders:
            r["sides"] = border_sides(r, codes)
    out += fetch_buildings(box, release, bucket, s3, log)
    return out


def fetch_division_codes(box, release, bucket=None, filesystem=None, log=print):
    """The countries' and regions' codes by their division id, for the divisions whose areas touch box: {id: code}."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import route_bake as rb
    south, west, north, east = box
    d = ds.dataset("%s/release/%s/theme=divisions/type=division_area" % (bucket or rb.OVERTURE_BUCKET, release),
                   filesystem=filesystem, format="parquet")
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south)
         & pc.field("subtype").isin(["country", "region"]))
    rows = d.to_table(columns=["division_id", "subtype", "country", "region"], filter=f).to_pylist()
    log("features: divisions/division_area %d rows" % len(rows))
    return {r["division_id"]: str((r["country"] if r["subtype"] == "country" else r["region"]) or "") for r in rows}


def border_sides(r, codes):
    """A border row's name: the codes of the divisions to its left and right, "LEFT|RIGHT" ("" if not known)."""
    ids = list(r.get("division_ids") or [])
    if len(ids) != 2:
        return ""
    return "%s|%s" % (codes.get(ids[0], ""), codes.get(ids[1], ""))


BUILDINGS = ("buildings", "building", "class")
# What fetch_buildings hands on, worked out as each batch of rows is read so a city's millions of outlines are never
# held at once: a building's look (building_look, its middle and words) and a tower (towers_from).
LOOK = ("buildings", "building", "look")
TOWER = ("buildings", "building", "tower")
BATCH = 20000


def fetch_buildings(box, release, bucket=None, filesystem=None, log=print):
    """The buildings touching box that the map says something about (LOOKS, BUILDING_CLASSES) as their looks, and its
    towers (tall or big, TOWER_M and BIG_M2, or a tall one's parts): [(LOOK, [lat, lon, words...]), (TOWER, tower)].
    Read a batch at a time, each row's outline dropped once its look and tower are made."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import route_bake as rb
    south, west, north, east = box
    root = "%s/release/%s/theme=buildings" % (bucket or rb.OVERTURE_BUCKET, release)
    d = ds.dataset(root + "/type=building", filesystem=filesystem, format="parquet")
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))
    said = pc.field("class").isin(list(BUILDING_CLASSES))
    for col in LOOKS:
        said = said | pc.field(col).is_valid()
    m_lat, m_lon = sketch_bake.metres_per_degree((south + north) / 2.0)
    span = BIG_M2 / (m_lat * m_lon)
    tall = ((pc.field("height") >= TOWER_M) | (pc.field("num_floors") >= TOWER_FLOORS)
            | ((pc.field("bbox", "xmax") - pc.field("bbox", "xmin")) * (pc.field("bbox", "ymax") - pc.field("bbox", "ymin")) >= span))
    cols = [c for c in ["id", "geometry", "class", "names", "height", "num_floors", "min_height", "min_floor", "has_parts"]
            + list(LOOKS) if c in d.schema.names]
    out = []
    towers = []
    n = 0
    for batch in d.to_batches(columns=cols, filter=f & (said | tall), batch_size=BATCH):
        for r in batch.to_pylist():
            if not r.get("geometry"):
                continue
            n += 1
            look = building_look(r, None)
            if look is not None:
                out.append((LOOK, look))
            towers += towers_from([r], [])
    log("features: buildings/building %d rows, %d towers" % (n, len(towers)))
    # A tall building's parts, where it has them: any part TOWER_M tall makes its building's parts its tower rows.
    parts = []
    p = ds.dataset(root + "/type=building_part", filesystem=filesystem, format="parquet")
    ptall = (pc.field("height") >= TOWER_M) | (pc.field("num_floors") >= TOWER_FLOORS)
    groups = set(t["group"] for t in towers if t["parts"] and not t["big_low"])
    for batch in p.to_batches(columns=["building_id"], filter=f & ptall, batch_size=BATCH):
        groups.update(short_id(b) for b in batch.column("building_id").to_pylist())
    if groups:
        pcols = [c for c in ["id", "building_id", "geometry", "height", "num_floors", "min_height", "min_floor", "names"]
                 + list(LOOKS) if c in p.schema.names]
        for batch in p.to_batches(columns=pcols, filter=f, batch_size=BATCH):
            ids = batch.column("building_id").to_pylist()
            keep = [k for k, b in enumerate(ids) if short_id(b) in groups]
            if keep:
                rows = batch.take(keep).to_pylist()
                parts += towers_from([], [r for r in rows if r.get("geometry")])
    log("features: buildings/building_part %d parts of %d towers" % (len(parts), len(groups)))
    return out + [(TOWER, t) for t in merge_parts(towers, parts)]


def merge_parts(towers, parts):
    """Towers with each building that has parts (`parts`, towers_from's of building_part rows) replaced by them, the
    parts with no height of their own taking their building's."""
    by_group = {}
    for t in parts:
        by_group.setdefault(t["group"], []).append(t)
    out = []
    for t in towers:
        got = by_group.pop(t["group"], None)
        if got is None:
            out.append(t)
            continue
        for q in got:
            if q["h"] is None:
                q["h"] = t["h"]
            if not q["name"]:
                q["name"] = t["name"]
            q["words"] = [t["words"][0]] + [q["words"][k] or t["words"][k] for k in range(1, len(q["words"]))]
            out.append(q)
    for got in by_group.values():   # (a tall part whose building is outside the box: kept as it is)
        out += [q for q in got if q["h"] is not None]
    return out


def towers_from(buildings, parts):
    """The towers among Overture building rows `buildings` (TOWER_M tall, or BIG_M2 big) and every building_part row
    in `parts`: [{"mid": (lon, lat), "ring": [(lon, lat)], "h": metres or None, "min": metres off the ground, "name",
    "id", "group" (its building's id), "words": [class, roof_shape, roof_color, roof_material, facade_material,
    facade_color], "big_low": a big one under TOWER_M, "parts": whether the map says it has parts}]."""
    out = []
    for is_part, rows in ((False, buildings), (True, parts)):
        for r in rows:
            try:
                _, _, rings = parse_any(r["geometry"])
            except (ValueError, struct.error, KeyError, TypeError):
                continue
            if not rings:
                continue
            ring = max(rings, key=lambda q: abs(_ring_area(q)))
            if len(ring) > 3 and ring[0] == ring[-1]:
                ring = ring[:-1]
            if len(ring) < 3:
                continue
            lon, lat = _ring_middle(ring)
            m_lat, m_lon = sketch_bake.metres_per_degree(lat)
            area = abs(_ring_area(ring)) * m_lat * m_lon
            h = number(r.get("height"))
            floors = number(r.get("num_floors"))
            if h is None and floors:
                h = round(floors * STOREY_M + 1.0, 1)
            low = number(r.get("min_height"))
            if low is None and number(r.get("min_floor")):
                low = round(number(r.get("min_floor")) * STOREY_M, 1)
            tall = h is not None and h >= TOWER_M
            if is_part:
                if area < TOWER_PART_AREA or (h is None and low is None):
                    continue
            elif not tall and area < BIG_M2:
                continue
            kept = simple(ring, lat, closed=True)
            if len(kept) < 3:
                continue
            cls = str(r["class"]).lower() if r.get("class") else None
            out.append({"mid": (lon, lat), "ring": kept, "h": h, "min": max(0.0, low or 0.0),
                        "name": english_or_primary(r.get("names")), "id": short_id(r.get("id", "")),
                        "group": short_id(r.get("building_id") if is_part else r.get("id", "")),
                        "words": [cls] + [_look_word(c, r.get(c)) for c in LOOKS],
                        "big_low": not is_part and not tall, "parts": bool(r.get("has_parts"))})
    return out


class NearGrid:
    """The roads a ride can take filed in a grid of NEAR_GRID_M squares, to find whether a place is within about NEAR_M
    of one (its square or the squares round it)."""

    def __init__(self, roads, lat0):
        import route_bake as rb
        self.m_lat, self.m_lon = sketch_bake.metres_per_degree(lat0)
        self.cells = set()
        reach = int(math.ceil(NEAR_M / NEAR_GRID_M))
        for wkb in roads:
            for line in rb.parse_wkb(wkb) or []:
                for (x0, y0), (x1, y1) in zip(line, line[1:]):
                    seg = math.hypot((x1 - x0) * self.m_lon, (y1 - y0) * self.m_lat)
                    steps = max(1, int(seg / (NEAR_GRID_M * 0.5)))
                    for k in range(steps + 1):
                        t = k / steps
                        gx, gy = self._cell(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
                        for dy in range(-reach, reach + 1):
                            for dx in range(-reach, reach + 1):
                                self.cells.add((gx + dx, gy + dy))

    def _cell(self, lon, lat):
        return int(math.floor(lon * self.m_lon / NEAR_GRID_M)), int(math.floor(lat * self.m_lat / NEAR_GRID_M))

    def near(self, lon, lat):
        return self._cell(lon, lat) in self.cells


def fetch_roads(box, release):
    import stream_bake
    pad = 0.01   # (the roads just over the box's edge count too)
    south, west, north, east = box
    return NearGrid(stream_bake.fetch_roads((south - pad, west - pad, north + pad, east + pad), release),
                    (south + north) / 2.0)


def fetch_square(box, release, log=print):
    """What a square's cells' features are made from: (its roads' NearGrid, its rows, near_filter's only)."""
    grid = fetch_roads(box, release)
    return grid, fetch(box, release, log=log, keep=near_filter(grid))


# ---------------------------------------------------------------------------- a cell's features

def cell_features(rows, grid, row, col, release=""):
    """The features of cell (row, col) from fetch's rows round it, the near ones only near the roads in `grid` (a
    NearGrid, or None for no roads: none of them)."""
    box = coast_bake.cell_box(row, col)
    lat0 = (box[0] + box[2]) / 2.0
    names = [""]
    name_ids = {"": 0}
    kind_ids = {k: i for i, k in enumerate(KINDS)}
    points, lines, areas = [], [], []

    def name_id(n):
        if n not in name_ids:
            name_ids[n] = len(names)
            names.append(n)
        return name_ids[n]

    def near(pts):
        return grid is not None and any(grid.near(lon, lat) for lon, lat in pts)

    looks = []
    words = [""]
    word_ids = {"": 0}

    def word(v):
        if v is None or v == "":
            return 0
        v = str(v)
        if v not in word_ids:
            word_ids[v] = len(words)
            words.append(v)
        return word_ids[v]

    towers = []
    for key, r in rows:
        if key == BUILDINGS:
            got = building_look(r, box)
            if got is not None:
                looks.append(got)
            towers += [t for t in towers_from([r], []) if inside(t["mid"][0], t["mid"][1], box)
                       and (not t["big_low"] or near(t["ring"]))]
            continue
        if key == LOOK:
            if s_inside(r, box):
                looks.append(list(r))
            continue
        if key == TOWER:
            if inside(r["mid"][0], r["mid"][1], box) and (not r["big_low"] or near(r["ring"])):
                towers.append(r)
            continue
        kind, only_near = kind_of(key, r)
        if kind is None:
            continue
        try:
            pts, lns, rings = parse_any(r["geometry"])
        except (ValueError, struct.error):
            continue
        tags = dict(r.get("source_tags") or [])
        height = number(r.get("height"))
        if height is None:
            height = number(tags.get("height"))
        elevation = number(r.get("elevation"))
        if elevation is None:
            elevation = number(tags.get("ele"))
        nm = r["sides"] if key[0] == "divisions" and r.get("sides") else english_or_primary(r.get("names"))
        for tag in NAME_TAGS.get(kind, ()):
            if tags.get(tag):
                nm = str(tags[tag])
                break
        oid = None if only_near else short_id(r.get("id", ""))
        k = kind_ids[kind]
        for lon, lat in pts:
            if inside(lon, lat, box) and (not only_near or near([(lon, lat)])):
                points.append([k, round(lat * SCALE), round(lon * SCALE), height, elevation, heading(tags),
                               name_id(nm), oid])
        ranges = rail_ranges(r.get("rail_flags")) if key[1] == "segment" else []
        width = number(tags.get("width"))
        for line in lns:
            for flags, piece in split_by(line, ranges):
                for run in clip_line(piece, box):
                    if only_near and not near(run):
                        continue
                    f = flat(simple(run, lat0))
                    if len(f) >= 4:
                        lines.append([k, height, width, flags, name_id(nm), oid] + f)
        for ring in rings:
            cut = coast_bake.clip(ring, box)
            if not cut or (only_near and not near(cut)):
                continue
            f = flat(simple(cut, lat0, closed=True))
            if len(f) >= 6:
                areas.append([k, height, elevation, name_id(nm), oid] + f)
    # In a fixed order (the same data bakes to the same bytes), the names numbered in it.
    points.sort(key=lambda p: (p[0], p[1], p[2], p[7] or ""))
    lines.sort(key=lambda ln: (ln[0], ln[6:], ln[5] or ""))
    areas.sort(key=lambda a: (a[0], a[5:], a[4] or ""))
    # The towers: [height, min height, name, id, group, class, roof_shape, roof_color, roof_material, facade_material,
    # facade_color, lat, lon, dlat, dlon, ...], the words numbered with the looks' (below).
    tower_rows = []
    for t in towers:
        tower_rows.append([t["h"], t["min"], name_id(t["name"]), t["id"], t["group"]] + list(t["words"]) + flat(t["ring"]))
    tower_rows.sort(key=lambda q: (q[11:], q[3], q[4]))
    order = {}
    for rows_, at in ((points, 6), (lines, 4), (areas, 3), (tower_rows, 2)):
        for row_ in rows_:
            n = names[row_[at]]
            if n and n not in order:
                order[n] = len(order) + 1
    new_names = [""] + sorted(order, key=order.get)
    for rows_, at in ((points, 6), (lines, 4), (areas, 3), (tower_rows, 2)):
        for row_ in rows_:
            row_[at] = order.get(names[row_[at]], 0)
    out = {"format": FORMAT, "cell": "%d_%d" % (row, col), "release": release, "classes": classes_hash(),
           "kinds": KINDS, "names": new_names, "points": points, "lines": lines, "areas": areas}
    if looks:
        # (a look says nothing of some things, None, and None and a word don't compare: they sort as "")
        looks.sort(key=lambda b: ["" if v is None else v for v in b])
        for b in looks:
            b[2:] = [word(v) for v in b[2:]]
        out["buildings"] = delta_rows(looks)
    if tower_rows:
        for q in tower_rows:
            q[5:11] = [word(v) for v in q[5:11]]
        out["towers"] = tower_rows
    if looks or tower_rows:
        out["words"] = words
    return out


def s_inside(look, box):
    """Whether a look ([lat, lon (1e-5 degrees), ...]) stands in box."""
    return inside(look[1] / SCALE, look[0] / SCALE, box)


def building_look(r, box):
    """What the map says building row `r` looks like, if it stands in `box`: [lat, lon (1e-5 degrees, its outline's
    middle), class, roof_shape, roof_color, roof_material, facade_material, facade_color] (the words as the map has
    them, None where it says nothing; a class only when it's one of BUILDING_CLASSES), else None."""
    try:
        pts, lns, rings = parse_any(r["geometry"])
    except (ValueError, struct.error):
        return None
    if not rings:
        return None
    ring = max(rings, key=lambda q: abs(_ring_area(q)))
    lon, lat = _ring_middle(ring)
    if box is not None and not inside(lon, lat, box):
        return None
    cls = r.get("class") if r.get("class") in BUILDING_CLASSES else None
    said = [cls] + [_look_word(c, r.get(c)) for c in LOOKS]
    if all(v is None for v in said):
        return None
    return [round(lat * SCALE), round(lon * SCALE)] + said


def _look_word(col, v):
    if v is None or v == "":
        return None
    v = str(v).strip()
    return v.upper() if col.endswith("_color") and v.startswith("#") else v.lower()


def _ring_area(ring):
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:] + ring[:1])) * 0.5


def _ring_middle(ring):
    """A ring's centroid (lon, lat), or its points' mean where it has no area."""
    a = _ring_area(ring)
    if abs(a) < 1e-14:
        return (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring))
    x0, y0 = ring[0]
    cx = cy = 0.0
    for p, q in zip(ring, ring[1:] + ring[:1]):
        cr = (p[0] - x0) * (q[1] - y0) - (q[0] - x0) * (p[1] - y0)
        cx += (p[0] + q[0] - 2 * x0) * cr
        cy += (p[1] + q[1] - 2 * y0) * cr
    return (x0 + cx / (6.0 * a), y0 + cy / (6.0 * a))


def delta_rows(looks):
    """Building looks [[lat, lon, ...], ...] (sorted) with each lat and lon after the first the step from the one
    before."""
    out = []
    last = (0, 0)
    for b in looks:
        out.append([b[0] - last[0], b[1] - last[1]] + b[2:])
        last = (b[0], b[1])
    return out


def undelta_rows(rows):
    out = []
    lat = lon = 0
    for b in rows:
        lat += b[0]
        lon += b[1]
        out.append([lat, lon] + list(b[2:]))
    return out


def cell_features_of(fetched, row, col, release=""):
    """cell_features from fetch_square's (grid, rows)."""
    return cell_features(fetched[1], fetched[0], row, col, release)


def counts(got):
    """How many of each kind a cell's (or a region's) features hold: {kind: n}."""
    out = {}
    for part in ("points", "lines", "areas"):
        for row in got[part]:
            k = got["kinds"][row[0]]
            out[k] = out.get(k, 0) + 1
    if got.get("buildings"):
        out["building looks"] = len(got["buildings"])
    return dict(sorted(out.items()))


def write(path, got):
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(got, separators=(",", ":"), ensure_ascii=False) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("lat", type=float, nargs="?")
    ap.add_argument("lon", type=float, nargs="?")
    ap.add_argument("--square", nargs=2, type=float, metavar=("LAT", "LON"), help="every cell of the 1 degree square at LAT, LON")
    ap.add_argument("--box", nargs=4, type=float, metavar=("S", "W", "N", "E"), help="the cells over a box, as one file")
    ap.add_argument("--cells", help="with --square, only these cells (ROW_COL,...)")
    ap.add_argument("--release")
    ap.add_argument("--out")
    ap.add_argument("--classes", action="store_true", help="print the hash of the classes kept, and nothing else")
    args = ap.parse_args(argv)
    if args.classes:
        print(classes_hash())
        return 0
    import route_bake as rb
    release = args.release or rb.latest_release()
    if args.box:
        # A bundled region's: its cells' features, each cut to its cell, in one file (the region's frame is the
        # game's business). Only the box's roads count for the near ones: those are the ones a ride there can take.
        south, west, north, east = args.box
        r0, c0 = coast_bake.cell_of(south, west)
        r1, c1 = coast_bake.cell_of(north, east)
        grid = fetch_roads((south, west, north, east), release)
        rows = fetch((r0 * 0.25 - 90.0, c0 * 0.25 - 180.0, (r1 + 1) * 0.25 - 90.0, (c1 + 1) * 0.25 - 180.0), release)
        cells = [cell_features(rows, grid, r, c, release) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)]
        write(args.out, merge(cells, (south, west, north, east)))
        print("%s: %s" % (args.out, counts(json.load(open(args.out, encoding="utf-8")))))
        return 0
    if args.square:
        lat, lon = math.floor(args.square[0]), math.floor(args.square[1])
        fetched = fetch_square((lat, lon, lat + 1.0, lon + 1.0), release)
        only = set(args.cells.split(",")) if args.cells else None
        os.makedirs(args.out, exist_ok=True)
        r0, c0 = coast_bake.cell_of(lat + 1e-9, lon + 1e-9)
        for r in range(r0, r0 + 4):
            for c in range(c0, c0 + 4):
                if only is not None and "%d_%d" % (r, c) not in only:
                    continue
                got = cell_features_of(fetched, r, c, release)
                write(os.path.join(args.out, "c%s.features" % got["cell"]), got)
        return 0
    if args.lat is None or args.lon is None:
        ap.error("a cell's LAT LON, --square or --box")
    row, col = coast_bake.cell_of(args.lat, args.lon)
    got = cell_features_of(fetch_square(coast_bake.cell_box(row, col), release), row, col, release)
    if args.out:
        write(args.out, got)
    else:
        print(json.dumps(got, separators=(",", ":"), ensure_ascii=False))
    return 0


def merge(cells, box=None):
    """Several cells' features as one (a bundled region's), only those touching `box` (south, west, north, east) if
    given: {"format", "release", "classes", "cells": [ROW_COL, ...], "kinds", "names", "points", "lines", "areas",
    and "words" and "buildings" where any building's look is mapped}."""
    names = [""]
    ids = {"": 0}
    out = {"format": FORMAT, "release": cells[0]["release"] if cells else "", "classes": classes_hash(), "cells": [],
           "kinds": KINDS, "names": names, "points": [], "lines": [], "areas": []}
    for got in cells:
        out["cells"].append(got["cell"])
        for part, at, first in (("points", 6, 1), ("lines", 4, 6), ("areas", 3, 5)):
            for row in got[part]:
                if box is not None and not _touches(row[:3] if part == "points" else row, first, box):
                    continue
                n = got["names"][row[at]]
                if n not in ids:
                    ids[n] = len(names)
                    names.append(n)
                row = list(row)
                row[0] = KINDS.index(got["kinds"][row[0]])
                row[at] = ids[n]
                out[part].append(row)
    # The buildings' looks, their words in one list.
    words = [""]
    wids = {"": 0}
    looks = []
    for got in cells:
        for b in undelta_rows(got.get("buildings", [])):
            if box is not None and not (box[0] * SCALE <= b[0] <= box[2] * SCALE and box[1] * SCALE <= b[1] <= box[3] * SCALE):
                continue
            row = b[:2]
            for i in b[2:]:
                w = got["words"][i]
                if w not in wids:
                    wids[w] = len(words)
                    words.append(w)
                row.append(wids[w])
            looks.append(row)
    towers = []
    for got in cells:
        for q in got.get("towers", []):
            if box is not None and not _touches(q, 11, box):
                continue
            q = list(q)
            n = got["names"][q[2]]
            if n not in ids:
                ids[n] = len(names)
                names.append(n)
            q[2] = ids[n]
            for k in range(5, 11):
                w = got["words"][q[k]]
                if w not in wids:
                    wids[w] = len(words)
                    words.append(w)
                q[k] = wids[w]
            towers.append(q)
    if looks:
        looks.sort()
        out["buildings"] = delta_rows(looks)
    if towers:
        towers.sort(key=lambda q: (q[11:], q[3], q[4]))
        out["towers"] = towers
    if looks or towers:
        out["words"] = words
    return out


def _touches(row, first, box):
    s, w, n, e = box
    lat, lon = row[first], row[first + 1]
    pts = [(lat, lon)]
    for k in range(first + 2, len(row) - 1, 2):
        lat += row[k]
        lon += row[k + 1]
        pts.append((lat, lon))
    return any(s * SCALE <= p[0] <= n * SCALE and w * SCALE <= p[1] <= e * SCALE for p in pts)


if __name__ == "__main__":
    sys.exit(main())
