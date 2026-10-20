class_name SatnavPanel
extends Control
## The satnav on the screen while riding a route: an arrow for the next turn, its distance, what to do,
## how far is left and a thin bar for the journey. Off route it says so and points back. See RouteGuide.

const SIZE_PX := Vector2(380.0, 92.0)

var guide: RouteGuide
## Which way the bike points in route coordinates (degrees clockwise from north), to aim the "back" arrow.
var bike_heading := 0.0
## What is drawn: the leg being ridden, shown on the bar's ticks.
var leg := 0


func _init() -> void:
	custom_minimum_size = SIZE_PX
	size = SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	position = Vector2(-SIZE_PX.x * 0.5, 14.0)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if guide == null:
		return
	var warn := guide.off_route
	draw_rect(Rect2(Vector2.ZERO, SIZE_PX), Color(0.05, 0.06, 0.08, 0.84))
	draw_rect(Rect2(Vector2.ZERO, SIZE_PX), Color(1.0, 0.55, 0.1) if warn else Color(0.3, 0.8, 1.0), false, 2.0)
	var accent := Color(1.0, 0.6, 0.2) if warn else Color(0.4, 0.85, 1.0)
	# The arrow, in a square on the left, turned to the manoeuvre.
	var centre := Vector2(46.0, 40.0)
	var deg := guide.arrow_degrees()
	if warn:
		deg = rad_to_deg(atan2(guide.back_dir.x, -guide.back_dir.y)) - bike_heading
	var a := deg_to_rad(deg)
	var pts := PackedVector2Array([Vector2(0, -26), Vector2(20, 2), Vector2(7, 2), Vector2(7, 24), Vector2(-7, 24), Vector2(-7, 2), Vector2(-20, 2)])
	var turned := PackedVector2Array()
	for p in pts:
		turned.append(centre + p.rotated(a))
	draw_colored_polygon(turned, accent)
	var font := ThemeDB.fallback_font
	var dist := guide.next_dist if not warn else guide.off
	draw_string(font, Vector2(92.0, 34.0), RouteGuide.distance_text(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	draw_string(font, Vector2(92.0, 58.0), guide.instruction(), HORIZONTAL_ALIGNMENT_LEFT, SIZE_PX.x - 100.0, 15, Color(0.92, 0.94, 0.96))
	draw_string(font, Vector2(92.0, 78.0), "%s to go  ·  leg %d of %d" % [RouteGuide.distance_text(guide.remaining), leg + 1, guide.journey.leg_count()],
		HORIZONTAL_ALIGNMENT_LEFT, SIZE_PX.x - 100.0, 12, Color(0.65, 0.7, 0.76))
	# The journey as a bar along the bottom.
	var frac := clampf(guide.d / maxf(guide.journey.length_m, 1.0), 0.0, 1.0)
	draw_rect(Rect2(8.0, SIZE_PX.y - 6.0, SIZE_PX.x - 16.0, 3.0), Color(1, 1, 1, 0.18))
	draw_rect(Rect2(8.0, SIZE_PX.y - 6.0, (SIZE_PX.x - 16.0) * frac, 3.0), accent)
