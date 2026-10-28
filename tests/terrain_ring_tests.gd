extends RefCounted
## Terrain by position (interfaces/terrain.md in the project's ride-anywhere-v2 folder): RealTerrain asked by position
## only, its tiles following the riders (follow_riders), and the sea told from land below sea level by the cells' place
## profiles. Run from tests/run_tests.gd (its _test_terrain_* functions hand over to these). Nothing here touches the
## network: the tiles are made here, flat, one height per level (so a height says which level answered), and "fetched"
## by writing them to disk.

const DIR := "user://test_terrain_ring"
## The Beemster (tests/postcards' polder), in cell 570_739.
const LAT := 52.54
const LON := 4.93
## Each live level's made-up height: fine, middle, ridge.
const LEVEL_H := [20.0, 12.0, 5.0]
const POLDER_PROFILE := "res://tests/postcards/world/profile/c570_739.json"

var t: Node   # the test runner: check()
var asked: Array[Vector3i] = []   # every tile the fake fetcher was asked for
var _was := []


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _begin() -> void:
	_was = [HeightTiles.dirs, HeightTiles.offline, HeightTiles.disk, CellStore.offline, RealTerrain.fetcher]
	RegionStore._remove_tree(DIR)
	DirAccess.make_dir_recursive_absolute(DIR)
	HeightTiles.dirs = [DIR] as Array[String]
	HeightTiles.disk = DIR
	HeightTiles.offline = true
	HeightTiles.reset()
	CellStore.offline = true
	PlaceProfile.forget()
	asked.clear()
	RealTerrain.fetcher = _fake_fetch


func _end() -> void:
	HeightTiles.dirs = _was[0]
	HeightTiles.offline = _was[1]
	HeightTiles.disk = _was[2]
	CellStore.offline = _was[3]
	RealTerrain.fetcher = _was[4]
	HeightTiles.reset()
	PlaceProfile.forget()
	RegionStore._remove_tree(DIR)


## A 64 px Terrarium tile of `key`, every pixel at `h` metres (or `h_of(i, j)` where given), on disk.
func _put(key: Vector3i, h: float, h_of := Callable()) -> void:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for j in size:
		for i in size:
			var v: float = h_of.call(i, j) if h_of.is_valid() else h
			var e := int(round((v + 32768.0) * 256.0))
			img.set_pixel(i, j, Color8((e >> 16) & 255, (e >> 8) & 255, e & 255))
	var path := DIR.path_join("%d/%d/%d.png" % [key.x, key.y, key.z])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)


## The fetcher the terrain is given: writes each tile asked for (its level's height) and notes it.
func _fake_fetch(keys: Array[Vector3i], _progress: Callable) -> int:
	var zms := RealTerrain.new("", {"heights": "live", "frame": {"lat": LAT, "lon": LON}}).zooms
	for k in keys:
		asked.append(k)
		var li := zms.find(k.x)
		_put(k, LEVEL_H[maxi(li, 0)])
		HeightTiles._missing.erase(k)
	return 0


## A ride's live terrain at the Beemster whose planned road runs 200 m east from the frame's middle.
func _ride() -> RealTerrain:
	var region := RealTerrain.new("", {"heights": "live", "frame": {"lat": LAT, "lon": LON}})
	var tr := region.for_road(PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)]))
	tr.threaded = false
	return tr


## Terrain is asked by position: height, ready and ground_arrived, before and after a tile comes in, from any thread.
func test_by_position() -> void:
	_begin()
	var tr := _ride()
	# The road's own tiles, as planning fetches them.
	for k in tr.used_keys():
		_put(k, LEVEL_H[tr.zooms.find(k.x)])
	# North of the road, past its fine and middle levels' tiles, within its ridge level's.
	var p := Vector2(0.0, -8000.0)
	while p.y > -30000.0 and (tr._uses(1, _key_at(tr, 1, p)) or not tr._uses(2, _key_at(tr, 2, p))):
		p.y -= 500.0
	var area := Rect2(p - Vector2(50, 50), Vector2(100, 100))
	check(is_equal_approx(tr.height(0.0, 0.0), LEVEL_H[0]), "on the road the fine level answers (%.1f m)" % tr.height(0.0, 0.0))
	check(is_equal_approx(tr.height(p.x, p.y), LEVEL_H[2]) and not tr.ready(area, 0) and tr.ready(area, 2),
		"%.0f km off it, before any tile comes, the ridge level's ground is there (%.1f m), not yet final" % [-p.y / 1000.0, tr.height(p.x, p.y)])
	check(is_nan(tr.height(0.0, -60000.0)), "60 km off, where no level has anything, the height is NAN")
	var arrived: Array = []
	tr.ground_arrived.connect(func(a: Rect2, li: int): arrived.append([a, li]))
	tr.follow_riders([Vector4(p.x, p.y, 0.0, 0.0)])
	check(is_equal_approx(tr.height(p.x, p.y), LEVEL_H[0]) and tr.ready(area, 0),
		"a rider there: the fine tiles round them come in and answer (%.1f m), final" % tr.height(p.x, p.y))
	var fine_here := arrived.filter(func(a): return int(a[1]) == 0 and (a[0] as Rect2).has_point(p))
	var mids := arrived.filter(func(a): return int(a[1]) == 1)
	check(fine_here.size() >= 1 and not mids.is_empty(), "and ground_arrived says where, level by level (%d areas)" % arrived.size())
	# From a worker, the same.
	var box := [NAN]
	var id := WorkerThreadPool.add_task(func(): box[0] = tr.height(p.x + 30.0, p.y + 30.0))
	WorkerThreadPool.wait_for_task_completion(id)
	check(is_equal_approx(float(box[0]), LEVEL_H[0]), "asked from a worker thread, the same ground")
	# Frame round trip.
	var g := tr.to_geo(p.x, p.y)
	var back := tr.from_geo(g[0], g[1])
	check(back.distance_to(p) < 0.01 and g[0] > LAT, "route frame to degrees and back (%.5f, %.5f)" % [g[0], g[1]])
	_end()


## The fetch rule: a ring round each rider, a strip ahead of one that's moving, nearest first; tiles let go once every
## rider is past, so a long ride holds no more than a short one.
func test_ring() -> void:
	_begin()
	var zms := RealTerrain.new("", {"heights": "live", "frame": {"lat": LAT, "lon": LON}}).zooms
	var still := RealTerrain.ring_keys([Vector4(0, 0, 0, 0)], zms, LAT, LON, RealTerrain.LIVE_REACH, RealTerrain.AHEAD, RealTerrain.AHEAD_WIDE)
	var east := RealTerrain.ring_keys([Vector4(0, 0, 20, 0)], zms, LAT, LON, RealTerrain.LIVE_REACH, RealTerrain.AHEAD, RealTerrain.AHEAD_WIDE)
	var tr := _ride()
	var here := _key_at(tr, 0, Vector2(0, 0))
	var ahead := _key_at(tr, 0, Vector2(3000, 0))
	var behind := _key_at(tr, 0, Vector2(-3000, 0))
	check(still[0][0] == here, "the first tile wanted is the one the rider is on")
	check(not still[0].has(ahead) and east[0].has(ahead) and not east[0].has(behind),
		"moving east, the fine tiles 3 km ahead are wanted, not those 3 km behind (%d fine tiles still, %d moving)" % [still[0].size(), east[0].size()])
	check(still[2].size() <= 4 and east[2] == still[2], "the ridge level is a ring only (%d tiles)" % still[2].size())
	var two := RealTerrain.ring_keys([Vector4(0, 0, 0, 0), Vector4(0, -20000, 0, 0)], zms, LAT, LON, RealTerrain.LIVE_REACH, RealTerrain.AHEAD, RealTerrain.AHEAD_WIDE)
	check(two[0].has(here) and two[0].has(_key_at(tr, 0, Vector2(0, -20000))), "two riders 20 km apart: the ground round each")
	# A long ride east, 40 km: what's held stays flat, nothing is fetched twice, and the start is let go.
	var most := 0
	var x := 0.0
	while x <= 40000.0:
		tr.follow_riders([Vector4(x, 0.0, 25.0, 0.0)])
		most = maxi(most, int(tr.held()["ring"]))
		x += 200.0
	var at_mid := int(tr.held()["ring"])
	var twice := asked.size() - _unique(asked)
	var held_start := tr._uses(0, _key_at(tr, 0, Vector2(4000, 0)))
	check(twice == 0 and most > 10 and most < 60 and not held_start,
		"a 40 km ride: at most %d tiles taken in at once (%d at the end), none fetched twice, the start let go" % [most, at_mid])
	check(is_equal_approx(tr.height(40000.0, 0.0), LEVEL_H[0]) and is_equal_approx(tr.height(42500.0, 0.0), LEVEL_H[0]),
		"and the fine ground is under the rider and 2.5 km ahead")
	_end()


func _key_at(tr: RealTerrain, li: int, p: Vector2) -> Vector3i:
	var g := tr.to_geo(p.x, p.y)
	return Vector3i(tr.zooms[li], floori(HeightTiles.mercator_x(g[1], tr.zooms[li])), floori(HeightTiles.mercator_y(g[0], tr.zooms[li])))


func _unique(list: Array) -> int:
	var seen := {}
	for k in list:
		seen[k] = true
	return seen.size()


## Land below sea level is land where the cell's place profile has no sea (the Beemster); where it has, the sea.
func test_polder() -> void:
	_begin()
	var tr := _ride()
	var cell := RealRegion.cell_of(LAT, LON)
	check(cell == Vector2i(570, 739), "the Beemster is in cell 570_739")
	var key := _key_at(tr, 0, Vector2(0, 0))
	_put(key, -4.0)
	# Before the profile is known: as it always was, ground at or under 0.4 m is sea.
	var before := HeightTiles.tile(key)
	check(before != null and before.is_sea(32, 32) and before.at(32, 32) < -2.0, "a polder 4 m below sea level, its cell's sea unknown: sea, as before")
	# Its profile (the bake's, from the postcards' world): no sea, no coast.
	var prof = JSON.parse_string(FileAccess.get_file_as_string(POLDER_PROFILE))
	PlaceProfile._cells["570_739"] = PlaceProfile.parse(prof)
	tr.know_sea_under([key] as Array[Vector3i])
	check(HeightTiles.sea_in(cell) == 0, "its place profile says the cell has no sea")
	var after := HeightTiles.tile(key)
	check(after != null and not after.is_sea(32, 32) and is_equal_approx(after.at(32, 32), -4.0) and is_equal_approx(tr.height(0.0, 0.0), -4.0),
		"so the polder is land, at its own height (%.2f m), read again once its sea was known" % tr.height(0.0, 0.0))
	check(not tr.sea_at(0.0, 0.0) and not tr.has_sea(), "sea_at says land, and the ride draws no sea")
	# A tile across two cells, one with sea: the sea only in that one.
	var zm := 12
	var edge := HeightTiles.mercator_x(5.0, zm)   # (the cells' edge at 5° E)
	var two := Vector3i(zm, floori(edge), floori(HeightTiles.mercator_y(LAT, zm)))
	var split := (edge - two.y) * 64.0
	_put(two, 0.0)
	HeightTiles.know_sea(Vector2i(570, 740), true)
	var tile := HeightTiles.tile(two)
	var west := int(split * 0.5)
	var east := int(split + (64.0 - split) * 0.5)
	check(tile != null and split > 4.0 and split < 60.0 and not tile.is_sea(west, 32) and is_equal_approx(tile.at(west, 32), 0.0)
		and tile.is_sea(east, 32) and tile.at(east, 32) < -2.0,
		"a tile over the polder's cell and one with sea: land at 0 m in the first (%.1f), sea in the second (%.1f)" % [tile.at(west, 32) if tile else NAN, tile.at(east, 32) if tile else NAN])
	_end()


## One ride off the plan: away from the road, out past the fine tiles, the land keeps coming round the rider and holds
## a bike up (its near blocks' collision), and the terrain asks for the tiles ahead.
func test_off_plan() -> void:
	var live = load("res://tests/live_heights_tests.gd").new(t)
	live._offline()
	var was_fetcher := RealTerrain.fetcher
	asked.clear()
	RealTerrain.fetcher = func(keys: Array[Vector3i], _p: Callable) -> int:
		asked.append_array(keys)
		return keys.size()
	var r := RealRegion.get_region(live.REGION)
	var res: Dictionary = live._plan_live(r)
	if not bool(res["ok"]):
		check(false, "the ride plans for the off-plan check (%s)" % str(res.get("error", "")))
		RealTerrain.fetcher = was_fetcher
		live._restore()
		return
	var pack: RealPack = res["pack"]
	pack.terrain.threaded = false
	var w := AdventureWorld.new()
	w.setup(pack, 11)
	t.add_child(w)
	var k := pack.x.size() / 2
	var hh := atan2(pack.x[k + 1] - pack.x[k], -(pack.z[k + 1] - pack.z[k]))
	var side := Vector2(cos(hh), sin(hh))
	var road := Vector2(pack.x[k], pack.z[k])
	var held := 0
	var tried := 0
	var heights := ""
	for out: float in [400.0, 800.0, 1600.0, 2600.0]:
		# Riding straight out from the road, across the land.
		var at := road + side * out
		var local := Vector3(at.x - w.origin.x, 0.0, at.y - w.origin.z)
		if absf(local.x) > 1500.0 or absf(local.z) > 1500.0:
			w.shift_origin_to(local)
			local = Vector3(at.x - w.origin.x, 0.0, at.y - w.origin.z)
		w.land.riders(at.x - side.x * 60.0, at.y - side.y * 60.0)   # (where it was a moment ago: its way is out)
		w.land._was.z -= 3.0
		w.follow(local)
		var end := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < end and (w.land.busy() or not w.land.holds(at.x, at.y)):
			await t.get_tree().process_frame
		await t.get_tree().physics_frame
		await t.get_tree().physics_frame
		var ground := pack.terrain.height(at.x, at.y)
		var q := PhysicsRayQueryParameters3D.create(local + Vector3.UP * (ground + 50.0), local + Vector3.UP * (ground - 50.0), 1)
		var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
		tried += 1
		if hit and (hit["collider"] as Node).name == "Ground" and absf(float(hit["position"].y) - ground) < 3.0:
			held += 1
		heights += " %.0f m out: %s" % [out, ("%.0f m" % ground) if not is_nan(ground) else "none"]
	check(held == tried, "riding out from the road, the land holds the bike up %d of %d places out to 2.6 km (%s)" % [held, tried, heights.strip_edges()])
	var ahead := _unique(asked.filter(func(key: Vector3i): return key.x == pack.terrain.zooms[0]))
	check(ahead > 0, "and the fine tiles out there and ahead were asked for (%d of them)" % ahead)
	# Network mode (T6's RoadNet): no strip is left out by the planned road, and the net cuts its roads in.
	var on_road := Vector2i(floori(road.x / RealLand.BLOCK), floori(road.y / RealLand.BLOCK))
	var single = w.land._block_arrays(on_road, 0)
	w.land.set_roads(FakeNet.new(road.y))
	var net = w.land._block_arrays(on_road, 0)
	var cells: int = RealLand.CELLS[0]
	var full := cells * cells * 6
	var dip := 0
	if net is Array:
		var verts: PackedVector3Array = net[Mesh.ARRAY_VERTEX]
		for v in verts.slice(0, (cells + 1) * (cells + 1)):
			var z := on_road.y * RealLand.BLOCK + v.z
			var bare := w.route.ground_at(on_road.x * RealLand.BLOCK + v.x, z)
			if absf(z - road.y) < FakeNet.HALF and absf(v.y - (bare - 1.0)) < 0.01:
				dip += 1
	# (every cell is drawn, and its skirts; the cells the cut runs through are drawn finer, so there are more)
	check(single is Array and net is Array and (single[Mesh.ARRAY_INDEX] as PackedInt32Array).size() < full + 4 * cells * 12
		and (net[Mesh.ARRAY_INDEX] as PackedInt32Array).size() >= full + 4 * cells * 12 and dip > 0,
		"in network mode the land under the road is drawn too, cut in where the net says (%d points)" % dip)
	# A deep cutting through the block's edge: the skirt there hangs as deep as the land and a coarser neighbour's
	# straight edge part, so the eye never sees through the seam.
	w.land.set_roads(FakeNet.new(road.y, 9.0))
	var deep = w.land._block_arrays(on_road, 0)
	var shallow := INF
	if deep is Array:
		var dv: PackedVector3Array = deep[Mesh.ARRAY_VERTEX]
		var n := cells + 1
		# (edge 2, the block's west side: each grid vertex there and the lowest vertex under it, its skirt's)
		var lowest := {}
		for v in dv:
			if absf(v.x) < 0.001:
				var at_z := snappedf(v.z, 0.01)
				lowest[at_z] = minf(float(lowest.get(at_z, INF)), v.y)
		for t in n:
			var z := on_road.y * RealLand.BLOCK + float(t) * RealLand.BLOCK / cells
			if absf(z - road.y) < FakeNet.HALF:
				shallow = minf(shallow, dv[t * n].y - float(lowest.get(snappedf(dv[t * n].z, 0.01), INF)))
	check(deep is Array and shallow >= 9.0, "a block's skirt hangs below a deep cutting through its edge (%.1f m)" % shallow)
	w.land.set_roads(null)
	w.queue_free()
	await t.get_tree().process_frame
	RealTerrain.fetcher = was_fetcher
	live._restore()


## A road network for RealLand's network mode: one road along z = `z0`, cut 1 m into the land HALF either side.
class FakeNet:
	extends RefCounted
	const HALF := 20.0
	var z0 := 0.0
	var depth := 1.0

	func _init(z: float, d := 1.0) -> void:
		z0 = z
		depth = d

	func roads_near(rect: Rect2) -> bool:
		return z0 > rect.position.y - HALF and z0 < rect.end.y + HALF

	func ground_at(_x: float, z: float, bare: float) -> float:
		return bare - depth if absf(z - z0) < HALF else bare

	func locate(_x: float, z: float) -> Dictionary:
		return {"edge": 0, "s": 0.0, "lat": z - z0, "width": 8.0}

	func bridge_at(_edge: int, _s: float) -> float:
		return 0.0
