class_name WorldView
extends Control
## The world on the Route planner TV (RouteTv): the land, lakes, rivers and borders of the whole world (WorldMap), the
## names of its towns and cities, and close in the roads of the cells in view, fetched (CellStore) and stitched on a
## worker (an area of listed cells, RealRegion.CELLS_PREFIX). Over them the crew's pins and the planned road.
##
## It shows the view it is given (show_view: a middle and the metres across), the crew's (Shed.route_tv): it never
## moves itself. A touch asks: `asked_pin(lat, lon, name)` where there are roads to pin on, `asked_unpin(i)` on a pin,
## else `asked_view(lat, lon, span)` to look closer there.

signal changed
signal asked_pin(lat: float, lon: float, name: String)
signal asked_unpin(i: int)
signal asked_view(lat: float, lon: float, span: float)

const SEA := Color(0.56, 0.74, 0.86)
const LAND := Color(0.91, 0.88, 0.79)
const RIVER := Color(0.42, 0.6, 0.8)
const BORDER := Color(0.6, 0.4, 0.45)
const INK := Color(0.2, 0.17, 0.13)
const NOTE := Color(0.1, 0.1, 0.12, 0.8)
## The bar along the foot while the map waits (shown_progress): its height (px) and its empty part's colour.
const BAR_H := 6.0
const BAR_BACK := Color(1.0, 1.0, 1.0, 0.15)
const ROUTE := Color(0.82, 0.1, 0.55)
const PIN := Color(0.78, 0.1, 0.1)
const PIN_FIRST := Color(0.15, 0.55, 0.25)
## The look of each class of road: colour, width (px), and the scale (px per metre) it first shows at.
const ROAD_LOOK := {
	"motorway": [Color(0.8, 0.35, 0.2), 3.2, 0.0], "trunk": [Color(0.82, 0.42, 0.2), 3.0, 0.0],
	"primary": [Color(0.88, 0.58, 0.25), 2.6, 0.0], "secondary": [Color(0.93, 0.78, 0.4), 2.2, 0.0],
	"tertiary": [Color(1, 1, 1, 0.92), 1.7, 0.0], "unclassified": [Color(1, 1, 1, 0.8), 1.4, 0.012],
	"residential": [Color(1, 1, 1, 0.55), 1.0, 0.04], "living_street": [Color(1, 1, 1, 0.5), 1.0, 0.06],
	"track": [Color(0.5, 0.35, 0.2, 0.85), 1.0, 0.04],
}
## How much one turn of the mouse wheel zooms (the Esc menu's full-screen planner).
const WHEEL_ZOOM := 1.5
## Closer in than this (metres across), the roads of the cells in view are fetched and drawn.
const ROADS_SPAN := 60000.0
## Between ROADS_SPAN and this (metres across), the sketch of the main roads of the baked parts of the world in view.
const SKETCH_SPAN := 1500000.0
## The most 5 degree blocks of sketch fetched for a view.
const SKETCH_BLOCKS := 12
## The sketch's look by class (motorway, trunk, A road): colour and width (px).
const SKETCH_LOOK := [[Color(0.8, 0.35, 0.2), 2.4], [Color(0.82, 0.42, 0.2), 2.0], [Color(0.9, 0.62, 0.32), 1.2]]
## Further out than this (metres across), the sketch leaves out the A roads: only the motorways and trunk roads.
const SKETCH_A_SPAN := 250000.0
## Closer in than this (metres across), the coast is the cells' own (tools/coast_bake.py, in the sketch's blocks)
## where the world's store has it, not Natural Earth's, a kilometre or more out beside the roads.
const COAST_SPAN := 300000.0
## Closer in than this, the finer coast (1:10m, else 1:50m) and the rivers.
const DETAIL_SPAN := 4000000.0
## The most town names on the map at once.
const MAX_LABELS := 28
## A touch on the world (not on roads) looks this many times closer there.
const TOUCH_ZOOM := 4.0
## A touch this near (px; on the big screen, more) a main road of the sketch pins on it.
const SKETCH_TOUCH := 14.0
const SKETCH_TOUCH_BIG := 22.0
## A pin on the sketch is named after the town or city nearest it within this far (m).
const SKETCH_NAME_M := 15000.0

var lat := 30.0
var lon := 0.0
var span := 30000000.0
## Bigger pins and names, for a screen read from a distance.
var big := true
## The planned road, as (lat, lon) points.
var route_geo := PackedVector2Array()
## What the map is waiting for, or why it has no roads here ("" when all is well): shown along its foot.
var note := ""
## The roads in view: the stitched cells (or a bundled region where the game has no cells), and its id.
var roads: RealRegion
## The roads in view as each class's line pieces, ready to draw in one go: {class index: [a, b, a, b...]} in the roads'
## frame (made on the worker with them: _road_segments).
var _road_segs := {}
var _want := ""                # the region id the view wants for its roads ("" when too far out)
var _task := -1
var _task_id := ""
var _task_result: Array = []   # [region, bbox, note] when the worker is done
var _task_lock := Mutex.new()
var _progress := ""
var _progress_frac := -1.0     # how far the worker is through fetching the roads (0 to 1), -1 when it can't say
var _shown_tick := -1          # the tick the foot's clock and bar were last drawn at (see poll)
var _world_task := -1
## The cells in view nobody has mapped (baked) yet, for the Survey button.
var unmapped: Array[Vector2i] = []
var _stale := false            # the roads in view are to be fetched again (a survey's cells came)
var _look_task := -1           # looking at the world's index while a survey is on
var _look_at := -1000000
## The sketch of the main roads: block ("R_C") -> [[class, PackedVector2Array (mercator)], ...], and each line's box.
var _sketch := {}
var _sketch_boxes := {}
## The coast close in: block -> [corner (mercator, the block's north-west), sea (the cells it knows, as triangles),
## land, holes (sea inside the land)], meshes in mercator units from the corner (so they're exact close in).
var _coast := {}
var _sketch_task := -1
var _sketch_got := {}           # what the worker read: block -> [lines, boxes]
var _sketch_lock := Mutex.new()


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _ready() -> void:
	if not WorldMap.loaded():
		_world_task = WorkerThreadPool.add_task(WorldMap.load_world)


func _exit_tree() -> void:
	for t in [_task, _world_task, _look_task, _sketch_task]:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)
	_task = -1
	_world_task = -1
	_look_task = -1
	_sketch_task = -1


## Shows `span_m` metres across, about (`at_lat`, `at_lon`).
func show_view(at_lat: float, at_lon: float, span_m: float) -> void:
	if is_equal_approx(at_lat, lat) and is_equal_approx(at_lon, lon) and is_equal_approx(span_m, span):
		return
	lat = at_lat
	lon = at_lon
	span = span_m
	_want_roads()
	_want_sketch()
	queue_redraw()


# ---------------------------------------------------------------------------- where things are

## Screen pixels per mercator unit.
func _k() -> float:
	return size.x / (span / WorldMap.metres_per_unit(lat))


func to_screen(at_lat: float, at_lon: float) -> Vector2:
	return (WorldMap.mercator(at_lat, at_lon) - WorldMap.mercator(lat, lon)) * _k() + size * 0.5


## (lat, lon) under screen point `s`.
func to_geo(s: Vector2) -> Vector2:
	return WorldMap.geo_of(WorldMap.mercator(lat, lon) + (s - size * 0.5) / _k())


## From a region's frame (metres east, south of `frame` (lat, lon)) to the screen: near enough a scale and a shift over
## the few tens of kilometres the roads are drawn across.
func _frame_xf(frame: Vector2) -> Transform2D:
	var k := _k()
	var m := RealRegion._metres_per_degree(frame.x)
	var sx := k / (360.0 * m.y)
	var sz := k / (360.0 * m.x * cos(deg_to_rad(frame.x)))
	return Transform2D(Vector2(sx, 0.0), Vector2(0.0, sz), to_screen(frame.x, frame.y))


## The view's corners, (south, west, north, east).
func _box() -> Array:
	var a := to_geo(Vector2.ZERO)
	var b := to_geo(size)
	return [b.x, a.y, a.x, b.y]


# ---------------------------------------------------------------------------- the roads in view

## Which roads the view wants: the cells under it when close in (the middle cell first), else none.
func _want_roads() -> void:
	var want := ""
	if span <= ROADS_SPAN and size.x > 10.0:
		var box := _box()
		var lo := RealRegion.cell_of(box[0], box[1])
		var hi := RealRegion.cell_of(box[2], box[3])
		var mid := RealRegion.cell_of(lat, lon)
		var cells: Array[Vector2i] = [mid]
		for i in range(lo.x, hi.x + 1):
			for j in range(lo.y, hi.y + 1):
				if Vector2i(i, j) != mid:
					cells.append(Vector2i(i, j))
		if cells.size() <= 16:
			want = RealRegion.cells_area_id(cells)
	_want = want
	if want == "":
		note = ""
		unmapped.clear()
	_start_task()


func _start_task() -> void:
	if _task >= 0 or _want == "" or (not _stale and ((roads != null and roads.id == _want) or _task_id == _want)):
		return
	var id := _want
	_task_id = id
	_stale = false
	_progress = "Fetching the roads here..."
	_progress_frac = -1.0
	note = _progress
	_task = WorkerThreadPool.add_task(func(): _load_roads(id))


## On a worker: the cells of `id` the index has baked are fetched, then stitched; else a bundled region there.
func _load_roads(id: String) -> void:
	var cells := RealRegion.cells_of_area(id)
	var idx := CellStore.index()
	var states := {}
	var nobody: Array[Vector2i] = []
	for c in cells:
		var st := CellStore.state_of(c, idx)
		states[st] = int(states.get(st, 0)) + 1
		if st == "unknown":
			nobody.append(c)
	var why := ""
	if states.has("baked"):
		why = CellStore.fetch_cells(cells, func(done: int, total: int):
			_task_lock.lock()
			_progress = "Fetching the roads here (%d of %d)..." % [done, total]
			_progress_frac = float(done) / float(maxi(total, 1))
			_task_lock.unlock())
	_task_lock.lock()
	_progress = "Drawing the roads here..."
	_progress_frac = -1.0
	_task_lock.unlock()
	var r: RealRegion = null
	var said := ""
	if states.has("here") or states.has("baked"):
		r = RealRegion.get_region(id)
		if r != null and r.edge_count() == 0:
			r = null
		said = why
	if r == null:
		var mid := RealRegion.cell_middle(cells[0])
		var bundled := AdventureJourney.bundled_at(mid.x, mid.y)
		if bundled != "":
			r = RealRegion.get_region(bundled)
			said = ""
		elif said == "":
			said = "Nobody has mapped the roads here yet." if not states.has("sea") or states.size() > 1 else ""
	var segs := _road_segments(r) if r != null else {}
	_task_lock.lock()
	_task_result = [r, segs, said, id, nobody]
	_task_lock.unlock()


## `r`'s roads as each class's line pieces end to end ({class index: [a, b, a, b...]}), so a redraw draws a class at a
## time (draw_multiline) rather than a road at a time: the map stays smooth however many roads are in view.
static func _road_segments(r: RealRegion) -> Dictionary:
	var out := {}
	for ei in r.edge_count():
		var ci := int(r.edge_class[ei])
		if not out.has(ci):
			out[ci] = PackedVector2Array()
		var line := r.edge_line[ei]
		var segs: PackedVector2Array = out[ci]
		var at := segs.size()
		segs.resize(at + (line.size() - 1) * 2)
		for j in line.size() - 1:
			segs[at + j * 2] = line[j]
			segs[at + j * 2 + 1] = line[j + 1]
		out[ci] = segs
	return out


## Takes in what the workers have done (call it every frame or so). True when the map should be drawn again.
func poll() -> bool:
	var again := _poll_sketch()
	if _world_task >= 0 and WorkerThreadPool.is_task_completed(_world_task):
		WorkerThreadPool.wait_for_task_completion(_world_task)
		_world_task = -1
		again = true
	if _task >= 0:
		_task_lock.lock()
		var said := _progress
		_task_lock.unlock()
		if said != note and _want != "" and said != "":
			note = said
			again = true
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_task_lock.lock()
			var res := _task_result
			_task_result = []
			_progress = ""
			_task_lock.unlock()
			if res.size() == 5:
				roads = res[0]
				_road_segs = res[1]
				note = str(res[2]) if _want != "" else ""
				unmapped = res[4] if _want != "" else ([] as Array[Vector2i])
			again = true
			_start_task()
	if size.x > 10.0 and _want == "" and span <= ROADS_SPAN:
		_want_roads()
	# (while it's waiting, the clock and the bar along its foot are drawn again every second, or half second as it sweeps)
	var frac := shown_progress()
	var tick := -1 if is_nan(frac) else int(Time.get_ticks_msec() / (500 if frac < 0.0 else 1000))
	if tick != _shown_tick:
		_shown_tick = tick
		again = true
	return _poll_survey() or again


## The crew's survey over the view: the world's index looked at every Survey.look_every seconds, and the roads fetched
## again once any of its cells are in it. True when the map should be drawn again.
func _poll_survey() -> bool:
	if _look_task >= 0:
		if not WorkerThreadPool.is_task_completed(_look_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_look_task)
		_look_task = -1
		var idx := CellStore.saved_index()
		for c in surveying():
			if CellStore.state_of(c, idx) != "unknown":
				_stale = true   # (its cells came: fetch the roads here again, and its block's sketch)
				_start_task()
				_sketch.erase("%d_%d" % [c.x / 20, c.y / 20])
				_want_sketch()
				return true
		return false
	if not surveying().is_empty() and Time.get_ticks_msec() - _look_at >= int(Survey.look_every * 1000.0):
		_look_at = Time.get_ticks_msec()
		_look_task = WorkerThreadPool.add_task(func(): CellStore.index(true))
	return false


## The cells in view the crew's survey is baking.
func surveying() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var here := RealRegion.cells_of_area(_want)
	for key in Survey.going():
		var rc := key.split("_")
		var c := Vector2i(int(rc[0]), int(rc[1]))
		if here.has(c) and unmapped.has(c):
			out.append(c)
	return out


## What the map says along its foot: a survey going on here (how long it's been, about how long to go, when the index
## was last looked at), or what the surveyors said, or the note.
func shown_note() -> String:
	var here := surveying()
	var s: Dictionary = Shed.route_tv.get("survey", {})
	var ago := Time.get_unix_time_from_system() - float(s.get("since", 0.0))
	if not here.is_empty() and _task < 0:   # (once its cells come, what the fetching says)
		var cells := "%d cell%s" % [here.size(), "" if here.size() == 1 else "s"]
		var looked := "looking for them now" if _look_task >= 0 \
			else "last looked %d s ago" % int((Time.get_ticks_msec() - _look_at) / 1000.0)
		if ago < Survey.TAKES:
			return "Surveying the roads here (%s): %s gone, about %d min to go. %s." % [cells, _clock(ago),
				ceili((Survey.TAKES - ago) / 60.0), looked[0].to_upper() + looked.substr(1)]
		return "Surveying the roads here (%s): %s gone, longer than usual. Still looking every minute; %s." % [cells,
			_clock(ago), looked]
	if not s.is_empty() and (s.get("cells", []) as Array).is_empty() and str(s.get("said", "")) != "" and ago < 90.0 and _want != "":
		return str(s["said"])
	return note


## The box the map's note `said` is drawn in along its foot (without its bar): as wide as it needs up to the map's
## width less a margin, wrapped onto more lines past that, so it always fits.
func note_box(said: String) -> Rect2:
	var font := ThemeDB.fallback_font
	var fs := _note_size()
	var most := maxf(size.x - 60.0, 80.0)
	var w := minf(font.get_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0, most)
	var tall := font.get_multiline_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, w, fs).y
	return Rect2(Vector2((size.x - w) * 0.5 - 10.0, size.y - tall - 22.0), Vector2(w + 20.0, tall + 14.0))


## The note's font size (px): a little larger on the full screen map.
func _note_size() -> int:
	return 14 if big else 11


## How far along what the map is waiting for is, for the bar along its foot: 0 to 1, or -1 when it can't say (the bar
## then sweeps to and fro, so it's plain nothing has stuck); NAN when it isn't waiting.
func shown_progress() -> float:
	if not surveying().is_empty() and _task < 0:
		var s: Dictionary = Shed.route_tv.get("survey", {})
		var ago := Time.get_unix_time_from_system() - float(s.get("since", 0.0))
		return minf(ago / Survey.TAKES, 0.95) if ago < Survey.TAKES else -1.0
	if _task >= 0:
		_task_lock.lock()
		var f := _progress_frac
		_task_lock.unlock()
		return f
	var s: Dictionary = Shed.route_tv.get("survey", {})
	if not s.is_empty() and (s.get("cells", []) as Array).is_empty() and str(s.get("said", "")).ends_with("...") \
			and Time.get_unix_time_from_system() - float(s.get("since", 0.0)) < 90.0:
		return -1.0   # (asking the surveyors)
	return NAN


## `secs` as minutes and seconds ("4:07").
static func _clock(secs: float) -> String:
	return "%d:%02d" % [int(secs) / 60, int(secs) % 60]


## Whether the view is waiting for anything (the world's map, the roads, the world's index, the main roads' sketch and
## the coast).
func busy() -> bool:
	return _world_task >= 0 or _task >= 0 or _look_task >= 0 or _sketch_task >= 0


# ---------------------------------------------------------------------------- the main roads' sketch

## Whether the view is far enough out (but not too far) for the sketch of the main roads.
func sketch_shown() -> bool:
	return span > ROADS_SPAN and span <= SKETCH_SPAN


## Whether the view is close enough in for the cells' own coast.
func coast_shown() -> bool:
	return span <= COAST_SPAN


## The 5 degree blocks ("R_C") under the view, for the sketch or the coast: [] too far out (or too many).
func sketch_blocks() -> Array[String]:
	var out: Array[String] = []
	if span > SKETCH_SPAN or size.x < 10.0:
		return out
	var box := _box()
	var lo := RealRegion.cell_of(box[0], box[1])
	var hi := RealRegion.cell_of(box[2], box[3])
	for i in range(lo.x / 20, hi.x / 20 + 1):
		for j in range(lo.y / 20, hi.y / 20 + 1):
			out.append("%d_%d" % [i, j])
	return out if out.size() <= SKETCH_BLOCKS else ([] as Array[String])


## Starts fetching (on a worker) the sketch blocks in view the view hasn't got.
func _want_sketch() -> void:
	if _sketch_task >= 0:
		return
	var want: Array[String] = []
	for b in sketch_blocks():
		if not _sketch.has(b):
			want.append(b)
	if want.is_empty():
		return
	for b in want:
		_sketch[b] = []   # (asked for: not again while this view lasts)
	_sketch_task = WorkerThreadPool.add_task(func():
		var idx := CellStore.index()
		var got := {}
		for b in want:
			var sketch := CellStore.sketch(b, idx)
			var cells: Dictionary = sketch.get("cells", {})
			var lines: Array = []
			var boxes := PackedFloat32Array()
			for cell in cells:
				for line in cells[cell]:
					var flat: Array = line[1]
					var pts := PackedVector2Array()
					var la := 0.0
					var lo := 0.0
					for i in range(0, flat.size() - 1, 2):
						la = float(flat[i]) if i == 0 else la + float(flat[i])
						lo = float(flat[i + 1]) if i == 0 else lo + float(flat[i + 1])
						pts.append(WorldMap.mercator(la * 1e-5, lo * 1e-5))
					var r := Rect2(pts[0], Vector2.ZERO)
					for p in pts:
						r = r.expand(p)
					lines.append([int(line[0]), pts])
					boxes.append_array([r.position.x, r.position.y, r.end.x, r.end.y])
			got[b] = [lines, boxes, coast_meshes(b, sketch.get("land", {}))]
		_sketch_lock.lock()
		_sketch_got = got
		_sketch_lock.unlock())


## Takes in the sketch blocks the worker read. True when the map should be drawn again.
func _poll_sketch() -> bool:
	if _sketch_task < 0 or not WorkerThreadPool.is_task_completed(_sketch_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_sketch_task)
	_sketch_task = -1
	_sketch_lock.lock()
	var got := _sketch_got
	_sketch_got = {}
	_sketch_lock.unlock()
	for b in got:
		_sketch[b] = got[b][0]
		_sketch_boxes[b] = got[b][1]
		_coast[b] = got[b][2]
	_want_sketch()   # (the view may have moved on meanwhile)
	return not got.is_empty()


## Block `block`'s coast meshes (see _coast) from its cells' coasts `land` ({"ROW_COL": "all", "none" or {rings, holes}},
## tools/coast_bake.py): [] when it has none. Made on a worker.
static func coast_meshes(block: String, land: Dictionary) -> Array:
	if land.is_empty():
		return []
	var rc := block.split("_")
	var corner := WorldMap.mercator(int(rc[0]) * 5.0 - 85.0, int(rc[1]) * 5.0 - 180.0)
	var sea := PackedVector2Array()
	var ground := PackedVector2Array()
	var holes := PackedVector2Array()
	for cell: String in land:
		var c := cell.split("_")
		var s := int(c[0]) * RealRegion.CELL_DEG - 90.0
		var w := int(c[1]) * RealRegion.CELL_DEG - 180.0
		var a := WorldMap.mercator(s + RealRegion.CELL_DEG, w) - corner
		var d := WorldMap.mercator(s, w + RealRegion.CELL_DEG) - corner
		var quad := PackedVector2Array([a, Vector2(d.x, a.y), d, a, d, Vector2(a.x, d.y)])
		sea.append_array(quad)
		var v = land[cell]
		if v is String:
			if v == "all":
				ground.append_array(quad)
			continue
		if not v is Dictionary:
			continue
		for ring in v.get("rings", []):
			ground.append_array(_triangles(ring, corner))
		for ring in v.get("holes", []):
			holes.append_array(_triangles(ring, corner))
	return [corner, _mesh_of(sea), _mesh_of(ground), _mesh_of(holes)]


## Ring [lat, lon, dlat, dlon, ...] (1e-5 degrees, steps after the first) as triangles in mercator units from `corner`.
static func _triangles(flat: Array, corner: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var la := 0.0
	var lo := 0.0
	for i in range(0, flat.size() - 1, 2):
		la = float(flat[i]) if i == 0 else la + float(flat[i])
		lo = float(flat[i + 1]) if i == 0 else lo + float(flat[i + 1])
		var p := WorldMap.mercator(la * 1e-5, lo * 1e-5) - corner
		if pts.is_empty() or not p.is_equal_approx(pts[pts.size() - 1]):
			pts.append(p)
	var out := PackedVector2Array()
	if pts.size() < 3:
		return out
	var corners := Geometry2D.triangulate_polygon(pts)
	if corners.is_empty():
		# (a ring the triangulator won't take, cut along the cell's edge: its convex pieces instead)
		for part in Geometry2D.decompose_polygon_in_convex(pts):
			for k in range(1, part.size() - 1):
				out.append_array([part[0], part[k], part[k + 1]])
		return out
	for k in corners:
		out.append(pts[k])
	return out


static func _mesh_of(tris: PackedVector2Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if tris.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The cells' own coast over the world's land, where the blocks in view have it: each cell's box the sea, then its land.
func _draw_coast(k: float, m0: Vector2) -> void:
	for b in sketch_blocks():
		var coast: Array = _coast.get(b, [])
		if coast.is_empty():
			continue
		draw_set_transform(size * 0.5 + (coast[0] - m0) * k, 0.0, Vector2(k, k))
		draw_mesh(coast[1], null, Transform2D(), SEA)
		draw_mesh(coast[2], null, Transform2D(), LAND)
		draw_mesh(coast[3], null, Transform2D(), SEA)
	draw_set_transform(Vector2.ZERO)


func _draw_sketch(view_m: Rect2, k: float, m0: Vector2) -> void:
	var to_px := Transform2D(Vector2(k, 0.0), Vector2(0.0, k), size * 0.5 - m0 * k)
	for cls in [2, 1, 0]:   # (A roads first, so the motorways lie over them)
		if cls == 2 and span > SKETCH_A_SPAN:
			continue
		var look: Array = SKETCH_LOOK[cls]
		for b in sketch_blocks():
			var lines: Array = _sketch.get(b, [])
			var boxes: PackedFloat32Array = _sketch_boxes.get(b, PackedFloat32Array())
			for i in lines.size():
				if int(lines[i][0]) != cls:
					continue
				var e := i * 4
				if boxes[e + 2] < view_m.position.x or boxes[e] > view_m.end.x or boxes[e + 3] < view_m.position.y or boxes[e + 1] > view_m.end.y:
					continue
				draw_polyline(to_px * (lines[i][1] as PackedVector2Array), look[0], float(look[1]) * (1.3 if big else 1.0), true)


## Whether the roads in view are drawn, so a touch there pins.
func roads_shown() -> bool:
	return roads != null and span <= ROADS_SPAN


# ---------------------------------------------------------------------------- touch

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			click(mb.position)
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# Closer or further out about the pointer: the point under it stays put.
			var k := WHEEL_ZOOM if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_ZOOM
			var under := to_geo(mb.position)
			var to_span := clampf(span / k, AdventureJourney.SPAN_MIN, AdventureJourney.SPAN_MAX)
			var m := WorldMap.mercator(under.x, under.y) - (mb.position - size * 0.5) / (size.x / (to_span / WorldMap.metres_per_unit(lat)))
			var mid := WorldMap.geo_of(m)
			asked_view.emit(mid.x, mid.y, to_span)
			accept_event()


## A touch at screen point `s`: takes the pin there off, or pins the road there, or looks closer.
func click(s: Vector2) -> void:
	var pins: Array = Shed.journey.get("pins", [])
	var reach := 24.0 if big else 15.0
	for i in pins.size():
		var g := AdventureJourney.pin_geo(Shed.journey, i)
		if g != Vector2.INF and to_screen(g.x, g.y).distance_to(s) <= reach:
			asked_unpin.emit(i)
			return
	var g := to_geo(s)
	if roads_shown():
		var frame := Vector2(roads.frame_lat, roads.frame_lon)
		var xz := RealRegion.to_frame(frame, g.x, g.y)
		var n := roads.nearest_connected(xz.x, xz.y, AdventureJourney.SNAP_M)
		if n >= 0:
			var at := RealRegion.from_frame(frame, roads.node_pos[n].x, roads.node_pos[n].y)
			asked_pin.emit(at.x, at.y, AdventureJourney.place_name(roads, n))
			return
		note = "There's no road near there."
		queue_redraw()
		changed.emit()
		return
	if sketch_shown():
		# On a main road of the sketch: pinned there (the plan finds the road itself once its cells come).
		var on := sketch_road_at(s)
		if on != Vector2.INF:
			asked_pin.emit(on.x, on.y, sketch_name(on.x, on.y))
			return
	asked_view.emit(g.x, g.y, maxf(span / TOUCH_ZOOM, AdventureJourney.SPAN_MIN))


## A name for a pin on the sketch at (lat, lon): the world's town or city nearest it within SKETCH_NAME_M, else "".
static func sketch_name(at_lat: float, at_lon: float) -> String:
	for p in WorldMap.places():
		if WorldMap._ground_metres(at_lat, at_lon, float(p[1]), float(p[2])) <= SKETCH_NAME_M:
			return str(p[0])   # (the most important first)
	return ""


## (lat, lon) on the main road of the sketch drawn nearest screen point `s`, within SKETCH_TOUCH; INF when none is.
func sketch_road_at(s: Vector2) -> Vector2:
	var k := _k()
	var m0 := WorldMap.mercator(lat, lon)
	var reach := SKETCH_TOUCH_BIG if big else SKETCH_TOUCH
	var best := Vector2.INF
	var best_d := reach
	var at_m := m0 + (s - size * 0.5) / k
	var pad := reach / k
	for b in sketch_blocks():
		var lines: Array = _sketch.get(b, [])
		var boxes: PackedFloat32Array = _sketch_boxes.get(b, PackedFloat32Array())
		for i in lines.size():
			if int(lines[i][0]) == 2 and span > SKETCH_A_SPAN:
				continue   # (not drawn this far out)
			var e := i * 4
			if boxes[e + 2] < at_m.x - pad or boxes[e] > at_m.x + pad or boxes[e + 3] < at_m.y - pad or boxes[e + 1] > at_m.y + pad:
				continue
			var line: PackedVector2Array = lines[i][1]
			for j in line.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(at_m, line[j], line[j + 1])
				var d := (q - at_m).length() * k
				if d < best_d:
					best_d = d
					best = q
	return WorldMap.geo_of(best) if best != Vector2.INF else Vector2.INF


# ---------------------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	if size.x < 10.0:
		return
	var k := _k()
	var m0 := WorldMap.mercator(lat, lon)
	# The world: land, then lakes, then rivers and borders, in mercator units.
	draw_set_transform(size * 0.5 - m0 * k, 0.0, Vector2(k, k))
	var detail := span <= DETAIL_SPAN
	var land := WorldMap.mesh("land" if detail else "land_low")
	if land != null:
		draw_mesh(land, null, Transform2D(), LAND)
	# Close in, the cells' own coast over it where the world's store has it (then the lakes over that).
	if coast_shown():
		_draw_coast(k, m0)
		draw_set_transform(size * 0.5 - m0 * k, 0.0, Vector2(k, k))
	if land != null:
		var lakes := WorldMap.mesh("lakes")
		if lakes != null:
			draw_mesh(lakes, null, Transform2D(), SEA)
	draw_set_transform(Vector2.ZERO)
	var view_m := Rect2(m0 - size * 0.5 / k, size / k)
	if detail:
		_draw_lines("rivers", view_m, k, m0, RIVER, 1.5)
	_draw_lines("borders", view_m, k, m0, BORDER, 1.5)
	# The roads in view, the small ones first so the big ones lie over them; further out, the main roads' sketch.
	if roads_shown():
		_draw_roads()
	elif sketch_shown():
		_draw_sketch(view_m, k, m0)
	# The planned road.
	if route_geo.size() > 1:
		var pts := PackedVector2Array()
		for g in route_geo:
			pts.append(to_screen(g.x, g.y))
		draw_polyline(pts, Color(0.1, 0.05, 0.05, 0.6), 9.0 if big else 7.0, true)
		draw_polyline(pts, ROUTE, 6.0 if big else 4.5, true)
	_draw_names()
	_draw_pins()
	var said := shown_note()
	if said != "":
		var font := ThemeDB.fallback_font
		var fs := _note_size()
		var box := note_box(said)
		var w := box.size.x - 20.0
		var frac := shown_progress()
		if not is_nan(frac):
			# (waiting: a bar along the box's foot, filling as it goes, or sweeping to and fro when it can't say how far)
			box = Rect2(box.position - Vector2(0.0, BAR_H + 4.0), box.size + Vector2(0.0, BAR_H + 4.0))
		draw_rect(box, NOTE)
		draw_multiline_string(font, box.position + Vector2(10.0, fs + 3.0), said, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, Color.WHITE)
		if not is_nan(frac):
			var bar := Rect2(box.position + Vector2(10.0, box.size.y - BAR_H - 8.0), Vector2(box.size.x - 20.0, BAR_H))
			draw_rect(bar, BAR_BACK)
			if frac >= 0.0:
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), ROUTE)
			else:
				var t := pingpong(float(Time.get_ticks_msec() / 500) / 8.0, 1.0)
				draw_rect(Rect2(bar.position + Vector2((bar.size.x * 0.75) * t, 0.0), Vector2(bar.size.x * 0.25, bar.size.y)), ROUTE)


func _draw_lines(layer: String, view_m: Rect2, k: float, m0: Vector2, col: Color, width: float) -> void:
	var lines := WorldMap.lines(layer)
	var boxes := WorldMap.line_boxes(layer)
	var to_px := Transform2D(Vector2(k, 0.0), Vector2(0.0, k), size * 0.5 - m0 * k)
	for i in lines.size():
		var b := i * 4
		if boxes[b + 2] < view_m.position.x or boxes[b] > view_m.end.x or boxes[b + 3] < view_m.position.y or boxes[b + 1] > view_m.end.y:
			continue
		draw_polyline(to_px * (lines[i] as PackedVector2Array), col, width, true)


func _draw_roads() -> void:
	var xf := _frame_xf(Vector2(roads.frame_lat, roads.frame_lon))
	var scale := xf.x.x   # pixels per metre
	var order: Array = ROAD_LOOK.keys()
	order.reverse()
	for cls: String in order:
		var look: Array = ROAD_LOOK[cls]
		if scale < float(look[2]):
			continue
		var ci := roads.classes.find(cls)
		if ci < 0 or not _road_segs.has(ci):
			continue
		var width := maxf(float(look[1]) * clampf(scale * 60.0, 0.7, 2.0), 1.0) * (1.4 if big else 1.0)
		# (the whole class at once, placed on the screen in one go: off the screen is clipped; the main roads' edges
		# smoothed, not the many small roads', which would cost more than the rest of the map put together)
		draw_multiline(xf * (_road_segs[ci] as PackedVector2Array), look[0], width, float(look[2]) <= 0.0)


## The names of the biggest places in view (the world's towns and cities, and close in the roads' own towns and
## villages), as many as fit without one over another.
func _draw_names() -> void:
	var font := ThemeDB.fallback_font
	var taken: Array[Rect2] = []
	var screen := Rect2(Vector2.ZERO, size)
	var shown := [0]   # (an array: a lambda's own copy of a number wouldn't count)
	var try := func(at: Vector2, name: String, fs: int, dot: float) -> void:
		if shown[0] >= MAX_LABELS or not screen.has_point(at):
			return
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(at + Vector2(-dot, -fs * 0.5), Vector2(w + dot * 2.0 + 6.0, fs + 4.0))
		for t in taken:
			if t.intersects(r):
				return
		taken.append(r)
		shown[0] += 1
		draw_circle(at, dot, INK)
		draw_string(font, at + Vector2(dot + 4.0, fs * 0.35), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	var fs_big := 20 if big else 15
	var fs_small := 16 if big else 12
	if roads_shown():
		for p: Dictionary in roads.places:
			if str(p["kind"]) == "town":
				var g := RealRegion.from_frame(Vector2(roads.frame_lat, roads.frame_lon), float(p["x"]), float(p["z"]))
				try.call(to_screen(g.x, g.y), str(p["name"]), fs_big, 3.5)
	# (each place's point on the screen in one go, and only those on it looked at further)
	var world := WorldMap.places()
	var at := Transform2D(Vector2(_k(), 0.0), Vector2(0.0, _k()), size * 0.5 - WorldMap.mercator(lat, lon) * _k()) * WorldMap.place_points()
	for i in at.size():
		if shown[0] >= MAX_LABELS:
			break
		if screen.has_point(at[i]):
			var p: Array = world[i]
			try.call(at[i], str(p[0]), fs_big if int(p[3]) >= 1000000 else fs_small, 3.0)
	if roads_shown():
		for p: Dictionary in roads.places:
			if str(p["kind"]) == "village":
				var g := RealRegion.from_frame(Vector2(roads.frame_lat, roads.frame_lon), float(p["x"]), float(p["z"]))
				try.call(to_screen(g.x, g.y), str(p["name"]), fs_small, 2.5)


func _draw_pins() -> void:
	var pins: Array = Shed.journey.get("pins", [])
	var r := 18.0 if big else 13.0
	for i in pins.size():
		var g := AdventureJourney.pin_geo(Shed.journey, i)
		if g == Vector2.INF:
			continue
		var at := to_screen(g.x, g.y)
		draw_circle(at, r, Color(1, 1, 1, 0.95))
		draw_circle(at, r - 2.5, PIN_FIRST if i == 0 else PIN)
		draw_string(ThemeDB.fallback_font, at + Vector2(-6, 6) * (r / 13.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * r / 13.0), Color.WHITE)
