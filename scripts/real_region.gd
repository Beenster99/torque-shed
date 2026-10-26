class_name RealRegion
extends RefCounted
## A region of the real world the crew can plan a route across (see tools/region_bake.py, RoutePlanner): every road of
## an area as a graph, and the land (RealTerrain: heights and cover at three levels), buildings, places to stop and
## landmarks wherever there is a road. A region is a folder under data/regions/. Everything is in the region's own
## frame: metres from the area's middle, +x east, -z north, heights above sea level.
##
## Regions are read-only once loaded, so one can be shared by every thread (the planner reads it on a worker).

const FORMAT := 2
const DIR := "res://data/regions"
## Downloaded regions (RegionStore) live here, beside the bundled ones.
const USER_DIR := "user://regions"
## Cells of the grid the nodes are filed in (m), for finding the nearest.
const CELL := 250.0
## The names roads without one are given, by class.
const GENERIC_NAMES := {"motorway": "Motorway", "trunk": "Trunk road", "primary": "Main road", "secondary": "B road",
	"tertiary": "Minor road", "unclassified": "Minor road", "residential": "Street", "living_street": "Street", "track": "Track"}

static var _cache := {}
static var _cache_lock := Mutex.new()
## The areas of listed cells ("area:@...") cached, oldest first: only the last few are kept (each is many cells).
static var _cell_areas: Array[String] = []
const CELL_AREAS_KEPT := 4

var id := ""
var title := ""
var hash := ""
var credits: Array = []
## The canopy map's credit, added to a region's when its cells have their trees (tools/tree_bake.py).
const TREES_CREDIT := "Tree heights: Meta and World Resources Institute, High Resolution Canopy Height Maps (CC BY 4.0)."
var theme := "hills"
var sea := false
## The country's speed-limit rules ("uk", "jp" or "world": see RealPack.region).
var country := "world"
var frame_lat := 0.0
var frame_lon := 0.0
## The area: left, top, right, bottom in the region's frame.
var bounds := Rect2()
var terrain: RealTerrain
var classes: Array = []
var surfaces: Array = []
var names: Array = []
## The graph: node positions; per edge its two nodes, class, surface (an index into `surfaces`), posted limit (km/h, 0 for
## none), name (into `names`), and line (from node a to node b, both ends included).
var node_pos := PackedVector2Array()
var edge_a := PackedInt32Array()
var edge_b := PackedInt32Array()
var edge_class := PackedInt32Array()
var edge_surface := PackedInt32Array()
var edge_limit := PackedInt32Array()
var edge_name := PackedInt32Array()
var edge_len := PackedFloat32Array()
## Which way each edge may be driven: 0 both, 1 only from a to b, -1 only from b to a (a one-way street).
var edge_oneway := PackedInt32Array()
var edge_line: Array[PackedVector2Array] = []
## The turns the road rules prohibit: Vector3i(edge arrived by, node, edge left by) -> true.
var bans := {}
## The towns, villages and quarters with names: [{kind ("town" or "village"), name, x, z, pop}].
var places: Array = []
## For each node the edges that meet there.
var adjacent: Array[PackedInt32Array] = []
var buildings: Array = []
var pois: Array = []
var landmarks: Array = []
## Its bridges and tunnels (tools/span_bake.py): [[kind (0 a bridge, 1 a tunnel), x0, z0, x1, z1], ...] in the
## region's frame, end to end. A bundled region's from its spans.json, an area's from its cells' sketch blocks.
var spans: Array = []
## Its rivers and streams as lines (tools/stream_bake.py: the becks the land cover's water polygons don't hold), near its
## roads: [[kind (0 a river, 1 a stream, 2 a canal), PackedVector2Array of points], ...] in the region's frame. A bundled
## region's from its streams.json, an area's from its cells' own files (CellStore.streams).
var streams: Array = []
var counts := {}
## For each node the connected piece of road it is in (numbered in order of the lowest node), and how many junctions that has.
var component := PackedInt32Array()
var component_size := PackedInt32Array()
var _grid := {}


## The ids of the regions the game has (bundled, and downloaded).
static func list() -> Array[String]:
	var out: Array[String] = []
	for root in [DIR, USER_DIR]:
		var d := DirAccess.open(root)
		if d == null:
			continue
		for name in d.get_directories():
			if FileAccess.file_exists(root.path_join(name).path_join("region.json")) and not out.has(name):
				out.append(name)
	for name in areas():
		if has_area(name):
			out.append(AREA_PREFIX + name)
	out.sort()
	return out


## The folder of region `region_id`: the bundled one, else the downloaded one (which may not exist).
static func dir_of(region_id: String) -> String:
	if FileAccess.file_exists(DIR.path_join(region_id).path_join("region.json")):
		return DIR.path_join(region_id)
	return USER_DIR.path_join(region_id)


## Drops region `region_id` from the cache (after a download replaces it).
static func forget(region_id: String) -> void:
	_cache_lock.lock()
	_cache.erase(region_id)
	_cache_lock.unlock()


## The region `region_id` (read once, then shared), or null with the reason in the log.
static func get_region(region_id: String) -> RealRegion:
	_cache_lock.lock()
	if _cache.has(region_id):
		var got: RealRegion = _cache[region_id]
		_cache_lock.unlock()
		return got
	_cache_lock.unlock()
	var r := _load(region_id)
	_cache_lock.lock()
	_cache[region_id] = r
	if region_id.begins_with(CELLS_PREFIX):
		_cell_areas.erase(region_id)
		_cell_areas.append(region_id)
		while _cell_areas.size() > CELL_AREAS_KEPT:
			_cache.erase(_cell_areas.pop_front())
	_cache_lock.unlock()
	return r


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _load(region_id: String) -> RealRegion:
	if region_id.begins_with(CELLS_PREFIX):
		var cells := cells_of_area(region_id)
		if cells.is_empty():
			return null
		CellStore.touch(cells)   # (in use: the last to be pruned, and never this run)
		var dirs: Array[String] = []
		for c in cells:
			var d := cell_dir(c)
			if d != "":
				dirs.append(d)
		var mid := cell_middle(cells[0])
		var stitched := stitch(region_id, title_of(region_id), dirs, mid.x, mid.y)
		if stitched != null:
			stitched.spans = _cell_spans(cells, mid)
			stitched.streams = _cell_streams(cells, mid)
			_cell_trees(cells, stitched.terrain)
			if stitched.terrain.has_trees():
				stitched.credits.append(TREES_CREDIT)
		return stitched
	if region_id.begins_with(AREA_PREFIX):
		var a: Dictionary = areas().get(region_id.trim_prefix(AREA_PREFIX), {})
		if a.is_empty():
			return null
		return area(region_id, str(a.get("title", region_id)), float(a["south"]), float(a["west"]), float(a["north"]), float(a["east"]),
			float(a["frame"]["lat"]), float(a["frame"]["lon"]))
	var dir := dir_of(region_id)
	var meta = _json(dir.path_join("region.json"))
	if not meta is Dictionary:
		if FileAccess.file_exists(dir.path_join("region.json")):
			push_error("Region: no readable region.json in %s" % dir)
		return null
	if int(meta.get("format", 0)) != FORMAT:
		push_error("Region: %s is format %s, this game reads %d" % [dir, meta.get("format"), FORMAT])
		return null
	var rows = _json(dir.path_join("roads.json"))
	if not rows is Dictionary or not rows.get("nodes") is Array or (rows["nodes"] as Array).size() < 2:
		push_error("Region: no readable roads.json in %s" % dir)
		return null
	var r := from_rows(rows)
	r.id = region_id
	r.title = str(meta.get("title", region_id))
	r.hash = str(meta.get("hash", ""))
	r.credits = meta.get("credits", [])
	r.theme = str(meta.get("theme", "hills"))
	r.sea = bool(meta.get("sea", false))
	r.country = str(meta.get("region", "world"))
	r.frame_lat = float(meta["frame"]["lat"])
	r.frame_lon = float(meta["frame"]["lon"])
	var b: Array = meta["bounds"]
	r.bounds = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	r.counts = meta.get("counts", {})
	var rows_b = _json(dir.path_join("buildings.json"))
	if rows_b is Array:
		r.buildings = rows_b
	var rows_p = _json(dir.path_join("pois.json"))
	if rows_p is Array:
		r.pois = rows_p
	var rows_l = _json(dir.path_join("landmarks.json"))
	if rows_l is Array:
		r.landmarks = rows_l
	var rows_t = _json(dir.path_join("places.json"))
	if rows_t is Array:
		r.places = rows_t
	var rows_s = _json(dir.path_join("spans.json"))
	if rows_s is Dictionary and rows_s.get("spans") is Array:
		r.spans = _spans_in(rows_s["spans"], Vector2(r.frame_lat, r.frame_lon))
	var rows_w = _json(dir.path_join("streams.json"))
	if rows_w is Dictionary and rows_w.get("streams") is Array:
		r.streams = _streams_in(rows_w["streams"], Vector2(r.frame_lat, r.frame_lon))
	r.terrain = RealTerrain.new(dir, meta)
	if r.terrain.live:
		r.terrain.set_buildings(r.buildings)   # (live heights level the ground under them; baked ones were levelled by the baker)
	var rows_tr = _json(dir.path_join("trees.json"))
	if rows_tr is Dictionary and rows_tr.get("cells") is Array:
		for row in rows_tr["cells"]:
			if row is Dictionary:
				r.terrain.add_trees(row)
		if r.terrain.has_trees() and not r.credits.has(TREES_CREDIT):
			r.credits.append(TREES_CREDIT)
	if PlaceProfile.bundled(region_id) and not r.credits.has(PlaceProfile.CREDIT):
		r.credits.append(PlaceProfile.CREDIT)
	return r


# ---------------------------------------------------------------------------- cells

## Cells: the world's grid of CELL_DEG squares (tools/region_bake.py --cell), each a region of its own (its roads,
## buildings, places, stops, landmarks and cover, in a frame at its middle; its heights live, HeightTiles). The game
## stitches the cells an area covers into one region (stitch): the player never meets a cell.
const CELL_DEG := 0.25
## Where cells are looked for (the tests add their own).
static var cell_dirs: Array[String] = ["res://data/cells", "user://cells"]
## Named areas made of cells, in an areas.json beside the cells: {name: {title, frame: {lat, lon}, south, west, north,
## east}}. An area's region id is "area:" and its name.
const AREA_PREFIX := "area:"
## An area of listed cells: "area:@" and the cells as ROW_COLUMN, comma between, its frame at the middle of the first. A
## journey anywhere in the world is one (AdventureJourney.cells_for), and so is what the Route planner TV shows close in.
const CELLS_PREFIX := "area:@"
## The most cells an area of listed cells may have (each is a couple of megabytes to stitch).
const MAX_AREA_CELLS := 64


## The region id of the area of `cells` (the first is where its frame is).
static func cells_area_id(cells: Array[Vector2i]) -> String:
	var parts := PackedStringArray()
	for c in cells:
		parts.append("%d_%d" % [c.x, c.y])
	return CELLS_PREFIX + ",".join(parts)


## The cells of an area of listed cells, in order; [] when `region_id` isn't one (or lists too many, or junk).
static func cells_of_area(region_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not region_id.begins_with(CELLS_PREFIX):
		return out
	for part in region_id.trim_prefix(CELLS_PREFIX).split(","):
		var rc := part.split("_")
		if rc.size() != 2 or not rc[0].is_valid_int() or not rc[1].is_valid_int():
			return [] as Array[Vector2i]
		var c := Vector2i(int(rc[0]), int(rc[1]))
		if c.x < 0 or c.x >= int(180.0 / CELL_DEG) or c.y < 0 or c.y >= int(360.0 / CELL_DEG) or out.has(c):
			return [] as Array[Vector2i]
		out.append(c)
	if out.size() > MAX_AREA_CELLS:
		return [] as Array[Vector2i]
	return out


## (lat, lon) of the middle of cell `c`.
static func cell_middle(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL_DEG - 90.0, (c.y + 0.5) * CELL_DEG - 180.0)


## The (row, column) of the cell that (lat, lon) is in: rows up from the south pole, columns east from 180 W.
static func cell_of(lat: float, lon: float) -> Vector2i:
	return Vector2i(floori((lat + 90.0) / CELL_DEG), floori((lon + 180.0) / CELL_DEG))


## The folder of cell (i, j), or "" when the game doesn't have it.
static func cell_dir(cell: Vector2i) -> String:
	for root in cell_dirs:
		var d := root.path_join("c%d_%d" % [cell.x, cell.y])
		if FileAccess.file_exists(d.path_join("region.json")):
			return d
	return ""


## The named areas made of cells, from every folder of cells: {name: {title, frame, south, west, north, east}}.
static func areas() -> Dictionary:
	var out := {}
	for root in cell_dirs:
		var v = _json(root.path_join("areas.json"))
		if v is Dictionary:
			for k in v:
				if not out.has(k):
					out[k] = v[k]
	return out


## Whether the game has any of area `name`'s cells, or can fetch them (the index last fetched has some: CellStore).
static func has_area(name: String) -> bool:
	var a: Dictionary = areas().get(name, {})
	if a.is_empty():
		return false
	var baked: Dictionary = CellStore.saved_index().get("cells", {})
	var lo := cell_of(float(a["south"]), float(a["west"]))
	var hi := cell_of(float(a["north"]) - 1e-9, float(a["east"]) - 1e-9)
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			var e = baked.get("%d_%d" % [i, j])
			if cell_dir(Vector2i(i, j)) != "" or (e is Dictionary and not bool(e.get("empty", false))):
				return true
	return false


## The extent of the region `region_id` in its own frame, without loading it when it's an area ("area:NAME": its box,
## from areas.json, so a plan for it can be checked before its cells are here); Rect2() when the game doesn't know it.
static func extent_of(region_id: String) -> Rect2:
	if not region_id.begins_with(AREA_PREFIX):
		var r := get_region(region_id)
		return r.bounds if r != null else Rect2()
	var a: Dictionary = areas().get(region_id.trim_prefix(AREA_PREFIX), {}) if not region_id.begins_with(CELLS_PREFIX) else _cells_box(region_id)
	if a.is_empty():
		return Rect2()
	var lat0 := float(a["frame"]["lat"])
	var lon0 := float(a["frame"]["lon"])
	var m := _metres_per_degree(lat0)
	var p0 := Vector2((float(a["west"]) - lon0) * m.y, -(float(a["north"]) - lat0) * m.x)
	var p1 := Vector2((float(a["east"]) - lon0) * m.y, -(float(a["south"]) - lat0) * m.x)
	return Rect2(p0, p1 - p0)


## Fetches the cells of area `region_id` ("area:NAME") the game hasn't got (CellStore): "" when it has them all, else why
## not. Blocks: a worker's job.
static func fetch_area(region_id: String, progress := Callable()) -> String:
	if region_id.begins_with(CELLS_PREFIX):
		var cells := cells_of_area(region_id)
		return CellStore.fetch_cells(cells, progress) if not cells.is_empty() else "That's not a part of the world."
	var a: Dictionary = areas().get(region_id.trim_prefix(AREA_PREFIX), {})
	if a.is_empty():
		return "This game doesn't know that part of the world."
	return CellStore.fetch_box(float(a["south"]), float(a["west"]), float(a["north"]), float(a["east"]), progress)


## The box and frame of an area of listed cells, as areas.json has a named area's: {frame, south, west, north, east}.
static func _cells_box(region_id: String) -> Dictionary:
	var cells := cells_of_area(region_id)
	if cells.is_empty():
		return {}
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var mid := cell_middle(cells[0])
	return {"frame": {"lat": mid.x, "lon": mid.y}, "south": lo.x * CELL_DEG - 90.0, "west": lo.y * CELL_DEG - 180.0,
		"north": (hi.x + 1) * CELL_DEG - 90.0, "east": (hi.y + 1) * CELL_DEG - 180.0}


## Forgets every area stitched so far (new cells came: CellStore), so each is stitched again with them.
static func forget_areas() -> void:
	_cache_lock.lock()
	for k in _cache.keys():
		if str(k).begins_with(AREA_PREFIX):
			_cache.erase(k)
	_cell_areas.clear()
	_cache_lock.unlock()


## The region of the cells the game has between latitudes `south` and `north` and longitudes `west` and `east`, in a
## frame at (`lat0`, `lon0`): see stitch. Null when it has none of them.
static func area(region_id: String, title: String, south: float, west: float, north: float, east: float, lat0: float, lon0: float) -> RealRegion:
	var a := cell_of(south, west)
	var b := cell_of(north - 1e-9, east - 1e-9)
	var dirs: Array[String] = []
	for i in range(a.x, b.x + 1):
		for j in range(a.y, b.y + 1):
			var d := cell_dir(Vector2i(i, j))
			if d != "":
				dirs.append(d)
	return stitch(region_id, title, dirs, lat0, lon0)


## One region of the cells in folders `dirs`, in a frame at (`lat0`, `lon0`) (metres from there, +x east, -z north, as the
## baker's frames are): each cell's frame is moved and scaled into it (both are the baker's flat frames, so a point's
## x is a scale and a shift of its x, and its z of its z); a road that runs from one cell into the next is in both, with
## the same Overture ids for its ends and its segment, and is joined up by them; a building, place or stop on an edge
## that both cells have is kept once. Its heights are live, its cover each cell's own. Null when no cell is readable.
static func stitch(region_id: String, title: String, dirs: Array[String], lat0: float, lon0: float) -> RealRegion:
	var ma := _metres_per_degree(lat0)
	var node_at := {}       # short id -> node index in the joined graph
	var nodes: Array = []
	var edges: Array = []
	var edge_seen := {}     # "segment|a|b" -> true
	var names: Array = [""]
	var name_at := {"": 0}
	var bans: Array = []
	var buildings: Array = []
	var building_seen := {}
	var pois: Array = []
	var landmarks: Array = []
	var places: Array = []
	var seen := {}
	var credits: Array = []
	var hashes: Array = []
	var sea := false
	var country := "world"
	var bounds := Rect2()
	var metas: Array = []
	var classes: Array = []
	var surfaces: Array = []
	for dir in dirs:
		var meta = _json(dir.path_join("region.json"))
		var rows = _json(dir.path_join("roads.json"))
		if not meta is Dictionary or not rows is Dictionary or not rows.get("ids") is Array:
			push_error("Region: %s isn't a readable cell" % dir)
			continue
		metas.append([dir, meta])
		classes = rows["classes"]
		surfaces = rows["surfaces"]
		var latc := float(meta["frame"]["lat"])
		var lonc := float(meta["frame"]["lon"])
		var mc := _metres_per_degree(latc)
		# A cell-frame (x, z) to the area's: x scaled by the ratio of a degree of longitude's metres, z of latitude's.
		var sx := ma.y / mc.y
		var ox := (lonc - lon0) * ma.y
		var sz := ma.x / mc.x
		var oz := -(latc - lat0) * ma.x
		var to_area := func(x: float, z: float) -> Vector2: return Vector2(ox + x * sx, oz + z * sz)
		hashes.append(str(meta.get("hash", "")))
		for c in meta.get("credits", []):
			if not credits.has(c):
				credits.append(c)
		sea = sea or bool(meta.get("sea", false))
		country = str(meta.get("region", country))
		var cb: Array = meta["bounds"]
		var r0: Vector2 = to_area.call(float(cb[0]), float(cb[1]))
		var r1: Vector2 = to_area.call(float(cb[2]), float(cb[3]))
		var rect := Rect2(r0, r1 - r0)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
		# The roads.
		var ids: Array = rows["ids"]
		var local := PackedInt32Array()
		for i in ids.size():
			var key := str(ids[i])
			if not node_at.has(key):
				var p: Vector2 = to_area.call(float(rows["nodes"][i][0]), float(rows["nodes"][i][1]))
				node_at[key] = nodes.size()
				nodes.append([p.x, p.y])
			local.append(int(node_at[key]))
		var cell_names: Array = rows["names"]
		var edge_local := {}
		var cell_edges: Array = rows["edges"]
		for ei in cell_edges.size():
			var e: Dictionary = cell_edges[ei]
			var a := local[int(e["a"])]
			var b := local[int(e["b"])]
			var key := "%s|%d|%d" % [str(e.get("g", "")), a, b]
			if edge_seen.has(key):
				edge_local[ei] = edge_seen[key]
				continue
			var nm := str(cell_names[int(e["n"])])
			if not name_at.has(nm):
				name_at[nm] = names.size()
				names.append(nm)
			var pts: Array = e["p"]
			var moved: Array = []
			for k in range(0, pts.size(), 2):
				var q: Vector2 = to_area.call(float(pts[k]), float(pts[k + 1]))
				moved.append_array([q.x, q.y])
			edge_seen[key] = edges.size()
			edge_local[ei] = edges.size()
			edges.append({"a": a, "b": b, "c": e["c"], "s": e["s"], "l": e["l"], "n": name_at[nm], "o": e.get("o", 0), "p": moved})
		for ban: Array in rows.get("bans", []):
			if edge_local.has(int(ban[0])) and edge_local.has(int(ban[2])):
				bans.append([edge_local[int(ban[0])], local[int(ban[1])], edge_local[int(ban[2])]])
		# What stands beside them.
		var rows_b = _json(dir.path_join("buildings.json"))
		for b: Array in (rows_b if rows_b is Array else []):
			var p: Vector2 = to_area.call(float(b[0]), float(b[1]))
			if _seen_building(building_seen, p, float(b[2]), float(b[3])):
				continue
			var row := b.duplicate()
			row[0] = snappedf(p.x, 0.1)
			row[1] = snappedf(p.y, 0.1)
			buildings.append(row)
		for list_name in ["pois", "landmarks", "places"]:
			var rows_x = _json(dir.path_join(list_name + ".json"))
			for d: Dictionary in (rows_x if rows_x is Array else []):
				var p: Vector2 = to_area.call(float(d["x"]), float(d["z"]))
				var key := "%s|%s|%s|%d|%d" % [list_name, d.get("kind", ""), d.get("name", ""), roundi(p.x / 10.0), roundi(p.y / 10.0)]
				if seen.has(key):
					continue
				seen[key] = true
				var row := d.duplicate()
				row["x"] = snappedf(p.x, 0.1)
				row["z"] = snappedf(p.y, 0.1)
				(pois if list_name == "pois" else (landmarks if list_name == "landmarks" else places)).append(row)
	if nodes.size() < 2:
		return null
	# (the classes and surfaces are the baker's own lists, the same in every cell)
	var r := from_rows({"nodes": nodes, "edges": edges, "bans": bans, "classes": classes, "surfaces": surfaces, "names": names})
	r.id = region_id
	r.title = title
	hashes.sort()
	r.hash = ("|".join(hashes)).sha256_text().substr(0, 16)
	if not credits.has(PlaceProfile.CREDIT):
		credits.append(PlaceProfile.CREDIT)   # (every cell of the world's store has its place profile)
	r.credits = credits
	r.sea = sea
	r.theme = "coastal" if sea else "hills"
	r.country = country
	r.frame_lat = lat0
	r.frame_lon = lon0
	r.bounds = bounds
	r.buildings = buildings
	r.pois = pois
	r.landmarks = landmarks
	r.places = places
	r.counts = {"nodes": nodes.size(), "edges": edges.size(), "buildings": buildings.size(), "cells": metas.size()}
	r.terrain = RealTerrain.new("", {"heights": "live", "frame": {"lat": lat0, "lon": lon0}})
	for m: Array in metas:
		r.terrain.add_cover_cell(str(m[0]), m[1])
	r.terrain.set_buildings(buildings)
	return r


## Spans [[kind, lat0, lon0, lat1, lon1] in 1e-5 degrees] (tools/span_bake.py) in the frame at `frame` (lat, lon).
static func _spans_in(rows: Array, frame: Vector2) -> Array:
	var out: Array = []
	for row in rows:
		if not row is Array or (row as Array).size() < 5:
			continue
		var a := to_frame(frame, float(row[1]) * 1e-5, float(row[2]) * 1e-5)
		var b := to_frame(frame, float(row[3]) * 1e-5, float(row[4]) * 1e-5)
		out.append([int(row[0]), a.x, a.y, b.x, b.y])
	return out


## Streams [[kind, lat, lon, dlat, dlon, ...] in 1e-5 degrees] (tools/stream_bake.py) in the frame at `frame` (lat, lon):
## [[kind, PackedVector2Array], ...].
static func _streams_in(rows: Array, frame: Vector2) -> Array:
	var out: Array = []
	for row in rows:
		if not row is Array or (row as Array).size() < 5:
			continue
		var pts := PackedVector2Array()
		var lat := int(row[1])
		var lon := int(row[2])
		pts.append(to_frame(frame, lat * 1e-5, lon * 1e-5))
		for k in range(3, (row as Array).size() - 1, 2):
			lat += int(row[k])
			lon += int(row[k + 1])
			pts.append(to_frame(frame, lat * 1e-5, lon * 1e-5))
		out.append([int(row[0]), pts])
	return out


## The rivers and streams of `cells` (their own files, CellStore.streams, fetched if this game hasn't the ones the world's
## index names) in the frame at `frame`. Blocks while it fetches: a worker's job.
static func _cell_streams(cells: Array[Vector2i], frame: Vector2) -> Array:
	var idx := CellStore.saved_index()
	var out: Array = []
	for c in cells:
		out.append_array(_streams_in(CellStore.streams("%d_%d" % [c.x, c.y], idx), frame))
	return out


## The trees of `cells` (their own files, CellStore.trees, fetched if this game hasn't the ones the world's index names)
## into `terrain`. Blocks while it fetches: a worker's job.
static func _cell_trees(cells: Array[Vector2i], terrain: RealTerrain) -> void:
	var idx := CellStore.saved_index()
	for c in cells:
		var row := CellStore.trees("%d_%d" % [c.x, c.y], idx)
		if not row.is_empty():
			terrain.add_trees(row)


## The bridges and tunnels of `cells` (from their sketch blocks, CellStore.sketch, fetched if this game hasn't the one
## the world's index names) in the frame at `frame`. Blocks while it fetches: a worker's job.
static func _cell_spans(cells: Array[Vector2i], frame: Vector2) -> Array:
	var idx := CellStore.saved_index()
	var blocks := {}
	for c in cells:
		var b := "%d_%d" % [c.x / 20, c.y / 20]
		if not blocks.has(b):
			blocks[b] = CellStore.sketch(b, idx).get("spans", {})
	var out: Array = []
	for c in cells:
		var rows = (blocks["%d_%d" % [c.x / 20, c.y / 20]] as Dictionary).get("%d_%d" % [c.x, c.y], [])
		if rows is Array:
			out.append_array(_spans_in(rows, frame))
	return out


## Whether a building of `w` by `d` metres stands within half a metre of `p` already (two cells that both have it
## put it a few centimetres apart: each rounds its own frame's metres); files it in `seen` (4 m squares) if not.
static func _seen_building(seen: Dictionary, p: Vector2, w: float, d: float) -> bool:
	var cell := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			for q: Vector4 in seen.get(cell + Vector2i(dx, dz), []):
				if Vector2(q.x, q.y).distance_to(p) < 0.5 and absf(q.z - w) < 0.2 and absf(q.w - d) < 0.2:
					return true
	if not seen.has(cell):
		seen[cell] = []
	(seen[cell] as Array).append(Vector4(p.x, p.y, w, d))
	return false


## A region's road graph from the rows of a roads.json ({nodes, edges, bans, classes, surfaces, names}): the loader's
## own step, and the tests', which make small graphs of their own.
static func from_rows(rows: Dictionary) -> RealRegion:
	var r := RealRegion.new()
	r.classes = rows["classes"]
	r.surfaces = rows["surfaces"]
	r.names = rows["names"]
	var nodes: Array = rows["nodes"]
	r.node_pos.resize(nodes.size())
	r.adjacent.resize(nodes.size())
	for i in nodes.size():
		r.node_pos[i] = Vector2(float(nodes[i][0]), float(nodes[i][1]))
		r.adjacent[i] = PackedInt32Array()
		var key := Vector2i(floori(r.node_pos[i].x / CELL), floori(r.node_pos[i].y / CELL))
		var cell: PackedInt32Array = r._grid.get(key, PackedInt32Array())
		cell.append(i)
		r._grid[key] = cell
	var edges: Array = rows["edges"]
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var a := int(e["a"])
		var bn := int(e["b"])
		r.edge_a.append(a)
		r.edge_b.append(bn)
		r.edge_class.append(int(e["c"]))
		r.edge_surface.append(int(e["s"]))
		r.edge_limit.append(int(e["l"]))
		r.edge_name.append(int(e["n"]))
		r.edge_oneway.append(int(e.get("o", 0)))
		var line := PackedVector2Array()
		line.append(r.node_pos[a])
		var p: Array = e["p"]
		for k in range(0, p.size(), 2):
			line.append(Vector2(float(p[k]), float(p[k + 1])))
		line.append(r.node_pos[bn])
		var len := 0.0
		for k in range(1, line.size()):
			len += line[k].distance_to(line[k - 1])
		r.edge_len.append(len)
		r.edge_line.append(line)
		var at_a := r.adjacent[a]
		at_a.append(ei)
		r.adjacent[a] = at_a
		var at_b := r.adjacent[bn]
		at_b.append(ei)
		r.adjacent[bn] = at_b
	for ban in rows.get("bans", []):
		r.bans[Vector3i(int(ban[0]), int(ban[1]), int(ban[2]))] = true
	r._find_components()
	return r


func _find_components() -> void:
	component.resize(node_pos.size())
	component.fill(-1)
	var sizes: Array[int] = []
	for n0 in node_pos.size():
		if component[n0] >= 0:
			continue
		var id_ := sizes.size()
		var stack := PackedInt32Array([n0])
		component[n0] = id_
		var count := 0
		while not stack.is_empty():
			var n := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			for ei in adjacent[n]:
				var m := other_end(ei, n)
				if component[m] < 0:
					component[m] = id_
					stack.append(m)
		sizes.append(count)
	component_size = PackedInt32Array(sizes)


func node_count() -> int:
	return node_pos.size()


func edge_count() -> int:
	return edge_a.size()


## The other node of edge `ei` from `node`.
func other_end(ei: int, node: int) -> int:
	return edge_b[ei] if edge_a[ei] == node else edge_a[ei]


## Whether edge `ei` may be driven starting from `node` (a one-way road only from its open end).
func passable(ei: int, node: int) -> bool:
	var o := edge_oneway[ei]
	return o == 0 or (o == 1 and edge_a[ei] == node) or (o == -1 and edge_b[ei] == node)


## Whether turning at `node` from edge `came` onto edge `onto` is prohibited.
func turn_banned(came: int, node: int, onto: int) -> bool:
	return not bans.is_empty() and bans.has(Vector3i(came, node, onto))


## The line of edge `ei` as it runs from `node` (one of its ends).
func line_from(ei: int, node: int) -> PackedVector2Array:
	var line := edge_line[ei]
	if edge_a[ei] == node:
		return line
	var out := PackedVector2Array()
	out.resize(line.size())
	for k in line.size():
		out[k] = line[line.size() - 1 - k]
	return out


## The class name (RoutePlanner.CLASS_COST has its cost) of edge `ei`.
func class_of(ei: int) -> String:
	return str(classes[edge_class[ei]])


func surface_of(ei: int) -> String:
	return str(surfaces[edge_surface[ei]])


## The road's name on edge `ei`: its own, or its class's ("Main road").
func name_of(ei: int) -> String:
	var n := str(names[edge_name[ei]])
	return n if n != "" else str(GENERIC_NAMES.get(class_of(ei), "Road"))


## The node nearest region-frame (x, z) within `within` metres, or -1.
func nearest_node(x: float, z: float, within := 500.0) -> int:
	var best := -1
	var best_d := within * within
	var span := int(ceil(within / CELL))
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	for gz in range(cz - span, cz + span + 1):
		for gx in range(cx - span, cx + span + 1):
			var cell: PackedInt32Array = _grid.get(Vector2i(gx, gz), PackedInt32Array())
			for n in cell:
				var d := node_pos[n].distance_squared_to(Vector2(x, z))
				if d < best_d or (d == best_d and (best < 0 or n < best)):
					best_d = d
					best = n
	return best


## The junction nearest (x, z) within `within` metres that is part of a road network of at least `min_nodes` junctions
## (not a stray bit of road), else just the nearest; -1 when there is none.
func nearest_connected(x: float, z: float, within := 500.0, min_nodes := 200) -> int:
	var best := -1
	var best_d := INF
	var fallback := -1
	var fallback_d := INF
	var span := int(ceil(within / CELL))
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	var at := Vector2(x, z)
	for gz in range(cz - span, cz + span + 1):
		for gx in range(cx - span, cx + span + 1):
			var cell: PackedInt32Array = _grid.get(Vector2i(gx, gz), PackedInt32Array())
			for n in cell:
				var d := node_pos[n].distance_to(at)
				if d > within:
					continue
				if d < fallback_d or (d == fallback_d and n < fallback):
					fallback_d = d
					fallback = n
				if component_size[component[n]] >= min_nodes and (d < best_d or (d == best_d and n < best)):
					best_d = d
					best = n
	return best if best >= 0 else fallback


## Region-frame (x, z) of a latitude and longitude, as the baker's frame has them (tools/route_bake.py Frame).
func geo_to_xz(lat: float, lon: float) -> Vector2:
	var m := _metres_per_degree(frame_lat)
	return Vector2((lon - frame_lon) * m.y, -(lat - frame_lat) * m.x)


## Latitude and longitude, as [lat, lon] (doubles: a Vector2 would only keep them to half a metre), of a region-frame point.
func xz_to_geo(x: float, z: float) -> Array[float]:
	var m := _metres_per_degree(frame_lat)
	return [frame_lat - z / m.x, frame_lon + x / m.y]


## What region `region_id` is called ("the roads round" a town for an area of listed cells, worked out without stitching
## it); "the map" when the game doesn't know it.
static func title_of(region_id: String) -> String:
	if region_id.begins_with(CELLS_PREFIX):
		var frame := frame_of(region_id)
		if frame == Vector2.INF:
			return "the map"
		WorldMap.load_world()
		var near := WorldMap.nearest_place(frame.x, frame.y)
		return "the roads round %s" % near if near != "" else "the roads here"
	if region_id.begins_with(AREA_PREFIX):
		return str(areas().get(region_id.trim_prefix(AREA_PREFIX), {}).get("title", "the map"))
	var r := get_region(region_id)
	return r.title if r != null else "the map"


## (lat, lon) of the frame of region `region_id` (an area's without loading it); Vector2.INF when the game doesn't know it.
static func frame_of(region_id: String) -> Vector2:
	if region_id.begins_with(AREA_PREFIX):
		var a: Dictionary = _cells_box(region_id) if region_id.begins_with(CELLS_PREFIX) else areas().get(region_id.trim_prefix(AREA_PREFIX), {})
		return Vector2(float(a["frame"]["lat"]), float(a["frame"]["lon"])) if not a.is_empty() else Vector2.INF
	var r := get_region(region_id)
	return Vector2(r.frame_lat, r.frame_lon) if r != null else Vector2.INF


## (x, z) in a frame at `frame` (lat, lon) of (lat, lon), as geo_to_xz has it.
static func to_frame(frame: Vector2, lat: float, lon: float) -> Vector2:
	var m := _metres_per_degree(frame.x)
	return Vector2((lon - frame.y) * m.y, -(lat - frame.x) * m.x)


## (lat, lon) of (x, z) in a frame at `frame` (lat, lon).
static func from_frame(frame: Vector2, x: float, z: float) -> Vector2:
	var m := _metres_per_degree(frame.x)
	return Vector2(frame.x - z / m.x, frame.y + x / m.y)


## (metres per degree of latitude, of longitude) at `lat`, from the WGS84 series.
static func _metres_per_degree(lat: float) -> Vector2:
	var p := deg_to_rad(lat)
	return Vector2(111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p),
		111412.84 * cos(p) - 93.5 * cos(3.0 * p) + 0.118 * cos(5.0 * p))
