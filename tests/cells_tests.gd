extends RefCounted
## Cells (tools/region_bake.py --cell; RealRegion.stitch): the world's grid of 0.25 degree squares, each baked on its
## own, stitched by the game into one region for an area. Run from tests/run_tests.gd (its _test_cells_* functions hand
## over to these). Nothing here touches the network.
##
## The fixtures: tests/fixtures/cells holds the two cells of the Yorkshire Dales either side of 2 degrees west
## (c577_711 and c577_712, baked from Overture's 2026-10-21.0 release, the same as the bundled Dales region, their
## cover cut to the land round Swaledale), and areas.json names the area "swaledale" over them, in the bundled Dales'
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
	check(asked > 100 and same >= asked * 0.9, "and the same cover beside it, either side of the edge (%d of %d)" % [same, asked])
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
