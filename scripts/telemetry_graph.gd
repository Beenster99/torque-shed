class_name TelemetryGraph
extends Control
## Strip charts of a ride's telemetry (see RideTelemetry), one measure per strip on a shared
## time axis: speed, lean and steering, bar torque, slip ratio, slip angle, grip used, loads and
## the controls. Front tyre in blue, rear in orange. The dyno desk shows the whole of the last
## ride; the ride overlay (TelemetryOverlay) uses the same strips for the last few seconds.

const BG := Color(0.035, 0.045, 0.06)
const PANEL := Color(1, 1, 1, 0.035)
const GRID := Color(1, 1, 1, 0.08)
const INK := Color(0.9, 0.92, 0.95)
const INK_DIM := Color(1, 1, 1, 0.55)
const FRONT := Color("#3b8fe0")    # the dyno graph's validated pair for the dark surface
const REAR := Color("#d9771f")
const ONE := Color(0.85, 0.87, 0.9)
const OVER := Color(1.0, 0.42, 0.32)
## The strips: [title, [[channel, colour, name]...], min, max, unit]. A range of [0, 0] fits the data.
const STRIPS := [
	["Speed", [["speed", ONE, ""]], 0.0, 0.0, "km/h"],
	["Lean (+ right)", [["lean", ONE, ""]], -60.0, 60.0, "°"],
	["Steering (+ right)", [["steer", ONE, "bars"]], -10.0, 10.0, "°"],
	["Slip ratio", [["kappa_f", FRONT, "front"], ["kappa_r", REAR, "rear"]], -0.4, 0.4, ""],
	["Slip angle", [["alpha_f", FRONT, "front"], ["alpha_r", REAR, "rear"]], -15.0, 15.0, "°"],
	["Grip used (1 = the limit)", [["grip_f", FRONT, "front"], ["grip_r", REAR, "rear"]], 0.0, 1.5, ""],
	["Tyre load", [["load_f", FRONT, "front"], ["load_r", REAR, "rear"]], 0.0, 0.0, "N"],
	["Throttle and brakes", [["throttle", ONE, "throttle"], ["brake_f", FRONT, "front brake"], ["brake_r", REAR, "rear brake"]], 0.0, 1.0, ""],
	["Gear", [["gear", ONE, ""]], 0.0, 6.0, ""],
	["Revs", [["rpm", ONE, ""]], 0.0, 0.0, "rpm"],
]

var telemetry: RideTelemetry
var seconds := 0.0             # how much of the end of the ride to show; 0 shows all of it
var strips: Array = []         # strip titles to draw; empty draws them all
var font_size := 13
var message := "No ride recorded yet. Ride a bike and come back."
var draw_background := true


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if draw_background:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
	if telemetry == null or telemetry.size() < 2:
		draw_string(get_theme_default_font(), Vector2(12, size.y * 0.5), message, HORIZONTAL_ALIGNMENT_CENTER,
			size.x - 24.0, font_size + 3, INK_DIM)
		return
	var shown := STRIPS.filter(func(s): return strips.is_empty() or strips.has(s[0]))
	var i0 := telemetry.index_since(seconds) if seconds > 0.0 else 0
	var gap := 6.0
	var h := (size.y - gap * (shown.size() + 1)) / maxf(shown.size(), 1)
	var y := gap
	for s in shown:
		draw_strip(self, Rect2(6.0, y, size.x - 12.0, h), telemetry, s, i0, font_size)
		y += h + gap


## One strip: its title, a zero line, and each channel as a thin line over samples i0 to the end.
static func draw_strip(ci: CanvasItem, r: Rect2, tel: RideTelemetry, strip: Array, i0: int, fs := 13) -> void:
	var font: Font = ci.get_theme_default_font() if ci is Control else ThemeDB.fallback_font
	ci.draw_rect(r, PANEL)
	var lo: float = strip[2]
	var hi: float = strip[3]
	var n := tel.size()
	if lo == 0.0 and hi == 0.0:
		for ch in strip[1]:
			var a: PackedFloat32Array = tel.data[ch[0]]
			for i in range(i0, n):
				hi = maxf(hi, a[i])
		hi = maxf(hi * 1.1, 1.0)
	var plot := Rect2(r.position + Vector2(4.0, fs + 6.0), r.size - Vector2(8.0, fs + 9.0))
	var to_y := func(v: float) -> float:
		return plot.position.y + plot.size.y * (1.0 - clampf((v - lo) / maxf(hi - lo, 1e-6), 0.0, 1.0))
	if lo < 0.0 and hi > 0.0:
		var zy: float = to_y.call(0.0)
		ci.draw_line(Vector2(plot.position.x, zy), Vector2(plot.end.x, zy), GRID, 1.0)
	if strip[0].begins_with("Grip used"):
		var ly: float = to_y.call(1.0)
		ci.draw_dashed_line(Vector2(plot.position.x, ly), Vector2(plot.end.x, ly), OVER.darkened(0.2), 1.0, 4.0)
	var t: PackedFloat32Array = tel.data["t"]
	var t0 := t[i0]
	var span := maxf(t[n - 1] - t0, 0.5)
	# At most one point per pixel or two, so a long ride still draws quickly.
	var step := maxi(1, int((n - i0) / maxf(plot.size.x * 0.5, 1.0)))
	var title := "%s" % strip[0]
	var x := r.position.x + 6.0
	ci.draw_string(font, Vector2(x, r.position.y + fs + 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK_DIM)
	x += font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
	for ch in strip[1]:
		var a: PackedFloat32Array = tel.data[ch[0]]
		var pts := PackedVector2Array()
		var i := i0
		while i < n:
			pts.append(Vector2(plot.position.x + plot.size.x * (t[i] - t0) / span, to_y.call(a[i])))
			i += step
		if pts.size() >= 2:
			ci.draw_polyline(pts, ch[1], 1.5, true)
		# The latest value of each line, in ink, with its colour swatch beside it.
		var label := ("%s " % ch[2] if ch[2] != "" else "") + _fmt(a[n - 1], str(strip[4]))
		ci.draw_rect(Rect2(x, r.position.y + fs * 0.5 - 1.0, 10.0, 3.0), ch[1])
		ci.draw_string(font, Vector2(x + 14.0, r.position.y + fs + 2.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
		x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 26.0


static func _fmt(v: float, unit: String) -> String:
	if unit == "N" or unit == "rpm" or unit == "km/h":
		return "%d %s" % [roundi(v), unit]
	if unit == "":
		return "%.2f" % v
	return "%.1f %s" % [v, unit]
