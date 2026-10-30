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


## The can shapes BikeModel's _can draws.
const CAN_SHAPES: Array[String] = ["round", "oval", "megaphone", "hex", "short", "peashooter", "slash", "open", "fishtail",
	"turnout", "baloney", "trumpet", "reverse", "tri", "stubby"]


## Every can shape is made in Blender and takes the code-built can's place: stretched between the
## same two points at the same radius, it keeps inside the code-built can's pieces, and lets the
## gas out where BikeModel's does (the exhaust's tip, for the smoke and the sound).
func test_cans_fit() -> void:
	var out := []
	var a := Vector3(0.15, 0.3, 0.2)
	var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build("classic")))
	for shape in CAN_SHAPES:
		var path := BlenderParts.ROOT + "exhaust/can/%s.glb" % shape
		if BlenderParts.part(path).is_empty():
			out.append("%s: no glb" % shape)
			continue
		for r in [0.04, 0.05, 0.06]:
			for length in [0.3, 0.5]:
				var b := a + Vector3(0.0, 0.0, length)
				var m := BikeModel.new()
				m.build_from(build, m.paint, {}, null, false)
				m._current_slot = "exhaust"
				var before := m.get_child_count()
				var tip := m._can(a, b, shape, StandardMaterial3D.new(), r)
				var corners := []
				for c in m.get_children().slice(before):
					var g := c as GeometryInstance3D
					if g != null:
						var box := g.transform * g.get_aabb()
						BikeModel._add_box_corners(corners, box.get_center(), Basis(), box.size * 0.5)
				m.free()
				var room := _boxes(corners)
				var xform := BlenderParts.can_xform(a, b, r, shape)
				var worst := 0.0
				for v in BlenderParts.points(path, xform):
					worst = maxf(worst, _outside(room, v))
				var miss := BlenderParts.can_outlet(path, xform).distance_to(tip)
				# (A can's end fittings stretch with it here, where BikeModel's stay their own size, so
				# off the reference can its outlet can move a little.)
				# (A turnout's end pipe is BikeModel's one size on every can, where here it scales with the
				# can, so off the reference can it's only kept near.)
				var off_ref: bool = length != BlenderParts.CAN_LENGTH or r != BlenderParts.CAN_RADIUS
				var room_tol: float = 0.02 if shape == "turnout" and off_ref else 0.003
				if worst > room_tol or miss > (0.03 if off_ref else 0.005):
					out.append("%s (r %.2f, %.1f m): %.1f mm out, its outlet %.1f mm off" % [shape, r, length, worst * 1000.0, miss * 1000.0])
	check(out.is_empty(), "every exhaust can is made in Blender and fits where BikeModel draws its own %s" % str(out.slice(0, 6)))
	# On the left a can is mirrored, so a turnout turns out to the left.
	var left := BlenderParts.can_xform(Vector3(-0.15, 0.3, 0.2), Vector3(-0.15, 0.3, 0.7), 0.05)
	check(BlenderParts.can_outlet(BlenderParts.can_path("turnout"), left).x < -0.17 and BlenderParts.can_path("no_such_can").ends_with("/round.glb"),
		"a can on the left turns out to the left, and an unknown shape is the round can")


## A header made of Blender pipe sections follows BikeModel's own: along a bent route its every
## ring sits round the same curve at the header's radius (a tapering one too, as a two-stroke's
## expansion chamber), from end to end.
func test_pipe_sweep() -> void:
	var route := [Vector3(0.05, 0.5, -0.3), Vector3(0.05, 0.38, -0.36), Vector3(0.1, 0.24, -0.22), Vector3(0.15, 0.24, 0.1), Vector3(0.16, 0.3, 0.35)]
	var curve := ShapeKit.smooth(route, 6)
	for finish in ["plain", "wrap"]:
		var path := BlenderParts.ROOT + "exhaust/pipe/%s.glb" % finish
		var lods := BlenderParts.sweep_section(path, route, 0.022)
		var bulge := 1.08 if finish == "wrap" else 1.001
		var worst := 0.0
		var ends := [INF, INF]
		for v in (lods[0] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var d := _to_curve(curve, v)
			worst = maxf(worst, maxf(d - 0.022 * bulge, 0.022 * 0.97 - d))
			ends[0] = minf(ends[0], v.distance_to(route[0]))
			ends[1] = minf(ends[1], v.distance_to(route[route.size() - 1]))
		check(lods.size() == 3 and worst < 0.0015 and ends[0] < 0.025 and ends[1] < 0.025,
			"a %s header follows BikeModel's curve at its radius (%.1f mm off at worst), end to end" % [finish, worst * 1000.0])
	var chamber := BlenderParts.sweep_section(BlenderParts.ROOT + "exhaust/pipe/plain.glb", route, [0.022, 0.03, 0.055, 0.06, 0.024])
	var fattest := 0.0
	for v in (chamber[0] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		fattest = maxf(fattest, _to_curve(curve, v))
	check(fattest > 0.055 and fattest < 0.062, "a tapering pipe swells as BikeModel's expansion chamber does (%.3f m at its fattest)" % fattest)


## Every wheel in the catalogue is made in Blender at its own size: its rim no bigger than
## BikeModel's (the flanges the tyre's beads sit in), no wider than the rim and the hub between
## them, and on the axle.
func test_wheels() -> void:
	var out := []
	for w in PartsDB.by_kind["wheel"]:
		var path := BlenderParts.path_for("wheel", str(w))
		var p := BlenderParts.part(path)
		if p.is_empty() or not p["mounts"].has("axle"):
			out.append("%s: no glb, or no axle" % w)
			continue
		var part: Dictionary = PartsDB.get_part(str(w))
		var rim_r := float(part["diameter"]) * 0.0127
		var hw := BikeModel.rim_width_of(part) * 0.5
		var big := 0.0
		var wide := 0.0
		for v in BlenderParts.points(path, Transform3D()):
			big = maxf(big, Vector2(v.y, v.z).length())
			wide = maxf(wide, absf(v.x))
		if big > rim_r + 0.0095 or wide > maxf(hw + 0.006, 0.085):
			out.append("%s: %.3f m round (rim %.3f), %.3f m across" % [w, big, rim_r, wide])
	check(out.is_empty(), "every wheel is made in Blender, its own size %s" % str(out.slice(0, 6)))


## Every tread pattern is made in Blender, and bent round the hoop it makes a tyre the size
## BikeModel's is: between the bead in the rim and the crown, no wider than the tyre, its crown
## (or its knobs' tops) where BikeModel's tread is, on a skinny trail tyre and a fat rear alike.
func test_tyres() -> void:
	var out := []
	for tread in ["slick", "rib", "touring", "sport", "cruiser", "trail", "sipes", "knobs", "blocks", "studs"]:
		var path := BlenderParts.tyre_path(tread)
		for size in [[0.2667, 0.36, 0.09, 0.04], [0.2159, 0.31, 0.18, 0.14]]:
			var lods := BlenderParts.tyre_hoop(path, size[0], size[1], size[2], size[3])
			if lods.size() != 3:
				out.append("%s: no glb" % tread)
				break
			var lo := INF
			var hi := 0.0
			var wide := 0.0
			for v in (lods[0] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var r := Vector2(v.y, v.z).length()
				lo = minf(lo, r)
				hi = maxf(hi, r)
				wide = maxf(wide, absf(v.x))
			for s in (lods[0] as ArrayMesh).get_surface_count():
				for v in (lods[0] as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					hi = maxf(hi, Vector2(v.y, v.z).length())
			if lo < float(size[0]) - 0.0075 or absf(hi - float(size[1])) > 0.004 or wide > float(size[2]) * 0.5 + 0.002:
				out.append("%s on %.2f m: %.3f to %.3f m round, %.3f across" % [tread, size[1], lo, hi, wide * 2.0])
	check(out.is_empty(), "every tread pattern makes a tyre BikeModel's size round the hoop %s" % str(out.slice(0, 6)))


## How far `v` is from the polyline `curve`.
static func _to_curve(curve: Array, v: Vector3) -> float:
	var best := INF
	for i in curve.size() - 1:
		var a: Vector3 = curve[i]
		var ab: Vector3 = (curve[i + 1] as Vector3) - a
		var f := clampf((v - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, v.distance_to(a + ab * f))
	return best


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


## Whether `mi` is a piece of a Blender-made part: its mesh's surface still carries the glb's
## material, named for a surface tag.
static func _blender_made(mi) -> bool:
	if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
		return false
	var mesh := (mi as MeshInstance3D).mesh
	return mesh.get_surface_count() > 0 and BlenderParts.TAGS.has(BlenderParts.tag_of(mesh.surface_get_material(0)))


## The slots the loader draws in their Blender-made shapes (this wave's).
const LOADED: Array[String] = ["engine", "head", "exhaust"]
## How far (m) a Blender-made part's box may be from the code-built one's, any side.
const LOADED_GIVE := 0.035
## The most triangles a new-look bike may draw close up with its Blender-made parts on, and how
## many more than with the code-built shapes alone (the parts agreement's budgets per part,
## added up for the parts loaded so far).
const LOADED_TRIS := 150000
const LOADED_MORE := 60000


## The loader: a bike in the new look wears its Blender-made engine, top end and exhaust where
## the code-built ones were, each surface in its finish on that bike, with the headers' ports
## kept for their heat colours; a Classic bike has none of them; and the bike stays in budget.
func test_new_look() -> void:
	var off := []
	var classic_blender := []
	var missing := []
	var worst := {}
	BikeLookNew.lods_now = true
	for style in PartsDB.STYLES:
		var parts := Contracts.style_build(style)
		var models := {}
		for k in ["classic", "code", "blender"]:
			var m := BikeModel.new()
			m.look = BikeLook.CLASSIC if k == "classic" else BikeLook.NEW
			BlenderParts.on = k != "code"
			t.add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
			models[k] = m
		BlenderParts.on = true
		var m: BikeModel = models["blender"]
		for slot in m._slot_meshes:
			var mine := (m._slot_meshes[slot] as Array).filter(_blender_made)
			if slot in LOADED and mine.is_empty() and not (models["code"] as BikeModel)._slot_meshes[slot].is_empty():
				missing.append("%s %s" % [style, slot])
			if (models["classic"] as BikeModel)._slot_meshes[slot].any(_blender_made):
				classic_blender.append("%s %s" % [style, slot])
		for slot in LOADED:
			var a := (models["code"] as BikeModel).slot_bounds(slot)
			var b := m.slot_bounds(slot)
			if slot == "head":
				# (A pushrod twin's head brings its pushrod tubes, down the barrels to the cases.)
				a = AABB(Vector3(a.position.x, b.position.y, a.position.z), Vector3(a.size.x, a.end.y - b.position.y, a.size.z))
			var d := maxf((a.position - b.position).abs()[(a.position - b.position).abs().max_axis_index()],
				(a.end - b.end).abs()[(a.end - b.end).abs().max_axis_index()])
			worst[slot] = maxf(float(worst.get(slot, 0.0)), d)
			if d > LOADED_GIVE:
				off.append("%s %s %.3f" % [style, slot, d])
		if m._exhaust_ports.size() != (models["code"] as BikeModel)._exhaust_ports.size() or m._exhaust_ports.is_empty():
			off.append("%s ports" % style)
		var tris_code := BikeLook.stats(models["code"])["tris"] as int
		var tris := BikeLook.stats(m)["tris"] as int
		worst["tris"] = maxi(int(worst.get("tris", 0)), tris)
		worst["more"] = maxi(int(worst.get("more", 0)), tris - tris_code)
		if tris > LOADED_TRIS or tris - tris_code > LOADED_MORE:
			off.append("%s %d triangles (%d with the code's shapes)" % [style, tris, tris_code])
		for k in models:
			(models[k] as Node).free()
	# Every engine, head and exhaust in the catalogue, on a bike in the new look, is drawn.
	var by_slot := {}
	var most := 0
	for id in PartsDB.parts:
		var slots := PartsDB.slots_for_kind(PartsDB.kind_of(id))
		if not slots.is_empty() and str(slots[0]) in LOADED:
			if not by_slot.has(slots[0]):
				by_slot[slots[0]] = []
			by_slot[slots[0]].append(id)
			most = maxi(most, (by_slot[slots[0]] as Array).size())
	var base := Contracts.style_build("classic")
	for i in most:
		var parts := base.duplicate()
		for slot in by_slot:
			parts[slot] = by_slot[slot][i % (by_slot[slot] as Array).size()]
		var m := BikeModel.new()
		m.look = BikeLook.NEW
		t.add_child(m)
		m.build_from(BikeBuild.new(parts))
		for slot in by_slot:
			if str(m._build.parts.get(slot, "")) == str(parts[slot]) and (m._slot_meshes[slot] as Array).is_empty():
				missing.append(str(parts[slot]))
		m.free()
	BikeLookNew.lods_now = false
	check(missing.is_empty(), "every style's new-look bike wears its Blender-made engine, top end and exhaust, and every one in the catalogue is drawn %s" % [missing])
	check(classic_blender.is_empty(), "and a Classic one none of them %s" % [classic_blender])
	check(off.is_empty(), "each in the code-built one's place, the ports kept and inside the budget %s %s" % [worst, off])
	# Baked as it's ridden: the headers still colour with heat, and the bike's still a few draws.
	var bake := BikeModel.new()
	bake.look = BikeLook.NEW
	bake.baked = true
	t.add_child(bake)
	BikeLookNew.lods_now = true
	bake.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build("classic"))))
	BikeLookNew.lods_now = false
	var hot := false
	var left := 0
	for mi in bake.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if _blender_made(mi):
			left += 1
		if mesh == null or (mi as MeshInstance3D).material_override != BikeShader.material():
			continue
		var c3 = mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM3]
		if c3 is PackedFloat32Array:
			for i in range(1, (c3 as PackedFloat32Array).size(), 4):
				hot = hot or (c3 as PackedFloat32Array)[i] > 0.1
	var s: Dictionary = BikeLook.stats(bake)
	check(hot and left == 0 and s["draws"] - s["rider_draws"] <= 40,
		"baked, the Blender-made pieces merge with the rest (%d left, %d draws) and the headers colour with heat" % [left, s["draws"] - s["rider_draws"]])
	bake.free()
	# A can on the left is the right-hand one mirrored, its triangles still facing out.
	var path := BlenderParts.can_path("turnout")
	var at := BlenderParts.placed(path, BlenderParts.can_xform(Vector3(-0.15, 0.3, 0.2), Vector3(-0.16, 0.25, 0.7), 0.05, "turnout"))
	var right := BlenderParts.can_xform(Vector3(0.15, 0.3, 0.2), Vector3(0.16, 0.25, 0.7), 0.05, "turnout")
	var flip: Mesh = at[0][0][0]
	var a: Vector3 = (at[1] as Transform3D) * flip.get_aabb().get_center()
	var b: Vector3 = right * (BlenderParts.surfaces(path)[0][0] as Mesh).get_aabb().get_center()
	check((at[1] as Transform3D).basis.determinant() > 0.0 and absf(a.x + b.x) < 0.002 and absf(a.z - b.z) < 0.002,
		"a can on the left is the right one mirrored, drawn the right way out")


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
