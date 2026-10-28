#!/usr/bin/env python3
"""Bakes a region of the real world for Torque Shed's adventure mode: the roads of a whole area and the land round them,
for the crew to plan a route across in the game (stage 4 of docs/real_world_plan.md).

    python3 tools/region_bake.py --name shodoshima --title "Shodoshima" \\
        --south 34.43 --west 134.12 --north 34.57 --east 134.38 --out data/regions/shodoshima

Where route_bake.py bakes the land down one chosen road, a region has every road of the area as a graph, and the land
(heights, cover, buildings, places) wherever there is a road, so the game can plan any route over it itself and ride it
(scripts/real_region.gd, scripts/route_planner.gd). A folder the game loads:

    region.json      name, credits, hash, the frame, the area, the land's levels, counts
    roads.json       the road graph: nodes, and edges between them with their class, surface, name, limit, line and
                     which way they may be driven (o: 0 both, 1 a to b, -1 b to a); bans: turns the rules prohibit
    places.json      the towns, villages and quarters of the area with names we can print, for finding on the map
    tiles/ coarse/ ridge/   the land at three levels (levels.py): .u16z heights, and .covz cover for the first two; with
                     --heights live, the cover only (the game reads the heights from Mapterhorn's map tiles itself)
    buildings.json   [[x, z, w, d, yaw, h, kind, 0], ...] beside any road (kind: land_bake.BUILDING_KINDS)
    pois.json        places to stop beside any road (road_facts.make_pois)
    landmarks.json   named peaks, lighthouses and the like

Everything is in a frame of its own: metres from the area's middle, +x east, -z north, heights above sea level.
Needs numpy and Pillow, and pyarrow for the data. No API keys.
"""
import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import land_bake  # noqa: E402
import levels  # noqa: E402
import road_facts  # noqa: E402
import route_bake as rb  # noqa: E402

FORMAT = 2
SIMPLIFY_M = 1.5            # road lines are kept to within this of the mapped ones
SAMPLE_M = 16.0             # the roads as points this far apart, for working out where the land is needed
MIN_NETWORK = 20            # road networks smaller than this many junctions are left out
PLACE_REACH = 1500.0        # a town or village this far from any road is on the map; further is not somewhere to ride to
PLACE_KINDS = {"locality": "town", "county": "town", "borough": "town", "macrohood": "village", "microhood": "village",
               "neighborhood": "village"}
BUILDING_MAX = 60000
# Each class's carriageway width (m), as the game lays it (RoutePlanner.WIDTH): the buildings are kept off it.
ROAD_WIDTH = {"motorway": 7.4, "trunk": 7.4, "primary": 7.4, "secondary": 6.0, "tertiary": 6.0, "unclassified": 4.6,
              "residential": 4.6, "living_street": 4.6, "track": 3.3}
GENERIC = list(rb.CLASSES)
SURFACES = ["tarmac", "gravel"]


CELL_DEG = 0.25             # the world's grid of cells: this many degrees of latitude and of longitude a side


def cell_of(lat, lon):
    """The (row, column) of the cell that (lat, lon) is in: rows up from the south pole, columns east from 180 W."""
    return int(math.floor((lat + 90.0) / CELL_DEG)), int(math.floor((lon + 180.0) / CELL_DEG))


def cell_box(i, j):
    """Cell (i, j)'s (south, west, north, east) in degrees."""
    return (i * CELL_DEG - 90.0, j * CELL_DEG - 180.0, (i + 1) * CELL_DEG - 90.0, (j + 1) * CELL_DEG - 180.0)


def cell_name(i, j):
    return "c%d_%d" % (i, j)


def simplify(pts, tol):
    """The polyline through `pts` ((x, z) pairs) with points within `tol` metres of the line dropped (Douglas-Peucker),
    both ends kept."""
    if len(pts) < 3:
        return list(pts)
    a = np.array(pts, dtype=float)
    keep = np.zeros(len(a), dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(a) - 1)]
    while stack:
        lo, hi = stack.pop()
        if hi <= lo + 1:
            continue
        d = a[hi] - a[lo]
        n = math.hypot(d[0], d[1])
        seg = a[lo + 1:hi] - a[lo]
        dist = np.hypot(seg[:, 0], seg[:, 1]) if n < 1e-9 else np.abs(seg[:, 0] * d[1] - seg[:, 1] * d[0]) / n
        i = int(np.argmax(dist))
        if dist[i] > tol:
            keep[lo + 1 + i] = True
            stack.append((lo, lo + 1 + i))
            stack.append((lo + 1 + i, hi))
    return [tuple(p) for p in a[keep]]


def graph_rows(graph, min_network=MIN_NETWORK, ids=False):
    """The road graph as plain rows: {nodes: [[x, z]], edges: [{a, b, c, s, l, n, o, p}], bans: [[from edge, node, to
    edge]], classes, surfaces, names}.

    Networks of fewer than `min_network` junctions are left out (stray bits of road). Nodes and names are numbered in a
    fixed order, so the same data bakes to the same bytes. With `ids` the rows also carry "ids", each node's short id
    (short_id of its Overture connector), and each edge a "g", its segment's: a cell's roads that run on into the next
    cell are the same nodes and edges there, and the game joins the two by these (RealRegion.stitch)."""
    keep = set()
    seen = set()
    for n0 in sorted(graph.pos):
        if n0 in seen:
            continue
        comp = graph.component_of(n0)
        seen |= comp
        if len(comp) >= min_network:
            keep |= comp
    node_ids = sorted(keep)
    index = {n: i for i, n in enumerate(node_ids)}
    names = sorted({e["label"] or "" for e in graph.edges})
    edges = []
    for ei, e in enumerate(graph.edges):
        if e["a"] not in index or e["b"] not in index:
            continue
        mid = simplify(e["pts"], SIMPLIFY_M)[1:-1]
        row = {"a": index[e["a"]], "b": index[e["b"]], "c": GENERIC.index(e["cls"]), "s": SURFACES.index(e["surface"]),
               "l": int(e.get("limit") or 0), "n": names.index(e["label"] or ""), "o": int(e.get("oneway", 0)),
               "p": [round(v, 1) for p in mid for v in p], "_ei": ei}
        if ids:
            row["g"] = short_id(e.get("seg") or "")
        edges.append(row)
    edges.sort(key=lambda r: (r["a"], r["b"], r["p"][:2]))
    new_index = {r.pop("_ei"): i for i, r in enumerate(edges)}
    bans = sorted([new_index[ef], index[node], new_index[et]] for ef, node, et in graph.bans
                  if ef in new_index and et in new_index and node in index)
    nodes = [[round(graph.pos[n][0], 1), round(graph.pos[n][1], 1)] for n in node_ids]
    out = {"nodes": nodes, "edges": edges, "bans": bans, "classes": GENERIC, "surfaces": SURFACES, "names": names}
    if ids:
        out["ids"] = [short_id(n) for n in node_ids]
    return out


def short_id(overture_id):
    """An Overture id as 12 hex digits (the first of its SHA-1): unique enough among a few cells' roads, a third of the size."""
    return hashlib.sha1(str(overture_id).encode()).hexdigest()[:12]


def make_places(divisions, frame, pts, bounds, reach=PLACE_REACH):
    """The area's towns, villages and quarters (Overture divisions) with a name we can print, within `reach` of a
    road: [{kind, name, x, z, pop}] sorted by name. The same name twice close together is one place."""
    out = []
    for row in divisions:
        kind = PLACE_KINDS.get(str(row.get("subtype")))
        name = road_facts.english_name(row.get("names"))
        if kind is None or not name:
            continue
        ll = road_facts.parse_point(row["geometry"])
        if ll is None:
            continue
        x, z = frame.to_world(ll[1], ll[0])
        x, z = float(x), float(z)
        if not (bounds[0] <= x <= bounds[2] and bounds[1] <= z <= bounds[3]):
            continue
        if len(pts) and float(np.min(np.hypot(pts[:, 0] - x, pts[:, 1] - z))) > reach:
            continue
        out.append({"kind": kind, "name": name, "x": round(x, 1), "z": round(z, 1), "pop": int(row.get("population") or 0)})
    out.sort(key=lambda p: (p["name"], -p["pop"], p["kind"], p["x"], p["z"]))
    kept = []
    for p in out:
        if any(q["name"] == p["name"] and math.hypot(q["x"] - p["x"], q["z"] - p["z"]) < 1500.0 for q in kept):
            continue
        kept.append(p)
    return kept


def road_points(rows, spacing=SAMPLE_M):
    """Every road as points `spacing` metres apart (an (n, 2) array): where the land is wanted."""
    nodes = rows["nodes"]
    out = []
    for e in rows["edges"]:
        line = [tuple(nodes[e["a"]])] + [(e["p"][i], e["p"][i + 1]) for i in range(0, len(e["p"]), 2)] + [tuple(nodes[e["b"]])]
        pts, _, _ = rb.resample(line, spacing)
        out.append(pts)
    return np.vstack(out) if out else np.zeros((0, 2))


def road_lines(rows):
    """Every road's line with half its width (land_bake.RoadLines): the buildings are kept off all of them."""
    nodes = rows["nodes"]
    out = []
    for e in rows["edges"]:
        line = [tuple(nodes[e["a"]])] + [(e["p"][i], e["p"][i + 1]) for i in range(0, len(e["p"]), 2)] + [tuple(nodes[e["b"]])]
        out.append((line, ROAD_WIDTH.get(rows["classes"][e["c"]], 4.6) * 0.5))
    return land_bake.RoadLines(out)


def region_hash(out):
    h = hashlib.sha256()
    for root, _, files in sorted(os.walk(out)):
        for fn in sorted(files):
            if fn == "region.json":
                continue
            with open(os.path.join(root, fn), "rb") as f:
                h.update(f.read())
    return h.hexdigest()[:16]


def bake(args, log=print):
    release = args.release or rb.latest_release()
    log("Overture release %s" % release)
    lat0, lon0 = (args.south + args.north) / 2.0, (args.west + args.east) / 2.0
    frame = rb.Frame(lat0, lon0)
    segments = rb.fetch_segments(args.south, args.west, args.north, args.east, release, log)
    graph = rb.Graph(segments, frame, set(args.avoid or []))
    cell = getattr(args, "cell", None)
    cover_levels = levels.CELL_COVER_LEVELS if cell else levels.COVER_LEVELS
    # (a cell keeps every bit of road: a stub at its edge is part of a network in the next cell)
    rows = graph_rows(graph, 1, ids=True) if cell else graph_rows(graph)
    log("roads: %d junctions, %d roads kept, %d one-way, %d banned turns" % (
        len(rows["nodes"]), len(rows["edges"]), sum(1 for e in rows["edges"] if e["o"]), len(rows["bans"])))
    if not rows["edges"]:
        raise SystemExit("no roads in that area")
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "roads.json"), "w") as f:
        json.dump(rows, f, separators=(",", ":"))
    pts = road_points(rows)
    # The land wherever there is a road (and its reach), at every level.
    dem = rb.Dem(args.cache, lat0, log)
    dems = {lv.name: (dem if lv is levels.FINE else rb.Dem(args.cache, lat0, log, lv.spacing)) for lv in levels.LEVELS}
    old_max = land_bake.BUILDING_MAX
    land_bake.BUILDING_MAX = BUILDING_MAX
    try:
        tiles, has_sea, land = rb.bake_terrain(
            args.out, frame, pts, dems,
            lambda cover_tiles: land_bake.bake_land(rb.OVERTURE_BUCKET, release, frame, pts, cover_tiles, args.out, log,
                                                    cover_levels=cover_levels, roads=road_lines(rows)), log,
            heights=getattr(args, "heights", "baked") == "baked", cover_levels=cover_levels)
    finally:
        land_bake.BUILDING_MAX = old_max
    x0, z0 = frame.to_world(args.north, args.west)
    x1, z1 = frame.to_world(args.south, args.east)
    bounds = [round(float(x0), 1), round(float(z0), 1), round(float(x1), 1), round(float(z1), 1)]
    divisions = land_bake.fetch(rb.OVERTURE_BUCKET, release, "divisions", "division",
                                (args.south, args.west, args.north, args.east), ["geometry", "subtype", "names", "population"])
    places = make_places(divisions, frame, pts, bounds)
    log("places: %d towns and villages with names (%d divisions in the box)" % (len(places), len(divisions)))
    with open(os.path.join(args.out, "places.json"), "w") as f:
        json.dump(places, f, separators=(",", ":"))
    meta = {
        "format": FORMAT, "kind": "cell" if cell else "region", "name": args.name, "title": args.title or args.name,
        "frame": {"lat": lat0, "lon": lon0}, "bounds": bounds,
        "geo": {"south": args.south, "west": args.west, "north": args.north, "east": args.east},
        "heights": getattr(args, "heights", "baked"),
        "cell": list(cell) if cell else None,
        "levels": ([lv.meta(cover=lv in cover_levels) for lv in levels.LEVELS + [c for c in cover_levels if c not in levels.LEVELS]]
                   if cell else [lv.meta() for lv in levels.LEVELS]),
        "tile_counts": {k: len(v) for k, v in tiles.items()},
        "cover": land_bake.COVER, "building_kinds": land_bake.BUILDING_KINDS,
        "counts": {"nodes": len(rows["nodes"]), "edges": len(rows["edges"]), "buildings": len(land["buildings"]),
                   "pois": len(land["pois"]), "landmarks": len(land["landmarks"]), "places": len(places),
                   "oneway": sum(1 for e in rows["edges"] if e["o"]), "bans": len(rows["bans"])},
        "sea": has_sea, "theme": "coastal" if has_sea else "hills", "region": road_facts.region_of(lat0, lon0),
        "sources": {"overture_release": release, "elevation": "Mapterhorn, AWS Terrain Tiles fallback"},
        "credits": rb.CREDITS,
    }
    meta["hash"] = region_hash(args.out)
    with open(os.path.join(args.out, "region.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--name", help="short id, used as the folder name (a cell's is c<row>_<column>)")
    ap.add_argument("--title", default="", help="the region's name for the magazine")
    ap.add_argument("--south", type=float)
    ap.add_argument("--west", type=float)
    ap.add_argument("--north", type=float)
    ap.add_argument("--east", type=float)
    ap.add_argument("--cell", type=float, nargs=2, metavar=("LAT", "LON"),
                    help="bake the cell (a 0.25 degree square of the world's grid) this point is in, with live heights, into"
                         " data/cells/c<row>_<column> (see docs/ride_anywhere_plan.md)")
    ap.add_argument("--out", help="folder to write (default data/regions/NAME)")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/torque-shed-bake"), help="download cache")
    ap.add_argument("--release", help="Overture release, default the latest")
    ap.add_argument("--avoid", default="", help="road classes to leave out, comma-separated")
    ap.add_argument("--heights", choices=["baked", "live"], default="baked",
                    help="bake the land's heights in (baked), or leave them to the game to read from the map tiles (live)")
    args = ap.parse_args(argv)
    args.avoid = [c for c in args.avoid.split(",") if c]
    if args.cell:
        i, j = cell_of(*args.cell)
        args.cell = (i, j)
        args.south, args.west, args.north, args.east = cell_box(i, j)
        args.name = args.name or cell_name(i, j)
        args.heights = "live"
        args.out = args.out or os.path.join("data", "cells", args.name)
    elif None in (args.name, args.south, args.west, args.north, args.east):
        ap.error("give --name and the box (--south --west --north --east), or --cell")
    args.out = args.out or os.path.join("data", "regions", args.name)
    meta = bake(args)
    print("wrote %s: %s, tiles %s, hash %s" % (args.out, meta["counts"], meta["tile_counts"], meta["hash"]))


if __name__ == "__main__":
    sys.exit(main())
