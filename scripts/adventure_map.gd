class_name AdventureMap
extends Control
## The paper map of an adventure ride, got out once you've stopped ({paper_map}, or the Esc menu):
## the whole route, north up (marked like a highlighter, its surfaces in colour), where everyone is,
## and the fuel stations and the stops along it (from the route's sites, so whatever's added there
## shows).

signal closed

const PAPER := Color(0.93, 0.89, 0.78)
const INK := Color(0.2, 0.17, 0.13)
const HIGHLIGHT := Color(0.95, 0.35, 0.2, 0.45)
const SURFACE_INK := {"tarmac": Color(0.28, 0.28, 0.3), "gravel": Color(0.55, 0.36, 0.16), "sand": Color(0.82, 0.62, 0.2),
	"snow": Color(0.35, 0.6, 0.9)}
## How often what's on it (where everyone is) is brought up to date (s).
const REFRESH := 0.5

var trip: AdventureTrip
var _whole: Control        # the whole route
var _info: Label
var _lines: Array = []     # AdventureRoute.map_lines, kept for the ride
var _sites: Array = []
var _box := Rect2()        # the route frame's bounds of it all
var _riders: Array = []    # [{x, z, name, me, heading}]
var _timer := 0.0
var _route: AdventureRoute   # the route the lines were made for


func _ready() -> void:
	name = "AdventureMap"
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
	_whole = Control.new()
	_whole.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_whole.size_flags_stretch_ratio = 1.0
	_whole.draw.connect(_draw_whole)
	_whole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_whole)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.15
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	var title := UITheme.title("Route map", 26)
	side.add_child(title)
	_info = UITheme.label("", 15, Color(0.9, 0.9, 0.9))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_info)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(gap)
	var close := Button.new()
	Controls.bind_text(close, "Fold the map away ({paper_map})")
	close.pressed.connect(func(): closed.emit())
	side.add_child(close)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("paper_map") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		closed.emit()


## Unfolds it, up to date.
func open() -> void:
	visible = true
	refresh()


func tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		refresh()


## Brings it all up to date: the lines (for a new ride), where everyone is.
func refresh() -> void:
	_timer = REFRESH
	if trip == null or trip.world == null:
		return
	var r := trip.world.route
	if _route != r or _lines.is_empty():
		_route = r
		_lines = r.map_lines(8)
		_sites = r.map_sites()
		var first := true
		for l in _lines:
			for p in l["pts"]:
				_box = Rect2(p, Vector2.ZERO) if first else _box.expand(p)
				first = false
	_riders = _rider_spots()
	_info.text = _info_text(r, _own_s())
	_whole.queue_redraw()


func _own_s() -> float:
	var p: Vector3 = trip.focus_points()[0]
	return maxf(trip.world.distance_of(p, "map"), 0.0)


## Where everyone is on the route frame: you first.
func _rider_spots() -> Array:
	var out := []
	var w := trip.world
	var mine: Vector3 = trip.focus_points()[0]
	var fwd := Vector3.FORWARD
	if trip.main and trip.main.bike:
		fwd = -trip.main.bike.global_transform.basis.z
	var xz := w.route_xz(mine)
	out.append({"x": xz[0], "z": xz[1], "name": "You", "me": true, "heading": atan2(fwd.x, -fwd.z)})
	# The others with how far ahead or behind along the road they are ("Dave 1.2 km ahead").
	for f in trip.friends():
		var q := w.route_xz(f["at"])
		out.append({"x": q[0], "z": q[1], "name": AdventureTrip.friend_text(str(f["name"]), float(f["ahead"])), "me": false, "heading": 0.0})
	return out


func _info_text(r: AdventureRoute, s: float) -> String:
	var lines := PackedStringArray()
	lines.append("%.1f of %.1f km to the destination." % [s / 1000.0, r.length / 1000.0])
	for st in r.sites_of("fuel"):
		if float(st["s"]) > s - 30.0:
			lines.append("Next fuel in %.1f km." % maxf(0.0, (float(st["s"]) - s) / 1000.0))
			break
	if trip.main and trip.main.bike:
		var bike: Bike = trip.main.bike
		lines.append("Petrol: %.1f litres, about %d km in the tank." % [bike.fuel_litres, roundi(bike.fuel_litres * bike.build.cruise_economy())])
	return "\n".join(lines)


# ---------------------------------------------------------------------------- drawing

## The whole route, fitted into `c`.
func _draw_whole() -> void:
	_draw_map(_whole, _box.grow(maxf(_box.size.x, _box.size.y) * 0.03))


## Draws the lines, sites and riders inside `box` (route frame) onto `c`, north up.
func _draw_map(c: Control, box: Rect2) -> void:
	var area := Rect2(Vector2.ZERO, c.size)
	if box.size.x <= 0.0 or box.size.y <= 0.0 or area.size.x < 10.0:
		return
	var k := minf(area.size.x / box.size.x, area.size.y / box.size.y)
	var used := box.size * k
	var off := area.position + (area.size - used) * 0.5
	var at := func(x: float, z: float) -> Vector2: return off + (Vector2(x, z) - box.position) * k
	var font := c.get_theme_default_font()
	c.draw_rect(Rect2(off - Vector2(10, 10), used + Vector2(20, 20)), PAPER)
	c.draw_rect(Rect2(off - Vector2(10, 10), used + Vector2(20, 20)), INK, false, 2.0)
	# The road highlighted, then in its surface's ink.
	for l in _lines:
		c.draw_polyline(_pts(l["pts"], at), HIGHLIGHT, 6.0)
	for l in _lines:
		c.draw_polyline(_pts(l["pts"], at), SURFACE_INK.get(str(l["surface"]), INK), 2.5, true)
	# The sites: fuel, the start and the destination, and any stops along the way.
	for e in _sites:
		var st: Dictionary = e["site"]
		var kind := str(st["kind"])
		var p: Vector2 = at.call(float(e["x"]), float(e["z"]))
		if not area.grow(-2.0).has_point(p):
			continue
		match kind:
			"fuel":
				c.draw_circle(p, 6.0, Color(0.15, 0.6, 0.25))
				c.draw_string(font, p + Vector2(-6, 4), "F", HORIZONTAL_ALIGNMENT_CENTER, 12, 10, Color.WHITE)
			"start":
				c.draw_circle(p, 6.0, Color(0.15, 0.35, 0.75))
				c.draw_string(font, p + Vector2(9, 5), "Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
			"finish":
				c.draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.8, 0.15, 0.1))
				c.draw_string(font, p + Vector2(10, 5), "Destination", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
			_:
				c.draw_circle(p, 3.5, Color(INK, 0.9))
	# Everyone on the route: you as an arrow, the others as dots with their names.
	for rd in _riders:
		var p: Vector2 = at.call(float(rd["x"]), float(rd["z"]))
		if not area.grow(4.0).has_point(p):
			continue
		if bool(rd["me"]):
			var h := float(rd["heading"])
			var fwd := Vector2(sin(h), -cos(h))
			var side := Vector2(-fwd.y, fwd.x)
			c.draw_colored_polygon(PackedVector2Array([p + fwd * 11.0, p - fwd * 7.0 + side * 7.0, p - fwd * 3.0, p - fwd * 7.0 - side * 7.0]),
				Color(0.85, 0.1, 0.1))
		else:
			c.draw_circle(p, 5.5, Color(0.1, 0.3, 0.85))
			c.draw_string(font, p + Vector2(8, 4), str(rd["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.1, 0.2, 0.6))
	# North, and a scale.
	var n0 := off + Vector2(used.x - 14.0, 30.0)
	c.draw_line(n0, n0 - Vector2(0, 20), INK, 2.0)
	c.draw_string(font, n0 - Vector2(7, 24), "N", HORIZONTAL_ALIGNMENT_CENTER, 14, 13, INK)
	var bar := 5000.0
	while bar * k > used.x * 0.4 and bar > 100.0:
		bar *= 0.5
	var b0 := off + Vector2(4.0, used.y - 6.0)
	c.draw_line(b0, b0 + Vector2(bar * k, 0), INK, 3.0)
	c.draw_string(font, b0 + Vector2(0, -6), "%s km" % str(snappedf(bar / 1000.0, 0.1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)


static func _pts(pts: PackedVector2Array, at: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = at.call(pts[i].x, pts[i].y)
	return out

