class_name JourneyView
extends Control
## The map of a real region (RealRegion) the crew plans a journey on: the land shaded by height, every road, the towns,
## the crew's pins (Shed.journey) and the planned road. A click pins a place (or takes a pin off); the wheel zooms it
## and the right button drags it, and zoom_by, pan_by and fit do the same for a screen with no wheel (the TVs' Route planner channel,
## RouteTv). Used by the full-screen JourneyMap and by RouteTv.

signal moved

const SEA := Color(0.56, 0.74, 0.86)
const INK := Color(0.2, 0.17, 0.13)
const ROUTE := Color(0.82, 0.1, 0.55)
const PIN := Color(0.78, 0.1, 0.1)
const PIN_FIRST := Color(0.15, 0.55, 0.25)
## Metres a cell of the land's shading covers.
const SHADE_CELL := 100.0
const MIN_SCALE := 0.004
const MAX_SCALE := 1.2
## The look of each class of road: colour, width (px), and the scale (px per metre) it first shows at.
const ROAD_LOOK := {
	"motorway": [Color(0.8, 0.35, 0.2), 3.2, 0.0], "trunk": [Color(0.82, 0.42, 0.2), 3.0, 0.0],
	"primary": [Color(0.88, 0.58, 0.25), 2.6, 0.0], "secondary": [Color(0.93, 0.78, 0.4), 2.2, 0.0],
	"tertiary": [Color(1, 1, 1, 0.92), 1.7, 0.0], "unclassified": [Color(1, 1, 1, 0.8), 1.4, 0.012],
	"residential": [Color(1, 1, 1, 0.55), 1.0, 0.04], "living_street": [Color(1, 1, 1, 0.5), 1.0, 0.06],
	"track": [Color(0.5, 0.35, 0.2, 0.85), 1.0, 0.04],
}

var region: RealRegion
## Bigger pins and names, for a screen read from a distance.
var big := false
var route_pts := PackedVector2Array()
var _centre := Vector2.ZERO
var _scale := 0.02
var _fitted := false
var _drag := false
var _hover := -1
var shade: ImageTexture
var _shade_task := -1
var _shade_image: Image
var _shade_lock := Mutex.new()
var _bbox := PackedFloat32Array()


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _exit_tree() -> void:
	if _shade_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_shade_task)
		_shade_task = -1


## Shows region `r` (the land is shaded on a worker thread, and comes in when it is done).
func show_region(r: RealRegion) -> void:
	if r == region:
		return
	region = r
	shade = null
	_bbox.clear()
	_fitted = false
	if region == null:
		queue_redraw()
		return
	_make_bboxes()
	if _shade_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_shade_task)
		_shade_task = -1
	var rr := region
	_shade_task = WorkerThreadPool.add_task(func():
		var img := shade_image(rr)
		_shade_lock.lock()
		_shade_image = img
		_shade_lock.unlock())
	fit()
	queue_redraw()


## Takes in the land picture once the worker has made it (call now and then). True when it just came in.
func poll_shade() -> bool:
	if _shade_task < 0 or not WorkerThreadPool.is_task_completed(_shade_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_shade_task)
	_shade_task = -1
	_shade_lock.lock()
	var img := _shade_image
	_shade_lock.unlock()
	if img == null:
		return false
	shade = ImageTexture.create_from_image(img)
	queue_redraw()
	return true


func _make_bboxes() -> void:
	_bbox.resize(region.edge_count() * 4)
	for ei in region.edge_count():
		var line := region.edge_line[ei]
		var lo := line[0]
		var hi := line[0]
		for p in line:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		_bbox[ei * 4] = lo.x
		_bbox[ei * 4 + 1] = lo.y
		_bbox[ei * 4 + 2] = hi.x
		_bbox[ei * 4 + 3] = hi.y


## Shows all of the region.
func fit() -> void:
	var box := size if size.x > 10.0 else Vector2(900, 640)
	_scale = clampf(minf(box.x / region.bounds.size.x, box.y / region.bounds.size.y) * 0.96, MIN_SCALE, MAX_SCALE)
	_centre = region.bounds.get_center()
	_fitted = size.x > 10.0
	queue_redraw()
	moved.emit()


func zoom_by(factor: float, about := Vector2(-1, -1)) -> void:
	var at := size * 0.5 if about.x < 0.0 else about
	var before := to_world(at)
	_scale = clampf(_scale * factor, MIN_SCALE, MAX_SCALE)
	_centre += before - to_world(at)
	queue_redraw()
	moved.emit()


## Moves the view by a fraction of its size (to the right and down for positive).
func pan_by(frac: Vector2) -> void:
	_centre += Vector2(frac.x * size.x, frac.y * size.y) / _scale
	queue_redraw()
	moved.emit()


## Looks at world point `p` (and zooms in to at least `at_scale`).
func look_at_point(p: Vector2, at_scale := 0.05) -> void:
	_centre = p
	_scale = clampf(maxf(_scale, at_scale), MIN_SCALE, MAX_SCALE)
	queue_redraw()
	moved.emit()


func to_screen(p: Vector2) -> Vector2:
	return (p - _centre) * _scale + size * 0.5


func to_world(s: Vector2) -> Vector2:
	return (s - size * 0.5) / _scale + _centre


func _gui_input(event: InputEvent) -> void:
	if region == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			zoom_by(1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2, mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			click(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag:
			_centre -= mm.relative / _scale
		var n := _node_near(mm.position)
		if _drag or n != _hover:
			_hover = n
			queue_redraw()


## The junction under screen point `s` (within 24 px), or -1.
func _node_near(s: Vector2) -> int:
	var w := to_world(s)
	return region.nearest_node(w.x, w.y, 24.0 / _scale)


## A click at screen point `s`: takes the pin there off, or puts a new one down.
func click(s: Vector2) -> void:
	var journey: Dictionary = Shed.journey if str(Shed.journey.get("region", "")) == region.id else {}
	var pins: Array = journey.get("pins", [])
	var reach := 22.0 if big else 14.0
	for i in pins.size():
		if to_screen(Vector2(float(pins[i]["x"]), float(pins[i]["z"]))).distance_to(s) <= reach:
			Shed.request({"a": "adventure_unpin", "i": i})
			return
	var w := to_world(s)
	Shed.request({"a": "adventure_pin", "region": region.id, "x": w.x, "z": w.y})


func _draw() -> void:
	if region == null:
		return
	if not _fitted and size.x > 10.0:
		fit()
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	var corner := to_screen(region.bounds.position)
	if shade != null:
		draw_texture_rect(shade, Rect2(corner, region.bounds.size * _scale), false)
	var view := Rect2(to_world(Vector2.ZERO), size / _scale)
	# The roads, the small ones first so the big ones lie over them.
	var order: Array = ROAD_LOOK.keys()
	order.reverse()
	for cls: String in order:
		var look: Array = ROAD_LOOK[cls]
		if _scale < float(look[2]):
			continue
		var ci := region.classes.find(cls)
		var width := maxf(float(look[1]) * clampf(_scale * 60.0, 0.7, 2.0), 1.0) * (1.4 if big else 1.0)
		for ei in region.edge_count():
			if region.edge_class[ei] != ci:
				continue
			var b := ei * 4
			if _bbox[b + 2] < view.position.x or _bbox[b] > view.end.x or _bbox[b + 3] < view.position.y or _bbox[b + 1] > view.end.y:
				continue
			var line := region.edge_line[ei]
			var pts := PackedVector2Array()
			var step := 1 if _scale > 0.05 else 2
			for k in range(0, line.size() - 1, step):
				pts.append(to_screen(line[k]))
			pts.append(to_screen(line[line.size() - 1]))
			draw_polyline(pts, look[0], width, true)
	# The planned road.
	if route_pts.size() > 1:
		var pts := PackedVector2Array()
		for p in route_pts:
			pts.append(to_screen(p))
		draw_polyline(pts, Color(0.1, 0.05, 0.05, 0.6), 9.0 if big else 7.0, true)
		draw_polyline(pts, ROUTE, 6.0 if big else 4.5, true)
	# The towns and villages, named once there is room.
	if _scale >= 0.012:
		for p: Dictionary in region.places:
			var at := to_screen(Vector2(float(p["x"]), float(p["z"])))
			if not Rect2(Vector2.ZERO, size).has_point(at):
				continue
			if str(p["kind"]) == "village" and _scale < 0.03:
				continue
			var fs := (19 if str(p["kind"]) == "town" else 15) if big else (15 if str(p["kind"]) == "town" else 12)
			draw_circle(at, 3.0 if str(p["kind"]) == "town" else 2.0, INK)
			draw_string(ThemeDB.fallback_font, at + Vector2(6, 5), str(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	# Where the pointer would pin.
	if _hover >= 0:
		var hp := to_screen(region.node_pos[_hover])
		draw_arc(hp, 9.0, 0.0, TAU, 20, Color(0.1, 0.1, 0.1, 0.8), 2.0)
		var hname := AdventureJourney.place_name(region, _hover)
		if hname != "":
			draw_string(ThemeDB.fallback_font, hp + Vector2(12, -10), hname, HORIZONTAL_ALIGNMENT_LEFT, -1, 18 if big else 14, INK)
	# The pins.
	var journey: Dictionary = Shed.journey if str(Shed.journey.get("region", "")) == region.id else {}
	var pins: Array = journey.get("pins", [])
	var r := 18.0 if big else 13.0
	for i in pins.size():
		var p: Dictionary = pins[i]
		var at := to_screen(Vector2(float(p["x"]), float(p["z"])))
		var col := PIN_FIRST if i == 0 else PIN
		draw_circle(at, r, Color(1, 1, 1, 0.95))
		draw_circle(at, r - 2.5, col)
		draw_string(ThemeDB.fallback_font, at + Vector2(-6, 6) * (r / 13.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * r / 13.0), Color.WHITE)


## The land as a picture: sea, and ground shaded by height and slope (lit from the north-west). Any thread.
static func shade_image(r: RealRegion) -> Image:
	if r.terrain != null and r.terrain.live:
		r.terrain.fetch_area(r.bounds)   # (a live region's land comes from the map tiles: this runs on a worker)
	var w := maxi(int(r.bounds.size.x / SHADE_CELL), 2)
	var h := maxi(int(r.bounds.size.y / SHADE_CELL), 2)
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for j in h:
		for i in w:
			var x := r.bounds.position.x + (i + 0.5) * SHADE_CELL
			var z := r.bounds.position.y + (j + 0.5) * SHADE_CELL
			var v := r.terrain.height(x, z)
			heights[j * w + i] = -1.0 if is_nan(v) else v
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for j in h:
		for i in w:
			var v := heights[j * w + i]
			if v <= 0.4:
				img.set_pixel(i, j, Color(SEA.r, SEA.g, SEA.b, 0.0))
				continue
			var l := heights[j * w + maxi(i - 1, 0)]
			var u := heights[maxi(j - 1, 0) * w + i]
			var rr := heights[j * w + mini(i + 1, w - 1)]
			var d := heights[mini(j + 1, h - 1) * w + i]
			l = v if l <= 0.4 else l
			u = v if u <= 0.4 else u
			rr = v if rr <= 0.4 else rr
			d = v if d <= 0.4 else d
			var light := clampf(0.5 + ((l - rr) + (u - d)) / (2.0 * SHADE_CELL) * 1.6, 0.25, 1.0)
			var base := Color(0.62, 0.74, 0.5).lerp(Color(0.78, 0.7, 0.5), smoothstep(40.0, 260.0, v)).lerp(Color(0.62, 0.55, 0.45), smoothstep(260.0, 700.0, v))
			img.set_pixel(i, j, Color(base.r * light, base.g * light, base.b * light, 1.0))
	return img
