extends RefCounted
## Handling at speed and grip off the road's edge, run from tests/run_tests.gd (its
## _test_handle_* functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## Seconds from a full steer input to the bike leaning `deg` degrees, riding `build` steadily at
## `v` m/s at Riding realism `assist`, or -1 if it never gets there (or can't reach the speed).
func lean_time(build: Dictionary, v: float, deg := 30.0, assist := 0.5) -> float:
	var st := {"steady": 0.0, "go": -1.0, "time": -1.0}
	var r: Dictionary = await t.ride(build, 45.0, func(b: Bike, now: float) -> void:
		b.assist = assist
		if st["go"] < 0.0:
			t._hold_speed(b, v)
			b.lean_input = 0.0
			st["steady"] = st["steady"] + 1.0 / Engine.physics_ticks_per_second if absf(b.speed - v) < 0.6 and absf(b.lean_angle) < deg_to_rad(1.0) else 0.0
			if st["steady"] > 1.5:
				st["go"] = now
			return
		t._hold_speed(b, v)
		# Full input until it gets there, then straight back up (a full input held at speed asks
		# for more lean than the measure needs).
		b.lean_input = 1.0 if st["time"] < 0.0 else 0.0
		if b.is_crashed and st["time"] < 0.0:
			st["time"] = -2.0
		if st["time"] == -1.0 and b.lean_angle > deg_to_rad(deg):
			st["time"] = now - float(st["go"]))
	var out: float = st["time"]
	await t._done(r)
	return out


## Rides `build` steadily at `v` m/s, then holds the steer input at `input` for `seconds`:
## whether it stayed up, and how much its lean wandered over the last two seconds (deg, the
## spread between the most and least).
func hold_lean(build: Dictionary, v: float, input: float, seconds := 5.0) -> Dictionary:
	var st := {"go": -1.0, "steady": 0.0, "lo": 9.0, "hi": -9.0, "lean": 0.0}
	var r: Dictionary = await t.ride(build, 40.0, func(b: Bike, now: float) -> void:
		b.assist = 0.5
		t._hold_speed(b, v)
		if st["go"] < 0.0:
			b.lean_input = 0.0
			st["steady"] = st["steady"] + 1.0 / Engine.physics_ticks_per_second if absf(b.speed - v) < 0.6 else 0.0
			if st["steady"] > 1.5:
				st["go"] = now
			return
		var into := now - float(st["go"])
		b.lean_input = input if into < seconds else 0.0
		if into > seconds - 2.0 and into < seconds:
			st["lo"] = minf(st["lo"], b.lean_angle)
			st["hi"] = maxf(st["hi"], b.lean_angle)
			st["lean"] = b.lean_angle)
	var out := {"crashed": r["crashed"], "held": float(st["go"]) > 0.0, "lean": rad_to_deg(st["lean"]),
		"wander": rad_to_deg(float(st["hi"]) - float(st["lo"]))}
	await t._done(r)
	return out


## Simon: "all bikes are very slow to lean at higher speed ... worst on the race bike which is VERY
## ponderous to turn." A full input at 120 and 160 km/h has the race bike over to 30 degrees in
## well under a second (it took 1.1 and 1.3 s), about as quick as the sports bike rather than the
## slowest of the fast bikes, and it holds a road lean at speed steadily.
func test_lean_speed() -> void:
	var times := {}
	for st: String in ["race", "sport"]:
		for kmh: float in [120.0, 160.0]:
			times["%s %d" % [st, kmh]] = await lean_time(Contracts.style_build(st), kmh / 3.6)
	var ok := times.values().all(func(x: float) -> bool: return x > 0.0 and x < 0.8)
	check(ok, "at 120 and 160 km/h a full input leans the race and sports bikes over to 30 deg inside 0.8 s %s" % str(times))
	check(float(times["race 120"]) < float(times["sport 120"]) * 1.1 and float(times["race 160"]) < float(times["sport 160"]) * 1.1,
		"the race bike turns in about as quickly as the sports bike, not the slowest (%.2f s against %.2f s at 120 km/h)"
		% [times["race 120"], times["sport 120"]])
	var held := await hold_lean(Contracts.style_build("race"), 120.0 / 3.6, Bike.ROAD_INPUT)
	check(held["held"] and not held["crashed"] and float(held["lean"]) > 25.0 and float(held["wander"]) < 2.0,
		"the race bike holds a road lean at 120 km/h steadily (%.0f deg, wandering %.1f deg)" % [held["lean"], held["wander"]])


## Not a check: prints the time to 30 degrees for each style at 50, 80, 120 and 160 km/h (-1: it
## can't reach that speed), for comparing handling changes. HANDLE_STYLES=race,sport and
## HANDLE_SPEEDS=120,160 (km/h) in the environment narrow it down.
func measure() -> void:
	var styles: Array = OS.get_environment("HANDLE_STYLES").split(",", false) if OS.has_environment("HANDLE_STYLES") \
		else PartsDB.STYLE_NAMES.keys()
	var speeds: Array = Array(OS.get_environment("HANDLE_SPEEDS").split(",", false)).map(func(x): return float(x)) \
		if OS.has_environment("HANDLE_SPEEDS") else [50.0, 80.0, 120.0, 160.0]
	for st: String in styles:
		var row := "    %-10s" % st
		for kmh: float in speeds:
			row += "  %6.2f" % await lean_time(Contracts.style_build(st), kmh / 3.6)
		print(row)


## A strip of `surf` (grass, say) laid just proud of the road (2 mm) along the arc the bike is
## turning on, starting `ahead` metres in front of it and `length` metres long, `width` wide.
static func _verge_on_arc(b: Bike, ahead: float, length: float, surf := "grass", width := 3.0) -> StaticBody3D:
	var pos := b.global_position
	var vel := Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z)
	var v := vel.length()
	var yaw := b.angular_velocity.y
	var fwd := vel.normalized()
	var at := func(d: float) -> Vector3:
		if absf(yaw) < 1e-3:
			return pos + fwd * d
		var r := v / yaw   # + turning left
		var left := Vector3.UP.cross(fwd)
		var centre := pos + left * r
		var th := d / r
		return centre + (pos - centre).rotated(Vector3.UP, th)
	var p0: Vector3 = at.call(ahead)
	var p1: Vector3 = at.call(ahead + length)
	var mid: Vector3 = at.call(ahead + length * 0.5)
	var dir := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	var body := StaticBody3D.new()
	body.set_meta("surface", surf)
	body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.2, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), Vector3(mid.x, 0.002 - 0.1, mid.z))
	return body


## Rides a stock sports bike (on road tyres) in a steady turn at `v` m/s with the input at
## `lean_in`, then lays grass across its line for `seconds` of riding. Returns what happened.
func _excursion(seconds: float, v := 15.0, lean_in := 0.75, build := {}) -> Dictionary:
	var st := {"patch": null, "t0": -1.0, "lean": 0.0, "min_mu": 9.0, "on_grass": 0.0, "lean_end": 0.0, "crashed_at": -1.0, "min_lean": 9.0, "slide": 0.0}
	var built: Dictionary = Contracts.style_build("sport") if build.is_empty() else build
	var r: Dictionary = await t.ride(built, 14.0, func(b: Bike, now: float) -> void:
		b.assist = 0.5
		t._hold_speed(b, v)
		b.lean_input = 0.0 if now < 3.0 else lean_in
		if st["patch"] == null and now >= 7.0:
			st["lean"] = absf(b.lean_angle)
			st["patch"] = _verge_on_arc(b, 4.0, v * seconds)
			b.get_parent().add_child(st["patch"])
			st["t0"] = now
		if st["t0"] > 0.0:
			for w: Dictionary in b.wheels:
				if w["contact"] and str(w["surface"]) == "grass":
					st["on_grass"] += 0.5 / Engine.physics_ticks_per_second
				if w["contact"]:
					st["min_mu"] = minf(st["min_mu"], float(w["mu"]))
				st["slide"] = maxf(st["slide"], absf(rad_to_deg(float(w["alpha"]))))
			if str(b.wheels[1]["surface"]) == "grass" or str(b.wheels[0]["surface"]) == "grass":
				st["min_lean"] = minf(st["min_lean"], absf(b.lean_angle))
		if b.is_crashed and st["crashed_at"] < 0.0:
			st["crashed_at"] = now
		st["lean_end"] = absf(b.lean_angle))
	st["crashed"] = r["crashed"]
	await t._done(r)
	return st


## A wheel dropping briefly off the road at a fair lean doesn't throw the bike down: the grip fades
## rather than stepping straight to the grass's, so it's gathered up and rides on round the turn.
## (With the grip stepping down, both of these slid out and crashed.)
func test_verge_save() -> void:
	for run: Array in [[0.75, 0.5], [0.85, 0.35]]:
		var st := await _excursion(run[1], 15.0, run[0])
		if t.verbose:
			print("    short excursion: %s" % str(st))
		check(not st["crashed"] and float(st["on_grass"]) > float(run[1]) * 0.6 and float(st["slide"]) < 6.0
			and float(st["lean_end"]) > deg_to_rad(15.0),
			"a sports bike leaned %.0f deg at 54 km/h that runs on to the grass for %.2f s stays up (tyres slid %.1f deg) and carries on round the turn (lean after %.0f deg)"
			% [rad_to_deg(st["lean"]), st["on_grass"], st["slide"], rad_to_deg(st["lean_end"])])


## Staying out there is another matter: a long run on the grass has the grass's grip. At a road
## rider's lean the bike can't hold its line and runs wide; leaned further it goes down.
func test_verge_long() -> void:
	var road := BikeBuild.new(Contracts.style_build("sport"))
	var grass := Bike.surface_grip(road, true, "grass")
	var wide := await _excursion(3.0, 15.0, 0.75)
	var down := await _excursion(3.0, 15.0, 0.85)
	if t.verbose:
		print("    long excursions: %s\n    %s" % [str(wide), str(down)])
	check(not wide["crashed"] and float(wide["min_mu"]) <= grass and float(wide["min_lean"]) < float(wide["lean"]) - deg_to_rad(4.0),
		"a sports bike leaned %.0f deg staying out on the grass for %.1f s gets the grass's grip (mu down to %.2f; the grass gives %.2f) and runs wide (lean down to %.0f deg)"
		% [rad_to_deg(wide["lean"]), wide["on_grass"], wide["min_mu"], grass, rad_to_deg(wide["min_lean"])])
	check(down["crashed"] and float(down["min_mu"]) <= grass,
		"leaned %.0f deg, a long run on the grass slides it out and it goes down (mu down to %.2f)" % [rad_to_deg(down["lean"]), down["min_mu"]])


## What's under a point (x, z) from above: [surface, height], or ["", NAN].
static func _probe(space: PhysicsDirectSpaceState3D, p: Vector3) -> Array:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return ["", NAN]
	return [str((hit["collider"] as Object).get_meta("surface", "")), (hit["position"] as Vector3).y]


## Each map's road edges, both sides of the road: the road's own surface just inside, a verge that
## grips less just outside, and no step between them to speak of, so the grip fade (in every
## wheel, whatever it's on) is what a wheel off the edge meets. `edges` is [[inside, outside], ...].
func _edges_ok(space: PhysicsDirectSpaceState3D, edges: Array, road_surf: Callable) -> Array:
	var bad := []
	var tyre := BikeBuild.new(Contracts.style_build("sport"))
	for e: Array in edges:
		var a := _probe(space, e[0])
		var b := _probe(space, e[1])
		var want: String = road_surf.call(e[0])
		if a[0] != want or b[0] == "" or b[0] == want or absf(float(a[1]) - float(b[1])) > 0.08 \
				or Bike.surface_grip(tyre, true, b[0]) >= Bike.surface_grip(tyre, true, a[0]):
			bad.append("%s/%s step %.2f" % [a[0], b[0], float(a[1]) - float(b[1])])
	return bad


func test_verge_edges() -> void:
	# The riding map round the shed: its tarmac roads and dirt tracks over the grass.
	var world := World.new()
	t.add_child(world)
	world.generate(1234)
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var edges := []
	var kinds := {}
	for road: Dictionary in world.roads.roads:
		var xz: PackedVector2Array = road["xz"]
		# The running surface's shoulders slope down to the grass (see WorldRoadMesh.section):
		# the edge a wheel runs off is at the shoulder's foot.
		var foot := float(WorldRoadMesh.section(road)[0][-1])
		for i in range(5, xz.size() - 5, maxi(xz.size() / 6, 1)):
			# Clear of junctions (another road there is no verge).
			var p := world.roads.point(world.roads.roads.find(road), i)
			var d: Vector2 = (xz[i + 1] - xz[i - 1]).normalized()
			var side := Vector3(-d.y, 0.0, d.x)
			for sgn: float in [-1.0, 1.0]:
				# Out from the road to where the ground under the wheel stops being the road.
				var inside := p
				var outside := p
				var off := float(road["hw"]) - 0.3
				var space := world.get_world_3d().direct_space_state
				while off < foot + 1.0:
					outside = p + side * sgn * off
					if _probe(space, outside)[0] != str(road["kind"]):
						break
					inside = outside
					off += 0.05
				var near_other := false
				for other: Dictionary in world.roads.roads:
					if other != road and Vector2(outside.x, outside.z).distance_to(other["xz"][world.roads.nearest_sample(other, Vector2(outside.x, outside.z))]) < float(other["hw"]) + 4.0:
						near_other = true
				# (Where the road runs on to a bridge's steel or a yard's slab, that's no verge.)
				if not near_other and inside != p and _probe(space, outside)[0] in ["grass", "dirt"]:
					edges.append([inside, outside, str(road["kind"])])
					kinds[str(road["kind"])] = true
	var by_kind := func(p: Vector3) -> String:
		for e: Array in edges:
			if e[0] == p:
				return e[2]
		return ""
	var bad := _edges_ok(world.get_world_3d().direct_space_state, edges, by_kind)
	check(edges.size() > 20 and kinds.size() >= 2 and bad.size() <= edges.size() / 20,
		"the riding map's %s roads run flush on to grass that grips less, at %d of %d edges %s"
		% ["/".join(kinds.keys()), edges.size() - bad.size(), edges.size(), str(bad.slice(0, 6))])
	world.queue_free()
	await t.get_tree().physics_frame
	# The adventure road: the land beside it, where that's another surface (sand and snow roads
	# run out on to sand and snow, which grip the same). The tour of the Dales by its tracks, for
	# gravel as well as tarmac.
	var spot := {}
	var w := AdventureWorld.new()
	var plan := AdventurePlans.tour("dales")
	plan["mode"] = "tracks"
	w.setup(AdventurePlans.pack_for(AdventurePlans.clean(plan)), 42, 60.0)
	for f in w.route.forks.size():
		w.route.choose(f, 0)
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(dd): spot["p"] -= dd)
	t.add_child(w)
	var aedges := []
	var surfs := {}
	for sec: Dictionary in w.route.surfaces:
		var surf: String = sec["surface"]
		if surfs.has(surf) or AdventureSurface.LAND[surf] == surf:
			continue
		var s0 := float(sec["s0"]) + 300.0
		spot["p"] = w.transform_at(s0).origin
		var end := Time.get_ticks_msec() + 20000
		while not w.chunks.has(AdventureRoute.chunk_of(s0)) and Time.get_ticks_msec() < end:
			await t.get_tree().process_frame
		await t.get_tree().physics_frame
		surfs[surf] = true
		for k in 6:
			var s := s0 + k * 12.0
			var e := w.route.width_at_s(s) * 0.5
			for sgn: float in [-1.0, 1.0]:
				aedges.append([w.transform_at(s, sgn * (e - 0.4)).origin, w.transform_at(s, sgn * (e + 0.6)).origin, surf])
		var abad := _edges_ok(w.get_world_3d().direct_space_state, aedges.slice(aedges.size() - 12),
			func(_p: Vector3) -> String: return surf)
		check(abad.size() <= 1, "the adventure road's %s runs flush on to its %s, which grips less %s"
			% [surf, AdventureSurface.LAND[surf], str(abad)])
	check(surfs.has("tarmac") and surfs.has("gravel"), "the adventure road's edges looked at on tarmac and gravel %s" % str(surfs.keys()))
	w.queue_free()
	await t.get_tree().physics_frame
