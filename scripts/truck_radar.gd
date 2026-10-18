class_name TruckRadar
extends Control
## The recovery truck's radar, up in the cab (for the driver and a passenger alike): a round
## screen with the truck in the middle pointing up the screen, a blip for each recovery job still
## to collect (orange) and one for the garage's yard (green), the ones further off than its range
## sat on the rim in their direction. Underneath, the next place to go (Recovery.next_site), how
## far it is and which way, with an arrow turned to point at it from the way the truck faces.

const RANGE := 900.0           # metres from the middle to the rim
const RADIUS := 74.0           # pixels
const JOB := Color(1.0, 0.6, 0.12)
const HOME := Color(0.35, 0.9, 0.45)

var view: RecoveryView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## Everywhere the radar shows: [{name, at, kind}], kind "job" (a bike still to
## collect) or "home" (the garage's yard, where the truck parks).
static func targets() -> Array:
	var out := []
	for jid in Recovery.jobs():
		var j: Dictionary = Recovery.jobs()[jid]
		if str(j["state"]) != "collect" or Recovery.loads().has(int(j["bike"])):
			continue
		var at: Vector3 = j["at"]
		var b: Dictionary = Shed.bikes.get(int(j["bike"]), {})
		if not b.is_empty():
			at = (b["xf"] as Transform3D).origin
		out.append({"name": str(j["name"]).capitalize(), "at": at, "kind": "job"})
	out.append({"name": "The garage", "at": Recovery.PARK.origin, "kind": "home"})
	return out


## Where on the radar something at `at` shows, from the truck at `from` facing `fwd` (world):
## pixels from the middle, up the screen ahead, held to the rim (`radius`) when it's out of range.
static func blip(from: Vector3, fwd: Vector3, at: Vector3, radius := RADIUS, range_m := RANGE) -> Vector2:
	var f := Vector3(fwd.x, 0.0, fwd.z)
	f = f.normalized() if f.length() > 0.001 else Vector3.FORWARD
	var right := Vector3(-f.z, 0.0, f.x)
	var d := at - from
	var p := Vector2(d.dot(right), -d.dot(f)) * (radius / range_m)
	return p.limit_length(radius)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if view == null or view.car == null or not is_instance_valid(view.car):
		return
	var car := view.car
	var from := car.global_position
	var fwd := -car.global_basis.z
	var font := get_theme_default_font()
	# Above the truck's dash in the bottom right corner.
	var c := Vector2(size.x - 137.0, size.y - 150.0 - RADIUS - 46.0)
	draw_circle(c, RADIUS + 6.0, Color(0.02, 0.04, 0.03, 0.72))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(0.4, 0.95, 0.6, 0.55), 1.5)
	draw_arc(c, RADIUS * 0.5, 0.0, TAU, 40, Color(0.4, 0.95, 0.6, 0.22), 1.0)
	draw_line(c - Vector2(RADIUS, 0.0), c + Vector2(RADIUS, 0.0), Color(0.4, 0.95, 0.6, 0.12), 1.0)
	draw_line(c - Vector2(0.0, RADIUS), c + Vector2(0.0, RADIUS), Color(0.4, 0.95, 0.6, 0.12), 1.0)
	# North on the rim, turning as the truck does.
	var north := blip(from, fwd, from + Vector3(0.0, 0.0, -RANGE * 2.0)).normalized() * (RADIUS + 0.5)
	draw_string(font, c + north + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 1.0, 0.8, 0.8))
	for t in targets():
		var p := blip(from, fwd, t["at"])
		var col: Color = HOME if str(t["kind"]) == "home" else JOB
		if p.length() >= RADIUS - 0.5:
			# Off the edge: a pointer on the rim.
			var dir := p.normalized()
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([c + dir * (RADIUS + 5.0), c + dir * (RADIUS - 5.0) + side * 4.5,
				c + dir * (RADIUS - 5.0) - side * 4.5]), col)
		else:
			draw_circle(c + p, 4.5, col)
	# The truck, pointing up.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 6), c + Vector2(-5, 6)]), Color.WHITE)
	# The next stop: its name, distance and an arrow to it.
	var site := Recovery.next_site(from)
	var name_text := "The garage"
	var at: Vector3 = Recovery.PARK.origin
	if not site.is_empty():
		name_text = str(site["name"])
		at = site["at"]
	var to := blip(from, fwd, at, 1.0, 1.0)
	var arrow_c := c + Vector2(-RADIUS + 4.0, RADIUS + 22.0)
	if to.length() > 0.001:
		var d := to.normalized()
		var s := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([arrow_c + d * 9.0, arrow_c - d * 6.0 + s * 6.0, arrow_c - d * 3.0,
			arrow_c - d * 6.0 - s * 6.0]), UITheme.ACCENT)
	var dist := Vector2(at.x - from.x, at.z - from.z).length()
	var how_far := "%d m" % roundi(dist) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
	draw_string(font, arrow_c + Vector2(16, 6), "%s  %s" % [name_text, how_far], HORIZONTAL_ALIGNMENT_LEFT, RADIUS * 2.0 + 30.0, 13,
		Color(1, 1, 1, 0.85))
