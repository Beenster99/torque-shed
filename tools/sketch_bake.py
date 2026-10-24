#!/usr/bin/env python3
"""The main-roads sketch of a baked cell, for the Route planner TV between the globe and the roads: its motorways,
trunk roads and A roads (the classes "motorway", "trunk", "primary"), simplified, as latitudes and longitudes. About
12 KB a cell on average: a country's worth can be fetched at once.

    python3 tools/sketch_bake.py CELL_DIR [--out FILE]            # one cell's sketch: {"cell", "lines"}
    python3 tools/sketch_bake.py CELL_DIR --coast COAST.json      # with the cell's coast (coast_bake.py) as "land"
    python3 tools/sketch_bake.py --block OUT SKETCH.json ...       # merged into a 5 degree block's file

A cell's sketch: {"cell": "ROW_COL", "lines": [[class, [lat, lon, dlat, dlon, dlat, dlon, ...]], ...]}, class 0
motorway, 1 trunk, 2 primary; the first point in 1e-5 degrees, each after it as the step from the one
before. A road is joined up through its junctions into lines as long as they go, so a city's are few. A block's file: {"format": 1, "cells": {"ROW_COL": lines, ...}, "land": {"ROW_COL":
the cell's coast (coast_bake.py), ...}} with the cells of one release block (cells-RELEASE-bR_C: rows R*20.., columns
C*20..), each replaced as it is baked again. A sketch with only "lines" or only "land" changes just that.
"""
import argparse
import hashlib
import json
import math
import os
import sys

CLASSES = ["motorway", "trunk", "primary"]
# How far (m) a simplified road may stray from the baked one.
TOLERANCE = 40.0
SCALE = 1e5


def metres_per_degree(lat):
    """(metres per degree of latitude, of longitude) at `lat`: the baker's frame (tools/route_bake.py Frame)."""
    p = math.radians(lat)
    return (111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p),
            111412.84 * math.cos(p) - 93.5 * math.cos(3 * p) + 0.118 * math.cos(5 * p))


def simplify(pts, tol):
    """Douglas-Peucker on a list of (x, z): the points to keep so the line strays no more than `tol`."""
    if len(pts) < 3:
        return list(pts)
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        ax, az = pts[a]
        bx, bz = pts[b]
        dx, dz = bx - ax, bz - az
        length = math.hypot(dx, dz)
        best, at = -1.0, -1
        for i in range(a + 1, b):
            px, pz = pts[i]
            d = math.hypot(px - ax, pz - az) if length < 1e-9 else abs(dx * (pz - az) - dz * (px - ax)) / length
            if d > best:
                best, at = d, i
        if best > tol:
            keep[at] = True
            stack.append((a, at))
            stack.append((at, b))
    return [p for p, k in zip(pts, keep) if k]


def chains(all_edges, edges, nodes):
    """The edges `edges` (indices into `all_edges`) joined into lines of points: each runs on through junctions where
    exactly two of them meet, and stops where a road ends or several meet."""
    ends = {}
    for ei in edges:
        e = all_edges[ei]
        ends.setdefault(e["a"], []).append(ei)
        ends.setdefault(e["b"], []).append(ei)

    def points(ei, start):
        e = all_edges[ei]
        p = e.get("p", [])
        pts = [tuple(nodes[e["a"]])] + [(p[i], p[i + 1]) for i in range(0, len(p), 2)] + [tuple(nodes[e["b"]])]
        return pts if start == e["a"] else pts[::-1]

    used = set()
    out = []
    # Lines start where a road ends or several meet; what's left (rings) starts anywhere.
    starts = [n for n, es in ends.items() if len(es) != 2] + list(ends.keys())
    for n0 in starts:
        for ei0 in ends[n0]:
            if ei0 in used:
                continue
            line = []
            n, ei = n0, ei0
            while ei is not None and ei not in used:
                used.add(ei)
                pts = points(ei, n)
                line += pts if not line else pts[1:]
                e = all_edges[ei]
                n = e["b"] if n == e["a"] else e["a"]
                nxt = [x for x in ends[n] if x not in used]
                ei = nxt[0] if len(ends[n]) == 2 and nxt else None
            out.append(line)
    return out


def cell_sketch(cell_dir):
    """The sketch of the cell baked into `cell_dir` (its region.json and roads.json)."""
    with open(os.path.join(cell_dir, "region.json")) as f:
        meta = json.load(f)
    with open(os.path.join(cell_dir, "roads.json")) as f:
        rows = json.load(f)
    lat0, lon0 = float(meta["frame"]["lat"]), float(meta["frame"]["lon"])
    m_lat, m_lon = metres_per_degree(lat0)
    classes = rows.get("classes", [])
    wanted = {i: CLASSES.index(c) for i, c in enumerate(classes) if c in CLASSES}
    nodes = rows["nodes"]
    # The roads of each class, joined end to end through the junctions where only two of them meet.
    by_class = {}
    for ei, e in enumerate(rows["edges"]):
        if e["c"] in wanted:
            by_class.setdefault(wanted[e["c"]], []).append(ei)
    lines = []
    for cls, edges in sorted(by_class.items()):
        for chain in chains(rows["edges"], edges, nodes):
            flat = []
            last = None
            for x, z in simplify(chain, TOLERANCE):
                q = (round((lat0 - z / m_lat) * SCALE), round((lon0 + x / m_lon) * SCALE))
                if last is None:
                    flat += [q[0], q[1]]
                elif q != last:
                    flat += [q[0] - last[0], q[1] - last[1]]
                else:
                    continue
                last = q
            if len(flat) >= 4:
                lines.append([cls, flat])
    lines.sort()
    cell = meta.get("cell") or [0, 0]
    return {"cell": "%d_%d" % (cell[0], cell[1]), "lines": lines}


def block_of(cell):
    """The 5 degree block ("R_C") of cell "ROW_COL", as the bake workflow's releases group them."""
    row, col = (int(v) for v in cell.split("_"))
    return "%d_%d" % (row // 20, col // 20)


def merge_block(path, sketches):
    """Puts `sketches` (cell sketches, all of path's block) into the block file at `path`; returns its hash."""
    block = {"format": 1, "cells": {}}
    if os.path.exists(path):
        with open(path) as f:
            block = json.load(f)
    for s in sketches:
        if "lines" in s:
            block["cells"][s["cell"]] = s["lines"]
        if "land" in s:
            block.setdefault("land", {})[s["cell"]] = s["land"]
    block["cells"] = dict(sorted(block["cells"].items()))
    if "land" in block:
        block["land"] = dict(sorted(block["land"].items()))
    text = json.dumps(block, separators=(",", ":"))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(text + "\n")
    return hashlib.sha1(text.encode()).hexdigest()[:12]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cell_dir", nargs="?")
    ap.add_argument("--out")
    ap.add_argument("--coast", help="the cell's coast (coast_bake.py), put in as its \"land\"")
    ap.add_argument("--block", nargs="+", metavar=("OUT", "SKETCH"), help="merge cell sketches into a block's file")
    args = ap.parse_args(argv)
    if args.block:
        out, files = args.block[0], args.block[1:]
        sketches = []
        for path in files:
            with open(path) as f:
                sketches.append(json.load(f))
        print(merge_block(out, sketches))
        return 0
    if not args.cell_dir:
        ap.error("a cell's folder, or --block")
    sketch = cell_sketch(args.cell_dir)
    if args.coast:
        with open(args.coast) as f:
            sketch["land"] = json.load(f)["land"]
    text = json.dumps(sketch, separators=(",", ":"))
    if args.out:
        with open(args.out, "w") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
