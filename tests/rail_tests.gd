extends RefCounted
## The railways' checks (Ride Anywhere v2, phase D round 1, D2: scripts/scenery/rail.gd and rail_train.gd), run from
## tests/run_tests.gd: its _test_rail_* functions hand over to these. Small graphs of their own (road_block_tests.gd's)
## with lines laid across them, and the bundled regions' own railways; no scene but the last.

const Roads := preload("res://tests/road_block_tests.gd")
const Rail := preload("res://scripts/scenery/rail.gd")
const Trains := preload("res://scripts/scenery/rail_train.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func line(kind: String, pts: Array, flags := 0, nm := "", id := "") -> Array:
	return [kind, PackedVector2Array(pts), null, null, flags, nm, id if id != "" else str(pts).sha1_text().left(12)]


## A main road east to west at z = 100 (Roads.tee's) with a railway crossing it on the level at x = 250, another over it
## on a bridge at x = 330, and a station beside the first.
static func crossing() -> RealRegion:
	var r := Roads.tee()
	r.features = {"points": [["railway_station", 258.0, 300.0, null, null, null, "Askrigg", "st"]], "areas": [],
		"lines": [
			line("railway", [Vector2(250, -700), Vector2(250, 40)], 0, "Up line", "a1"),
			# (the map cuts a line where its flags change and at a cell's edge: the same point either side)
			line("railway", [Vector2(250, 40), Vector2(250, 900)], 0, "Up line", "a2"),
			line("railway", [Vector2(330, -700), Vector2(330, 60)], 0, "Over", "b1"),
			line("railway", [Vector2(330, 60), Vector2(330, 140)], Rail.BRIDGE, "Over", "b2"),
			line("railway", [Vector2(330, 140), Vector2(330, 900)], 0, "Over", "b3"),
			line("railway", [Vector2(-150, -300), Vector2(-150, 300)], Rail.DISUSED, "Old line", "c1"),
		]}
	return r


## Whole lines from pieces; disused ones left out; spans; a viaduct with no line on it its own; pairs.
func test_runs() -> void:
	Rail.forget()
	var r := crossing()
	var got := Rail.build_runs(r.features["lines"], null)
	var runs: Array = got["runs"]
	check(runs.size() == 2, "two lines from five live pieces, the disused one left out (%d)" % runs.size())
	var a: Dictionary = runs[0]
	var b: Dictionary = runs[1]
	check(absf(float(a["len"]) - 1600.0) < 0.5 and absf(float(b["len"]) - 1600.0) < 0.5, "each whole (%.1f, %.1f)"
		% [float(a["len"]), float(b["len"])])
	check((a["spans"] as Array).is_empty() and (b["spans"] as Array).size() == 1
		and absf(float(b["spans"][0][1]) - float(b["spans"][0][0]) - 80.0) < 0.5, "the bridge is one span 80 m long (%s)" % str(b["spans"]))
	check(int(a["pair"]) == 0 and not (a["timetable"] as Dictionary).is_empty() and a["timetable"]["mode"] == "shuttle",
		"a single line has a shuttle (%s)" % str(a["timetable"]))
	# Two lines side by side (a double track mapped as two) run one way each, opposite ways.
	var dbl := Rail.build_runs([line("railway", [Vector2(0, 0), Vector2(2000, 0)]), line("railway", [Vector2(0, 4), Vector2(2000, 4)]),
		line("railway", [Vector2(0, 300), Vector2(150, 300)])], null)
	var d0: Dictionary = dbl["runs"][0]
	var d1: Dictionary = dbl["runs"][1]
	var d2: Dictionary = dbl["runs"][2]
	check(int(d0["pair"]) != 0 and int(d0["pair"]) == -int(d1["pair"]) and d0["timetable"]["mode"] == "oneway"
		and int(d0["timetable"]["dir"]) == -int(d1["timetable"]["dir"]), "a double track: one way each, opposite ways (%d, %d)"
		% [int(d0["pair"]), int(d1["pair"])])
	check((d2["timetable"] as Dictionary).is_empty(), "a siding has no train")
	# A viaduct the map has with no live line on it still stands, with no track and no train.
	var v := Rail.build_runs([line("viaduct", [Vector2(0, 0), Vector2(120, 0)], 0, "Mossdale Viaduct"),
		line("viaduct", [Vector2(500, 0), Vector2(560, 0)]), line("railway", [Vector2(400, 0), Vector2(500, 0)], 0),
		line("railway", [Vector2(500, 0), Vector2(560, 0)], Rail.BRIDGE), line("railway", [Vector2(560, 0), Vector2(900, 0)], 0)], null)
	var lone := (v["runs"] as Array).filter(func(x): return not x["track"])
	var live := (v["runs"] as Array).filter(func(x): return x["track"])
	check(lone.size() == 1 and absf(float(lone[0]["len"]) - 120.0) < 0.5 and str(lone[0]["spans"][0][3]) == "stone",
		"the old viaduct stands on its own, in stone (%d)" % lone.size())
	check(live.size() == 1 and str(live[0]["spans"][0][3]) == "stone", "a line's bridge along a mapped viaduct is stone arches")
	# Joined through a junction along the straightest way on; the branch its own line.
	var j := Rail.build_runs([line("railway", [Vector2(0, 0), Vector2(500, 0)]), line("railway", [Vector2(500, 0), Vector2(1000, 10)]),
		line("railway", [Vector2(500, 0), Vector2(900, 300)])], null)
	check((j["runs"] as Array).size() == 2 and absf(float(j["runs"][0]["len"]) - 1000.1) < 1.0,
		"through a junction straight on, the branch its own (%s)" % str((j["runs"] as Array).map(func(x): return snappedf(float(x["len"]), 0.1))))


## A block's railway: track off the road and its verge, a level crossing's barriers beside it, a bridge over it with a
## road bridge's headroom and no pier in it, a station's platform and boards; quick, and nothing a bike can touch.
func test_lay_out() -> void:
	Rail.forget()
	var r := crossing()
	var net := RoadNet.new(r, Roads.flat)
	var rows := {"points": [[r.features["points"][0], SceneryStreamer.kit("railway_station")]], "lines": [], "areas": []}
	var b := Rail.lay_out(net, Vector2i(0, 0), rows)
	var d: Dictionary = b["dress"]
	var clear := net.width_of(1) * 0.5 + RoadNet.VERGE
	# No track in the carriageway or its verge, but on the bridge over it.
	var multis: Dictionary = d["multis"]
	var in_road := 0
	var on_deck := 0
	var low_deck := INF
	for model: String in ["track", "track_far", "skirt_l", "skirt_r"]:
		for xf: Transform3D in multis.get(model, []):
			for end: Vector3 in [xf.origin, xf.origin - xf.basis.z]:
				if absf(end.z - 100.0) < clear and absf(end.x - 250.0) < 20.0:
					in_road += 1
	for xf: Transform3D in multis.get("deck_concrete", []):
		if absf(xf.origin.z - 100.0) < clear and absf(xf.origin.x - 330.0) < 3.0:
			on_deck += 1
			low_deck = minf(low_deck, xf.origin.y - Rail.DECK_DEPTH)
	check(in_road == 0, "no track on the level crossing's road or verge (%d)" % in_road)
	check(on_deck > 0 and low_deck >= 10.0 + RoadNet.HEADROOM - 0.05, "the bridge over the road clears it by a road bridge's headroom (deck's underside %.2f over a road at 10)"
		% low_deck)
	check((multis.get("pier_concrete", []) as Array).all(func(x): return absf((x as Transform3D).origin.z - 100.0) > clear),
		"no pier in the road (%d piers)" % (multis.get("pier_concrete", []) as Array).size())
	var pieces: Array = multis.get("track", [])
	check(pieces.size() > 200, "track along both lines (%d pieces)" % pieces.size())
	check((multis.get("platform", []) as Array).size() > 10, "a platform (%d pieces)" % (multis.get("platform", []) as Array).size())
	# The crossing: barriers either side, their arms' pivots past the verge, nothing on the road.
	var gates: Array = d["gates"]
	check(gates.size() == 1, "one level crossing (%d)" % gates.size())
	if gates.size() == 1:
		var arms: Array = gates[0]["arms"]
		check(arms.size() == 4 and arms.all(func(x): return absf((x as Transform3D).origin.z - 100.0) > clear),
			"four barriers, each past the verge (%s)" % str(arms.map(func(x): return (x as Transform3D).origin)))
		check(float(gates[0]["length"]) > net.width_of(1) * 0.5, "an arm reaches over its half of the road")
	# Each crossing is laid once, by the block its road point is in, though the blocks either side see it.
	var runs := Rail.runs_of(r)
	var laid := 0
	for k: Vector2i in runs["filed"]:
		laid += (Rail.lay_out(net, k, {})["dress"]["gates"] as Array).size()
	check(laid == 1, "the crossing laid by one block only (%d)" % laid)
	# Beside a bridge the map has on either line, a road goes under: no crossing there.
	check(Rail._bridge_near(runs, Vector2(330.0, 100.0)) and not Rail._bridge_near(runs, Vector2(250.0, 100.0)),
		"a road beside a rail bridge has no crossing")
	# The station: a platform beside the track, boards with its name.
	check((d["boards"] as Array).size() == 1 and d["boards"][0]["text"] == "Askrigg" and (d["boards"][0]["at"] as Array).size() >= 2,
		"the station's name boards (%s)" % str(d["boards"]))
	check((d["portions"] as Array).size() == 2, "both lines' trains have their share here")
	check(float(b["ms"]) < 60.0, "laid out in %.1f ms" % float(b["ms"]))
	# Into the world: nothing a bike can touch.
	var node := Node3D.new()
	Rail.dress(node, d)
	check(node.find_children("*", "CollisionObject3D", true, false).is_empty() and node.get_child_count() >= 3,
		"dressed with track, boards and trains, nothing a bike can touch (%d)" % node.get_child_count())
	node.free()


## Two blocks laying out the same line agree where they meet: the same heights at the same samples, each worked out
## afresh; and what one block found along it, kept for the next, changes nothing a block lays.
func test_seams() -> void:
	Rail.forget()
	var r := Roads.tee()
	var hilly := func(x: float, z: float) -> float: return 20.0 + sin(x * 0.01) * 8.0 + cos(z * 0.013) * 5.0
	r.features = {"points": [], "areas": [], "lines": [line("railway", [Vector2(-900, -300), Vector2(900, 400)])]}
	var net := RoadNet.new(r, hilly)
	var runs := Rail.runs_of(r)
	var filed: Dictionary = runs["filed"]
	var worst := 0.0
	var shared := 0
	var a := {}
	for k: Vector2i in filed:
		for f: Array in filed[k]:
			Rail._seen.clear()
			var sec := Rail.section(net, runs["runs"][int(f[0])], float(f[1]), float(f[2]), {})
			var own := Rect2(Vector2(k) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(8.0)
			for i in (sec["s"] as PackedFloat32Array).size():
				if not own.has_point(sec["p"][i]):
					continue
				var s := snappedf(sec["s"][i], 0.01)
				if a.has(s):
					shared += 1
					worst = maxf(worst, absf(float(a[s]) - sec["y"][i]))
				a[s] = sec["y"][i]
	check(shared > 4 and worst < 0.01, "blocks agree at their seams (%d shared samples, %.4f m apart at most)" % [shared, worst])
	var differ: Array = []
	for k: Vector2i in filed:
		Rail._seen.clear()
		var cold: Dictionary = Rail.lay_out(net, k, {})["dress"]["multis"]
		for k2: Vector2i in filed:
			if k2 != k:
				Rail.lay_out(net, k2, {})
		var warm: Dictionary = Rail.lay_out(net, k, {})["dress"]["multis"]
		if str(cold) != str(warm):
			differ.append(k)
	check(differ.is_empty() and filed.size() > 2, "a block lays the same with its neighbours' findings kept as without (%s)" % str(differ))
	# A climb no steeper than the land's, and never under the land.
	var sec := Rail.section(net, runs["runs"][0], 0.0, float(runs["runs"][0]["len"]), {})
	var under := 0
	for i in (sec["s"] as PackedFloat32Array).size():
		if sec["y"][i] < sec["land"][i] - 0.2:
			under += 1
	check(under == 0, "the track is never under the land (no cutting): %d samples" % under)


## The timetable: every machine has the same trains at the same time; a train stays on its line; midnight moves none.
func test_timetable() -> void:
	var r := {"track": true, "len": 6000.0, "kind": "railway", "id": "abc", "pair": 0, "kit": SceneryStreamer.kit("railway", "british_isles")}
	var tt := Trains.timetable_of(r)
	check(tt["mode"] == "shuttle" and int(tt["cars"]) == 2, "a single line's shuttle, its region's stock (%s)" % str(tt))
	var long := int(tt["cars"]) * float(tt["car_len"])
	var bad := 0
	var moved := 0
	var last := -1.0
	for k in 400:
		var tr: Array = Trains.trains_on(tt, 6000.0, k * 7.3, 0.0)
		if tr.size() != 1:
			bad += 1
			continue
		var f := float(tr[0][0])
		var tail := f - int(tr[0][1]) * long
		if minf(f, tail) < -0.01 or maxf(f, tail) > 6000.01:
			bad += 1
		if last >= 0.0 and absf(f - last) > 0.1:
			moved += 1
		last = f
	check(bad == 0 and moved > 100, "one train, always on the line, and moving (%d bad, %d moves)" % [bad, moved])
	check(str(Trains.trains_on(tt, 6000.0, 1234.5)) == str(Trains.trains_on(tt.duplicate(), 6000.0, 1234.5)), "the same time, the same train")
	var day := 24.0 * 60.0 * 20.0
	var before: Array = Trains.trains_on(tt, 6000.0, day - 0.01, day)
	var after: Array = Trains.trains_on(tt, 6000.0, 0.0, day)
	check(absf(float(before[0][0]) - float(after[0][0])) < 1.0, "midnight moves no train (%.2f, %.2f)" % [float(before[0][0]), float(after[0][0])])
	# One way, every headway.
	r["pair"] = 1
	var ow := Trains.timetable_of(r)
	var most := 0
	for k in 50:
		most = maxi(most, Trains.trains_on(ow, 6000.0, k * 31.0, 0.0).size())
	check(ow["mode"] == "oneway" and most >= 1, "a double track's line runs one way (%d at most at once)" % most)
	var trip: Vector2 = Trains.trip(1000.0, 30.0, 0.0)
	check(is_equal_approx(Trains.trip(1000.0, 30.0, trip.x).y, 1000.0) and Trains.trip(1000.0, 30.0, trip.x * 0.5).y > 400.0,
		"a trip ends where it should")


## The bundled regions: the Dales' Wensleydale Railway is a whole line with its stations; Shodoshima has none.
func test_regions() -> void:
	Rail.forget()
	var dales := RealRegion.get_region("dales")
	var runs: Array = Rail.runs_of(dales)["runs"]
	var longest := 0.0
	for r: Dictionary in runs:
		if r["track"]:
			longest = maxf(longest, float(r["len"]))
	check(longest > 6000.0, "the Dales: the Wensleydale Railway is a whole line (%.0f m)" % longest)
	for st: Array in (dales.features["points"] as Array).filter(func(p): return p[0] == "railway_station"):
		var p := Vector2(float(st[1]), float(st[2]))
		var near := runs.any(func(r): return r["track"] and Rail._near_line(r["pts"], p, Rail.STATION_NEAR))
		check(near, "%s station is beside its line" % st[6])
	check(runs.any(func(r): return not r["track"]), "and its old viaducts on the closed line west of Redmire still stand")
	check(Rail.runs_of(RealRegion.get_region("shodoshima"))["runs"].is_empty(), "Shodoshima has no railway, and none is laid")


## A viaduct across a valley (Ribblehead's shape: a line on a bridge 400 m long over a dale 30 m deep, the map's viaduct
## along it): a straight deck from rim to rim, stone piers down to the valley floor every few arches' worth, and arches.
func test_viaduct() -> void:
	Rail.forget()
	var r := Roads.graph([[-3000, -3000], [-2900, -3000]], [[0, 1, "track"]])
	var dale := func(x: float, _z: float) -> float: return 300.0 - 30.0 * exp(-pow(x / 120.0, 2.0))
	r.features = {"points": [], "areas": [], "lines": [
		line("railway", [Vector2(-1200, 200), Vector2(-200, 200)], 0, "Settle and Carlisle"),
		line("railway", [Vector2(-200, 200), Vector2(200, 200)], Rail.BRIDGE, "Settle and Carlisle"),
		line("railway", [Vector2(200, 200), Vector2(1200, 200)], 0, "Settle and Carlisle"),
		line("viaduct", [Vector2(-200, 200), Vector2(200, 200)], 0, "Ribblehead Viaduct")]}
	var net := RoadNet.new(r, dale)
	var piers: Array = []
	var arches: Array = []
	var decks: Array = []
	for k: Vector2i in [Vector2i(-1, 0), Vector2i(0, 0)]:
		var b := Rail.lay_out(net, k, {})
		var o := Vector3(k.x * RoadBlock.SIZE, 0.0, k.y * RoadBlock.SIZE)
		for xf: Transform3D in b["dress"]["multis"].get("pier_stone", []):
			piers.append(Transform3D(xf.basis, xf.origin + o))
		for xf: Transform3D in b["dress"]["multis"].get("arch_stone", []):
			arches.append(Transform3D(xf.basis, xf.origin + o))
		for xf: Transform3D in b["dress"]["multis"].get("deck_stone", []):
			decks.append(Transform3D(xf.basis, xf.origin + o))
	var lowest := INF
	for xf: Transform3D in decks:
		lowest = minf(lowest, xf.origin.y)
	check(decks.size() >= 95 and lowest > 297.0, "a stone deck from rim to rim, level across the dale (%d pieces, lowest %.1f)" % [decks.size(), lowest])
	var tallest := 0.0
	for xf: Transform3D in piers:
		tallest = maxf(tallest, xf.basis.y.length())
	check(piers.size() >= 20 and tallest > 25.0, "stone piers down to the valley floor (%d, the tallest %.1f m)" % [piers.size(), tallest])
	check(arches.size() >= 12, "arches between them where it's high enough (%d)" % arches.size())


## On the network ride round Redmire: the railway's block is put in the world with its track, platform and train, and
## nothing a bike can touch.
func test_ride() -> void:
	Rail.forget()
	var region := RealRegion.get_region("dales")
	var fr := Vector2(region.frame_lat, region.frame_lon)
	var a := RealRegion.to_frame(fr, 54.3160, -1.9300)
	var b := RealRegion.to_frame(fr, 54.3090, -1.8260)
	var plan := AdventurePlans.clean({"region": "dales", "region_hash": "", "pins": [[a.x, a.y], [b.x, b.y]], "names": ["Redmire"],
		"mode": "main"})
	var res := AdventurePlans.result(plan, true)
	check(bool(res.get("ok", false)), "a ride from Redmire to Leyburn (%s)" % str(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var was := AdventureWorld.network
	AdventureWorld.network = true
	var w := AdventureWorld.new()
	w.roads_region = region
	w.setup(res["pack"], 1)
	AdventureWorld.network = was
	var st: Array = (region.features["points"] as Array).filter(func(p): return p[6] == "Redmire" and p[0] in ["railway_station", "railway_halt"])[0]
	var at := Vector2(float(st[1]), float(st[2]))
	var key := RoadBlock.key_of(at.x, at.y)
	w.focus = func(): return [w.to_local_pos(at.x, 0.0, at.y)]
	t.add_child(w)
	w.shift_origin_to(w.to_local_pos(at.x, 0.0, at.y))
	var t0 := Time.get_ticks_msec()
	while not w.scenery.blocks.has(key) and Time.get_ticks_msec() - t0 < 90000:
		await t.get_tree().process_frame
	check(w.scenery.blocks.has(key), "Redmire's block is in the world (%s)" % str(w.scenery.stats))
	if w.scenery.blocks.has(key):
		for f in 5:
			await t.get_tree().process_frame
		var node: Node3D = w.scenery.blocks[key]
		var names := node.find_children("*", "", true, false).map(func(c): return str(c.name))
		check(names.has("track") and names.has("platform") and names.has("Trains"), "its track, platform and trains (%s)"
			% str(names.slice(0, 20)))
		check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), "and nothing a bike can touch")
	w.queue_free()
