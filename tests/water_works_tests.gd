extends RefCounted
## Water and coast's checks (Ride Anywhere v2, phase D round 1, D3: scripts/scenery/water_works.gd), run from
## tests/run_tests.gd: its _test_water_* functions hand over to these. Small graphs of their own (road_block_tests.gd's)
## over made-up land, and the bundled regions' own features; no scene and no network.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The land of the made-up place: a valley running north to south at x 250 (its floor at 10 m, 40 wide, its sides
## rising 0.3 in 1) south of z 200, level at 10 m round the road (z 100), and the sea east of x 440 (below 0 m).
static func land(x: float, z: float) -> float:
	if x > 440.0:
		return -4.0 - (x - 440.0) * 0.05
	if x > 400.0:
		return lerpf(10.0, -4.0, (x - 400.0) / 40.0)
	var side := clampf(absf(x - 250.0) - 20.0, 0.0, 200.0) * 0.3
	return 10.0 + side * smoothstep(150.0, 220.0, z)


## Every kind of D3's names a model of this script in the kit library, over every region (a default for each), and
## every model a block can name has a mesh.
func test_kits() -> void:
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var bad := []
	for kind: String in kinds:
		var row: Dictionary = kinds[kind]
		if str(row.get("round", "")) != "D3":
			continue
		for region in [""] + RegionKit.regions():
			var k := SceneryStreamer.kit(kind, region)
			if not str(k.get("model", "")).begins_with("water_works:"):
				bad.append("%s/%s" % [kind, region])
		for region: String in (row.get("regions", {}) as Dictionary):
			if not region in RegionKit.regions():
				bad.append("%s/%s (no such region)" % [kind, region])
			for f: String in ["stone", "armour", "deck", "legs", "rail", "face"]:
				var v = (row["regions"][region] as Dictionary).get(f)
				if v != null and not WaterWorks.STONES.has(str(v)):
					bad.append("%s/%s %s %s" % [kind, region, f, v])
			for boat in (row["regions"][region] as Dictionary).get("boats", []):
				if not WaterWorks.BOAT_LENGTH.has(str(boat)):
					bad.append("%s/%s boat %s" % [kind, region, boat])
	check(bad.is_empty(), "every water kind is modelled in every region, with stones and boats there are (%s)" % str(bad))
	for kind in ["dam", "waterfall", "breakwater", "pier", "quay", "marina", "canal_lock", "geyser"]:
		check(kinds.has(kind) and str(kinds[kind]["round"]) == "D3", "%s is round 1's water" % kind)
	var missing := []
	for m in ["block:concrete", "block:grass", "wedge:grass", "wedge:rock", "mound:rock", "arch:sandstone", "sheet", "foam",
			"steam", "pool", "jet", "tetrapod", "bollard", "lamp_post", "lamp_head:white", "beacon:red", "beacon:green",
			"light_tower:red", "boat:narrowboat:2", "boat:yacht", "boat:fishing:1", "boat:barge", "boat:motor",
			"boat:pirogue:0", "boat:longtail:3", "boat:lifeboat", "water_works:block:granite"]:
		var mesh := WaterWorks.mesh(m)
		if mesh == null or mesh.get_surface_count() == 0 or mesh.get_aabb().size.length() <= 0.0:
			missing.append(m)
	check(missing.is_empty(), "every model has its mesh (%s)" % str(missing))
	var nb := WaterWorks.mesh("boat:narrowboat:0").get_aabb()
	check(absf(nb.size.z - 20.0) < 1.0 and absf(nb.size.x - 2.1) < 0.3, "a narrowboat is 20 m by 7 ft (%s)" % str(nb.size))


## The rows of `features` (RealRegion.features' shape) that are water's, each with its kit (the default's: the
## made-up place has no country), as the streamer hands them over.
static func rows_of(features: Dictionary, region := "") -> Dictionary:
	var out := {"points": [], "lines": [], "areas": []}
	for part in out:
		for row: Array in features.get(part, []):
			var k := SceneryStreamer.kit(str(row[0]), region)
			if str(k.get("model", "")).begins_with("water_works:"):
				(out[part] as Array).append([row, k])
	return out


## A made-up place's dam, falls, harbour and lock: each stands where it should, off the roads, laid out quickly.
func test_lay_out() -> void:
	var r := Roads.tee()
	r.features = {"points": [
		["waterfall", 302.0, 260.0, 12.0, null, null, "", "fall"],     # on the valley's east side
		["geyser", 200.0, 450.0, null, null, null, "", "gey"],
		["blowhole", 432.0, 350.0, null, null, null, "", "blow"],
		["waterfall", 250.0, 100.0, null, null, null, "", "onroad"],   # on the main road: left out
	], "lines": [
		["dam", PackedVector2Array([Vector2(130, 300), Vector2(370, 300)]), null, null, 0, "", "kielder"],
		["dam", PackedVector2Array([Vector2(235, 240), Vector2(265, 240)]), 18.0, null, 0, "", "wall"],
		["breakwater", PackedVector2Array([Vector2(410, 420), Vector2(500, 420)]), null, 9.0, 0, "", "bw"],
		["pier", PackedVector2Array([Vector2(410, 470), Vector2(500, 470)]), null, 4.0, 0, "", "pier"],
		["quay", PackedVector2Array([Vector2(430, 140), Vector2(430, 220)]), null, null, 0, "", "quay"],
		["pier", PackedVector2Array([Vector2(300, 60), Vector2(300, 140)]), null, 3.0, 0, "", "acrossroad"],
	], "areas": [
		["canal_lock", PackedVector2Array([Vector2(150, 160), Vector2(180, 160), Vector2(180, 165), Vector2(150, 165)]), null, null, "", "lock"],
		["marina", PackedVector2Array([Vector2(445, 150), Vector2(505, 150), Vector2(505, 250), Vector2(445, 250)]), null, null, "", "marina"],
	]}
	var net := RoadNet.new(r, land)
	var rows := rows_of(r.features)
	var t0 := Time.get_ticks_usec()
	var b := WaterWorks.lay_out(net, Vector2i(0, 0), rows)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var items: Dictionary = b["items"]
	var count := 0
	for m: String in items:
		count += (items[m] as Array).size()
		check(WaterWorks.mesh(m).get_surface_count() > 0, "%s has a mesh" % m)
	check(count > 50, "a block of water works (%d pieces in %d models: %s)" % [count, items.size(), str(items.keys())])
	check(items.size() <= 24, "a draw call a model: a handful, not one a thing (%d)" % items.size())
	# The long dam is an earth bank, its crest at the lower of its ends (40 m), its slopes grassed.
	var grass: Array = items.get("block:grass", [])
	var crest := -INF
	for xf: Transform3D in grass:
		crest = maxf(crest, xf.origin.y + xf.basis.y.length())
	check(not grass.is_empty() and absf(crest - 40.0) < 1.0, "the long dam is an embankment up to its banks' height (%.1f)" % crest)
	check((items.get("wedge:grass", []) as Array).size() > 10, "with its grassed slope downstream")
	# The short one a concrete wall its mapped height up from the valley floor, with its spillway.
	var walls := (items.get("block:concrete", []) as Array).filter(func(xf): return absf(xf.origin.z - 240.0) < 3.0)
	var top := -INF
	for xf: Transform3D in walls:
		top = maxf(top, xf.origin.y + xf.basis.y.length())
	check(not walls.is_empty() and top > 26.0 and top < 29.5, "the short dam a wall 18 m up off the floor (%.1f)" % top)
	# The fall: a sheet from its lip down 12 m.
	var sheets: Array = items.get("sheet", [])
	var fall := sheets.filter(func(xf): return Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(302, 260)) < 2.0)
	check(not fall.is_empty() and absf((fall[0] as Transform3D).basis.y.length() - 12.0) < 1.5,
		"the waterfall falls its mapped 12 m (%s)" % str(fall))
	check(sheets.all(func(xf): return Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(250, 100)) > 10.0),
		"the one the map puts on the road isn't there")
	# The harbour: the breakwater out of the sea, a light at its end, the pier on legs with lamps, boats.
	var mounds: Array = items.get("mound:rock", [])
	check(mounds.size() > 8 and mounds.all(func(xf): return xf.origin.y + xf.basis.y.length() > 2.0),
		"the breakwater stands out of the sea (%d)" % mounds.size())
	check((items.get("light_tower:red", []) as Array).size() + (items.get("light_tower:green", []) as Array).size() >= 1,
		"a light at its end")
	check((items.get("lamp_post", []) as Array).size() >= 3 and bool(b["dress"]["lamps"]), "lamps along the pier, lit at dusk")
	var boats := 0
	for m: String in items:
		if m.begins_with("boat:"):
			boats += (items[m] as Array).size()
	check(boats >= 6, "boats at the quay, in the lock and the marina (%d)" % boats)
	check(items.keys().any(func(m): return m.begins_with("boat:narrowboat")) or items.keys().any(func(m): return m.begins_with("boat:motor")),
		"a boat in the lock")
	check((items.get("block:timber", []) as Array).size() >= 4, "the lock's gates and beams")
	# The geyser's jet and the blowhole's spout come in with dress, nothing else moves.
	check((b["dress"]["jets"] as Array).size() == 2, "the geyser and the blowhole have their jets")
	# Nothing on a road or its verge: every piece's middle past it, but for the pier the map runs across the road,
	# which is left out where it would be.
	var on_road := []
	for m: String in items:
		for xf: Transform3D in items[m]:
			var p := Vector2(xf.origin.x, xf.origin.z)
			var hit := net.locate(p.x, p.y, -1, false)
			if not hit.is_empty() and (int(hit["node"]) >= 0 or absf(float(hit["lat"])) < float(hit["width"]) * 0.5 + RoadNet.VERGE):
				on_road.append("%s at %s" % [m, p])
	check(on_road.is_empty(), "nothing stands on a road or its verge (%s)" % str(on_road.slice(0, 5)))
	check(ms < 25.0, "laid out in %.2f ms" % ms)
	# Into the world: dress adds the jets and the lamps' glow, nothing a bike can touch.
	var node := Node3D.new()
	WaterWorks.dress(node, b["dress"])
	check(node.find_children("*", "CollisionObject3D", true, false).is_empty() and node.get_child_count() == 1,
		"dress puts in what moves and glows, nothing a bike can touch")
	node.free()


## A road along a dam's crest: the dam stands under it, its surface as it was.
func test_dam_under_road() -> void:
	var r := Roads.graph([[130, 300], [370, 300]], [[0, 1, "secondary"]])
	r.features = {"points": [], "areas": [], "lines": [
		["dam", PackedVector2Array([Vector2(130, 300), Vector2(370, 300)]), null, null, 0, "", "crest"]]}
	var net := RoadNet.new(r, land)
	var b := WaterWorks.lay_out(net, Vector2i(0, 0), rows_of(r.features))
	var under := 0
	var over := []
	for m: String in b["items"]:
		for xf: Transform3D in b["items"][m]:
			var on := net.locate(xf.origin.x, xf.origin.z)
			if on.is_empty() or is_nan(float(on["y"])):
				continue
			if absf(float(on["lat"])) < float(on["width"]) * 0.5 + RoadNet.VERGE:
				if xf.origin.y + absf(xf.basis.y.y) > float(on["y"]) - 0.3:
					over.append("%s %.1f over %.1f" % [m, xf.origin.y + xf.basis.y.y, float(on["y"])])
				else:
					under += 1
	check(under > 5 and over.is_empty(), "the dam under the road (%d pieces), none up through it (%s)" % [under, str(over.slice(0, 4))])


## A canal in Britain: its towpath along one bank, narrowboats moored along it, none on the road it passes under.
func test_canal() -> void:
	var r := Roads.graph([[250, -100], [250, 600]], [[0, 1, "secondary"]])
	r.features = {"points": [], "areas": [], "lines": [
		["canal", PackedVector2Array([Vector2(0, 300), Vector2(500, 300)]), null, 9.0, 0, "", "leeds_liverpool"]]}
	var net := RoadNet.new(r, Roads.flat)
	var b := WaterWorks.lay_out(net, Vector2i(0, 0), rows_of(r.features, "british_isles"))
	var path: Array = b["items"].get("block:gravel", [])
	var boats := []
	for m: String in b["items"]:
		if m.begins_with("boat:narrowboat"):
			boats.append_array(b["items"][m])
	check(path.size() > 30, "a towpath along it (%d pieces)" % path.size())
	check(boats.size() >= 1, "narrowboats moored along it (%d)" % boats.size())
	check(path.all(func(xf): return absf(xf.origin.x - 250.0) > 4.0 + 4.0) and boats.all(func(xf): return absf(xf.origin.x - 250.0) > 12.0),
		"none on the road it passes under")
	# A lock the map has as a stretch of the canal (as it has the Bingley Five Rise): its walls, its gates, a boat.
	r.features["lines"].append(["canal_lock", PackedVector2Array([Vector2(100, 300), Vector2(124, 300)]), null, null, 0, "Five Rise", "lock25"])
	var lk := WaterWorks.lay_out(net, Vector2i(0, 0), rows_of(r.features, "british_isles"))
	var walls := (lk["items"].get("block:gritstone", []) as Array).filter(func(xf): return absf(xf.origin.x - 112.0) < 1.0)
	var leaves := (lk["items"].get("block:timber", []) as Array).filter(func(xf): return absf(xf.origin.x - 112.0) < 14.0)
	var in_lock := 0
	for m: String in lk["items"]:
		if m.begins_with("boat:narrowboat"):
			in_lock += (lk["items"][m] as Array).filter(func(xf): return absf(xf.origin.x - 112.0) < 2.0 and absf(xf.origin.z - 300.0) < 1.0).size()
	check(walls.size() == 2 and leaves.size() >= 8, "the lock's walls and its two pairs of gates (%d, %d)" % [walls.size(), leaves.size()])
	check(in_lock == (1 if WaterWorks.roll("lock25boat") < 0.7 else 0), "a narrowboat in it when it's busy (%d)" % in_lock)
	r.features["lines"].pop_back()
	var none := WaterWorks.lay_out(net, Vector2i(0, 0), rows_of(r.features, "sub_saharan_africa"))
	check(not none["items"].keys().any(func(m): return m.begins_with("boat:")), "no narrowboats where the kit has none")


## Two blocks a line runs over: each lays out its own pieces of it, none twice.
func test_blocks_meet() -> void:
	var r := Roads.graph([[-100, -900], [-50, -900]], [[0, 1, "track"]])
	r.features = {"points": [], "areas": [], "lines": [
		["breakwater", PackedVector2Array([Vector2(300, 700), Vector2(900, 700)]), null, 8.0, 0, "", "long"]]}
	var net := RoadNet.new(r, func(_x, _z): return -5.0)
	var rows := rows_of(r.features)
	var a: Array = WaterWorks.lay_out(net, Vector2i(0, 1), rows)["items"].get("mound:rock", [])
	var c: Array = WaterWorks.lay_out(net, Vector2i(1, 1), rows)["items"].get("mound:rock", [])
	var total := 0.0
	for xf: Transform3D in a + c:
		total += xf.basis.z.length()
	check(not a.is_empty() and not c.is_empty() and absf(total - 600.0 - 0.05 * (a.size() + c.size())) < 1.0,
		"the breakwater over two blocks is in both, end to end, once (%.1f m of 600)" % total)


## The bundled regions' water as the game lays it out: the Dales' falls and Shodoshima's harbour walls and dams,
## each block quickly, nothing on a road.
func test_regions() -> void:
	for id in ["dales", "shodoshima"]:
		RealRegion.forget(id)
		var r := RealRegion.get_region(id)
		var net := RoadNet.new(r, func(x, z): return 20.0 + sin(x * 0.01) * 6.0 + cos(z * 0.013) * 5.0)
		var by_block := {}
		for part in ["points", "lines", "areas"]:
			for row: Array in r.features[part]:
				var k := SceneryStreamer.kit(str(row[0]))
				if not str(k.get("model", "")).begins_with("water_works:"):
					continue
				var pts: PackedVector2Array = PackedVector2Array([Vector2(float(row[1]), float(row[2]))]) if part == "points" else row[1]
				var seen := {}
				for p in pts:
					var key := RoadBlock.key_of(p.x, p.y)
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							seen[key + Vector2i(dx, dz)] = true
				for key: Vector2i in seen:
					if not by_block.has(key):
						by_block[key] = {"points": [], "lines": [], "areas": []}
					(by_block[key][part] as Array).append([row, k])
		var worst := 0.0
		var worst_key := Vector2i.ZERO
		var pieces := 0
		var over := 0
		# (each block twice: the first time round a place waits on its roads' heights, as the road blocks do)
		for key: Vector2i in by_block:
			WaterWorks.lay_out(net, key, by_block[key])
		for key: Vector2i in by_block:
			var t0 := Time.get_ticks_usec()
			var b := WaterWorks.lay_out(net, key, by_block[key])
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if ms > 2.0:
				over += 1
			if ms > worst:
				worst = ms
				worst_key = key
			for m: String in b["items"]:
				pieces += (b["items"][m] as Array).size()
		print("  %s: %d blocks of water, %d pieces, %d over 2 ms, the slowest %.2f ms (%s: %s)" % [id, by_block.size(), pieces, over, worst, worst_key,
			str((by_block[worst_key] as Dictionary).values().map(func(v): return (v as Array).size()))])
		if OS.get_environment("WATER_PROFILE") != "":
			var slow := {}
			for key: Vector2i in by_block:
				for part in ["points", "lines", "areas"]:
					for pair: Array in by_block[key][part]:
						var one := {"points": [], "lines": [], "areas": []}
						one[part] = [pair]
						var t0 := Time.get_ticks_usec()
						WaterWorks.lay_out(net, key, one)
						var ms := (Time.get_ticks_usec() - t0) / 1000.0
						var kind := "%s %s" % [part, pair[0][0]]
						slow[kind] = maxf(float(slow.get(kind, 0.0)), ms)
			var bb := WaterWorks._Block.new(net, worst_key)
			var c0 := (Vector2(worst_key) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
			var tg := Time.get_ticks_usec()
			bb.gap(c0)
			print("  the block's first look at a road: %.2f ms" % [(Time.get_ticks_usec() - tg) / 1000.0])
			for what in ["bare", "ground", "clear", "near"]:
				var t2 := Time.get_ticks_usec()
				for q in 1000:
					var pq := c0 + Vector2(q % 37, q / 37) * 7.0
					match what:
						"bare": bb.bare(pq)
						"ground": bb.ground(pq)
						"clear": bb.clear(pq)
						"near": net._near(pq.x, pq.y)
				print("  1000 %s: %.2f ms" % [what, (Time.get_ticks_usec() - t2) / 1000.0])
			var t1 := Time.get_ticks_usec()
			WaterWorks.lay_out(net, worst_key, {"points": [], "lines": [], "areas": []})
			print("  slowest by kind: %s; an empty block %.3f ms" % [str(slow), (Time.get_ticks_usec() - t1) / 1000.0])
		check(pieces > 20, "%s has its water works (%d pieces)" % [id, pieces])
		check(worst < 40.0, "%s: every block quickly (%.2f ms at worst)" % [id, worst])
