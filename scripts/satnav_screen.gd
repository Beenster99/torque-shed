class_name SatnavScreen
extends Control
## What a sat nav shows: a heading-up moving map round the bike (the roads near it, the way
## ahead picked out bright), the bike's arrow low in the middle, the road it's on along the
## bottom, and along the top how far to the next fuel and the destination, when the route
## knows them. It draws the `view` Satnav makes (see Satnav.view_for), whether that's on the
## unit's own screen on the bars (in a SubViewport, see Satnav) or as the HUD overlay.

## How many metres the map spans across, at a standstill and at speed (it zooms out as you go).
const SPAN_SLOW := 220.0
const SPAN_FAST := 520.0
const BACK := Color(0.07, 0.1, 0.13)
const LAND := Color(0.11, 0.16, 0.13)
const ROAD := Color(0.62, 0.64, 0.66)
const TRACK := Color(0.55, 0.45, 0.32)
const ROUTE := Color(0.25, 0.75, 1.0)
const FUEL := Color(0.25, 0.9, 0.4)
const DEST := Color(1.0, 0.45, 0.35)
const FORK := Color(1.0, 0.8, 0.25)
## Another way off at a fork, not the one being taken.
const OTHER := Color(0.5, 0.52, 0.55, 0.5)
## The rest of the crew on the map and in their list, and the wrong-way warning.
const FRIEND := Color(0.45, 0.85, 1.0)
const WRONG := Color(0.85, 0.12, 0.1)
## The stops ahead (see Satnav.satnav_stops): each kind's colour and the letter on its marker.
const STOP_COLORS := {"food": Color(1.0, 0.7, 0.2), "rest": Color(0.4, 0.65, 1.0), "sleep": Color(0.8, 0.5, 1.0), "fuel": FUEL}
const STOP_MARKS := {"food": "E", "rest": "P", "sleep": "Z", "fuel": "F"}

## {pos: Vector2 (x, z), fwd: Vector2 (unit heading, x z), speed (m/s), roads: Array of
## {pts: PackedVector2Array, kind, hw}, route: PackedVector2Array, road: name of the road it's
## on, points: Array of {kind, name, distance (m), at: Vector2 or null}, stops: the next places
## to stop, Array of {kind, name, label, distance, at}, guide: {wrong_way, turn} (the way to go,
## relative to the heading), friends: Array of {name, ahead (m), at}, junction: what to do at the
## next one, {text, type, exit, distance}} or {} for no fix yet.
var view := {}
## What the unit can show (BikeBuild.satnav_features): "map", "route", "fuel".
var features: Array = ["map", "route", "fuel"]
## The span in use, eased between SPAN_SLOW and SPAN_FAST.
var span := SPAN_SLOW
## Rounded corners and a frame (the HUD overlay); the unit's own screen fills edge to edge.
var framed := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true   # the roads run off the edge of the screen, not over the HUD


## Takes a new `v` (see view) and redraws.
func show_view(v: Dictionary) -> void:
	view = v
	var want := lerpf(SPAN_SLOW, SPAN_FAST, clampf(float(v.get("speed", 0.0)) / 35.0, 0.0, 1.0))
	span = lerpf(span, want, 0.15)
	queue_redraw()


## Where world point `p` (x, z) lands on the screen, heading up.
func to_screen(p: Vector2) -> Vector2:
	var pos: Vector2 = view.get("pos", Vector2.ZERO)
	var fwd: Vector2 = view.get("fwd", Vector2(0, -1))
	var right := Vector2(-fwd.y, fwd.x)
	var rel := p - pos
	var k := size.x / span
	return _bike_at() + Vector2(rel.dot(right), -rel.dot(fwd)) * k


func _bike_at() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.72)


func _draw() -> void:
	var font := get_theme_default_font()
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BACK)
	if framed:
		draw_rect(r, Color(1, 1, 1, 0.25), false, 2.0)
	var fs := maxi(9, int(size.y / 14.0))
	if view.is_empty():
		draw_string(font, Vector2(0, size.y * 0.5), "Finding satellites...", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(1, 1, 1, 0.6))
		return
	var k := size.x / span
	var show_map := features.has("map")
	if show_map:
		draw_rect(r.grow(-1.0), LAND)
		for road in view.get("roads", []):
			var pts: PackedVector2Array = road["pts"]
			if pts.size() < 2:
				continue
			var out := PackedVector2Array()
			out.resize(pts.size())
			for i in pts.size():
				out[i] = to_screen(pts[i])
			var w := maxf(float(road.get("hw", 3.0)) * 2.0 * k, 2.0)
			var kind := str(road.get("kind", ""))
			draw_polyline(out, TRACK if kind == "dirt" else OTHER if kind == "other" else ROAD, w if kind != "other" else maxf(w * 0.6, 1.5), true)
	var route: PackedVector2Array = view.get("route", PackedVector2Array())
	if features.has("route") and route.size() >= 2:
		var out := PackedVector2Array()
		out.resize(route.size())
		for i in route.size():
			out[i] = to_screen(route[i])
		draw_polyline(out, ROUTE, maxf(4.0 * k * 2.0, 3.0), true)
	# The points on the map, where they're in view.
	for p in view.get("points", []):
		if not _shows(p) or not (p.get("at") is Vector2):
			continue
		var at := to_screen(p["at"])
		if r.grow(-4.0).has_point(at):
			var c := _colour(p)
			draw_circle(at, maxf(size.x / 40.0, 4.0), c)
			draw_string(font, at + Vector2(-20, -8), {"fuel": "F", "fork": "Y"}.get(str(p["kind"]), "X"), HORIZONTAL_ALIGNMENT_CENTER, 40, fs, Color.WHITE)
	# The stops ahead: their markers on the map and a list of the next few (a unit that knows the route).
	var stops: Array = view.get("stops", []) if features.has("route") else []
	for p in stops:
		if str(p.get("kind", "")) == "fuel" or not (p.get("at") is Vector2):
			continue
		var at := to_screen(p["at"])
		if r.grow(-4.0).has_point(at):
			draw_circle(at, maxf(size.x / 46.0, 3.5), STOP_COLORS.get(str(p["kind"]), Color.WHITE))
			draw_string(font, at + Vector2(-20, -7), str(STOP_MARKS.get(str(p["kind"]), "?")), HORIZONTAL_ALIGNMENT_CENTER, 40, fs - 2, Color.WHITE)
	# The rest of the crew, where they're in view: a dot and their initial.
	var friends: Array = view.get("friends", [])
	for f in friends:
		if not (f.get("at") is Vector2):
			continue
		var at := to_screen(f["at"])
		if r.grow(-4.0).has_point(at):
			draw_circle(at, maxf(size.x / 46.0, 3.5), FRIEND)
			draw_string(font, at + Vector2(-20, -7), str(f.get("name", "?")).left(1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 40, fs - 2, BACK)
	# The bike's arrow.
	var b := _bike_at()
	var a := maxf(size.x / 28.0, 6.0)
	draw_colored_polygon(PackedVector2Array([b + Vector2(0, -a * 1.4), b + Vector2(a, a), b + Vector2(0, a * 0.45), b + Vector2(-a, a)]), Color.WHITE)
	# Along the top: the next fuel and the destination.
	var top := PackedStringArray()
	var cols: Array[Color] = []
	for p in view.get("points", []):
		if _shows(p):
			top.append("%s %.1f %s" % [str(p.get("name", "")), Units.distance_value(float(p["distance"]) / 1000.0), Units.distance_unit()])
			cols.append(_colour(p))
	var bar_h := fs + 8.0
	if not top.is_empty():
		draw_rect(Rect2(0, 0, size.x, bar_h), Color(0, 0, 0, 0.6))
		var x := 6.0
		for i in mini(top.size(), 2):
			draw_string(font, Vector2(x, fs + 2.0), top[i], HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.5 - 8.0, fs, cols[i])
			x += size.x * 0.5
	# Coming up to a fork: the ways, their votes and the pick, under the top bar.
	var choice: Dictionary = view.get("choice", {})
	if features.has("route") and not choice.is_empty():
		_draw_choice(choice, bar_h + 4.0, fs, font)
	elif features.has("route") and not (view.get("junction", {}) as Dictionary).is_empty():
		_draw_junction(view["junction"], bar_h + 4.0, fs, font)
	elif not stops.is_empty():
			var lfs := maxi(8, fs - 2)
			var line_h := lfs + 4.0
			var box := Rect2(4.0, bar_h + 4.0, size.x * 0.62, line_h * stops.size() + 4.0)
			draw_rect(box, Color(0, 0, 0, 0.55))
			for i in stops.size():
				var p: Dictionary = stops[i]
				var txt := "%s %s  %.1f %s" % [str(STOP_MARKS.get(str(p["kind"]), "?")), str(p.get("label", p.get("name", ""))),
					Units.distance_value(float(p["distance"]) / 1000.0), Units.distance_unit()]
				draw_string(font, Vector2(box.position.x + 4.0, box.position.y + line_h * (i + 1) - 2.0), txt, HORIZONTAL_ALIGNMENT_LEFT,
					box.size.x - 8.0, lfs, STOP_COLORS.get(str(p["kind"]), Color.WHITE))
	# Which way to go: an arrow (relative to the heading) to the road on towards the destination,
	# and facing back the way you came, a warning to turn round.
	var guide: Dictionary = view.get("guide", {})
	if features.has("route") and not guide.is_empty():
		var wrong := bool(guide.get("wrong_way", false))
		var gc := Vector2(fs * 1.4 + 2.0, size.y - bar_h - fs * 1.4 - 2.0)
		_draw_guide(gc, fs * 1.1, float(guide.get("turn", 0.0)), WRONG if wrong else ROUTE)
		if wrong:
			var band := Rect2(size.x * 0.08, size.y * 0.4, size.x * 0.84, fs * 2.2)
			draw_rect(band, Color(WRONG, 0.9))
			draw_rect(band, Color.WHITE, false, 2.0)
			draw_string(font, Vector2(band.position.x, band.position.y + fs * 1.55), "WRONG WAY: TURN AROUND", HORIZONTAL_ALIGNMENT_CENTER,
				band.size.x, fs + 1, Color.WHITE)
	# The rest of the crew along the road: how far ahead or behind, nearest first.
	if not friends.is_empty():
		var lfs := maxi(8, fs - 2)
		var shown := friends.duplicate()
		shown.sort_custom(func(a, c): return absf(float(a["ahead"])) < absf(float(c["ahead"])))
		shown = shown.slice(0, 3)
		var lh := lfs + 4.0
		var box := Rect2(size.x * 0.56, size.y - bar_h - lh * shown.size() - 6.0, size.x * 0.44 - 2.0, lh * shown.size() + 4.0)
		draw_rect(box, Color(0, 0, 0, 0.55))
		for i in shown.size():
			draw_string(font, Vector2(box.position.x + 4.0, box.position.y + lh * (i + 1) - 2.0), AdventureTrip.friend_text(str(shown[i]["name"]),
				float(shown[i]["ahead"])), HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 8.0, lfs, FRIEND)
	# Along the bottom: the road it's on, and north.
	draw_rect(Rect2(0, size.y - bar_h, size.x, bar_h), Color(0, 0, 0, 0.6))
	var road_name := str(view.get("road", ""))
	draw_string(font, Vector2(6, size.y - 5.0), road_name if road_name != "" else "Off road", HORIZONTAL_ALIGNMENT_LEFT, size.x - 40.0, fs, Color(1, 1, 1, 0.85))
	var fwd: Vector2 = view.get("fwd", Vector2(0, -1))
	var n := Vector2(0, -1)   # north is -z
	var north := Vector2(n.dot(Vector2(-fwd.y, fwd.x)), -n.dot(fwd))
	var nc := Vector2(size.x - 16.0, size.y - bar_h * 0.5)
	draw_line(nc - north * 7.0, nc + north * 7.0, Color(1, 1, 1, 0.5), 2.0)
	draw_circle(nc + north * 7.0, 2.5, Color(1, 0.35, 0.3))
	draw_string(font, Vector2(size.x - 34.0, size.y - bar_h - 4.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 36, fs - 2, Color(1, 1, 1, 0.6))


## The guide arrow in a disc at `c` (radius `rad`), pointing `turn` radians round from straight up
## (the heading); right round behind you it's a U-turn.
func _draw_guide(c: Vector2, rad: float, turn: float, col: Color) -> void:
	draw_circle(c, rad, Color(0, 0, 0, 0.6))
	draw_arc(c, rad, 0.0, TAU, 24, col, 2.0, true)
	if absf(turn) > deg_to_rad(150.0):
		# A U-turn: up, over and back down on the side the road on lies.
		var sx := 1.0 if turn > 0.0 else -1.0
		var w := rad * 0.32
		var top := c.y - rad * 0.15
		draw_line(Vector2(c.x - sx * w, c.y + rad * 0.55), Vector2(c.x - sx * w, top), col, 3.0, true)
		var pts := PackedVector2Array()
		for k in 9:
			var a := PI * k / 8.0
			pts.append(Vector2(c.x - sx * w * cos(a), top - w * sin(a)))
		draw_polyline(pts, col, 3.0, true)
		var e := Vector2(c.x + sx * w, top)
		draw_colored_polygon(PackedVector2Array([e + Vector2(0, rad * 0.6), e + Vector2(-rad * 0.28, rad * 0.1), e + Vector2(rad * 0.28, rad * 0.1)]), col)
		return
	var d := Vector2(sin(turn), -cos(turn))
	var side := Vector2(-d.y, d.x)
	var tip := c + d * rad * 0.75
	draw_line(c - d * rad * 0.6, c + d * rad * 0.2, col, 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip, c + d * rad * 0.1 + side * rad * 0.42, c + d * rad * 0.1 - side * rad * 0.42]), col)


## What to do at the junction coming up: a little sign (a roundabout with its exit marked, or
## lights) and the words, with how far it is.
func _draw_junction(j: Dictionary, y: float, fs: int, font: Font) -> void:
	var lh := fs + 3.0
	var box := Rect2(4.0, y, size.x - 8.0, lh * 2.0 + 8.0)
	draw_rect(box, Color(0, 0, 0, 0.72))
	var icon := Vector2(box.position.x + lh, box.position.y + box.size.y * 0.5)
	var rad := lh * 0.62
	match str(j.get("type", "")):
		"roundabout", "mini":
			draw_arc(icon, rad * 0.6, 0.0, TAU, 18, Color.WHITE, 2.0, true)
			draw_line(icon + Vector2(0, rad * 0.6), icon + Vector2(0, rad * 1.3), Color.WHITE, 2.0, true)
			# The way out: straight on over the top (the main road goes on).
			draw_line(icon - Vector2(0, rad * 0.6), icon - Vector2(0, rad * 1.3), ROUTE, 3.0, true)
		"lights":
			for k in 3:
				draw_circle(icon + Vector2(0, (k - 1) * rad * 0.62), rad * 0.26, [Color(0.95, 0.2, 0.15), Color(1.0, 0.7, 0.1), Color(0.2, 0.9, 0.35)][k])
		_:
			draw_line(icon + Vector2(0, rad * 1.2), icon - Vector2(0, rad * 1.2), Color.WHITE, 3.0, true)
			draw_line(icon + Vector2(-rad, 0), icon + Vector2(rad, 0), Color.WHITE, 2.0, true)
	var x := box.position.x + lh * 2.0
	draw_string(font, Vector2(x, box.position.y + fs + 2.0), near_distance(float(j.get("distance", 0.0))), HORIZONTAL_ALIGNMENT_LEFT,
		box.size.x - x, fs, ROUTE)
	draw_string(font, Vector2(x, box.position.y + lh + fs + 3.0), str(j.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT,
		box.end.x - x - 4.0, maxi(8, fs - 1), Color.WHITE)


## A short way off, as the sat nav says it: "250 m", "270 yd", "Now".
static func near_distance(m: float) -> String:
	if m < 15.0:
		return "Now"
	if Units.imperial():
		return "%d yd" % (roundi(m * 1.0936 / 10.0) * 10)
	return "%d m" % (roundi(m / 10.0) * 10)


func _colour(p: Dictionary) -> Color:
	return {"fuel": FUEL, "fork": FORK}.get(str(p.get("kind", "")), DEST)


## The ways at the fork ahead, a line each: letter, which way, name, length, time, the surface
## it's mostly on and how many have voted for it; the picked one marked.
func _draw_choice(c: Dictionary, y: float, fs: int, font: Font) -> void:
	var ways: Array = c["ways"]
	var lh := fs + 3.0
	var picked := int(c["picked"])
	draw_rect(Rect2(0, y, size.x, lh * (ways.size() + 1) + 6.0), Color(0, 0, 0, 0.72))
	var head := "Fork %.1f %s: %s" % [Units.distance_value(float(c["dist"]) / 1000.0), Units.distance_unit(),
		"vote 1-%d" % ways.size() if picked < 0 else str(ways[picked]["letter"]) + " chosen"]
	draw_string(font, Vector2(6, y + fs + 1.0), head, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12.0, fs, FORK)
	for k in ways.size():
		var w: Dictionary = ways[k]
		var n := (w["voters"] as PackedStringArray).size()
		var bits := str(w["text"]).split(", ")
		var line := "%s%s %s %s %s %s%s" % [">" if bool(w["picked"]) else "", str(w["letter"]), str(w["arrow"]), str(w["name"]),
			bits[0], bits[1].replace("about ", "") if bits.size() > 1 else "", "  +%d" % n if n > 0 else ""]
		var col := Color.WHITE if picked < 0 or bool(w["picked"]) else Color(1, 1, 1, 0.45)
		draw_string(font, Vector2(6, y + lh * (k + 1) + fs + 1.0), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12.0, fs, col)


## Whether point `p` is one this unit shows (fuel needs the "fuel" feature, a destination the route).
func _shows(p: Dictionary) -> bool:
	return features.has("fuel") if str(p.get("kind", "")) == "fuel" else features.has("route")
