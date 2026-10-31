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


## Every fairing in the catalogue, on a sports bike in the new look, keeps the shape the code lays
## out round the bike, given a real thickness: its shell and screen are drawn with the Blender-made
## edge section rolled round their edges, hugging the code's outline (within a few millimetres),
## and its panels are held on round their edges, a race fairing's by quarter-turn fasteners and a
## road one's by screws in rubber well nuts; in Classic the fairing is the code's alone.
func test_fairings() -> void:
	var out := []
	var base := Contracts.style_build("sport")
	for id in PartsDB.by_kind["fairing"]:
		var parts := base.duplicate()
		parts["fairing"] = id
		var race := str(PartsDB.get_part(str(id)).get("style", "")) == "race"
		for look in [BikeLook.NEW, BikeLook.CLASSIC]:
			var m := BikeModel.new()
			m.look = look
			t.add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
			var tags := {}
			var shells := 0
			for mi in m._slot_meshes.get("fairing", []):
				if not (mi is MeshInstance3D) or not _blender_made(mi):
					continue
				var mesh := (mi as MeshInstance3D).mesh
				if look == BikeLook.CLASSIC:
					out.append("%s: Blender-made in Classic" % id)
					break
				for k in mesh.get_surface_count():
					tags[BlenderParts.tag_of(mesh.surface_get_material(k))] = true
				if str(mi.name).begins_with("Fastener"):
					continue
				shells += 1
				var code: AABB = mesh.custom_aabb
				var real: AABB = mesh.get_aabb()
				var d := maxf(((real.position - code.position).abs()).x, maxf(((real.position - code.position).abs()).y, ((real.position - code.position).abs()).z))
				d = maxf(d, maxf(((real.end - code.end).abs()).x, maxf(((real.end - code.end).abs()).y, ((real.end - code.end).abs()).z)))
				if code.size == Vector3.ZERO or d > 0.006:
					out.append("%s %s: %.3f m off the code's outline" % [id, mi.name, d])
			if look == BikeLook.NEW:
				for name in ["FairingShell", "Screen"]:
					var named := (m._slot_meshes.get("fairing", []) as Array).filter(func(mi): return is_instance_valid(mi) and str(mi.name) == name)
					if named.any(func(mi): return not _blender_made(mi)):
						out.append("%s: its %s is the code's" % [id, name])
				if shells == 0:
					out.append("%s: no thick panels" % id)
				if not tags.has("rubber" if not race else "chrome"):
					out.append("%s: no %s fasteners %s" % [id, "quarter-turn" if race else "well-nut", tags.keys()])
			m.free()
	check(out.is_empty(), "every fairing in the new look is drawn thick, its Blender-made edges round the code's shape, held on by its own kind of fastener; Classic's is the code's %s" % str(out.slice(0, 6)))

## Every frame in the catalogue, on a bike in the new look, keeps the layout the code bends round
## the bike: its round tubes are the Blender-made tube swept along the same lines, each joint where
## a tube butts into a thicker one is welded (a bead sitting on the tube, not off in the air), the
## head stock has its bearing cups in both ends, and the battery box, the frame's own footpegs and a
## plain swingarm's box-section arms are Blender-made; in Classic the frame is the code's alone.
func test_frames() -> void:
	var out := []
	var counts := {}
	var base := Contracts.style_build("classic")
	base["rearsets"] = "none"
	for id in PartsDB.by_kind["frame"]:
		var parts := base.duplicate()
		parts["frame"] = id
		for look in [BikeLook.NEW, BikeLook.CLASSIC]:
			var m := BikeModel.new()
			m.look = look
			t.add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
			var named := {}
			var code_tubes := 0
			for mi in m._slot_meshes.get("frame", []):
				if not (mi is MeshInstance3D):
					continue
				var key := str(mi.name).rstrip("0123456789").trim_prefix("@MeshInstance3D@")
				named[key] = int(named.get(key, 0)) + 1
				# (A tube, not a short lug or boss.)
				var cyl := (mi as MeshInstance3D).mesh as CylinderMesh
				if cyl != null and cyl.height > 0.05 and (mi as MeshInstance3D).scale.is_equal_approx(Vector3.ONE):
					code_tubes += 1
				if str(mi.name).begins_with("Footpeg") and BlenderParts.tag_of((mi as MeshInstance3D).mesh.surface_get_material(0)) == "rubber":
					named["peg"] = int(named.get("peg", 0)) + 1
				if look == BikeLook.CLASSIC and _blender_made(mi):
					out.append("%s: Blender-made in Classic" % id)
					break
				if look == BikeLook.NEW and str(mi.name).begins_with("Weld"):
					# Each bead sits on one of the frame's tube lines, about its radius out.
					var verts := (mi as MeshInstance3D).mesh.get_faces()
					for k in range(0, verts.size(), 97):
						var near := INF
						for rail in m._rails:
							near = minf(near, BikeModel._rail_distance(rail, verts[k]) - float(rail["r"]))
						if near > 0.012:
							out.append("%s: a weld %.3f m off its tube" % [id, near])
							break
			var fp := PartsDB.get_part(str(id))
			# (A frame of cast beams, a perimeter's, a spar's or a cast trestle's, has no tubes butting
			# into each other to weld.)
			var cast := str(fp.get("style", "")) in ["perimeter", "spar"] or bool((fp.get("look", {}) as Dictionary).get("cast", false))
			if look == BikeLook.NEW and not cast:
				counts[id] = int(named.get("Weld", 0))
			if look == BikeLook.NEW:
				if code_tubes > 0:
					out.append("%s: %d of the code's tubes" % [id, code_tubes])
				if int(named.get("BatteryBox", 0)) == 0 and not str(PartsDB.get_part(str(id)).get("style", "")) in ["softail", "chopper"]:
					out.append("%s: no battery box" % id)
				if int(named.get("peg", 0)) != 2:
					out.append("%s: %d footpegs" % [id, int(named.get("peg", 0))])
				var cups := 0
				for mi in m._slot_meshes.get("frame", []):
					if is_instance_valid(mi) and _blender_made(mi) and BlenderParts.tag_of((mi as MeshInstance3D).mesh.surface_get_material(0)) == "raw_steel":
						cups += 1
				if cups < 2:
					out.append("%s: no bearing cups" % id)
				if m._arm_type() == "box" and int(named.get("BoxArm", 0)) == 0:
					out.append("%s: the code's box swingarm" % id)
			m.free()
	var welded := counts.values().filter(func(c): return c > 0).size()
	check(out.is_empty() and welded == counts.size(), "every frame in the new look is Blender-made tube on the code's lines, welded where its tubes meet (%d of %d tubular frames welded %s), with its head stock's bearing cups, battery box, footpegs and swingarm; Classic's is the code's %s" % [welded, counts.size(), counts.keys().filter(func(k): return counts[k] == 0), str(out.slice(0, 6))])


## Every handlebar, front master cylinder and set of rearsets in the catalogue, on a bike in the new
## look, keeps the code's layout with Blender-made pieces on it: the bar tube swept along the
## bar's own line, its grips, bar-end weights, switch gear, throttle, clutch perch and lever, the
## master cylinder and brake lever, and each footrest's peg, board or cleat; in Classic they're
## the code's alone.
func test_controls() -> void:
	var out := []
	var base := Contracts.style_build("classic")
	var builds := []
	for slot in ["handlebars", "front_master", "rearsets"]:
		for id in PartsDB.by_kind.get(PartsDB.SLOT_KIND.get(slot, slot), []):
			var parts := base.duplicate()
			parts[slot] = id
			builds.append([slot, id, parts])
	for b in builds:
		for look in [BikeLook.NEW, BikeLook.CLASSIC]:
			var m := BikeModel.new()
			m.look = look
			t.add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(b[2])))
			var made := {}
			for slot in ["handlebars", "front_master", "rearsets"]:
				for mi in m._slot_meshes.get(slot, []):
					if not _blender_made(mi):
						continue
					if look == BikeLook.CLASSIC:
						out.append("%s: Blender-made in Classic" % b[1])
						break
					var key := str(mi.name).rstrip("0123456789")
					made[key] = int(made.get(key, 0)) + 1
			if look == BikeLook.NEW:
				var want := {"Grip": 2, "BarEnd": 2, "SwitchGear": 1, "Throttle": 1, "ClutchLever": 1, "ClutchPerch": 1}
				if m.is_fitted("front_master") and not m._slot_meshes.get("front_master", []).is_empty():
					want["BrakeLever"] = 1
					want["Reservoir"] = 1
				if m.is_fitted("rearsets") and not m._slot_meshes.get("rearsets", []).is_empty():
					want["Footpeg"] = 2
				for k in want:
					if int(made.get(k, 0)) < int(want[k]):
						out.append("%s %s: %d of %d %s" % [b[0], b[1], int(made.get(k, 0)), want[k], k])
				var code_tubes := 0
				for mi in m._slot_meshes.get("handlebars", []):
					if mi is MeshInstance3D and ((mi as MeshInstance3D).mesh is CylinderMesh) and ((mi as MeshInstance3D).mesh as CylinderMesh).height > 0.05:
						code_tubes += 1
				if code_tubes > 0:
					out.append("%s: %d of the code's bar tubes" % [b[1], code_tubes])
			m.free()
	check(out.is_empty() and builds.size() > 20, "every handlebar, front master and set of rearsets (%d) in the new look wears its Blender-made bar, grips, switch gear, levers, master cylinder and pegs on the code's layout; Classic's are the code's %s" % [builds.size(), str(out.slice(0, 6))])

## The headlights (wave 4c): in the new look every lamp but the nacelle's cowl and the triple's
## angular pair wears its Blender-made body and glass, each glass still the lamp's own lit
## material (so it lights with the switch) and named Lens as the code's, in the code-built one's
## place; Classic's are the code's.
func test_headlights() -> void:
	var out := []
	var base := Contracts.style_build("naked")
	base["fairing"] = "none"
	var ids: Array = PartsDB.by_kind.get("headlight", [])
	for id in ids:
		var parts := base.duplicate()
		parts["headlight"] = id
		var models := {}
		for k in ["classic", "code", "new"]:
			var m := BikeModel.new()
			m.look = BikeLook.CLASSIC if k == "classic" else BikeLook.NEW
			BlenderParts.on = k != "code"
			t.add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
			models[k] = m
		BlenderParts.on = true
		var m: BikeModel = models["new"]
		var made := (m._slot_meshes.get("headlight", []) as Array).filter(_blender_made)
		var lamp := str(m._build.part("headlight").get("look", {}).get("lamp", m._build.part("headlight").get("style", "round")))
		if (models["classic"] as BikeModel)._slot_meshes.get("headlight", []).any(_blender_made):
			out.append("%s Blender-made in Classic" % id)
		if made.is_empty() != (lamp in ["nacelle", "triple"]):
			out.append("%s (%s): %d Blender-made pieces" % [id, lamp, made.size()])
		var heads: Array = m._lamps.filter(func(l): return l["group"] == "head").map(func(l): return l["mat"])
		var glass := made.filter(func(mi): return str((mi as Node).name).begins_with("Lens"))
		if not made.is_empty() and (glass.is_empty() or not glass.all(func(mi): return heads.has((mi as MeshInstance3D).material_override))):
			out.append("%s: %d glasses, not all the lamp's" % [id, glass.size()])
		var a := (models["code"] as BikeModel).slot_bounds("headlight")
		var b := m.slot_bounds("headlight")
		var d := maxf((a.position - b.position).abs()[(a.position - b.position).abs().max_axis_index()],
			(a.end - b.end).abs()[(a.end - b.end).abs().max_axis_index()])
		if d > LOADED_GIVE:
			out.append("%s %.3f m off" % [id, d])
		for k in models:
			(models[k] as Node).free()
	check(out.is_empty() and ids.size() > 20, "every headlight (%d) in the new look wears its Blender-made lamp, its glass the lamp's lit one, in the code-built one's place; Classic's are the code's %s" % [ids.size(), str(out.slice(0, 6))])


## The small lamps and the clocks (wave 4d): in the new look every indicator, rear light, set of
## clocks and pair of mirrors wears its Blender-made housing in the code-built one's place, the
## rear light's glass still the tail lamp's (named TailLight), the clocks with their needles and
## the mirrors with their glasses as before; Classic's are the code's.
func test_lamps() -> void:
	var out := []
	var builds := 0
	var base := Contracts.style_build("classic")
	for slot in ["indicators", "tail", "dashboard", "mirrors"]:
		for id in PartsDB.by_kind.get(slot, []):
			var parts := base.duplicate()
			parts[slot] = id
			var models := {}
			for k in ["classic", "code", "new"]:
				var m := BikeModel.new()
				m.look = BikeLook.CLASSIC if k == "classic" else BikeLook.NEW
				BlenderParts.on = k != "code"
				t.add_child(m)
				m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
				models[k] = m
			BlenderParts.on = true
			builds += 1
			var m: BikeModel = models["new"]
			var code: BikeModel = models["code"]
			if str(m._build.parts.get(slot, "")) != str(id):
				for k in models:
					(models[k] as Node).free()
				continue
			var made := (m._slot_meshes.get(slot, []) as Array).filter(_blender_made)
			if (models["classic"] as BikeModel)._slot_meshes.get(slot, []).any(_blender_made):
				out.append("%s Blender-made in Classic" % id)
			match slot:
				"tail":
					var light: Node = m.find_child("TailLight", true, false)
					var tails: Array = m._lamps.filter(func(l): return l["group"] == "tail").map(func(l): return l["mat"])
					if light == null or not _blender_made(light) or not tails.has((light as MeshInstance3D).material_override):
						out.append("%s: its rear light" % id)
				"dashboard":
					if made.is_empty() or m._needles.size() != code._needles.size():
						out.append("%s: %d Blender-made, %d needles of %d" % [id, made.size(), m._needles.size(), code._needles.size()])
				"mirrors":
					var shells := m.find_children("MirrorShell*", "", true, false)
					if shells.size() < m.mirrors.size() or m.mirrors.size() != code.mirrors.size() or m.mirrors.is_empty():
						out.append("%s: %d shells, %d mirrors of %d" % [id, shells.size(), m.mirrors.size(), code.mirrors.size()])
				_:
					if made.size() < 4:
						out.append("%s: %d Blender-made" % [id, made.size()])
			var a := code.slot_bounds(slot)
			var b := m.slot_bounds(slot)
			var d := maxf((a.position - b.position).abs()[(a.position - b.position).abs().max_axis_index()],
				(a.end - b.end).abs()[(a.end - b.end).abs().max_axis_index()])
			if d > LOADED_GIVE:
				out.append("%s %.3f m off" % [id, d])
			for k in models:
				(models[k] as Node).free()
	check(out.is_empty() and builds > 30, "every indicator, rear light, set of clocks and pair of mirrors (%d) in the new look wears its Blender-made housing in the code-built one's place, lights, needles and glasses kept; Classic's are the code's %s" % [builds, str(out.slice(0, 6))])


## The small parts (wave 4e): in the new look every final drive's sprockets, the chain, both
## stands, every horn and the rear master cylinder wear their Blender-made shapes in the
## code-built ones' place; Classic's are the code's.
func test_small_parts() -> void:
	var out := []
	var builds := 0
	var base := Contracts.style_build("classic")
	base["centre_stand"] = PartsDB.by_kind["centre_stand"][0]
	for slot in ["final_drive", "chain", "side_stand", "centre_stand", "horn"]:
		for id in PartsDB.by_kind.get(slot, []):
			var parts := base.duplicate()
			parts[slot] = id
			var models := {}
			for k in ["classic", "code", "new"]:
				var m := BikeModel.new()
				m.look = BikeLook.CLASSIC if k == "classic" else BikeLook.NEW
				BlenderParts.on = k != "code"
				t.add_child(m)
				m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
				models[k] = m
			BlenderParts.on = true
			builds += 1
			var m: BikeModel = models["new"]
			for s in [slot, "rear_master"]:
				if (m._slot_meshes.get(s, []) as Array).filter(_blender_made).is_empty() and not (models["code"] as BikeModel)._slot_meshes.get(s, []).is_empty():
					out.append("%s %s: none Blender-made" % [id, s])
				if (models["classic"] as BikeModel)._slot_meshes.get(s, []).any(_blender_made):
					out.append("%s %s: Blender-made in Classic" % [id, s])
				var a := (models["code"] as BikeModel).slot_bounds(s)
				var b := m.slot_bounds(s)
				var d := maxf((a.position - b.position).abs()[(a.position - b.position).abs().max_axis_index()],
					(a.end - b.end).abs()[(a.end - b.end).abs().max_axis_index()])
				if d > LOADED_GIVE:
					out.append("%s %s %.3f m off" % [id, s, d])
			for k in models:
				(models[k] as Node).free()
	check(out.is_empty() and builds > 15, "every final drive, chain, stand and horn (%d), and the rear master cylinder, in the new look wear their Blender-made shapes in the code-built ones' place; Classic's are the code's %s" % [builds, str(out.slice(0, 6))])


## The add-ons (wave 4f): in the new look every pannier and top box (but the roll and throw-over
## bags), fog lamp, radiator and oil cooler, and the rotary and friction steering dampers wear
## their Blender-made shapes in the code-built ones' place, the fog lamps' glasses still lit as
## fog lamps; Classic's are the code's.
func test_add_ons() -> void:
	var out := []
	var builds := 0
	var base := Contracts.style_build("tourer")
	for slot in ["panniers", "top_box", "fog_lights", "cooling", "steering_damper"]:
		for id in PartsDB.by_kind.get(slot, []):
			var p := PartsDB.get_part(id)
			var style := str(p.get("look", {}).get("shape", p.get("style", "")))
			var parts := base.duplicate()
			parts[slot] = id
			if slot == "cooling":
				parts["engine"] = "four_1000"
			var models := {}
			for k in ["classic", "code", "new"]:
				var m := BikeModel.new()
				m.look = BikeLook.CLASSIC if k == "classic" else BikeLook.NEW
				BlenderParts.on = k != "code"
				t.add_child(m)
				m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
				models[k] = m
			BlenderParts.on = true
			var m: BikeModel = models["new"]
			if str(m._build.parts.get(slot, "")) != str(id):
				for k in models:
					(models[k] as Node).free()
				continue
			builds += 1
			var expect := not (style in ["roll", "soft", "fins", "twin", "linear"])
			var made := (m._slot_meshes.get(slot, []) as Array).filter(_blender_made)
			if expect and made.is_empty():
				out.append("%s (%s): none Blender-made" % [id, style])
			if (models["classic"] as BikeModel)._slot_meshes.get(slot, []).any(_blender_made):
				out.append("%s: Blender-made in Classic" % id)
			if slot == "fog_lights":
				var fogs: Array = m._lamps.filter(func(l): return l["group"] == "fog").map(func(l): return l["mat"])
				var glass := made.filter(func(mi): return str((mi as Node).name).begins_with("FogLens"))
				if glass.is_empty() or not glass.all(func(mi): return fogs.has((mi as MeshInstance3D).material_override)):
					out.append("%s: its glasses not the fog lamps'" % id)
			var a := (models["code"] as BikeModel).slot_bounds(slot)
			var b := m.slot_bounds(slot)
			var d := maxf((a.position - b.position).abs()[(a.position - b.position).abs().max_axis_index()],
				(a.end - b.end).abs()[(a.end - b.end).abs().max_axis_index()])
			if d > LOADED_GIVE:
				out.append("%s %.3f m off" % [id, d])
			for k in models:
				(models[k] as Node).free()
	check(out.is_empty() and builds > 20, "every pannier, top box, fog lamp, radiator and steering damper (%d) in the new look wears its Blender-made shapes in the code-built one's place, the fog lamps still lit; Classic's are the code's %s" % [builds, str(out.slice(0, 6))])


## The slots the loader draws in their Blender-made shapes (waves 1 to 4 so far).
const LOADED: Array[String] = ["engine", "head", "exhaust", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre",
	"front_disc", "rear_disc", "front_caliper", "rear_caliper", "front_pads", "rear_pads", "shock", "fork", "tank", "saddle",
	"front_mudguard", "tail", "side_panels", "fairing", "frame", "handlebars", "front_master", "rearsets", "headlight", "indicators", "dashboard", "mirrors",
	"final_drive", "chain", "side_stand", "horn", "rear_master", "panniers", "top_box", "fog_lights", "cooling", "steering_damper"]


## Whether `m`'s part in `slot` (one of LOADED) has Blender-made shapes: all but the girder,
## springer and leading-link forks, a drum brake's arm and shoes (its caliper and pads), and a
## tidy tail's tray (it has no mudguard round the wheel) and the oval number boards (the race
## number's printed on the code's).
static func _expects_blender(m: BikeModel, slot: String) -> bool:
	match slot:
		"fork":
			return str(m._build.part("fork").get("style", "conventional")) in ["conventional", "usd"]
		"front_caliper", "rear_caliper", "front_pads", "rear_pads":
			return str(m._build.part(slot.get_slice("_", 0) + "_disc").get("style", "")) != "drum"
		"tail":
			return str(m._build.part("tail").get("style", "classic")) != "tidy" or m._build.part("tail").get("look", {}).has("cowl")
		"side_panels":
			return str(m._build.part("side_panels").get("style", "triangle")) != "oval"
		"headlight":
			return not str(m._build.part("headlight").get("look", {}).get("lamp", "")) in ["nacelle", "triple"]
		"cooling":
			return not str(m._build.part("cooling").get("style", "fins")) in ["fins", "twin"]
	return true
## How far (m) a Blender-made part's box may be from the code-built one's, any side.
const LOADED_GIVE := 0.035
## A tank's: the code's loft leans its end sections with the dip of its middle line, where the
## Blender-made tank's stand upright, so a deep tank's ends sit a few centimetres apart.
const TANK_GIVE := 0.05
## The most triangles a new-look bike may draw close up with its Blender-made parts on, and how
## many more than with the code-built shapes alone (the parts agreement's budgets per part,
## added up for the parts loaded so far).
const LOADED_TRIS := 150000
const LOADED_MORE := 60000


## The loader: a bike in the new look wears its Blender-made engine, top end, exhaust, wheels,
## tyres, brakes, shocks, fork, tank, seat, mudguards, tail, side panels, fairing, frame, bars and controls where the code-built ones were (the wheels' turning with them), each surface in its finish on that bike, with the headers' ports
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
			if slot in LOADED and mine.is_empty() and not (models["code"] as BikeModel)._slot_meshes[slot].is_empty() and _expects_blender(m, slot):
				missing.append("%s %s" % [style, slot])
			if (models["classic"] as BikeModel)._slot_meshes[slot].any(_blender_made):
				classic_blender.append("%s %s" % [style, slot])
			# What turns with the wheel hangs from its spinning node.
			if slot.ends_with("_wheel") or slot.ends_with("_tyre") or slot.ends_with("_disc"):
				var spin: Node = m._front_wheel if slot.begins_with("front") else m._rear_wheel
				if mine.any(func(mi): return (mi as Node).get_parent() != spin):
					off.append("%s %s off its wheel" % [style, slot])
		for slot in LOADED:
			var a := (models["code"] as BikeModel).slot_bounds(slot)
			var b := m.slot_bounds(slot)
			if slot == "head":
				# (A pushrod twin's head brings its pushrod tubes, down the barrels to the cases.)
				a = AABB(Vector3(a.position.x, b.position.y, a.position.z), Vector3(a.size.x, a.end.y - b.position.y, a.size.z))
			var d := maxf((a.position - b.position).abs()[(a.position - b.position).abs().max_axis_index()],
				(a.end - b.end).abs()[(a.end - b.end).abs().max_axis_index()])
			worst[slot] = maxf(float(worst.get(slot, 0.0)), d)
			if d > (TANK_GIVE if slot == "tank" else LOADED_GIVE):
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
	# Every one of those parts in the catalogue, on a bike in the new look, is drawn.
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
	check(missing.is_empty(), "every style's new-look bike wears its Blender-made engine, top end, exhaust, wheels, tyres, brakes, shocks, fork, tank, seat, mudguards, tail, side panels, fairing, frame, bars and controls, and every one in the catalogue is drawn %s" % [missing])
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
		# (A tyre stays a mesh of its own, the sidewall lettering hanging off it, and a shock's pieces
		# move with the swingarm, as in Classic.)
		if _blender_made(mi) and (mi as Node).get_child_count() == 0 and not bake._struts.any(func(st): return st["mi"] == mi):
			left += 1
		if mesh == null or (mi as MeshInstance3D).material_override != BikeShader.material():
			continue
		var c3 = mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM3]
		if c3 is PackedFloat32Array:
			for i in range(1, (c3 as PackedFloat32Array).size(), 4):
				hot = hot or (c3 as PackedFloat32Array)[i] > 0.1
	var s: Dictionary = BikeLook.stats(bake)
	check(hot and left == 0 and s["draws"] - s["rider_draws"] <= 40 and s["tris_lod1"] <= 26000 and s["tris_lod2"] <= 22000,
		"baked, the Blender-made pieces merge with the rest (%d left, %d draws, %d and %d triangles 30 and 120 m off) and the headers colour with heat"
		% [left, s["draws"] - s["rider_draws"], s["tris_lod1"], s["tris_lod2"]])
	bake.free()
	# A Blender-made shock stays on its mounts as the swingarm moves, twin or mono, and the fork's
	# sliders go up and down with the wheel.
	var gap := 0.0
	var slides := true
	for style in ["classic", "sport", "cruiser"]:
		var m := BikeModel.new()
		m.look = BikeLook.NEW
		t.add_child(m)
		m.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style))))
		m.update_pose_from(0.0, 0.0, 0.0, 0.06, 0.09, 0.0, 0.0)
		var struts := m._struts.filter(func(st): return st.get("from_top", false))
		for st in struts:
			var mi := st["mi"] as MeshInstance3D
			var low: Vector3 = m._swingarm.transform * (st["bottom"] as Vector3)
			gap = maxf(gap, (mi.transform * Vector3(0.0, -float(st["rest"]), 0.0)).distance_to(low))
			gap = maxf(gap, mi.position.distance_to(st["top"]))
		var lower: Array = m._slot_meshes["fork"].filter(func(mi): return _blender_made(mi) and (mi as Node).get_parent() == m._front_hub)
		slides = slides and not struts.is_empty() and (not lower.is_empty() or not _expects_blender(m, "fork"))
		m.free()
	check(slides and gap < 0.002, "a Blender shock stays on both its mounts as the arm swings (%.1f mm off at worst), and the fork's sliders ride on the wheel" % [gap * 1000.0])
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
