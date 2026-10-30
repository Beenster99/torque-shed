"""Builds the Blender bike parts: runs each family script (blender/parts/<kind>/<family>.py) and
writes each part's glb, its three LODs and its mount points, to assets/bike_parts.

    python3 blender/build.py [family ...]

Needs Blender as a Python module (`pip install bpy`, Python 3.13). The export is the same byte for
byte each run, so CI rebuilds and checks the committed glbs match their scripts."""

import glob
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(HERE), "assets", "bike_parts")
sys.path.insert(0, os.path.join(HERE, "lib"))

import kit  # noqa: E402


def families():
    """Every family script, as {name: path}."""
    return {os.path.basename(p)[:-3]: p for p in sorted(glob.glob(os.path.join(HERE, "parts", "*", "*.py")))}


def load(path):
    spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_family(path):
    for part in load(path).parts():
        kit.reset()
        lods = [part["build"](lod) for lod in range(3)]
        out = os.path.join(ASSETS, part["path"])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        kit.export(out, lods, part["mounts"])
        print("%-44s tris %s" % (part["path"], [kit.tris(ob) for ob in lods]))


def main():
    have = families()
    want = [a for a in sys.argv[1:] if not a.startswith("-")] or list(have)
    for name in want:
        build_family(have[name])


if __name__ == "__main__":
    main()
