extends RefCounted
## Cells (tools/region_bake.py --cell; RealRegion.stitch): the world's grid of 0.25 degree squares, each baked on its
## own, stitched by the game into one region for an area. Run from tests/run_tests.gd (its _test_cells_* functions hand
## over to these). Nothing here touches the network.
##
## The fixtures: tests/fixtures/cells holds the two cells of the Yorkshire Dales either side of 2 degrees west
## (c577_711 and c577_712, as tools/region_bake.py --cell bakes them from Overture's 2026-10-21.0 release, the same as
## the bundled Dales region's), and areas.json names the area "swaledale" over them, in the bundled Dales'
## own frame; tests/fixtures/heights holds the map tiles of the land along the road from Gunnerside to Grinton, which
## crosses from one cell into the other.

const CELLS := "res://tests/fixtures/cells"
const HEIGHTS := "res://tests/fixtures/heights"
const AREA := "area:swaledale"
## Gunnerside and Grinton, in the Dales' frame (the bundled region's tour pins them there too).
const PINS := [Vector2(-2422, -4363), Vector2(7187, -4599)]
## 2 degrees west, where one cell ends and the next begins, in the Dales' frame.
const EDGE_X := 2604.0

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _use_fixtures() -> void:
	RealRegion.cell_dirs = [CELLS]
	HeightTiles.dirs = [HEIGHTS]
	HeightTiles.offline = true
	HeightTiles.reset()


func _restore() -> void:
	RealRegion.cell_dirs = ["res://data/cells", "user://cells"]
	HeightTiles.dirs = ["res://data/heights"]
	HeightTiles.offline = false
	HeightTiles.reset()


func _request() -> Dictionary:
	return {"pins": PINS, "mode": "main", "names": ["Gunnerside", "Grinton"], "seed": 0}


func test_grid() -> void:
	check(RealRegion.cell_of(54.3, -1.9) == Vector2i(577, 712) and RealRegion.cell_of(54.3, -2.1) == Vector2i(577, 711)
		and RealRegion.cell_of(-0.1, -0.1) == Vector2i(359, 719), "a place's cell is the baker's (tools/region_bake.py cell_of)")
	_use_fixtures()
	check(RealRegion.cell_dir(Vector2i(577, 712)).ends_with("c577_712") and RealRegion.cell_dir(Vector2i(577, 713)) == "",
		"the game finds the cells it has, and not the ones it hasn't")
	check(RealRegion.list().has(AREA), "an area made of cells is listed with the regions (%s)" % str(RealRegion.list()))
	_restore()
	check(not RealRegion.list().has(AREA), "and isn't when the game has none of its cells")


## Two cells stitched into one region: the roads that cross from one to the other joined up, nothing on the edge twice.
func test_stitch() -> void:
	_use_fixtures()
	var t0 := Time.get_ticks_msec()
	var r := RealRegion.get_region(AREA)
	var ms := Time.get_ticks_msec() - t0
	check(r != null and r.counts.get("cells", 0) == 2 and r.terrain.live, "the Swaledale area stitches from its two cells, its heights live (%d ms)" % ms)
	if r == null:
		_restore()
		return
	# Roads across the edge: an edge with its ends either side, and the roads either side one network.
	var across := 0
	for ei in r.edge_count():
		var xa := r.node_pos[r.edge_a[ei]].x
		var xb := r.node_pos[r.edge_b[ei]].x
		if (xa - EDGE_X) * (xb - EDGE_X) < 0.0:
			across += 1
	var west := r.nearest_node(PINS[0].x, PINS[0].y)
	var east := r.nearest_node(PINS[1].x, PINS[1].y)
	check(across >= 5 and r.component[west] == r.component[east], "%d roads cross from one cell into the other, and both sides are one network" % across)
	# Nothing twice: as many roads as the two cells have between them, less those both have (the same segment between
	# the same junctions); no two junctions in the same place; no building twice.
	var both := {}
	var expected := 0
	for name in ["c577_711", "c577_712"]:
		var rows: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CELLS.path_join(name).path_join("roads.json")))
		var ids: Array = rows["ids"]
		for e: Dictionary in rows["edges"]:
			var key := "%s|%s|%s" % [e["g"], ids[int(e["a"])], ids[int(e["b"])]]
			if not both.has(key):
				expected += 1
			both[key] = true
	var spots := {}
	var stacked := 0
	for i in r.node_count():
		var key := Vector2i(roundi(r.node_pos[i].x * 2.0), roundi(r.node_pos[i].y * 2.0))
		if spots.has(key):
			stacked += 1
		spots[key] = true
	check(r.edge_count() == expected and stacked <= 2, "every road once: %d, as the cells have them between them (%d junctions in the same place)" % [r.edge_count(), stacked])
	var grid := {}
	var dup := 0
	for b: Array in r.buildings:
		var p := Vector2(float(b[0]), float(b[1]))
		var cell := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				for q: Vector3 in grid.get(cell + Vector2i(dx, dz), []):
					if Vector2(q.x, q.y).distance_to(p) < 0.5 and absf(q.z - float(b[2])) < 0.2:
						dup += 1
		if not grid.has(cell):
			grid[cell] = []
		(grid[cell] as Array).append(Vector3(p.x, p.y, float(b[2])))
	check(r.buildings.size() > 10000 and dup == 0, "and its %d buildings (%d twice), %d places to stop and %d towns and villages once each" % [r.buildings.size(), dup, r.pois.size(), r.places.size()])
	var again := RealRegion.stitch("again", "Again", [CELLS.path_join("c577_712"), CELLS.path_join("c577_711")] as Array[String], 54.34, -2.04)
	check(again != null and again.hash == r.hash and again.node_count() == r.node_count() and again.edge_count() == r.edge_count(),
		"stitched in the other order, the same roads and the same hash")
	_restore()


## The road from Gunnerside to Grinton over the stitched cells is the bundled Dales region's road (baked from the same
## data), and the land under it the same: its heights from the map tiles, the bundled ones baked.
func test_same_road() -> void:
	_use_fixtures()
	var area := RealRegion.get_region(AREA)
	var dales := RealRegion.get_region("dales")
	var a := RoutePlanner.plan(area, _request())
	var b := RoutePlanner.plan(dales, _request())
	check(bool(a["ok"]) and bool(b["ok"]), "the road plans over the cells, the land fetched from the fixtures (%s)" % str(a.get("error", "")))
	if not bool(a["ok"]) or not bool(b["ok"]):
		_restore()
		return
	var pa: RealPack = a["pack"]
	var pb: RealPack = b["pack"]
	var apart := 0.0
	var high := 0.0
	var total := 0.0
	for i in mini(pa.x.size(), pb.x.size()):
		apart = maxf(apart, Vector2(pa.x[i] - pb.x[i], pa.z[i] - pb.z[i]).length())
		high = maxf(high, absf(pa.e[i] - pb.e[i]))
		total += absf(pa.e[i] - pb.e[i])
	check(pa.x.size() == pb.x.size() and apart < 1.0, "the same road as the bundled Dales' (%d knots, %.2f m apart at most, %.1f km)" % [pa.x.size(), apart, pa.max_km()])
	check(total / pa.e.size() < 1.0 and high < 6.0, "on the same land: %.2f m apart on average, %.1f at most" % [total / pa.e.size(), high])
	check(pa.pois.size() == pb.pois.size() and absf(pa.building_count - pb.building_count) <= pb.building_count * 0.1,
		"with the same places to stop (%d) and about the same buildings beside it (%d, %d)" % [pa.pois.size(), pa.building_count, pb.building_count])
	# The land's cover, read from whichever cell it is in: as the bundled region has it.
	var same := 0
	var asked := 0
	for k in range(0, pa.x.size(), 25):
		for side: float in [-40.0, 40.0]:
			var x := pa.x[k] + side
			var z := pa.z[k]
			var ca := area.terrain.cover(x, z)
			var cb := dales.terrain.cover(x, z)
			if cb >= 0:
				asked += 1
				same += 1 if ca == cb else 0
	# (a cell's cover near the road is at 16 m, the bundled region's at 4: they differ along the edges of woods and fields)
	check(asked > 100 and same >= asked * 0.8, "and the same cover beside it, either side of the edge, at a cell's 16 m to the region's 4 m (%d of %d)" % [same, asked])
	_restore()


## A world laid out along the road over the cells: its chunks build either side of the edge.
func test_ride() -> void:
	_use_fixtures()
	var res := RoutePlanner.plan(RealRegion.get_region(AREA), _request())
	if not bool(res["ok"]):
		check(false, "the road plans for the ride")
		_restore()
		return
	var pack: RealPack = res["pack"]
	var w := AdventureWorld.new()
	w.setup(pack, 3)
	var crossing := -1
	for i in pack.x.size():
		if pack.x[i] > EDGE_X:
			crossing = i
			break
	var c0 := AdventureRoute.chunk_of(crossing * pack.step)
	var built := 0
	for c in [c0 - 2, c0 - 1, c0, c0 + 1, c0 + 2]:
		var data := AdventureChunk.build(w.route, c)
		if (data["road"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0 and (data["land_1"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
			built += 1
	check(crossing > 0 and built == 5, "the ride's chunks build either side of where it crosses into the next cell (%d of 5)" % built)
	w.free()
	_restore()


# ---------------------------------------------------------------------------- fetched from where they're served

## A stand-in for GitHub on this machine: the index at /index.json, each cell's zip at /zips/NAME.zip behind a redirect
## from /dl/NAME (as a release asset's download redirects), and nothing else. Answer it a frame at a time (serve()).
class FakeHost:
	extends RefCounted
	var server := TCPServer.new()
	var port := 0
	var files := {}        # path -> PackedByteArray
	var asked: Array[String] = []
	var bodies := {}       # path -> the body last sent to it (a POST's)
	var redirects := {}    # path -> where it sends you (a short link's)
	var _peers: Array = []

	func start() -> bool:
		for p in range(18440, 18480):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return true
		return false

	func serve() -> void:
		while server.is_connection_available():
			_peers.append({"peer": server.take_connection(), "got": PackedByteArray()})
		for c: Dictionary in _peers.duplicate():
			var peer: StreamPeerTCP = c["peer"]
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peers.erase(c)
				continue
			var n := peer.get_available_bytes()
			if n > 0:
				var got: PackedByteArray = c["got"]
				got.append_array(peer.get_data(n)[1])
				c["got"] = got
			var text := (c["got"] as PackedByteArray).get_string_from_utf8()
			if not text.contains("\r\n\r\n"):
				continue
			var head := text.get_slice("\r\n\r\n", 0)
			var length := 0
			for line in head.split("\r\n"):
				if line.to_lower().begins_with("content-length:"):
					length = int(line.get_slice(":", 1).strip_edges())
			var body_text := text.substr(head.length() + 4)
			if body_text.to_utf8_buffer().size() < length:
				continue   # (the rest of the body is still coming)
			var path := text.get_slice(" ", 1)
			asked.append(path)
			if length > 0:
				bodies[path] = body_text
			var reply := PackedByteArray()
			if redirects.has(path):
				reply = ("HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\n\r\n" % str(redirects[path])).to_utf8_buffer()
			elif path.begins_with("/dl/"):
				reply = ("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:%d/zips/%s.zip\r\nContent-Length: 0\r\n\r\n" % [port, path.trim_prefix("/dl/")]).to_utf8_buffer()
			elif files.has(path):
				var body: PackedByteArray = files[path]
				reply = ("HTTP/1.1 200 OK\r\nContent-Length: %d\r\n\r\n" % body.size()).to_utf8_buffer()
				reply.append_array(body)
			else:
				reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n".to_utf8_buffer()
			peer.put_data(reply)
			peer.disconnect_from_host()
			_peers.erase(c)

	func stop() -> void:
		server.stop()


## Zips a fixture cell's folder the way tools/region_zip.py does (its files at the top level).
func _zip_cell(name: String) -> PackedByteArray:
	var path := "user://test_zip_%s.zip" % name
	var z := ZIPPacker.new()
	z.open(path)
	var root := CELLS.path_join(name)
	var files: Array[String] = []
	_walk(root, "", files)
	for rel in files:
		z.start_file(rel)
		z.write_file(FileAccess.get_file_as_bytes(root.path_join(rel)))
		z.close_file()
	z.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes


func _walk(root: String, rel: String, out: Array[String]) -> void:
	var d := DirAccess.open(root.path_join(rel) if rel != "" else root)
	for fn in d.get_files():
		out.append(rel.path_join(fn) if rel != "" else fn)
	for sub in d.get_directories():
		_walk(root, rel.path_join(sub) if rel != "" else sub, out)


## A journey over an area whose cells this game hasn't got: they're fetched from the index (following the download's
## redirect), checked against their hashes, kept, and the road planned over them, all on the planner's worker; a cell
## whose bytes aren't the index's is turned away.
func test_fetch() -> void:
	var host := FakeHost.new()
	check(host.start(), "a stand-in for GitHub listens on this machine")
	var store := "user://test_cells"
	RegionStore._remove_tree(store)
	var index := {"format": 1, "release": "2026-10-21.0", "cells": {}, "areas": {"swaledale": JSON.parse_string(FileAccess.get_file_as_string(CELLS.path_join("areas.json")))["swaledale"]}}
	for name in ["c577_711", "c577_712"]:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CELLS.path_join(name).path_join("region.json")))
		host.files["/zips/%s.zip" % name] = _zip_cell(name)
		index["cells"][name.trim_prefix("c")] = {"hash": meta["hash"], "bytes": (host.files["/zips/%s.zip" % name] as PackedByteArray).size(),
			"url": "http://127.0.0.1:%d/dl/%s" % [host.port, name]}
	index["cells"]["577_713"] = {"empty": true}
	host.files["/index.json"] = JSON.stringify(index).to_utf8_buffer()
	CellStore.index_url = "http://127.0.0.1:%d/index.json" % host.port
	CellStore.dir = store
	CellStore.offline = false
	RealRegion.cell_dirs = [store]
	HeightTiles.dirs = [HEIGHTS]
	HeightTiles.offline = true
	HeightTiles.reset()
	RealRegion.forget_areas()
	# The index first: the area is listed before any of its cells are here.
	var task := WorkerThreadPool.add_task(func(): CellStore.index(true))
	while not WorkerThreadPool.is_task_completed(task):
		host.serve()
		await t.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	check(RealRegion.list().has(AREA) and RealRegion.cell_dir(Vector2i(577, 712)) == "", "the index lists the Swaledale area before any of its cells are here")
	# The journey: its cells fetched on the planner's worker.
	# (the host's plan names the map it planned over: the two cells' hash, as the host stitched them)
	var host_map := RealRegion.stitch("host", "Host", [CELLS.path_join("c577_711"), CELLS.path_join("c577_712")] as Array[String], 54.34, -2.04)
	var plan := AdventurePlans.clean({"region": AREA, "region_hash": host_map.hash, "pins": [[PINS[0].x, PINS[0].y], [PINS[1].x, PINS[1].y]],
		"mode": "main", "names": ["Gunnerside", "Grinton"]})
	check(not plan.is_empty() and plan["region_hash"] == host_map.hash, "the host's plan for the area is taken before its cells are here")
	var res := {}
	var end := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < end:
		host.serve()
		res = AdventurePlans.result(plan)
		if not res.is_empty():
			break
		await t.get_tree().process_frame
	var redirected := host.asked.filter(func(p): return str(p).begins_with("/dl/")).size()
	check(not res.is_empty() and bool(res.get("ok", false)), "planned over the area once its cells came (%s)" % str(res.get("error", "still waiting")))
	check(RealRegion.cell_dir(Vector2i(577, 711)).begins_with(store) and RealRegion.cell_dir(Vector2i(577, 712)).begins_with(store) and redirected == 2,
		"both cells fetched (through the download's redirect) and kept, the empty one next door not asked for (%s)" % str(host.asked))
	if bool(res.get("ok", false)):
		check(absf((res["pack"] as RealPack).max_km() - 11.35) < 0.1, "the same road as from the fixtures (%.2f km)" % (res["pack"] as RealPack).max_km())
	# A cell whose bytes aren't the index's.
	RegionStore._remove_tree(store.path_join("c577_712"))
	RealRegion.forget_areas()
	index["cells"]["577_712"]["hash"] = "0000000000000000"
	host.files["/index.json"] = JSON.stringify(index).to_utf8_buffer()
	var why := [""]
	task = WorkerThreadPool.add_task(func():
		CellStore.index(true)
		why[0] = CellStore.fetch_box(54.3, -2.0, 54.31, -1.99))
	while not WorkerThreadPool.is_task_completed(task):
		host.serve()
		await t.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	check(str(why[0]).contains("isn't the region the index names") and RealRegion.cell_dir(Vector2i(577, 712)) == "",
		"a cell whose bytes aren't what the index says is turned away: %s" % str(why[0]))
	host.stop()
	RegionStore._remove_tree(store)
	CellStore.index_url = CellStore.INDEX_URL
	CellStore.dir = "user://cells"
	CellStore._index = {}
	RealRegion.forget_areas()
	_restore()


## The ready-check: a rider on the road waits at the start, held there, while a mate is still getting the road ready
## (not on the ride yet: their cells and land still coming), and sets off once they're on it.
func test_ready_check() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	# A mate in the crew who hasn't got the road yet.
	Shed.crew[77] = {"name": "Dave"}
	const Rides := preload("res://tests/rides.gd")
	Rides.start(8.0, 4)
	for i in 20:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and trip.crew_waiting() == ["Dave"] and trip.crew_hold(), "on the road, waiting at the start for Dave (%s)" % str(trip.crew_waiting()))
	check(trip._hud.text.contains("Waiting at the start for Dave"), "and the screen says so: %s" % trip._hud.text)
	if main.bike:
		main.bike.controls_enabled = true
		Input.action_press("throttle")
		for i in 60:
			await t.get_tree().physics_frame
		Input.action_release("throttle")
		check(absf(main.bike.speed) < 0.5, "the throttle doesn't move the bike off the start meanwhile (%.2f m/s)" % main.bike.speed)
	# Dave's on the road now.
	(Shed.adventure["riders"] as Dictionary)[77] = 0
	check(not trip.crew_hold() and trip.crew_waiting().is_empty(), "once Dave's on it, nobody's waited for")
	Shed.adventure["riders"].erase(77)
	trip._started_at -= int((AdventureTrip.CREW_WAIT + 1.0) * 1000.0)
	check(not trip.crew_hold(), "and nobody waits for anyone longer than %d s" % int(AdventureTrip.CREW_WAIT))
	Shed.crew.erase(77)
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await t.get_tree().process_frame
