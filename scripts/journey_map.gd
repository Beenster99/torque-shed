class_name JourneyMap
extends Control
## The shed's map of a real region, where the crew plans a journey together: click to pin a start, stops and a finish
## (anyone's pin shows to everyone, see AdventureJourney), pick the style of ride, and see the road the game plans
## between the pins (RoutePlanner, on a worker thread as you go). The host starts the ride from here, for everyone.
##
## The wheel zooms, dragging with the right or middle button moves the map, a click on a pin takes it off.

signal closed

const PAPER := Color(0.93, 0.89, 0.78)
const INK := Color(0.2, 0.17, 0.13)
const SEA := Color(0.56, 0.74, 0.86)
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
const MODE_TEXT := {
	"main": ["Quick", "the main roads, the sensible way"],
	"scenic": ["Scenic", "the quiet back roads, a bit slower"],
	"tracks": ["Tracks", "gravel and dirt wherever there are any"],
}
const REFRESH := 0.25

var region: RealRegion
## The article of the magazine this is opened from (the adventure's `mag`).
var article_id := ""
var _canvas: Control
var _pin_box: VBoxContainer
var _search: LineEdit
var _found: VBoxContainer
var _facts: Label
var _note: Label
var _start: Button
var _clear: Button
var _mode_buttons := {}
var _centre := Vector2.ZERO
var _scale := 0.02
var _fitted := false
var _drag := false
var _hover := -1
var _shade: ImageTexture
var _shade_task := -1
var _shade_image: Image
var _shade_lock := Mutex.new()
var _bbox := PackedFloat32Array()
var _route_pts := PackedVector2Array()
var _route_key := ""
var _sig := ""
var _timer := 0.0


func _ready() -> void:
	name = "JourneyMap"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28.0
	row.offset_top = 28.0
	row.offset_right = -28.0
	row.offset_bottom = -28.0
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_content_margin_all(4)
	style.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 2.2
	row.add_child(frame)
	_canvas = Control.new()
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_map_input)
	_canvas.resized.connect(func(): _canvas.queue_redraw())
	frame.add_child(_canvas)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	side.add_child(UITheme.title("Plan a journey", 26))
	var how := UITheme.label("Click the map to pin a start, stops and a finish: everyone in the shed sees the pins. Click a pin to take it off. "
		+ "The wheel zooms; drag the map to move it.", 14, Color(0.85, 0.85, 0.85))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(how)
	_pin_box = VBoxContainer.new()
	_pin_box.add_theme_constant_override("separation", 3)
	side.add_child(_pin_box)
	_search = LineEdit.new()
	_search.placeholder_text = "Find a town, village or place"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill_found())
	side.add_child(_search)
	_found = VBoxContainer.new()
	_found.add_theme_constant_override("separation", 2)
	side.add_child(_found)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	side.add_child(modes)
	for m in ["main", "scenic", "tracks"]:
		var b := Button.new()
		b.toggle_mode = true
		b.text = str(MODE_TEXT[m][0])
		b.tooltip_text = str(MODE_TEXT[m][1])
		b.pressed.connect(func(): Shed.request({"a": "adventure_mode", "mode": m}))
		modes.add_child(b)
		_mode_buttons[m] = b
	_facts = UITheme.label("", 15, Color(0.92, 0.92, 0.92))
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_facts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_facts)
	_note = UITheme.label("", 14, Color(0.9, 0.8, 0.5))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_note)
	_clear = Button.new()
	_clear.text = "Clear the pins"
	_clear.pressed.connect(func(): Shed.request({"a": "adventure_clear"}))
	side.add_child(_clear)
	_start = Button.new()
	_start.text = "Start this ride for everyone"
	_start.pressed.connect(start)
	side.add_child(_start)
	var close := Button.new()
	Controls.bind_text(close, "Fold the map away ({menu})")
	close.pressed.connect(func(): closed.emit())
	side.add_child(close)


func _exit_tree() -> void:
	if _shade_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_shade_task)
		_shade_task = -1


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		closed.emit()


## Opens the map of region `region_id` (the one the crew's pins are on, if they have some).
func open(region_id: String) -> void:
	region = RealRegion.get_region(region_id)
	visible = true
	if region == null:
		_facts.text = "This game doesn't have that map."
		return
	if _bbox.is_empty():
		_make_bboxes()
	if _shade == null and _shade_task < 0:
		_shade_task = WorkerThreadPool.add_task(func():
			var img := shade_image(region)
			_shade_lock.lock()
			_shade_image = img
			_shade_lock.unlock())
	_fit()
	_sig = ""
	_fill_found()
	refresh()


## The places that match what's typed (or, with nothing typed, a few suggested destinations), each a button that pins
## it: the region's towns and villages, then its named places to stop and landmarks.
func _fill_found() -> void:
	for c in _found.get_children():
		c.queue_free()
	if region == null:
		return
	var hits := find_places(region, _search.text)
	if hits.is_empty():
		_found.add_child(UITheme.label("Nothing by that name here." if _search.text.strip_edges() != "" else "", 13, Color(0.7, 0.7, 0.7)))
		return
	if _search.text.strip_edges() == "":
		_found.add_child(UITheme.label("Worth a ride:", 13, Color(0.7, 0.7, 0.7)))
	for h: Dictionary in hits:
		var b := Button.new()
		b.text = "%s  (%s)" % [str(h["name"]), str(h["kind"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Pin %s" % str(h["name"])
		b.pressed.connect(func():
			Shed.request({"a": "adventure_pin", "region": region.id, "x": float(h["x"]), "z": float(h["z"])})
			_centre = Vector2(float(h["x"]), float(h["z"]))
			_scale = maxf(_scale, 0.05)
			_canvas.queue_redraw())
		_found.add_child(b)


## The region's places whose names contain `text` (any case), up to `limit`: towns and villages first (the bigger
## first), then places to stop and landmarks with names. With nothing typed: suggested destinations, the biggest towns
## and villages, then the lighthouses, castles and beaches, spread about the region.
static func find_places(region: RealRegion, text: String, limit := 8) -> Array:
	var q := text.strip_edges().to_lower()
	var out: Array = []
	var seen := {}
	var rank := {"town": 0, "village": 1, "lighthouse": 2, "castle": 2, "viewpoint": 3, "beach": 3, "peak": 4, "cafe": 5, "inn": 5, "pub": 5, "fuel": 6, "campsite": 5, "layby": 7, "worship": 4}
	var rows: Array = []
	for p: Dictionary in region.places:
		rows.append({"name": str(p["name"]), "kind": str(p["kind"]), "x": float(p["x"]), "z": float(p["z"]), "pop": int(p.get("pop", 0))})
	for m: Dictionary in region.landmarks:
		if str(m.get("name", "")) != "":
			rows.append({"name": str(m["name"]), "kind": str(m["kind"]), "x": float(m["x"]), "z": float(m["z"]), "pop": 0})
	for m: Dictionary in region.pois:
		if str(m.get("name", "")) != "":
			rows.append({"name": str(m["name"]), "kind": str(m["kind"]), "x": float(m["x"]), "z": float(m["z"]), "pop": 0})
	for row: Dictionary in rows:
		if q != "" and not str(row["name"]).to_lower().contains(q):
			continue
		if q == "" and int(rank.get(row["kind"], 9)) > 2:
			continue
		var key := "%s|%s" % [row["name"], row["kind"]]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(row)
	out.sort_custom(func(a, b):
		var ra := int(rank.get(a["kind"], 9))
		var rb := int(rank.get(b["kind"], 9))
		if ra != rb:
			return ra < rb
		if int(a["pop"]) != int(b["pop"]):
			return int(a["pop"]) > int(b["pop"])
		return str(a["name"]) < str(b["name"]))
	if q == "":
		# Spread about: no two suggestions within 3 km of each other.
		var spread: Array = []
		for row: Dictionary in out:
			var near := false
			for s: Dictionary in spread:
				if Vector2(float(s["x"]) - float(row["x"]), float(s["z"]) - float(row["z"])).length() < 3000.0:
					near = true
					break
			if not near:
				spread.append(row)
		out = spread
	return out.slice(0, limit)


func _process(delta: float) -> void:
	if not visible or region == null:
		return
	if _shade_task >= 0 and WorkerThreadPool.is_task_completed(_shade_task):
		WorkerThreadPool.wait_for_task_completion(_shade_task)
		_shade_task = -1
		_shade_lock.lock()
		var img := _shade_image
		_shade_lock.unlock()
		if img != null:
			_shade = ImageTexture.create_from_image(img)
			_canvas.queue_redraw()
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		AdventurePlans.poll()
		var sig := _signature()
		if sig != _sig:
			refresh()


func _signature() -> String:
	var plan := AdventureJourney.plan_of(Shed.journey)
	var res := AdventurePlans.result(plan) if not plan.is_empty() else {}
	return "%s|%s|%s|%s" % [JSON.stringify(Shed.journey), str(not res.is_empty()), str(Shed.is_authority()), str(Adventure.active())]


## Brings the panel and the route up to date with the board and the plan.
func refresh() -> void:
	_sig = _signature()
	for c in _pin_box.get_children():
		c.queue_free()
	var journey: Dictionary = Shed.journey if str(Shed.journey.get("region", "")) == region.id else {}
	var pins: Array = journey.get("pins", [])
	if pins.is_empty():
		var empty := UITheme.label("No pins yet.", 15, Color(0.7, 0.7, 0.7))
		_pin_box.add_child(empty)
	for i in pins.size():
		var p: Dictionary = pins[i]
		var line := HBoxContainer.new()
		var label := UITheme.label("%d  %s" % [i + 1, _pin_label(i, pins.size(), p)], 15, Color(0.95, 0.95, 0.95))
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 200.0
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		line.add_child(label)
		var x := Button.new()
		x.text = "x"
		x.tooltip_text = "Take this pin off"
		x.pressed.connect(func(): Shed.request({"a": "adventure_unpin", "i": i}))
		line.add_child(x)
		_pin_box.add_child(line)
	var mode := str(journey.get("mode", "main"))
	for m in _mode_buttons:
		(_mode_buttons[m] as Button).set_pressed_no_signal(m == mode)
	_clear.disabled = pins.is_empty()
	var plan := AdventureJourney.plan_of(journey)
	_route_pts = PackedVector2Array()
	_note.text = ""
	if pins.size() < 2:
		_facts.text = "Pin where you start and where you want to get to; more pins in between make it your way.\n\n%s" % _region_text()
	elif plan.is_empty():
		_facts.text = "Those pins can't be planned."
	else:
		var res := AdventurePlans.result(plan)
		if res.is_empty():
			_facts.text = "Planning the road..."
		elif not bool(res["ok"]):
			_facts.text = str(res["error"])
		else:
			var pack: RealPack = res["pack"]
			_facts.text = "%s\n\n%s" % [_journey_text(pack), "\n".join(pack.credits)]
			var step := 6
			for k in range(0, pack.x.size(), step):
				_route_pts.append(Vector2(pack.x[k], pack.z[k]))
			_route_pts.append(Vector2(pack.x[pack.x.size() - 1], pack.z[pack.z.size() - 1]))
	var why := AdventureJourney.start_reason(journey)
	_start.disabled = why != "" or plan.is_empty() or not _plan_ok(plan)
	_note.text = why if why != "" and pins.size() >= 2 else ""
	_canvas.queue_redraw()


func _plan_ok(plan: Dictionary) -> bool:
	var res := AdventurePlans.result(plan)
	return not res.is_empty() and bool(res["ok"]) and (res["pack"] as RealPack).max_km() >= Adventure.MIN_KM


func _pin_label(i: int, count: int, p: Dictionary) -> String:
	var name := str(p.get("name", ""))
	var role := "Start" if i == 0 else ("Finish" if i == count - 1 else "Stop")
	var by := str(p.get("by", ""))
	var text := role if name == "" else "%s: %s" % [role, name]
	return text if by == "" else "%s (%s)" % [text, by]


func _region_text() -> String:
	return "%s: %d junctions, %d roads, %d places to stop." % [region.title, region.node_count(), region.edge_count(), region.pois.size()]


func _journey_text(pack: RealPack) -> String:
	var km := pack.max_km()
	var lines := ["%.1f km, %s of riding%s." % [km, AdventureDest.time_text(km), ", with a night's stop" if AdventureDest.overnight(km) else ""]]
	var roads: Array = pack.summary.get("roads", [])
	if not roads.is_empty():
		lines.append("Along " + (", ".join(roads.slice(0, -1)) + " and " + str(roads[-1]) if roads.size() > 1 else str(roads[0])) + ".")
	if int(pack.summary.get("climb_m", 0)) > 0:
		lines.append("%d metres of climbing, up to %d m above the sea." % [int(pack.summary["climb_m"]), int(pack.summary["top_m"])])
	var stops: PackedStringArray = []
	for kind in ["fuel", "cafe", "inn"]:
		var n := pack.pois_of(kind).size()
		if n > 0:
			stops.append("%d %s" % [n, {"fuel": "filling stations", "cafe": "cafes", "inn": "inns and hotels"}[kind]])
	if not stops.is_empty():
		lines.append("On the way: " + ", ".join(stops) + ".")
	return "\n".join(lines)


## Host: starts the ride along the pinned journey, for the whole crew.
func start() -> void:
	var plan := AdventureJourney.plan_of(Shed.journey)
	var why := AdventureJourney.start_reason(Shed.journey)
	if why != "" or plan.is_empty():
		Shed.feedback.emit(why if why != "" else "Pin a start and somewhere to get to.", false)
		return
	var res := AdventurePlans.result(plan, true)
	if not bool(res["ok"]):
		Shed.feedback.emit(str(res["error"]), false)
		return
	var pack: RealPack = res["pack"]
	var names: Array = plan.get("names", [])
	var title := "Across %s" % region.title
	if names.size() >= 2 and str(names[0]) != "" and str(names[names.size() - 1]) != "" and names[0] != names[names.size() - 1]:
		title = "%s to %s" % [names[0], names[names.size() - 1]]
	Shed.request({"a": "adventure_start", "plan": plan, "seed": int(("0x" + pack.hash.left(7)).hex_to_int()), "title": title, "mag": article_id,
		"dest": AdventureDest.default_for(pack.theme, 1)})
	closed.emit()


# ---------------------------------------------------------------------------- the map

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
func _fit() -> void:
	var size := _canvas.size if _canvas.size.x > 10.0 else Vector2(900, 640)
	_scale = clampf(minf(size.x / region.bounds.size.x, size.y / region.bounds.size.y) * 0.96, MIN_SCALE, MAX_SCALE)
	_centre = region.bounds.get_center()
	_fitted = _canvas.size.x > 10.0


func _to_screen(p: Vector2) -> Vector2:
	return (p - _centre) * _scale + _canvas.size * 0.5


func _to_world(s: Vector2) -> Vector2:
	return (s - _canvas.size * 0.5) / _scale + _centre


func _map_input(event: InputEvent) -> void:
	if region == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var before := _to_world(mb.position)
			_scale = clampf(_scale * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), MIN_SCALE, MAX_SCALE)
			_centre += before - _to_world(mb.position)
			_canvas.queue_redraw()
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
			_canvas.queue_redraw()


## The junction under screen point `s` (within 24 px), or -1.
func _node_near(s: Vector2) -> int:
	var w := _to_world(s)
	return region.nearest_node(w.x, w.y, 24.0 / _scale)


## A click at screen point `s`: takes the pin there off, or puts a new one down.
func click(s: Vector2) -> void:
	var journey: Dictionary = Shed.journey if str(Shed.journey.get("region", "")) == region.id else {}
	var pins: Array = journey.get("pins", [])
	for i in pins.size():
		if _to_screen(Vector2(float(pins[i]["x"]), float(pins[i]["z"]))).distance_to(s) <= 14.0:
			Shed.request({"a": "adventure_unpin", "i": i})
			return
	var w := _to_world(s)
	Shed.request({"a": "adventure_pin", "region": region.id, "x": w.x, "z": w.y})


func _draw_map() -> void:
	if region == null:
		return
	if not _fitted and _canvas.size.x > 10.0:
		_fit()
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), SEA)
	var corner := _to_screen(region.bounds.position)
	if _shade != null:
		_canvas.draw_texture_rect(_shade, Rect2(corner, region.bounds.size * _scale), false)
	var view := Rect2(_to_world(Vector2.ZERO), size / _scale)
	# The roads, the small ones first so the big ones lie over them.
	var order: Array = ROAD_LOOK.keys()
	order.reverse()
	for cls: String in order:
		var look: Array = ROAD_LOOK[cls]
		if _scale < float(look[2]):
			continue
		var ci := region.classes.find(cls)
		var width := maxf(float(look[1]) * clampf(_scale * 60.0, 0.7, 2.0), 1.0)
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
				pts.append(_to_screen(line[k]))
			pts.append(_to_screen(line[line.size() - 1]))
			_canvas.draw_polyline(pts, look[0], width, true)
	# The planned road.
	if _route_pts.size() > 1:
		var pts := PackedVector2Array()
		for p in _route_pts:
			pts.append(_to_screen(p))
		_canvas.draw_polyline(pts, Color(0.1, 0.05, 0.05, 0.6), 7.0, true)
		_canvas.draw_polyline(pts, ROUTE, 4.5, true)
	# The towns and villages, named once there is room.
	if _scale >= 0.012:
		for p: Dictionary in region.places:
			var at := _to_screen(Vector2(float(p["x"]), float(p["z"])))
			if not Rect2(Vector2.ZERO, size).has_point(at):
				continue
			if str(p["kind"]) == "village" and _scale < 0.03:
				continue
			var fs := 15 if str(p["kind"]) == "town" else 12
			_canvas.draw_circle(at, 3.0 if str(p["kind"]) == "town" else 2.0, INK)
			_canvas.draw_string(ThemeDB.fallback_font, at + Vector2(6, 5), str(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	# Where the pointer would pin.
	if _hover >= 0:
		var hp := _to_screen(region.node_pos[_hover])
		_canvas.draw_arc(hp, 9.0, 0.0, TAU, 20, Color(0.1, 0.1, 0.1, 0.8), 2.0)
		var hname := AdventureJourney.place_name(region, _hover)
		if hname != "":
			_canvas.draw_string(ThemeDB.fallback_font, hp + Vector2(12, -10), hname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	# The pins.
	var journey: Dictionary = Shed.journey if str(Shed.journey.get("region", "")) == region.id else {}
	var pins: Array = journey.get("pins", [])
	for i in pins.size():
		var p: Dictionary = pins[i]
		var at := _to_screen(Vector2(float(p["x"]), float(p["z"])))
		var col := PIN_FIRST if i == 0 else PIN
		_canvas.draw_circle(at, 13.0, Color(1, 1, 1, 0.95))
		_canvas.draw_circle(at, 10.5, col)
		_canvas.draw_string(ThemeDB.fallback_font, at + Vector2(-5, 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## The land as a picture: sea, and ground shaded by height and slope (lit from the north-west). Any thread.
static func shade_image(r: RealRegion) -> Image:
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
