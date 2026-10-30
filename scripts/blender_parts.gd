class_name BlenderParts
extends RefCounted
## The bike parts made in Blender (blender/, exported to assets/bike_parts): finds the glb drawn
## for a part, and puts it where BikeModel lays that part out. A part with no glb is still drawn
## the old way, by BikeModel's own code. The glbs follow the parts agreement (bike look overhaul):
## meshes `lod0`, `lod1` and `lod2`, mount points as `mount_<name>` nodes, and each surface's
## material named for its surface tag (the bike shader reads it).

const ROOT := "res://assets/bike_parts/"
## The surface tags a part's materials are named for (blender/lib/kit.py has the same list).
const TAGS: Array[String] = ["paint", "paint_2", "powder", "chrome", "polished_alloy", "cast_alloy", "brushed_steel", "raw_steel",
	"black_metal", "anodised", "titanium", "carbon", "rubber", "plastic", "plastic_paint", "leather", "fabric",
	"glass", "lens_white", "lens_amber", "lens_red", "dial", "decal"]
## How far off (m) a bike draws its lod1 and its lod2 (the parts agreement's 30 m and 120 m).
const LOD1_AT := 30.0
const LOD2_AT := 120.0
## The reference top end's spacing between bores (m): a 700 cc's, as BikeModel lays it out.
const TOP_END_SPACING := 0.12

static var _loaded := {}    # path -> {"lods": [Mesh x3], "mounts": {name: Transform3D}}, or {} when there's no glb


## Where the glb for a part of `kind` lives. A top end (kind "head") depends on the engine's
## layout as well as the head part, so it's under the layout.
static func path_for(kind: String, part_id: String, layout := "") -> String:
	if kind == "head":
		return ROOT + "head/%s/%s.glb" % [layout, part_id]
	return ROOT + "%s/%s.glb" % [kind, part_id]


## A part's meshes and mount points from its glb ({} when there's none), loaded once.
static func part(path: String) -> Dictionary:
	if _loaded.has(path):
		return _loaded[path]
	var out := {}
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		var lods := []
		for k in 3:
			var mi := scene.find_child("lod%d" % k, true, false) as MeshInstance3D
			lods.append(mi.mesh if mi != null else null)
		var mounts := {}
		for n in scene.find_children("mount_*", "Node3D", true, false):
			mounts[str(n.name).trim_prefix("mount_")] = _in(scene, n as Node3D)
		if lods[0] != null:
			out = {"lods": lods, "mounts": mounts}
		scene.free()
	_loaded[path] = out
	return out


## Where `n` sits in `root`'s space (the scene isn't in the tree, so no global transforms).
static func _in(root: Node, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != root and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## The surface tag a part's material carries (its name, less any ".001" Blender added and any
## "__<slot>" ending).
static func tag_of(mat: Material) -> String:
	return "" if mat == null else mat.resource_name.get_slice(".", 0).get_slice("__", 0)


## The slot whose part a surface takes its colour from: the "__<slot>" ending of its material's
## name (a head glb's barrels are the engine's colour), or "" for the part's own.
static func colour_slot(mat: Material) -> String:
	var name := "" if mat == null else mat.resource_name.get_slice(".", 0)
	return name.get_slice("__", 1) if name.contains("__") else ""


## Where a top end goes: its origin on the first barrel's base, turned up the barrels, and scaled
## by the engine's size across and forward and by the barrels' height up (`cyls` as BikeModel's
## _cyls lays them out, their "up" as long as _head_k; `eng_s` is BikeModel's _eng_s). Across, it's
## scaled to the barrels' own spacing, which on a small engine shrunk into a cruiser's frame stays
## wider than its size alone would make it (the bores don't shrink with it).
static func top_end_xform(cyls: Array, eng_s: float) -> Transform3D:
	var up: Vector3 = cyls[0]["up"]
	var turn := Basis()
	var axis := Vector3.UP.cross(up)
	if axis.length() > 0.0001:
		turn = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	var across := eng_s
	if cyls.size() > 1:
		across = absf((cyls[cyls.size() - 1]["base"] as Vector3).x - (cyls[0]["base"] as Vector3).x) / (TOP_END_SPACING * (cyls.size() - 1))
	return Transform3D(turn * Basis.from_scale(Vector3(across, up.length(), eng_s)), cyls[0]["base"])


## Where an engine's crankcase goes: on the engine's middle (BikeModel's _engine_c), scaled by its
## size (_eng_s).
static func engine_xform(engine_c: Vector3, eng_s: float) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * eng_s), engine_c)


## The engine layouts whose top ends are drawn a cylinder at a time (a glb on each cylinder), where
## the rest are one glb for the whole row of bores.
const PER_CYLINDER: Array[String] = ["2stroke", "vtwin", "boxer"]
## The bore radius (m) each of those layouts' glbs is drawn for. BikeModel sizes a lone cylinder's
## barrel and head by its bore and its barrels' height (_bore_r, _head_k), so these scale the same
## way: by head_k x the bore over this, across and front to back, and by head_k up.
const PER_CYLINDER_BORE := {"2stroke": 0.045, "vtwin": 0.05, "boxer": 0.05}


## The top end's glbs for an engine `layout` with head part `head`, and where each goes, for the
## cylinders BikeModel lays out (`cyls`, `eng_s` as in top_end_xform, `bore_r` its _bore_r):
## [[path, Transform3D], ...]. Empty when the layout has no Blender top end for that head.
static func top_end_pieces(layout: String, head: String, cyls: Array, eng_s: float, bore_r: float) -> Array:
	if cyls.is_empty():
		return []
	if not layout in PER_CYLINDER:
		var path := path_for("head", head, layout)
		return [[path, top_end_xform(cyls, eng_s)]] if not part(path).is_empty() else []
	var out := []
	for i in cyls.size():
		# A cylinder can have a glb of its own (a V-twin's rear, a boxer's left), else they share one.
		var path := path_for("head", "%s_%d" % [head, i + 1], layout)
		if part(path).is_empty():
			path = path_for("head", head, layout)
		if part(path).is_empty():
			return []
		var up: Vector3 = cyls[i]["up"]
		var b := up.length() * bore_r / float(PER_CYLINDER_BORE[layout])
		var t := top_end_xform([cyls[i]], 1.0)
		out.append([path, Transform3D(t.basis * Basis.from_scale(Vector3(b, 1.0, b)), t.origin)])
	return out


## A node holding a part's three LODs, each shown over its own distances, and its mount points
## as Marker3Ds, placed at `xform`. Null when the part has no glb.
static func instance(path: String, xform: Transform3D) -> Node3D:
	var p := part(path)
	if p.is_empty():
		return null
	var root := Node3D.new()
	root.name = "BlenderPart"
	root.transform = xform
	var ranges := [[0.0, LOD1_AT], [LOD1_AT, LOD2_AT], [LOD2_AT, 0.0]]
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.name = "lod%d" % k
		mi.mesh = p["lods"][k]
		mi.visibility_range_begin = ranges[k][0]
		mi.visibility_range_end = ranges[k][1]
		root.add_child(mi)
	for m in p["mounts"]:
		var mk := Marker3D.new()
		mk.name = "mount_" + str(m)
		mk.transform = p["mounts"][m]
		root.add_child(mk)
	return root


## Every vertex of a part's `lod` mesh, in the space `xform` puts it in.
static func points(path: String, xform: Transform3D, lod := 0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var p := part(path)
	if p.is_empty():
		return out
	var mesh: Mesh = p["lods"][lod]
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(xform * v)
	return out
