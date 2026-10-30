"""Renders a contact sheet of the Blender parts from their glbs: a column for each part, a row for
each LOD.

    python3 blender/contact_sheet.py OUT.png [folder under assets/bike_parts, e.g. head/twin]"""

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

GAP_X = 0.36    # m between the columns
GAP_Z = 0.42    # m between the LOD rows


def load(path):
    """Imports a part's glb; returns its LOD objects by number."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    lods = {}
    for ob in set(bpy.data.objects) - before:
        if ob.type == "MESH" and ob.name.startswith("lod"):
            # (A second glb's come in as "lod0.001".)
            lods[int(ob.name[3])] = ob
        elif ob.type == "EMPTY" and ob.name.startswith("mount_"):
            ob.hide_render = True
    return lods


def label(text, at, size=0.02):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new("label", cu)
    ob.location = at
    ob.rotation_euler = (math.radians(90), 0.0, math.pi)
    ob.data.materials.append(kit.tag_material("black_metal"))
    bpy.context.scene.collection.objects.link(ob)


def aim(ob, target):
    ob.rotation_euler = (Vector(target) - ob.location).to_track_quat("-Z", "Y").to_euler()


def main():
    out = sys.argv[1]
    where = sys.argv[2] if len(sys.argv) > 2 else ""
    paths = sorted(glob.glob(os.path.join(ASSETS, where, "**", "*.glb"), recursive=True))
    kit.reset()
    sc = bpy.context.scene
    n = len(paths)
    parts = []
    for path in paths:
        lods = load(path)
        # A pipe section is drawn at radius 1 for the game to scale: shown here at a header's 3 cm.
        size = 0.03 if os.sep + "pipe" + os.sep in path else 1.0
        ys = [v.co.y * size for v in lods[0].data.vertices] if 0 in lods else [0.0]
        parts.append((path, lods, size, ys))
    # A long part (an exhaust can) lies side on across its column, the columns spread to fit.
    longest = max(max(ys) - min(ys) for _, _, _, ys in parts)
    gap = max(GAP_X, longest + 0.08)
    for c, (path, lods, size, ys) in enumerate(parts):
        x = ((n - 1) * 0.5 - c) * gap   # (seen from the front, so the first on the left)
        long = max(ys) - min(ys) > 0.3
        turn = math.radians(90 if long else 32)
        mid = Vector((0.0, (max(ys) + min(ys)) * 0.5, 0.0)) if long else Vector()
        for k, ob in lods.items():
            ob.parent = None
            ob.rotation_mode = "XYZ"
            ob.rotation_euler = (0.0, 0.0, turn)
            ob.scale = (size, size, size)
            shift = ob.rotation_euler.to_matrix() @ mid
            ob.location = Vector((x + (0.0 if long else 0.05), -0.03, -k * GAP_Z)) - shift
        label(os.path.splitext(os.path.relpath(path, ASSETS))[0].split(os.sep)[-1].replace("_", " "), (x, 0.12, 0.3))
    for k, text in enumerate(["lod0 near", "lod1 at 30 m", "lod2 far"]):
        label(text, ((n * 0.5) * gap + 0.04, 0.12, 0.05 - k * GAP_Z), 0.018)
    # A floor, a big soft key light and a fill, and a camera a little above and ahead (the
    # bike's front is +Y); each part turned to show its front and right side.
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0.0, 0.0, -2 * GAP_Z - 0.12))
    bpy.context.object.data.materials.append(kit.tag_material("cast_alloy"))
    target = (0.0, 0.0, -GAP_Z + 0.05)
    bpy.ops.object.camera_add(location=(0.0, 2.4, 0.75))
    cam = bpy.context.object
    aim(cam, target)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(n * gap + 0.3, 3 * GAP_Z * 1.5) * 1.02
    sc.camera = cam
    for at, energy, size in (((1.2, 1.6, 1.4), 90, 1.6), ((-1.5, 0.6, 0.8), 25, 2.0)):
        bpy.ops.object.light_add(type="AREA", location=at)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = size
        aim(light, (0.0, 0.0, -0.3))
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.27, 0.3, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("SHEET_SAMPLES", "40"))
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = False
    sc.render.resolution_x = 340 * n + 260
    sc.render.resolution_y = 1300
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
