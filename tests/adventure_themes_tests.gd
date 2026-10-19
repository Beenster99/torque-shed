extends RefCounted
## The adventure themes' checks (AdventureTheme: varied, desert, alpine, coastal and hills), run
## from tests/run_tests.gd: its _test_adv_themes_* functions hand over to these.

const SEEDS := [3, 42, 2024]

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


## A world of `theme` for `seed` and `km` following `spot` ({p}), the main road at every fork.
func _world(seed: int, km: float, theme: String, spot: Dictionary) -> AdventureWorld:
	var w := AdventureWorld.new()
	w.setup(seed, km, theme)
	for f in w.route.forks.size():
		w.route.choose(f, 0)
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	return w


## Shares of the road (main road, the whole length) by surface and by kind of bends, the mean
## width, the tightest bend, and the high and low points.
static func _mix(r: AdventureRoute) -> Dictionary:
	var surf := {}
	for s in r.chunk_surface:
		surf[s] = float(surf.get(s, 0.0)) + 1.0 / r.chunk_surface.size()
	var kinds := {}
	var total := 0.0
	for sec in r.sections:
		var l := float(sec["s1"]) - float(sec["s0"])
		kinds[sec["kind"]] = float(kinds.get(sec["kind"], 0.0)) + l
		total += l
	for k in kinds:
		kinds[k] = float(kinds[k]) / maxf(total, 1.0)
	var wsum := 0.0
	var kmax := 0.0
	var hi := -INF
	var lo := INF
	for i in r.knot_count():
		wsum += r.width[i]
		kmax = maxf(kmax, absf(r.curv[i]))
		hi = maxf(hi, r.ph[i])
		lo = minf(lo, r.ph[i])
	return {"surf": surf, "kinds": kinds, "width": wsum / r.knot_count(), "radius": 1.0 / maxf(kmax, 1e-6), "hi": hi, "lo": lo}


static func _fmt(d: Dictionary) -> String:
	var bits := []
	for k in d:
		bits.append("%s %d%%" % [k, roundi(float(d[k]) * 100.0)])
	return ", ".join(bits)


## Every theme plans a whole ride from its seed (the same seed, the very same road; the theme is
## part of it), with fuel, stops and forks along it; and its road is the theme's: the surfaces,
## the bends, the widths and the climbs.
func test_plan() -> void:
	check(Adventure.THEMES == AdventureTheme.IDS and AdventureTheme.IDS.size() == 5, "five themes: %s" % str(Adventure.THEMES))
	var mixes := {}
	for theme in AdventureTheme.IDS:
		var agg := {"surf": {}, "kinds": {}, "width": 0.0, "radius": INF, "hi": -INF, "lo": INF}
		var ok_sites := true
		var same := true
		for seed in SEEDS:
			var a := AdventureRoute.new()
			a.plan(seed, 80.0, theme)
			var b := AdventureRoute.new()
			b.plan(seed, 80.0, theme)
			same = same and a.px == b.px and a.ph == b.ph and a.chunk_surface == b.chunk_surface and a.width == b.width \
				and str(AdventureChunk.build(a, 200)["mm"]) == str(AdventureChunk.build(b, 200)["mm"])
			ok_sites = ok_sites and a.sites_of("fuel").size() >= 2 and AdventureStops.stops(a).size() >= 8 and a.forks.size() >= 2 \
				and a.sites_of("finish").size() == 1
			var m := _mix(a)
			for k in m["surf"]:
				agg["surf"][k] = float(agg["surf"].get(k, 0.0)) + float(m["surf"][k]) / SEEDS.size()
			for k in m["kinds"]:
				agg["kinds"][k] = float(agg["kinds"].get(k, 0.0)) + float(m["kinds"][k]) / SEEDS.size()
			agg["width"] = float(agg["width"]) + float(m["width"]) / SEEDS.size()
			agg["radius"] = minf(agg["radius"], m["radius"])
			agg["hi"] = maxf(agg["hi"], m["hi"])
			agg["lo"] = minf(agg["lo"], m["lo"])
		mixes[theme] = agg
		check(same, "%s: the same seed plans the very same road and scenery" % theme)
		check(ok_sites, "%s: fuel stations, stops, forks and the destination along it" % theme)
		print("    THEME %s: surfaces %s; bends %s; width %.1f m; tightest %.0f m; heights %.0f..%.0f m" % [theme,
			_fmt(agg["surf"]), _fmt(agg["kinds"]), agg["width"], agg["radius"], agg["lo"], agg["hi"]])
	var other := AdventureRoute.new()
	other.plan(42, 80.0, "desert")
	var vr := AdventureRoute.new()
	vr.plan(42, 80.0, "varied")
	check(other.px != vr.px, "another theme on the same seed is another road")
	var v: Dictionary = mixes["varied"]
	var de: Dictionary = mixes["desert"]
	var al: Dictionary = mixes["alpine"]
	var co: Dictionary = mixes["coastal"]
	var hl: Dictionary = mixes["hills"]
	var sh := func(m: Dictionary, table: String, k: String) -> float: return float(m[table].get(k, 0.0))
	check(v["surf"].size() == 4, "varied: tarmac, gravel, sand and snow, as before (%s)" % _fmt(v["surf"]))
	check(sh.call(de, "surf", "sand") > 0.25 and sh.call(de, "surf", "snow") == 0.0 and sh.call(de, "kinds", "straight") > 0.4
		and sh.call(de, "kinds", "straight") > 2.0 * sh.call(v, "kinds", "straight"),
		"desert: sand and long straights, no snow (%s; %s)" % [_fmt(de["surf"]), _fmt(de["kinds"])])
	check(sh.call(al, "surf", "snow") > 0.08 and sh.call(al, "surf", "sand") == 0.0
		and sh.call(al, "kinds", "very_curvy") + sh.call(al, "kinds", "switchback") > 0.35
		and float(al["radius"]) < 22.0 and float(al["hi"]) > 1500.0,
		"alpine: hairpins (%.0f m), climbs to %.0f m and snow over the tops (%s)" % [al["radius"], al["hi"], _fmt(al["surf"])])
	check(sh.call(co, "surf", "snow") == 0.0 and float(co["hi"]) < 260.0 and float(co["lo"]) > AdventureTheme.SEA_Y + 15.0,
		"coastal: no snow, the road between %.0f and %.0f m above the sea" % [co["lo"], co["hi"]])
	check(sh.call(hl, "surf", "sand") == 0.0 and sh.call(hl, "surf", "snow") == 0.0 and sh.call(hl, "surf", "tarmac") > 0.6
		and float(hl["width"]) < float(v["width"]) - 0.4,
		"hills: narrow lanes (%.1f m against %.1f), tarmac and gravel (%s)" % [hl["width"], v["width"], _fmt(hl["surf"])])
	# The snow is near the tops: higher than the road's average.
	var r := AdventureRoute.new()
	r.plan(42, 80.0, "alpine")
	var snow_h := 0.0
	var all_h := 0.0
	var n_snow := 0
	for c in r.chunk_surface.size():
		var h := r.ph[mini(c * AdventureRoute.CHUNK_KNOTS + 16, r.knot_count() - 1)]
		all_h += h / r.chunk_surface.size()
		if r.chunk_surface[c] == "snow":
			snow_h += h
			n_snow += 1
	check(n_snow > 0 and snow_h / n_snow > all_h + 150.0, "alpine snow lies high up (%.0f m against %.0f m on average)" % [snow_h / maxi(n_snow, 1), all_h])
	# The ways at the forks are the theme's too: a desert track runs on sand, a hills track never does.
	var tracks := {}
	for theme in ["desert", "hills"]:
		var surfs := {}
		for seed in SEEDS:
			var rr := AdventureRoute.new()
			rr.plan(seed, 120.0, theme)
			for fk in rr.forks:
				for way in fk["ways"]:
					if way["kind"] == "gravel":
						for s in way["chunk_surface"]:
							surfs[s] = true
		tracks[theme] = surfs
	check(tracks["desert"].has("sand") and not tracks["hills"].has("sand") and not tracks["hills"].has("snow"),
		"a fork's track is the theme's: desert %s, hills %s" % [str(tracks["desert"].keys()), str(tracks["hills"].keys())])


## The scenery is the theme's: cacti, red rock and mesas in the desert; pines, snow and crags in
## the mountains; gorse, dunes, the sea and a lighthouse or two by the coast; oaks, sheep, stone
## walls and hedges in the hills. Each theme's stops are built in its own style.
func test_scenery() -> void:
	var want := {"varied": ["tree", "pine"], "desert": ["cactus", "red_rock", "mesa"], "alpine": ["pine", "snow_pine", "crag"],
		"coastal": ["gorse", "lighthouse"], "hills": ["oak", "sheep"]}
	var never := {"desert": ["pine", "snow_pine", "tree"], "alpine": ["cactus", "sheep"], "coastal": ["cactus", "snow_pine"],
		"hills": ["cactus", "snow_pine", "mesa"], "varied": ["cactus", "sheep", "mesa"]}
	for theme in AdventureTheme.IDS:
		var r := AdventureRoute.new()
		r.plan(42, 80.0, theme)
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
		check(has_all and has_none, "%s scenery: %s (%.1f ms a chunk to lay out)" % [theme, str(kinds), ms])
		if theme == "hills":
			check(walls > 1000, "hills: dry-stone walls and hedges along the lanes (%d wall vertices)" % walls)
		if theme == "coastal":
			check(land_below > 100 and under == 0, "coastal: the land runs down into the sea (%d points under it) and nothing stands in the water" % land_below)
	# The stops' buildings in the theme's style.
	var found := _find_stop("village")
	for theme in AdventureTheme.IDS:
		var r := AdventureRoute.new()
		r.plan(int(found[0]), 150.0, theme)
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


## The first seed whose 150 km road has a stop of `kind`: [seed, site].
static func _find_stop(kind: String) -> Array:
	for seed in range(1, 60):
		var r := AdventureRoute.new()
		r.plan(seed, 150.0)
		for st in AdventureStops.stops(r):
			if str(st["kind"]) == kind:
				return [seed, st]
	return [1, {}]


## Each theme streams in and races along without a hitch, its fuel stations and stops on the
## satnav; the profiler's numbers for each theme go in the report.
func test_stream() -> void:
	for theme in AdventureTheme.IDS:
		var spot := {}
		var w := _world(42, 40.0, theme, spot)
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
		check(ready and float(w.stats["commit_ms_max"]) < 25.0 and float(w.stats["stream_ms_max"]) < 30.0 and float(w.stats["plan_ms"]) < 2000.0,
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


## Starting a themed ride sets the sky's tint, the weather from the theme's odds (the same for
## the same seed) and the time it sets off; back home they're the shed's again.
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
	Adventure.start(77, 10.0, "alpine")
	for i in 10:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	var expect := AdventureTheme.weather_pick("alpine", float(absi(hash([77, "weather"])) % 1000) / 1000.0)
	check(trip.on_trip() and trip.world.route.theme == "alpine" and absf(Daylight.time_of_day() - 6.8) < 0.1,
		"an alpine ride sets off early in the morning (%s)" % Daylight.clock_text(Daylight.time_of_day()))
	check(not Daylight.tint.is_empty() and Weather.odds == AdventureTheme.get_value("alpine", "weather") and Weather.current.state == expect,
		"under the mountains' sky, the weather %s from the seed" % expect)
	check(trip.world.horizon.material_override is StandardMaterial3D, "the far ground's there")
	Adventure.menu_action()
	for i in 10:
		await t.get_tree().physics_frame
	check(not trip.on_trip() and Daylight.tint.is_empty() and Weather.odds.is_empty(), "back home the sky and weather are the shed's")
	Adventure.start(78, 10.0, "coastal")
	for i in 10:
		await t.get_tree().physics_frame
	var m := trip.world.horizon.material_override as StandardMaterial3D
	check(trip.on_trip() and trip.world.route.sea and absf(trip.world.horizon.position.y - AdventureTheme.SEA_Y) < 0.01 and m.albedo_color == AdventureWorld.SEA_COLOR,
		"a coastal ride has the sea alongside")
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
