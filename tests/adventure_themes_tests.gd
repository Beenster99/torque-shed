extends RefCounted
## The adventure themes' checks (AdventureTheme: the look of each region's land; Shodoshima's coastal, the Dales'
## hills), run from tests/run_tests.gd: its _test_adv_themes_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")
## The bundled regions, and the theme each is dressed as.
const REGIONS := {"shodoshima": "coastal", "dales": "hills"}

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _until(cond: Callable, seconds := 20.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await t.get_tree().process_frame
	return cond.call()


## A world along the tour of `region_id` following `spot` ({p}), the main road at every fork.
func _world(seed: int, region_id: String, spot: Dictionary) -> AdventureWorld:
	var w := AdventureWorld.new()
	w.setup(Rides.tour_pack(region_id), seed, 40.0)
	for f in w.route.forks.size():
		w.route.choose(f, 0)
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	return w


## The scenery is the region's theme's: gorse and a lighthouse or two by the coast round Shodoshima; oaks, sheep, stone
## walls and hedges in the Dales. Each theme's stops are built in its own style.
func test_scenery() -> void:
	var want := {"coastal": ["gorse"], "hills": ["oak", "sheep"]}
	var never := {"coastal": ["cactus", "snow_pine", "sheep"], "hills": ["cactus", "snow_pine", "mesa"]}
	for region_id in REGIONS:
		var theme: String = REGIONS[region_id]
		var r := Rides.tour_route(region_id, 42)
		var kinds := {}
		var walls := 0
		var under := 0
		var land_below := 0
		var t0 := Time.get_ticks_usec()
		var built := 0
		for c in range(0, r.chunk_count() - 1, 3):
			var data := AdventureChunk.build(r, c)
			built += 1
			for k in data["mm"]:
				if not (data["mm"][k] as Array).is_empty():
					kinds[k] = int(kinds.get(k, 0)) + (data["mm"][k] as Array).size()
					for xf: Transform3D in data["mm"][k]:
						if r.sea and xf.origin.y < AdventureTheme.SEA_Y + 0.5 and k != "post" and k != "km_post":
							under += 1
			walls += (data["walls"]["v"] as PackedVector3Array).size()
			if r.sea:
				for v: Vector3 in data["land_-1"][Mesh.ARRAY_VERTEX]:
					if v.y < AdventureTheme.SEA_Y:
						land_below += 1
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / built
		# The far things are rare (a lighthouse every 10 km or so): look along every chunk for them.
		var far: Array = AdventureTheme.get_value(theme, "far", [])
		if not far.is_empty():
			var count := 0
			for c in r.chunk_count() - 1:
				var mm := {}
				var i0 := c * AdventureRoute.CHUNK_KNOTS
				AdventureChunk._far(r, c, i0, mini(i0 + AdventureRoute.CHUNK_KNOTS, r.knot_count() - 1), r.px[i0], r.pz[i0], mm)
				count += (mm.get(far[0], []) as Array).size()
			kinds[far[0]] = count
		var has_all := (want[theme] as Array).all(func(k): return int(kinds.get(k, 0)) > 0)
		var has_none := (never[theme] as Array).all(func(k): return int(kinds.get(k, 0)) == 0)
		if theme == "coastal":
			has_all = has_all and int(kinds["lighthouse"]) <= 16   # a few, not a row of them
		check(r.theme == theme and has_all and has_none, "%s, %s scenery: %s (%.1f ms a chunk to lay out)" % [region_id, theme, str(kinds), ms])
		if theme == "hills":
			check(walls > 1000, "hills: dry-stone walls and hedges along the lanes (%d wall vertices)" % walls)
		if theme == "coastal":
			check(under == 0, "coastal: nothing stands in the water (%d points of the land under it)" % land_below)
	# The stops' buildings in the theme's style.
	for region_id in REGIONS:
		var theme: String = REGIONS[region_id]
		var r := Rides.tour_route(region_id, 7)
		var site: Dictionary = {}
		for st in AdventureStops.stops(r):
			if str(st["kind"]) in ["village", "inn"]:
				site = st
				break
		if site.is_empty():
			check(false, "%s: a village or inn to build" % theme)
			continue
		var node := AdventureStops.build(r, site, Transform3D(Basis(), Vector3(0, 100, 0)))
		var style := AdventureTheme.style(theme)
		var cols := {}
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			for k in m.get_surface_count():
				var arr := m.surface_get_arrays(k)
				if arr[Mesh.ARRAY_COLOR] != null:
					for col: Color in arr[Mesh.ARRAY_COLOR]:
						cols[col] = true
		var walls_found := (style["walls"] as Array).filter(func(c: Color):
			return cols.keys().any(func(q: Color): return absf(q.r - c.r) + absf(q.g - c.g) + absf(q.b - c.b) < 0.01)).size()
		check(str(node.get_meta("style", "")) == str(AdventureTheme.get_value(theme, "style")) and walls_found > 0,
			"%s: the %s is built %s (%d of its wall colours on it)" % [theme, site["kind"], node.get_meta("style", ""), walls_found])
		node.free()


## Each region streams in and races along without a hitch, its fuel stations and stops on the satnav; the profiler's
## numbers for each go in the report.
func test_stream() -> void:
	for region_id in REGIONS:
		var theme: String = REGIONS[region_id]
		var spot := {}
		var w := _world(42, region_id, spot)
		var ready := await _until(func(): return w.wanted_chunks().all(func(c): return w.chunks.has(c)))
		var worst := 0.0
		var tris := 0
		var nodes := 0
		for k in 60:
			spot["p"] = w.transform_at(20.0 + k * 100.0).origin
			var t0 := Time.get_ticks_usec()
			await t.get_tree().process_frame
			worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
			while Time.get_ticks_usec() - t0 < 16000:
				await t.get_tree().process_frame
		await _until(func(): return w.wanted_chunks().all(func(c): return w.chunks.has(c)))
		for c in w.chunks:
			for mi in (w.chunks[c] as Node).find_children("*", "GeometryInstance3D", true, false):
				nodes += 1
				if mi is MeshInstance3D and (mi as MeshInstance3D).mesh:
					var m := (mi as MeshInstance3D).mesh
					for s in m.get_surface_count():
						tris += _verts(m, s) / 3
				elif mi is MultiMeshInstance3D:
					var mm := (mi as MultiMeshInstance3D).multimesh
					var per := 0
					for s in mm.mesh.get_surface_count():
						per += _verts(mm.mesh, s) / 3
					tris += per * mm.instance_count
		var per_chunk := tris / maxi(1, w.chunks.size())
		check(ready and float(w.stats["commit_ms_max"]) < 25.0 and float(w.stats["stream_ms_max"]) < 40.0 and float(w.stats["plan_ms"]) < 3000.0,
			"%s streams without a hitch: %s" % [theme, w.timing_text()])
		check(per_chunk < 60000, "%s: %d triangles a chunk on average, %d drawn things in %d chunks" % [theme, per_chunk, nodes, w.chunks.size()])
		print("    THEME TIMING %s: %s; worst whole frame %.1f ms; %d tris/chunk; %d instances" % [theme, w.timing_text(), worst, per_chunk, nodes])
		# The road under the wheels is the theme's surface, and the satnav knows what's ahead.
		var s := 6100.0
		var p := w.transform_at(s, 0.5).origin
		var nav := Satnav.AdventureNav.new(w)
		var at := w.transform_at(1000.0)
		var list: Array = nav.satnav_stops(Vector2(at.origin.x, at.origin.z), Vector2(-at.basis.z.x, -at.basis.z.z), 3)
		check(AdventureWorld.surface_at(p) == w.route.surface_at_s(s) and list.size() == 3,
			"%s: the tyres find the %s, and the satnav lists %s" % [theme, w.route.surface_at_s(s), str(list.map(func(q): return q["label"]))])
		w.queue_free()
		await _frames(2)


## Starting a ride sets the sky's tint, the weather from its region's theme's odds (the same for the same seed) and the
## time it sets off; back home they're the shed's again.
func test_sky() -> void:
	# The weather drawn from each theme's odds.
	var counts := {}
	for theme in AdventureTheme.IDS:
		var c := {}
		for k in 400:
			var w := AdventureTheme.weather_pick(theme, (k + 0.5) / 400.0)
			c[w] = int(c.get(w, 0)) + 1
		counts[theme] = c
	check(counts["varied"].keys() == [""] and int(counts["desert"].get("clear", 0)) > 280 and not counts["desert"].has("fog")
		and int(counts["hills"].get("rain", 0)) > int(counts["desert"].get("rain", 0)) and int(counts["alpine"].get("fog", 0)) > 40,
		"the weather's odds: desert mostly clear, hills wetter, alpine mornings misty %s" % str(counts))
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	var held := Settings.weather
	Settings.weather = "auto"
	Daylight.current.set_time(15.0)
	Adventure.start(AdventurePlans.tour("dales", 2), 77)
	for i in 10:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	var expect := AdventureTheme.weather_pick("hills", float(absi(hash([77, "weather"])) % 1000) / 1000.0)
	check(trip.on_trip() and trip.world.route.theme == "hills" and absf(Daylight.time_of_day() - 8.5) < 0.1,
		"a ride in the Dales sets off in the morning (%s)" % Daylight.clock_text(Daylight.time_of_day()))
	check(not Daylight.tint.is_empty() and Weather.odds == AdventureTheme.get_value("hills", "weather") and Weather.current.state == expect,
		"under the hills' sky, the weather %s from the seed" % expect)
	check(trip.world.horizon.material_override is StandardMaterial3D, "the far ground's there")
	Adventure.menu_action()
	for i in 10:
		await t.get_tree().physics_frame
	check(not trip.on_trip() and Daylight.tint.is_empty() and Weather.odds.is_empty(), "back home the sky and weather are the shed's")
	Adventure.start(AdventurePlans.tour("shodoshima", 2), 78)
	for i in 10:
		await t.get_tree().physics_frame
	var m := trip.world.horizon.material_override as StandardMaterial3D
	check(trip.on_trip() and trip.world.route.sea and absf(trip.world.horizon.position.y - AdventureTheme.SEA_Y) < 0.01 and m.albedo_color == AdventureWorld.SEA_COLOR,
		"a ride round Shodoshima has the sea alongside")
	Adventure.menu_action()
	for i in 10:
		await t.get_tree().physics_frame
	Settings.weather = held
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)


## The vertices in surface `s` of `m`, an ArrayMesh or a primitive one (the lights' heads and poles).
static func _verts(m: Mesh, s: int) -> int:
	if m is ArrayMesh:
		return (m as ArrayMesh).surface_get_array_len(s)
	return (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
