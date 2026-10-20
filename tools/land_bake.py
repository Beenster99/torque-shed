"""The land beside a baked road: what covers it, the buildings on it and the places worth naming.

Used by route_bake.py (stage 2 of docs/real_world_plan.md). All from Overture Maps (ODbL), nothing from imagery:

    tiles/TX_TZ.cov   per height tile, one byte a sample (same 128 x 128 grid as the heights): COVER's ids
    buildings.json    [[x, z, w, d, yaw, h, kind, knot], ...] in the route frame, kinds as BUILDING_KINDS says,
                      knot the nearest road knot (by index), in order along the road
    landmarks.json    [{kind, name, x, z}, ...] peaks, lighthouses and the like

The data decides where things are and what kind they are; the game decides how they look.
"""
import json
import math
import os
import struct

import numpy as np
from PIL import Image, ImageDraw

STEP = 4.0
TILE_M = 512.0
TILE_N = 128

COVER = ["grass", "forest", "crop", "shrub", "barren", "urban", "sand", "wetland", "water", "rock"]
CID = {name: i for i, name in enumerate(COVER)}
BUILDING_KINDS = ["house", "shed", "barn", "shop", "block", "industrial", "worship", "civic"]
BID = {name: i for i, name in enumerate(BUILDING_KINDS)}

# Overture land_cover subtype -> cover
LAND_COVER = {"forest": "forest", "crop": "crop", "shrub": "shrub", "barren": "barren", "urban": "urban", "wetland": "wetland",
              "mangrove": "wetland", "moss": "grass", "grass": "grass", "snow": "barren"}
# base/land class -> cover
LAND = {"forest": "forest", "wood": "forest", "sand": "sand", "beach": "sand", "cliff": "rock", "rock": "rock", "stone": "rock",
        "grassland": "grass", "wetland": "wetland", "scrub": "shrub", "shrub": "shrub", "bare_rock": "rock", "scree": "rock"}
# base/land_use subtype -> cover (anything else leaves the land cover as it was)
LAND_USE = {"residential": "urban", "developed": "urban", "commercial": "urban", "industrial": "urban", "transportation": "urban",
            "education": "urban", "medical": "urban", "institutional": "urban", "agriculture": "crop", "horticulture": "crop",
            "recreation": "grass", "park": "grass", "cemetery": "grass", "managed": "grass"}
# water polygons that are not the sea (the sea is shaped into the heights)
WATER_SKIP = {"ocean", "sea", "bay", "strait", "swimming_pool"}

BUILDING_REACH = 500.0       # buildings are kept this far either side of the road
BUILDING_GAP = 4.0           # and this far clear of the road's edge
BUILDING_MAX = 14000
BUILDING_MIN_AREA = 9.0
BUILDING_MAX_AREA = 2500.0
LANDMARK_REACH = {"peak": 3500.0, "lighthouse": 2500.0, "beach": 800.0, "worship": 500.0, "castle": 2000.0}

PLACE_KINDS = {"lighthouse": "lighthouse", "castle": "castle", "beach": "beach",
               "buddhist_place_of_worship": "worship", "shinto_place_of_worship": "worship",
               "christian_place_of_worship": "worship"}


# ---------------------------------------------------------------------------- geometry

def parse_geometry(wkb):
    """A WKB geometry as a list of polygons, each a list of rings of (lon, lat); points and lines give none."""
    def read(buf, off):
        order = "<" if buf[off] == 1 else ">"
        kind = struct.unpack_from(order + "I", buf, off + 1)[0] % 1000
        off += 5
        if kind == 3:
            nr = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            rings = []
            for _ in range(nr):
                n = struct.unpack_from(order + "I", buf, off)[0]
                off += 4
                pts = struct.unpack_from(order + "%dd" % (2 * n), buf, off)
                off += 16 * n
                rings.append(list(zip(pts[0::2], pts[1::2])))
            return [rings], off
        if kind in (6, 7):
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            out = []
            for _ in range(n):
                part, off = read(buf, off)
                out += part
            return out, off
        if kind == 1:
            return [], off + 16
        if kind == 2:
            n = struct.unpack_from(order + "I", buf, off)[0]
            return [], off + 4 + 16 * n
        if kind == 5:
            n = struct.unpack_from(order + "I", buf, off)[0]
            off += 4
            for _ in range(n):
                _, off = read(buf, off)
            return [], off
        raise ValueError("unsupported geometry type %d" % kind)
    return read(bytes(wkb), 0)[0]


def parse_point(wkb):
    """(lon, lat) of a WKB point, or None."""
    buf = bytes(wkb)
    order = "<" if buf[0] == 1 else ">"
    if struct.unpack_from(order + "I", buf, 1)[0] % 1000 != 1:
        return None
    return struct.unpack_from(order + "2d", buf, 5)


def english_name(names):
    """A name the game can print: English, else a Latin-script one, else the primary if it is plain ASCII, else ''."""
    if not names:
        return ""
    common = names.get("common") or {}
    common = dict(common)
    for key in ("en", "ja-Latn", "ja_latn"):
        if common.get(key):
            return str(common[key])
    primary = str(names.get("primary") or "")
    return primary if primary.isascii() else ""


# ---------------------------------------------------------------------------- fetching

def fetch(bucket, release, theme, kind, box, columns, filesystem=None):
    """Rows of an Overture dataset touching box = (south, west, north, east) as plain dicts."""
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as pafs
    s3 = filesystem or pafs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset("%s/release/%s/theme=%s/type=%s" % (bucket, release, theme, kind), filesystem=s3, format="parquet")
    south, west, north, east = box
    f = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
         & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))
    cols = [c for c in columns if c in d.schema.names]
    return d.to_table(columns=cols, filter=f).to_pylist()


# ---------------------------------------------------------------------------- the cover raster

def polygon_layers(rows, frame, classify):
    """[(cover id, ring points as an (n, 2) array in the route frame, ...)]: the rows' polygons in drawing order."""
    out = []
    for row in rows:
        cover = classify(row)
        if cover is None:
            continue
        try:
            polys = parse_geometry(row["geometry"])
        except (ValueError, struct.error):
            continue
        for rings in polys:
            pts = []
            for ring in rings:
                lon, lat = zip(*ring)
                x, z = frame.to_world(np.array(lat), np.array(lon))
                pts.append(np.column_stack([x, z]))
            if pts:
                lo = pts[0].min(axis=0)
                hi = pts[0].max(axis=0)
                out.append((CID[cover], pts, (lo[0], lo[1], hi[0], hi[1])))
    return out


def rasterise_tile(tx, tz, layers):
    """One tile's cover bytes (TILE_N x TILE_N, row = z): the layers drawn in order over grass."""
    img = Image.new("L", (TILE_N, TILE_N), 0)
    draw = ImageDraw.Draw(img)
    x0, z0 = tx * TILE_M, tz * TILE_M
    x1, z1 = x0 + TILE_M, z0 + TILE_M
    for cid, rings, (lx, lz, hx, hz) in layers:
        if hx < x0 or lx > x1 or hz < z0 or lz > z1:
            continue
        pts = [((p[:, 0] - x0) / STEP, (p[:, 1] - z0) / STEP) for p in rings]
        if len(pts[0][0]) < 3:
            continue
        draw.polygon(list(zip(*pts[0])), fill=cid)
        for hole in pts[1:]:
            if len(hole[0]) >= 3:
                draw.polygon(list(zip(*hole)), fill=0)   # (a hole shows grass: good enough for forest clearings)
    return np.asarray(img, dtype=np.uint8)


def cover_layers(frame, box, bucket, release, log=print):
    """Every cover polygon in the box in drawing order: land cover, land, land use, then water on top."""
    layers = []
    rows = fetch(bucket, release, "base", "land_cover", box, ["geometry", "subtype"])
    layers += polygon_layers(rows, frame, lambda r: LAND_COVER.get(str(r.get("subtype"))))
    rows = fetch(bucket, release, "base", "land", box, ["geometry", "subtype", "class"])
    layers += polygon_layers(rows, frame, lambda r: LAND.get(str(r.get("class"))))
    rows = fetch(bucket, release, "base", "land_use", box, ["geometry", "subtype", "class"])
    layers += polygon_layers(rows, frame, lambda r: LAND_USE.get(str(r.get("subtype"))))
    rows = fetch(bucket, release, "base", "water", box, ["geometry", "subtype", "class"])
    layers += polygon_layers(rows, frame, lambda r: None if str(r.get("subtype")) in WATER_SKIP or str(r.get("class")) in WATER_SKIP
                             else "water")
    log("cover: %d polygons" % len(layers))
    return layers


# ---------------------------------------------------------------------------- buildings

def min_rect(pts):
    """The smallest rectangle round points (x, z): (centre x, centre z, width, depth, yaw radians)."""
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


def building_kind(row, w, d):
    cls = str(row.get("class") or "")
    sub = str(row.get("subtype") or "")
    area = w * d
    if cls in ("temple", "church", "cathedral", "chapel", "mosque", "synagogue", "shrine", "religious") or sub == "religious":
        return "worship"
    if cls in ("apartments", "dormitory", "terrace") or (sub == "residential" and area > 600.0):
        return "block"
    if cls in ("warehouse", "industrial", "factory", "storage_tank", "service", "manufacture") or sub == "industrial":
        return "industrial"
    if cls in ("barn", "farm_auxiliary", "agricultural", "greenhouse", "cowshed", "stable", "sty", "farm") or sub == "agricultural":
        return "barn"
    if cls in ("garage", "garages", "carport", "shelter", "roof", "shed", "hut", "outbuilding", "allotment_house") or sub == "outbuilding":
        return "shed"
    if cls in ("commercial", "retail", "supermarket", "hotel", "kiosk", "office") or sub == "commercial":
        return "shop"
    if cls in ("public", "government", "school", "kindergarten", "university", "hospital", "train_station", "civic", "post_office",
               "sports_hall", "stadium", "college") or sub in ("civic", "education", "medical", "transportation", "entertainment", "service"):
        return "civic"
    if area < 28.0:
        return "shed"
    if area > 900.0:
        return "industrial"
    return "house"


DEFAULT_HEIGHT = {"house": 5.5, "shed": 3.0, "barn": 6.0, "shop": 6.5, "block": 14.0, "industrial": 7.5, "worship": 8.0, "civic": 8.5}


def make_buildings(rows, frame, knots, reach=BUILDING_REACH, gap=BUILDING_GAP, max_count=BUILDING_MAX):
    """Building boxes within `reach` of the road, clear of it: [[x, z, w, d, yaw, h, kind id]], nearest the road first."""
    cell = 64.0
    grid = {}
    for k in range(0, len(knots), 2):
        grid.setdefault((int(knots[k][0] // cell), int(knots[k][1] // cell)), []).append((k, knots[k][0], knots[k][1]))
    span = int(reach // cell) + 1

    def road_distance(x, z):
        """(distance to the road, the knot nearest)."""
        best, at = 1e9, 0
        gx, gz = int(x // cell), int(z // cell)
        for ix in range(gx - span, gx + span + 1):
            for iz in range(gz - span, gz + span + 1):
                for k, px, pz in grid.get((ix, iz), ()):
                    d = math.hypot(x - px, z - pz)
                    if d < best:
                        best, at = d, k
        return best, at

    out = []
    for row in rows:
        try:
            polys = parse_geometry(row["geometry"])
        except (ValueError, struct.error):
            continue
        if row.get("is_underground"):
            continue
        for rings in polys:
            if not rings or len(rings[0]) < 4:
                continue
            lon, lat = zip(*rings[0])
            x, z = frame.to_world(np.array(lat), np.array(lon))
            cx, cz, w, d, yaw = min_rect(np.column_stack([x, z]))
            if not (BUILDING_MIN_AREA <= w * d <= BUILDING_MAX_AREA) or min(w, d) < 2.5:
                continue
            near, knot = road_distance(cx, cz)
            if near > reach or near < gap + math.hypot(w, d) * 0.5 * 0.55 + 2.0:
                continue
            kind = building_kind(row, w, d)
            height = row.get("height")
            floors = row.get("num_floors")
            h = float(height) if height else (float(floors) * 3.0 + 1.0 if floors else DEFAULT_HEIGHT[kind])
            h = min(max(h, 2.6), 40.0)
            out.append((near, [round(cx, 2), round(cz, 2), round(w, 2), round(d, 2), round(yaw, 4), round(h, 1), BID[kind], knot]))
    out.sort(key=lambda t: (t[0], t[1][0], t[1][1]))
    kept = [b for _, b in out[:max_count]]
    kept.sort(key=lambda b: (b[7], b[0], b[1]))   # along the road
    return kept


def level_ground(heights, tx, tz, buildings, margin=2.5, feather=5.0):
    """Levels the ground under each building to the mean of what is there, feathered into the land round it."""
    x0, z0 = tx * TILE_M, tz * TILE_M
    out = heights.copy()
    for b in buildings:
        x, z, w, d, yaw = b[0], b[1], b[2], b[3], b[4]
        r = math.hypot(w, d) * 0.5 + margin + feather
        if x + r < x0 or x - r > x0 + TILE_M or z + r < z0 or z - r > z0 + TILE_M:
            continue
        i0, i1 = int(math.floor((x - r - x0) / STEP)), int(math.ceil((x + r - x0) / STEP))
        j0, j1 = int(math.floor((z - r - z0) / STEP)), int(math.ceil((z + r - z0) / STEP))
        i0, i1 = max(i0, 0), min(i1, TILE_N - 1)
        j0, j1 = max(j0, 0), min(j1, TILE_N - 1)
        if i0 > i1 or j0 > j1:
            continue
        ii, jj = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1))
        px = x0 + ii * STEP - x
        pz = z0 + jj * STEP - z
        c, s = math.cos(yaw), math.sin(yaw)
        lx = px * c - pz * s
        lz = px * s + pz * c
        out_x = np.maximum(np.abs(lx) - w * 0.5 - margin, 0.0)
        out_z = np.maximum(np.abs(lz) - d * 0.5 - margin, 0.0)
        dist = np.hypot(out_x, out_z)
        inside = dist <= 0.0
        if not inside.any():
            continue
        # (the mean over the footprint's samples in this tile: across a tile edge each side uses its own)
        level = float(np.mean(heights[jj[inside], ii[inside]]))
        t = np.clip(1.0 - dist / feather, 0.0, 1.0)
        t = t * t * (3.0 - 2.0 * t)
        sel = heights[j0:j1 + 1, i0:i1 + 1]
        out[j0:j1 + 1, i0:i1 + 1] = sel + (level - sel) * t
    return out


# ---------------------------------------------------------------------------- landmarks

def make_landmarks(places, peaks, frame, knots):
    """[{kind, name, x, z}] for the named peaks, lighthouses and the like near the road."""
    pts = knots[::8]
    out = []

    def near(x, z):
        return float(np.min(np.hypot(pts[:, 0] - x, pts[:, 1] - z)))

    for row in peaks:
        if str(row.get("class")) != "peak":
            continue
        ll = parse_point(row["geometry"])
        name = english_name(row.get("names"))
        if ll is None:
            continue
        x, z = frame.to_world(ll[1], ll[0])
        if near(float(x), float(z)) <= LANDMARK_REACH["peak"]:
            out.append({"kind": "peak", "name": name, "x": round(float(x), 1), "z": round(float(z), 1)})
    for row in places:
        kind = PLACE_KINDS.get(str(row.get("basic_category")))
        if kind is None or float(row.get("confidence") or 0.0) < 0.6:
            continue
        ll = parse_point(row["geometry"])
        if ll is None:
            continue
        x, z = frame.to_world(ll[1], ll[0])
        if near(float(x), float(z)) <= LANDMARK_REACH[kind]:
            out.append({"kind": kind, "name": english_name(row.get("names")), "x": round(float(x), 1), "z": round(float(z), 1)})
    out.sort(key=lambda m: (m["kind"], m["x"], m["z"]))
    return out


# ---------------------------------------------------------------------------- the lot

def bake_land(bucket, release, frame, knots, tiles, out, log=print):
    """Fetches and writes the cover tiles, buildings and landmarks; returns {buildings, landmarks, layers} for the baker."""
    reach = max(BUILDING_REACH, 1400.0)
    lo = knots.min(axis=0) - reach - TILE_M
    hi = knots.max(axis=0) + reach + TILE_M
    lat_n, lon_w = frame.to_geo(lo[0], lo[1])
    lat_s, lon_e = frame.to_geo(hi[0], hi[1])
    box = (float(lat_s), float(lon_w), float(lat_n), float(lon_e))
    layers = cover_layers(frame, box, bucket, release, log)
    rows = fetch(bucket, release, "buildings", "building", box,
                 ["geometry", "height", "num_floors", "class", "subtype", "is_underground"])
    log("buildings: %d footprints in the box" % len(rows))
    buildings = make_buildings(rows, frame, knots)
    log("buildings: %d kept" % len(buildings))
    places = fetch(bucket, release, "places", "place", box, ["geometry", "basic_category", "names", "confidence"])
    peaks = fetch(bucket, release, "base", "land", box, ["geometry", "class", "names"])
    landmarks = make_landmarks(places, peaks, frame, knots)
    log("landmarks: %d" % len(landmarks))
    with open(os.path.join(out, "buildings.json"), "w") as f:
        json.dump(buildings, f, separators=(",", ":"))
    with open(os.path.join(out, "landmarks.json"), "w") as f:
        json.dump(landmarks, f, separators=(",", ":"))
    os.makedirs(os.path.join(out, "tiles"), exist_ok=True)
    for tx, tz in tiles:
        rasterise_tile(tx, tz, layers).tofile(os.path.join(out, "tiles", "%d_%d.cov" % (tx, tz)))
    return {"buildings": buildings, "landmarks": landmarks}
