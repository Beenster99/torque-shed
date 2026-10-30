extends RefCounted
## Land texture's checks (Ride Anywhere v2, phase D round 2, D5: scripts/scenery/fields.gd), run from tests/run_tests.gd:
## its _test_fields_* functions hand over to these. Small graphs of their own (road_block_tests.gd's) over made-up land,
## and the bundled regions' own features; no scene and no network.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The land of the made-up place round the tee (its main road east to west at z 100, its side road south at x 100): level
## at 10 m north of z 200, then a hillside rising 0.3 in 1 to the south.
static func land(_x: float, z: float) -> float:
	return 10.0 + maxf(0.0, z - 200.0) * 0.3


static func box(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## The rows of `features` (RealRegion.features' shape) that are land texture's, each with its kit in `region`, as the
## streamer hands them over.
static func rows_of(features: Dictionary, region := "") -> Dictionary:
	var out := {"points": [], "lines": [], "areas": []}
	for part in out:
		for row: Array in features.get(part, []):
			var k := SceneryStreamer.kit(str(row[0]), region)
			if str(k.get("model", "")).begins_with("fields:"):
				(out[part] as Array).append([row, k])
	return out


## Every kind of D5's names a model of this script in the kit library, over every region (a default for each), with
## stones, fences, trees, graves and houses there are; and every model a block can name has a mesh.
func test_kits() -> void:
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var bad := []
	for kind: String in kinds:
		var row: Dictionary = kinds[kind]
		if str(row.get("round", "")) != "D5":
			continue
		for region in [""] + RegionKit.regions():
			var k := SceneryStreamer.kit(kind, region)
			if not str(k.get("model", "")).begins_with("fields:"):
				bad.append("%s/%s" % [kind, region])
			if k.has("stone") and not Fields.STONES.has(str(k["stone"])):
				bad.append("%s/%s stone %s" % [kind, region, k["stone"]])
			if k.has("fence") and not Fields.FENCES.has(str(k["fence"])):
				bad.append("%s/%s fence %s" % [kind, region, k["fence"]])
			if kind == "orchard" and not Fields.TREES.has(str(k.get("tree", ""))):
				bad.append("%s/%s tree %s" % [kind, region, k.get("tree")])
			if kind in ["cemetery", "grave_yard"] and (not Fields.GRAVES.has(str(k.get("graves", ""))) or not str(k.get("trees", "")) in ["", "yew", "cypress"]):
				bad.append("%s/%s graves %s" % [kind, region, k.get("graves")])
			if kind == "greenhouses" and not Fields.HOUSES.has(str(k.get("house", ""))):
				bad.append("%s/%s house %s" % [kind, region, k.get("house")])
		for region: String in (row.get("regions", {}) as Dictionary):
			if not region in RegionKit.regions():
				bad.append("%s/%s (no such region)" % [kind, region])
	check(bad.is_empty(), "every land texture kind is modelled in every region, with looks there are (%s)" % str(bad))
	for kind in ["vineyard", "orchard", "greenhouses", "salt_pond", "paddy", "farmland", "wall", "hedge", "fence", "quarry",
			"military", "range", "cemetery", "golf_green", "race_track", "theme_park"]:
		check(kinds.has(kind) and str(kinds[kind]["round"]) == "D5", "%s is round 2's land texture" % kind)
	var missing := []
	var models := ["vine", "bush_vine", "shrub", "plot", "shed", "salt_heap", "pond", "cage", "raft", "oyster_table", "bench",
		"spoil", "heap", "excavator", "dumper", "loader", "headframe", "chimney", "flag:red", "flag:range", "sign:danger",
		"golf_flag", "track", "tyres", "grandstand", "coaster", "big_wheel", "coaster_rail", "coaster_leg", "pan:pink",
		"pan:white", "pan:brine", "paddy:water", "paddy:rice", "hedge:green", "hedge:bocage", "drape:fairway", "drape:fairway2",
		"drape:green", "drape:sand", "drape:tee", "drape:gravel"]
	for s: String in Fields.STONES:
		models.append("wall:" + s)
	for f: String in Fields.FENCES:
		models.append("fence:" + f)
	for tr: String in Fields.TREES:
		models.append("tree:" + tr)
	for g: String in Fields.GRAVES:
		models.append("stone:" + g)
	for h: String in Fields.HOUSES:
		models.append("house:" + h)
	for m: String in models:
		var mesh := Fields.mesh(m)
		if mesh == null or mesh.get_surface_count() == 0 or mesh.get_aabb().size.length() <= 0.0:
			missing.append(m)
	check(missing.is_empty(), "every model has its mesh (%s)" % str(missing))
	var gh := Fields.mesh("house:glass").get_aabb()
	check(absf(gh.size.z - 32.0) < 1.0 and absf(gh.size.x - 9.6) < 0.5, "a glasshouse is a 32 m Venlo of three ridges (%s)" % str(gh.size))
	var st := Fields.mesh("stone:slab").get_aabb()
	check(st.size.y > 0.8 and st.size.y < 1.4, "a headstone is under a man's height (%s)" % str(st.size))


## A made-up place's fields, walls and the rest: each laid out where it should be, clear of the roads, a draw call a
## model, quickly.
func test_lay_out() -> void:
	var r := Roads.tee()
	r.features = {"points": [], "lines": [
		["wall", PackedVector2Array([Vector2(50, 40), Vector2(50, 160)]), null, null, 0, "", null],     # across the main road
		["wall", PackedVector2Array([Vector2(110, 150), Vector2(110, 380)]), null, null, 0, "", null],  # along the lane, past its verge
		["hedge", PackedVector2Array([Vector2(102, 150), Vector2(102, 380)]), null, null, 0, "", null],  # on the lane's verge: left out
		["fence", PackedVector2Array([Vector2(-150, 20), Vector2(-20, 20)]), null, null, 0, "", null],
	], "areas": [
		["vineyard", box(200, 10, 390, 70), null, null, "", "flat"],
		["vineyard", box(150, 230, 260, 360), null, null, "", "hill"],
		["greenhouses", box(420, 120, 500, 300), null, null, "", "glass"],
		["cemetery", box(20, 120, 70, 175), null, null, "", "cem"],
		["orchard", box(-180, 130, -60, 190), null, null, "", "orch"],
		["salt_pond", box(-190, -190, -60, -100), null, null, "", "salt"],
		["golf_green", box(300, 150, 330, 175), null, null, "", "green"],
		["military", box(280, 380, 420, 480), null, null, "", "army"],
		["quarry", box(-190, 240, -60, 380), null, null, "", "q"],
		["vineyard", box(60, 60, 140, 140), null, null, "", "junction"],   # over the junction: kept clear of both roads
	]}
	var net := RoadNet.new(r, land)
	var rows := rows_of(r.features)
	var all := {}
	var worst := 0.0
	for key: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1)]:
		var t0 := Time.get_ticks_usec()
		var b := Fields.lay_out(net, key, rows)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		check(b["items"].size() <= 24, "a draw call a model: a handful a block, not one a thing (%d: %s)" % [b["items"].size(), b["items"].keys()])
		var o := Vector3(key.x * 512.0, 0.0, key.y * 512.0)
		for m: String in b["items"]:
			check(Fields.mesh(m).get_surface_count() > 0, "%s has a mesh" % m)
			if not all.has(m):
				all[m] = []
			for xf: Transform3D in b["items"][m]:
				(all[m] as Array).append(Transform3D(xf.basis, xf.origin + o))
	for m in ["vine", "wall:fieldstone", "fence:wood_wire", "house:glass", "stone:slab", "tree:apple", "pan:pink", "drape:green",
			"golf_flag", "fence:security", "flag:red", "sign:danger"]:
		check(all.has(m) and not (all[m] as Array).is_empty(), "%s laid out (%s)" % [m, all.keys()])
	check(not all.has("hedge:green"), "the hedge on the lane's verge is left out")
	# Nothing on a road or its verge: every piece's middle CLEAR past it (a tile's and a house's further).
	var probe := Fields._Block.new(net, Vector2i.ZERO)
	var on_road := []
	for m: String in all:
		for xf: Transform3D in all[m]:
			var p := Vector2(xf.origin.x, xf.origin.z)
			if probe.gap(p) < Fields.CLEAR - 0.01:
				on_road.append("%s at %s (%.2f)" % [m, p, probe.gap(p)])
	check(on_road.is_empty(), "nothing stands on a road or its verge (%s)" % str(on_road.slice(0, 6)))
	# The wall across the main road stops short of it either side and never crosses.
	var north := 0
	var south := 0
	for xf: Transform3D in all.get("wall:fieldstone", []):
		if absf(xf.origin.x - 50.0) < 0.5:
			if xf.origin.z < 100.0:
				north += 1
				check(xf.origin.z + absf(xf.basis.z.z) * 0.5 <= 100.0 - 3.7 - RoadNet.VERGE - Fields.CLEAR + 0.01, "the wall stops short of the road (north end %.1f)" % (xf.origin.z + absf(xf.basis.z.z) * 0.5))
			else:
				south += 1
	check(north > 5 and south > 5, "the wall is there either side of the road (%d north, %d south)" % [north, south])
	check((all["wall:fieldstone"] as Array).any(func(xf): return absf(xf.origin.x - 110.0) < 0.5), "the lane runs between its own wall")
	# The vines on the level run along the field's long axis (x), on the hillside down the slope (z).
	var along_x := 0
	var along_z := 0
	for xf: Transform3D in all["vine"]:
		var d: Vector3 = xf.basis.z
		if xf.origin.z < 100.0:
			along_x += 1 if absf(d.x) > absf(d.z) * 4.0 else 0
		elif xf.origin.z > 200.0:
			along_z += 1 if absf(d.z) > absf(d.x) * 4.0 else 0
			check(absf(d.y - d.z * 0.3) < 0.05 * absf(d.z) + 0.01, "a vine row down the hill follows its slope")
	check(along_x > 100 and along_z > 100, "rows along the long axis on the level, down the slope on the hill (%d, %d)" % [along_x, along_z])
	# Each glasshouse is wholly in its plot, along its long axis (z).
	for xf: Transform3D in all["house:glass"]:
		check(xf.origin.z - 16.0 >= 119.0 and xf.origin.z + 16.0 <= 301.0 and absf(xf.basis.z.z) > 0.99, "a glasshouse in its plot, along it (%s)" % str(xf.origin))
	check(worst < 80.0, "every block quickly (%.2f ms at worst: a block crammed with a dozen fields)" % worst)


## Paddies: tiles flat on top, stepping down a hillside terrace by terrace; farmland is paddies only where its region's
## kit names the place's climate.
func test_paddies() -> void:
	var r := Roads.tee()
	r.features = {"points": [], "lines": [], "areas": [["paddy", box(150, 220, 300, 330), null, null, "", "rice"]]}
	var net := RoadNet.new(r, land)
	var b := Fields.lay_out(net, Vector2i(0, 0), rows_of(r.features))
	var tiles: Array = (b["items"].get("paddy:water", []) as Array) + (b["items"].get("paddy:rice", []) as Array)
	check(tiles.size() > 200, "a hillside of paddies (%d tiles)" % tiles.size())
	var flat := true
	var tops := {}
	for xf: Transform3D in tiles:
		flat = flat and absf(xf.basis.x.y) < 1e-4 and absf(xf.basis.z.y) < 1e-4
		check(xf.origin.y >= land(xf.origin.x, xf.origin.z + 3.0) - 0.01, "a paddy's water is over the land under it")
		tops[snappedf(xf.origin.y, 0.5)] = true
	check(flat and tops.size() > 10, "each paddy is level, stepping down the hill (%d levels)" % tops.size())
	check(not (b["items"].get("paddy:water", []) as Array).is_empty() and not (b["items"].get("paddy:rice", []) as Array).is_empty(),
		"some fields flooded, some green with rice")
	var farm := {"points": [], "lines": [], "areas": [["farmland", box(150, 220, 300, 330), null, null, "", "farm"]]}
	r.features = farm
	var k := SceneryStreamer.kit("farmland", "british_isles")
	check(Fields.lay_out(net, Vector2i(0, 0), {"areas": [[farm["areas"][0], k]]})["items"].is_empty(), "farmland in Britain is not paddies")
	var hot := k.duplicate()
	hot["climates"] = [Fields._Block.new(net, Vector2i.ZERO).koppen(Vector2(225, 275))]   # (the made-up place's own, whatever it is)
	var got: Dictionary = Fields.lay_out(net, Vector2i(0, 0), {"areas": [[farm["areas"][0], hot]]})["items"]
	check(got.has("paddy:water") or got.has("paddy:rice"), "farmland in a climate its kit names is paddies")
	check(SceneryStreamer.kit("farmland", "south_east_asia")["climates"].has("Af"), "south-east Asia's hot and wet farmland is paddies")


## An area over two blocks is filled once: each block its own part, meeting at the edge; a wall over two blocks is in
## both, end to end.
func test_blocks_meet() -> void:
	var r := Roads.tee()
	r.features = {"points": [], "lines": [["wall", PackedVector2Array([Vector2(300, 300), Vector2(800, 300)]), null, null, 0, "", null]],
		"areas": [["orchard", box(400, 200, 650, 450), null, null, "", "o"], ["vineyard", box(400, 460, 650, 500), null, null, "", "v"]]}
	var net := RoadNet.new(r, Roads.flat)
	var rows := rows_of(r.features)
	var seen := {}
	var dup := 0
	var trees := 0
	var wall := 0.0
	for key: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
		var b := Fields.lay_out(net, key, rows)
		for xf: Transform3D in b["items"].get("tree:apple", []):
			var p := Vector2i(roundi(xf.origin.x + key.x * 512.0), roundi(xf.origin.z))
			if seen.has(p):
				dup += 1
			seen[p] = true
			trees += 1
		for xf: Transform3D in b["items"].get("wall:fieldstone", []):
			wall += xf.basis.z.length()
	var whole := Fields.lay_out(net, Vector2i(0, 0), rows)
	check(dup == 0 and trees > 1000, "the orchard over two blocks has each tree once (%d trees, %d twice)" % [trees, dup])
	check(absf(wall - 500.0) < 0.5, "the wall over two blocks is in both, end to end, once (%.1f m of 500)" % wall)
	check(not whole["items"].is_empty(), "each block has its part")


## The bundled regions' land texture as the game lays it out: the Dales' walls and Shodoshima's orchards, each block
## quickly, nothing on a road.
func test_regions() -> void:
	for id in ["dales", "shodoshima"]:
		RealRegion.forget(id)
		var r := RealRegion.get_region(id)
		var net := RoadNet.new(r, func(x, z): return 20.0 + sin(x * 0.01) * 6.0 + cos(z * 0.013) * 5.0)
		var region := "british_isles" if id == "dales" else "east_asia"
		var filed := SceneryStreamer.file_features(r.features)
		var by_block := {}
		for key: Vector2i in filed:
			var rows := {"points": [], "lines": [], "areas": []}
			var any := false
			for part in ["points", "lines", "areas"]:
				for i in (filed[key] as Dictionary)[part]:
					var row: Array = r.features[part][i]
					var k := SceneryStreamer.kit(str(row[0]), region)
					if str(k.get("model", "")).begins_with("fields:"):
						(rows[part] as Array).append([row, k])
						any = true
			if any:
				by_block[key] = rows
		var worst := 0.0
		var worst_key := Vector2i.ZERO
		var times: Array = []
		var pieces := 0
		var counts := {}
		# (each block twice: the first time round a place waits on its roads' heights, as the road blocks do)
		for key: Vector2i in by_block:
			Fields.lay_out(net, key, by_block[key])
		for key: Vector2i in by_block:
			var t0 := Time.get_ticks_usec()
			var b := Fields.lay_out(net, key, by_block[key])
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			times.append(ms)
			if ms > worst:
				worst = ms
				worst_key = key
			for m: String in b["items"]:
				pieces += (b["items"][m] as Array).size()
				counts[m] = int(counts.get(m, 0)) + (b["items"][m] as Array).size()
		if OS.get_environment("FIELDS_PROFILE") != "":
			var slow := {}
			for part in ["lines", "areas"]:
				for pair: Array in by_block[worst_key][part]:
					var one := {"points": [], "lines": [], "areas": []}
					one[part] = [pair]
					var t1 := Time.get_ticks_usec()
					var got: Dictionary = Fields.lay_out(net, worst_key, one)
					var n := 0
					for m: String in got["items"]:
						n += (got["items"][m] as Array).size()
					var kind := "%s %s" % [part, pair[0][0]]
					var have: Array = slow.get(kind, [0.0, 0])
					slow[kind] = [float(have[0]) + (Time.get_ticks_usec() - t1) / 1000.0, int(have[1]) + n]
			print("  the slowest block by kind [ms, pieces]: ", slow)
			var bb := Fields._Block.new(net, worst_key)
			var c0 := (Vector2(worst_key) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
			for what in ["bare", "ground", "gap", "near"]:
				var t2 := Time.get_ticks_usec()
				for q in 1000:
					var pq := c0 + Vector2(q % 37, q / 37) * 7.0 + Vector2(0.3, 0.7) * float(what.length())
					match what:
						"bare": bb.bare(pq)
						"ground": bb.ground(pq)
						"gap": bb.gap(pq)
						"near": net._near(pq.x, pq.y)
				print("  1000 %s: %.2f ms" % [what, (Time.get_ticks_usec() - t2) / 1000.0])
		times.sort()
		var middle: float = times[times.size() / 2] if not times.is_empty() else 0.0
		print("  %s: %d blocks of land texture, %d pieces, the middle block %.2f ms, the slowest %.2f ms (%s); %s" % [id, by_block.size(), pieces,
			middle, worst, worst_key, str(counts)])
		check(pieces > 200, "%s has its land texture (%d pieces)" % [id, pieces])
		# (a block of fields is thousands of pieces, laid out on a worker: the middle one is what most of a ride waits on;
		# the busiest is a village's orchards or a dale's walls along its lanes)
		check(middle < 8.0 and worst < 200.0, "%s: a block in %.2f ms (the middle), the slowest %.2f ms" % [id, middle, worst])
	var dales := RealRegion.get_region("dales")
	check(dales != null, "the Dales are bundled")
