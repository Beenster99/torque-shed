extends RefCounted
## Adventure performance and graphics checks (Simon's v0.17.0 round: "too many stutters in
## adventures - this causes lag for everyone" and "lots of graphics glitches on adventure - long
## triangles"). Run from tests/run_tests.gd (its _test_adv_perf_* functions hand over to these).

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree()

## The longest a triangle's edge may be in each of a chunk's meshes (m). The land is checked
## its own way (see _scan_land): its columns are meant to get wider out to the skyline.
const MAX_EDGE := {"road": 12.0, "lines": 12.0, "paint": 14.0, "arms": 24.0, "walls": 12.0, "buildings": 150.0}
## A frame this much longer than the ride's typical one is a stutter (ms, headless: no drawing).
const SPIKE_MS := 12.0


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func _until(cond: Callable, seconds := 20.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > seconds * 1000.0:
			return false
		await t.get_tree().process_frame
	return true


# ---------------------------------------------------------------------------- the meshes

## Every mesh of a built chunk (AdventureChunk.build) as [name, vertices, indices]: indexed
## grids come with their indices, triangle soups with none.
static func meshes(data: Dictionary) -> Array:
	var out := []
	for key in ["road", "land_-1", "land_1"]:
		var arr: Array = data[key]
		out.append([key, arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX]])
	for key in ["lines", "paint", "walls", "buildings"]:
		if data.get(key) is Dictionary and (data[key] as Dictionary).has("v"):
			out.append([key, data[key]["v"], PackedInt32Array()])
	for surf in data.get("arms", {}):
		out.append(["arms", data["arms"][surf]["v"], PackedInt32Array()])
	return out


## What's wrong with the triangles of chunk `data` built from `route`: a line for each problem,
## saying which mesh, which triangle and why (a vertex that isn't a number or is miles off, an
## index past the end, an edge far longer than that mesh's pieces ever are, a spike of land, a
## row of land ending up in the air).
static func scan(route: AdventureRoute, data: Dictionary, tally := {}) -> Array:
	var bad := []
	for m in meshes(data):
		var name: String = m[0]
		var v: PackedVector3Array = m[1]
		var idx: PackedInt32Array = m[2]
		var n := idx.size() if not idx.is_empty() else v.size()
		if n % 3 != 0:
			bad.append("%s: %d corners, not whole triangles" % [name, n])
			continue
		for k in v.size():
			var p := v[k]
			if not p.is_finite() or absf(p.x) > 4000.0 or absf(p.z) > 4000.0 or absf(p.y) > 6000.0:
				bad.append("%s: vertex %d is at %s" % [name, k, str(p)])
				break
		var limit := float(MAX_EDGE.get(name, -1.0))
		for tri in n / 3:
			var a := tri * 3
			var ia := idx[a] if not idx.is_empty() else a
			var ib := idx[a + 1] if not idx.is_empty() else a + 1
			var ic := idx[a + 2] if not idx.is_empty() else a + 2
			if ia < 0 or ib < 0 or ic < 0 or ia >= v.size() or ib >= v.size() or ic >= v.size():
				bad.append("%s: triangle %d points past the end (%d, %d, %d of %d)" % [name, tri, ia, ib, ic, v.size()])
				break
			if limit > 0.0:
				var e := maxf(v[ia].distance_to(v[ib]), maxf(v[ib].distance_to(v[ic]), v[ic].distance_to(v[ia])))
				if e > limit:
					bad.append("%s: triangle %d has a %.0f m edge (%s %s %s)" % [name, tri, e, str(v[ia]), str(v[ib]), str(v[ic])])
	bad.append_array(_scan_land(route, data, tally))
	return bad


## The land's grid either side (its rows a knot apart along the road, its columns out to the
## skyline, see AdventureChunk.LAND_OUT): no triangle folded over, face down; no vertex standing
## up out of the ground round it, or sunk below it, like a spike; and every row going down at
## its far end to under the far ground (or the sea), however far out it got (but where it
## closes in on the middle of a bend, with the rows either side). A row cut short
## that stopped up in the air, beside rows that ran on out and down, made long triangles up into
## the sky and down to the far ground, with the sky showing between them.
static func _scan_land(route: AdventureRoute, data: Dictionary, tally: Dictionary) -> Array:
	var bad := []
	var cols := AdventureChunk.land_cols(route)
	var i0 := int(data["i0"])
	for side: int in [-1, 1]:
		var v: PackedVector3Array = data["land_%d" % side][Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = data["land_%d" % side][Mesh.ARRAY_INDEX]
		var rows := v.size() / cols
		for tri in idx.size() / 3:
			var p0 := v[idx[tri * 3]]
			var p1 := v[idx[tri * 3 + 1]]
			var p2 := v[idx[tri * 3 + 2]]
			var nrm := (p2 - p0).cross(p1 - p0)
			if nrm.y < -0.001 * nrm.length() and nrm.length() > 1.0:
				bad.append("land %d: triangle %d is folded over, face down (%s %s %s)" % [side, tri, str(p0), str(p1), str(p2)])
			elif nrm.length() > 40.0 and absf(nrm.y) < 0.15 * nrm.length():
				tally["walls"] = int(tally.get("walls", 0)) + 1   # a big face standing on its edge, a wall or a fin
		tally["tris"] = int(tally.get("tris", 0)) + idx.size() / 3
		for r in rows:
			var end := v[r * cols + (0 if side < 0 else cols - 1)]
			var ground := AdventureTheme.SEA_Y if route.sea else route.base[i0 + r] - 70.0
			var mid := Vector2(route.px[i0 + r] - float(data["ax"]), route.pz[i0 + r] - float(data["az"]))
			var closing := Vector2(end.x, end.z).distance_to(mid) > route.inside_reach(i0 + r, side) * 0.9
			if end.y > ground and not closing:   # (not where the rows close in on a bend's middle)
				bad.append("land %d: row %d ends %.0f m up over the far ground, at %s" % [side, r, end.y - ground, str(end)])
			for k in cols:
				var p := v[r * cols + k]
				var nb := []
				if k > 0:
					nb.append(v[r * cols + k - 1])
				if k < cols - 1:
					nb.append(v[r * cols + k + 1])
				if r > 0:
					nb.append(v[(r - 1) * cols + k])
				if r < rows - 1:
					nb.append(v[(r + 1) * cols + k])
				var above := true
				var below := true
				for q: Vector3 in nb:
					var flat := Vector2(q.x - p.x, q.z - p.z).length()
					if p.y - q.y < 25.0 + flat * 2.0:
						above = false
					if q.y - p.y < 25.0 + flat * 2.0:
						below = false
				if k == (0 if side < 0 else cols - 1):
					below = false   # (the far edge goes down on purpose, see AdventureChunk.FAR_SIDE_DROP)
				if (above or below) and nb.size() >= 3:
					bad.append("land %d: row %d column %d at %s stands %s its neighbours" % [side, r, k, str(p), "up out of" if above else "down below"])
	return bad


## The chunks of both tours' roads, either way at the forks, looked over for bad triangles (see scan): none anywhere.
func test_triangles() -> void:
	var chunks := 0
	var bad := []
	var by_theme := {}
	var tally := {}
	for theme in ["shodoshima", "dales"]:
		for seed in [5, 42]:
			var r := Rides.tour_route(theme, seed)
			for f in r.forks.size():
				r.choose(f, seed % 2)
			var found := 0
			for c in r.chunk_count():
				var data := AdventureChunk.build(r, c)
				chunks += 1
				var here := scan(r, data, tally)
				found += here.size()
				if not here.is_empty() and bad.size() < 6:
					bad.append("%s seed %d chunk %d: %s" % [theme, seed, c, here[0]])
			by_theme[theme] = int(by_theme.get(theme, 0)) + found
		await _frames(1)
	check(chunks > 600 and bad.is_empty(),
		"%d chunks of both tours looked over: no bad or overlong triangles, every row of land down under the far ground at its end %s %s" % [chunks, str(by_theme), str(bad)])
	check(int(tally.get("walls", 0)) * 1000 < int(tally.get("tris", 0)),
		"and hardly a wall or fin of land where it goes down (%d of %d faces)" % [int(tally.get("walls", 0)), int(tally.get("tris", 0))])


# ---------------------------------------------------------------------------- stutters

## Rides the adventure from `from` to `to` metres headless, `step` metres a frame (the bike put
## there each frame; `during` called with where it's got to), timing every frame:
## [the frames' ms sorted, where the worst was].
func _ride(main: Node, trip: AdventureTrip, from: float, to: float, step: float, during := Callable()) -> Array:
	var w := trip.world
	var times := []
	var worst := 0.0
	var worst_at := 0.0
	var s := from
	var last := Time.get_ticks_usec()
	while s < to:
		s = minf(s + step, minf(w.route.total, w.route.stream_end()) - 30.0)
		var xf := w.transform_at(s, -1.6)
		if main.bike:
			main.bike.place(xf.origin, w.heading_at(s))
			main.bike.linear_velocity = xf.basis * Vector3(0, 0, -step * 60.0)
		if during.is_valid():
			during.call(s)
		await t.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		times.append(ms)
		if ms > worst:
			worst = ms
			worst_at = s
		if times.size() > 20000:
			break
	times.sort()
	return [times, worst_at]


## The frames' median, 99th percentile and worst (ms), how many stutter (SPIKE_MS over the
## median) and how many take longer than two frames at 60 fps.
static func _summary(times: Array) -> Dictionary:
	if times.is_empty():
		return {"n": 0, "median": 0.0, "p99": 0.0, "worst": 0.0, "spikes": 0, "over33": 0}
	var med: float = times[times.size() / 2]
	return {"n": times.size(), "median": med, "p99": float(times[int(times.size() * 0.99)]), "worst": float(times[-1]),
		"spikes": times.filter(func(x): return x > med + SPIKE_MS).size(), "over33": times.filter(func(x): return x > 33.0).size()}


## Simon's v0.17.0 round: "too many stutters in adventures - this causes lag for everyone".
## Out on a long ride every frame now goes by without a hitch: the chunks of road go into the
## world a piece at a time, the ride's stats each second no longer go over the whole shed (nor
## redraw the shed, out of sight back home), and a fork's way off the main road is put together
## on a worker thread (a tenth of a second on the main thread, on every player's game at once).
func test_ride() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	Rides.start(60.0, 42)
	await _ticks(30)
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and main.bike != null and trip.world.route.forks.size() > 0, "out on a %.0f km ride, with a fork in it" % (trip.world.route.length / 1000.0 if trip.on_trip() else 0.0))
	if not trip.on_trip() or main.bike == null or trip.world.route.forks.is_empty():
		await _done(main)
		return
	var w := trip.world
	await _frames(120)
	# From the start: three kilometres at 120 m a second (2 m a frame).
	var a: Array = await _ride(main, trip, 40.0, 3000.0, 2.0)
	# Then up to the first fork, the host picking the way off the main road, and on through it.
	var fs := w.route.fork_s(0)
	var jumped := fs - 2200.0
	trip.jump(jumped - w.distance_of(main.bike.global_position, "own"))
	await _frames(60)
	var voted := [false]
	var b: Array = await _ride(main, trip, jumped, fs + 1200.0, 2.0, func(s):
		if not voted[0] and s > fs - 2000.0:
			voted[0] = true
			Shed.request({"a": "adventure_vote", "fork": 0, "way": 1}))
	var fork := _summary(b[0])
	var all: Array = (a[0] as Array) + (b[0] as Array)
	all.sort()
	var sum := _summary(all)
	var taken := w.route.decided.has(0) and int(w.route.choices.get(0, 0)) == 1
	# The ride goes as fast as the frames do, and on a quick machine it can get ahead of the worker
	# thread building the road: give it a moment to catch up along the way picked.
	for i in 600:
		if w.has_ground(fs + 600.0):
			break
		await t.get_tree().process_frame
	print("    ADV RIDE PROFILE: %d frames, median %.2f ms, p99 %.2f, worst %.1f ms (at %.0f m / %.0f m), %d frames over the median by %.0f ms, %d over 33 ms; through the fork: worst %.1f ms, %d stutters; %s"
		% [sum["n"], sum["median"], sum["p99"], sum["worst"], a[1], b[1], sum["spikes"], SPIKE_MS, sum["over33"], fork["worst"], fork["spikes"], w.timing_text()])
	check(taken and w.has_ground(fs + 600.0), "the host's pick at the fork is taken, and the road built on along it (picks %s, chosen %s, ground %s, voted %s)"
		% [Shed.adventure.get("picks", {}), w.route.choices, w.has_ground(fs + 600.0), voted[0]])
	check(float(sum["worst"]) < 60.0 and int(sum["over33"]) <= 2,
		"no stutter on the ride: the worst of %d frames %.1f ms, %d over 33 ms (the median %.1f ms)" % [sum["n"], sum["worst"], sum["over33"], sum["median"]])
	check(int(sum["spikes"]) * 400 < int(sum["n"]) and float(fork["worst"]) < 60.0,
		"hardly a frame much slower than the rest (%d of %d over the median by %.0f ms), and none at the fork (worst there %.1f ms)" % [sum["spikes"], sum["n"], SPIKE_MS, fork["worst"]])
	# A customer walking in at the shed meanwhile (their bike's model made as they come) was a
	# hitch of 100 ms and more, on every machine: not till you're home.
	var cid := Contracts.spawn("maint")
	var q := Time.get_ticks_usec()
	Shed.changed.emit()
	var ms := (Time.get_ticks_usec() - q) / 1000.0
	check(not main.contracts_view.views.has(cid), "a customer coming in at the shed while you're away isn't made there and then (%.1f ms)" % ms)
	Shed.request({"a": "adventure_end"})
	await _until(func(): return not trip.on_trip(), 5.0)
	await _frames(3)
	check(not trip.on_trip() and main.contracts_view.views.has(cid), "but they're there waiting when you're home")
	await _done(main)


## "This causes lag for everyone": every rider's stats go to the host once a second, and each
## went over the whole shed again there (Shed.changed: the shed's computers, the cafe, the staff,
## the shed itself), then again with the sync to the crew. Now a ride's stats only wear the bike
## and are carried by the next sync: five riders' stats in a frame are one going-over, not six.
func test_ride_stats() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	Shed.bikes[faithful]["xf"] = Transform3D(Basis(), Vector3(14.0, 0.0, 30.0))
	main._try_mount(faithful)
	await _ticks(10)
	check(main.bike != null and Shed.riding(Shed.me()) == faithful, "you're out on your bike")
	if main.bike == null:
		main.queue_free()
		Shed.stop()
		await _frames(3)
		return
	await _ticks(Engine.physics_ticks_per_second / 2)
	var tyre := Shed.item_on(faithful, "rear_tyre")
	var worn := float(Shed.items[tyre]["wear"])
	var km := float(Shed.crew[Shed.me()].get("km", 0.0))
	var heard := [0]
	var count := func(): heard[0] += 1
	Shed.changed.connect(count)
	var t0 := Time.get_ticks_usec()
	for k in 5:
		Shed.request({"a": "ride", "km": 0.03, "top_kmh": 110.0, "kmh": 105.0, "dirt_km": 0.02, "fly_km": 0.03, "fuel": 0.004})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var at_once: int = heard[0]
	await _ticks(Engine.physics_ticks_per_second / 4)
	var later: int = heard[0]
	Shed.changed.disconnect(count)
	print("    RIDE STATS: five riders' stats %.2f ms on the host, Shed.changed %d times then, %d by the next sync" % [ms, at_once, later])
	check(float(Shed.items[tyre]["wear"]) > worn and float(Shed.crew[Shed.me()]["km"]) > km + 0.14,
		"the stats still wear the tyre and count the distance at once")
	check(at_once == 0 and later >= 1 and later <= 3,
		"and the shed's gone over once by the next sync (%d), not once for each (%d at once)" % [later, at_once])
	main.queue_free()
	Shed.stop()
	await _frames(3)


func _done(main: Node) -> void:
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
