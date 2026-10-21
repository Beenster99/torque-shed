extends RefCounted
## The in-game route planner's checks (RoutePlanner planning over a RealRegion), run from tests/run_tests.gd: its
## _test_planner_* functions hand over to these.

const REGION := "shodoshima"
## The baked Shodoshima road (data/routes/shodoshima) starts and ends here; the planner is given the same two pins.
const START := Vector2(34.518638, 134.269646)
const END := Vector2(34.499373, 134.347915)

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func pins() -> Array:
	var r := RealRegion.get_region(REGION)
	return [r.geo_to_xz(START.x, START.y), r.geo_to_xz(END.x, END.y)]


## The same two places the baker took, planned by the game: about the same road.
func test_plan() -> void:
	var r := RealRegion.get_region(REGION)
	var baked := RealPack.get_pack(REGION)
	var res := RoutePlanner.plan(r, {"pins": pins(), "mode": "main", "seed": 1})
	check(bool(res["ok"]), "the planner plans a route between two pins (%s)" % str(res["error"]))
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	check(absf(p.max_km() - baked.max_km()) < 0.04 * baked.max_km(),
		"%.1f km, the baker's was %.1f km" % [p.max_km(), baked.max_km()])
	check(p.x.size() == p.z.size() and p.x.size() == p.e.size() and p.chunks.size() == int(ceil((p.x.size() - 1) / 32.0)),
		"a knot every 4 m with a height each, and a row for each chunk")
	# Heights match the baker's where the two roads coincide.
	var offset := pins()[0] as Vector2
	var worst := 0.0
	var met := 0
	for k in range(0, baked.x.size(), 25):
		var bx := baked.x[k] + offset.x
		var bz := baked.z[k] + offset.y
		var best := INF
		var at := -1
		for j in range(0, p.x.size(), 2):
			var d := Vector2(p.x[j] - bx, p.z[j] - bz).length()
			if d < best:
				best = d
				at = j
		if best < 6.0:
			met += 1
			worst = maxf(worst, absf(p.e[at] - baked.e[k]))
	check(met > baked.x.size() / 25 * 0.7 and worst < 4.0,
		"it follows the baker's road (%d of %d points) with heights within %.1f m" % [met, baked.x.size() / 25, worst])
	# No bend tighter than the bike's, no climb steeper than the grade.
	var tight := 0
	var steep := 0.0
	for i in range(1, p.x.size() - 1):
		var a := Vector2(p.x[i - 1], p.z[i - 1])
		var b := Vector2(p.x[i], p.z[i])
		var c := Vector2(p.x[i + 1], p.z[i + 1])
		var cross := absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
		if 2.0 * cross / maxf(a.distance_to(b) * b.distance_to(c) * a.distance_to(c), 1e-9) > 1.0 / 8.0:
			tight += 1
		steep = maxf(steep, absf(p.e[i + 1] - p.e[i]) / RoutePlanner.STEP)
	check(tight == 0 and steep <= 0.151, "no bend tighter than 8 m radius and no grade over %.1f%%" % (steep * 100.0))
	check(p.junctions.size() > 5 and p.pois.size() > 5 and p.building_count > 100 and p.buildings.size() > 5,
		"with %d junctions, %d places to stop and %d buildings along it" % [p.junctions.size(), p.pois.size(), p.building_count])
	var limited := 0
	for row: Array in p.chunks:
		if int(row[4]) > 0:
			limited += 1
	check(limited == p.chunks.size() and p.name_at(0.0) != "" and p.turns.size() > 5 and str(p.turns[p.turns.size() - 1]["turn"]) == "arrive",
		"every chunk has a name and a limit, and there are turns to the arrival")


## The same pins plan the same route, every time (and on every machine: the hash says so); other pins another.
func test_deterministic() -> void:
	var r := RealRegion.get_region(REGION)
	var a := RoutePlanner.plan(r, {"pins": pins(), "mode": "main", "seed": 1})
	var b := RoutePlanner.plan(r, {"pins": pins(), "mode": "main", "seed": 1})
	check(bool(a["ok"]) and bool(b["ok"]) and (a["pack"] as RealPack).hash == (b["pack"] as RealPack).hash and (a["pack"] as RealPack).x == (b["pack"] as RealPack).x,
		"the same pins plan the same road, with the same hash")
	var c := RoutePlanner.plan(r, {"pins": pins(), "mode": "scenic", "seed": 1})
	check(bool(c["ok"]) and (c["pack"] as RealPack).hash != (a["pack"] as RealPack).hash, "another style of ride is another road")
	var d := RoutePlanner.plan(r, {"pins": [pins()[0], r.geo_to_xz(34.53, 134.22)], "mode": "main"})
	check(bool(d["ok"]) and (d["pack"] as RealPack).hash != (a["pack"] as RealPack).hash and (d["pack"] as RealPack).max_km() < (a["pack"] as RealPack).max_km(),
		"and other pins another")


## Mistakes come back as words, not crashes.
func test_errors() -> void:
	var r := RealRegion.get_region(REGION)
	check(not bool(RoutePlanner.plan(r, {"pins": [Vector2.ZERO]})["ok"]), "one pin is not a journey")
	var far := RoutePlanner.plan(r, {"pins": [pins()[0], Vector2(90000, 90000)]})
	check(not bool(far["ok"]) and str(far["error"]).contains("far"), "a pin in the sea is too far from a road: \"%s\"" % str(far["error"]))
	var same := RoutePlanner.plan(r, {"pins": [pins()[0], pins()[0]]})
	check(not bool(same["ok"]), "the same place twice is nowhere to get to")
	check(not bool(RoutePlanner.plan(r, {"pins": pins(), "mode": "flying"})["ok"]), "and there is no flying style of ride")


## Planning is a job for a worker thread: it must not fill a frame (the heights and tiles load on first use, so the
## second plan is the one timed).
func test_speed() -> void:
	var r := RealRegion.get_region(REGION)
	RoutePlanner.plan(r, {"pins": pins()})
	var res := RoutePlanner.plan(r, {"pins": pins()})
	check(int(res["ms"]) < 4000, "a %.0f km route plans in %d ms %s" % [(res["pack"] as RealPack).max_km(), int(res["ms"]), str(res["parts"])])


## The planned road is ridden like a baked one: the world builds it and streams it end to end.
func test_ride() -> void:
	var r := RealRegion.get_region(REGION)
	var res := RoutePlanner.plan(r, {"pins": pins(), "mode": "main"})
	var p: RealPack = res["pack"]
	RealPack.register(p)
	check(RealPack.get_pack(p.id) == p, "a planned road is found by its id like a baked one")
	var w := AdventureWorld.new()
	w.setup(5, 10.0, "coastal", "lighthouse", p.id)
	check(w.route.real == p and absf(w.route.length - 10000.0) < 0.1, "the world rides the planned road (%.1f km)" % (w.route.length / 1000.0))
	var spot := {}
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	var s := 20.0
	while s < w.route.total - 100.0:
		s += 100.0
		spot["p"] = w.transform_at(s).origin
		await t.get_tree().process_frame
		var held := Time.get_ticks_msec()
		while not w.chunks.has(AdventureRoute.chunk_of(minf(s + 300.0, w.route.total - 1.0))) and Time.get_ticks_msec() - held < 4000:
			await t.get_tree().process_frame
	check(w.chunks.has(AdventureRoute.chunk_of(s)), "and streams it from start to finish (%d chunks freed behind)" % int(w.stats["freed"]))
	w.queue_free()
	await t.get_tree().process_frame


## The crew's pins on the shared board: anyone adds, moves along, removes; the plan comes out; the host starts it.
func test_board() -> void:
	var r := RealRegion.get_region(REGION)
	var saved_adventure = Shed.adventure
	Shed.adventure = {}
	Shed.journey = {}
	var a: Vector2 = pins()[0]
	var b: Vector2 = pins()[1]
	Shed.request({"a": "adventure_pin", "region": REGION, "x": a.x + 40.0, "z": a.y - 30.0})
	check(Shed.journey.has("pins") and (Shed.journey["pins"] as Array).size() == 1, "a pin goes on the board")
	var first: Dictionary = (Shed.journey["pins"] as Array)[0]
	check(r.node_pos[r.nearest_node(float(first["x"]), float(first["z"]), 5.0)].distance_to(Vector2(float(first["x"]), float(first["z"]))) < 0.2,
		"on a road junction (%s)" % str(first))
	check(AdventureJourney.plan_of(Shed.journey).is_empty(), "one pin is no plan yet")
	Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
	Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
	check((Shed.journey["pins"] as Array).size() == 2, "the same place twice in a row isn't put down again")
	var plan := AdventureJourney.plan_of(Shed.journey)
	check(not plan.is_empty() and (plan["pins"] as Array).size() == 2 and plan["region_hash"] == r.hash, "two pins make a plan")
	var res := AdventurePlans.result(plan, true)
	check(bool(res["ok"]) and AdventurePlans.result(plan, true)["pack"] == res["pack"], "that is planned once and kept (%.1f km)" % (res["pack"] as RealPack).max_km())
	Shed.request({"a": "adventure_pin", "region": REGION, "x": 1.0e6, "z": 0.0})
	check((Shed.journey["pins"] as Array).size() == 2, "a pin far from any road is refused")
	Shed.request({"a": "adventure_mode", "mode": "scenic"})
	var scenic := AdventureJourney.plan_of(Shed.journey)
	check(AdventurePlans.key(scenic) != AdventurePlans.key(plan) and str(Shed.journey["mode"]) == "scenic", "another style of ride is another plan")
	# Round trip through the sync (the other players get it like this).
	check(AdventureJourney.sanitize(Shed.journey) == Shed.journey, "the board survives being sent to the crew")
	# The host starts it.
	Shed.request({"a": "adventure_mode", "mode": "main"})
	var go := AdventureJourney.plan_of(Shed.journey)
	Shed.request({"a": "adventure_start", "plan": go, "seed": 77, "title": "Across the island"})
	var adv: Dictionary = Shed.adventure
	check(int(adv.get("id", 0)) != 0 and adv.get("plan") is Dictionary and str(adv["real"]).begins_with("plan_"), "the host starts the adventure along the plan")
	var pack := RealPack.get_pack(str(adv.get("real", "")))
	check(pack != null and pack.hash == str(adv["real_hash"]) and absf(float(adv["km"]) - pack.max_km()) < 0.11 and str(adv["theme"]) == "coastal",
		"it is ridden at the road's own length (%.1f km), dressed for the coast" % float(adv.get("km", 0.0)))
	check(AdventureTrip.real_mismatch(adv) == "", "and this game agrees it is the host's road")
	var other := adv.duplicate(true)
	other["real_hash"] = "0000000000000000"
	check(AdventureTrip.real_mismatch(other) != "", "while a road that came out differently is refused: \"%s\"" % AdventureTrip.real_mismatch(other))
	var gone := adv.duplicate(true)
	(gone["plan"] as Dictionary)["region"] = "nowhere"
	check(AdventureTrip.real_mismatch(gone) != "", "as is a map this game doesn't have")
	var kept := Adventure.sanitize(adv)
	check(kept.get("plan") is Dictionary and kept["real"] == adv["real"] and kept["real_hash"] == adv["real_hash"], "a joiner's copy keeps the plan")
	Shed.request({"a": "adventure_clear"})
	check(Shed.journey.is_empty(), "the board is wiped clean")
	Shed.adventure = saved_adventure


## The map: opens on the region, a click pins a road junction, a click on a pin takes it off, the panel and the plan follow.
func test_map() -> void:
	var r := RealRegion.get_region(REGION)
	Shed.adventure = {}
	Shed.journey = {}
	var map := JourneyMap.new()
	t.add_child(map)
	map.open(REGION)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	check(map.visible and map.region == r and map._scale > 0.0, "the map opens on the region, all of it in view")
	var a: Vector2 = pins()[0]
	var b: Vector2 = pins()[1]
	map.click(map._to_screen(a))
	map.click(map._to_screen(b))
	check((Shed.journey["pins"] as Array).size() == 2, "a click on the map puts a pin down")
	map.refresh()
	await t.get_tree().process_frame
	check(map._pin_box.get_child_count() == 2, "and the panel lists it")
	var end := Time.get_ticks_msec() + 20000
	while map._route_pts.size() < 2 and Time.get_ticks_msec() < end:
		await t.get_tree().process_frame
		map.refresh()
		await t.get_tree().create_timer(0.1).timeout
	check(map._route_pts.size() > 100 and "km" in map._facts.text, "the road is planned and shown (%s)" % map._facts.text.split("\n")[0])
	check(not map._start.disabled, "and the host can start it")
	map.click(map._to_screen(Vector2(float(Shed.journey["pins"][1]["x"]), float(Shed.journey["pins"][1]["z"]))))
	check((Shed.journey["pins"] as Array).size() == 1, "a click on a pin takes it off")
	map.refresh()
	check(map._start.disabled and "Pin where you start" in map._facts.text, "with one pin there is nothing to start")
	var img := JourneyMap.shade_image(r)
	check(img.get_width() > 100 and img.get_height() > 50 and img.get_pixel(img.get_width() / 2, img.get_height() / 2).a >= 0.0, "the land is shaded for the map (%d x %d)" % [img.get_width(), img.get_height()])
	map.queue_free()
	Shed.journey = {}
	await t.get_tree().process_frame
	# The magazine has the page that opens it.
	var art := AdventureMag.find("shodoshima_plan")
	check(not art.is_empty() and str(art["region"]) == REGION and AdventureMag.unlocked(art, 1), "the magazine has the Shodoshima page that opens the map")


## A pin the road has to go out to and back from (not just a dead-end street) is visited, and the way in is not
## cut out of the route as a spur.
func test_via() -> void:
	var r := RealRegion.get_region(REGION)
	var mid := r.geo_to_xz(34.53, 134.22)
	var res := RoutePlanner.plan(r, {"pins": [pins()[0], mid, pins()[1]]})
	check(bool(res["ok"]), "a journey with a stop in the middle plans")
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	var node := r.nearest_connected(mid.x, mid.y, 800.0)
	var best := INF
	for k in range(0, p.x.size()):
		best = minf(best, Vector2(p.x[k], p.z[k]).distance_to(r.node_pos[node]))
	var direct := RoutePlanner.plan(r, {"pins": pins()})["pack"] as RealPack
	check(best < 80.0 and p.max_km() > direct.max_km() + 0.5, "it goes out to the stop and turns round there (%.0f m short at the nearest) and the road is longer for it (%.1f km, %.1f direct)" % [best, p.max_km(), direct.max_km()])
	# A pin 100 m up a dead-end street is not driven into: the spur is shorter than SPUR_M each way.
	var steps: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(1, 0, 0)]
	check(RoutePlanner.strip_spurs(r, steps).is_empty() == (r.edge_len[0] <= RoutePlanner.SPUR_M), "an out-and-back of %.0f m is %s" % [r.edge_len[0], "cut out" if r.edge_len[0] <= RoutePlanner.SPUR_M else "kept"])


## A small graph of the tests' own: A-B-C along the bottom, B-D up, and A-D across.
func _square() -> RealRegion:
	return RealRegion.from_rows({"classes": ["primary", "tertiary"], "surfaces": ["tarmac"], "names": [""],
		"nodes": [[0, 0], [1000, 0], [2000, 0], [1000, 800]],
		"edges": [{"a": 0, "b": 1, "c": 0, "s": 0, "l": 0, "n": 0, "o": 1, "p": []},
			{"a": 1, "b": 2, "c": 0, "s": 0, "l": 0, "n": 0, "o": -1, "p": []},
			{"a": 1, "b": 3, "c": 1, "s": 0, "l": 0, "n": 0, "o": 0, "p": []},
			{"a": 0, "b": 3, "c": 1, "s": 0, "l": 0, "n": 0, "o": 0, "p": []}],
		"bans": [[3, 3, 2]]})


## One-way roads are driven their way only, and a prohibited turn is not taken.
func test_rules() -> void:
	var r := _square()
	check(r.passable(0, 0) and not r.passable(0, 1) and r.passable(1, 2) and not r.passable(1, 1) and r.passable(2, 3),
		"a one-way road is passable from its open end only")
	check(r.turn_banned(3, 3, 2) and not r.turn_banned(2, 3, 3), "the banned turn is known, its reverse isn't")
	var costs := PackedFloat64Array([1.0, 1.0])
	var ab = RoutePlanner._shortest(r, 0, 1, costs)
	check(ab != null and (ab as Array).size() == 1 and (ab as Array)[0].y == 0, "A to B goes straight along the one-way road")
	var ba = RoutePlanner._shortest(r, 1, 0, costs)
	check(ba != null and (ba as Array).size() == 2 and (ba as Array)[0].y == 2 and (ba as Array)[1].y == 3, "B to A can't go back along it: round by D")
	check(RoutePlanner._shortest(r, 1, 2, costs) == null, "B to C is against the one-way and there is no way round")
	var cb = RoutePlanner._shortest(r, 2, 1, costs)
	check(cb != null and (cb as Array).size() == 1, "C to B is with it")
	var ad = RoutePlanner._shortest(r, 0, 3, costs)
	check(ad != null and (ad as Array).size() == 1 and (ad as Array)[0].y == 3, "A to D takes the direct road")
	var ab2 = RoutePlanner._shortest(r, 0, 1, PackedFloat64Array([10.0, 1.0]))
	check(ab2 != null and (ab2 as Array).size() == 1 and (ab2 as Array)[0].y == 0, "A to B still can't go A-D-B: the turn at D onto D-B is banned, so the dear road it is")
	var db = RoutePlanner._shortest(r, 3, 1, PackedFloat64Array([10.0, 1.0]))
	check(db != null and (db as Array)[0].y == 2, "but from D itself the road to B is fine (no turn to ban)")


## A planned road has forks where the roads offer another way: the other way is a road of its own that meets the main
## road at both ends, and the adventure rides it like a baked fork.
func test_forks() -> void:
	var r := RealRegion.get_region(REGION)
	var res := RoutePlanner.plan(r, {"pins": pins(), "mode": "scenic", "seed": 3})
	var p: RealPack = res["pack"]
	check(bool(res["ok"]) and p.forks.size() >= 1, "the scenic island road has %d fork(s) (%d ms for them)" % [p.forks.size(), int(res["parts"].get("forks", 0)) - int(res["parts"].get("places", 0))])
	if p.forks.is_empty():
		return
	var ok := true
	for row: Dictionary in p.forks:
		var way: Dictionary = row["way"]
		var n := int(way["n"])
		var i0 := int(row["i0"])
		var i1 := int(row["i1"])
		var wx: PackedFloat64Array = way["x"]
		var wz: PackedFloat64Array = way["z"]
		var we: PackedFloat32Array = way["e"]
		if (n - 1) % 32 != 0 or i0 % 32 != 0 or i1 % 32 != 0 or i1 <= i0 or wx.size() != n or we.size() != n:
			ok = false
		if Vector2(wx[0] - p.x[i0], wz[0] - p.z[i0]).length() > 0.01 or Vector2(wx[n - 1] - p.x[i1], wz[n - 1] - p.z[i1]).length() > 0.01:
			ok = false
		if absf(we[0] - p.e[i0]) > 0.01 or absf(we[n - 1] - p.e[i1]) > 0.01:
			ok = false
		var line := PackedVector2Array()
		for k in n:
			line.append(Vector2(wx[k], wz[k]))
		if (way["chunks"] as Array).size() != (n - 1) / 32 or RoutePlanner.sharpest_turn(line) > RoutePlanner.MAX_TURN:
			ok = false
		var kinds: Array = row["kinds"]
		if kinds[0] != "main" or not ["scenic", "gravel"].has(str(kinds[1])) or str((row["names"] as Dictionary)[kinds[1]]) == "":
			ok = false
	check(ok, "each fork's other way runs from the main road's knot i0 to i1 in whole chunks, with their heights and a name")
	# The adventure rides it.
	RealPack.register(p)
	var route := AdventureRoute.new()
	route.plan_real(p, 3, p.max_km(), [])
	check(route.forks.size() == p.forks.size(), "the adventure has the planned forks (%d)" % route.forks.size())


## Finding places on the map: the region's towns and villages by name, and suggestions with nothing typed.
func test_places() -> void:
	var r := RealRegion.get_region(REGION)
	check(r.places.size() >= 30 and r.places.all(func(p): return str(p["name"]) != "" and ["town", "village"].has(str(p["kind"]))),
		"the region has %d towns and villages with names we can print" % r.places.size())
	var hits := JourneyMap.find_places(r, "fuku")
	check(hits.size() >= 1 and str(hits[0]["name"]).to_lower().contains("fuku"), "typing part of a name finds it (%s)" % str(hits.map(func(h): return h["name"])))
	check(JourneyMap.find_places(r, "zzzz").is_empty(), "and a name that isn't there finds nothing")
	var sug := JourneyMap.find_places(r, "")
	var apart := true
	for i in sug.size():
		for j in range(i + 1, sug.size()):
			if Vector2(float(sug[i]["x"]) - float(sug[j]["x"]), float(sug[i]["z"]) - float(sug[j]["z"])).length() < 3000.0:
				apart = false
	check(sug.size() >= 4 and sug.size() <= 8 and apart, "with nothing typed, %d suggested places spread about the island (%s)" % [sug.size(), str(sug.map(func(h): return h["name"]))])
	var oneway := 0
	for ei in r.edge_count():
		if r.edge_oneway[ei] != 0:
			oneway += 1
	check(oneway == int(r.counts.get("oneway", -1)) and oneway > 0, "%d one-way roads, as the bake counted" % oneway)
