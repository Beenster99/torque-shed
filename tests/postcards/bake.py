#!/usr/bin/env python3
"""The postcards' own copy of the world: the one cell each place (places.json) is in, with its streams, trees and sketch
(coast, bridges and tunnels), kept in tests/postcards/world/ in the layout CellStore keeps the world's store in, so the
rig (postcards.gd) reads it offline and the postcards only change when the game does.

    python3 tests/postcards/bake.py [--cache DIR] [--only dales,atlas]

A cell the world's store (Beenster99/torque-shed-world) has is copied from there; one it hasn't is baked here with the
game's own tools, as the store's bake workflow does (tools/region_bake.py --cell, coast_bake, span_bake, sketch_bake,
stream_bake, tree_bake). A cell already in world/ is left alone (delete its folder to bake it again); its profile comes from the store when the
store has one (profile/cROW_COL.json). The heights come
after, from the rig itself: postcards.sh --fetch.

Needs numpy, Pillow and pyarrow for a bake. Downloads are kept under --cache (the project's shared folder by default)."""
import argparse
import glob
import hashlib
import io
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
WORLD = os.path.join(HERE, "world")
STORE = "https://raw.githubusercontent.com/Beenster99/torque-shed-world/main/"
CELL_DEG = 0.25
USER_AGENT = "TorqueShed postcards (+https://github.com/Beenster99/torque-shed)"
SHARED_CACHE = "/mnt/project-files/torque-shed/ride-anywhere-v2/cache/bake"


def cell_of(lat, lon):
    return math.floor((lat + 90.0) / CELL_DEG), math.floor((lon + 180.0) / CELL_DEG)


def middle(row, col):
    return (row + 0.5) * CELL_DEG - 90.0, (col + 0.5) * CELL_DEG - 180.0


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def text_hash(text):
    """The hash CellStore checks a kept file against: sha1 of its text without the last newline, 12 characters."""
    return hashlib.sha1(text.rstrip("\n").encode()).hexdigest()[:12]


def copy_from_store(cell, store, entries):
    """Cell "ROW_COL" from the world's store: its folder, and its streams, trees and sketch as bake entries."""
    e = store["cells"][cell]
    with zipfile.ZipFile(io.BytesIO(get(e["url"]))) as z:
        z.extractall(os.path.join(WORLD, "c" + cell))
    if cell in store.get("streams", {}):
        s = json.loads(get(STORE + "stream/c%s.json" % cell))
        write_json(os.path.join(entries, "c%s.streams" % cell), {"cell": cell, "streams": s["streams"]})
    if cell in store.get("trees", {}):
        write_json(os.path.join(entries, "c%s.trees" % cell), json.loads(get(STORE + "tree/c%s.json" % cell)))
    if cell in store.get("profiles", {}):
        # (the place profile, Place profiles' file of its own: interfaces/profile.md)
        put(os.path.join(WORLD, "profile", "c%s.json" % cell), json.loads(get(STORE + "profile/c%s.json" % cell)))
    row, col = (int(v) for v in cell.split("_"))
    block = "%d_%d" % (row // 20, col // 20)
    if block in store.get("sketches", {}):
        b = json.loads(get(STORE + "sketch/b%s.json" % block))
        s = {"cell": cell}
        if cell in b.get("cells", {}):
            s["lines"] = b["cells"][cell]
        for key in ("land", "spans"):
            if cell in b.get(key, {}):
                s[key] = b[key][cell]
        write_json(os.path.join(entries, "c%s.sketch" % cell), s)


def bake_here(cell, release, cache, entries):
    """Cell "ROW_COL" baked with the game's tools, as the store's bake workflow does."""
    row, col = (int(v) for v in cell.split("_"))
    lat, lon = middle(row, col)
    tools = os.path.join(GAME, "tools")
    py = sys.executable
    rel = ["--release", release] if release else []
    out = os.path.join(WORLD, "c" + cell)
    subprocess.run([py, os.path.join(tools, "region_bake.py"), "--cell", str(lat), str(lon), "--out", out,
                    "--cache", cache] + rel, check=True)
    with tempfile.TemporaryDirectory() as tmp:
        extra = []
        for tool, flag in (("coast_bake.py", "--coast"), ("span_bake.py", "--spans")):
            path = os.path.join(tmp, flag.strip("-") + ".json")
            if subprocess.run([py, os.path.join(tools, tool), str(lat), str(lon), "--out", path] + rel).returncode == 0:
                extra += [flag, path]
        subprocess.run([py, os.path.join(tools, "sketch_bake.py"), out] + extra
                       + ["--out", os.path.join(entries, "c%s.sketch" % cell)], check=True)
    subprocess.run([py, os.path.join(tools, "stream_bake.py"), str(lat), str(lon), "--out",
                    os.path.join(entries, "c%s.streams" % cell)] + rel)
    subprocess.run([py, os.path.join(tools, "tree_bake.py"), str(lat), str(lon), "--cache", os.path.join(cache, "canopy"),
                    "--out", os.path.join(entries, "c%s.trees" % cell)] + rel)


def write_json(path, v):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(v, f, separators=(",", ":"))


def write_index(release):
    """world/index.json naming every cell here and the hash of its streams, trees and sketch block, as CellStore reads."""
    index = {"format": 1, "release": release, "cells": {}, "sketches": {}, "streams": {}, "trees": {}, "profiles": {}}
    for d in sorted(glob.glob(os.path.join(WORLD, "c*_*"))):
        if os.path.exists(os.path.join(d, "region.json")):
            with open(os.path.join(d, "region.json")) as f:
                index["cells"][os.path.basename(d)[1:]] = {"hash": json.load(f).get("hash", "")}
    for key, folder in (("streams", "stream"), ("trees", "tree"), ("profiles", "profile")):
        for p in sorted(glob.glob(os.path.join(WORLD, folder, "c*.json"))):
            with open(p) as f:
                index[key][os.path.basename(p)[1:-5]] = text_hash(f.read())
    for p in sorted(glob.glob(os.path.join(WORLD, "sketch", "b*.json"))):
        with open(p) as f:
            index["sketches"][os.path.basename(p)[1:-5]] = text_hash(f.read())
    with open(os.path.join(WORLD, "index.json"), "w") as f:
        json.dump(index, f, indent=1)
        f.write("\n")


def merge(entries):
    """The bake entries' streams, trees and sketches into world/'s files, as the store's scripts/index.py does."""
    for p in sorted(glob.glob(os.path.join(entries, "*.streams"))):
        with open(p) as f:
            s = json.load(f)
        put(os.path.join(WORLD, "stream", "c%s.json" % s["cell"]), {"streams": s["streams"]})
    for p in sorted(glob.glob(os.path.join(entries, "*.trees"))):
        with open(p) as f:
            s = json.load(f)
        put(os.path.join(WORLD, "tree", "c%s.json" % s["cell"]), s)
    for p in sorted(glob.glob(os.path.join(entries, "*.sketch"))):
        with open(p) as f:
            s = json.load(f)
        row, col = (int(v) for v in s["cell"].split("_"))
        path = os.path.join(WORLD, "sketch", "b%d_%d.json" % (row // 20, col // 20))
        data = {"format": 1, "cells": {}}
        if os.path.exists(path):
            with open(path) as f:
                data = json.load(f)
        if "lines" in s:
            data["cells"][s["cell"]] = s["lines"]
        for key in ("land", "spans"):
            if key in s:
                data.setdefault(key, {})[s["cell"]] = s[key]
        put(path, data)


def put(path, v):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(json.dumps(v, separators=(",", ":")) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--cache", default=SHARED_CACHE if os.path.isdir(os.path.dirname(SHARED_CACHE))
                    else os.path.expanduser("~/.cache/torque-shed-bake"))
    ap.add_argument("--only", default="", help="place ids, comma-separated")
    args = ap.parse_args(argv)
    with open(os.path.join(HERE, "places.json")) as f:
        places = json.load(f)["places"]
    only = [p for p in args.only.split(",") if p]
    store = json.loads(get(STORE + "index.json"))
    release = store["release"]
    with tempfile.TemporaryDirectory() as entries:
        for p in places:
            if only and p["id"] not in only:
                continue
            cell = "%d_%d" % cell_of(*p["from"])
            if os.path.exists(os.path.join(WORLD, "c" + cell, "region.json")):
                print("%s: c%s already here" % (p["id"], cell))
                if cell in store.get("profiles", {}):
                    put(os.path.join(WORLD, "profile", "c%s.json" % cell), json.loads(get(STORE + "profile/c%s.json" % cell)))
                continue
            e = store["cells"].get(cell)
            if isinstance(e, dict) and not e.get("empty"):
                print("%s: c%s from the world's store" % (p["id"], cell))
                copy_from_store(cell, store, entries)
            else:
                print("%s: baking c%s" % (p["id"], cell))
                bake_here(cell, release, args.cache, entries)
        merge(entries)
    write_index(release)


if __name__ == "__main__":
    sys.exit(main())
