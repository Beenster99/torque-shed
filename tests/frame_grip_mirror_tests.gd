extends RefCounted
## Simon's v0.39 round on the bike's looks: slimmer twin-spar and carbon monocoque beams, the
## grips on every handlebar's own ends, and mirror stalks that meet the back of the head and keep
## off the bars. Run from tests/run_tests.gd (its _test_fgm_* functions hand over to these).
## The geometry is checked by the numbers, in the model's own spaces.

var t: Node   # the test runner: check(), get_tree()

const STEP := 1.0 / 60.0
## The deepest a spar frame's beam may be now, top to bottom (m); it was 0.198.
const SPAR_DEPTH_MAX := 0.13
## The widest a carbon monocoque's beam may be now (m); it was 0.144.
const MONO_WIDTH_MAX := 0.1
## A spread of bars for the mirrors: wide, narrow, clip-ons, apes, buckhorns, braced MX, z and
## drop bars, each a different shape.
const MIRROR_BARS := ["flat_bar", "clip_ons", "race_ti_clips", "ape_hangers", "chopper_tall_apes", "chopper_buckhorn",
	"cruiser_beach_bar", "cafe_ace_bar", "clubman_bar", "mx_tall", "mx_braced_blue", "bobber_z_bar", "bobber_t_bar",
	"bobber_drag_risers", "tourer_pullback", "roader_wide"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A model of `parts` over the stock bike of `style` (sorted out like a real build), in the
## runner's tree.
func _model(style: String, parts: Dictionary) -> BikeModel:
	var build: Dictionary = Contracts.style_build(style)
	build.merge(parts, true)
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(BikeBuild.new(PartsDB.sanitize_build(BikeBuild.sensible_fork(build, 7))))
	return m


## The slot's meshes named `name`.
static func _named(m: BikeModel, slot: String, name: String) -> Array:
	return (m._slot_meshes.get(slot, []) as Array).filter(func(mi): return is_instance_valid(mi) and str((mi as Node).name).rstrip("0123456789") == name)


## The line a tube from BikeModel._tube runs along: [one end, the other], in its parent's space.
static func _tube_ends(mi: MeshInstance3D) -> Array:
	var h := float((mi.mesh as CylinderMesh).height) * 0.5
	var along := mi.basis.y.normalized() * h
	return [mi.position - along, mi.position + along]


## Every twin-spar frame and every carbon monocoque: the beams are slimmer at their deepest than
## before (and the monocoque's narrower), each still starting inside the head stock and ending on
## the top of its pivot plate.
func test_frames() -> void:
	var bad := []
	var seen := []
	for id in PartsDB.by_kind["frame"]:
		var p := PartsDB.get_part(id)
		if str(p.get("style", "")) != "spar":
			continue
		var carbon := str(p.get("material", "")) == "carbon"
		seen.append(id)
		var m := _model(str((p["styles"] as Array)[0]), {"frame": id})
		var beams := _named(m, "frame", "SparBeam")
		# (In the Rig built look a beam can bend up over a tall top end: two straight lengths a
		# side, run end to end from the head stock to the pivot plate.)
		var sides := {}
		var line := []
		for mi: MeshInstance3D in beams:
			var r := float((mi.mesh as CylinderMesh).top_radius)
			var wide := 2.0 * r * mi.basis.x.length()
			var deep := 2.0 * r * mi.basis.z.length()
			line.append("%.0f x %.0f mm" % [wide * 1000.0, deep * 1000.0])
			if maxf(wide, deep) > SPAR_DEPTH_MAX:
				bad.append("%s: a beam %.0f mm at its thickest" % [id, maxf(wide, deep) * 1000.0])
			if carbon and wide > MONO_WIDTH_MAX:
				bad.append("%s: monocoque %.0f mm wide" % [id, wide * 1000.0])
			var ends := _tube_ends(mi)
			var side := signf((ends[0] as Vector3).x + (ends[1] as Vector3).x)
			if not sides.has(side):
				sides[side] = {"front": ends[0], "back": ends[0], "wide": wide, "n": 0}
			var sd: Dictionary = sides[side]
			sd["n"] = int(sd["n"]) + 1
			for e: Vector3 in ends:
				if e.z < (sd["front"] as Vector3).z:
					sd["front"] = e
					sd["wide"] = wide
				if e.z > (sd["back"] as Vector3).z:
					sd["back"] = e
		if sides.size() != 2 or sides.values().any(func(sd): return int(sd["n"]) > (2 if not m.rig.is_empty() else 1)):
			bad.append("%s: %d beams" % [id, beams.size()])
		for side in sides:
			var front: Vector3 = sides[side]["front"]
			var back: Vector3 = sides[side]["back"]
			# Into the head stock: the beam's inner face reaches well inside the head tube (0.038 round).
			var axis := m._steer_axis
			var off := front - m._head_bottom
			var from_axis := (off - axis * off.dot(axis)).length()
			if from_axis - float(sides[side]["wide"]) * 0.5 > 0.03:
				bad.append("%s: beam's inner face %.0f mm out from the head stock's axis" % [id, (from_axis - float(sides[side]["wide"]) * 0.5) * 1000.0])
			var plate_top := m._pivot + Vector3(0.12 * float(side), 0.1, 0.0)
			if back.distance_to(plate_top) > 0.005:
				bad.append("%s: beam ends %.0f mm off its pivot plate" % [id, back.distance_to(plate_top) * 1000.0])
		print("    %s%s: %s" % [id, " (carbon)" if carbon else "", ", ".join(line)])
		m.free()
	check(seen.size() >= 6, "every twin-spar and carbon monocoque frame is checked (%d)" % seen.size())
	check(bad.is_empty(), "spar beams at most %.0f mm deep (monocoques %.0f mm wide), meeting the head stock and pivot plates %s"
		% [SPAR_DEPTH_MAX * 1000.0, MONO_WIDTH_MAX * 1000.0, str(bad)])


## Every handlebar: each grip sits on its own bar end, along the bar's axis there, on a run of bar
## that's straight under it (and under the switches and levers); the controls sit on the bar's
## line; and the rider's hands are on the grips, still with the bars turned.
func test_grips() -> void:
	var bad := []
	var ids: Array = PartsDB.by_kind["handlebars"]
	for id in ids:
		var p := PartsDB.get_part(id)
		var m := _model(str((p["styles"] as Array)[0]), {"handlebars": id})
		var why := []
		var grips := _named(m, "handlebars", "Grip")
		if grips.size() != 2:
			why.append("%d grips" % grips.size())
		for mi: MeshInstance3D in grips:
			var side := signf(mi.position.x)
			var end := m.bar_end(side)
			var out := m.bar_out(side)
			var ends := _tube_ends(mi)
			var outer: Vector3 = ends[0] if absf((ends[0] as Vector3).x) > absf((ends[1] as Vector3).x) else ends[1]
			var inner: Vector3 = ends[1] if outer == ends[0] else ends[0]
			if outer.distance_to(end) > 0.002:
				why.append("grip %.1f mm off the bar end" % (outer.distance_to(end) * 1000.0))
			var angle := rad_to_deg((outer - inner).angle_to(out))
			if angle > 1.0:
				why.append("grip %.1f degrees off the bar" % angle)
			# The bar under it, as drawn, is straight and on the grip's axis.
			for k in 11:
				var q: Vector3 = inner.lerp(outer, k / 10.0)
				if m.bar_distance(q) > 0.0015:
					why.append("bar %.1f mm off the grip's axis" % (m.bar_distance(q) * 1000.0))
					break
			var grip := m._grip_r if side > 0.0 else m._grip_l
			if Geometry3D.get_closest_point_to_segment(grip, inner, outer).distance_to(grip) > 0.0005:
				why.append("hand point off the grip")
		# The bar runs straight for the levers too: the line within BAR_STRAIGHT of the end.
		var line := m.bar_line()
		var tip := m.bar_end(1.0)
		for q in line:
			if q.distance_to(tip) < BikeModel.BAR_STRAIGHT - 0.005:
				var off := q - tip
				var bow := (off - m.bar_out(1.0) * off.dot(m.bar_out(1.0))).length()
				if bow > 0.001:
					why.append("bar bends %.1f mm under the levers" % (bow * 1000.0))
					break
		for n in ["SwitchGear", "Throttle", "BarEnd"]:
			for piece in m._slot_meshes["handlebars"].filter(func(mi): return is_instance_valid(mi) and str((mi as Node).name).rstrip("0123456789") == n):
				var at: Vector3 = (piece as Node3D).position
				var d := m.bar_distance(at)
				if n == "BarEnd":
					d = (at - m.bar_end(signf(at.x))).cross(m.bar_out(signf(at.x))).length()
				if d > 0.002:
					why.append("%s %.1f mm off the bar's line" % [n, d * 1000.0])
		# Hands on the grips, sat still and with the bars turned.
		for steer in [0.0, 0.3]:
			m._steer_node.basis = Basis(m._steer_axis, -steer)
			for i in 30:
				m.update_rider(0.0, steer, 5.0, 0.0, STEP)
			var hands := _hands_off(m)
			if hands > 0.03:
				why.append("hands %.0f mm off the grips (steer %.1f)" % [hands * 1000.0, steer])
		if not why.is_empty():
			bad.append("%s: %s" % [id, ", ".join(why)])
		m.free()
		await t.get_tree().process_frame
	check(ids.size() >= 40, "all %d handlebars are checked" % ids.size())
	check(bad.is_empty(), "on every handlebar the grips sit on the bar ends along the bar, on straight bar, the switches on its line and the hands on the grips %s" % str(bad))


## How far each hand is off its grip (m), the worse of the two (as tests/rider_style_tests.gd has it).
static func _hands_off(m: BikeModel) -> float:
	var worst := 0.0
	for side in m._arm_at:
		var a: Dictionary = m._arm_at[side]
		var grip: Vector3 = a["grip"]
		var hand: Vector3 = m._rider.transform * ((a["node"] as Node3D).transform * (m._head + grip - (a["sh"] as Vector3)))
		worst = maxf(worst, hand.distance_to(m._steer_node.transform * grip))
	return worst


## Whether point `p` (in the head's space, see _mirror_on_stalk) is inside a mirror head of
## `half` (its radius both ways for a round one), padded by `pad`.
static func _in_head(p: Vector3, half: Vector2, round_head: bool, pad: float) -> bool:
	if p.z < -BikeModel.MIRROR_DEPTH * 0.5 - pad or p.z > BikeModel.MIRROR_DEPTH * 0.5 + 0.003 + pad:
		return false
	if round_head:
		return Vector2(p.x, p.y).length() < half.x + pad
	return absf(p.x) < half.x + pad and absf(p.y) < half.y + pad


## Every pair of mirrors on a spread of bars (and the fairing pods on the fairings they bolt to):
## the stalk ends inside the back of the head, comes to it from behind the glass without passing
## through the head, and keeps clear of the bar, the grips and the brake master cylinder;
## bar-end mirrors' stalks stay out past the end of the bar.
func test_mirrors() -> void:
	var bad := []
	var tried := 0
	var rounds := 0
	for id in PartsDB.by_kind["mirrors"]:
		var p := PartsDB.get_part(id)
		var style := str((p["styles"] as Array)[0])
		var setups := []
		if str(p.get("style", "")) == "fairing":
			for f in ["half_fairing", "touring_fairing", "race_fairing", "flyscreen", "bikini_fairing"]:
				setups.append({"mirrors": id, "fairing": f})
		else:
			for bars in MIRROR_BARS:
				setups.append({"mirrors": id, "handlebars": bars})
		for parts in setups:
			var m := _model(style, parts)
			var what := "%s on %s" % [id, parts.get("handlebars", parts.get("fairing", ""))]
			var why := _mirror_faults(m, str(p.get("style", "")))
			tried += 1
			for mr in m.mirrors:
				if mr["round_rim"]:
					rounds += 1
			if not why.is_empty():
				bad.append("%s: %s" % [what, ", ".join(why)])
			m.free()
		await t.get_tree().process_frame
	print("    %d mirror and bar pairs, %d stalks went round a rim" % [tried, rounds])
	check(tried > 150 and bad.is_empty(), "every mirror's stalk meets the back of its head, never through the glass, and keeps off the bars (%d pairs) %s" % [tried, str(bad)])
	check(rounds == 0, "no stalk has to go round the rim of its mirror to get behind it (%d)" % rounds)


## Whether a stalk `r` thick from `a` to `b` passes through any of the triangles in `faces`: its
## middle line or any of four lines along its skin.
static func _through(a: Vector3, b: Vector3, r: float, faces: PackedVector3Array) -> bool:
	var d := (b - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := d.cross(u)
	for off in [Vector3.ZERO, u * r, -u * r, w * r, -w * r]:
		for i in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(a + off, b + off, faces[i], faces[i + 1], faces[i + 2]) != null:
				return true
	return false


## What's wrong with the mirrors on `m` (see test_mirrors).
func _mirror_faults(m: BikeModel, kind: String) -> Array:
	var why := []
	if m.mirrors.size() != 2:
		return ["%d mirrors" % m.mirrors.size()]
	var master := []   # the code-built brake master cylinder's pieces, as boxes in steering space
	var shaped := PackedVector3Array()   # and a Blender-made one's triangles (its box is far looser than its shape)
	for mi in m._slot_meshes.get("front_master", []):
		if is_instance_valid(mi) and mi is MeshInstance3D and (mi as Node).get_parent() == m._steer_node and not str((mi as Node).name).begins_with("Brake"):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh is ArrayMesh:
				var xf := (mi as MeshInstance3D).transform
				for v in mesh.get_faces():
					shaped.append(xf * v)
			else:
				master.append((mi as MeshInstance3D).transform * mesh.get_aabb())
	for mr: Dictionary in m.mirrors:
		var path: PackedVector3Array = mr["stalk"]
		var r := float(mr["stalk_r"])
		var head: Transform3D = mr["head"]
		var half: Vector2 = mr["half"]
		var round_head := (mr["size"] as Vector2).x == (mr["size"] as Vector2).y
		var to_head := head.affine_inverse()
		var stem_end := to_head * path[path.size() - 1]
		var knuckle := to_head * path[path.size() - 2]
		# The stem ends inside the shell, behind the glass, within the head's outline.
		if stem_end.z > BikeModel.MIRROR_DEPTH * 0.5 - 0.002 or stem_end.z < -BikeModel.MIRROR_DEPTH * 0.5 or not _in_head(stem_end, half, round_head, 0.0):
			why.append("stem ends at %s in the head" % str(stem_end))
		if knuckle.z > -BikeModel.MIRROR_DEPTH * 0.5 - r * 1.5:
			why.append("ball joint not behind the head")
		# The stalk up to the joint never enters the head.
		for i in path.size() - 2:
			for k in 21:
				var q := to_head * path[i].lerp(path[i + 1], k / 20.0)
				if _in_head(q, half, round_head, r - 0.001):
					why.append("stalk runs into the head")
					break
		if not mr["on_bars"]:
			continue
		# The head itself keeps off the bar and the grips: round its rim.
		var reach := BikeModel._mirror_reach(half * 2.0 if not round_head else half)
		for k in 16:
			var a := TAU * k / 16.0
			var q := head * Vector3(cos(a) * reach, sin(a) * reach, 0.0)
			if m.bar_distance(q) < BikeModel.GRIP_R + 0.003:
				why.append("the head %.0f mm from the bar's middle" % (m.bar_distance(q) * 1000.0))
				break
		var side := signf(path[0].x)
		var run := 0.0
		for i in path.size() - 2:
			var seg := path[i].distance_to(path[i + 1])
			for k in 21:
				var q := path[i].lerp(path[i + 1], k / 20.0)
				var along := run + seg * k / 20.0
				if kind == "bar_end":
					if (q - m.bar_end(side)).dot(m.bar_out(side)) < 0.015:
						why.append("stalk back alongside the bar")
						break
				elif along > 0.03 and m.bar_distance(q) < BikeModel.GRIP_R + r + 0.002:
					why.append("stalk %.0f mm from the bar's middle" % (m.bar_distance(q) * 1000.0))
					break
				if side > 0.0:
					for box: AABB in master:
						if box.grow(r).has_point(q):
							why.append("stalk through the brake master cylinder at %s (box %s)" % [q, box])
							break
			run += seg
			if side > 0.0 and not shaped.is_empty() and _through(path[i], path[i + 1], r, shaped):
				why.append("stalk through the brake master cylinder from %s to %s" % [path[i], path[i + 1]])
	return why
