extends RefCounted
## Real roads' checks (a baked pack read by RealPack and RealTerrain, planned by AdventureRoute.plan_real
## and built into chunks), run from tests/run_tests.gd: its _test_real_* functions hand over to these.

const PACK := "shodoshima"

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func test_pack() -> void:
	check(RealPack.list().has(PACK), "the game has the %s road pack" % PACK)
	var p := RealPack.get_pack(PACK)
	check(p != null and p.hash != "" and p.credits.size() > 0, "it reads, with its hash and credits")
	if p == null:
		return
	check(RealPack.get_pack(PACK) == p, "and is read once, then shared")
	check(RealPack.get_pack("nowhere") == null, "a pack that isn't there is null, not a crash")
	check(p.max_km() > 20.0 and p.x.size() > 1000, "%.1f km of road in %d knots" % [p.max_km(), p.x.size()])
	# The land is one surface: bilinear across the tile seams.
	var worst := 0.0
	var known := 0
	for k in range(0, p.x.size(), 25):
		var h := p.terrain.height(p.x[k], p.z[k])
		if is_nan(h):
			continue
		known += 1
		worst = maxf(worst, absf(h - p.terrain.height(p.x[k] + 0.5, p.z[k])))
	check(known > p.x.size() / 25 * 0.95, "land under the road all along it (%d of %d samples)" % [known, p.x.size() / 25])
	check(worst < 3.0, "land heights are continuous, also over tile edges (worst step %.2f m in 0.5 m)" % worst)
	check(is_nan(p.terrain.height(1.0e7, 1.0e7)), "and unknown far from the tiles")
	var off := 0.0
	for k in range(0, p.x.size(), 50):
		var h := p.terrain.height(p.x[k], p.z[k])
		if not is_nan(h):
			off = maxf(off, absf(h - p.e[k]))
	check(off < 12.0, "the road sits on the land it was baked from (most %.1f m off)" % off)


func test_plan() -> void:
	var p := RealPack.get_pack(PACK)
	var a := AdventureRoute.new()
	a.plan_real(p, 7, 10.0)
	var b := AdventureRoute.new()
	b.plan_real(p, 7, 10.0)
	check(a.px == b.px and a.ph == b.ph and a.width == b.width and a.chunk_surface == b.chunk_surface and a.sites.size() == b.sites.size(),
		"the same real road plans the very same ride (%d knots)" % a.knot_count())
	check(absf(a.length - 10000.0) < 0.1 and a.total > a.length, "its length is the km asked for (%.0f m) and a run-out" % a.length)
	check(a.real == p and a.sea == p.sea and a.forks.is_empty() and a.tunnels.is_empty(), "no forks or tunnels on a real road")
	var gmax := 0.0
	var step_worst := 0.0
	var hd_jump := 0.0
	for i in range(1, a.knot_count()):
		gmax = maxf(gmax, absf(a.ph[i] - a.ph[i - 1]) / AdventureRoute.STEP)
		step_worst = maxf(step_worst, absf(Vector2(a.px[i] - a.px[i - 1], a.pz[i] - a.pz[i - 1]).length() - AdventureRoute.STEP))
		hd_jump = maxf(hd_jump, absf(a.hd[i] - a.hd[i - 1]))
	check(gmax <= AdventureRoute.MAX_GRADE + 0.001, "grades stay under the planner's limit (steepest %.1f%%)" % (gmax * 100.0))
	check(step_worst < 0.5 and hd_jump < 0.5, "knots 4 m apart, headings continuous (step off %.2f m, turn %.2f rad)" % [step_worst, hd_jump])
	check(a.chunk_surface.size() == a.chunk_count() and a.width.size() == a.knot_count() and a.base.size() == a.knot_count(),
		"surfaces, widths and the lie of the land cover every knot")
	check(a.sites_of("start").size() == 1 and a.sites_of("finish").size() == 1 and absf(a.sites_of("finish")[0]["s"] - 10000.0) < 1.0,
		"start and destination, with %d fuel stations and %d stops" % [a.sites_of("fuel").size(), AdventureStops.stops(a).size()])
	for st in a.sites:
		if st["kind"] == "fuel" or AdventureStops.KINDS.has(str(st["kind"])):
			var i := int(st["i"])
			if absf(a.hd[mini(i + 12, a.knot_count() - 1)] - a.hd[maxi(i - 12, 0)]) > deg_to_rad(12.0):
				check(false, "a %s sits on a bend" % st["kind"])
	var big := AdventureRoute.new()
	big.plan_real(p, 7, 1000.0)
	check(big.length <= p.max_km() * 1000.0 + 0.1, "a longer ride than the pack is cut to the pack (%.1f km)" % (big.length / 1000.0))
	var c := AdventureChunk.build(a, 20)
	var d := AdventureChunk.build(b, 20)
	check(c["road"][Mesh.ARRAY_VERTEX] == d["road"][Mesh.ARRAY_VERTEX] and c["land_1"][Mesh.ARRAY_VERTEX] == d["land_1"][Mesh.ARRAY_VERTEX],
		"and builds the same chunk twice, land and all (%.1f ms)" % float(c["ms"]))
	var last := AdventureChunk.build(a, a.chunk_count() - 1)
	check(not last["road"].is_empty(), "the last chunk builds too")


## Ridden: the real road streams in chunk by chunk, all the way along (dashing the length at 100 m a frame).
func test_ride() -> void:
	var spot := {}
	var w := AdventureWorld.new()
	w.setup(11, 23.0, "coastal", "lighthouse", PACK)
	check(w.route.real != null and absf(w.route.length - 23000.0) < 0.1, "the world rides the real road (%.1f km)" % (w.route.length / 1000.0))
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	var end := Time.get_ticks_msec() + 20000
	var s := 20.0
	var worst := 0.0
	while s < w.route.total - 100.0 and Time.get_ticks_msec() < end + 180000:
		s += 100.0
		spot["p"] = w.transform_at(s).origin
		var t0 := Time.get_ticks_usec()
		await t.get_tree().process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		while Time.get_ticks_usec() - t0 < 16000:
			await t.get_tree().process_frame
	var wait_end := Time.get_ticks_msec() + 20000
	while not w.wanted_chunks().all(func(c): return w.chunks.has(c)) and Time.get_ticks_msec() < wait_end:
		await t.get_tree().process_frame
	check(w.chunks.has(AdventureRoute.chunk_of(s)) and int(w.stats["freed"]) > 20,
		"streamed from the start to the end of the island road (%d chunks freed behind, worst frame %.0f ms)" % [int(w.stats["freed"]), worst])
	w.queue_free()
	await t.get_tree().process_frame


## The magazine's and the crew's side: the Shodoshima page, the real road in the state, and a copy that differs.
func test_magazine() -> void:
	var a := AdventureMag.find("shodoshima")
	var km := floorf(RealPack.get_pack(PACK).max_km())
	check(not a.is_empty() and str(a.get("real", "")) == PACK and km > 20.0, "the magazine has Shodoshima, ridden the whole road (%.0f km)" % km)
	var f := AdventureMag.route_facts(4104, km, "coastal", "lighthouse", PACK)
	check(int(f["fuel"]) >= 1 and int(f["forks"]) == 0, "its facts come from the real road: %s" % str(f))
	var real_path := Progress.path
	Progress.path = "user://test_real_progress.json"
	Shed.start_new("Tester", 5)
	AdventureMag.start_article(a, km)
	check(Adventure.active() and str(Shed.adventure["real"]) == PACK and str(Shed.adventure["real_hash"]) == RealPack.get_pack(PACK).hash,
		"starting it puts the road and its hash in the crew's adventure")
	check(AdventureTrip.real_mismatch(Shed.adventure) == "", "a game with the same road joins")
	var odd: Dictionary = Shed.adventure.duplicate()
	odd["real_hash"] = "0000"
	check(AdventureTrip.real_mismatch(odd).contains("isn't the host's"), "one with another copy of it is told so")
	odd["real"] = "nowhere"
	check(AdventureTrip.real_mismatch(odd).contains("doesn't have"), "and one without it too")
	Shed.request({"a": "adventure_end"})
	check(Adventure.check(Shed.me(), {"a": "adventure_start", "seed": 1, "km": 10.0, "theme": "coastal", "real": "nowhere"}).contains("doesn't have"),
		"the host can't start a road the game hasn't got")
	Shed.stop()
	Progress.path = real_path
	DirAccess.remove_absolute("user://test_real_progress.json")
