extends RefCounted
## Live heights (HeightTiles, RealTerrain with "heights": "live"): the ground read from Mapterhorn's map tiles in the
## game rather than baked into a region. Run from tests/run_tests.gd (its _test_live_* functions hand over to these).
## Nothing here touches the network: the tiles a ride round Shodoshima as far as Kusakabe uses are kept in
## tests/fixtures/heights, and Shodoshima's own baked heights (from the same source) are what they are checked against.

const Rides := preload("res://tests/rides.gd")
const FIXTURES := "res://tests/fixtures/heights"
const REGION := "shodoshima"
## The ride the fixtures cover: the first four pins of Shodoshima's tour (28 km, one fork).
const PINS := 4

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The tiles from the fixtures only, and no network.
func _offline(dirs: Array[String] = [FIXTURES]) -> void:
	HeightTiles.dirs = dirs
	HeightTiles.offline = true
	HeightTiles.reset()
	_cells_were = CellStore.offline
	CellStore.offline = true   # (the place profiles, for the sea: guessed, so the sea is as it always was)


var _cells_were := false


func _restore() -> void:
	HeightTiles.dirs = ["res://data/heights"]
	HeightTiles.offline = false
	HeightTiles.reset()
	CellStore.offline = _cells_were


## Shodoshima's terrain made live: the same region, its heights from the map tiles (its buildings levelled).
func _live_terrain(r: RealRegion) -> RealTerrain:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(RealRegion.dir_of(REGION).path_join("region.json")))
	meta["heights"] = "live"
	var live := RealTerrain.new(RealRegion.dir_of(REGION), meta)
	live.set_buildings(r.buildings)
	return live


## The ride planned over Shodoshima with live heights: {ok, error, pack, ...} (RoutePlanner.plan).
func _plan_live(r: RealRegion) -> Dictionary:
	var baked := r.terrain
	r.terrain = _live_terrain(r)
	var plan := AdventurePlans.tour(REGION, PINS)
	var res := RoutePlanner.plan(r, AdventurePlans._request(plan))
	r.terrain = baked
	return res


func test_tiles() -> void:
	check(HeightTiles.zoom_for(34.5, 4.0) == 14 and HeightTiles.zoom_for(34.5, 32.0) == 11 and HeightTiles.zoom_for(34.5, 128.0) == 9
		and HeightTiles.zoom_for(54.34, 4.0) == 14, "the zoom for each level: the smallest whose pixels are no coarser than its spacing")
	var ax := HeightTiles.mercator_x(134.185, 14)
	var ay := HeightTiles.mercator_y(34.485, 14)
	var bx := HeightTiles.mercator_x(-2.0, 11)
	var by := HeightTiles.mercator_y(54.3, 11)
	check(absf(ax - 14298.908444444) < 1e-6 and absf(ay - 6518.190371270) < 1e-6 and absf(bx - 1012.622222222) < 1e-6 and absf(by - 654.661115864) < 1e-6,
		"a place's tile and pixel are the baker's, to a millionth of a tile (%.6f, %.6f)" % [ax, ay])
	var m := RealTerrain.metres_per_degree(34.5)
	check(absf(m.x - 110931.425) < 0.01 and absf(m.y - 91839.949) < 0.01, "metres per degree as the baker has them")
	_offline()
	var tile := HeightTiles.tile(Vector3i(14, 14298, 6518))
	check(tile != null and tile.size == 512 and tile.rgb.size() == 512 * 512 * 3, "a tile off disk decodes: 512 px, its heights in the pixels")
	if tile != null:
		var lo := INF
		var hi := -INF
		for j in range(0, 512, 8):
			for i in range(0, 512, 8):
				lo = minf(lo, tile.at(i, j))
				hi = maxf(hi, tile.at(i, j))
		check(not tile.sea.is_empty() and lo < -2.0 and lo >= -HeightTiles.SEA_DEPTH - 0.01 and hi > 100.0,
			"over Tonosho's harbour the sea has a floor (down to %.1f m) and the hills behind are there (%.0f m)" % [lo, hi])
	check(HeightTiles.tile(Vector3i(14, 1, 1)) == null and not HeightTiles.has(Vector3i(14, 1, 1)), "and a tile that isn't on disk is missing, not fetched")
	check(HeightTiles.fetch([Vector3i(14, 1, 1)] as Array[Vector3i]) == 1, "offline, fetching it says it couldn't")
	# The tiles kept are capped: past `keep`, the ones fetched longest ago go; never one asked for this run.
	var was := [HeightTiles.disk, HeightTiles.keep, HeightTiles._used_now]
	HeightTiles.disk = "user://test_heights_kept"
	RegionStore._remove_tree(HeightTiles.disk)
	var keys: Array[Vector3i] = [Vector3i(14, 5, 1), Vector3i(14, 5, 2), Vector3i(14, 5, 3), Vector3i(14, 5, 4)]
	for k in keys:
		DirAccess.make_dir_recursive_absolute(HeightTiles.disk.path_join("14/5"))
		var f := FileAccess.open(HeightTiles.disk.path_join("14/5/%d.webp" % k.z), FileAccess.WRITE)
		f.store_string("tile")
		f.close()
		OS.delay_msec(1100)   # (a second apart: when each was fetched)
	HeightTiles.keep = 2
	HeightTiles._used_now = {keys[0]: true}
	var gone := HeightTiles.prune()
	var left := [1, 2, 3, 4].filter(func(z): return FileAccess.file_exists(HeightTiles.disk.path_join("14/5/%d.webp" % z)))
	check(gone == 2 and left == [1, 4], "past the cap the tiles fetched longest ago go, not one this run asked for (%s left)" % str(left))
	RegionStore._remove_tree(HeightTiles.disk)
	HeightTiles.disk = was[0]
	HeightTiles.keep = was[1]
	HeightTiles._used_now = was[2]
	_restore()


## The same road planned with live heights as with the baked ones, and the land beside it about the same: both come from
## Mapterhorn, one baked at 4 m with the baker's shaping, the other read from the tiles with the game's.
func test_heights() -> void:
	_offline()
	var r := RealRegion.get_region(REGION)
	var res := _plan_live(r)
	var baked := AdventurePlans.pack_for(AdventurePlans.tour(REGION, PINS))
	check(bool(res["ok"]), "a ride plans over live heights, from the fixtures (%s)" % str(res.get("error", "")))
	if not bool(res["ok"]):
		_restore()
		return
	var live: RealPack = res["pack"]
	check(live.terrain.live and live.x.size() == baked.x.size() and live.forks.size() == baked.forks.size(),
		"the same road (%d knots, %d fork) on the live land" % [live.x.size(), live.forks.size()])
	var worst := 0.0
	var total := 0.0
	for i in live.e.size():
		var d := absf(live.e[i] - baked.e[i])
		worst = maxf(worst, d)
		total += d
	var mean := total / maxf(live.e.size(), 1.0)
	check(mean < 1.0 and worst < 6.0, "its heights are the baked road's: %.2f m apart on average, %.1f at most" % [mean, worst])
	# The land beside it, out to a kilometre.
	var diffs := []
	for k in range(200, live.x.size() - 200, 300):
		var hh := atan2(live.x[k + 1] - live.x[k], -(live.z[k + 1] - live.z[k]))
		for out: float in [-800.0, -300.0, -60.0, 60.0, 300.0, 800.0]:
			var x := live.x[k] + cos(hh) * out
			var z := live.z[k] + sin(hh) * out
			var a := live.terrain.height(x, z)
			var b := baked.terrain.height(x, z)
			if not is_nan(a) and not is_nan(b) and b > 2.0:
				diffs.append(absf(a - b))
	diffs.sort()
	var mid: float = diffs[diffs.size() / 2] if not diffs.is_empty() else INF
	var p90: float = diffs[diffs.size() * 9 / 10] if not diffs.is_empty() else INF
	check(diffs.size() > 100 and mid < 1.0 and p90 < 4.0, "and so is the land beside it (%.2f m apart at the middle of %d points, %.1f m at the 90th)" % [mid, diffs.size(), p90])
	# The fork's other way: its tiles were taken in too, so it's on the fine land.
	if not live.forks.is_empty():
		var w: Dictionary = live.forks[0]["way"]
		var k := (w["x"] as Array).size() / 2
		check(live.terrain.has_tile_at(float(w["x"][k]), float(w["z"][k])), "the fork's other way is on the finest land too")
	_restore()


## The live ground at route-frame (x, z) before any building levels it (where they stand, the pads step it).
func _bare(tr: RealTerrain, x: float, z: float) -> float:
	return tr._live_level(0, tr.lat0 - z / tr._m.x, tr.lon0 + x / tr._m.y, true)


## Where the finest level's tiles end, the land eases into the middle level's: no step at the edge.
func test_edges() -> void:
	_offline()
	var r := RealRegion.get_region(REGION)
	var res := _plan_live(r)
	if not bool(res["ok"]):
		check(false, "the ride plans for the edge check")
		_restore()
		return
	var live: RealPack = res["pack"]
	var tr := live.terrain
	# Walk out from the road till the finest level's tiles end.
	var k := live.x.size() / 2
	var hh := atan2(live.x[k + 1] - live.x[k], -(live.z[k + 1] - live.z[k]))
	var out := 0.0
	while out < 6000.0 and tr.has_tile_at(live.x[k] + cos(hh) * out, live.z[k] + sin(hh) * out):
		out += 4.0
	var ex := live.x[k] + cos(hh) * out
	var ez := live.z[k] + sin(hh) * out
	var at_edge := _bare(tr, ex - cos(hh) * 1.0, ez - sin(hh) * 1.0)
	var mid_there := tr.height_at_level(1, ex - cos(hh) * 1.0, ez - sin(hh) * 1.0)
	check(out > 1000.0 and out < 6000.0, "the finest land reaches %.0f m out from the road" % out)
	check(absf(at_edge - mid_there) < 0.5, "at its edge it is the middle level's height (%.2f against %.2f)" % [at_edge, mid_there])
	# Across the band where it eases, each 4 m step of the land is no bigger than the steeper of the two levels' own steps
	# there (the hillside's): the easing adds none of its own.
	var worst := -INF
	var prev := Vector3(NAN, NAN, NAN)   # (eased, fine alone, middle alone)
	var d := out - 300.0
	while d < out + 200.0:
		var x := live.x[k] + cos(hh) * d
		var z := live.z[k] + sin(hh) * d
		var now := Vector3(_bare(tr, x, z), tr._live_level(0, tr.lat0 - z / tr._m.x, tr.lon0 + x / tr._m.y, false), tr.height_at_level(1, x, z))
		if not is_nan(prev.x):
			var own := absf(now.z - prev.z) if is_nan(now.y) or is_nan(prev.y) else maxf(absf(now.y - prev.y), absf(now.z - prev.z))
			worst = maxf(worst, absf(now.x - prev.x) - own)
		prev = now
		d += 4.0
	check(worst < 0.3, "and walking across it in 4 m steps, no step bigger than the hillside's own (%.2f m over it at most)" % maxf(worst, 0.0))
	_restore()


## The ground under a building is level (the baker levelled it; live heights level it as they are read).
func test_pads() -> void:
	_offline()
	var r := RealRegion.get_region(REGION)
	var res := _plan_live(r)
	if not bool(res["ok"]):
		check(false, "the ride plans for the building check")
		_restore()
		return
	var live: RealPack = res["pack"]
	var tr := live.terrain
	var levelled := 0
	var tried := 0
	var worst := 0.0
	var all: Array = []
	for c in live.buildings:
		all.append_array(live.buildings[c])
	for b: Array in all:
		if tried >= 40:
			break
		# (one whose pad no other building's reaches: where two meet, the second levels over the first, as the baker does)
		var reach := Vector2(float(b[2]), float(b[3])).length() * 0.5 + RealTerrain.PAD_MARGIN + RealTerrain.PAD_FEATHER
		var alone := true
		for o: Array in all:
			var oreach := Vector2(float(o[2]), float(o[3])).length() * 0.5 + RealTerrain.PAD_MARGIN + RealTerrain.PAD_FEATHER
			if o != b and Vector2(float(o[0]) - float(b[0]), float(o[1]) - float(b[1])).length() < reach + oreach:
				alone = false
				break
		if not alone:
			continue
		var cs := cos(float(b[4]))
		var sn := sin(float(b[4]))
		var hs := []
		for corner: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
			var lx := corner.x * float(b[2])
			var lz := corner.y * float(b[3])
			hs.append(tr.height(float(b[0]) + lx * cs + lz * sn, float(b[1]) - lx * sn + lz * cs))
		var spread: float = hs.max() - hs.min()
		tried += 1
		worst = maxf(worst, spread)
		if spread < 0.01:
			levelled += 1
	check(tried >= 20 and levelled == tried, "the ground is level under every building standing on its own (%d of %d, %.3f m off at worst)" % [levelled, tried, worst])
	_restore()


## Every machine that plans the road gets the same heights, and the plan's hash says so; with no tiles to be had the
## plan says why.
func test_same_everywhere() -> void:
	_offline()
	var r := RealRegion.get_region(REGION)
	var a := _plan_live(r)
	HeightTiles.reset()   # (another machine: nothing decoded yet)
	var b := _plan_live(r)
	var same := bool(a["ok"]) and bool(b["ok"]) and (a["pack"] as RealPack).e == (b["pack"] as RealPack).e
	check(same and (a["pack"] as RealPack).hash == (b["pack"] as RealPack).hash, "the same road planned twice: the same heights and hash")
	var baked := AdventurePlans.pack_for(AdventurePlans.tour(REGION, PINS))
	check(bool(a["ok"]) and (a["pack"] as RealPack).hash != baked.hash, "and the hash takes the heights in: the baked land's road has another")
	_offline([] as Array[String])
	var c := _plan_live(r)
	check(not bool(c["ok"]) and str(c["error"]).contains("lie of the land"), "with no tiles to be had: %s" % str(c["error"]))
	_restore()


## A world laid out on the live land: its chunks, the land blocks beside the road and the skyline, pushed down near the
## road as the baker pushes a baked one down.
func test_ride() -> void:
	_offline()
	var r := RealRegion.get_region(REGION)
	var res := _plan_live(r)
	if not bool(res["ok"]):
		check(false, "the ride plans for the world check")
		_restore()
		return
	var pack: RealPack = res["pack"]
	var w := AdventureWorld.new()
	w.setup(pack, 11)
	t.add_child(w)
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and (w.ridges.busy() or w.ridges.block_count() == 0 or w.land.busy() or w.land.block_count() == 0):
		await t.get_tree().process_frame
	var built := 0
	for c in [0, 20, 60, 100, 150, w.route.chunk_count() - 1]:
		var data := AdventureChunk.build(w.route, c)
		if (data["road"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
			built += 1
	check(built == 6 and w.land.block_count() > 4 and w.ridges.block_count() > 2,
		"the world builds on the live land: %d of 6 chunks with their road, %d land blocks, %d of skyline" % [built, w.land.block_count(), w.ridges.block_count()])
	var k := 1200
	var ground := pack.terrain.height(pack.x[k], pack.z[k])
	var ridge_h := NAN
	var block := Vector2i(floori(pack.x[k] / (RealRidges.BLOCK * 128.0)), floori(pack.z[k] / (RealRidges.BLOCK * 128.0)))
	var arrays = w.ridges._block_arrays(block)
	if arrays is Array:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var lx := pack.x[k] - block.x * RealRidges.BLOCK * 128.0
		var lz := pack.z[k] - block.y * RealRidges.BLOCK * 128.0
		var best := INF
		for v in verts:
			var dd := Vector2(v.x - lx, v.z - lz).length()
			if dd < best:
				best = dd
				ridge_h = v.y
	check(not is_nan(ridge_h) and ridge_h < ground - 30.0, "under the road the skyline lies %.0f m below the land, out of sight" % (ground - ridge_h))
	w.queue_free()
	await t.get_tree().process_frame
	_restore()
