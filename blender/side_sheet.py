"""Renders a side-on contact sheet of one kind of part, old glbs against new: a column for each
part, a row for the old one (from another folder, a copy of main's), the new one, and the new one
with its shape keys set. Rig built bodywork (H3), so the tanks' tunnels, the seats and the tails
are judged before they go on a bike. A tank is drawn with a 50 mm backbone through its tunnel.

    python3 blender/side_sheet.py OUT.png KIND_FOLDER OLD_ROOT [key=weight ...]

KIND_FOLDER is under assets/bike_parts (e.g. tank); OLD_ROOT holds the old glbs at the same paths.
Each `key=weight` sets that shape key on the third row."""

import glob
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(HERE), "assets", "bike_parts")
sys.path.insert(0, os.path.join(HERE, "lib"))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import kit  # noqa: E402

GAP_Y = 1.25    # m between the columns (along the bike, side on)
GAP_Z = 0.5     # m between the rows


def load(path):
    """Imports a glb's lod0, or None."""
    if not os.path.exists(path):
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    keep = None
    for ob in set(bpy.data.objects) - before:
        if ob.type == "MESH" and ob.name.startswith("lod0"):
            keep = ob
    for ob in set(bpy.data.objects) - before:
        if ob is not keep:
            bpy.data.objects.remove(ob)
    return keep


def label(text, at, size=0.045):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new("label", cu)
    ob.location = at
    ob.rotation_euler = (math.radians(90), 0.0, math.radians(90))
    ob.data.materials.append(kit.tag_material("black_metal"))
    bpy.context.scene.collection.objects.link(ob)


def place(ob, y, z):
    ob.parent = None
    ob.location = (0.0, y, z)


def main():
    out, folder, old_root = sys.argv[1], sys.argv[2], sys.argv[3]
    weights = dict((a.split("=")[0], float(a.split("=")[1])) for a in sys.argv[4:])
    paths = sorted(glob.glob(os.path.join(ASSETS, folder, "*.glb")))
    only = os.environ.get("SHEET_ONLY", "")
    if only:
        paths = [p for p in paths if os.path.splitext(os.path.basename(p))[0] in only.split(",")]
    kit.reset()
    n = len(paths)
    tank = folder.startswith("tank")
    for c, path in enumerate(paths):
        rel = os.path.relpath(path, ASSETS)
        y = -c * GAP_Y
        # (The glbs run back along -Y from their origin: each column's middle at its y.)
        old = load(os.path.join(old_root, rel))
        if old:
            place(old, y + 0.5, 0.0)
        new = load(path)
        place(new, y + 0.5, -GAP_Z)
        keyed = load(path)
        place(keyed, y + 0.5, -2 * GAP_Z)
        if keyed.data.shape_keys:
            for kb in keyed.data.shape_keys.key_blocks:
                kb.value = weights.get(kb.name, 0.0)
        if tank:
            for z in (-GAP_Z, -2 * GAP_Z):
                tube = kit.tube("spine", (0.0, y + 0.75, z - 0.025), (0.0, y - 0.75, z - 0.025), 0.025, 16, "powder")
                tube.parent = None
        label(os.path.splitext(os.path.basename(rel))[0].replace("_", " "), (0.4, y, 0.32))
    rows = ["main today", "rig built", "rig built, keys set"]
    for k, text in enumerate(rows):
        label(text, (0.4, 0.95, 0.1 - k * GAP_Z), 0.04)
    sc = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=60, location=(-0.5, 0.0, 0.0), rotation=(0.0, math.radians(90), 0.0))
    bpy.context.object.data.materials.append(kit.tag_material("paint_2"))
    mid = Vector((0.0, -(n - 1) * GAP_Y * 0.5 + 0.2, -GAP_Z))
    bpy.ops.object.camera_add(location=mid + Vector((3.0, 0.0, 0.0)))
    cam = bpy.context.object
    cam.rotation_euler = (Vector((-1.0, 0.0, 0.0))).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = n * GAP_Y + 0.6
    sc.camera = cam
    for at, energy in (((2.0, 1.0, 1.5), 400), ((2.0, -3.0, -1.0), 150)):
        bpy.ops.object.light_add(type="AREA", location=at)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = 4.0
        light.rotation_euler = (Vector(mid) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.62, 0.65, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("SHEET_SAMPLES", "24"))
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = False
    sc.render.resolution_x = 230 * n + 120
    sc.render.resolution_y = int(sc.render.resolution_x * (3 * GAP_Z + 0.4) / (n * GAP_Y + 0.6))
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
