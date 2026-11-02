extends RefCounted
## Ferries' checks (Ride Anywhere v2, phase D round 3, D7: scripts/ferry_links.gd, scripts/scenery/ferry.gd,
## scripts/ferry_crossing.gd and the ferry leg in the planner, the route, the sat nav and the crew), run from
## tests/run_tests.gd: its _test_ferry_* functions hand over to these. A made-up place of its own (road_block_tests.gd's
## graphs): a mainland and an island 600 m across the water, a ferry between; no scene and no network. Crossing for
## real, solo and as a crew, is tests/mp_ferry.gd's.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The mainland (a main road east from 0 to the terminal at 1000, 0, a lane north off it) and the island (from its
## terminal at 1600, 0, a main road east to 2600, a lane north): two road pieces, the sea between x 1010 and 1590.
## With `ferries`, the ferry between (in two pieces, cut at 1300 as a cell's edge cuts one, one drawn backwards), a
## foot ferry off up the coast to nowhere, and the terminals' offices.
static func island(ferries := true) -> RealRegion:
	var r := Roads.graph([[0, 0], [1000, 0], [1000, 400], [1600, 0], [2600, 0], [1600, 400]],
		[[0, 1, "primary"], [1, 2, "residential"], [3, 4, "primary"], [3, 5, "residential"]])
	r.features = {"points": [], "lines": [], "areas": []}
	if ferries:
		r.features["lines"] = [
			["ferry", PackedVector2Array([Vector2(1010, 0), Vector2(1200, 20), Vector2(1300, 20)]), null, null, 0, "Sound Ferry", "f1"],
			["ferry", PackedVector2Array([Vector2(1590, 0), Vector2(1400, 20), Vector2(1300, 20)]), null, null, 0, "Sound Ferry", "f1"],
			["ferry", PackedVector2Array([Vector2(1010, 410), Vector2(1100, 2000)]), null, null, 0, "", "away"],
		]
		r.features["points"] = [
			["ferry_terminal", 985.0, 30.0, null, null, null, "", "office_a"],
			["ferry_terminal", 1615.0, 30.0, null, null, null, "", "office_b"],
		]
	return r


## The made-up place's land: the sea between the shores, 5 m up either side.
static func land(x: float, _z: float) -> float:
	return -6.0 if x > 1010.0 and x < 1590.0 else 5.0


## The links made from the map: the ferry's pieces joined, its ends on the junctions where the road meets the water,
## the road pieces joined by it; the foot ferry kept for the scenery but no link; its size, crossing time and cost.
func test_links() -> void:
	var r := island()
	var links := FerryLinks.of(r)
	check(links.links.size() == 1, "one link from the ferry's two pieces (%d)" % links.links.size())
	if links.links.is_empty():
		return
	var l: Dictionary = links.links[0]
	check([int(l["a"]), int(l["b"])] in [[1, 3], [3, 1]], "between the two terminals' junctions (%d, %d)" % [int(l["a"]), int(l["b"])])
	var pts: PackedVector2Array = l["pts"]
	check(pts.size() == 7 and absf(float(l["m"]) - FerryLinks._length(pts)) < 0.01 and float(l["m"]) > 580.0 and float(l["m"]) < 640.0,
		"its line junction to junction, the pieces joined end to end (%d points, %.0f m)" % [pts.size(), float(l["m"])])
	check(str(l["name"]) == "Sound Ferry" and str(l["id"]) == "f1" and str(l["size"]) == "roro", "named, and a roll-on roll-off ferry (%s)" % str(l["size"]))
	check(links.routes.size() == 2, "the foot ferry to nowhere's a route the scenery sails, not a link (%d routes)" % links.routes.size())
	check(r.component[0] != r.component[4] and links.joined(r.component[0], r.component[4]) and links.joined(r.component[4], r.component[4]),
		"the mainland and the island are two road pieces, joined by the ferry")
	check(links.other_end(0, 1) == 3 and links.line_from(0, 3)[0] == r.node_pos[3] and links.find("f1", 3, 1) == 0 and links.find("f1", 1, 2) == -1,
		"each end's other, its line from either end, found by id and ends")
	check(links.hash.length() == 12 and FerryLinks.of(r) == links and FerryLinks.new(island()).hash == links.hash,
		"its hash, the same from the same map, and worked out once a region")
	check(FerryLinks.new(island(false)).is_empty() and FerryLinks.new(island(false)).hash == "", "no ferries, no links and no hash")
	check(r.hash == "fixture", "the region's own hash left as it was")
	# Sizes, crossing times and what the planner counts a crossing as.
	check(FerryLinks.size_of("", 150.0) == "chain" and FerryLinks.size_of("Cowes Floating Bridge", 600.0) == "chain"
		and FerryLinks.size_of("", 600.0) == "roro" and FerryLinks.size_of("", 22000.0) == "ship", "chain ferry, ro-ro and big ship by length and name")
	check(FerryLinks.seconds_of(100.0) == FerryLinks.CROSS_LEAST and FerryLinks.seconds_of(50000.0) == FerryLinks.CROSS_MOST
		and absf(links.seconds(0) - float(l["m"]) / FerryLinks.SPEED) < 0.01, "about a minute aboard: %.0f s for this one" % links.seconds(0))
	var costs := PackedFloat64Array([1.0, 1.5, 3.0])
	check(absf(links.cost(0, costs) - (FerryLinks.BOARD_COST + float(l["m"]) * FerryLinks.COST_PER_M)) < 0.01,
		"a crossing costs boarding and its length, at the cheapest road's rate")
	# A long crossing's open sea has no cells baked: its route comes as the pieces by either shore, apart (Holyhead to
	# Dublin), and is joined across the gap.
	var apart := island()
	(apart.features["lines"][0] as Array)[1] = PackedVector2Array([Vector2(1010, 0), Vector2(1200, 20), Vector2(1250, 20)])
	(apart.features["lines"][1] as Array)[1] = PackedVector2Array([Vector2(1590, 0), Vector2(1400, 20), Vector2(1350, 20)])
	var across := FerryLinks.new(apart)
	check(across.links.size() == 1 and (across.links[0]["pts"] as PackedVector2Array).size() == 8 and across.routes.size() == 2,
		"a route's pieces with open sea between them joined across it, into one link (%d)" % across.links.size())
	(apart.features["lines"][1] as Array)[6] = "other"
	check(FerryLinks.new(apart).links.is_empty(), "but never two routes' pieces")


## The planner routes over the water where the roads don't go, says so, and plans a route that doesn't cross the
## same as before: the same steps and the same hash.
func test_plan() -> void:
	var r := island()
	var res := RoutePlanner.plan(r, {"pins": [Vector2(0, 0), Vector2(2600, 0)], "mode": "main", "seed": 1})
	check(bool(res["ok"]), "a route to the island (%s)" % str(res["error"]))
	var none := RoutePlanner.plan(island(false), {"pins": [Vector2(0, 0), Vector2(2600, 0)], "mode": "main", "seed": 1})
	check(not bool(none["ok"]), "and none without its ferry (%s)" % str(none["error"]))
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	check(p.ferries.size() == 1, "one crossing (%s)" % str(p.ferries))
	if p.ferries.size() != 1:
		return
	var f: Dictionary = p.ferries[0]
	check(int(f["from"]) == 1 and int(f["to"]) == 3 and str(f["id"]) == "f1" and str(f["name"]) == "Sound Ferry"
		and float(f["seconds"]) > 60.0 and str(f["size"]) == "roro", "from the mainland's terminal to the island's (%s)" % str(f))
	var step := int(f["step"])
	check(step == 1 and p.steps[step * 3] == 3 and p.steps[step * 3 - 1] == 1, "between the road to the water and the road on (%s)" % str(p.steps))
	check((p.summary.get("ferries", []) as Array).size() == 1, "and the route's summary tells of it")
	check(p.max_km() > 2.5 and p.max_km() < 2.8, "the ride's length takes the crossing in (%.2f km)" % p.max_km())
	# A route that doesn't cross: as it was without ferries on the map.
	var plain := {"pins": [Vector2(0, 0), Vector2(1000, 400)], "mode": "main", "seed": 1}
	var with: Dictionary = RoutePlanner.plan(island(), plain)
	var without: Dictionary = RoutePlanner.plan(island(false), plain)
	check(bool(with["ok"]) and bool(without["ok"]) and (with["pack"] as RealPack).hash == (without["pack"] as RealPack).hash
		and (with["pack"] as RealPack).steps == (without["pack"] as RealPack).steps and (with["pack"] as RealPack).ferries.is_empty(),
		"a route on the mainland plans and hashes as it did before ferries")
	var back := RoutePlanner.plan(r, {"pins": [Vector2(2600, 0), Vector2(0, 0)], "mode": "main", "seed": 1})
	check(bool(back["ok"]) and int(((back["pack"] as RealPack).ferries[0] as Dictionary)["from"]) == 3, "and back the other way")
	check(p.hash != (back["pack"] as RealPack).hash and RoutePlanner.plan(r, {"pins": [Vector2(0, 0), Vector2(2600, 0)], "mode": "main", "seed": 1})["pack"].hash == p.hash,
		"the same journey hashes the same, another differently")


## The route and the sat nav: the crossing's a leg's end, the way ahead stops at the water with "Take the ferry", and
## the rider landed on the far side is on along the route from there.
func test_nav() -> void:
	var r := island()
	var res := RoutePlanner.plan(r, {"pins": [Vector2(0, 0), Vector2(2600, 0)], "mode": "main", "seed": 1})
	if not bool(res["ok"]):
		check(false, "a route to the island to follow")
		return
	var p: RealPack = res["pack"]
	var route := NetRoute.of_pack(p, r)
	var step := int((p.ferries[0] as Dictionary)["step"])
	check(not route.ferry_before(step).is_empty() and route.ferry_before(0).is_empty() and route.next_ferry(0) == step and route.next_ferry(step + 1) == -1,
		"the route knows the crossing before step %d" % step)
	var steps: Array[Vector2i] = []
	for i in route.edges.size():
		steps.append(Vector2i(route.edges[i], route.froms[i]))
	var plain := NetRoute.new(r, steps, p.pin_nodes, p.run_start)
	var again := NetRoute.new(r, steps, p.pin_nodes, p.run_start, "main", p.ferries)
	check(plain.hash != route.hash and again.hash == route.hash and route.at_m[step] - route.at_m[step - 1] > 1500.0,
		"its hash takes the crossing in, and its metres (%.0f to the far side)" % (route.at_m[step] - route.at_m[step - 1]))
	var net := RoadNet.new(r, land)
	var nav := NetNav.new(null, net, route)
	nav.threaded = false
	var was: Dictionary = Shed.adventure
	Shed.adventure = {}
	nav.update(Vector2(500, 0), Vector2(1, 0))
	check(nav.status == "on_route" and nav.progress == 0, "on the mainland's road, on the route (%s %d)" % [nav.status, nav.progress])
	check(nav.steps_ahead().size() == step, "the way ahead stops at the water (%d steps)" % nav.steps_ahead().size())
	check(str(nav.ferry_ahead().get("id", "")) == "f1", "with the ferry at its end")
	var j := nav.next_junction(800.0)
	check(str(j.get("type", "")) == "ferry" and str(j.get("text", "")) == "Take the ferry: Sound Ferry" and absf(float(j.get("distance", 0.0)) - 500.0) < 5.0,
		"\"Take the ferry\" 500 m on (%s)" % str(j))
	var ahead := nav.line_ahead(900.0)
	check(not ahead.is_empty() and ahead[ahead.size() - 1].x > 1100.0, "the line ahead drawn on over the water (to %s)" % str(ahead[ahead.size() - 1] if not ahead.is_empty() else null))
	nav.landed(step)
	check(nav.status == "on_route" and nav.progress == step, "landed: on along the route from the far side (%s %d)" % [nav.status, nav.progress])
	Shed.adventure = {}
	nav.update(Vector2(1700, 0), Vector2(1, 0))
	check(nav.status == "on_route" and nav.progress >= step, "and riding on there (%s %d)" % [nav.status, nav.progress])
	Shed.adventure = was


## The crew's sailing (AdventureCrew): aboard at the ramp, away once all are (or most, after a wait), cleared once all
## who went have landed (or long after), and junk from the wire made safe.
func test_crew() -> void:
	check(AdventureCrew.sanitize_ferry(null).is_empty() and AdventureCrew.sanitize_ferry({"sail": 0, "id": "x"}).is_empty()
		and AdventureCrew.sanitize_ferry({"sail": 1, "id": ""}).is_empty(), "no sailing from junk")
	var s := AdventureCrew.sanitize_ferry({"sail": 2, "id": "f1", "from": 1, "to": 3, "seconds": 9999, "aboard": {"1": true}, "landed": "x"})
	check(float(s["seconds"]) == FerryLinks.CROSS_MOST and (s["aboard"] as Dictionary).has(1) and (s["landed"] as Dictionary).is_empty(),
		"a sailing's crossing kept to a minute or so, its peers as numbers")
	var riders := [1, 7]
	check(AdventureCrew.board_check({}, 9, "f1", 1, riders) != "", "only those out on the ride go aboard")
	check(AdventureCrew.board_check({}, 1, "", 1, riders) != "", "only at a ferry")
	check(AdventureCrew.board_check({}, 1, "f1", 1, riders) == "", "the first aboard starts a sailing")
	var f := AdventureCrew.board({}, 1, "f1", 1, 3, 66.7, 1, 1000)
	check(int(f["sail"]) == 1 and int(f["departs"]) == 0 and int(f["since"]) == 1000 and (f["aboard"] as Dictionary).has(1), "aboard, at the ramp")
	check(AdventureCrew.board_check(f, 1, "f1", 1, riders) != "" and AdventureCrew.board_check(f, 7, "f2", 1, riders) != ""
		and AdventureCrew.board_check(f, 7, "f1", 3, riders) != "" and AdventureCrew.board_check(f, 7, "f1", 1, riders) == "",
		"the rest of the crew may join it, at its ramp")
	check(not AdventureCrew.should_sail(f, riders, 1000 + int(AdventureCrew.FERRY_WAIT * 1000.0) - 1) and AdventureCrew.should_sail(f, riders, 1000 + int(AdventureCrew.FERRY_WAIT * 1000.0)),
		"half the crew aboard: it waits a while, then goes")
	check(AdventureCrew.should_sail(f, [1], 1000), "alone: away at once")
	check(not AdventureCrew.should_sail(f, [1, 7, 8], 999999), "a third aboard: it waits on")
	check(Array(AdventureCrew.ferry_waiting(f, {7: {"name": "Sam"}}, riders)) == ["Sam"], "the crew told who's still to come")
	var all := AdventureCrew.board(f, 7, "f1", 1, 3, 66.7, 1, 5000)
	check(not AdventureCrew.should_sail(all, riders, 1500) and AdventureCrew.should_sail(all, riders, 1000 + int(AdventureCrew.FERRY_ALL_IN * 1000.0)),
		"everyone aboard: away a moment later")
	all["departs"] = 6000
	check(AdventureCrew.board_check(all, 8, "f1", 1, [1, 7, 8]) != "", "once it's gone, it's gone")
	var total := FerryCrossing.total_of(all)
	check(not AdventureCrew.sailing_over(f, riders, 999999, total) and not AdventureCrew.sailing_over(all, riders, 7000, total), "not over while at the ramp or sailing")
	(all["landed"] as Dictionary)[1] = true
	check(not AdventureCrew.sailing_over(all, riders, 7000, total) and AdventureCrew.sailing_over(all, [1], 7000, total), "over once all who are still on the ride have landed")
	check(AdventureCrew.sailing_over(all, riders, 6000 + int((total * AdventureCrew.FERRY_LATE + 120.0) * 1000.0) + 1, total), "or long after (a game that dropped out)")
	(all["landed"] as Dictionary)[7] = true
	check(AdventureCrew.sailing_over(all, riders, 7000, total), "or when everyone's off")
	# Ridden off again before it sails: off it, and with nobody left aboard there's no sailing (the next on starts one).
	var two := AdventureCrew.board(f, 7, "f1", 1, 3, 60.0, 1, 1200)
	var one := AdventureCrew.got_off(two, 7, 1)
	check((one["aboard"] as Dictionary).keys() == [1] and AdventureCrew.got_off(one, 1, 1).is_empty()
		and AdventureCrew.got_off(one, 1, 2) == one and AdventureCrew.got_off(all, 1, int(all["sail"])) == all,
		"off again before it sails: off it, the sailing gone once nobody's aboard (not once it's left)")


## The crossing's timeline: a short route sailed all the way, easing out and in; a long one out of one harbour and
## into the other, its open water passed in the dark; and the scenery's boats on their timetables.
func test_timeline() -> void:
	var m := 600.0
	var secs := FerryLinks.seconds_of(m)
	var last := -1.0
	var smooth := true
	for k in 200:
		var tau := k * (FerryCrossing.PREP + secs + 1.0) / 199.0
		var tl := FerryCrossing.timeline(m, secs, tau)
		smooth = smooth and float(tl["s"]) >= last - 0.001 and float(tl["s"]) - last < 15.0 and float(tl["fade"]) == 0.0
		last = float(tl["s"])
	check(smooth and absf(last - m) < 0.01 and float(FerryCrossing.timeline(m, secs, 0.0)["s"]) == 0.0, "a short crossing sailed all the way, no jump")
	check(FerryCrossing.total_of({"seconds": secs}) == FerryCrossing.PREP + secs + FerryCrossing.DOCK, "ramp up, the crossing, tying up")
	var big := 22000.0
	var long_s := FerryLinks.seconds_of(big)
	var mid := FerryCrossing.timeline(big, long_s, FerryCrossing.PREP + long_s * 0.5)
	var start := FerryCrossing.timeline(big, long_s, FerryCrossing.PREP + 5.0)
	var end := FerryCrossing.timeline(big, long_s, FerryCrossing.PREP + long_s)
	check(float(mid["fade"]) > 0.99 and float(start["fade"]) == 0.0 and float(start["s"]) < 100.0 and absf(float(end["s"]) - big) < 0.01,
		"a long one: out of the harbour, the dark over the open water, into the other (%.0f m in 5 s)" % float(start["s"]))
	# The scenery's boats: on the route, the same on every machine, a whole number of trips a day.
	var day := 1200.0
	var ok := true
	for k in 100:
		var at := FerryScenery.boat_on(m, k * 37.0, FerryScenery.offset_of("f1"), day)
		ok = ok and at.x >= 0.0 and at.x <= m and absf(at.y) == 1.0 and at == FerryScenery.boat_on(m, k * 37.0 + day, FerryScenery.offset_of("f1"), day)
	check(ok, "the scenery's boats on their route, back and forth, the same each day")
	check(FerryScenery.offset_of("f1") == FerryScenery.offset_of("f1") and FerryScenery.offset_of("f1") != FerryScenery.offset_of("f2"), "each route its own timetable")


## Every region's ferry and terminal kit names this script's models, each with a mesh; every size of boat in every
## region's colours has one.
func test_kits() -> void:
	var bad := []
	for region in [""] + RegionKit.regions():
		var k := SceneryStreamer.kit("ferry", region)
		var o := SceneryStreamer.kit("ferry_terminal", region)
		if str(k.get("model", "")) != "ferry:ramp" or str(o.get("model", "")) != "ferry:hut":
			bad.append(region)
			continue
		for size: String in FerryScenery.BOATS:
			if FerryScenery.boat_mesh(size, k).get_surface_count() == 0:
				bad.append("%s %s" % [region, size])
	check(bad.is_empty() and RegionKit.regions().size() == 13, "a ferry kit for each of the 13 regions and a default (%s)" % str(bad))
	check(FerryScenery.mesh("ramp").get_surface_count() > 0 and FerryScenery.mesh("gantry").get_surface_count() > 0
		and FerryScenery.mesh("hut_d8d2c4").get_surface_count() > 0, "the ramp, its gantry and the office have meshes")
	check(FerryScenery.slot_at("chain", 0) != FerryScenery.slot_at("chain", 1) and is_equal_approx(FerryScenery.slot_at("ship", 0).y, float(FerryScenery.BOATS["ship"]["deck"])),
		"a bike's slot each, on the deck")
	var fits := true
	for size: String in FerryScenery.BOATS:
		var b: Dictionary = FerryScenery.BOATS[size]
		var seen := {}
		for slot in 4:
			var at := FerryScenery.slot_at(size, slot)
			seen[at] = true
			fits = fits and absf(at.z) < float(b["len"]) * 0.5 and absf(at.x) < float(b["beam"]) * 0.5
		fits = fits and seen.size() == 4 and float(b["len"]) <= 32.0
	check(fits, "every boat's small (two to four cars) and takes the crew's four bikes")
	# Drive-through: the lane down the deck clear of everything solid from one ramp's hinge to the other's, the cabin
	# beside it; on the deck is aboard, over the side isn't.
	var clear := true
	for size: String in FerryScenery.BOATS:
		var b: Dictionary = FerryScenery.BOATS[size]
		var lane: Vector2 = b["lane"]
		for part: Array in FerryScenery.solids(size).slice(1):
			var box := AABB((part[0] as Vector3) - (part[1] as Vector3) * 0.5, part[1])
			var path := AABB(Vector3(lane.x + 0.1, float(b["deck"]) + 0.05, -float(b["half"])), Vector3(lane.y - lane.x - 0.2, 2.0, float(b["half"]) * 2.0))
			clear = clear and not box.intersects(path)
		clear = clear and lane.y - lane.x > 5.0 and FerryScenery.hinge(size, 1.0).z == float(b["half"]) and FerryScenery.hinge(size, -1.0).z == -float(b["half"])
		clear = clear and FerryScenery.on_deck(size, FerryScenery.slot_at(size, 3) + Vector3.UP * 0.4) \
			and not FerryScenery.on_deck(size, Vector3(float(b["beam"]), float(b["deck"]), 0.0)) and not FerryScenery.on_deck(size, Vector3(0, -3.0, 0))
		clear = clear and FerryScenery.boat_mesh(size, {}, false).get_surface_count() > 0 and FerryScenery.flap_mesh(size, {}).get_surface_count() > 0
	check(clear, "every boat's drive-through: a clear lane from end to end, more than 5 m wide, a ramp at each end and the cabin beside it")


## A block at the mainland's terminal: its ramp at the road's end out over the water, its office off the road, the
## boats passing for dress; a model a draw call, laid out quickly; and nothing on the road.
func test_lay_out() -> void:
	var r := island()
	var net := RoadNet.new(r, land)
	var rows := {"points": [], "lines": [], "areas": []}
	var key := Vector2i(int(floor(1000.0 / RoadBlock.SIZE)), 0)
	for part in rows:
		for row: Array in r.features[part]:
			if part != "points" or SceneryStreamer.in_block(key, Vector2(float(row[1]), float(row[2]))):   # (the streamer's rows: the block's own)
				(rows[part] as Array).append([row, SceneryStreamer.kit(str(row[0]), "")])
	FerryScenery.lay_out(net, key, rows)   # (once to warm the roads' lookups, as a ride's are by the time it's streaming)
	var t0 := Time.get_ticks_usec()
	var b := FerryScenery.lay_out(net, key, rows)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var items: Dictionary = b["items"]
	var corner := Vector2(key) * RoadBlock.SIZE
	var ramps: Array = items.get("ramp", [])
	check(ramps.size() == 1 and Vector2((ramps[0] as Transform3D).origin.x + corner.x, (ramps[0] as Transform3D).origin.z + corner.y).distance_to(r.node_pos[1]) < 3.5,
		"a ramp where the road meets the water, out on its bank (%d)" % ramps.size())
	if ramps.size() == 1:
		var fwd := -(ramps[0] as Transform3D).basis.z.normalized()
		check(fwd.x > 0.9, "facing out over the water (%s)" % str(fwd))
	var huts: Array = []
	for m: String in items:
		if m.begins_with("hut_"):
			huts.append_array(items[m])
	var on_road := 0
	for xf: Transform3D in huts:
		var on := net.locate(xf.origin.x + corner.x, xf.origin.z + corner.y)
		on_road += int(not on.is_empty() and bool(on["on_road"]))
	check(huts.size() == 1 and on_road == 0, "the office by the terminal, off the road (%d, %d on it)" % [huts.size(), on_road])
	var dress: Dictionary = b.get("dress", {})
	var ids := (dress.get("boats", []) as Array).map(func(x): return str(x["id"]))
	check(ids.has("f1") and ids.has("away") and bool(dress.get("lamps", false)), "the boats passing, the foot ferry's too, and the office's lamps (%s)" % str(ids))
	check(items.size() <= 4 and (items.get("gantry", []) as Array).size() == ramps.size(), "a draw call a model (%s)" % str(items.keys()))
	check(ms < 2.0, "laid out in %.2f ms (under 2)" % ms)
	var island_key := Vector2i(int(floor(1600.0 / RoadBlock.SIZE)), 0)
	check((FerryScenery.lay_out(net, island_key, rows)["items"].get("ramp", []) as Array).size() == 1, "and the island's ramp in its own block")
	# A route drawn over a headland by the shore: the boat lies on from the ramp where the ground's under the water,
	# never on the land.
	var line := PackedVector2Array([Vector2(1000, 0), Vector2(1600, 0)])
	var headland := func(x: float, _z: float) -> float: return -6.0 if x > 1200.0 else 4.0
	var afloat := FerryScenery.lies(line, headland, 0.0)
	check(afloat > 200.0 and afloat < 200.0 + FerryScenery.WET_STEP + 0.5 and FerryScenery.lies(line, land, 0.0) == FerryScenery.berth(line),
		"a boat lies afloat past a headland (%.0f m out) and at the ramp's end where it's sea (%.0f m)" % [afloat, FerryScenery.lies(line, land, 0.0)])
	check(FerryScenery.lies(line, func(_x: float, _z: float) -> float: return NAN, 0.0) == FerryScenery.berth(line),
		"and at the ramp's end while the heights aren't there")
	# A ramp where the road runs on down a slipway under the water starts up the road where it's dry.
	var slip := func(x: float, _z: float) -> float: return -6.0 if x > 1010.0 and x < 1590.0 else (2.0 if x < 980.0 else -1.0)
	var wet := RoadNet.new(r, slip)
	var links := FerryLinks.of(r)
	var dry: Dictionary = FerryScenery.ramp_of(wet, links, 0, 1)
	var plain: Dictionary = FerryScenery.ramp_of(net, links, 0, 1)
	check(not dry.is_empty() and (dry["road"] as Vector3).x < 997.0 and (dry["road"] as Vector3).y > FerryScenery.DRY
		and not plain.is_empty() and Vector2((plain["road"] as Vector3).x, (plain["road"] as Vector3).z).distance_to(r.node_pos[1]) < 0.5,
		"a ramp starts at the road's end, or up a slipway where it's dry (at %s)" % (str(dry["road"]) if not dry.is_empty() else "none"))
	# A bank that stays high a few metres on past the road's end: the ramp starts out on it, never runs into it.
	var bank := func(x: float, _z: float) -> float: return 2.0 if x < 1002.5 else (-6.0 if x < 1590.0 else 2.0)
	var banked := RoadNet.new(r, bank)
	var over: Dictionary = FerryScenery.ramp_of(banked, links, 0, 1)
	var clear := not over.is_empty()
	if clear:
		var fa: Vector3 = over["foot"]
		var fb: Vector3 = over["tip"]
		for k in range(1, 41):   # (on from its joint with the bank, a metre on at most)
			var q := fa.lerp(fb, minf(1.0, k / 40.0 + 1.0 / fa.distance_to(fb)))
			clear = clear and FerryScenery.surface_at(banked, Vector2(q.x, q.z)) <= q.y - FerryScenery.RAMP_CLEAR + 0.05
	check(clear and (over["foot"] as Vector3).x > 1001.5 and (over["road"] as Vector3).x < 1000.5,
		"a ramp starts out on a bank past the road's end, clear of it all along (%s)" % (str(over["foot"]) if not over.is_empty() else "none"))
	var boats: Array = dress.get("boats", [])
	var f1: Array = boats.filter(func(x): return str(x["id"]) == "f1")
	check(not f1.is_empty() and (f1[0]["afloat"] as Vector2).x < 20.0, "the scenery's boats afloat too (%s)" % (str(f1[0]["afloat"]) if not f1.is_empty() else "none"))


## The road's traffic and the other bikers never go out over a ferry's water (Simon on v0.43.0: cars and bikes on the
## water by the Skye ferry): what comes to it stops short at the terminal, as if for the boat, and is gone once nobody
## sees it; nothing turns up on it.
func test_traffic() -> void:
	var stream := TrafficStream.new()
	stream.sample = func(s: float) -> Dictionary:
		return {"pos": Vector3(0.0, 0.0, -s), "fwd": Vector3(0, 0, -1), "hw": 3.6, "busy": 0.0, "limit": 22.0, "grade": 0.0}
	stream.gaps = [[600.0, 1200.0]]
	t.add_child(stream)
	stream.set_physics_process(false)
	stream.focus_s = 400.0
	stream.despawn = 5000.0
	stream._spawn_timer = 1.0e9
	check(stream.in_gap(900.0) and not stream.in_gap(300.0) and stream.in_gap(590.0, 20.0) and stream.gap_ahead(500.0, 1) == 100.0
		and stream.gap_ahead(1300.0, -1) == 100.0 and stream.gap_ahead(1300.0, 1) == INF, "the ferry's water is a gap in the road")
	var car: Dictionary = stream.find(stream.spawn_at("hatchback", 300.0, 1, 20.0))
	var back: Dictionary = stream.find(stream.spawn_at("hatchback", 1500.0, -1, 20.0))
	car["pace"] = 1.0
	back["pace"] = 1.0
	var furthest := 0.0
	var nearest := INF
	for i in 400:
		stream.step(0.05, false)
		furthest = maxf(furthest, float(car["s"]))
		nearest = minf(nearest, float(back["s"]))
	check(furthest < 600.0 and furthest > 580.0 and float(car["v"]) < 0.5 and nearest > 1200.0 and nearest < 1220.0,
		"both ways the traffic stops short of the water at the terminal (%.0f and %.0f m: the water's 600 to 1200)" % [furthest, nearest])
	var spawned := 0
	for i in 300:
		var d := stream.spawn_one(0.0, 1500.0)
		if not d.is_empty():
			spawned += 1
			check(not stream.in_gap(float(d["s"]), TrafficStream.GAP_CLEAR), "nothing turns up on the water (%.0f)" % float(d["s"]))
			stream.remove_id(int(d["seed"]))
	check(spawned > 0, "but it does either side of it (%d)" % spawned)
	stream.queue_free()
