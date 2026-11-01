extends RefCounted
## Real roads' checks (a road planned across a region by RoutePlanner, its land read by RealTerrain, laid out by
## AdventureRoute.plan_real and built into chunks), run from tests/run_tests.gd: its _test_real_* functions hand over to
## these. The roads are the bundled regions' tours (see Rides): round Shodoshima, and the long one round the Dales.

const Rides := preload("res://tests/rides.gd")
const PACK := "shodoshima"
## The long road.
const EPIC := "dales"
## What a chunk may hold (see test_budget): the buildings' vertices, and trees, bushes, rocks and the like.
const BUDGET_BUILDING_VERTS := 20000
const BUDGET_INSTANCES := 800

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func test_pack() -> void:
	var p := Rides.tour_pack(PACK)
	check(p != null and p.hash != "" and p.credits.size() > 0, "the tour of %s plans, with its hash and credits" % PACK)
	if p == null:
		return
	check(Rides.tour_pack(PACK) == p and RealPack.get_pack(p.id) == p, "and is planned once, then shared")
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
	var on := 0
	var all := 0
	for k in range(0, p.x.size(), 50):
		var h := p.terrain.height(p.x[k], p.z[k])
		if not is_nan(h):
			all += 1
			on += int(absf(h - p.e[k]) < 6.0)
	check(on > all * 0.9, "the road sits on the land it was planned over (%d of %d points within 6 m: it rides over the bumps)" % [on, all])


## The land's three levels: the fine one by the road, the coarse one out over the hillsides, the ridge level to the
## skyline; joined without steps, and the whole region small.
func test_levels() -> void:
	var p := Rides.tour_pack(PACK)
	var t := p.terrain
	check(t.levels.size() == 3 and t.levels[0].spacing < t.levels[1].spacing and t.levels[1].spacing < t.levels[2].spacing,
		"three levels of land, each coarser than the last")
	var k := 2000
	var hd := atan2(p.x[k + 1] - p.x[k], -(p.z[k + 1] - p.z[k]))
	var rx := cos(hd)
	var rz := sin(hd)
	var reach := {}
	for side: float in [-1.0, 1.0]:
		for off in [100.0, 600.0, 1200.0, 3000.0, 9000.0]:
			var h := t.height(p.x[k] + rx * off * side, p.z[k] + rz * off * side)
			if not is_nan(h):
				reach[int(off)] = true
	check(reach.has(100) and reach.has(600) and reach.has(1200) and reach.has(3000) and reach.has(9000),
		"land to 9 km out (%s m out have heights)" % str(reach.keys()))
	check(is_nan(t.height(p.x[k] + 80000.0, p.z[k])), "and none past the ridge level's reach")
	check(not is_nan(t.height_at_level(1, p.x[k] + rx * 1200.0, p.z[k] + rz * 1200.0)), "1.2 km out the coarse level has it")
	# Walk out from the road: no step where one level hands over to the next (the fine tiles' last metres are eased
	# into the coarse level).
	var worst := 0.0
	var handovers := 0
	for side: float in [-1.0, 1.0]:
		for kk in range(400, 5800, 200):
			var hh := atan2(p.x[kk + 1] - p.x[kk], -(p.z[kk + 1] - p.z[kk]))
			var was_fine := true
			var prev := NAN
			var prev2 := NAN
			for step in range(0, 2400, 4):
				var x: float = p.x[kk] + cos(hh) * step * side
				var z: float = p.z[kk] + sin(hh) * step * side
				var fine_h := t.height_at_level(0, x, z)
				var h := t.height(x, z)
				if was_fine and is_nan(fine_h) and not is_nan(prev) and not is_nan(prev2) and not is_nan(h):
					handovers += 1
					worst = maxf(worst, absf(h - (2.0 * prev - prev2)))   # off the line the slope was already on
				if not is_nan(fine_h):
					was_fine = true
				else:
					was_fine = false
				prev2 = prev
				prev = h
	check(handovers > 5 and worst < 3.0, "no step where the fine level hands over to the coarse (%d handovers, worst %.2f m off the slope)" % [handovers, worst])
	# The tile codec against a tile worked out by hand: [[10, 12], [14, 20]].
	var raw := PackedByteArray()
	raw.resize(8)
	for i in 4:
		raw.encode_u16(i * 2, [10, 2, 4, 4][i])   # differences along x then z: a, b-a; c-a, (d-c)-(b-a)
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var got := RealTerrain.decode_heights(packed, 2, 0.0, 1.0)
	check(got.size() == 4 and got[0] == 10.0 and got[1] == 12.0 and got[2] == 14.0 and got[3] == 20.0, "a tile's bytes decode to its heights (%s)" % str(got))
	check(RealTerrain.decode_heights(PackedByteArray([1, 2, 3]), 2, 0.0, 1.0).is_empty(), "and bad bytes to nothing")
	var total := 0
	var root := RealRegion.DIR.path_join(PACK)
	var dir := DirAccess.open(root)
	for sub in ["tiles", "coarse", "ridge"]:
		var d := DirAccess.open(root.path_join(sub))
		for f in d.get_files():
			total += FileAccess.get_file_as_bytes(root.path_join(sub).path_join(f)).size()
	check(dir != null and total < 10000000, "the whole island's land is %.1f MB" % (total / 1.0e6))


func test_ridges() -> void:
	var w := AdventureWorld.new()
	w.setup(Rides.tour_pack(PACK), 11, 23.0)
	t.add_child(w)   # (the blocks are put in a frame at a time, once laid out on worker threads)
	var p: RealPack = w.route.real
	var end := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < end and (w.ridges.busy() or w.ridges.block_count() == 0):
		await t.get_tree().process_frame
	check(w.ridges != null and w.ridges.block_count() > 4, "the world draws the real skyline (%d blocks of hills)" % w.ridges.block_count())
	# Pushed down by the road so the land hides it, the real height from a kilometre out.
	var k := 2400
	var fine := p.terrain.height(p.x[k], p.z[k])
	var ridge := _ridge_at(p.terrain, p.x[k], p.z[k])
	check(ridge < fine - 30.0, "under the road the ridge level lies %.0f m below the land (%.0f vs %.0f)" % [fine - ridge, ridge, fine])
	# 1.5 km out, where both levels have it, they agree (the coarse level is the finer of the two).
	var diffs := []
	for kk in range(400, p.x.size() - 400, 400):
		var hh := atan2(p.x[kk + 1] - p.x[kk], -(p.z[kk + 1] - p.z[kk]))
		for side: float in [-1.0, 1.0]:
			var fc := p.terrain.height_at_level(1, p.x[kk] + cos(hh) * 1500.0 * side, p.z[kk] + sin(hh) * 1500.0 * side)
			var fr := p.terrain.height_at_level(2, p.x[kk] + cos(hh) * 1500.0 * side, p.z[kk] + sin(hh) * 1500.0 * side)
			if not is_nan(fc) and not is_nan(fr):
				diffs.append(absf(fc - fr))
	diffs.sort()
	var mid: float = diffs[diffs.size() / 2] if not diffs.is_empty() else INF
	check(mid < 150.0, "and 1.5 km out it is about the real ground's, as the coarse level has it (%.0f m apart at the middle of %d points)" % [mid, diffs.size()])
	# Moves with the origin.
	var block: MeshInstance3D = w.ridges.get_children()[0]
	var before := block.position
	w.origin += Vector3(1024.0, 0.0, 0.0)
	w.ridges.place()
	check(absf((block.position - before).x + 1024.0) < 0.01, "and moves with the world's origin")
	w.queue_free()
	await t.get_tree().process_frame


func _ridge_at(t: RealTerrain, x: float, z: float) -> float:
	var sp := t.ridge_spacing()
	var n := t.ridge_cells()
	var ix := int(floor(x / sp))
	var iz := int(floor(z / sp))
	var tile := t.ridge_tile(Vector2i(floori(float(ix) / n), floori(float(iz) / n)))
	return NAN if tile.is_empty() else tile[posmod(iz, n) * n + posmod(ix, n)]


func test_land() -> void:
	var p := Rides.tour_pack(PACK)
	check(p.building_count > 200 and not p.buildings.is_empty(), "the road has its buildings (%d), filed by the chunk beside them" % p.building_count)
	var bad := 0
	var kinds := {}
	for c in p.buildings:
		for b: Array in p.buildings[c]:
			kinds[int(b[6])] = true
			var k := int(b[7])
			if int(c) != k / 32 or int(b[6]) >= RealPack.BUILDING_KINDS.size() or float(b[2]) < 2.0 or float(b[5]) < 2.0:
				bad += 1
	check(bad == 0 and kinds.size() >= 2, "each in its own chunk, a kind we draw, a real size (%d kinds)" % kinds.size())
	var seen := {}
	for k in range(0, p.x.size(), 20):
		for off: float in [-30.0, 30.0]:
			seen[p.terrain.cover(p.x[k] + off, p.z[k])] = true
	check(seen.has(RealPack.COVER.find("forest")) and not seen.has(-1), "cover under the road's sides (%d kinds, forest among them)" % seen.size())
	check(p.terrain.cover(1.0e7, 0.0) == -1, "and unknown beyond the tiles")
	var named := 0
	for c in p.chunks.size():
		named += int(p.name_at(c * 128.0 + 1.0) != "")
	check(named > 5, "roads have their own names (%d chunks named)" % named)


func test_building_shapes() -> void:
	var meshes := {}
	for kind in RealPack.BUILDING_KINDS:
		var a := AdventureProps.new_arrays()
		AdventureProps.real_building(a, Vector3(10.0, 5.0, -20.0), 12.0, 8.0, 0.7, 6.0, kind)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v: Vector3 in a["v"]:
			lo = lo.min(v)
			hi = hi.max(v)
		meshes[kind] = a["v"].size()
		# Inside the footprint's circle, from the walls' skirt to roof height, and drawn.
		var ok: bool = a["v"].size() > 20 and lo.y >= 5.0 - AdventureProps.SKIRT - 0.01 and hi.y <= 5.0 + 6.0 + 4.0 \
			and Vector2(lo.x - 10.0, lo.z + 20.0).length() < 12.0 and Vector2(hi.x - 10.0, hi.z + 20.0).length() < 12.0
		check(ok, "a %s is a building on its footprint (%d vertices, up to %.1f m)" % [kind, a["v"].size(), hi.y - 5.0])
	var b := AdventureProps.new_arrays()
	AdventureProps.real_building(b, Vector3(10.0, 5.0, -20.0), 12.0, 8.0, 0.7, 6.0, "house")
	var c := AdventureProps.new_arrays()
	AdventureProps.real_building(c, Vector3(10.0, 5.0, -20.0), 12.0, 8.0, 0.7, 6.0, "house")
	check(b["v"] == c["v"] and b["c"] == c["c"], "and the same one every time")


## The trees stand where the canopy map has them (tools/tree_bake.py, RealTerrain.trees_at, AdventureChunk._canopy_trees):
## a cell's grid read the right way round, the bundled region's trees under the road's sides, and each chunk's trees on
## ground the map has trees on, never in the water, and as tall as the map says.
func test_trees() -> void:
	var g := RealTerrain.new("", {"frame": {"lat": 54.375, "lon": -2.125}})
	# Cell 577_711 (54.25 to 54.5 N, 2.25 to 2 W) as two rows of three: thick conifers 20 m tall in the north row's
	# middle, a few broadleaves 6 m tall at the south row's west end (as tools/tree_bake.py writes them).
	g.add_trees({"cell": "577_711", "rows": 2, "cols": 3, "trees": "eNpjeMWgzMAAAAUBAQ4=", "leaf": "eNpjYGJgZGAAAAATAAQ="})
	var m := RealTerrain.metres_per_degree(54.375)
	var at := func(lat: float, lon: float) -> int: return g.trees_at((lon + 2.125) * m.y, -(lat - 54.375) * m.x)
	var north_middle: int = at.call(54.45, -2.125)
	var south_west: int = at.call(54.3, -2.2)
	check(g.has_trees() and north_middle == (7 << 5 | 10) + 2 * 256 and south_west == (1 << 5 | 3) + 256 and at.call(54.45, -2.2) == 0,
		"a cell's trees read north to south, west to east: %d %d" % [north_middle, south_west])
	check(at.call(54.6, -2.125) == -1 and RealTerrain.new().trees_at(0.0, 0.0) == -1, "and none known beyond its cells")
	var p := Rides.tour_pack(PACK)
	check(p.terrain.has_trees(), "the bundled region has its trees")
	var region := RealRegion.get_region(PACK)
	check(region.credits.has(RealRegion.TREES_CREDIT) and RouteTv.credits_line(region.credits).contains("Meta"),
		"and the canopy map is credited")
	var r := AdventureRoute.new()
	r.plan_real(p, 7, 1000.0)
	var planted := 0
	var stray := 0
	var wet := 0
	var tall := 0
	var kinds := {}
	var chunks := 0
	for c in mini(r.chunk_count(), 150):
		var d := AdventureChunk.build(r, c)
		var i0: int = d["i0"]
		if not AdventureChunk._has_canopy(r, i0, d["i1"]):
			continue
		chunks += 1
		for kind in AdventureChunk.TREES:
			for xf: Transform3D in d["mm"].get(kind, []):
				planted += 1
				kinds[kind] = true
				var x: float = float(d["ax"]) + xf.origin.x
				var z: float = float(d["az"]) + xf.origin.z
				var v := p.terrain.trees_at(x, z)
				var most := float(v & 31) * AdventureChunk.CANOPY_HEIGHT_STEP if v > 0 else 0.0
				stray += int(most == 0.0)
				wet += int(AdventureChunk._in_water(r, x, z))
				var high := xf.basis.y.length() * float(AdventureChunk.TREE_SIZE[kind][0])
				tall += int(most > 0.0 and (high < 2.9 or high > most + 0.1))
	check(chunks > 10 and planted > chunks * 20, "trees planted from the canopy map in %d chunks (%d of them)" % [chunks, planted])
	check(stray == 0 and wet == 0 and tall == 0,
		"each where the map has trees (%d not), none in the water (%d), as tall as the map says (%d not)" % [stray, wet, tall])
	check(kinds.has(r.look["needle"]) and (kinds.has(r.look["broad"]) or kinds.has("tree") or kinds.has("autumn_tree")),
		"conifers and broadleaves both, the place's kinds (%s)" % [kinds.keys()])
	# Without the canopy map, the trees are scattered by the land cover as before.
	var cells: Array = p.terrain._tree_cells
	p.terrain._tree_cells = []
	var d0 := AdventureChunk.build(r, 3)
	p.terrain._tree_cells = cells
	var n0 := 0
	for kind in AdventureChunk.TREES:
		n0 += (d0["mm"].get(kind, []) as Array).size()
	check(n0 > 0, "and without it the land cover still scatters them (%d in chunk 3)" % n0)


## Every chunk of the whole island road is within its budget: buildings' vertices and scattered things.
func test_budget() -> void:
	var r := AdventureRoute.new()
	r.plan_real(Rides.tour_pack(PACK), 7, 1000.0)
	var worst_v := 0
	var worst_i := 0
	var worst_ms := 0.0
	var where := 0
	for c in r.chunk_count():
		var d := AdventureChunk.build(r, c)
		var verts: int = d["buildings"]["v"].size()
		var inst := 0
		for kind in d["mm"]:
			inst += (d["mm"][kind] as Array).size()
		if verts > worst_v:
			worst_v = verts
			where = c
		worst_i = maxi(worst_i, inst)
		worst_ms = maxf(worst_ms, float(d["ms"]))
	check(worst_v <= BUDGET_BUILDING_VERTS and worst_i <= BUDGET_INSTANCES,
		"all %d chunks within budget: buildings %d vertices at most (chunk %d, of %d), %d scattered things (of %d); slowest to lay out %.0f ms"
		% [r.chunk_count(), worst_v, where, BUDGET_BUILDING_VERTS, worst_i, BUDGET_INSTANCES, worst_ms])


## The map's own places as the stops, the real road's junctions and its speed limits.
func test_stops() -> void:
	var p := Rides.tour_pack(PACK)
	var a := AdventureRoute.new()
	a.plan_real(p, 7, 23.0)
	var fuel := a.sites_of("fuel")
	check(not fuel.is_empty(), "a ride has fuel (%d stations)" % fuel.size())
	# A real filling station at the first station's place (where one fits): a stop there, and the only one.
	var at := float(fuel[0]["s"])
	var saved := p.pois
	p.pois = [{"kind": "fuel", "name": "Test Garage", "x": 0.0, "z": 0.0, "k": int(round(at / AdventureRoute.STEP)), "lat": -22.0, "conf": 0.9},
		{"kind": "cafe", "name": "Far Cafe", "x": 0.0, "z": 0.0, "k": 5, "lat": 30.0, "conf": 0.9}]
	var b := AdventureRoute.new()
	b.plan_real(p, 7, 23.0)
	p.pois = saved
	var taken := b.sites_of("fuel").filter(func(st): return st.has("real"))
	check(taken.size() == 1 and str(taken[0]["name"]) == "Test Garage" and absf(float(taken[0]["s"]) - at) < 1.0 and int(taken[0]["side"]) == -1,
		"the map's filling station is a stop, with its name and side (%s)" % str(taken.map(func(st): return [st["name"], st["s"], st["side"]])))
	check(b.sites_of("cafe").all(func(st): return str(st["name"]) != "Far Cafe"), "a real place right by the start is left alone")
	check(b.sites_of("fuel").size() == 1, "and on a ride that short no made-up filling station beside it (%d)" % b.sites_of("fuel").size())
	var c := AdventureRoute.new()
	c.plan_real(p, 7, 23.0)
	check(c.sites.size() == a.sites.size() and c.px == a.px, "with the real places put back it plans as before")


func test_junctions() -> void:
	var p := Rides.tour_pack(PACK)
	check(p.junctions.size() >= 5, "the pack has the road's junctions (%d)" % p.junctions.size())
	var r := AdventureRoute.new()
	r.plan_real(p, 7, 23.0)
	var js := r.sites_of(AdventureJunctions.KIND)
	check(js.size() >= 3, "the ride has them as junction sites (%d of %d in the pack)" % [js.size(), p.junctions.size()])
	var bad := 0
	var kinds := {}
	for st: Dictionary in js:
		kinds[str(st["type"])] = true
		var m := int(st["i"]) % AdventureRoute.CHUNK_KNOTS
		if m < 5 or m > 26 or (st["arms"] as Array).is_empty() or not st.has("arm_geo"):
			bad += 1
		for other: Dictionary in r.sites:
			if other != st and absf(float(other["s"]) - float(st["s"])) < 100.0:
				bad += 1
		for arm: Dictionary in st["arms"]:
			if int(arm["side"]) == 0 or float(arm["w"]) < 3.0 or float(arm["len"]) < 40.0:
				bad += 1
	check(bad == 0, "each well inside its chunk, clear of other sites, with its arms laid out (%s)" % str(kinds.keys()))
	if not js.is_empty():
		var st: Dictionary = js[0]
		var d := AdventureChunk.build(r, int(st["i"]) / AdventureRoute.CHUNK_KNOTS)
		check(not (d["arms"] as Dictionary).is_empty() and (d["paint"]["v"] as PackedVector3Array).size() > 0,
			"and its side roads and paint are built with the chunk")
	var same := AdventureRoute.new()
	same.plan_real(p, 7, 23.0)
	check(same.sites_of(AdventureJunctions.KIND).map(func(st): return [st["s"], st["type"]]) == js.map(func(st): return [st["s"], st["type"]]),
		"the same every time")
	# A real road bends through a roundabout: where it does, it's no roundabout.
	var rounds := js.filter(func(st): return st["type"] == "roundabout")
	for st: Dictionary in rounds:
		var i: int = st["i"]
		check(absf(wrapf(r.hd[mini(i + 15, r.hd.size() - 1)] - r.hd[maxi(i - 15, 0)], -PI, PI)) <= deg_to_rad(5.0) + 0.001,
			"a roundabout is only where the road runs straight through it")


func test_limits() -> void:
	var p := Rides.tour_pack(PACK)
	var r := AdventureRoute.new()
	r.plan_real(p, 7, 23.0)
	var seen := {}
	var ok := true
	for s in range(0, int(r.length), 128):
		var kmh := p.limit_at(float(s))
		seen[int(kmh)] = true
		ok = ok and kmh >= 20.0 and kmh <= 120.0
	check(ok and seen.size() >= 2, "the real road has its limits (%s km/h along it)" % str(seen.keys()))
	check(p.region == "jp", "the limits are the country's (%s)" % p.region)
	var signs := r.sites_of("limit")
	var wrong := 0
	for st: Dictionary in signs:
		if absf(float(st["kmh"]) - r.limit_kmh_at(float(st["s"]) + 8.0)) > 0.5:
			wrong += 1
	check(signs.size() >= 2 and wrong == 0, "a speed-limit sign at the start and at each change (%d signs, %d wrong)" % [signs.size(), wrong])
	var kmh_sign := AdventureProps.limit_sign(60.0, false, Transform3D())
	var mph_sign := AdventureProps.limit_sign(96.0, true, Transform3D())
	var labels := kmh_sign.find_children("*", "Label3D", true, false)
	var mph_labels := mph_sign.find_children("*", "Label3D", true, false)
	check(labels.size() == 1 and (labels[0] as Label3D).text == "60" and (mph_labels[0] as Label3D).text == "60",
		"the sign says the limit, in mph on a UK road (96 km/h is 60)")
	var small_sign := AdventureProps.limit_sign(48.0, true, Transform3D())
	check((small_sign.find_children("*", "Label3D", true, false)[0] as Label3D).text == "30", "and 48 km/h is 30")
	kmh_sign.free()
	mph_sign.free()
	small_sign.free()


## The long tour round the Dales: its chunks all have the road's names and limits.
func test_epic() -> void:
	var p := Rides.tour_pack(EPIC)
	check(p != null and p.max_km() > 60.0, "the tour of the Dales is %.0f km" % p.max_km())
	var r := AdventureRoute.new()
	r.plan_real(p, 5, p.max_km())
	check(r.chunk_name.size() == r.chunk_count() and r.chunk_limit.size() == r.chunk_count(), "the road's names and limits cover every chunk")


func test_plan() -> void:
	var p := Rides.tour_pack(PACK)
	var a := AdventureRoute.new()
	a.plan_real(p, 7, 10.0)
	var b := AdventureRoute.new()
	b.plan_real(p, 7, 10.0)
	check(a.px == b.px and a.ph == b.ph and a.width == b.width and a.chunk_surface == b.chunk_surface and a.sites.size() == b.sites.size(),
		"the same real road plans the very same ride (%d knots)" % a.knot_count())
	check(absf(a.length - 10000.0) < 0.1 and a.total > a.length, "its length is the km asked for (%.0f m) and a run-out" % a.length)
	check(a.real == p and a.sea == p.sea and a.theme == "coastal", "the island's sea and look")
	var gmax := 0.0
	var step_worst := 0.0
	var hd_jump := 0.0
	for i in range(1, a.knot_count()):
		gmax = maxf(gmax, absf(a.ph[i] - a.ph[i - 1]) / AdventureRoute.STEP)
		step_worst = maxf(step_worst, absf(Vector2(a.px[i] - a.px[i - 1], a.pz[i] - a.pz[i - 1]).length() - AdventureRoute.STEP))
		hd_jump = maxf(hd_jump, absf(a.hd[i] - a.hd[i - 1]))
	check(gmax <= RoutePlanner.MAX_GRADE + 0.001, "grades stay under the planner's limit (steepest %.1f%%)" % (gmax * 100.0))
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
	# Woods where the cover says forest, few where it doesn't.
	var woods := {}
	for ch in range(5, big.chunk_count() - 5):
		var forest := 0
		var open := 0
		for i in range(ch * AdventureRoute.CHUNK_KNOTS, (ch + 1) * AdventureRoute.CHUNK_KNOTS, 4):
			for side: float in [-1.0, 1.0]:
				var cov := big.cover_at(big.px[i] + cos(big.hd[i]) * 40.0 * side, big.pz[i] + sin(big.hd[i]) * 40.0 * side)
				forest += int(cov == "forest")
				open += int(cov == "crop" or cov == "urban" or cov == "grass")
		if forest == 16 and not woods.has("forest"):
			woods["forest"] = ch
		if forest <= 4 and open >= 8 and not woods.has("open"):
			woods["open"] = ch
	if woods.has("forest") and woods.has("open"):
		var fc := AdventureChunk.build(big, int(woods["forest"]))
		var oc := AdventureChunk.build(big, int(woods["open"]))
		var ft := 0
		var ot := 0
		for kind in AdventureChunk.TREES:   # (whichever the place's kit has)
			ft += (fc["mm"].get(kind, []) as Array).size()
			ot += (oc["mm"].get(kind, []) as Array).size()
		print("    woods: ", ft, " trees in forest chunk ", woods["forest"], ", ", ot, " in open chunk ", woods["open"])
		check(ft > 150 and ft > ot * 3, "a chunk of forest has woods (%d trees), open country few (%d)" % [ft, ot])
	var busiest := 0
	var most := 0
	for ch in p.buildings:
		if int(ch) < big.chunk_count() and (p.buildings_in(int(ch)) as Array).size() > most:
			most = (p.buildings_in(int(ch)) as Array).size()
			busiest = int(ch)
	var town := AdventureChunk.build(big, busiest)
	check((town["buildings"]["v"] as PackedVector3Array).size() > 1500, "a chunk in a village has its buildings (%d vertices)" % town["buildings"]["v"].size())
	var last := AdventureChunk.build(a, a.chunk_count() - 1)
	check(not last["road"].is_empty(), "the last chunk builds too")


## Ridden: the real road streams in chunk by chunk, all the way along (dashing the length at 100 m a frame).
func test_ride() -> void:
	var spot := {}
	var w := AdventureWorld.new()
	w.setup(Rides.tour_pack(PACK), 11, 23.0)
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
		w.follow(spot["p"])   # (the trip does, every frame: the skyline and the land blocks follow the rider)
		var t0 := Time.get_ticks_usec()
		await t.get_tree().process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		while Time.get_ticks_usec() - t0 < 16000:
			await t.get_tree().process_frame
		# On at the pace the road is built (a slow machine builds slowly): the next stretch has to be there.
		var held := Time.get_ticks_msec()
		while not w.chunks.has(AdventureRoute.chunk_of(minf(s + 300.0, w.route.total - 1.0))) and Time.get_ticks_msec() - held < 4000:
			await t.get_tree().process_frame
	var wait_end := Time.get_ticks_msec() + 20000
	while not w.wanted_chunks().all(func(c): return w.chunks.has(c)) and Time.get_ticks_msec() < wait_end:
		await t.get_tree().process_frame
	check(w.chunks.has(AdventureRoute.chunk_of(s)) and int(w.stats["freed"]) > 8,
		"streamed from the start to the end of the island road (%d chunks freed behind, worst frame %.0f ms)" % [int(w.stats["freed"]), worst])
	w.queue_free()
	await t.get_tree().process_frame


## The crew's side: the planned road in the state, a game that plans another, and what the data says of the Dales tour.
func test_magazine() -> void:
	var plan := AdventurePlans.tour(PACK)
	var pack := AdventurePlans.pack_for(plan)
	var ep := Rides.tour_pack(EPIC)
	var names: Array = AdventurePlans.tour(EPIC)["names"]
	var text := ep.summary_text()
	check(text.contains("km from %s to %s" % [names[0], names[-1]]) and text.contains("climbing") and text.contains("filling stations") and text.contains("inns"),
		"the Dales tour's summary says what the data does (%s)" % text)
	var real_path := Progress.path
	Progress.path = "user://test_real_progress.json"
	Shed.start_new("Tester", 5)
	Shed.request({"a": "adventure_start", "plan": plan, "seed": 4104, "title": "Shodoshima"})
	check(Adventure.active() and str(Shed.adventure["real"]) == pack.id and str(Shed.adventure["real_hash"]) == pack.hash,
		"starting it puts the road and its hash in the crew's adventure")
	check(AdventureTrip.real_mismatch(Shed.adventure) == "", "a game that plans the same road joins")
	var odd: Dictionary = Shed.adventure.duplicate(true)
	odd["real_hash"] = "0000"
	check(AdventureTrip.real_mismatch(odd).contains("different road"), "one that plans another is told so")
	odd["plan"]["region"] = "nowhere"
	check(AdventureTrip.real_mismatch(odd) != "", "and one without that part of the world too (%s)" % AdventureTrip.real_mismatch(odd))
	Shed.request({"a": "adventure_end"})
	var bad_plan: Dictionary = plan.duplicate(true)
	bad_plan["region"] = "nowhere"
	check(Adventure.check(Shed.me(), {"a": "adventure_start", "plan": bad_plan, "seed": 1}) != "", "the host can't start a journey the game can't plan")
	check(Adventure.check(Shed.me(), {"a": "adventure_start", "seed": 1, "km": 10.0}) != "", "nor a ride with no journey")
	Shed.stop()
	Progress.path = real_path
	DirAccess.remove_absolute("user://test_real_progress.json")


## The land beyond the road's own chunks (RealLand): blocks round the rider in three levels, the near level always beside
## the road, heights that meet the chunks' land at their seam, and the ridge eased down under them.
func test_real_land() -> void:
	var w := AdventureWorld.new()
	w.setup(Rides.tour_pack(PACK), 11, 23.0)
	var land := w.land
	check(land != null and w.route.real != null, "a ride's world has its land blocks")
	if land == null:
		w.free()
		return
	check(AdventureChunk.land_cols(w.route) == AdventureChunk.REAL_LAND_COLS and AdventureChunk.REAL_LAND_COLS < AdventureChunk.LAND_OUT.size(),
		"the chunks' land runs out to %d m, the blocks take over from there" % int(AdventureChunk.LAND_OUT[AdventureChunk.REAL_LAND_COLS - 1]))
	# A block by the road: near level, and its seam with the chunks' land (the same heights as the road's own land).
	var xz := w.route.xz_at(3000.0, 0.0)
	var key := Vector2i(floori(xz[0] / RealLand.BLOCK), floori(xz[1] / RealLand.BLOCK))
	check(land._near_road(key), "a block with the road in it counts as beside the road")
	var near = land._block_arrays(key, 0)
	var mid = land._block_arrays(key, 1)
	var far = land._block_arrays(key, 2)
	check(near != null and mid != null and far != null, "a block lays out at every level")
	if near == null or mid == null or far == null:
		w.free()
		return
	var nv: PackedVector3Array = near[Mesh.ARRAY_VERTEX]
	var mv: PackedVector3Array = mid[Mesh.ARRAY_VERTEX]
	var fv: PackedVector3Array = far[Mesh.ARRAY_VERTEX]
	check(nv.size() > 4000 and mv.size() < 500 and fv.size() < 200, "the near level is dense and the far levels light (%d, %d and %d vertices)" % [nv.size(), mv.size(), fv.size()])
	# Heights beyond the seam are the land's: the real heights, and the same wherever a level samples them.
	var worst := 0.0
	var checked := 0
	var n := RealLand.CELLS[0] + 1
	for j in range(0, n, 3):
		for i in range(0, n, 3):
			var x := key.x * RealLand.BLOCK + i * (RealLand.BLOCK / RealLand.CELLS[0])
			var z := key.y * RealLand.BLOCK + j * (RealLand.BLOCK / RealLand.CELLS[0])
			var hit := w.route.locate(x, z)
			if hit.is_empty() or float(hit["d"]) < 130.0 or float(hit["d"]) > 400.0:
				continue
			var want := w.route.land_height(int(hit["i"]), float(hit["lat"]), x, z)
			worst = maxf(worst, absf(nv[j * n + i].y - want))
			checked += 1
	check(checked > 30 and worst < 0.5, "away from the road its heights are the land's own, to %.2f m (%d points)" % [worst, checked])
	# Under the chunks' land the blocks lie hidden.
	var hidden := 0
	var under := 0
	for j in n:
		for i in n:
			var x := key.x * RealLand.BLOCK + i * (RealLand.BLOCK / RealLand.CELLS[0])
			var z := key.y * RealLand.BLOCK + j * (RealLand.BLOCK / RealLand.CELLS[0])
			var hit := w.route.locate(x, z)
			if not hit.is_empty() and float(hit["d"]) < 80.0:
				under += 1
				if nv[j * n + i].y < w.route.land_height(int(hit["i"]), float(hit["lat"]), x, z) - 1.0:
					hidden += 1
	check(under == 0 or hidden * 10 >= under * 9, "and within %d m of it they lie below it (%d of %d)" % [int(RealLand.BAND_NEAR), hidden, under])
	# Rivers and lakes (RealPack.WATER cover): a block beside the road with water in it draws it at the water's level
	# (RealTerrain.water_level), flat across, over a bed WATER_DEPTH down, and none of it on the road.
	var wkey := Vector2i(1 << 30, 0)
	var water = null
	var sp := RealLand.BLOCK / RealLand.CELLS[0]
	# (a cell of a lake or a river the cover has is square on the grid; the becks' ribbons, RealPack.streams, aren't)
	var square := func(v: PackedVector3Array, q: int) -> bool:
		return is_equal_approx(v[q + 1].x - v[q].x, sp) and is_equal_approx(v[q + 1].z, v[q].z) and is_equal_approx(v[q + 3].z - v[q].z, sp)
	for k in range(0, w.route.px.size(), 64):
		var bk := Vector2i(floori(w.route.px[k] / RealLand.BLOCK), floori(w.route.pz[k] / RealLand.BLOCK))
		var got = land._water_arrays(bk, 0)
		if got != null and range(0, (got[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 4).any(func(q): return square.call(got[Mesh.ARRAY_VERTEX], q)):
			water = got
			wkey = bk
			break
	check(water != null, "a block beside the road has water in it (%s)" % str(wkey))
	if water != null:
		var wv: PackedVector3Array = water[Mesh.ARRAY_VERTEX]
		var terr := w.route.real.terrain
		var by_water := 0
		var wet := 0
		var bed := 0
		var not_up := 0
		var on_road := 0
		var cells := 0
		for q in range(0, wv.size(), 4):
			if not square.call(wv, q):
				continue
			cells += 1
			var cx := wkey.x * RealLand.BLOCK + wv[q].x + sp * 0.5
			var cz := wkey.y * RealLand.BLOCK + wv[q].z + sp * 0.5
			# Within a cell of mapped water (or land let down under it beside it: RealTerrain.water_shore), and no higher
			# than the highest water round it.
			var top := -INF
			for dz: float in [-sp, 0.0, sp]:
				for dx: float in [-sp, 0.0, sp]:
					var h := terr.height(cx + dx, cz + dz)
					if terr.cover(cx + dx, cz + dz) == RealPack.WATER:
						top = maxf(top, h)
					elif terr.water_shore(cx + dx, cz + dz, h) < terr.water_level(cx + dx, cz + dz):
						top = maxf(top, terr.water_level(cx + dx, cz + dz))
			if top > -INF:
				by_water += 1
				if wv[q].y <= top + 0.05 and wv[q + 2].y <= top + 0.05:
					not_up += 1
			if terr.cover(cx, cz) == RealPack.WATER:
				wet += 1
				var lv := terr.water_at(cx, cz)
				var gr := land.by_water(cx, cz, w.route.ground_at(cx, cz))
				# (out in it WATER_DEPTH under the level, at its edge no higher than half-way up to the map's height)
				if not is_nan(lv.x) and is_equal_approx(gr, terr.water_bed(cx, cz, terr.height(cx, cz), AdventureRoute.WATER_DEPTH)) \
						and (gr <= lv.x - AdventureRoute.WATER_DEPTH + 0.01 or lv.z > 0.0):
					bed += 1
			var hit := w.route.locate(cx, cz)
			if not hit.is_empty() and float(hit["d"]) < w.route.width[int(hit["i"])] * 0.5 + 2.0 and not RealLand.near_deck(w.route, int(hit["i"])):
				on_road += 1
		check(cells > 0 and by_water == cells and not_up == cells and wet * 2 > cells and bed == wet and on_road == 0,
			"its %d cells of water are on or beside the water (%d, %d on it), never up a bank (%d), over a bed below it (%d), none on the road (%d)" % [cells, by_water, wet, not_up, bed, on_road])
		# Smooth, and never above the water's own heights: at the lattice's points on the water the level is at or under
		# the map's heights, and lies close to the mean of its neighbours (flat across, an even fall along), where the map's
		# heights wander a metre or two from one point to the next.
		var over := 0
		var points := 0
		var rough_raw := 0
		var rough := 0
		var st := RealTerrain.WATER_STEP
		for j in 64:
			for i in 64:
				var x := wkey.x * RealLand.BLOCK + i * st
				var z := wkey.y * RealLand.BLOCK + j * st
				if terr.cover(x, z) != RealPack.WATER or is_nan(terr.height(x, z)):
					continue
				points += 1
				if terr.water_level(x, z) > terr.height(x, z) + 0.01:
					over += 1
				var nb := [Vector2(x - st, z), Vector2(x + st, z), Vector2(x, z - st), Vector2(x, z + st)]
				if nb.all(func(v): return terr.cover(v.x, v.y) == RealPack.WATER):
					var lv := 0.0
					var hv := 0.0
					for v: Vector2 in nb:
						lv += terr.water_level(v.x, v.y) * 0.25
						hv += terr.height(v.x, v.y) * 0.25
					if absf(terr.water_level(x, z) - lv) > 0.15:
						rough += 1
					if absf(terr.height(x, z) - hv) > 0.15:
						rough_raw += 1
		check(points > 0 and over == 0, "the water's level is at or under the map's heights of it (%d of %d points over)" % [over, points])
		# (the tiles' cover, read a grid at a time, is cover()'s)
		var grid := terr._cover_grid(wkey.x * RealLand.BLOCK, wkey.y * RealLand.BLOCK, st, 64)
		var same := 0
		for j in 64:
			for i in 64:
				if grid[j * 64 + i] == terr.cover(wkey.x * RealLand.BLOCK + i * st, wkey.y * RealLand.BLOCK + j * st):
					same += 1
		check(same == 64 * 64, "its cover read a grid at a time is the same as a point at a time (%d of %d)" % [same, 64 * 64])
		check(rough_raw > 0 and rough * 4 <= rough_raw, "and it's smooth where the map's heights aren't (%d points off their neighbours by 15 cm, the map's %d)" % [rough, rough_raw])
		var mi := land._make_mesh(wkey, land._block_arrays(wkey, 0), water)
		check(mi.mesh.get_surface_count() == 2 and mi.mesh.surface_get_material(1) == land._water_material, "and the block's mesh has it as water")
		mi.free()
	check(land._water_arrays(wkey, RealLand.WATER_LODS) == null, "the far level draws no water")
	# Levels by distance, with a margin for the block on the line.
	check(RealLand._lod_for(100.0, -1) == 0 and RealLand._lod_for(1000.0, -1) == 1 and RealLand._lod_for(3000.0, -1) == 2 and RealLand._lod_for(9000.0, -1) == -1,
		"blocks are near, middle or far by their distance, and none past the far range")
	check(RealLand._lod_for(RealLand.RANGES[0] + 20.0, 0) == 0 and RealLand._lod_for(RealLand.RANGES[0] + 20.0, -1) == 1, "a block keeps its level a little past the line")
	# They stream in as the rider comes.
	var spot := w.transform_at(3000.0).origin + w.origin
	t.add_child(w)
	land.follow(spot.x, spot.z)
	var end := Time.get_ticks_msec() + 90000
	while land.busy() and Time.get_ticks_msec() < end:
		await t.get_tree().process_frame
	var counts := land.level_counts()
	check(int(counts.get(0, 0)) >= 3 and int(counts.get(1, 0)) >= 3 and int(counts.get(2, 0)) >= 20, "round the rider they come in at every level (%s)" % str(counts))
	# The ridge lies under them.
	check(w.ridges != null and RealRidges.LAND_UNDER > 5.0 and RealRidges.LAND_REACH >= RealLand.RANGES[2], "the skyline is eased down under them, out to their far range")
	land.reset()
	check(land.block_count() == 0 and land._at.x == INF, "a new road clears them to be laid out again")
	w.queue_free()
	await t.get_tree().process_frame


## What the game ships: every file of the game's data (the regions' tiles included) must be in the exported
## build, which only takes files that are resources or that its include filters name. (A build once went out with the
## tiles missing: the land came out flat at sea level, and rides across it were a road on a blue plane.)
func test_export_includes_data() -> void:
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var filters: Array[String] = []
	for line in cfg.split("\n"):
		if line.begins_with("include_filter="):
			for f in line.trim_prefix("include_filter=").trim_prefix("\"").trim_suffix("\"").split(","):
				filters.append(f.strip_edges())
			break
	check(not filters.is_empty(), "the export presets have include filters (%s)" % ", ".join(filters))
	var missing := {}
	var files := 0
	var stack: Array[String] = ["data"]
	while not stack.is_empty():
		var rel: String = stack.pop_back()
		var d := DirAccess.open("res://" + rel)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append(rel + "/" + sub)
		for fn in d.get_files():
			if fn.ends_with(".import") or fn.ends_with(".uid"):
				continue
			files += 1
			var path := rel + "/" + fn
			if not filters.any(func(f): return path.match(f)):
				missing[fn.get_extension()] = path
	check(files > 100 and missing.is_empty(), "every one of the %d data files is in the export (not: %s)" % [files, str(missing)])
