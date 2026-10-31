"""The shared kit every part script builds with: the surface tags, a few solid shapes, mount
points, UVs, and the export that writes a part's three LODs to one glb. It follows the parts
agreement (/mnt/project-files/torque-shed/bike-look/parts-agreement.md).

Blender's axes here are the bike's: X right, Y forward, Z up, in metres. The glTF export ("+Y up")
lands that in Godot as BikeModel's own space (X right, Y up, -Z forward)."""

import math

import bpy  # (first: bmesh and mathutils come with it)
import bmesh
from mathutils import Matrix, Vector

# The surface tags (agreement 2): a face's tag is its material's name, and the game's bike shader
# reads it. Anything else fails blender/check.py.
TAGS = [
    "paint", "paint_2", "powder", "chrome", "polished_alloy", "cast_alloy", "brushed_steel", "raw_steel",
    "black_metal", "anodised", "titanium", "carbon", "rubber", "plastic", "plastic_paint", "leather", "fabric",
    "glass", "lens_white", "lens_amber", "lens_red", "dial", "decal",
]

# How the tags are drawn on the contact sheet (colour, metallic, roughness). The game ignores these.
PREVIEW = {
    "paint": ((0.5, 0.06, 0.05), 0.0, 0.3),
    "paint_2": ((0.85, 0.82, 0.75), 0.0, 0.3),
    "powder": ((0.08, 0.08, 0.09), 0.0, 0.55),
    "chrome": ((0.95, 0.95, 0.96), 1.0, 0.04),
    "polished_alloy": ((0.88, 0.88, 0.86), 1.0, 0.12),
    "cast_alloy": ((0.6, 0.6, 0.58), 0.85, 0.48),
    "brushed_steel": ((0.75, 0.75, 0.74), 1.0, 0.28),
    "raw_steel": ((0.45, 0.45, 0.46), 1.0, 0.4),
    "black_metal": ((0.035, 0.035, 0.04), 0.5, 0.55),
    "anodised": ((0.1, 0.25, 0.7), 0.9, 0.3),
    "titanium": ((0.55, 0.53, 0.5), 1.0, 0.3),
    "carbon": ((0.03, 0.03, 0.03), 0.0, 0.2),
    "rubber": ((0.02, 0.02, 0.02), 0.0, 0.85),
    "plastic": ((0.04, 0.04, 0.045), 0.0, 0.6),
    "plastic_paint": ((0.9, 0.5, 0.05), 0.0, 0.4),
    "leather": ((0.1, 0.06, 0.035), 0.0, 0.6),
    "fabric": ((0.12, 0.12, 0.12), 0.0, 0.9),
    "glass": ((0.8, 0.85, 0.9), 0.0, 0.05),
    "lens_white": ((1.0, 0.97, 0.9), 0.0, 0.1),
    "lens_amber": ((1.0, 0.55, 0.05), 0.0, 0.1),
    "lens_red": ((0.8, 0.03, 0.02), 0.0, 0.1),
    "dial": ((0.02, 0.02, 0.02), 0.0, 0.3),
    "decal": ((0.9, 0.9, 0.9), 0.0, 0.4),
}

# Triangle caps per LOD by part kind (agreement 5); a kind not listed is a small part.
BUDGETS = {
    "frame": [14000, 3500, 500], "engine": [16000, 4000, 500], "head": [16000, 4000, 400],
    "exhaust": [8000, 2000, 250], "fairing": [14000, 3500, 500], "tank": [8000, 2000, 250],
    # (A tyre glb is one of the 32 sections the game bends round the hoop: 1/32 of a tyre's 8000.)
    "wheel": [10000, 2500, 250], "tyre": [250, 62, 8], "fork": [8000, 2000, 200],
    "swingarm": [5000, 1200, 150], "saddle": [4000, 1000, 150], "tail": [4000, 1000, 150],
    "shock": [4000, 1000, 100], "disc": [4000, 1000, 100], "caliper": [4000, 1000, 100], "pads": [4000, 1000, 100],
    "handlebars": [4000, 1000, 100], "dashboard": [4000, 1000, 100], "headlight": [4000, 1000, 100],
    "panniers": [4000, 1000, 100], "top_box": [4000, 1000, 100],
    # (A guard glb is a cross-section the game bends round a short stretch of the guard: one plate's.)
    "guard": [400, 400, 400], "side_panels": [3000, 800, 100],
    # (A fairing edge glb is the section the game runs round one stretch of a fairing's edge.)
    "fairing_edge": [100, 60, 20], "fastener": [240, 100, 50],
    # (A weld glb is one bead round one tube end; a frame fitting a small bolted-on piece.)
    "weld": [600, 150, 40], "frame_fitting": [1500, 400, 120],
    # (A controls glb is one lever, grip, switch block, clamp or footrest piece.)
    "controls": [1500, 400, 120],
    # (Indicators, rear lights, the clocks' housings and mirror heads: small lamps and shells.)
    "indicator": [1500, 400, 60], "tail_light": [1500, 400, 80], "mirror": [1500, 400, 60],
    # (A sprocket, a strip of chain, a stand's foot or pivot, a horn.)
    "final_drive": [3000, 800, 60], "chain": [1500, 400, 40], "stand": [1500, 400, 40], "horn": [1500, 400, 60],
    # (A pannier or top box, a fog lamp, a radiator, a steering damper.)
    "luggage": [6000, 1500, 150], "fog": [1500, 400, 60], "radiator": [4000, 1000, 100], "damper": [1500, 400, 40],
    # (An air or oil filter or airbox, the ECU, a number board, a piece of the adventure kit.)
    "filter": [3000, 800, 60], "ecu": [1500, 400, 40], "number_board": [1500, 400, 40], "kit": [4000, 1000, 100],
}
SMALL_BUDGET = [1500, 400, 0]

# The mount points every glb of a kind must carry (agreement 4, and N = 1 .. the cylinders), by
# the folder under assets/bike_parts (the longest that matches).
MOUNTS = {
    "head": ["cyl_N", "exhaust_port_N", "plug_N", "intake_N"],
    "engine": ["engine"],
    "exhaust/can": ["inlet", "outlet"],
    "exhaust/fitting": ["exhaust_port"],
    "wheel": ["axle"],
    "shock": ["top", "bottom"],
}


def mounts_for(rel):
    """The mounts a glb at `rel` (under assets/bike_parts, with "/") must carry."""
    best = ""
    for folder in MOUNTS:
        if (rel + "/").startswith(folder + "/") and len(folder) > len(best):
            best = folder
    return MOUNTS.get(best, [])


def budget(kind):
    return BUDGETS.get(kind, SMALL_BUDGET)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tag_material(tag):
    """The material for surface `tag`. A tag can end in "__<slot>" to take its colour from that
    slot's part (barrels in a head glb are "cast_alloy__engine"), agreement v5."""
    assert tag.split("__")[0] in TAGS, tag
    m = bpy.data.materials.get(tag)
    if m is None:
        m = bpy.data.materials.new(tag)
        m.use_nodes = True
        col, metal, rough = PREVIEW[tag.split("__")[0]]
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*col, 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
    return m


def _new_object(name, bm, tag):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(tag_material(tag))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _bevel_hard_edges(bm, width, segs):
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(50)]
    bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segs, affect="EDGES", profile=0.5, clamp_overlap=True)


def rounded_rect(hx, hy, r, segs):
    """A rounded rectangle's outline (half sizes hx, hy, corner radius r), anticlockwise."""
    r = min(r, hx, hy)
    pts = []
    for cx, cy, a0 in ((hx - r, hy - r, 0.0), (-hx + r, hy - r, 0.5 * math.pi), (-hx + r, -hy + r, math.pi), (hx - r, -hy + r, 1.5 * math.pi)):
        for k in range(segs + 1):
            a = a0 + 0.5 * math.pi * k / segs
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def prism(name, outline, z0, z1, tag, bevel=0.0, bevel_segs=1, plane="XY", at=(0.0, 0.0, 0.0)):
    """A solid made by pushing a closed outline from z0 to z1: along Z for plane "XY", or along X
    for "YZ" (the outline's (u, v) then being (y, z)), its hard edges rounded by `bevel`."""
    bm = bmesh.new()

    def p(u, v, w):
        if plane == "YZ":
            return (at[0] + w, at[1] + u, at[2] + v)
        return (at[0] + u, at[1] + v, at[2] + w)
    lo = [bm.verts.new(p(u, v, z0)) for u, v in outline]
    hi = [bm.verts.new(p(u, v, z1)) for u, v in outline]
    n = len(outline)
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0.0:
        _bevel_hard_edges(bm, bevel, bevel_segs)
    return _new_object(name, bm, tag)


def tube(name, a, b, r, segs, tag, bevel=0.0, r_end=None):
    """A capped cylinder from point a to point b (radius r, or tapering to r_end)."""
    bm = bmesh.new()
    ax = Vector(b) - Vector(a)
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r_end is None else r_end, depth=ax.length)
    if bevel > 0.0:
        _bevel_hard_edges(bm, bevel, 1)
    ob = _new_object(name, bm, tag)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(ax.normalized())
    ob.location = (Vector(a) + Vector(b)) * 0.5
    return ob


def hex_nut(name, at, normal, r, h, tag="raw_steel"):
    return tube(name, at, Vector(at) + Vector(normal) * h, r, 6, tag)


def box_uvs(me):
    """UV map 1 at 1 unit = 1 m (agreement 3): each face projected flat along its main axis."""
    bm = bmesh.new()
    bm.from_mesh(me)
    # (Caps with more than four corners are cut into triangles, so the export can work out tangents.)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY", ngon_method="BEAUTY")
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        a = max(range(3), key=lambda i: abs(n[i]))
        u, v = [(1, 2), (0, 2), (0, 1)][a]
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co[u], co[v])
    bm.to_mesh(me)
    bm.free()


def join(objs, name, offset=(0.0, 0.0, 0.0)):
    """Joins pieces into one object with every transform applied, moved by `offset` (to put the
    glb's origin on its primary mount), smooth shaded with its sharp edges marked and UV'd."""
    for ob in objs:
        ob.data.transform(ob.matrix_basis)
        ob.matrix_basis.identity()
    ctx = {"active_object": objs[0], "selected_editable_objects": objs, "selected_objects": objs}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.join()
    ob = objs[0]
    ob.name = name
    me = ob.data
    me.name = name
    me.transform(Matrix.Translation(Vector(offset)))
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(38))
    box_uvs(me)
    return ob


def tris(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def export(path, lods, mounts):
    """Writes a part's LOD meshes and mount points to one glb (agreement 3): a root with children
    `lod0`, `lod1`, `lod2` and `mount_<name>` empties. `mounts` maps a name to (where, which way
    its +Z points)."""
    root = bpy.data.objects.new("part", None)
    bpy.context.scene.collection.objects.link(root)
    for k, ob in enumerate(lods):
        ob.name = "lod%d" % k
        ob.data.name = ob.name
        ob.parent = root
    for name, (loc, axis) in mounts.items():
        e = bpy.data.objects.new("mount_" + name, None)
        e.empty_display_type = "ARROWS"
        e.empty_display_size = 0.02
        e.location = loc
        e.rotation_mode = "QUATERNION"
        e.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(Vector(axis).normalized())
        bpy.context.scene.collection.objects.link(e)
        e.parent = root
    keep = {root} | set(root.children)
    for ob in list(bpy.context.scene.objects):
        ob.select_set(ob in keep)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_extras=False, export_materials="EXPORT", export_image_format="NONE",
        export_tangents=True, export_texcoords=True, export_normals=True)


def superellipse(hw, up, down, n, segs):
    """A rounded-box cross-section in the XZ plane (half width hw, `up` above and `down` below, n
    the squareness: 2 is an ellipse, higher is boxier), anticlockwise from +X."""
    pts = []
    for k in range(segs):
        t = 2.0 * math.pi * k / segs
        c, s = math.cos(t), math.sin(t)
        x = hw * math.copysign(abs(c) ** (2.0 / n), c)
        z = (up if s > 0 else down) * math.copysign(abs(s) ** (2.0 / n), s)
        pts.append((x, z))
    return pts


def loft(name, sections, segs, tag, at=(0.0, 0.0, 0.0), caps=True):
    """A closed solid lofted through cross-sections along Y: each (y, half width, up, down, n), as
    BikeModel's _shell draws its crankcases. Without `caps` its ends are left open (a section of
    pipe the game lays end to end)."""
    bm = bmesh.new()
    rings = []
    for y, hw, up, down, n in sections:
        rings.append([bm.verts.new((at[0] + x, at[1] + y, at[2] + z)) for x, z in superellipse(hw, up, down, n, segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if caps:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    else:
        # (No caps to tell the inside from: the faces point out from the axis.)
        for f in bm.faces:
            c = f.calc_center_median()
            if f.normal.dot(Vector((c.x - at[0], 0.0, c.z - at[2]))) < 0.0:
                f.normal_flip()
    return _new_object(name, bm, tag)


def ring(name, y, r, thick, segs, tag, minor=6):
    """A torus round the Y axis at `y` (a clamp band or an end cap's rolled edge): `r` to the
    middle of its tube, `thick` the tube's radius."""
    bm = bmesh.new()
    rows = []
    for i in range(segs):
        t = 2.0 * math.pi * i / segs
        rows.append([bm.verts.new(((r + thick * math.cos(u)) * math.cos(t), y + thick * math.sin(u), (r + thick * math.cos(u)) * math.sin(t)))
            for u in (2.0 * math.pi * j / minor for j in range(minor))])
    for i in range(segs):
        a, b = rows[i], rows[(i + 1) % segs]
        for j in range(minor):
            k = (j + 1) % minor
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_object(name, bm, tag)


def sphere(name, at, r, scale, segs, tag, rot_x=0.0):
    """A ball of radius `r` stretched by `scale`, turned `rot_x` about X: lofted ring by ring along
    Y, its ends closed flat on small rings (a UV sphere's poles didn't export the same normals
    twice running, and CI rebuilds every glb to the byte)."""
    sx, sy, sz = scale
    rings = max(4, segs // 2)
    secs = []
    for i in range(rings + 1):
        a = math.pi * (0.04 + 0.92 * i / rings)
        secs.append((-math.cos(a) * r * sy, math.sin(a) * r * sx, math.sin(a) * r * sz, math.sin(a) * r * sz, 2.0))
    ob = loft(name, secs, segs, tag)
    ob.rotation_euler = (rot_x, 0.0, 0.0)
    ob.location = at
    return ob


def revolve(name, profile, segs, tag, closed=True):
    """A solid turned round the X axis (an axle's): `profile` is its outline as (x along the
    axle, radius) points, closed back to the first unless `closed` is False (a lip left open)."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        t = 2.0 * math.pi * i / segs
        rings.append([bm.verts.new((x, r * math.cos(t), r * math.sin(t))) for x, r in profile])
    n = len(profile)
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % segs]
        for j in range(n if closed else n - 1):
            k = (j + 1) % n
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_object(name, bm, tag)


def sweep(name, points, radii, segs, tag, squash=1.0, caps=True, side=None):
    """A tube along `points` (a spoke, a rail), `radii` one per point or one for all, its section
    stretched by `squash` along its `side` axis (by default level and square to the tube). The
    frames are carried along without twisting."""
    pts = [Vector(p) for p in points]
    rs = radii if isinstance(radii, (list, tuple)) else [radii] * len(pts)
    t0 = (pts[1] - pts[0]).normalized()
    side = Vector(side) if side is not None else t0.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 0.01:
        side = t0.cross(Vector((1.0, 0.0, 0.0)))
    side.normalize()
    bm = bmesh.new()
    rings = []
    prev = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if prev is not None:
            axis = prev.cross(t)
            if axis.length > 1e-6:
                side.rotate(Matrix.Rotation(prev.angle(t), 3, axis.normalized()))
        side = (side - t * side.dot(t)).normalized()
        up = t.cross(side).normalized()
        prev = t
        rings.append([bm.verts.new(p + side * (math.cos(2.0 * math.pi * j / segs) * rs[i] * squash) + up * (math.sin(2.0 * math.pi * j / segs) * rs[i]))
            for j in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for j in range(segs):
            k = (j + 1) % segs
            bm.faces.new((a[j], a[k], b[k], b[j]))
    if caps:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_object(name, bm, tag)


def skin(name, rings, tag, caps=True, closed=True):
    """A solid through `rings` of points (each the same count, in order round the part): quads
    between neighbouring rings, each ring closed round on itself unless not `closed`, and the two
    end rings capped. Normals point out."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(vs[0])
    for a, b in zip(vs, vs[1:]):
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if caps:
        bm.faces.new(vs[0])
        bm.faces.new(list(reversed(vs[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_object(name, bm, tag)


def sharp_along(ob, axis=1):
    """Marks every edge of `ob` that runs some way along `axis` (Y by default) sharp, and the
    rest left as join set them: a shell folded from flat panels, creased at every fold."""
    me = ob.data
    attr = me.attributes.get("sharp_edge") or me.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
    for e in me.edges:
        a, b = me.vertices[e.vertices[0]].co, me.vertices[e.vertices[1]].co
        if abs(a[axis] - b[axis]) > 1e-5:
            attr.data[e.index].value = True


def gd_const(name, script="scripts/bike_model.gd"):
    """A dictionary constant from the game's code (BikeModel's TANK_SHAPES, say), so a part
    script draws from the same numbers as the code it stands in for."""
    import json
    import os
    import re
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", script)
    with open(path) as f:
        text = f.read()
    start = text.index("const %s := {" % name) + len("const %s := " % name)
    depth = 0
    for i in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            body = text[start:i + 1]
            break
    body = "\n".join(line.split("#")[0] for line in body.split("\n"))
    body = re.sub(r",(\s*[}\]])", r"\1", body)
    return json.loads(body)


def cap(name, ring, tag, flip=False):
    """One flat face closing `ring` (an end of a skin left open), facing round its points'
    order, or the other way when `flip`."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in (reversed(ring) if flip else ring)]
    bm.faces.new(vs)
    return _new_object(name, bm, tag)


def weld(ob, dist=1e-6):
    """Merges `ob`'s pieces where they meet (skins and caps built apart) into one closed shell,
    its normals pointing out."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
