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

var id := ""
var title := ""
var hash := ""
var credits: Array = []
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
	_cache_lock.unlock()
	return r


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _load(region_id: String) -> RealRegion:
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
	r.terrain = RealTerrain.new(dir, meta)
	return r


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


## (metres per degree of latitude, of longitude) at `lat`, from the WGS84 series.
static func _metres_per_degree(lat: float) -> Vector2:
	var p := deg_to_rad(lat)
	return Vector2(111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p),
		111412.84 * cos(p) - 93.5 * cos(3.0 * p) + 0.118 * cos(5.0 * p))
