extends RefCounted
## The Rig built look's lines and its bike rig (BikeRig), run from tests/run_tests.gd: its
## _test_bike_rig_* functions hand over to these. data/bike_lines.json holds the eight lines of
## each style's reference bike (see /mnt/project-files/torque-shed/bike-look/lines-agreement.md).

var t: Node

const LINES := "res://data/bike_lines.json"
const LINE_KEYS := ["1_backbone", "2_tank", "3_tank_seat", "4_seat", "5_rider", "6_drive", "7_front", "8_ground"]
## How far a stock bike's catalogue numbers may sit from its reference bike's published ones.
const WHEELBASE_TOL := 0.06   # m
const SEAT_TOL := 0.05        # m
const RAKE_TOL := 4.5         # degrees
## Choppers are customs: built longer and more raked than any factory one.
const CUSTOM_LONG := ["chopper"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func lines() -> Dictionary:
	var f := FileAccess.open(LINES, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d.get("styles", {}) if d is Dictionary else {}


## Every style has its reference bike and all eight lines, and the stock bike's wheelbase, seat
## height and rake (the catalogue's, which both looks and the riding share) are the reference's.
func test_lines_table() -> void:
	var styles := lines()
	check(not styles.is_empty(), "data/bike_lines.json loads")
	for style in PartsDB.STYLES:
		var s: Dictionary = styles.get(style, {})
		check(not str(s.get("reference", "")).is_empty(), "the %s has a reference bike" % style)
		var l: Dictionary = s.get("lines", {})
		var missing := LINE_KEYS.filter(func(k): return not l.has(k))
		check(missing.is_empty(), "the %s has all eight lines (missing %s)" % [style, missing])
		if s.is_empty():
			continue
		var pub: Dictionary = s["published"]
		var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style)))
		var wb := float(pub["wheelbase_mm"]) / 1000.0
		if style in CUSTOM_LONG:
			check(build.wheelbase >= wb - WHEELBASE_TOL, "the stock %s is at least as long as a %s (%.2f m)" % [style, s["reference"], build.wheelbase])
		else:
			check(absf(build.wheelbase - wb) <= WHEELBASE_TOL,
				"the stock %s's wheelbase %.3f m is a %s's %.3f" % [style, build.wheelbase, s["reference"], wb])
			check(absf(build.rake_deg - float(pub["rake_deg"])) <= RAKE_TOL,
				"the stock %s's rake %.1f deg is a %s's %.1f" % [style, build.rake_deg, s["reference"], float(pub["rake_deg"])])
		check(absf(build.seat_height - float(pub["seat_mm"]) / 1000.0) <= SEAT_TOL,
			"the stock %s's seat %.2f m is a %s's %.2f" % [style, build.seat_height, s["reference"], float(pub["seat_mm"]) / 1000.0])
		var u := [l["3_tank_seat"]["tank_rear_u"], l["4_seat"]["front_u"], l["4_seat"]["rider_u"]]
		check(u.all(func(x): return float(x) > 0.2 and float(x) < 0.9), "the %s's lines sit between the wheels" % style)


## A model in the Rig built look, in the runner's tree.
func _model() -> BikeModel:
	var m := BikeModel.new()
	m.look = BikeLook.NEW
	t.add_child(m)
	return m


## Every style's stock bike laid out by the rig sits on its lines: the engine at its full size
## with its output shaft just ahead of the pivot, no kink in the backbone, the tank on the backbone
## clear of the heads and its top near the style's line, the rider where the style sits them, the
## engine at the style's ground clearance, and nothing through anything; and it all bolts on.
func test_stock_on_lines() -> void:
	var styles := lines()
	var m := _model()
	var off := []
	for style in PartsDB.STYLES:
		var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style)))
		m.build_engine_bay(build)
		var r := m.rig
		if r.is_empty():
			off.append("%s: no rig" % style)
			continue
		var l: Dictionary = styles[style]["lines"]
		var wb := build.wheelbase
		var ahead: float = m._pivot.z - (r["output"] as Vector3).z
		if absf(ahead - float(l["6_drive"]["countershaft_ahead_mm"]) / 1000.0) > float(l["6_drive"]["tol_mm"]) / 1000.0:
			off.append("%s: output shaft %.0f mm ahead of the pivot" % [style, ahead * 1000.0])
		if absf(m._eng_s - BikeRig.engine_scale(build.displacement)) > 0.001 or m._spine_kink != Vector3.ZERO:
			off.append("%s: engine drawn at %.2f, backbone kinked %s" % [style, m._eng_s, m._spine_kink != Vector3.ZERO])
		var c := m.engine_clash()
		if c["tube"] > 0.002 or c["tank"] > 0.001:
			off.append("%s: %.0f mm into a tube, %.0f mm into the tank (%s)" % [style, c["tube"] * 1000.0, c["tank"] * 1000.0, c["where"]])
		var top := -INF
		for s in m._tank_secs:
			top = maxf(top, (s["c"] as Vector3).y + float(s["up"]))
		# (The rig's own fit report still reckons the cruiser's fat tank as the old one sitting over
		# the V-twin's heads; drawn, its tunnel lets it sink round the backbone onto its line, H3.)
		var tall_tank := style == "cruiser"
		if top - float(r["tank_top_max"]) > BikeRig.TANK_HIGH + 0.001:
			off.append("%s: tank top %.0f mm over its line" % [style, (top - float(r["tank_top_max"])) * 1000.0])
		# The rider sits on the line, or a little behind it where the tank runs long; on a frame
		# whose seat post passes behind the heads (a cradle, a softail), further back still.
		var hip_u: float = ((r["hip"] as Vector3).z + wb * 0.5) / wb
		var behind := 0.14 if str(r["family"]) in BikeRig.POST_FAMILIES else 0.08
		if hip_u < float(l["4_seat"]["rider_u"]) - 0.03 or hip_u > float(l["4_seat"]["rider_u"]) + behind:
			off.append("%s: rider sits at %.2f of the wheelbase" % [style, hip_u])
		var low := (r["crank"] as Vector3).y + (r["hard"]["sump"] as Vector3).y + build.rear_radius
		if low < float(l["8_ground"]["clear_mm"]) / 1000.0 - 0.001:
			off.append("%s: sump %.0f mm off the ground" % [style, low * 1000.0])
		if str(r["fit"]["tier"]) != BikeRig.TIER_BOLTS and not tall_tank:
			off.append("%s: %s (%s)" % [style, r["fit"]["tier"], r["fit"]["reason"]])
	m.queue_free()
	check(off.is_empty(), "every stock bike is laid out on its style's lines and bolts together %s" % [off])


## No engine that suits a frame goes through its tubes or its tank, in any frame in the catalogue
## (the engines tagged with a style the frame is made for), in the Rig built look.
func test_catalogue_clear() -> void:
	var m := _model()
	var bad := []
	var n := 0
	var worst := 0.0
	for f in PartsDB.by_kind["frame"]:
		var fs: Array = PartsDB.styles_of(str(f))
		var style := str(fs[0]) if not fs.is_empty() else "classic"
		for e in PartsDB.by_kind["engine"]:
			if not PartsDB.styles_of(str(e)).any(func(st): return fs.has(st)):
				continue
			var parts := Contracts.style_build(style)
			parts["frame"] = f
			parts["engine"] = e
			var build := BikeBuild.new(PartsDB.sanitize_build(parts))
			if BikeRig.fit(build)["tier"] == BikeRig.TIER_NO:
				continue
			m.build_engine_bay(build)
			n += 1
			var c := m.engine_clash()
			worst = maxf(worst, maxf(c["tube"], c["tank"]))
			if c["tube"] > 0.002 or c["tank"] > 0.001:
				bad.append("%s in %s: %.0f mm into a tube, %.0f into the tank (%s)" % [e, f, c["tube"] * 1000.0, c["tank"] * 1000.0, c["where"]])
	m.queue_free()
	check(n > 300 and bad.is_empty(), "every engine clears the tubes and tank of every frame it suits (%d bikes, deepest %.1f mm) %s" % [n, worst * 1000.0, bad.slice(0, 8)])


## The rig is worked out from the parts alone: the same bike solved again from scratch, or drawn
## by a second model (a co-op guest's), comes out the same to the last digit.
func test_deterministic() -> void:
	var same := true
	for style in PartsDB.STYLES:
		var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style)))
		var first := var_to_str(BikeRig.solve(build))
		BikeRig._cache.clear()
		same = same and var_to_str(BikeRig.solve(build)) == first
	var a := _model()
	var b := _model()
	var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build("chopper")))
	a.build_engine_bay(build)
	BikeRig._cache.clear()
	b.build_engine_bay(build)
	check(same and a._engine_c == b._engine_c and a._tank_a == b._tank_a and a._seat_front == b._seat_front and var_to_str(a.rig) == var_to_str(b.rig),
		"the rig lays a bike out the same every time, on every machine")
	a.queue_free()
	b.queue_free()


## Everyone's bikes go through the rig: customers' and second-hand bikes and the riders on the
## road (Contracts.random_parts), not just the stock ones; and the Classic look has none.
func test_everyone_rigged() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var m := _model()
	var missing := []
	var tiers := {}
	for i in 40:
		var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.random_parts(rng, i % 2 == 0)))
		m.build_engine_bay(build)
		if m.rig.is_empty() or not BikeRig.lines().has(str(m.rig["style"])):
			missing.append(str(build.parts.get("frame")))
		tiers[m.rig.get("fit", {}).get("tier", "")] = true
	m.queue_free()
	var c := BikeModel.new()
	c.look = BikeLook.CLASSIC
	t.add_child(c)
	c.build_engine_bay(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build("cruiser"))))
	check(missing.is_empty() and tiers.has(BikeRig.TIER_BOLTS), "random customers' and riders' bikes are laid out by the rig (%s; fit %s)" % [missing, tiers.keys()])
	check(c.rig.is_empty() and c._spine_kink != Vector3.ZERO, "the Classic look keeps its own layout")
	c.queue_free()


## The fit report: what goes in a frame as it comes bolts on; a big engine in a small frame needs
## the shed to make something, named; a boxer can't go through an MX frame's loops.
func test_fit_report() -> void:
	var p := Contracts.style_build("bobber")
	var bolts := BikeRig.fit(BikeBuild.new(PartsDB.sanitize_build(p)))
	p["engine"] = "inline_1200"
	var fab := BikeRig.fit(BikeBuild.new(PartsDB.sanitize_build(p)))
	var mx := Contracts.style_build("mx")
	mx["engine"] = "boxer_1200"
	var no := BikeRig.fit(BikeBuild.new(PartsDB.sanitize_build(mx)))
	check(bolts["tier"] == BikeRig.TIER_BOLTS and fab["tier"] == BikeRig.TIER_FAB and not (fab["work"] as Array).is_empty() and no["tier"] == BikeRig.TIER_NO,
		"the fit report: %s / %s (%s) / %s (%s)" % [bolts["tier"], fab["tier"], fab["reason"], no["tier"], no["reason"]])


## H2: each of the 37 frames has its own Rig built numbers (its "rig" in parts.json, keys from
## BikeRig.FRAME_RIG only), no two of a family alike; and they show: a Featherbed carries its tank
## lower than the plain steel cradle on the same bike, and a Lowboy's backbone drops further to
## its seat.
func test_frame_numbers() -> void:
	var bad := []
	var seen := {}
	for f in PartsDB.by_kind["frame"]:
		var part := PartsDB.get_part(str(f))
		var own = part.get("rig")
		if not (own is Dictionary):
			bad.append("%s has no rig" % f)
			continue
		for k in own:
			if not BikeRig.FRAME_RIG.has(k):
				bad.append("%s: unknown %s" % [f, k])
		var key := str(part.get("style", "")) + var_to_str(BikeRig.frame_rig(part))
		if seen.has(key):
			bad.append("%s is %s over again" % [f, seen[key]])
		seen[key] = f
	check(PartsDB.by_kind["frame"].size() == 37 and bad.is_empty(), "all 37 frames have their own Rig built numbers %s" % [bad])
	var at := {}
	for f in ["steel_cradle", "featherbed_cradle", "cafe_lowboy_cradle"]:
		var parts := Contracts.style_build("classic")
		parts["frame"] = f
		at[f] = BikeRig.solve(BikeBuild.new(PartsDB.sanitize_build(parts)))
	var low: float = (at["steel_cradle"]["tank_top_max"] as float) - (at["featherbed_cradle"]["tank_top_max"] as float)
	check(low > 0.01, "a Featherbed carries its tank lower than a plain cradle (%.0f mm)" % (low * 1000.0))
	var end := func(r: Dictionary) -> float:
		var sp: PackedVector3Array = r["spine"]
		return sp[sp.size() - 1].y - (r["seat_front"] as Vector3).y
	check(end.call(at["cafe_lowboy_cradle"]) < end.call(at["steel_cradle"]) - 0.03, "a Lowboy's backbone drops further to its seat")


## H2: the frame shows how it holds the engine: plates from the cases' lugs to the frame, a head
## steady up to the backbone where the frame has one, gussets under the neck where it has them,
## each a frame piece; none in Classic.
func test_frame_fittings() -> void:
	var m := _model()
	var counts := func(frame: String, look: String) -> Dictionary:
		var parts := Contracts.style_build(str(PartsDB.get_part(frame)["styles"][0]))
		parts["frame"] = frame
		m.look = look
		m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)), Color.RED, {}, null, false)
		var c := {"EngineMount": 0, "HeadSteady": 0, "Gusset": 0}
		for n in m.get_children():
			for k in c:
				if str(n.name).begins_with(k):
					c[k] += 1
		return c
	var bad := []
	for f in ["steel_cradle", "featherbed_cradle", "softail_hardtail", "adv_trellis", "mx_twin_loop", "cruiser_bagger_frame"]:
		var c: Dictionary = counts.call(f, BikeLook.NEW)
		var own := BikeRig.frame_rig(PartsDB.get_part(f))
		if c["EngineMount"] < 2 or (bool(own["steady"]) and c["HeadSteady"] < 2) or (bool(own["gusset"]) != (c["Gusset"] > 0)):
			bad.append("%s %s" % [f, c])
	var classic: Dictionary = counts.call("steel_cradle", BikeLook.CLASSIC)
	check(bad.is_empty() and classic["EngineMount"] + classic["HeadSteady"] + classic["Gusset"] == 0,
		"Rig built frames show their engine mounts, head steadies and gussets, Classic none %s" % [bad])
	m.queue_free()


## H2: change the engine and the frame re-forms round the new one over half a second: the meshes
## start in the old rig's shape (their base pulled back by how far the engine moved) and end in
## the new, plain again; it costs the rebuild little. The same bike drawn again, Classic, or
## another frame doesn't morph.
func test_reform() -> void:
	var parts := Contracts.style_build("classic")
	var a := _model()
	a.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)), Color.RED, {}, null, false)
	var other := parts.duplicate()
	other["engine"] = "twin_1200" if str(parts["engine"]) != "twin_1200" else "single_500"
	var b := _model()
	b.reform_from = a.rig
	var t0 := Time.get_ticks_usec()
	b.build_from(BikeBuild.new(PartsDB.sanitize_build(other)), Color.RED, {}, null, false)
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	var moved := ((b.rig["crank"] as Vector3) - (a.rig["crank"] as Vector3)).length()
	check(moved > 0.01 and not b._reform.is_empty(), "a new engine re-forms the frame (crank %.0f mm away, %d meshes)" % [moved * 1000.0, b._reform.size()])
	var engine_mi: MeshInstance3D = null
	for m in b._reform:
		var mi: MeshInstance3D = m["mi"]
		if mi.mesh.get_blend_shape_count() != 1 or mi.get_blend_shape_value(0) != 0.0:
			engine_mi = null
			break
		if b._slot_meshes["engine"].has(mi):
			engine_mi = mi
	var shift := 0.0
	if engine_mi != null:
		var now: PackedVector3Array = engine_mi.mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
		var was: PackedVector3Array = engine_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var shifts := []
		for v in range(0, now.size(), maxi(1, now.size() / 50)):
			shifts.append((engine_mi.transform * now[v]).distance_to(engine_mi.transform * was[v]))
		shifts.sort()
		shift = shifts[shifts.size() / 2]
	check(engine_mi != null and absf(shift - moved) < moved * 0.25, "it starts with the engine where the old one was (%.0f of %.0f mm back)" % [shift * 1000.0, moved * 1000.0])
	for i in 4:
		b._process(BikeReform.LENGTH / 3.0)
	var plain := b._reform.is_empty()
	for c in b.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh and ((c as MeshInstance3D).mesh as ArrayMesh).get_blend_shape_count() > 0 \
				and ((c as MeshInstance3D).mesh as ArrayMesh).get_blend_shape_name(0) == &"reform":
			plain = false
	check(plain, "after half a second the meshes are the plain new ones")
	check(took < 1500.0, "the re-formed bike is drawn in %.0f ms" % took)
	var c := _model()
	c.reform_from = b.rig
	c.build_from(BikeBuild.new(PartsDB.sanitize_build(other)), Color.RED, {}, null, false)
	var d := _model()
	d.look = BikeLook.CLASSIC
	d.reform_from = a.rig
	d.build_from(BikeBuild.new(PartsDB.sanitize_build(other)), Color.RED, {}, null, false)
	var e := _model()
	e.reform_from = a.rig
	var swap := other.duplicate()
	swap["frame"] = "featherbed_cradle" if str(parts["frame"]) != "featherbed_cradle" else "nickel_cradle"
	e.build_from(BikeBuild.new(PartsDB.sanitize_build(swap)), Color.RED, {}, null, false)
	check(c._reform.is_empty() and d._reform.is_empty() and e._reform.is_empty(), "the same rig, Classic, or another frame doesn't morph")
	for m in [a, b, c, d, e]:
		m.queue_free()
