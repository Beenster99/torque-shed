extends RefCounted
## Real roads' checks (a baked pack read by RealPack and RealTerrain, planned by AdventureRoute.plan_real
## and built into chunks), run from tests/run_tests.gd: its _test_real_* functions hand over to these.

const PACK := "shodoshima"
## What a chunk may hold (see test_budget): the buildings' vertices, and trees, bushes, rocks and the like.
const BUDGET_BUILDING_VERTS := 20000
const BUDGET_INSTANCES := 800

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
	check(off < 2.5, "the road sits on the land it was baked from (most %.1f m off)" % off)


## The land's three levels: the fine one by the road, the coarse one out over the hillsides, the ridge level to the
## skyline; joined without steps, and the whole pack small.
func test_levels() -> void:
	var p := RealPack.get_pack(PACK)
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
	check(is_nan(t.height_at_level(0, p.x[k] + rx * 1200.0, p.z[k] + rz * 1200.0)) and not is_nan(t.height_at_level(1, p.x[k] + rx * 1200.0, p.z[k] + rz * 1200.0)),
		"1.2 km out it is the coarse level's (the fine ends near 300 m)")
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
	var dir := DirAccess.open(RealPack.DIR.path_join(PACK))
	for sub in ["tiles", "coarse", "ridge"]:
		var d := DirAccess.open(RealPack.DIR.path_join(PACK).path_join(sub))
		for f in d.get_files():
			total += FileAccess.get_file_as_bytes(RealPack.DIR.path_join(PACK).path_join(sub).path_join(f)).size()
	check(dir != null and total < 3000000, "the land is %.1f MB for %.0f km of road" % [total / 1.0e6, p.max_km()])


func test_ridges() -> void:
	var w := AdventureWorld.new()
	w.setup(11, 23.0, "coastal", "lighthouse", PACK)
	var p: RealPack = w.route.real
	check(w.ridges != null and w.ridges.block_count() > 4, "the world draws the real skyline (%d blocks of hills)" % w.ridges.block_count())
	# Pushed down by the road so the land hides it, the real height from a kilometre out.
	var k := 2400
	var fine := p.terrain.height(p.x[k], p.z[k])
	var ridge := _ridge_at(p.terrain, p.x[k], p.z[k])
	check(ridge < fine - 30.0, "under the road the ridge level lies %.0f m below the land (%.0f vs %.0f)" % [fine - ridge, ridge, fine])
	var hd := atan2(p.x[k + 1] - p.x[k], -(p.z[k + 1] - p.z[k]))
	var far_c := p.terrain.height_at_level(1, p.x[k] + cos(hd) * 1500.0, p.z[k] + sin(hd) * 1500.0)
	var far_r := p.terrain.height_at_level(2, p.x[k] + cos(hd) * 1500.0, p.z[k] + sin(hd) * 1500.0)
	check(absf(far_c - far_r) < 40.0, "and 1.5 km out it is the real ground's, as the coarse level has it (%.0f vs %.0f)" % [far_r, far_c])
	# Moves with the origin.
	var block: MeshInstance3D = w.ridges.get_children()[0]
	var before := block.position
	w.origin += Vector3(1024.0, 0.0, 0.0)
	w.ridges.place()
	check(absf((block.position - before).x + 1024.0) < 0.01, "and moves with the world's origin")
	w.free()


func _ridge_at(t: RealTerrain, x: float, z: float) -> float:
	var sp := t.ridge_spacing()
	var n := t.ridge_cells()
	var ix := int(floor(x / sp))
	var iz := int(floor(z / sp))
	var tile := t.ridge_tile(Vector2i(floori(float(ix) / n), floori(float(iz) / n)))
	return NAN if tile.is_empty() else tile[posmod(iz, n) * n + posmod(ix, n)]


func test_land() -> void:
	var p := RealPack.get_pack(PACK)
	check(p.building_count > 200 and not p.buildings_in(136).is_empty(), "the pack has its buildings (%d), filed by the chunk beside them" % p.building_count)
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


## Every chunk of the whole island road is within its budget: buildings' vertices and scattered things.
func test_budget() -> void:
	var r := AdventureRoute.new()
	r.plan_real(RealPack.get_pack(PACK), 7, 1000.0)
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


## Real places the stops take over, the real road's junctions and its speed limits.
func test_stops() -> void:
	var p := RealPack.get_pack(PACK)
	var a := AdventureRoute.new()
	a.plan_real(p, 7, 23.0)
	var fuel := a.sites_of("fuel")
	check(not fuel.is_empty(), "a ride has fuel (%d stations)" % fuel.size())
	# A real filling station at the first station's place (the planner's own pick, so it fits): taken over.
	var at := float(fuel[0]["s"])
	var saved := p.pois
	p.pois = [{"kind": "fuel", "name": "Test Garage", "x": 0.0, "z": 0.0, "k": int(round(at / AdventureRoute.STEP)), "lat": -22.0, "conf": 0.9},
		{"kind": "cafe", "name": "Far Cafe", "x": 0.0, "z": 0.0, "k": 5, "lat": 30.0, "conf": 0.9}]
	var b := AdventureRoute.new()
	b.plan_real(p, 7, 23.0)
	p.pois = saved
	var taken := b.sites_of("fuel").filter(func(st): return st.has("real"))
	check(taken.size() == 1 and str(taken[0]["name"]) == "Test Garage" and absf(float(taken[0]["s"]) - at) < 1.0 and int(taken[0]["side"]) == -1,
		"a real filling station takes over a made-up one, with its name and side (%s)" % str(taken.map(func(st): return [st["name"], st["s"], st["side"]])))
	check(b.sites_of("cafe").all(func(st): return str(st["name"]) != "Far Cafe"), "a real place too far from any stop is left alone")
	check(a.sites_of("fuel").size() == b.sites_of("fuel").size(), "and taking over doesn't change how many stops there are")
	var c := AdventureRoute.new()
	c.plan_real(p, 7, 23.0)
	check(c.sites.size() == a.sites.size() and c.px == a.px, "with the real places put back it plans as before")


func test_junctions() -> void:
	var p := RealPack.get_pack(PACK)
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
	var p := RealPack.get_pack(PACK)
	var r := AdventureRoute.new()
	r.plan_real(p, 7, 23.0)
	var seen := {}
	var ok := true
	for s in range(0, int(r.length), 128):
		var kmh := p.limit_at(float(s))
		seen[int(kmh)] = true
		ok = ok and kmh >= 20.0 and kmh <= 120.0 and absf(AdventurePolice.limit_at(r, float(s)) * 3.6 - kmh) < 0.01
	check(ok and seen.size() >= 2, "the police go by the real road's limits (%s km/h along it)" % str(seen.keys()))
	check(p.region == "jp", "the limits are the country's (%s)" % p.region)
	var made_up := AdventureRoute.new()
	made_up.plan(7, 20.0)
	check(is_equal_approx(AdventurePolice.limit_at(made_up, 1000.0), AdventurePolice.OPEN_LIMIT) or AdventurePolice.limit_at(made_up, 1000.0) == AdventurePolice.VILLAGE_LIMIT,
		"and a made-up road keeps its 60 and 30 mph")


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
		var ft := (fc["mm"].get("tree", []) as Array).size() + (fc["mm"].get("pine", []) as Array).size()
		var ot := (oc["mm"].get("tree", []) as Array).size() + (oc["mm"].get("pine", []) as Array).size()
		print("    woods: ", ft, " trees in forest chunk ", woods["forest"], ", ", ot, " in open chunk ", woods["open"])
		check(ft > 150 and ft > ot * 3, "a chunk of forest has woods (%d trees), open country few (%d)" % [ft, ot])
	var town := AdventureChunk.build(big, 136)
	check((town["buildings"]["v"] as PackedVector3Array).size() > 1500, "a chunk by a village has its buildings (%d vertices)" % town["buildings"]["v"].size())
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
