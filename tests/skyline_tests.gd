extends RefCounted
## The skyline's checks (Ride Anywhere v2, phase D round 1: scripts/scenery/skyline.gd), run from tests/run_tests.gd:
## its _test_skyline_* functions hand over to these. Small graphs of their own (road_block_tests.gd's) and the bundled
## regions' features; no scene, no network.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The rows of `features` (RealRegion.features' shape) whose kit names the skyline, by block, as the streamer hands
## them over: {key: {points: [[row, kit]], lines: [...], areas: [...]}}.
static func rows_of(features: Dictionary, region_id := "") -> Dictionary:
	var by := {}
	for part: String in ["points", "lines", "areas"]:
		for row: Array in features.get(part, []):
			var kit := SceneryStreamer.kit(str(row[0]), region_id)
			if not str(kit.get("model", "")).begins_with("skyline:"):
				continue
			var keys := {}
			if part == "points":
				keys[RoadBlock.key_of(float(row[1]), float(row[2]))] = true
			else:
				for p: Vector2 in row[1]:
					keys[RoadBlock.key_of(p.x, p.y)] = true
			for key: Vector2i in keys:
				if not by.has(key):
					by[key] = {"points": [], "lines": [], "areas": []}
				(by[key][part] as Array).append([row, kit])
	return by


## Every model a skyline kit names is built, as one surface (one draw call a block), and every support a line names
## says where its wires hang.
func test_models() -> void:
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var models := {}
	var supports := {}
	var cabins := {}
	for kind: String in kinds:
		var row: Dictionary = kinds[kind]
		if row.get("round") != "D1":
			continue
		for region in [""] + (row.get("regions", {}) as Dictionary).keys():
			var k := SceneryStreamer.kit(kind, region)
			check(str(k.get("model", "")).begins_with("skyline:"), "%s (%s) is the skyline's (%s)" % [kind, region, k.get("model")])
			var m := Skyline._model_of(k)
			if m not in ["none", "wire", "yard", "fence", "piste"]:
				models[m] = true
			for f: String in ["support", "end"]:
				if k.has(f):
					supports[str(k[f])] = true
			for f: String in ["tall", "big", "marker"]:
				if k.has(f):
					models[str(k[f])] = true
			if k.has("cabin"):
				cabins[str(k["cabin"])] = true
	models.merge(supports)
	models.merge(cabins)
	models.merge({"transformer": true, "portal": true, "steam": true})
	var bad := []
	for m: String in models:
		var mesh := Skyline.mesh(m)
		if mesh.get_surface_count() != 1 or mesh.get_faces().size() < 12:
			bad.append(m)
	check(bad.is_empty(), "%d models built, one surface each (%s)" % [models.size(), bad])
	for s: String in supports:
		check(Skyline.SUPPORTS.has(s) and not (Skyline.SUPPORTS[s]["wires"] as Array).is_empty(), "support %s says where its wires hang" % s)
	for c: String in cabins:
		check(Skyline.CABINS.has(c), "cabin %s has its spacing and speed" % c)
	check(Skyline.mesh("turbine") == Skyline.mesh("turbine"), "a model is built once")
	# Every kind that has a regional model has one for every region it names, and the turbines face the wind.
	check(Skyline.SUPPORTS["pylon"]["wires"].size() == Skyline.SUPPORTS["pylon_tall"]["wires"].size(),
		"the tall Japanese pylon carries the same wires as the default")


## Lines cut at the cells' edges are joined; a line's supports are its mapped towers, its ends and its bends, and enough
## between that no span is longer than its kit's.
func test_lines() -> void:
	var pieces := [["power_line", PackedVector2Array([Vector2(0, 0), Vector2(500, 0)]), null, null, 0, "", "a"],
		["power_line", PackedVector2Array([Vector2(1200, 0), Vector2(500, 0)]), null, null, 0, "", "a"],
		["minor_line", PackedVector2Array([Vector2(500, 0), Vector2(500, 300)]), null, null, 0, "", null]]
	var joined := Skyline._join(pieces)
	check(joined.size() == 2 and (joined.filter(func(j): return j[0] == "power_line")[0][1] as PackedVector2Array).size() == 3,
		"two pieces of one power line joined end to end, a line of another kind left alone (%s)" % str(joined))
	var r := Roads.tee()
	r.features = {"points": [
		["power_tower", 2000.0, 1003.0, 52.0, null, null, "", "t1"],   # 3 m off the line
		["power_tower", 2000.0, 1100.0, null, null, null, "", "t2"],   # 100 m off it: a tower of another line
	], "lines": [
		["power_line", PackedVector2Array([Vector2(1500, 1000), Vector2(2600, 1000), Vector2(2600, 1600)]), null, null, 0, "", "l"],
	], "areas": []}
	var net := RoadNet.new(r, Roads.flat)
	var lines := Skyline._work_out_lines(r)
	var line: Dictionary = lines["lines"][0]
	var sups: Array = line["supports"]
	var span := float(line["kit"]["span"])
	var longest := 0.0
	for i in range(1, sups.size()):
		longest = maxf(longest, (sups[i]["p"] as Vector2).distance_to(sups[i - 1]["p"]))
	check(longest <= span + 1.0, "no span longer than %.0f m (%.0f, %d supports)" % [span, longest, sups.size()])
	check(sups.filter(func(s): return int(s["point"]) >= 0).size() == 1 and lines["mapped"].has(Skyline._spot(Vector2(2000, 1003))),
		"the mapped tower on it is one of its supports, the one off it isn't")
	check(sups.any(func(s): return (s["p"] as Vector2).distance_to(Vector2(2600, 1000)) < 1.0), "a support at its bend")
	check((sups[0]["p"] as Vector2).distance_to(Vector2(1500, 1000)) < 1.0 and (sups[sups.size() - 1]["p"] as Vector2).distance_to(Vector2(2600, 1600)) < 1.0,
		"and at its ends")
	# Each support and span is laid out in one block only, whichever blocks ask.
	var by := rows_of(r.features)
	for key: Vector2i in lines["by_block"]:
		if not by.has(key):
			by[key] = {"points": [], "lines": [], "areas": []}
	var pylons := 0
	var wires := 0
	for key: Vector2i in by:
		var b := Skyline.lay_out(net, key, by[key])
		pylons += (b["items"].get("pylon", []) as Array).size()
		if b.has("dress"):
			wires += (b["dress"]["wires"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	check(pylons == sups.size() + 1, "every support drawn once, and the other line's tower on its own (%d for %d)" % [pylons, sups.size()])
	check(wires > 0 and wires % 6 == 0, "the wires between them")
	# Its supports are the same whichever region asked first (worked out once, from the region alone).
	var again := Skyline._work_out_lines(r)
	check(str(again["lines"][0]["supports"]) == str(sups), "the same supports every time")


## A block: everything beside the road, never on it, its wires high over it, the turbines into the wind, and nothing a
## bike can touch.
func test_block() -> void:
	var r := Roads.tee()
	r.features = {"points": [
		["wind_turbine", 300.0, 300.0, 124.0, null, null, "", "w1"],
		["wind_turbine", 330.0, 200.0, null, null, null, "", "w2"],
		["communication_tower", 20.0, 300.0, 180.0, null, null, "", "m1"],
		["water_tower", 250.0, 101.0, null, null, null, "", "wt"],         # on the main road: stood off it
		["minaret", 100.0, 100.0, null, null, null, "", "in_junction"],    # in the tee: left out
		["power_pole", 60.0, 120.0, null, null, null, "", null],
		["aerialway_station", 380.0, 20.0, null, null, null, "", "s1"],
	], "lines": [
		["power_line", PackedVector2Array([Vector2(-150, -50), Vector2(350, 450)]), null, null, 0, "", "pl"],
		["minor_line", PackedVector2Array([Vector2(60, 120), Vector2(60, 400)]), null, null, 0, "", null],
		["gondola", PackedVector2Array([Vector2(380, 20), Vector2(450, 480)]), null, null, 0, "", "g"],
	], "areas": [
		["substation", PackedVector2Array([Vector2(-150, 200), Vector2(-100, 200), Vector2(-100, 250), Vector2(-150, 250)]), null, null, "", "ss"],
		["solar", PackedVector2Array([Vector2(150, 150), Vector2(240, 150), Vector2(240, 230), Vector2(150, 230)]), null, null, "", "sf"],
		["storage_tank", PackedVector2Array([Vector2(-180, 400), Vector2(-160, 400), Vector2(-160, 420), Vector2(-180, 420)]), null, null, "", "tk"],
	]}
	var net := RoadNet.new(r, Roads.flat)
	var by := rows_of(r.features)
	var key := Vector2i(0, 0)
	var lines := Skyline._lines_of(net)
	for k: Vector2i in lines["by_block"]:
		if not by.has(k):
			by[k] = {"points": [], "lines": [], "areas": []}
	var items := {}
	var wires := PackedVector3Array()
	var dresses := []
	var ms := 0.0
	for k: Vector2i in by:
		var t0 := Time.get_ticks_usec()
		var b := Skyline.lay_out(net, k, by[k])
		ms = maxf(ms, (Time.get_ticks_usec() - t0) / 1000.0)
		var o := Vector3(k.x, 0, k.y) * RoadBlock.SIZE
		for m: String in b["items"]:
			if not items.has(m):
				items[m] = []
			for xf: Transform3D in b["items"][m]:
				(items[m] as Array).append(Transform3D(xf.basis, xf.origin + o))
		if b.has("dress"):
			dresses.append(b["dress"])
			if not (b["dress"]["wires"] as Array).is_empty():
				for v: Vector3 in b["dress"]["wires"][Mesh.ARRAY_VERTEX]:
					wires.append(v + o)
	for m in ["turbine", "tv_tower", "water_tower", "pole", "pylon", "transformer", "solar_row", "tank", "lift_station", "lift_pylon"]:
		check(items.has(m), "%s laid out (%s)" % [m, items.keys()])
	check(not items.has("minaret"), "the minaret in the junction is left out")
	# Nothing stands on a carriageway or its verge.
	var on_road := []
	for m: String in items:
		for xf: Transform3D in items[m]:
			var hit := net.locate(xf.origin.x, xf.origin.z, -1, false)
			if not hit.is_empty() and (int(hit["node"]) >= 0 or absf(float(hit["lat"])) < float(hit["width"]) * 0.5 + RoadNet.VERGE):
				on_road.append(m)
	check(on_road.is_empty(), "nothing on a road or its verge (%s)" % str(on_road))
	# The wires are high over the road where they cross it (the land is at 10 m here).
	var low := INF
	for v in wires:
		var hit := net.locate(v.x, v.z, -1, false)
		if not hit.is_empty() and absf(float(hit["lat"])) < float(hit["width"]) * 0.5 + RoadNet.VERGE:
			low = minf(low, v.y)
	check(low >= 10.0 + 5.9 and low < INF, "every wire over a road at least its clearance above it (lowest %.1f m over 10)" % low)
	# The turbines face into the wind (their rotor on -z), sized to the map's height or the region's default.
	var w1: Transform3D = (items["turbine"] as Array).filter(func(x): return x.origin.distance_to(Vector3(300, 10, 300)) < 1.0)[0]
	var face := -w1.basis.z.normalized()
	check(Vector2(face.x, face.z).normalized().dot(-Skyline.WIND.normalized()) > 0.99, "a rotor faces into the wind")
	check(absf(w1.basis.y.length() * 100.0 - 124.0 / 1.55) < 0.5, "a turbine mapped 124 m tall has an 80 m hub")
	var tv: Transform3D = items["tv_tower"][0]
	check(absf(tv.basis.y.length() * 200.0 - 180.0) < 0.5, "a mast mapped 180 m tall is a TV tower that tall")
	check(ms < 25.0, "laid out quickly (%.2f ms the slowest block)" % ms)
	# Put into a block: the wires as one mesh, cabins moving, nothing a bike can touch.
	var node := Node3D.new()
	t.add_child(node)
	for d in dresses:
		Skyline.dress(node, d)
	var cabins := node.find_children("Cabins", "", true, false)
	check(not cabins.is_empty() and (cabins[0] as MultiMeshInstance3D).multimesh.instance_count > 2, "the gondola has its cabins")
	# (they go by the clock on the wall, so every machine in a crew has them in the same place)
	var mover = cabins[0]
	var now: Array = mover.placed(1000.0)
	var later: Array = mover.placed(1001.0)
	check(now.size() == mover.multimesh.instance_count and (now[0] as Transform3D).origin.distance_to((later[0] as Transform3D).origin) > 4.0
		and str(mover.placed(1000.0)) == str(now), "and they move by the clock, five metres a second")
	check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), "nothing a bike can touch")
	# (the wires in their own see-through shader, so a far one is faint rather than a bold line)
	var wire_mi := node.find_child("SkylineWires", true, false) as MeshInstance3D
	check(wire_mi != null and wire_mi.mesh.surface_get_material(0) == Skyline.wire_material()
		and Skyline.wire_material().shader.code.contains("ALPHA = cover"), "the wires drawn fainter the finer they look")
	node.queue_free()


## The bundled regions: every block within the budget, the Dales' poles and lines and Shodoshima's pylons and its
## cable car all placed.
func test_regions() -> void:
	for id in ["dales", "shodoshima"]:
		var r := RealRegion.get_region(id)
		var net := RoadNet.new(r, Roads.flat)
		Skyline._lines_of(net)   # (once a region, on the first block's worker)
		var by := rows_of(r.features, "british_isles" if id == "dales" else "east_asia")
		for k: Vector2i in Skyline._lines_of(net)["by_block"]:
			if not by.has(k):
				by[k] = {"points": [], "lines": [], "areas": []}
		# (the twelve busiest blocks: laying a block out the first time works out its roads' heights, a tenth of a second
		# or more each, so the test stays quick)
		var keys: Array = by.keys()
		var load_of := func(k: Vector2i) -> int:
			var f: Dictionary = (Skyline._lines_of(net)["by_block"] as Dictionary).get(k, {})
			return (by[k]["points"] as Array).size() + (f.get("supports", []) as Array).size() + (f.get("spans", []) as Array).size()
		keys.sort_custom(func(a, b): return load_of.call(a) > load_of.call(b))
		var sample: Array = keys.slice(0, 12)
		# (the first time round a block works out its roads' heights, as the road blocks do before it on a ride: timed
		# the second)
		for k: Vector2i in sample:
			Skyline.lay_out(net, k, by[k])
		var worst := 0.0
		var times: Array[float] = []
		var counts := {}
		for k: Vector2i in sample:
			var t0 := Time.get_ticks_usec()
			var b := Skyline.lay_out(net, k, by[k])
			var took := (Time.get_ticks_usec() - t0) / 1000.0
			times.append(took)
			worst = maxf(worst, took)
			for m: String in b["items"]:
				counts[m] = int(counts.get(m, 0)) + (b["items"][m] as Array).size()
		check(not counts.is_empty(), "%s: %s" % [id, counts])
		times.sort()
		var middle := times[times.size() / 2]
		# (a block is laid out once, on a worker. A whole region's middle block is under a millisecond; the busiest are
		# the Dales' pole lines along the lanes, each pole stood off its road as SceneryStreamer.stand does and each
		# span's clearance over the road checked, a few milliseconds)
		check(middle < 8.0 and worst < 25.0, "%s: a block in %.2f ms (the middle of the %d busiest), the slowest %.2f ms, once its roads are known"
			% [id, middle, times.size(), worst])
	var shodo := RealRegion.get_region("shodoshima")
	var lines := Skyline._lines_of(RoadNet.new(shodo, Roads.flat))
	check((lines["lines"] as Array).any(func(l): return l["kind"] == "cable_car" and (l["supports"] as Array).size() >= 2),
		"Shodoshima's cable car (Kankakei) has its stations")
