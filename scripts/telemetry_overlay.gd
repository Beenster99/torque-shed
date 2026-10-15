class_name TelemetryOverlay
extends Control
## The live telemetry at the right of the screen while riding (F3, or Settings): speed, gear and
## revs; each tyre's friction circle (where its force sits against its grip: a dot past the
## ring is sliding) with its load; the throttle and brakes; and strip charts of the last few
## seconds (lean, steering, bar torque, slip, grip used, loads). Reads the bike's RideTelemetry.

const WIDTH := 400.0
const WINDOW := 8.0            # seconds of history in the strips
const STRIPS := ["Lean (+ right)", "Steering (+ right)", "Bar torque", "Slip ratio", "Slip angle",
	"Grip used (1 = the limit)", "Tyre load"]

var bike: Bike


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -WIDTH - 12.0
	offset_right = -12.0
	offset_top = 70.0
	offset_bottom = -175.0   # clear of the fuel gauge in the corner


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if bike == null or not is_instance_valid(bike) or bike.telemetry == null:
		return
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, 0.78))
	var ink := TelemetryGraph.INK
	var dim := TelemetryGraph.INK_DIM
	var y := 22.0
	draw_string(font, Vector2(10, y), "TELEMETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.ACCENT)
	draw_string(font, Vector2(110, y), "%s  ·  gear %d  ·  %d rpm" % ["%d %s" % [Units.speed_value(absf(bike.speed)), Units.speed_unit()], bike.gear,
		roundi(bike.rpm / 50.0) * 50], HORIZONTAL_ALIGNMENT_LEFT, size.x - 120.0, 14, ink)
	y += 10.0
	# The two friction circles, front and rear.
	var d := 112.0
	for i in 2:
		var c := Vector2(10.0 + d * 0.5 + i * (d + 16.0), y + d * 0.5 + 18.0)
		_circle(c, d * 0.5 - 4.0, bike.wheels[i], "FRONT" if i == 0 else "REAR",
			TelemetryGraph.FRONT if i == 0 else TelemetryGraph.REAR)
	# Throttle and brakes as bars beside them.
	var bx := 10.0 + 2.0 * (d + 16.0)
	var bars := [["Throttle", bike.throttle, TelemetryGraph.ONE], ["Front brake", bike.front_brake, TelemetryGraph.FRONT],
		["Rear brake", bike.rear_brake, TelemetryGraph.REAR]]
	var by := y + 16.0
	for b in bars:
		draw_string(font, Vector2(bx, by + 12.0), str(b[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
		draw_rect(Rect2(bx, by + 16.0, size.x - bx - 10.0, 8.0), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(bx, by + 16.0, (size.x - bx - 10.0) * clampf(float(b[1]), 0.0, 1.0), 8.0), b[2])
		by += 36.0
	y += d + 30.0
	# The last few seconds as strips.
	var shown := TelemetryGraph.STRIPS.filter(func(s): return STRIPS.has(s[0]) and (bike.direct_bars or s[0] != "Bar torque"))
	var gap := 5.0
	var h := (size.y - y - gap * shown.size()) / maxf(shown.size(), 1)
	var i0 := bike.telemetry.index_since(WINDOW)
	if bike.telemetry.size() - i0 < 2:
		return
	for s in shown:
		TelemetryGraph.draw_strip(self, Rect2(6.0, y, size.x - 12.0, h), bike.telemetry, s, i0, 12)
		y += h + gap


## A tyre's friction circle: the ring is its grip at this load; the dot is where its force sits
## (right is cornering right, up is drive, down is braking), red once it's past the peak.
func _circle(c: Vector2, r: float, w: Dictionary, name: String, color: Color) -> void:
	var font := get_theme_default_font()
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.5, true)
	draw_arc(c, r * 0.5, 0.0, TAU, 32, Color(1, 1, 1, 0.1), 1.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.08))
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(1, 1, 1, 0.08))
	var used: float = w.get("grip_used", 0.0)
	var p := Vector2(-float(w.get("gy", 0.0)), -float(w.get("gx", 0.0)))
	var over := used > 1.0
	draw_circle(c + p * r, 5.0, TelemetryGraph.OVER if over else color)
	draw_string(font, c + Vector2(-r, -r - 6.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TelemetryGraph.INK_DIM)
	var load_text := "%.1f kN" % (float(w.get("load", 0.0)) / 1000.0) if w.get("contact", false) else "in the air"
	draw_string(font, c + Vector2(-r, r + 14.0), load_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TelemetryGraph.INK)
	if over:
		draw_string(font, c + Vector2(r - 34.0, r + 14.0), "SLIDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TelemetryGraph.OVER)
