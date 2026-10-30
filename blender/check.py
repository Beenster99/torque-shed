"""Checks every Blender part's glb (assets/bike_parts) against the parts agreement: three LODs,
each inside its kind's triangle budget; every face carrying a surface tag; UVs on lod0 and lod1;
and every mount point its kind needs. Prints a line per part and exits 1 when anything is wrong.

    python3 blender/check.py"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(HERE), "assets", "bike_parts")
sys.path.insert(0, os.path.join(HERE, "lib"))

import bpy  # noqa: E402

import kit  # noqa: E402


def check_part(path):
    """What's wrong with one glb, and its LODs' triangle counts."""
    bad = []
    kind = os.path.relpath(path, ASSETS).split(os.sep)[0]
    kit.reset()
    bpy.ops.import_scene.gltf(filepath=path)
    cap = kit.budget(kind)
    counts = []
    for lod in range(3):
        ob = bpy.data.objects.get("lod%d" % lod)
        if ob is None or ob.type != "MESH":
            bad.append("lod%d missing" % lod)
            continue
        n = kit.tris(ob)
        counts.append(n)
        if n > cap[lod]:
            bad.append("lod%d has %d triangles, over the %s cap of %d" % (lod, n, kind, cap[lod]))
        # (Blender names a second "cast_alloy" it meets "cast_alloy.001": the tag is the name before the dot.)
        # (A "__<slot>" ending names the part the colour comes from: the tag is before it.)
        tags = [s.material.name.split(".")[0].split("__")[0] if s.material else "" for s in ob.material_slots]
        untagged = sum(1 for p in ob.data.polygons if p.material_index >= len(tags) or tags[p.material_index] not in kit.TAGS)
        if untagged:
            bad.append("lod%d has %d faces without a surface tag (materials %s)" % (lod, untagged, tags))
        if lod < 2 and not ob.data.uv_layers:
            bad.append("lod%d has no UVs" % lod)
    mounts = {o.name.split(".")[0][len("mount_"):] for o in bpy.data.objects if o.type == "EMPTY" and o.name.startswith("mount_")}
    for need in kit.MOUNTS.get(kind, []):
        if need.endswith("_N"):
            stem = need[:-1]
            n = len([m for m in mounts if re.fullmatch(stem + r"\d+", m)])
            cyls = len([m for m in mounts if re.fullmatch(r"cyl_\d+", m)])
            if n == 0 or (kind == "head" and n != cyls):
                bad.append("mount points %s1.. missing (%d of %d)" % (stem, n, cyls))
        elif need not in mounts:
            bad.append("mount point %s missing" % need)
    return bad, counts


def main():
    paths = sorted(glob.glob(os.path.join(ASSETS, "**", "*.glb"), recursive=True))
    failed = 0
    for path in paths:
        bad, counts = check_part(path)
        print("%-6s %-44s tris %s" % ("FAIL" if bad else "ok", os.path.relpath(path, ASSETS), counts))
        for b in bad:
            print("         " + b)
        failed += 1 if bad else 0
    print("%d parts, %d failed" % (len(paths), failed))
    sys.exit(1 if failed or not paths else 0)


if __name__ == "__main__":
    main()
