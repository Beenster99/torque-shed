#!/usr/bin/env python3
"""Bakes a region of the real world for Torque Shed's adventure mode: the roads of a whole area and the land round them,
for the crew to plan a route across in the game (stage 4 of docs/real_world_plan.md).

    python3 tools/region_bake.py --name shodoshima --title "Shodoshima" \\
        --south 34.43 --west 134.12 --north 34.57 --east 134.38 --out data/regions/shodoshima

Where route_bake.py bakes the land down one chosen road, a region has every road of the area as a graph, and the land
(heights, cover, buildings, places) wherever there is a road, so the game can plan any route over it itself and ride it
(scripts/real_region.gd, scripts/route_planner.gd). A folder the game loads:

    region.json      name, credits, hash, the frame, the area, the land's levels, counts
    roads.json       the road graph: nodes, and edges between them with their class, surface, name, limit and line
    tiles/ coarse/ ridge/   the land at three levels (levels.py): .u16z heights, and .covz cover for the first two
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

FORMAT = 1
SIMPLIFY_M = 1.5            # road lines are kept to within this of the mapped ones
SAMPLE_M = 16.0             # the roads as points this far apart, for working out where the land is needed
MIN_NETWORK = 20            # road networks smaller than this many junctions are left out
BUILDING_MAX = 60000
GENERIC = list(rb.CLASSES)
SURFACES = ["tarmac", "gravel"]


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


def graph_rows(graph, min_network=MIN_NETWORK):
    """The road graph as plain rows: {nodes: [[x, z]], edges: [{a, b, c, s, l, n, p}], classes, surfaces, names}.

    Networks of fewer than `min_network` junctions are left out (stray bits of road). Nodes and names are numbered in a
    fixed order, so the same data bakes to the same bytes."""
    keep = set()
    seen = set()
    for n0 in sorted(graph.pos):
        if n0 in seen:
            continue
        comp = graph.component_of(n0)
        seen |= comp
        if len(comp) >= min_network:
            keep |= comp
    ids = sorted(keep)
    index = {n: i for i, n in enumerate(ids)}
    names = sorted({e["label"] or "" for e in graph.edges})
    edges = []
    for e in graph.edges:
        if e["a"] not in index or e["b"] not in index:
            continue
        mid = simplify(e["pts"], SIMPLIFY_M)[1:-1]
        edges.append({"a": index[e["a"]], "b": index[e["b"]], "c": GENERIC.index(e["cls"]), "s": SURFACES.index(e["surface"]),
                      "l": int(e.get("limit") or 0), "n": names.index(e["label"] or ""),
                      "p": [round(v, 1) for p in mid for v in p]})
    edges.sort(key=lambda r: (r["a"], r["b"], r["p"][:2]))
    nodes = [[round(graph.pos[n][0], 1), round(graph.pos[n][1], 1)] for n in ids]
    return {"nodes": nodes, "edges": edges, "classes": GENERIC, "surfaces": SURFACES, "names": names}


def road_points(rows, spacing=SAMPLE_M):
    """Every road as points `spacing` metres apart (an (n, 2) array): where the land is wanted."""
    nodes = rows["nodes"]
    out = []
    for e in rows["edges"]:
        line = [tuple(nodes[e["a"]])] + [(e["p"][i], e["p"][i + 1]) for i in range(0, len(e["p"]), 2)] + [tuple(nodes[e["b"]])]
        pts, _, _ = rb.resample(line, spacing)
        out.append(pts)
    return np.vstack(out) if out else np.zeros((0, 2))


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
    rows = graph_rows(graph)
    log("roads: %d junctions, %d roads kept" % (len(rows["nodes"]), len(rows["edges"])))
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
            lambda cover_tiles: land_bake.bake_land(rb.OVERTURE_BUCKET, release, frame, pts, cover_tiles, args.out, log), log)
    finally:
        land_bake.BUILDING_MAX = old_max
    x0, z0 = frame.to_world(args.north, args.west)
    x1, z1 = frame.to_world(args.south, args.east)
    meta = {
        "format": FORMAT, "kind": "region", "name": args.name, "title": args.title or args.name,
        "frame": {"lat": lat0, "lon": lon0}, "bounds": [round(float(x0), 1), round(float(z0), 1), round(float(x1), 1), round(float(z1), 1)],
        "geo": {"south": args.south, "west": args.west, "north": args.north, "east": args.east},
        "levels": [lv.meta() for lv in levels.LEVELS], "tile_counts": {k: len(v) for k, v in tiles.items()},
        "cover": land_bake.COVER, "building_kinds": land_bake.BUILDING_KINDS,
        "counts": {"nodes": len(rows["nodes"]), "edges": len(rows["edges"]), "buildings": len(land["buildings"]),
                   "pois": len(land["pois"]), "landmarks": len(land["landmarks"])},
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
    ap.add_argument("--name", required=True, help="short id, used as the folder name")
    ap.add_argument("--title", default="", help="the region's name for the magazine")
    ap.add_argument("--south", type=float, required=True)
    ap.add_argument("--west", type=float, required=True)
    ap.add_argument("--north", type=float, required=True)
    ap.add_argument("--east", type=float, required=True)
    ap.add_argument("--out", help="folder to write (default data/regions/NAME)")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/torque-shed-bake"), help="download cache")
    ap.add_argument("--release", help="Overture release, default the latest")
    ap.add_argument("--avoid", default="", help="road classes to leave out, comma-separated")
    args = ap.parse_args(argv)
    args.avoid = [c for c in args.avoid.split(",") if c]
    args.out = args.out or os.path.join("data", "regions", args.name)
    meta = bake(args)
    print("wrote %s: %s, tiles %s, hash %s" % (args.out, meta["counts"], meta["tile_counts"], meta["hash"]))


if __name__ == "__main__":
    sys.exit(main())
