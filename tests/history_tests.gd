extends RefCounted
## History's checks (Ride Anywhere v2, phase D round 2, D6: scripts/scenery/history.gd, scripts/building_looks.gd and
## the mapped buildings in scripts/region_buildings.gd), run from tests/run_tests.gd: its _test_history_* functions
## hand over to these. Small graphs of their own (road_block_tests.gd's); no scene, no network.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The rows of `features` (RealRegion.features' shape) whose kit names history, by block, as the streamer hands them
## over: {key: {points: [[row, kit]], lines: [...], areas: [...]}}.
static func rows_of(features: Dictionary, region_id := "") -> Dictionary:
	var by := {}
	for part: String in ["points", "lines", "areas"]:
		for row: Array in features.get(part, []):
			var kit := SceneryStreamer.kit(str(row[0]), region_id)
			if not str(kit.get("model", "")).begins_with("history:"):
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


## Every block of `by` laid out: {items: {model: [Transform3D in the region frame]}, labels: [[text, xf]], ms (the
## slowest block)}.
static func lay_all(net: RoadNet, by: Dictionary) -> Dictionary:
	var items := {}
	var labels := []
	var ms := 0.0
	for k: Vector2i in by:
		var t0 := Time.get_ticks_usec()
		var b := History.lay_out(net, k, by[k])
		ms = maxf(ms, (Time.get_ticks_usec() - t0) / 1000.0)
		var o := Vector3(k.x, 0, k.y) * RoadBlock.SIZE
		for m: String in b["items"]:
			if not items.has(m):
				items[m] = []
			for xf: Transform3D in b["items"][m]:
				(items[m] as Array).append(Transform3D(xf.basis, xf.origin + o))
		for l: Array in b["dress"]["labels"]:
			labels.append([l[0], Transform3D(l[1].basis, l[1].origin + o)])
	return {"items": items, "labels": labels, "ms": ms}


## Every model a history kit names is built, as one surface (one draw call a block), in every stone.
func test_models() -> void:
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var models := {}
	for kind: String in kinds:
		var row: Dictionary = kinds[kind]
		if row.get("round") != "D6":
			continue
		for region in [""] + (row.get("regions", {}) as Dictionary).keys():
			var k := SceneryStreamer.kit(kind, region)
			check(str(k.get("model", "")).begins_with("history:"), "%s (%s) is history's (%s)" % [kind, region, k.get("model")])
			var stone := str(k.get("stone", "grey"))
			match History._model_of(k):
				"wall":
					for m in ["wall", "merlons", "gate_tower", "arch", "tower_" + str(k.get("tower", "round"))]:
						models["%s_%s" % [m, stone]] = true
				"sally":
					models["sally_" + stone] = true
	for m in ["stones", "standing_stone", "obelisk", "cross", "statue", "sculpture", "heritage", "name_board", "board",
			"panorama", "bench", "pull_in", "fountain", "milestone", "flood"]:
		models[m] = true
	var bad := []
	for m: String in models:
		var mesh := History.mesh(m)
		if mesh.get_surface_count() != 1 or mesh.get_faces().size() < 12:
			bad.append(m)
	check(bad.is_empty(), "%d models built, one surface each (%s)" % [models.size(), bad])
	check(History.mesh("wall_sand") == History.mesh("wall_sand"), "a model is built once")
	check(History.monument_model("Cefn Coch Stone Circle") == "stones" and History.monument_model("The Cenotaph") == "cross"
		and History.monument_model("Queen of Hearts Statue") == "statue" and History.monument_model("Nelson's Column") == "obelisk"
		and History.monument_model("Conwy Town Walls") == "", "a monument's model by its name, a name that says none a board")
	# The arch's underside is nowhere below its bottom: the headroom over the road holds all the way across.
	var low := INF
	for v: Vector3 in History.mesh("arch_grey").get_faces():
		low = minf(low, v.y)
	check(low >= -0.001, "the arch's underside is all at or above its bottom (%.3f)" % low)


## A walled town: the wall along its line, towers on it, a gate over each road through it whose arch clears the road
## by the headroom, nothing on a road or its verge, each piece laid out once whichever block asks, and lines cut at a
## cell's edge joined.
func test_walls() -> void:
	var r := Roads.tee()
	# A ring round a quarter south of the main road, the side road going through it twice; a wall cut at x = 512 (a
	# cell's edge, say) in two pieces over two blocks.
	var ring := PackedVector2Array([Vector2(20, 180), Vector2(180, 180), Vector2(180, 350), Vector2(20, 350), Vector2(20, 180)])
	r.features = {"points": [
		["defensive_tower", 180.0, 265.0, 20.0, null, null, "", "t1"],
	], "lines": [
		["city_wall", ring, null, null, 0, "Town Walls", "w1"],
		["city_wall", PackedVector2Array([Vector2(470, 300), Vector2(512, 300)]), 6.0, null, 0, "", "w2"],
		["city_wall", PackedVector2Array([Vector2(512, 300), Vector2(590, 300)]), 6.0, null, 0, "", "w2"],
	], "areas": [
		# (a wall mapped as the outline of what it rings)
		["city_wall", PackedVector2Array([Vector2(250, 250), Vector2(350, 250), Vector2(350, 350), Vector2(250, 350)]), null, null, "", "w3"],
	]}
	var net := RoadNet.new(r, Roads.flat)
	var walls := History._walls_of(net)
	check((walls["walls"] as Array).size() == 3, "the wall cut at the edge joined into one, and the outline a wall (%d walls)" % (walls["walls"] as Array).size())
	var by := rows_of(r.features)
	# (a wall's plan is worked out once, by the first block that asks; then each block lays out its own part)
	var t0 := Time.get_ticks_usec()
	for wi in (walls["walls"] as Array).size():
		History._plan_of(net, walls, wi)
	var plan_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var got := lay_all(net, by)
	var items: Dictionary = got["items"]
	var walls_n := 0
	var expected := 0
	for wi in (walls["walls"] as Array).size():
		expected += (History._plan_of(net, walls, wi)["pieces"] as PackedInt32Array).size()
	for m: String in items:
		if m.begins_with("wall_"):
			walls_n += (items[m] as Array).size()
	check(walls_n == expected and walls_n > 100, "each piece of wall laid out once (%d of %d)" % [walls_n, expected])
	check(items.has("tower_round_grey"), "towers along the wall (%s)" % str(items.keys()))
	var arches: Array = items.get("arch_grey", [])
	check(arches.size() == 2, "a gate over the side road each time it goes through (%d)" % arches.size())
	# The arch's bottom (its transform's origin: the underside is all above it) clears the road by the headroom.
	for xf: Transform3D in arches:
		var on := net.locate(xf.origin.x, xf.origin.z, -1, true)
		check(not on.is_empty() and xf.origin.y >= float(on["y"]) + History.HEADROOM - 0.01,
			"an arch %.1f m over the road under it (at least %.1f)" % [xf.origin.y - float(on.get("y", 0.0)), History.HEADROOM])
	# Nothing below the headroom stands on a carriageway or its verge (the wall stops either side of a road).
	var on_road := []
	for m: String in items:
		if m.begins_with("arch_"):
			continue
		for xf: Transform3D in items[m]:
			var half := (xf.basis.x.length() * 0.5) if m.begins_with("wall_") else 0.0
			if not History.clear_of_roads(net, Vector2(xf.origin.x, xf.origin.z), half - 0.01):
				on_road.append(m)
	check(on_road.is_empty(), "nothing on a road or its verge (%s)" % str(on_road))
	# No tower of the wall's own beside the one the map has (the skyline draws that).
	var near_mapped := (items.get("tower_round_grey", []) as Array).filter(
		func(xf): return Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(180, 265)) < History.TOWER_NEAR)
	check(near_mapped.is_empty(), "no tower of its own by the mapped one")
	check(items.has("flood") and (items["flood"] as Array).size() >= 15, "floodlights round the walls (%d)" % (items.get("flood", []) as Array).size())
	check(plan_ms < 400.0 and float(got["ms"]) < 60.0,
		"laid out quickly (the walls' plans %.0f ms once, then %.1f ms the slowest block)" % [plan_ms, float(got["ms"])])
	# Laid out again, the same.
	History._walls.clear()
	var again := lay_all(RoadNet.new(r, Roads.flat), by)
	check(str(again["items"].get("arch_grey")) == str(arches), "the same gates every time")


## The things at a point: monuments by their names, artwork and its board, a viewpoint's pull-in, a fountain, a
## milestone and a board, each beside the road and never on it; names on boards facing the road; nothing to touch.
func test_points() -> void:
	var r := Roads.tee()
	r.features = {"points": [
		["monument", 300.0, 250.0, null, null, null, "Cefn Coch Stone Circle", "m1"],
		["monument", 250.0, 103.0, null, null, null, "War Memorial", "m2"],      # on the main road: stood off it
		["monument", -100.0, 300.0, null, null, null, "Ye Olde Market", "m3"],
		["monument", 100.0, 100.0, null, null, null, "Obelisk", "in"],          # in the tee: left out
		["artwork", 60.0, 125.0, null, null, null, "Mytilus Edulis", null],
		["viewpoint", 300.0, 112.0, null, null, null, "", null],
		["fountain", 140.0, 160.0, null, null, null, "", null],
		["milestone", 0.0, 108.0, null, null, null, "", null],
		["information", 50.0, 109.0, null, null, null, "", null],
		["castle", 200.0, 300.0, null, null, null, "Castle", "c"],
	], "lines": [], "areas": []}
	var net := RoadNet.new(r, Roads.flat)
	var got := lay_all(net, rows_of(r.features))
	var items: Dictionary = got["items"]
	for m in ["stones", "cross", "heritage", "sculpture", "name_board", "pull_in", "bench", "panorama", "fountain", "milestone", "board"]:
		check(items.has(m), "%s laid out (%s)" % [m, items.keys()])
	check(not items.has("obelisk"), "the monument in the junction is left out")
	var on_road := []
	for m: String in items:
		for xf: Transform3D in items[m]:
			if not History.clear_of_roads(net, Vector2(xf.origin.x, xf.origin.z), 0.0):
				on_road.append(m)
	check(on_road.is_empty(), "nothing on a road or its verge (%s)" % str(on_road))
	# The pull-in's corners stand clear of the road too: it's beside it, never on it.
	var pull: Transform3D = items["pull_in"][0]
	var corners_clear := true
	for c: Vector3 in [Vector3(-4, 0, -1), Vector3(4, 0, -1), Vector3(-4, 0, 3), Vector3(4, 0, 3)]:
		var p := pull * c
		corners_clear = corners_clear and History.clear_of_roads(net, Vector2(p.x, p.z), 0.0)
	check(corners_clear, "the viewpoint's pull-in beside the road, its bench looking away from it")
	var names := (got["labels"] as Array).map(func(l): return l[0])
	check("Mytilus Edulis" in names and "Cefn Coch Stone Circle" in names and "Ye Olde Market" in names and not "Castle" in names,
		"the names on their boards (%s)" % str(names))
	# The artwork's name faces the main road, north of it (-z).
	for l: Array in got["labels"]:
		if l[0] == "Mytilus Edulis":
			var face: Vector3 = (l[1] as Transform3D).basis.z.normalized()
			check(face.z < -0.9, "its name faces the road (%s)" % str(face))
	# Into a block: names as labels, nothing a bike can touch.
	var node := Node3D.new()
	t.add_child(node)
	History.dress(node, {"labels": got["labels"]})
	check(node.find_children("*", "Label3D", true, false).size() == (got["labels"] as Array).size(), "the names put up")
	check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), "nothing a bike can touch")
	node.queue_free()


## Buildings' looks: the map's words as a look, matched to the building they stand in, laid over the kit; a mapped
## church, mosque or hangar drawn as one, inside its outline; onion towers where they belong.
func test_looks() -> void:
	var look := BuildingLooks.look_of([0.0, 0.0, "", "gabled", "#778899", "slate", "brick", ""], 53.0)
	check(look.get("roof") == "gable" and (look["roof_colour"] as Color).is_equal_approx(BuildingLooks.colour("#778899"))
		and (look["wall_colour"] as Color).is_equal_approx(BuildingLooks.colour(BuildingLooks.FACADE_MATERIALS["brick"])),
		"a gabled roof of light slate grey over brick walls (%s)" % str(look))
	look = BuildingLooks.look_of([0.0, 0.0, "", "", "", "roof_tiles", "", ""])
	check((look["roof_colour"] as Color).is_equal_approx(BuildingLooks.colour(BuildingLooks.ROOF_MATERIALS["roof_tiles"])), "a tiled roof without a colour is tile red")
	check(BuildingLooks.look_of([0.0, 0.0, "", "", "", "", "", ""]).is_empty(), "nothing said, no look")
	# Matched by where it stands: inside the building's box (turned as it's turned), the nearest of several.
	var r := Roads.tee()
	r.features = {"points": [], "lines": [], "areas": [], "buildings": [
		[300.0, 300.0, "church", "", "", "", "", ""],
		[303.0, 300.0, "", "flat", "", "", "", ""],
		[340.0, 300.0, "", "hipped", "", "", "", ""],
	]}
	var row := [300.0, 300.5, 20.0, 8.0, 0.4, 9.0, 6, 0]
	check(BuildingLooks.of(r, row).get("class") == "church", "the look nearest the building's middle is its own")
	check(BuildingLooks.of(r, [340.0, 290.0, 6.0, 6.0, 0.0, 5.0, 0, 0]).is_empty(), "a look outside the building isn't its")
	check(BuildingLooks.of(Roads.tee(), row).is_empty(), "no looks mapped: none")
	var kit := RegionKit.choose({"country": "GB"})
	var dressed := BuildingLooks.dress_kit(kit, {"roof": "flat", "roof_colour": Color.RED})
	check(dressed["roof"] == "flat" and float(dressed["flat"]) == 1.0 and dressed["roofs"] == [Color.RED] and kit["roofs"] != [Color.RED],
		"a look laid over a copy of the kit")
	# Every mapped class drawn as its own, inside its outline (its roof's eaves and the odd sill aside: 0.6 m), so no
	# mapped building reaches nearer a road than its box. (A windmill's sails swing out, high over the ground.)
	var de := RegionKit.choose({"country": "DE"})
	var kits := [de, RegionKit.choose({"country": "JP"}), RegionKit.choose({"country": "IN"}), RegionKit.choose({"country": "MA"}),
		RegionKit.choose({"country": "GR"}), RegionKit.choose({"country": "TH"}), RegionKit.choose({"country": "MX"}), kit]
	for cls in ["church", "cathedral", "chapel", "mosque", "synagogue", "temple", "shrine", "hangar", "silo", "stadium",
			"grandstand", "greenhouse", "bunker", "train_station", "trullo", "ger", "beach_hut", "castle", "lighthouse", "windmill"]:
		var w := 14.0 if cls not in ["stadium", "cathedral", "hangar"] else 60.0
		var d := 22.0 if cls not in ["stadium", "cathedral", "hangar"] else 90.0
		if cls == "chapel":
			w = 3.0
			d = 4.0
		# (at a few spots: each draws its own of the kit's kinds)
		var out := 0
		var v := PackedVector3Array()
		for i in 8:
			var a := AdventureProps.new_arrays()
			var at := Vector3(i * 37.0, 0, i * 11.0)
			RegionBuildings.real_building(a, at, w, d, 0.0, 10.0, "worship", kits[i % kits.size()], {"class": cls, "lat": 48.0})
			v = a["v"]
			for p in v:
				if absf(p.x - at.x) > w * 0.5 + 0.6 or absf(p.z - at.z) > d * 0.5 + 0.6:
					if cls != "windmill" or p.y < History.HEADROOM:
						out += 1
		check(v.size() > 30 and out == 0, "a mapped %s drawn as one, inside its outline (%d triangles, %d points outside)" % [cls, v.size() / 3, out])
	check(not RegionBuildings.mapped(AdventureProps.new_arrays(), Transform3D(), 10.0, 10.0, 6.0, "house", de, RandomNumberGenerator.new(), {}),
		"a house is drawn as its kind, as before")
	# Onion towers on a share of Bavaria's churches, hardly any in the north.
	var onions := {48.0: 0, 53.5: 0}
	for lat: float in onions:
		for i in 200:
			var rng := RandomNumberGenerator.new()
			rng.seed = i
			if RegionBuildings.church_kind(de, {"lat": lat}, rng, "church") == "onion_church":
				onions[lat] += 1
	check(onions[48.0] > 80 and onions[48.0] < 160 and onions[53.5] < 20,
		"onion towers on %d of 200 Bavarian churches and %d of 200 in the north" % [onions[48.0], onions[53.5]])
	# A building the map says nothing about is drawn just as before.
	var a1 := AdventureProps.new_arrays()
	var a2 := AdventureProps.new_arrays()
	RegionBuildings.real_building(a1, Vector3(5, 0, 5), 9.0, 7.0, 0.3, 6.0, "house", kit)
	RegionBuildings.real_building(a2, Vector3(5, 0, 5), 9.0, 7.0, 0.3, 6.0, "house", kit, {})
	check(a1["v"] == a2["v"] and a1["c"] == a2["c"], "no look: the same house as ever")
	var a3 := AdventureProps.new_arrays()
	RegionBuildings.real_building(a3, Vector3(5, 0, 5), 9.0, 7.0, 0.3, 6.0, "house", kit, {"roof_colour": Color(0.9, 0.1, 0.1)})
	check((a3["c"] as PackedColorArray).has(Color(0.9, 0.1, 0.1)), "a mapped red roof is red")


## A features file's building looks read into the region's frame, beside its points; a file without any reads as
## before.
func test_features() -> void:
	var into := {"points": [], "lines": [], "areas": []}
	var frame := Vector2(53.28, -3.83)
	RealRegion.add_features(into, {"format": 1, "kinds": ["monument"], "names": ["", "A"], "points": [[0, 5328000, -383000, null, null, null, 1, "x"]],
		"lines": [], "areas": [], "words": ["", "church", "gabled", "#778899"],
		"buildings": [[5328000, -383000, 1, 2, 3, 0, 0, 0], [10, 0, 0, 2, 0, 0, 0, 0]]}, frame)
	var b: Array = into.get("buildings", [])
	check(b.size() == 2 and b[0][2] == "church" and b[0][3] == "gabled" and b[0][4] == "#778899" and b[1][2] == "",
		"the looks and their words (%s)" % str(b))
	var p := RealRegion.to_frame(frame, 53.2801, -3.83)
	check(Vector2(float(b[1][0]), float(b[1][1])).distance_to(p) < 0.05, "each a step from the one before, in the region's frame")
	var plain := {"points": [], "lines": [], "areas": []}
	RealRegion.add_features(plain, {"format": 1, "kinds": [], "names": [""], "points": [], "lines": [], "areas": []}, frame)
	check(not plain.has("buildings"), "a file without looks leaves none")


## The bundled regions: their history laid out within the budget, the Dales' boards and viewpoints placed, and their
## buildings' looks matched.
func test_regions() -> void:
	for id in ["dales", "shodoshima"]:
		var r := RealRegion.get_region(id)
		var net := RoadNet.new(r, Roads.flat)
		var by := rows_of(r.features, "british_isles" if id == "dales" else "east_asia")
		# (the eight busiest blocks: the first lay-out of a block works out its roads' heights, so the test stays quick)
		var keys: Array = by.keys()
		keys.sort_custom(func(a, b): return (by[a]["points"] as Array).size() > (by[b]["points"] as Array).size())
		var worst := 0.0
		var items := 0
		for k: Vector2i in keys.slice(0, 8):
			History.lay_out(net, k, by[k])   # (once to work the roads' heights out)
			var t0 := Time.get_ticks_usec()
			var b := History.lay_out(net, k, by[k])
			worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
			for m: String in b["items"]:
				items += (b["items"][m] as Array).size()
		check(items > 0 and worst < 25.0, "%s: %d things in its busiest blocks, %.1f ms the slowest once its roads are known" % [id, items, worst])
		var matched := 0
		for row: Array in r.buildings:
			if not BuildingLooks.of(r, row).is_empty():
				matched += 1
		check(matched > 0, "%s: %d of its %d mapped looks on its buildings" % [id, matched, (r.features.get("buildings", []) as Array).size()])
