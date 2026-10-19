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

## {pos: Vector2 (x, z), fwd: Vector2 (unit heading, x z), speed (m/s), roads: Array of
## {pts: PackedVector2Array, kind, hw}, route: PackedVector2Array, road: name of the road it's
## on, points: Array of {kind, name, distance (m), at: Vector2 or null}} or {} for no fix yet.
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
			draw_polyline(out, TRACK if str(road.get("kind", "")) == "dirt" else ROAD, w, true)
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
			var c := FUEL if str(p["kind"]) == "fuel" else DEST
			draw_circle(at, maxf(size.x / 40.0, 4.0), c)
			draw_string(font, at + Vector2(-20, -8), "F" if str(p["kind"]) == "fuel" else "X", HORIZONTAL_ALIGNMENT_CENTER, 40, fs, Color.WHITE)
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
			cols.append(FUEL if str(p["kind"]) == "fuel" else DEST)
	var bar_h := fs + 8.0
	if not top.is_empty():
		draw_rect(Rect2(0, 0, size.x, bar_h), Color(0, 0, 0, 0.6))
		var x := 6.0
		for i in mini(top.size(), 2):
			draw_string(font, Vector2(x, fs + 2.0), top[i], HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.5 - 8.0, fs, cols[i])
			x += size.x * 0.5
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


## Whether point `p` is one this unit shows (fuel needs the "fuel" feature, a destination the route).
func _shows(p: Dictionary) -> bool:
	return features.has("fuel") if str(p.get("kind", "")) == "fuel" else features.has("route")
