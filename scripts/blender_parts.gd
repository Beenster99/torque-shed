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

## Whether bikes in the new look are drawn with these (see BikeModel._blender_on): the tests turn
## it off to check the new look's bake on the code-built shapes alone.
static var on := true
static var _loaded := {}    # path -> {"lods": [Mesh x3], "mounts": {name: Transform3D}}, or {} when there's no glb
static var _split := {}     # [path, mirrored] -> its lod0 a surface at a time (see surfaces)


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
static func top_end_pieces(layout: String, head: String, cyls: Array, eng_s: float, bore_r: float, width := -1.0) -> Array:
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
		# (`width`: the barrel's width against its drawn length, when that isn't the same.)
		var b := (up.length() if width < 0.0 else width) * bore_r / float(PER_CYLINDER_BORE[layout])
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


## A part's lod0 a surface at a time, [[Mesh, Material], ...] with each surface's own material, so
## BikeModel can put each on in the material its tag takes on that bike; `mirrored`, turned inside
## out across X (for a part on the left: see placed). Made once; empty when there's no glb.
static func surfaces(path: String, mirrored := false) -> Array:
	var key := [path, mirrored]
	if not _split.has(key):
		var p := part(path)
		_split[key] = [] if p.is_empty() else split(p["lods"][0], mirrored)
	return _split[key]


## `mesh` a surface at a time ([[Mesh, Material], ...]), `mirrored` across X with its triangles
## turned the other way round, so they still face out.
static func split(mesh: Mesh, mirrored := false) -> Array:
	var out := []
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if mirrored:
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in v.size():
				v[i].x = -v[i].x
			for i in n.size():
				n[i].x = -n[i].x
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size() - 2, 3):
				var t := idx[i + 1]
				idx[i + 1] = idx[i + 2]
				idx[i + 2] = t
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = n
			arrays[Mesh.ARRAY_INDEX] = idx
			arrays[Mesh.ARRAY_TANGENT] = null
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(0, mesh.surface_get_material(s))
		out.append([am, mesh.surface_get_material(s)])
	return out


## A part's surfaces (see surfaces) and the transform to draw them with for it to sit at `xform`:
## [surfaces, Transform3D]. A mirroring `xform` (a can on the left) gets the mirrored surfaces and
## a transform that doesn't mirror, as a bike's merged meshes keep every triangle the way it faces.
static func placed(path: String, xform: Transform3D) -> Array:
	if xform.basis.determinant() >= 0.0:
		return [surfaces(path), xform]
	return [surfaces(path, true), Transform3D(xform.basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), xform.origin)]


## `surfaces` (as surfaces gives them) with `xform` put into their vertices, for a part drawn
## sheared (a tank tilted along its frame line): a sheared node's bounds take in the corners of
## its sheared box, well outside the part, where these are drawn untransformed and bound tight.
static func baked_in(surfaces: Array, xform: Transform3D) -> Array:
	var out := []
	var turn := xform.basis.inverse().transposed()
	for s in surfaces:
		var arrays := (s[0] as Mesh).surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in v.size():
			v[i] = xform * v[i]
		for i in n.size():
			n[i] = (turn * n[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = null
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(0, s[1])
		out.append([am, s[1]])
	return out


## A cross-section part (a mudguard's: see blender/parts/guard/guards.py, running 0 to 1 along +Z,
## -0.5 to 0.5 across) bent along `pts`, its up `ups` at each, `width` across: each vertex goes
## the share of the way along the line its Z gives, out across by its X and up by its Y. A `tip`
## narrows to a point at the far end in a half-ellipse. Null when there's no glb.
static func section_along(path: String, pts: Array, ups: Array, width: float, tip := false) -> ArrayMesh:
	var p := part(path)
	if p.is_empty() or pts.size() < 2:
		return null
	var lengths := [0.0]
	for i in range(1, pts.size()):
		lengths.append(float(lengths[i - 1]) + (pts[i] - pts[i - 1] as Vector3).length())
	var total := maxf(float(lengths[-1]), 0.0001)
	var mesh: Mesh = p["lods"][0]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in v.size():
			var at := clampf(v[i].z, 0.0, 1.0) * total
			var k := 1
			while k < pts.size() - 1 and float(lengths[k]) < at:
				k += 1
			var f := clampf((at - float(lengths[k - 1])) / maxf(float(lengths[k]) - float(lengths[k - 1]), 0.0001), 0.0, 1.0)
			var along: Vector3 = (pts[k] - pts[k - 1] as Vector3).normalized()
			var up: Vector3 = (ups[k - 1] as Vector3).lerp(ups[k], f)
			up = (up - along * up.dot(along)).normalized()
			var across := up.cross(along).normalized()
			var w := width * (sqrt(maxf(1.0 - v[i].z * v[i].z, 0.0)) if tip else 1.0)
			var nx := n[i]
			v[i] = (pts[k - 1] as Vector3).lerp(pts[k], f) + across * v[i].x * w + up * v[i].y
			n[i] = (across * nx.x / maxf(w, 0.001) + up * nx.y + along * nx.z / total).normalized()
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


## The rings of points ShapeKit.loft lays an open shell through (`sections` from `a0` round to
## `a1`), the same points, for shell to give a thickness and edges.
static func loft_rows(sections: Array, ring: int, a0: float, a1: float) -> Array:
	var rows := []
	var count := sections.size()
	var span := a1 - a0
	var steps := maxi(4, roundi(ring * span / TAU))
	for i in count:
		var s: Dictionary = sections[i]
		var c: Vector3 = s["c"]
		var prev: Vector3 = (sections[maxi(i - 1, 0)] as Dictionary)["c"]
		var next: Vector3 = (sections[mini(i + 1, count - 1)] as Dictionary)["c"]
		var t := next - prev
		t.x = 0.0
		t = t.normalized() if t.length() > 0.0001 else Vector3.BACK
		var up := t.cross(Vector3.RIGHT).normalized()
		var w := float(s.get("w", 0.1))
		var hu := float(s.get("up", 0.1))
		var hd := float(s.get("down", hu))
		var e := 2.0 / float(s.get("n", 2.4))
		var bw := float(s.get("bw", 1.0))
		var pts := PackedVector3Array()
		for j in steps + 1:
			var a := a0 + span * j / steps
			var ca := cos(a)
			var sa := sin(a)
			var x := signf(ca) * pow(absf(ca), e) * w * (bw if sa < 0.0 else 1.0)
			var y := signf(sa) * pow(absf(sa), e) * (hu if sa > 0.0 else hd)
			pts.append(c + Vector3.RIGHT * x + up * y)
		rows.append(pts)
	return rows


## An open shell the code drew paper thin (`code`: ShapeKit.loft or facets, its outer face then
## its inside face) through `rows` (each a PackedVector3Array, in order across), given the
## thickness of the edge section at `path` (fairing/edge/<kind>.glb): the inside face set in by
## it, and the section run round every edge between the two faces. Null when there's no glb.
static func shell(code: Mesh, rows: Array, path: String) -> ArrayMesh:
	var p := part(path)
	if p.is_empty() or rows.size() < 2 or code == null or code.get_surface_count() == 0:
		return null
	var edge: Mesh = p["lods"][0]
	var thick := -edge.get_aabb().position.y
	var arrays := code.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var half := v.size() / 2
	for k in half:
		v[half + k] += n[half + k] * thick
	var normals := _grid_normals(rows, code)
	var edges := _grid_edges(rows)
	var ev := PackedVector3Array()
	var en := PackedVector3Array()
	var euv := PackedVector2Array()
	var ei := PackedInt32Array()
	var e_arrays := edge.surface_get_arrays(0)
	for e in edges:
		var line: Array = e[0]
		var inner: Array = e[1]
		for k in line.size() - 1:
			var a: Vector3 = rows[line[k].x][line[k].y]
			var b: Vector3 = rows[line[k + 1].x][line[k + 1].y]
			if a.distance_squared_to(b) < 1e-8:
				continue
			var na: Vector3 = normals[line[k].x][line[k].y]
			var nb: Vector3 = normals[line[k + 1].x][line[k + 1].y]
			var hint: Vector3 = ((rows[inner[k].x][inner[k].y] as Vector3) + (rows[inner[k + 1].x][inner[k + 1].y] as Vector3)) * 0.5
			var out_dir := (a + b) * 0.5 - hint
			var up := (na + nb).normalized()
			if up.cross(b - a).dot(out_dir) < 0.0:
				var swap := a
				a = b
				b = swap
				var swap_n := na
				na = nb
				nb = swap_n
			_along(e_arrays, a, b, na, nb, ev, en, euv, ei)
	var base := v.size()
	v.append_array(ev)
	n.append_array(en)
	uv.append_array(euv)
	for k in ei:
		idx.append(k + base)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, edge.surface_get_material(0))
	return mesh


## Each point's normal on the grid `rows`, from the faces round it, turned the way the outer face
## of the code's mesh of it looks (its first half: see shell).
static func _grid_normals(rows: Array, code: Mesh) -> Array:
	# (The code's first vertex, outer face, is the grid's first point, on the loft and the facets alike.)
	var outer: Vector3 = code.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]
	var count := rows.size()
	var width: int = (rows[0] as PackedVector3Array).size()
	var normals := []
	for i in count:
		var row := []
		row.resize(width)
		row.fill(Vector3.ZERO)
		normals.append(row)
	for i in count - 1:
		for j in width - 1:
			var a: Vector3 = rows[i][j]
			var fn := ((rows[i][j + 1] as Vector3) - a).cross((rows[i + 1][j] as Vector3) - a)
			fn += ((rows[i + 1][j + 1] as Vector3) - (rows[i + 1][j] as Vector3)).cross((rows[i + 1][j + 1] as Vector3) - (rows[i][j + 1] as Vector3))
			for q in [[i, j], [i, j + 1], [i + 1, j], [i + 1, j + 1]]:
				normals[q[0]][q[1]] += fn
	var turn := -1.0 if (normals[0][0] as Vector3).dot(outer) < 0.0 else 1.0
	for i in count:
		for j in width:
			normals[i][j] = ((normals[i][j] as Vector3) * turn).normalized()
	return normals


## The grid's four edges, each [its points, the points next in from them] as Vector2i(row,
## across): the first row, the last row, the first point across and the last.
static func _grid_edges(rows: Array) -> Array:
	var count := rows.size()
	var width: int = (rows[0] as PackedVector3Array).size()
	var edges := [[[], []], [[], []], [[], []], [[], []]]
	for j in width:
		edges[0][0].append(Vector2i(0, j))
		edges[0][1].append(Vector2i(1, j))
		edges[1][0].append(Vector2i(count - 1, j))
		edges[1][1].append(Vector2i(count - 2, j))
	for i in count:
		edges[2][0].append(Vector2i(i, 0))
		edges[2][1].append(Vector2i(i, 1))
		edges[3][0].append(Vector2i(i, width - 1))
		edges[3][1].append(Vector2i(i, width - 2))
	return edges


## Where fasteners go round a shell (as for shell): along each of the grid's `which` edges (0 the
## first row, 1 the last, 2 the first point across, 3 the last), every `spacing` m and `inset` m in
## from it, clear of its ends; each a transform with Y out of the surface and Z along the edge.
static func edge_spots(rows: Array, code: Mesh, which: Array, spacing: float, inset: float) -> Array:
	var out := []
	if rows.size() < 2 or code == null or code.get_surface_count() == 0:
		return out
	var normals := _grid_normals(rows, code)
	var edges := _grid_edges(rows)
	for w: int in which:
		var line: Array = edges[w][0]
		var inner: Array = edges[w][1]
		var lengths := [0.0]
		for k in range(1, line.size()):
			lengths.append(float(lengths[k - 1]) + (rows[line[k].x][line[k].y] as Vector3).distance_to(rows[line[k - 1].x][line[k - 1].y]))
		var total: float = lengths[-1]
		if total < spacing:
			continue
		var count := floori(total / spacing)
		var gap := (total - spacing * (count - 1)) * 0.5
		var k := 1
		for c in count:
			var at := gap + spacing * c
			while k < line.size() - 1 and float(lengths[k]) < at:
				k += 1
			var f := clampf((at - float(lengths[k - 1])) / maxf(float(lengths[k]) - float(lengths[k - 1]), 0.0001), 0.0, 1.0)
			var a: Vector3 = rows[line[k - 1].x][line[k - 1].y]
			var b: Vector3 = rows[line[k].x][line[k].y]
			var p := a.lerp(b, f)
			var hint: Vector3 = (rows[inner[k - 1].x][inner[k - 1].y] as Vector3).lerp(rows[inner[k].x][inner[k].y], f)
			var up: Vector3 = (normals[line[k - 1].x][line[k - 1].y] as Vector3).lerp(normals[line[k].x][line[k].y], f).normalized()
			var into := hint - p
			into = (into - up * into.dot(up))
			if into.length() < inset * 1.5:
				continue
			var along := (b - a).normalized()
			along = (along - up * along.dot(up)).normalized()
			out.append(Transform3D(Basis(up.cross(along), up, along), p + into.normalized() * inset))
	return out


## A part's surfaces ([[Mesh, Material], ...] as surfaces gives them) drawn once at each of
## `xforms`, all in one mesh a surface.
static func copies(path: String, xforms: Array) -> Array:
	var out := []
	if xforms.is_empty():
		return out
	for s in surfaces(path):
		var arrays := (s[0] as Mesh).surface_get_arrays(0)
		var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var suv = arrays[Mesh.ARRAY_TEX_UV]
		var si = arrays[Mesh.ARRAY_INDEX]
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		for x: Transform3D in xforms:
			var base := v.size()
			for k in sv.size():
				v.append(x * sv[k])
				n.append((x.basis * sn[k]).normalized())
				uv.append(suv[k] if suv != null else Vector2.ZERO)
			if si == null:
				for k in sv.size():
					idx.append(base + k)
			else:
				for k in si:
					idx.append(base + k)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(0, s[1])
		out.append([am, s[1]])
	return out


## One stretch of an edge section (its surface's `arrays`) laid from `a` to `b`, out along the
## normal crossed with the edge, added to the lists.
static func _along(arrays: Array, a: Vector3, b: Vector3, na: Vector3, nb: Vector3, verts: PackedVector3Array,
		normals: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> void:
	var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var suv = arrays[Mesh.ARRAY_TEX_UV]
	var si = arrays[Mesh.ARRAY_INDEX]
	var along := b - a
	var length := along.length()
	along /= length
	var base := verts.size()
	for k in sv.size():
		var f := clampf(sv[k].z, 0.0, 1.0)
		var up := na.lerp(nb, f)
		up = (up - along * up.dot(along)).normalized()
		var across := up.cross(along).normalized()
		verts.append(a.lerp(b, f) + across * sv[k].x + up * sv[k].y)
		normals.append((across * sn[k].x + up * sn[k].y + along * sn[k].z).normalized())
		uvs.append(suv[k] if suv != null else Vector2.ZERO)
	if si == null:
		for k in sv.size():
			idx.append(base + k)
	else:
		for k in si:
			idx.append(base + k)


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


## How far outboard of its pivot the Blender-made lever's ball end is (blender/parts/controls).
const LEVER_REACH := 0.127
## A footrest hanger plate's thickness (m), the Blender-made one's (blender/parts/controls).
const HANGER_T := 0.012


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
## `radius` (one number, or one per route point as _bend takes). One ArrayMesh per LOD, for the
## first `lods` of them; [] when there's no such glb.
static func sweep_section(path: String, route: Array, radius, per_seg := 6, lods := 3) -> Array:
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
	for lod in lods:
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


## How many sections a tyre is made of, round the hoop (the parts agreement's 6b).
const TYRE_SECTIONS := 32
## How far up a tyre section its sidewalls bulge to the full width (blender/parts/tyre/treads.py).
const TYRE_BULGE := 0.434


## The size (m) of a pixel `distance` off, on a 75 degree view 1080 pixels high (as BikeLook.lod_tris
## works it out): a level of detail that size is drawn from there on.
static func lod_size(distance: float) -> float:
	return distance * 2.0 * tan(deg_to_rad(75.0) * 0.5) / 1080.0


## A mesh per surface of `lods` (a part's three LODs as ArrayMeshes, as tyre_hoop makes them),
## each carrying all three: the lighter ones drawn from LOD1_AT and LOD2_AT off. [[Mesh, Material],
## ...] as split's, each mesh with its triangles at each level in its "lod_tris" (see BikeLook.stats).
static func with_lods(lods: Array) -> Array:
	var first: Mesh = lods[0]
	var out := []
	for s in first.get_surface_count():
		var mat := first.surface_get_material(s)
		var arrays := first.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var tris := [(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3]
		var levels := {}
		for k in range(1, lods.size()):
			var mesh: Mesh = lods[k]
			# (A surface a lighter level leaves out, such as studs far off, is one empty triangle there.)
			var idx := PackedInt32Array([0, 0, 0])
			for j in mesh.get_surface_count():
				if mesh.surface_get_material(j) != mat:
					continue
				var a := mesh.surface_get_arrays(j)
				var base := verts.size()
				verts.append_array(a[Mesh.ARRAY_VERTEX])
				normals.append_array(a[Mesh.ARRAY_NORMAL])
				uvs.append_array(a[Mesh.ARRAY_TEX_UV])
				idx = PackedInt32Array()
				for i in a[Mesh.ARRAY_INDEX]:
					idx.append(base + i)
			var size := lod_size(LOD1_AT if k == 1 else LOD2_AT)
			levels[size] = idx
			tris.append([size, idx.size() / 3])
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = index
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], levels)
		am.surface_set_material(0, mat)
		am.set_meta(&"lod_tris", tris)
		out.append([am, mat])
	return out


## The glb for a tyre's tread pattern (BikeModel.tread_pattern's: "" is a slick).
static func tyre_path(tread: String) -> String:
	return ROOT + "tyre/%s.glb" % (tread if tread != "" else "slick")


## A whole tyre on a wheel's node, as BikeModel's tyre_mesh draws it to its size: the tread
## pattern's Blender section (`path`, drawn in the tyre's own units: across -1 to 1, bead 0 to
## crown 1, and 1/32 of the way round along +Z) bent round the hoop 32 times, from the bead just
## inside the rim (`rim_r`) to the crown at `radius`, `width` across, the axle along X. Its
## sidewalls run out from the beads, inside a rim `rim_w` wide, to the full width at the bulge, as
## BikeModel's do. One ArrayMesh per LOD; [] when there's no such glb.
static func tyre_hoop(path: String, rim_r: float, radius: float, width: float, rim_w: float) -> Array:
	var p := part(path)
	if p.is_empty():
		return []
	var half := width * 0.5
	var bead := minf(rim_w * 0.5 - 0.004, half * 0.9)
	var base := rim_r - 0.006
	var span := maxf(radius - rim_r, 0.02) + 0.006
	var step := TAU / TYRE_SECTIONS
	var out := []
	for lod in 3:
		var mesh: Mesh = p["lods"][lod]
		var am := ArrayMesh.new()
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
			var nv := PackedVector3Array()
			var nn := PackedVector3Array()
			var nuv := PackedVector2Array()
			var ni := PackedInt32Array()
			for k in TYRE_SECTIONS:
				for j in verts.size():
					var v := verts[j]
					var a := (k + v.z) * step
					var r := base + v.y * span
					var out_dir := Vector3(0.0, cos(a), sin(a))
					var round_dir := Vector3(0.0, -sin(a), cos(a))
					# (Below the bulge, the wall's 0.9 to 1 across runs from the bead to the full width.)
					var x := v.x * half
					if v.y < TYRE_BULGE and absf(v.x) >= 0.9:
						x = signf(v.x) * lerpf(bead, half, clampf((absf(v.x) - 0.9) / 0.1, 0.0, 1.0))
					nv.append(Vector3(x, 0.0, 0.0) + out_dir * r)
					# (The section's stretched to the tyre, so its normals are squeezed the other way. Where
					# one section meets the next, the normal runs square round the tyre, as both sides
					# of the join would have it, so the joins don't show.)
					var n := normals[j]
					if v.z < 0.001 or v.z > 0.999:
						n.z = 0.0
					nn.append((Vector3.RIGHT * (n.x / half) + out_dir * (n.y / span) + round_dir * (n.z / (step * r))).normalized())
					# (1 UV unit = 1 m, round the tyre and across it.)
					nuv.append(Vector2(a * r, v.x * half))
				for i in idx:
					ni.append(i + k * verts.size())
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
