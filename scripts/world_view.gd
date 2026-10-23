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
const ROUTE := JourneyView.ROUTE
const PIN := JourneyView.PIN
const PIN_FIRST := JourneyView.PIN_FIRST
## Closer in than this (metres across), the roads of the cells in view are fetched and drawn.
const ROADS_SPAN := 60000.0
## Closer in than this, the finer coast (1:10m, else 1:50m) and the rivers.
const DETAIL_SPAN := 4000000.0
## The most town names on the map at once.
const MAX_LABELS := 28
## A touch on the world (not on roads) looks this many times closer there.
const TOUCH_ZOOM := 4.0

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
var _roads_bbox := PackedFloat32Array()
var _want := ""                # the region id the view wants for its roads ("" when too far out)
var _task := -1
var _task_id := ""
var _task_result: Array = []   # [region, bbox, note] when the worker is done
var _task_lock := Mutex.new()
var _progress := ""
var _world_task := -1


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _ready() -> void:
	if not WorldMap.loaded():
		_world_task = WorkerThreadPool.add_task(WorldMap.load_world)


func _exit_tree() -> void:
	for t in [_task, _world_task]:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)
	_task = -1
	_world_task = -1


## Shows `span_m` metres across, about (`at_lat`, `at_lon`).
func show_view(at_lat: float, at_lon: float, span_m: float) -> void:
	if is_equal_approx(at_lat, lat) and is_equal_approx(at_lon, lon) and is_equal_approx(span_m, span):
		return
	lat = at_lat
	lon = at_lon
	span = span_m
	_want_roads()
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
	_start_task()


func _start_task() -> void:
	if _task >= 0 or _want == "" or (roads != null and roads.id == _want) or _task_id == _want:
		return
	var id := _want
	_task_id = id
	_progress = "Fetching the roads here..."
	note = _progress
	_task = WorkerThreadPool.add_task(func(): _load_roads(id))


## On a worker: the cells of `id` the index has baked are fetched, then stitched; else a bundled region there.
func _load_roads(id: String) -> void:
	var cells := RealRegion.cells_of_area(id)
	var idx := CellStore.index()
	var states := {}
	for c in cells:
		var st := CellStore.state_of(c, idx)
		states[st] = int(states.get(st, 0)) + 1
	var why := ""
	if states.has("baked"):
		why = CellStore.fetch_cells(cells, func(done: int, total: int):
			_task_lock.lock()
			_progress = "Fetching the roads here (%d of %d)..." % [done, total]
			_task_lock.unlock())
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
	var bbox := _edge_boxes(r) if r != null else PackedFloat32Array()
	_task_lock.lock()
	_task_result = [r, bbox, said, id]
	_task_lock.unlock()


static func _edge_boxes(r: RealRegion) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(r.edge_count() * 4)
	for ei in r.edge_count():
		var line := r.edge_line[ei]
		var lo := line[0]
		var hi := line[0]
		for p in line:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		out[ei * 4] = lo.x
		out[ei * 4 + 1] = lo.y
		out[ei * 4 + 2] = hi.x
		out[ei * 4 + 3] = hi.y
	return out


## Takes in what the workers have done (call it every frame or so). True when the map should be drawn again.
func poll() -> bool:
	var again := false
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
			if res.size() == 4:
				roads = res[0]
				_roads_bbox = res[1]
				note = str(res[2]) if _want != "" else ""
			again = true
			_start_task()
	if size.x > 10.0 and _want == "" and span <= ROADS_SPAN:
		_want_roads()
	return again


## Whether the view is waiting for anything (the world's map, the roads).
func busy() -> bool:
	return _world_task >= 0 or _task >= 0


## Whether the roads in view are drawn, so a touch there pins.
func roads_shown() -> bool:
	return roads != null and span <= ROADS_SPAN


# ---------------------------------------------------------------------------- touch

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			click(mb.position)


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
	asked_view.emit(g.x, g.y, maxf(span / TOUCH_ZOOM, AdventureJourney.SPAN_MIN))


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
		var lakes := WorldMap.mesh("lakes")
		if lakes != null:
			draw_mesh(lakes, null, Transform2D(), SEA)
	draw_set_transform(Vector2.ZERO)
	var view_m := Rect2(m0 - size * 0.5 / k, size / k)
	if detail:
		_draw_lines("rivers", view_m, k, m0, RIVER, 1.5)
	_draw_lines("borders", view_m, k, m0, BORDER, 1.5)
	# The roads in view, the small ones first so the big ones lie over them.
	if roads_shown():
		_draw_roads()
	# The planned road.
	if route_geo.size() > 1:
		var pts := PackedVector2Array()
		for g in route_geo:
			pts.append(to_screen(g.x, g.y))
		draw_polyline(pts, Color(0.1, 0.05, 0.05, 0.6), 9.0 if big else 7.0, true)
		draw_polyline(pts, ROUTE, 6.0 if big else 4.5, true)
	_draw_names()
	_draw_pins()
	if note != "":
		var font := ThemeDB.fallback_font
		var fs := 18 if big else 14
		var w := font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(Vector2((size.x - w) * 0.5 - 10.0, size.y - fs - 22.0), Vector2(w + 20.0, fs + 14.0))
		draw_rect(box, NOTE)
		draw_string(font, box.position + Vector2(10.0, fs + 3.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_lines(layer: String, view_m: Rect2, k: float, m0: Vector2, col: Color, width: float) -> void:
	var lines := WorldMap.lines(layer)
	var boxes := WorldMap.line_boxes(layer)
	for i in lines.size():
		var b := i * 4
		if boxes[b + 2] < view_m.position.x or boxes[b] > view_m.end.x or boxes[b + 3] < view_m.position.y or boxes[b + 1] > view_m.end.y:
			continue
		var line: PackedVector2Array = lines[i]
		var pts := PackedVector2Array()
		pts.resize(line.size())
		for j in line.size():
			pts[j] = (line[j] - m0) * k + size * 0.5
		draw_polyline(pts, col, width, true)


func _draw_roads() -> void:
	var xf := _frame_xf(Vector2(roads.frame_lat, roads.frame_lon))
	var inv := xf.affine_inverse()
	var a := inv * Vector2.ZERO
	var b := inv * size
	var view := Rect2(a, Vector2.ZERO).expand(b)
	var scale := xf.x.x   # pixels per metre
	var order: Array = JourneyView.ROAD_LOOK.keys()
	order.reverse()
	for cls: String in order:
		var look: Array = JourneyView.ROAD_LOOK[cls]
		if scale < float(look[2]):
			continue
		var ci := roads.classes.find(cls)
		if ci < 0:
			continue
		var width := maxf(float(look[1]) * clampf(scale * 60.0, 0.7, 2.0), 1.0) * (1.4 if big else 1.0)
		for ei in roads.edge_count():
			if roads.edge_class[ei] != ci:
				continue
			var e := ei * 4
			if _roads_bbox[e + 2] < view.position.x or _roads_bbox[e] > view.end.x or _roads_bbox[e + 3] < view.position.y or _roads_bbox[e + 1] > view.end.y:
				continue
			var line := roads.edge_line[ei]
			var pts := PackedVector2Array()
			var step := 1 if scale > 0.05 else 2
			for j in range(0, line.size() - 1, step):
				pts.append(xf * line[j])
			pts.append(xf * line[line.size() - 1])
			draw_polyline(pts, look[0], width, true)


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
	for p: Array in WorldMap.places():
		if shown[0] >= MAX_LABELS:
			break
		try.call(to_screen(float(p[1]), float(p[2])), str(p[0]), fs_big if int(p[3]) >= 1000000 else fs_small, 3.0)
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
