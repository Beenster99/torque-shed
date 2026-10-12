class_name DynoGraph
extends Control
## Torque and power curves from the engine model, like a printout from a dyno run.

const TORQUE_COLOR := Color(1.0, 0.62, 0.2)
const POWER_COLOR := Color(0.35, 0.8, 1.0)

var build: BikeBuild


func show_build(b: BikeBuild) -> void:
	build = b
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var r := Rect2(Vector2(46, 14), size - Vector2(96, 44))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.85))
	if build == null or r.size.x < 10.0:
		return
	var curve := build.dyno_curve(80)
	var max_rpm := build.redline
	var max_tq := 0.0
	var max_kw := 0.0
	for p in curve:
		max_tq = maxf(max_tq, p["torque"])
		max_kw = maxf(max_kw, p["kw"])
	max_tq = ceilf(max_tq / 10.0 + 0.5) * 10.0
	var max_hp := ceilf(max_kw * 1.341 / 10.0 + 0.5) * 10.0
	# Grid
	for i in 5:
		var y := r.position.y + r.size.y * i / 4.0
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(4, y + 4), "%d" % roundi(max_tq * (1.0 - i / 4.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TORQUE_COLOR)
		draw_string(font, Vector2(r.end.x + 6, y + 4), "%d" % roundi(max_hp * (1.0 - i / 4.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, POWER_COLOR)
	var rpm := 2000.0
	while rpm < max_rpm:
		var x := r.position.x + r.size.x * rpm / max_rpm
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.06))
		draw_string(font, Vector2(x - 10, r.end.y + 16), "%dk" % int(rpm / 1000), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
		rpm += 2000.0
	draw_string(font, Vector2(r.position.x, size.y - 4), "Nm", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TORQUE_COLOR)
	draw_string(font, Vector2(r.end.x - 4, size.y - 4), "hp", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, POWER_COLOR)
	# Curves
	var tq_pts := PackedVector2Array()
	var hp_pts := PackedVector2Array()
	for p in curve:
		var x: float = r.position.x + r.size.x * p["rpm"] / max_rpm
		tq_pts.append(Vector2(x, r.end.y - r.size.y * p["torque"] / max_tq))
		hp_pts.append(Vector2(x, r.end.y - r.size.y * p["kw"] * 1.341 / max_hp))
	draw_polyline(tq_pts, TORQUE_COLOR, 2.5, true)
	draw_polyline(hp_pts, POWER_COLOR, 2.5, true)
	var red_x := r.position.x + r.size.x * build.redline / max_rpm
	draw_line(Vector2(red_x, r.position.y), Vector2(red_x, r.end.y), Color(1, 0.2, 0.2, 0.6), 2.0)
