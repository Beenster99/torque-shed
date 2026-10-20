class_name AdventureMap
extends Control
## The paper map of an adventure ride, got out once you've stopped ({paper_map}, or the Esc menu):
## the whole route as a graph, north up (the way the crew's on marked like a highlighter, the
## other ways at each fork fainter and lettered, their surfaces in colour), where everyone is,
## the fuel stations and the stops along it (from the route's sites, so whatever's added there
## shows), and beside it a close-up of the next fork with a button per way to vote (the host's
## vote is the pick, see AdventureForks).

signal closed

const PAPER := Color(0.93, 0.89, 0.78)
const INK := Color(0.2, 0.17, 0.13)
const HIGHLIGHT := Color(0.95, 0.35, 0.2, 0.45)
const SURFACE_INK := {"tarmac": Color(0.28, 0.28, 0.3), "gravel": Color(0.55, 0.36, 0.16), "sand": Color(0.82, 0.62, 0.2),
	"snow": Color(0.35, 0.6, 0.9)}
const WAY_INK: Array[Color] = [Color(0.15, 0.45, 0.2), Color(0.55, 0.25, 0.65), Color(0.15, 0.4, 0.75)]
## How often what's on it (where everyone is, the votes) is brought up to date (s).
const REFRESH := 0.5

var trip: AdventureTrip
var _whole: Control        # the whole route
var _zoom: Control         # the next fork, close up
var _info: Label
var _vote_title: Label
var _vote_box: VBoxContainer
var _lines: Array = []     # AdventureRoute.map_lines, kept till the path changes
var _sites: Array = []
var _box := Rect2()        # the route frame's bounds of it all
var _fork := -1            # the fork in the close-up
var _riders: Array = []    # [{x, z, name, me, heading}]
var _timer := 0.0
var _choices := ""         # the route's choices the lines were made for


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
	_zoom = Control.new()
	_zoom.custom_minimum_size = Vector2(0, 300)
	_zoom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_zoom.draw.connect(_draw_zoom)
	_zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(_zoom)
	_vote_title = UITheme.label("", 16, UITheme.ACCENT)
	_vote_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_vote_title)
	_vote_box = VBoxContainer.new()
	_vote_box.add_theme_constant_override("separation", 4)
	side.add_child(_vote_box)
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
	_choices = ""
	refresh()


func tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		refresh()


## Brings it all up to date: the lines (when a way's been chosen), where everyone is, the votes.
func refresh() -> void:
	_timer = REFRESH
	if trip == null or trip.world == null:
		return
	var r := trip.world.route
	if _choices != str(r.choices) or _lines.is_empty():
		_choices = str(r.choices)
		_lines = r.map_lines(8)
		_sites = r.map_sites()
		var first := true
		for l in _lines:
			for p in l["pts"]:
				_box = Rect2(p, Vector2.ZERO) if first else _box.expand(p)
				first = false
	_riders = _rider_spots()
	var s := _own_s()
	_fork = r.next_fork(s)
	if _fork < 0:
		_fork = r.fork_at(s)
	_info.text = _info_text(r, s)
	_fill_votes(r, s)
	_whole.queue_redraw()
	_zoom.queue_redraw()


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
	var f := r.fork_at(s)
	if f >= 0:
		var way := r.way_of(f, int(r.choices.get(f, 0)))
		lines.append("On %s %s: %.1f km till it meets the road on." % [str(way["letter"]), str(way["name"]), (r.rejoin_s(f) - s) / 1000.0])
	return "\n".join(lines)


## The vote for the fork in the close-up: a button a way, with who's for it.
func _fill_votes(r: AdventureRoute, s: float) -> void:
	for c in _vote_box.get_children():
		c.queue_free()
	if _fork < 0:
		_vote_title.text = "No more forks: straight on to the destination."
		return
	var picked := AdventureForks.pick_of(_fork)
	var dist := r.fork_s(_fork) - s
	var host := Shed.is_authority()
	if dist < 0.0:
		_vote_title.text = "Through the fork."
	elif picked >= 0:
		_vote_title.text = "Fork in %.1f km: %s it is." % [dist / 1000.0, AdventureForks.way_name(_fork, picked)]
	else:
		_vote_title.text = "Fork in %.1f km. %s" % [dist / 1000.0, "Your vote is the pick." if host else "Vote: the host decides (main road if nobody picks)."]
	var vs := AdventureForks.votes_of(_fork)
	for w in r.forks[_fork]["ways"].size():
		var way: Dictionary = r.forks[_fork]["ways"][w]
		var who := PackedStringArray()
		for peer in vs:
			if int(vs[peer]) == w:
				who.append(str(Shed.crew.get(peer, {}).get("name", "?")))
		var b := Button.new()
		b.text = "%s%s  %s: %s%s" % ["> " if picked == w else "", str(way["letter"]), str(way["name"]), AdventureForks.way_text(way),
			"   [%s]" % ", ".join(who) if not who.is_empty() else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = picked >= 0 or dist < 0.0
		b.add_theme_color_override("font_color", WAY_INK[w].lightened(0.45))
		b.pressed.connect(func():
			Shed.request({"a": "adventure_vote", "fork": _fork, "way": w})
			refresh.call_deferred())
		_vote_box.add_child(b)


# ---------------------------------------------------------------------------- drawing

## The whole route, fitted into `c`.
func _draw_whole() -> void:
	_draw_map(_whole, _box.grow(maxf(_box.size.x, _box.size.y) * 0.03), -1)


## The next fork's ways close up.
func _draw_zoom() -> void:
	if _fork < 0 or trip == null or trip.world == null:
		return
	var r := trip.world.route
	var box := Rect2()
	var first := true
	for l in _lines:
		if int(l["fork"]) == _fork:
			for p in l["pts"]:
				box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
				first = false
	if first:
		return
	_draw_map(_zoom, box.grow(maxf(box.size.x, box.size.y) * 0.08), _fork)


## Draws the lines, sites and riders inside `box` (route frame) onto `c`, north up; `focus` is the
## fork in a close-up (its ways lettered big), -1 for the whole.
func _draw_map(c: Control, box: Rect2, focus: int) -> void:
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
	var r := trip.world.route
	var thin := focus < 0
	# The way the crew's on, highlighted (as far as it's decided), then every road in its surface's ink.
	for l in _lines:
		if not bool(l["on"]) or (int(l["fork"]) >= 0 and not r.decided.has(int(l["fork"]))):
			continue
		c.draw_polyline(_pts(l["pts"], at), HIGHLIGHT, 9.0 if not thin else 6.0)
	for l in _lines:
		var f := int(l["fork"])
		var on := bool(l["on"])
		var open := f >= 0 and not r.decided.has(f)
		var col: Color = SURFACE_INK.get(str(l["surface"]), INK)
		var wdt := 2.5 if thin else 4.0
		if open:
			col = WAY_INK[int(l["way"])].lerp(col, 0.35)
		elif not on:
			col = Color(col, 0.35)
			wdt *= 0.6
		c.draw_polyline(_pts(l["pts"], at), col, wdt, true)
	# Each way at a fork lettered halfway along (big in the close-up).
	for f in r.forks.size():
		if focus >= 0 and f != focus:
			continue
		for w in r.forks[f]["ways"].size():
			var mid := _way_mid(f, w)
			if mid == Vector2.INF:
				continue
			var p: Vector2 = at.call(mid.x, mid.y)
			var rad := 7.0 if thin else 13.0
			c.draw_circle(p, rad, WAY_INK[w])
			c.draw_string(font, p + Vector2(-rad, rad * 0.45), str(r.forks[f]["ways"][w]["letter"]), HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0,
				10 if thin else 16, Color.WHITE)
			if not thin:
				var way: Dictionary = r.forks[f]["ways"][w]
				c.draw_string(font, p + Vector2(rad + 4.0, 5.0), "%s, %.1f km" % [str(way["name"]), float(way["len"]) / 1000.0],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	# The sites: fuel, the start and the destination, and any stops along the way.
	for e in _sites:
		var st: Dictionary = e["site"]
		var kind := str(st["kind"])
		if kind in ["junction", "fork"]:
			continue
		var p: Vector2 = at.call(float(e["x"]), float(e["z"]))
		if not area.grow(-2.0).has_point(p):
			continue
		var faded := not bool(e["on"])
		match kind:
			"fuel":
				c.draw_circle(p, 6.0, Color(0.15, 0.6, 0.25, 0.4 if faded else 1.0))
				c.draw_string(font, p + Vector2(-6, 4), "F", HORIZONTAL_ALIGNMENT_CENTER, 12, 10, Color.WHITE)
			"start":
				c.draw_circle(p, 6.0, Color(0.15, 0.35, 0.75))
				c.draw_string(font, p + Vector2(9, 5), "Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
			"finish":
				c.draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.8, 0.15, 0.1))
				c.draw_string(font, p + Vector2(10, 5), "Destination", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
			_:
				c.draw_circle(p, 3.5, Color(INK, 0.35 if faded else 0.9))
				if str(st.get("name", "")) != "" and not thin:
					c.draw_string(font, p + Vector2(6, 4), str(st["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.8))
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
	var bar := 5000.0 if thin else 1000.0
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


## The middle of way `w` at fork `f` on the route frame (from the map's lines).
func _way_mid(f: int, w: int) -> Vector2:
	var mine := _lines.filter(func(l): return int(l["fork"]) == f and int(l["way"]) == w)
	if mine.is_empty():
		return Vector2.INF
	var pts: PackedVector2Array = mine[mine.size() / 2]["pts"]
	return pts[pts.size() / 2]
