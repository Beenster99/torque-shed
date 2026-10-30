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


## The reference exhaust can every can glb is drawn at (m): its length, inlet to end, and its
## biggest radius.
const CAN_LENGTH := 0.5
const CAN_RADIUS := 0.05


## The glb for an exhaust can of `shape` (the part's "can"), as BikeModel's _can draws it: a
## shape with no glb of its own is the round can, as BikeModel draws an unknown one.
static func can_path(shape: String) -> String:
	var path := ROOT + "exhaust/can/%s.glb" % shape
	return path if not part(path).is_empty() else ROOT + "exhaust/can/round.glb"


## The cans BikeModel draws one size whatever the radius it's asked for (a slash-cut pipe and an
## open one): drawn here at that size on the reference can, so they're never scaled across.
const FIXED_SIZE_CANS: Array[String] = ["slash", "open"]


## Where a can of `shape` goes: its inlet on `a`, stretched back to `b`, and scaled across by its
## biggest radius `r`, the reference can's "up" kept as near the bike's up as it'll go (BikeModel's
## _can takes the same). A can on the left is mirrored, so a turnout turns out to its own side.
static func can_xform(a: Vector3, b: Vector3, r: float, shape := "") -> Transform3D:
	if shape in FIXED_SIZE_CANS:
		r = CAN_RADIUS
	var dir := (b - a).normalized()
	var up := Vector3.UP - dir * dir.dot(Vector3.UP)
	if up.length() < 0.001:
		up = Vector3.BACK - dir * dir.dot(Vector3.BACK)
	up = up.normalized()
	var side := up.cross(dir) * (r / CAN_RADIUS)
	if a.x < 0.0:
		side = -side
	return Transform3D(Basis(side, up * (r / CAN_RADIUS), dir * (a.distance_to(b) / CAN_LENGTH)), a)


## Where the gas leaves a can at `xform` (BikeModel's _can returns it, for the exhaust's tip).
static func can_outlet(path: String, xform: Transform3D) -> Vector3:
	var p := part(path)
	return xform * (p["mounts"]["outlet"] as Transform3D).origin if not p.is_empty() else xform.origin


## A pipe (a header) along `route`, as BikeModel's _bend sweeps its own along ShapeKit.sweep's
## curve: copies of a Blender pipe section (`path`, drawn at radius 1 running along +Z) laid end to
## end, each stretched a little so a whole number of them fill the curve, and every ring bent onto
## it, turned with the curve's own frames (so the pipe doesn't twist round the bends) and scaled by
## `radius` (one number, or one per route point as _bend takes). One ArrayMesh per LOD; [] when
## there's no such glb.
static func sweep_section(path: String, route: Array, radius, per_seg := 6) -> Array:
	var p := part(path)
	var pts := ShapeKit.smooth(route, per_seg)
	if p.is_empty() or pts.size() < 2:
		return []
	var radii: Array = ShapeKit.smooth_floats(radius, per_seg) if radius is Array else [float(radius)]
	# The curve's frames, as ShapeKit.sweep turns them, and how far along it each point is.
	var count := pts.size()
	var tangents := []
	var sides := []
	var arc := [0.0]
	var t0: Vector3 = (pts[1] - pts[0]).normalized()
	var side := t0.cross(Vector3.UP)
	if side.length() < 0.01:
		side = t0.cross(Vector3.RIGHT)
	side = side.normalized()
	for i in count:
		var t: Vector3 = (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if i > 0:
			var prev_t: Vector3 = tangents[i - 1]
			var axis := prev_t.cross(t)
			if axis.length() > 0.00001:
				side = side.rotated(axis.normalized(), prev_t.angle_to(t))
			arc.append(float(arc[i - 1]) + (pts[i] as Vector3).distance_to(pts[i - 1]))
		side = (side - t * side.dot(t)).normalized()
		tangents.append(t)
		sides.append(side)
	var total: float = arc[count - 1]
	var out := []
	for lod in 3:
		var mesh: Mesh = p["lods"][lod]
		var am := ArrayMesh.new()
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
			var length := 0.0
			for v in verts:
				length = maxf(length, v.z)
			var copies := maxi(1, roundi(total / length))
			var stretch := total / (copies * length)
			var nv := PackedVector3Array()
			var nn := PackedVector3Array()
			var nuv := PackedVector2Array()
			var ni := PackedInt32Array()
			for c in copies:
				for j in verts.size():
					var v := verts[j]
					var d := (c * length + v.z) * stretch
					# The curve's point at d along, its frame lerped between the points either side.
					var i := arc.bsearch(d)
					i = clampi(i - 1, 0, count - 2)
					var f := clampf((d - float(arc[i])) / maxf(float(arc[i + 1]) - float(arc[i]), 0.000001), 0.0, 1.0)
					var at: Vector3 = (pts[i] as Vector3).lerp(pts[i + 1], f)
					var tan: Vector3 = (tangents[i] as Vector3).lerp(tangents[i + 1], f).normalized()
					var sd: Vector3 = (sides[i] as Vector3).lerp(sides[i + 1], f)
					sd = (sd - tan * sd.dot(tan)).normalized()
					var up := tan.cross(sd).normalized()
					var r := float(radii[0])
					if radii.size() > 1:
						var k := (i + f) / (count - 1) * (radii.size() - 1)
						r = lerpf(float(radii[floori(k)]), float(radii[mini(floori(k) + 1, radii.size() - 1)]), k - floorf(k))
					nv.append(at + sd * (v.x * r) + up * (v.y * r))
					var n := normals[j]
					nn.append((sd * n.x + up * n.y + tan * n.z).normalized())
					# (1 UV unit = 1 m, round the pipe and along it.)
					nuv.append(Vector2(atan2(v.y, v.x) * r, d))
				for k in idx:
					ni.append(k + c * verts.size())
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = nv
			arrays[Mesh.ARRAY_NORMAL] = nn
			arrays[Mesh.ARRAY_TEX_UV] = nuv
			arrays[Mesh.ARRAY_INDEX] = ni
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(am.get_surface_count() - 1, mesh.surface_get_material(s))
		out.append(am)
	return out


## A node showing a mesh per LOD (sweep_section's), each over its own distances, like instance's.
static func lod_node(lods: Array, name := "BlenderPipe") -> Node3D:
	var root := Node3D.new()
	root.name = name
	var ranges := [[0.0, LOD1_AT], [LOD1_AT, LOD2_AT], [LOD2_AT, 0.0]]
	for k in lods.size():
		var mi := MeshInstance3D.new()
		mi.name = "lod%d" % k
		mi.mesh = lods[k]
		mi.visibility_range_begin = ranges[k][0]
		mi.visibility_range_end = ranges[k][1]
		root.add_child(mi)
	return root
