extends RefCounted
## The Blender parts' checks (bike look overhaul, geometry track: blender/, assets/bike_parts and
## scripts/blender_parts.gd), run from tests/run_tests.gd: its _test_blender_parts_* functions hand
## over to these. No scene: the bikes are only laid out (BikeModel's _lay_out and
## _layout_cylinders), not drawn.

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## Every glb under assets/bike_parts, by path.
static func glbs(dir := BlenderParts.ROOT) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		out += glbs(dir + d + "/")
	return out


## Every glb loads as the parts agreement has it: three LODs, each lighter than the last, every
## surface named for a surface tag, and a top end's mount points (barrels, plugs, ports, inlets).
func test_glbs() -> void:
	var paths := glbs()
	check(paths.size() >= 6, "the Blender parts are in the game (%d glbs)" % paths.size())
	var bad := []
	for path in paths:
		var p := BlenderParts.part(path)
		if p.is_empty() or p["lods"].has(null):
			bad.append("%s: not three LODs" % path)
			continue
		var tris := []
		for mesh in p["lods"]:
			var n := 0
			for s in (mesh as Mesh).get_surface_count():
				var tag := BlenderParts.tag_of((mesh as Mesh).surface_get_material(s))
				if not BlenderParts.TAGS.has(tag):
					bad.append("%s: a surface tagged \"%s\"" % [path, tag])
				var idx: PackedInt32Array = (mesh as Mesh).surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				n += idx.size() / 3
			tris.append(n)
		if not (tris[0] > tris[1] and tris[1] > tris[2] and tris[2] > 0):
			bad.append("%s: LODs of %s triangles" % [path, str(tris)])
		if path.contains("/head/"):
			var m: Dictionary = p["mounts"]
			for need in ["cyl_1", "plug_1", "exhaust_port_1", "intake_1"]:
				if not m.has(need):
					bad.append("%s: no mount_%s" % [path, need])
	check(bad.is_empty(), "every glb has its three LODs, a surface tag on every surface and its mount points %s" % str(bad))


## The top ends fit every bike they can go in: for every engine whose layout has them, in every
## frame that suits one of its styles, each head's top end, scaled and placed by BlenderParts, sits
## inside the room BikeModel keeps round the code-built barrels and head (the frame's tubes and
## the tank are laid out clear of that), its barrels land on the engine's cylinders, and its plugs
## near where BikeModel draws them (on a leaning cylinder BikeModel's sit a little off the middle of
## the head; the plugs go on the glb's own plug mounts. A two-stroke's sit on its head, which
## BikeModel draws lower).
func test_top_end_fit() -> void:
	var heads: Array = PartsDB.by_kind["head"]
	var frames: Array = PartsDB.by_kind["frame"]
	var layouts := {}
	var bikes := 0
	var seen := {}
	var local := {}    # path -> its lod0's points, each once
	var out := []
	var off := []
	var missing := []
	for e in PartsDB.by_kind["engine"]:
		var layout := str(PartsDB.get_part(str(e)).get("layout"))
		if not DirAccess.dir_exists_absolute(BlenderParts.ROOT + "head/" + layout):
			continue
		layouts[layout] = true
		var styles := PartsDB.styles_of(str(e))
		for f in frames:
			if not PartsDB.styles_of(str(f)).any(func(s): return styles.has(s)):
				continue
			var m := BikeModel.new()
			var build := BikeBuild.new({"engine": e, "frame": f})
			m._lay_out(build)
			m._layout_cylinders(build)
			bikes += 1
			# (Frames that lay an engine out the same way, all but the cruisers' and choppers', are checked once.)
			var key := "%s %.4f %.4f %s" % [e, m._eng_s, m._head_k, str(m._cyls[0]["up"])]
			if seen.has(key):
				m.free()
				continue
			seen[key] = true
			# (The barrels' and heads' boxes first: most of a top end is in one of them.)
			var room := _boxes(m._engine_corners())
			room.reverse()
			for h in heads:
				var pieces := BlenderParts.top_end_pieces(layout, str(h), m._cyls, m._eng_s, m._bore_r)
				if pieces.is_empty():
					missing.append("%s %s" % [layout, h])
					continue
				var worst := 0.0
				var at := []    # [base, plug] per cylinder, in BikeModel's space
				for piece in pieces:
					var path: String = piece[0]
					var xform: Transform3D = piece[1]
					if not local.has(path):
						var once := {}
						for v in BlenderParts.points(path, Transform3D()):
							once[v.snappedf(0.0002)] = true
						local[path] = once.keys()
					for v in local[path]:
						worst = maxf(worst, _outside(room, xform * v))
					var mounts: Dictionary = BlenderParts.part(path)["mounts"]
					var n := 1
					while mounts.has("cyl_%d" % n):
						at.append([xform * (mounts["cyl_%d" % n] as Transform3D).origin, xform * (mounts["plug_%d" % n] as Transform3D).origin])
						n += 1
				if worst > 0.003:
					out.append("%s in %s, %s: %.1f mm out" % [e, f, h, worst * 1000.0])
				if at.size() != m._cyls.size():
					off.append("%s, %s: %d barrels for %d cylinders" % [e, h, at.size(), m._cyls.size()])
					continue
				for i in m._cyls.size():
					var c: Dictionary = m._cyls[i]
					var base_off := (at[i][0] as Vector3).distance_to(c["base"])
					var plug_off := (at[i][1] as Vector3).distance_to(c["base"] + c["up"] * 0.2 + Vector3(0.0, 0.0, 0.02))
					if layout == "2stroke":
						plug_off = 0.0
					if base_off > 0.001 or plug_off > 0.016:
						off.append("%s in %s, %s cylinder %d: base %.1f mm, plug %.1f mm off" % [e, f, h, i + 1, base_off * 1000.0, plug_off * 1000.0])
			m.free()
	check(layouts.size() >= 6 and missing.is_empty(), "every head part has a top end made in Blender for each of %s %s" % [str(layouts.keys()), str(missing)])
	check(bikes >= 300 and out.is_empty(), "each top end fits every frame its engine suits (%d engine and frame pairs) %s" % [bikes, str(out.slice(0, 6))])
	check(off.is_empty(), "its barrels land on the engine's cylinders and its plugs where the plugs are drawn %s" % str(off.slice(0, 6)))


## Every engine's crankcase is made in Blender, and fits every frame its engine suits: inside the
## room BikeModel keeps round the code-built case, sump and alternator cover, or the code-built
## engine's own pieces that reach out past that (its covers, a V-twin's pushrod tubes, a four's
## starter motor).
func test_cases_fit() -> void:
	var missing := []
	var out := []
	var seen := {}
	var pairs := 0
	for e in PartsDB.by_kind["engine"]:
		var path := BlenderParts.path_for("engine", str(e))
		if BlenderParts.part(path).is_empty():
			missing.append(e)
			continue
		var styles := PartsDB.styles_of(str(e))
		var local := {}
		for v in BlenderParts.points(path, Transform3D()):
			local[v.snappedf(0.0002)] = true
		for f in PartsDB.by_kind["frame"]:
			if not PartsDB.styles_of(str(f)).any(func(s): return styles.has(s)):
				continue
			var m := BikeModel.new()
			var build := BikeBuild.new({"engine": e, "frame": f})
			m._lay_out(build)
			m._layout_cylinders(build)
			pairs += 1
			var key := "%s %.4f" % [e, m._eng_s]
			if seen.has(key):
				m.free()
				continue
			seen[key] = true
			var s := m._eng_s
			var corners := m._engine_corners()
			m.build_from(build, m.paint, {}, null, false)
			for mi in m._slot_meshes.get("engine", []):
				var g := mi as GeometryInstance3D
				if g != null:
					var box := g.transform * g.get_aabb()
					BikeModel._add_box_corners(corners, box.get_center(), Basis(), box.size * 0.5)
			var room := _boxes(corners)
			var xform := BlenderParts.engine_xform(m._engine_c, s)
			var worst := 0.0
			for v in local:
				worst = maxf(worst, _outside(room, xform * v))
			if worst > 0.003:
				out.append("%s in %s: %.1f mm out" % [e, f, worst * 1000.0])
			m.free()
	check(missing.is_empty(), "every engine has a crankcase made in Blender %s" % str(missing))
	check(pairs >= 300 and out.is_empty(), "each fits every frame its engine suits (%d pairs) %s" % [pairs, str(out.slice(0, 6))])


## A part with no glb has none to load, so BikeModel keeps drawing it itself: an engine layout with no
## top ends made yet.
func test_fallback() -> void:
	check(BlenderParts.instance(BlenderParts.path_for("head", "four_valve", "rotary"), Transform3D()) == null
		and BlenderParts.part(BlenderParts.path_for("frame", "steel_cradle")).is_empty(),
		"a part with no Blender glb is left to BikeModel's own drawing")
	var node := BlenderParts.instance(BlenderParts.path_for("head", "two_valve_stock", "twin"), Transform3D())
	check(node != null and node.get_child_count() >= 3 + 8 and (node.get_node("lod0") as MeshInstance3D).visibility_range_end == BlenderParts.LOD1_AT
		and (node.get_node("lod2") as MeshInstance3D).visibility_range_begin == BlenderParts.LOD2_AT,
		"one with a glb comes as its three LODs, each over its own distances, and its mount points")
	if node != null:
		node.free()


## The boxes BikeModel's _engine_corners lists (eight corners each), as [middle, half x, half y, half z].
static func _boxes(corners: Array) -> Array:
	var out := []
	for i in range(0, corners.size(), 8):
		var p := []
		for k in 8:
			p.append(corners[i + k][0])
		var mid := Vector3.ZERO
		for q in p:
			mid += q
		out.append([mid / 8.0, (p[1] - p[0]) * 0.5, (p[2] - p[0]) * 0.5, (p[4] - p[0]) * 0.5])
	return out


## How far (m) `v` is outside the nearest of `boxes` (0 inside one).
static func _outside(boxes: Array, v: Vector3) -> float:
	var best := INF
	for b in boxes:
		var d: Vector3 = v - b[0]
		var worst := 0.0
		for a in [b[1], b[2], b[3]]:
			var ax: Vector3 = a
			var half := ax.length()
			if half < 0.0001:
				continue
			worst = maxf(worst, absf(d.dot(ax / half)) - half)
		if worst <= 0.0:
			return 0.0
		best = minf(best, worst)
	return best
