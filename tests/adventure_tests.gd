extends RefCounted
## Adventure rides' checks (the streaming road, its floating origin, surfaces, fuel stations and
## going there and back with the crew), run from tests/run_tests.gd: its _test_adventure_*
## functions hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Runs frames until `cond` is true or `seconds` of real time have gone (the worker threads
## build in real time, however fast the frames run). Returns whether it came true.
func _until(cond: Callable, seconds := 20.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await t.get_tree().process_frame
	return cond.call()


## A world for `seed` and `km` whose road follows `spot` ({p: local position}), kept in step
## with the origin. The main road is taken at every fork (unless `forks_open`), so it's all there to stream.
func _world(seed: int, km: float, spot: Dictionary, forks_open := false) -> AdventureWorld:
	var w := AdventureWorld.new()
	w.setup(seed, km)
	if not forks_open:
		for f in w.route.forks.size():
			w.route.choose(f, 0)
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	return w


## The same seed plans the same road, chunk for chunk; another seed a different one. The road has
## all its kinds of section, widths down to a single track, climbs and descents, every surface,
## fuel stations every so often, and always makes progress (never crossing itself).
func test_route() -> void:
	var a := AdventureRoute.new()
	a.plan(42, 60.0)
	var b := AdventureRoute.new()
	b.plan(42, 60.0)
	var c := AdventureRoute.new()
	c.plan(43, 60.0)
	check(a.px == b.px and a.pz == b.pz and a.ph == b.ph and a.width == b.width and a.chunk_surface == b.chunk_surface,
		"the same seed plans the very same road (%d knots, %.1f km)" % [a.knot_count(), a.total / 1000.0])
	check(a.px != c.px, "another seed plans another road")
	var ca := AdventureChunk.build(a, 150)
	var cb := AdventureChunk.build(b, 150)
	check(ca["road"][Mesh.ARRAY_VERTEX] == cb["road"][Mesh.ARRAY_VERTEX] and ca["land_1"][Mesh.ARRAY_VERTEX] == cb["land_1"][Mesh.ARRAY_VERTEX]
		and str(ca["mm"]) == str(cb["mm"]) and ca["road_faces"] == cb["road_faces"],
		"and builds the same chunk 19 km along, scenery and all (%.1f ms to build)" % float(ca["ms"]))
	var kinds := {}
	for s in a.sections:
		kinds[s["kind"]] = true
	check(kinds.size() == 4, "straight, sweeping, curvy and very curvy sections %s" % str(kinds.keys()))
	var wmin := 99.0
	var wmax := 0.0
	var gmin := 0.0
	var gmax := 0.0
	var monotonic := true
	var kmax := 0.0
	for i in a.knot_count():
		wmin = minf(wmin, a.width[i])
		wmax = maxf(wmax, a.width[i])
		kmax = maxf(kmax, absf(a.curv[i]))
		if i > 0:
			gmin = minf(gmin, (a.ph[i] - a.ph[i - 1]) / AdventureRoute.STEP)
			gmax = maxf(gmax, (a.ph[i] - a.ph[i - 1]) / AdventureRoute.STEP)
			monotonic = monotonic and a.pz[i] < a.pz[i - 1]
	check(wmax >= 7.0 and wmin <= 3.5, "wide two-lane road down to single track (%.1f .. %.1f m)" % [wmin, wmax])
	check(gmax > 0.04 and gmin < -0.04, "climbs and descents (%.0f%% .. %.0f%%)" % [gmin * 100.0, gmax * 100.0])
	check(kmax > 1.0 / 60.0, "very curvy means tight: a %.0f m radius" % (1.0 / kmax))
	check(monotonic, "the road always heads on north, so it never crosses itself")
	var surfs := {}
	for s in a.chunk_surface:
		surfs[s] = true
	check(surfs.size() == 4, "a varied adventure has tarmac, gravel, sand and snow %s" % str(surfs.keys()))
	var fuel := a.sites_of("fuel")
	var gaps_ok := fuel.size() >= 2 and float(fuel[0]["s"]) >= 9000.0 and float(fuel[0]["s"]) <= 15000.0
	for k in range(1, fuel.size()):
		var gap := float(fuel[k]["s"]) - float(fuel[k - 1]["s"])
		gaps_ok = gaps_ok and gap >= 22000.0 and gap <= 32000.0
	check(gaps_ok, "fuel stations every so often %s" % str(fuel.map(func(f): return roundi(float(f["s"])))))
	var flat := true
	for f in fuel:
		var i: int = f["i"]
		for j in range(i - 20, i + 20):
			flat = flat and absf(a.curv[j]) < 1e-6 and absf(a.ph[j + 1] - a.ph[j]) < 0.1
	check(flat, "the road runs straight and level past every fuel station")
	check(a.sites_of("start").size() == 1 and a.sites_of("finish").size() == 1 and float(a.sites_of("finish")[0]["s"]) == 60000.0,
		"a start banner, and the destination 60 km on")
	var xz := a.xz_at(20000.0, 2.5)
	var hit := a.locate(xz[0], xz[1])
	check(not hit.is_empty() and absf(float(hit["s"]) - 20000.0) < 1.0 and absf(float(hit["lat"]) - 2.5) < 0.05,
		"a point is found along the road: %.1f m, %.2f m right" % [float(hit.get("s", -1)), float(hit.get("lat", 0))])
	var short := AdventureRoute.new()
	short.plan(5, 10.0)
	check(short.sites_of("fuel").size() == 1, "even a short ride has a fuel station on it")


## The road streams in ahead and is freed behind, built on worker threads; the main thread only
## takes a few ms a frame for it. The ms figures go in the report.
func test_stream() -> void:
	var spot := {}
	var w := _world(5, 40.0, spot)
	await _until(func(): return w.wanted_chunks().all(func(c): return w.chunks.has(c)))
	var want := w.wanted_chunks()
	var have := want.filter(func(c): return w.chunks.has(c))
	check(have.size() == want.size() and want.size() >= 25, "the road is there %.1f km ahead (%d chunks)" % [AdventureWorld.AHEAD / 1000.0, have.size()])
	check(w.chunks.has(0) and float(w.stats["build_ms_max"]) > 0.0, "built on worker threads (%s)" % w.timing_text())
	# Off down the road: 8 km at 100 m a frame, held to 60 frames a second (a mad 6 km a minute).
	var worst := 0.0
	for k in 80:
		spot["p"] = w.transform_at(20.0 + k * 100.0).origin
		var t0 := Time.get_ticks_usec()
		await t.get_tree().process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		while Time.get_ticks_usec() - t0 < 16000:
			await t.get_tree().process_frame
	await _until(func(): return w.wanted_chunks().all(func(c): return w.chunks.has(c)))
	var here := AdventureRoute.chunk_of(8000.0)
	check(not w.chunks.has(0) and not w.chunks.has(here - 10) and int(w.stats["freed"]) > 20,
		"what's left behind is freed (%d chunks freed, %d in the world)" % [int(w.stats["freed"]), w.chunks.size()])
	check(w.chunks.has(here) and w.chunks.has(AdventureRoute.chunk_of(8000.0 + 3000.0)), "and the road is there ahead again")
	check(float(w.stats["commit_ms_max"]) < 25.0 and float(w.stats["stream_ms_max"]) < 30.0,
		"one chunk a frame goes in without a hitch: %s" % w.timing_text())
	check(int(w.stats["shifts"]) >= 10 and Vector2(spot["p"].x - AdventureWorld.ANCHOR.x, spot["p"].z - AdventureWorld.ANCHOR.z).length() <= AdventureWorld.SHIFT_DIST + 60.0,
		"the origin moved along %d times, keeping us near the anchor" % int(w.stats["shifts"]))
	print("    ADVENTURE TIMING: ", w.timing_text(), "; worst whole frame while racing along: %.1f ms" % worst)
	w.queue_free()
	await _frames(2)


## A local position in the world means the same point of the route on every machine, however
## the origin has moved; network snapshots carry the sender's origin and come out in the
## receiver's frame.
func test_frames() -> void:
	var spot := {}
	var w := _world(9, 50.0, spot)
	var p := w.transform_at(31234.5, 1.25).origin
	var xz := w.route.xz_at(31234.5, 1.25)
	check(absf(float(w.route_xz(p)[0]) - xz[0]) < 0.01, "local and route frames agree before a shift")
	var d := w.shift_origin_to(p)
	var q := p - d
	var hit := w.locate_local(q)
	check(absf(float(hit["s"]) - 31234.5) < 0.05 and absf(float(hit["lat"]) - 1.25) < 0.05 and q.length() < 7000.0,
		"after shifting 31 km the same point is the same place on the road (%.2f m, %.2f m right), near the anchor" % [float(hit["s"]), float(hit["lat"])])
	check(fmod(w.origin.x, 1.0) == 0.0 and fmod(w.origin.z, 1.0) == 0.0, "the origin is whole metres (%s)" % str(w.origin))
	# Another machine, whose origin is somewhere else.
	var other := AdventureWorld.new()
	other.setup(9, 50.0)
	other.shift_origin_to(other.transform_at(29000.0).origin)
	var mine := PackedFloat32Array([1.0, 7.0, q.x, q.y, q.z, 0, 0, 0, 1, 3, 0, 0])
	var theirs := AdventureWorld.untag(w.tag_state(mine), other.origin)
	var at := Vector3(theirs[2], theirs[3], theirs[4])
	var ohit := other.route.locate(float(at.x) + other.origin.x, float(at.z) + other.origin.z)
	check(theirs.size() == mine.size() and absf(float(ohit["s"]) - 31234.5) < 0.05 and absf(float(ohit["lat"]) - 1.25) < 0.05,
		"a rider's snapshot lands on the same spot in another player's frame (%.2f m, %.2f m right)" % [float(ohit["s"]), float(ohit["lat"])])
	var walk := PackedFloat32Array([0.0, q.x, q.y, q.z, 0.3, 0.0, 0.0])
	var wt := AdventureWorld.untag(w.tag_state(walk), other.origin)
	check(wt.size() == walk.size() and absf(wt[1] - (q.x + w.origin.x - other.origin.x)) < 0.01, "and so does someone on foot")
	check(AdventureWorld.untag(mine, other.origin) == mine, "a snapshot from the shed (no origin on it) is left alone")
	other.free()
	w.queue_free()
	await _frames(2)


## Riding along, the origin shifts under the bike: its speed, lean and the way it's going carry on
## as if nothing happened. And 30 km out it rides as steadily as at the start.
func test_origin() -> void:
	var spot := {}
	var w := _world(11, 60.0, spot)
	w.preload_range(0.0, 600.0)
	var bike := Bike.new()
	bike.setup(BikeBuild.new({}))
	w.add_child(bike)
	w.focus = func(): return [bike.global_position]
	w.origin_shifted.connect(func(d): bike.shift_origin(d))
	var start := w.transform_at(30.0, -1.5)
	bike.place(start.origin, w.heading_at(30.0))
	bike.auto_shift = true
	bike.assist = 0.5
	await _ticks(60)
	# Up to speed down the straight at the start, steering along it: how steady it is here.
	var wob0 := 0.0
	var jit0 := 0.0
	var prev0 := bike.lean_angle
	for i in 300:
		if i > 180:
			wob0 = maxf(wob0, absf(bike.wobble))
			jit0 = maxf(jit0, absf(bike.lean_angle - prev0))
		prev0 = bike.lean_angle
		bike.throttle = 0.8 if bike.speed < 18.0 else 0.2
		_steer(bike, w, -1.5)
		await t.get_tree().physics_frame
	var before := {"v": bike.linear_velocity, "w": bike.angular_velocity, "lean": bike.lean_angle, "speed": bike.speed,
		"route": w.route_xz(bike.global_position)}
	var d := w.shift_origin_to(bike.global_position + Vector3(900.0, 0.0, -700.0))
	var after_route := w.route_xz(bike.global_position)
	check(d.length() > 500.0 and absf(after_route[0] - before["route"][0]) < 0.001 and absf(after_route[1] - before["route"][1]) < 0.001,
		"the origin shifts %.0f m and the bike's still at the same place on the route" % d.length())
	check(bike.linear_velocity.is_equal_approx(before["v"]) and bike.angular_velocity.is_equal_approx(before["w"]),
		"its velocity and spin are untouched")
	var speeds := []
	var leans := []
	for i in 30:
		bike.throttle = 0.2
		_steer(bike, w, -1.5)
		await t.get_tree().physics_frame
		speeds.append(bike.speed)
		leans.append(bike.lean_angle)
	check(absf(speeds[0] - before["speed"]) < 0.3 and absf(leans[0] - before["lean"]) < 0.02 and not bike.is_crashed,
		"and it rides straight on: %.2f -> %.2f m/s, lean %.1f -> %.1f deg" % [before["speed"], speeds[0], rad_to_deg(before["lean"]), rad_to_deg(leans[0])])
	# 30 km on, at the next straight: as steady as at the start.
	var far := _straight_after(w.route, 30500.0)
	w.preload_range(far - 200.0, far + 600.0)
	var at := w.transform_at(far, -1.5)
	var v := bike.linear_velocity.length()
	bike.place(at.origin, w.heading_at(far))
	bike.linear_velocity = at.basis * Vector3(0.0, 0.0, -v)
	await _ticks(2)
	var p := bike.global_position
	check(Vector2(p.x - AdventureWorld.ANCHOR.x, p.z - AdventureWorld.ANCHOR.z).length() < AdventureWorld.SHIFT_DIST,
		"%.1f km out the bike is drawn near the anchor, not 30 km off (%.0f m from it)" % [far / 1000.0, Vector2(p.x - AdventureWorld.ANCHOR.x, p.z - AdventureWorld.ANCHOR.z).length()])
	var wob := 0.0
	var lean_jit := 0.0
	var prev_lean := bike.lean_angle
	for i in 240:
		bike.throttle = 0.6 if bike.speed < 18.0 else 0.2
		_steer(bike, w, -1.5)
		await t.get_tree().physics_frame
		if i > 60:
			wob = maxf(wob, absf(bike.wobble))
			lean_jit = maxf(lean_jit, absf(bike.lean_angle - prev_lean))
		prev_lean = bike.lean_angle
	var hit := w.locate_local(bike.global_position)
	check(not bike.is_crashed and absf(float(hit["lat"]) + 1.5) < 2.0 and bike.speed > 12.0,
		"and it rides on down the road there (%.1f m/s, %.1f m off its line)" % [bike.speed, float(hit["lat"]) + 1.5])
	check(wob < maxf(wob0 * 2.0, 0.02) and lean_jit < maxf(jit0 * 2.0, 0.01),
		"no more shake or jitter than at the start (wobble %.4f rad vs %.4f, lean step %.4f vs %.4f rad)" % [wob, wob0, lean_jit, jit0])
	bike.queue_free()
	w.queue_free()
	await _frames(2)


## The first point at or after `s` with 200 m of straight tarmac ahead (the same surface as
## the start, to compare like with like).
static func _straight_after(r: AdventureRoute, s: float) -> float:
	var i := int(s / AdventureRoute.STEP)
	var run := 0
	while i < r.knot_count() - 1:
		run = run + 1 if absf(r.curv[i]) < 1e-5 and r.surface_at_s(i * AdventureRoute.STEP) == "tarmac" else 0
		if run >= 50:
			return (i - 50) * AdventureRoute.STEP
		i += 1
	return s


## Leans the bike to hold `lat` metres off the centre line along the road.
static func _steer(bike: Bike, w: AdventureWorld, lat: float) -> void:
	var hit := w.locate_local(bike.global_position, "test")
	if hit.is_empty():
		return
	var h := w.route.heading_at_s(float(hit["s"]))
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var right := Vector3(cos(h), 0.0, sin(h))
	var bf := -bike.global_basis.z
	var herr := atan2(bf.dot(right), bf.dot(fwd))
	bike.lean_input = clampf(-(0.12 * (float(hit["lat"]) - lat) + 1.6 * herr), -0.6, 0.6)


## Every surface is under the tyres where the route says (its collision carries it), and looks
## different; AdventureWorld.surface_at answers the same; grip falls from tarmac to snow.
func test_surfaces() -> void:
	var spot := {}
	var w := _world(42, 60.0, spot)
	var found := {}
	var looks := {}
	for sec in w.route.surfaces:
		var surf: String = sec["surface"]
		if found.has(surf):
			continue
		var s := float(sec["s0"]) + 300.0
		spot["p"] = w.transform_at(s).origin
		await _until(func(): return w.chunks.has(AdventureRoute.chunk_of(s)))
		await t.get_tree().physics_frame
		var p := w.transform_at(s, 0.5).origin
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, 1)
		var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
		var meta := str((hit["collider"] as Object).get_meta("surface", "")) if hit else ""
		var side := w.transform_at(s, w.route.width_at_s(s) * 0.5 + 6.0).origin
		found[surf] = meta == surf and AdventureWorld.surface_at(p) == surf and AdventureWorld.surface_at(side) == AdventureSurface.LAND[surf]
		var chunk: Node3D = w.chunks[AdventureRoute.chunk_of(s)]
		looks[surf] = (chunk.get_node("Road") as MeshInstance3D).material_override
	check(found.size() == 4 and found.values().all(func(v): return v), "the tyres find each surface on the road, and the land beside it %s" % str(found))
	var mats := {}
	for m in looks.values():
		mats[m] = true
	check(mats.size() == 4, "each surface has its own look")
	var tyre := BikeBuild.new({})
	var knobbly := BikeBuild.new({"front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx"})
	var g := func(b, s): return Bike.surface_grip(b, false, s)
	check(g.call(tyre, "tarmac") == float(tyre.grip_rear["tarmac"]) and g.call(tyre, "tarmac") > g.call(tyre, "gravel")
		and g.call(tyre, "gravel") > g.call(tyre, "sand") and g.call(tyre, "sand") > g.call(tyre, "snow"),
		"grip falls from tarmac to gravel, sand and snow (%.2f, %.2f, %.2f, %.2f)" % [g.call(tyre, "tarmac"), g.call(tyre, "gravel"), g.call(tyre, "sand"), g.call(tyre, "snow")])
	check(g.call(knobbly, "gravel") > g.call(tyre, "gravel") and g.call(knobbly, "sand") > g.call(tyre, "sand"),
		"knobblies grip better off the tarmac")
	check(AdventureWorld.surface_at(Vector3(1, 0, 1)) != "", "the surface lookup answers anywhere")
	w.queue_free()
	await _frames(2)
	check(AdventureWorld.surface_at(Vector3.ZERO) == "tarmac", "with no adventure on it says tarmac")


## Each fuel station has its forecourt and four pumps in group "fuel_pump", beside the road at
## its distance; they go when the road behind is freed.
func test_pumps() -> void:
	var spot := {}
	var w := _world(42, 60.0, spot)
	var fuel: Dictionary = w.route.sites_of("fuel")[0]
	var s := float(fuel["s"])
	spot["p"] = w.transform_at(s).origin
	await _until(func(): return w.chunks.has(AdventureRoute.chunk_of(s)))
	var pumps := t.get_tree().get_nodes_in_group(AdventureProps.PUMP_GROUP)
	var near := 0
	for p in pumps:
		var hit := w.locate_local((p as Node3D).global_position)
		if absf(float(hit["s"]) - s) < 30.0 and float(hit["lat"]) > 0.0 and float(hit["lat"]) < 25.0:
			near += 1
	check(pumps.size() >= 4 and near == 4, "a fuel station %.1f km along with four pumps beside the road (%d found)" % [s / 1000.0, near])
	var forecourt := PhysicsRayQueryParameters3D.create((pumps[0] as Node3D).global_position + Vector3(0, 3, 1.4), (pumps[0] as Node3D).global_position + Vector3(0, -3, 1.4), 1)
	var hit2 := w.get_world_3d().direct_space_state.intersect_ray(forecourt)
	check(hit2 and str((hit2["collider"] as Object).get_meta("surface", "")) == "tarmac", "with a forecourt to ride onto")
	spot["p"] = w.transform_at(s + 6000.0).origin
	await _until(func(): return not w.chunks.has(AdventureRoute.chunk_of(s)))
	await t.get_tree().process_frame
	check(t.get_tree().get_nodes_in_group(AdventureProps.PUMP_GROUP).is_empty(), "and it goes once it's far behind")
	w.queue_free()
	await _frames(2)


## The host starts an adventure: you're on your bike at the start, the town asleep, the day running
## faster; you ride, reach the destination and everyone's brought home, the bike parked in a bay
## with the fuel it burnt and the muck it picked up kept. A save made out there keeps you at home.
func test_trip() -> void:
	AdventureTrip.instant = true
	AdventureDest.album_path = ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	var fuel_before := Shed.build_of(faithful).fuel_litres
	var tyre := Shed.item_on(faithful, "rear_tyre")
	var wear_before := float(Shed.items[tyre]["wear"])
	var dirt_before := float(Shed.items[tyre]["dirt"])
	main.menu.show_pause()
	check(main.menu._adventure.visible and not main.menu._adventure.disabled and main.menu._adventure.text.begins_with("Adventure ride"),
		"the Esc menu offers the host an adventure ride")
	main.menu.hide()
	Adventure.start(77, 20.0)
	for i in 10:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	check(Adventure.active() and trip.on_trip() and trip.world.route.length == 20000.0, "the host starts a 20 km adventure and it loads")
	check(main.bike != null and Shed.riding(Shed.me()) == faithful, "you're on the bike you were standing by")
	var start: Transform3D = trip.start_xf()
	check(main.bike.global_position.distance_to(start.origin) < 1.5, "on the grid at the start (%.1f m off)" % main.bike.global_position.distance_to(start.origin))
	check(not main.workshop.visible and main.workshop.process_mode == Node.PROCESS_MODE_DISABLED and not main.traffic.visible,
		"the town is asleep while you're away")
	check(Daylight.local_rate() == Adventure.day_rate() and absf(24.0 / Daylight.local_rate() / 3600.0 - 1.25) < 0.01,
		"the day runs faster: a whole day in %.0f minutes" % (24.0 / Daylight.local_rate() / 60.0))
	check(main.home_reason() != "" and main.home_reason() != "home", "Back to the garage waits for the adventure to end")
	main.menu.show_pause()
	check(main.menu._adventure.text.begins_with("End the adventure"), "and the menu offers to end it")
	main.menu.hide()
	# Ride off down the straight from the start.
	main.bike.engine_on = true
	main.bike.gear = 1
	Input.action_press("throttle", 0.6)
	for i in 360:
		await t.get_tree().physics_frame
	Input.action_release("throttle")
	var hud_ok: bool = trip._hud.visible and trip._hud.text.begins_with("Adventure")
	check(main.bike.speed > 8.0 and not main.bike.is_crashed and hud_ok, "riding off down the road (%.1f m/s), the distance at the top (%s)" % [main.bike.speed, trip._hud.text])
	# A save made out here keeps everyone at home.
	main.saver._note_players()
	var noted: Dictionary = main.saver._players.values()[0]
	check(int(noted["riding"]) == 0 and (noted["xf"] as Transform3D).origin.distance_to(Workshop.walker_spawn(Net.local_slot()).origin) < 0.1,
		"a save out here puts you back at the shed")
	# To the destination.
	trip.jump(trip.world.route.length - trip.world.distance_of(main.bike.global_position, "own") - 5.0)
	for i in 30:
		main.bike.throttle = 0.3
		await t.get_tree().physics_frame
	check(int(Shed.adventure.get("arrived", 0)) == Shed.me(), "reaching the destination tells the host")
	# There: parked by the set piece for the moment, the photo up on the shed wall, and it's the
	# host who rides everyone home (nothing ends by itself).
	var at_dest: float = trip.world.distance_of(main.bike.global_position, "own")
	check(trip.moment_done and absf(at_dest - AdventureDest.dest_s(trip.world)) < 20.0,
		"everyone's brought to the destination's set piece (%.0f m along, it's at %.0f)" % [at_dest, AdventureDest.dest_s(trip.world)])
	var photo: Dictionary = Shed.adventure.get("photo", {})
	check(not photo.is_empty() and not AdventureDest.photo_on_wall(str(photo.get("key", ""))).is_empty(), "and the crew's photo hangs in the shed")
	for i in 30:
		await t.get_tree().physics_frame
	check(Adventure.active() and trip.on_trip(), "the adventure stays on at the destination")
	main.menu.show_pause()
	check(main.menu._adventure.text.begins_with("Ride home") and not main.menu._adventure.disabled, "the Esc menu offers the host Ride home")
	main.menu.hide()
	Adventure.menu_action()
	for i in 10:
		await t.get_tree().physics_frame
	check(not Adventure.active() and not trip.on_trip() and main.bike == null and Shed.riding(Shed.me()) == 0,
		"Ride home brings everyone home")
	var parked: Transform3D = Shed.bikes[faithful]["xf"]
	check(Shed.bay_at(parked.origin) >= 0 and main.walker.global_position.distance_to(Workshop.walker_spawn(Net.local_slot()).origin) < 1.0,
		"the bike's parked in a bay and you're at the shed door (%s, %s)" % [parked.origin, main.walker.global_position])
	check(main.workshop.visible and main.workshop.process_mode != Node.PROCESS_MODE_DISABLED and Daylight.adventure_rate == 0.0,
		"the town wakes up and the day runs as before")
	var fuel_after := Shed.build_of(faithful).fuel_litres
	check(fuel_after < fuel_before and fuel_after > fuel_before - 2.0, "the petrol it burnt stays burnt (%.2f -> %.2f l)" % [fuel_before, fuel_after])
	check(float(Shed.items[tyre]["wear"]) >= wear_before and float(Shed.items[tyre]["dirt"]) > dirt_before - 0.01,
		"and the tyre's wear and muck are kept (wear %.5f -> %.5f, dirt %.4f -> %.4f)" % [wear_before, float(Shed.items[tyre]["wear"]), dirt_before, float(Shed.items[tyre]["dirt"])])
	# Ending one by hand, from the menu, while on foot.
	Adventure.start(78, 10.0)
	await _ticks(10)
	check(trip.on_trip() and main.bike != null, "a second adventure starts")
	Adventure.menu_action()
	await _ticks(10)
	check(not trip.on_trip() and main.bike == null and main.walker.visible, "and the host ends it from the menu")
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
