class_name DynoGraph
extends Control
## The dyno's printout: power and torque against rpm (two charts sharing the rpm axis), the
## speed in each gear, and the headline numbers. The run before is drawn dashed behind the
## latest one so a change can be compared before and after. Used on the tuning computer and
## the big screen in the dyno room.

const BG := Color(0.035, 0.045, 0.06)
const PANEL := Color(1, 1, 1, 0.035)
const GRID := Color(1, 1, 1, 0.07)
const AXIS := Color(1, 1, 1, 0.28)
const INK := Color(0.9, 0.92, 0.95)
const INK_DIM := Color(1, 1, 1, 0.55)
const POWER := Color("#d9771f")    # validated pair for the dark surface
const TORQUE := Color("#3b8fe0")
const GEARS := Color(0.8, 0.82, 0.86)
const GOOD := Color(0.35, 0.9, 0.45)
const BAD := Color(1.0, 0.42, 0.32)

var title := ""
var runs: Array = []          # the previous run (if any), then the latest
var progress := 1.0           # how much of the latest run's sweep has been drawn: <0 before it starts
var live := {}                # {rpm, gear} while it's running
var message := ""             # shown when there's nothing to plot


func _init() -> void:
	clip_contents = true


func show_runs(new_title: String, new_runs: Array, new_progress := 1.0, new_live := {}, new_message := "") -> void:
	title = new_title
	runs = new_runs
	progress = new_progress
	live = new_live
	message = new_message
	queue_redraw()


func _k() -> float:
	return clampf(minf(size.x / 1280.0, size.y / 720.0), 0.5, 2.0)


func _text(pos: Vector2, text: String, font_size: float, color := INK, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(get_theme_default_font(), pos, text, align, width, int(font_size * _k()), color)


func _latest() -> Dictionary:
	return runs[-1] if not runs.is_empty() else {}


func _previous() -> Dictionary:
	return runs[-2] if runs.size() >= 2 else {}


func _draw() -> void:
	var k := _k()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var pad := 18.0 * k
	_text(Vector2(pad, 38.0 * k), title, 26, POWER)
	if not live.is_empty():
		var g := int(live.get("gear", 0))
		_text(Vector2(size.x - pad - 420.0 * k, 38.0 * k), "%5d rpm   %s" % [roundi(float(live["rpm"])), "N" if g == 0 else "GEAR %d" % g],
			24, INK, 420.0 * k, HORIZONTAL_ALIGNMENT_RIGHT)
	if runs.is_empty():
		_text(Vector2(pad, size.y * 0.5), message if message != "" else "No runs yet.", 24, INK_DIM, size.x - pad * 2.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		return
	_legend(Vector2(pad, 66.0 * k))
	var top := 84.0 * k
	var tiles_h := 112.0 * k
	var body := Rect2(pad, top, size.x - pad * 2.0, size.y - top - tiles_h - pad * 1.5)
	var left := Rect2(body.position, Vector2(body.size.x * 0.6, body.size.y))
	var right := Rect2(body.position + Vector2(left.size.x + pad, 0.0), Vector2(body.size.x - left.size.x - pad, body.size.y))
	var half := (left.size.y - pad) * 0.5
	var rpm_max := _rpm_max()
	_curve_chart(Rect2(left.position, Vector2(left.size.x, half)), "POWER AT THE WHEEL (hp)", "hp", POWER, rpm_max, false)
	_curve_chart(Rect2(left.position + Vector2(0.0, half + pad), Vector2(left.size.x, half)), "TORQUE AT THE WHEEL (Nm)", "nm", TORQUE, rpm_max, true)
	_gear_chart(right)
	_tiles(Rect2(pad, size.y - tiles_h - pad * 0.5, size.x - pad * 2.0, tiles_h))
	if message != "":
		_text(Vector2(pad, size.y - 6.0 * k), message, 15, INK_DIM, size.x - pad * 2.0)


func _legend(at: Vector2) -> void:
	var k := _k()
	var x := at.x
	var latest := _latest()
	draw_line(Vector2(x, at.y - 6.0 * k), Vector2(x + 28.0 * k, at.y - 6.0 * k), INK, 2.0 * k)
	_text(Vector2(x + 36.0 * k, at.y), "Run %d (latest)" % int(latest.get("n", 1)), 16, INK)
	x += 220.0 * k
	if not _previous().is_empty():
		draw_dashed_line(Vector2(x, at.y - 6.0 * k), Vector2(x + 28.0 * k, at.y - 6.0 * k), INK_DIM, 2.0 * k, 6.0 * k)
		_text(Vector2(x + 36.0 * k, at.y), "Run %d (previous)" % int(_previous().get("n", 0)), 16, INK_DIM)


func _rpm_max() -> float:
	var top := 0.0
	for run in runs:
		top = maxf(top, float(run.get("redline", 10000.0)))
	return ceilf(top / 1000.0) * 1000.0


## One measure against rpm, with the previous run dashed behind the latest.
func _curve_chart(r: Rect2, label: String, key: String, color: Color, rpm_max: float, show_rpm: bool) -> void:
	var k := _k()
	draw_rect(r, PANEL)
	_text(r.position + Vector2(10.0 * k, 22.0 * k), label, 15, INK_DIM)
	var plot := Rect2(r.position + Vector2(52.0 * k, 32.0 * k), r.size - Vector2(64.0 * k, (58.0 if show_rpm else 42.0) * k))
	var y_max := 1.0
	for run in runs:
		for v in run.get(key, []):
			y_max = maxf(y_max, float(v))
	y_max = _nice(y_max * 1.1)
	_grid(plot, rpm_max, y_max, show_rpm)
	var prev := _previous()
	if not prev.is_empty():
		var pts := _points(prev, key, plot, rpm_max, y_max, 1.0)
		for i in pts.size() - 1:
			draw_dashed_line(pts[i], pts[i + 1], Color(color, 0.55), 2.0 * k, 6.0 * k)
	var latest := _latest()
	var pts := _points(latest, key, plot, rpm_max, y_max, progress)
	if pts.size() >= 2:
		draw_polyline(pts, color, 2.5 * k, true)
		# Mark the peak once the sweep has passed it.
		var peak_rpm := float(latest.get("peak_hp_rpm" if key == "hp" else "peak_nm_rpm", 0.0))
		var peak := float(latest.get("peak_hp" if key == "hp" else "peak_nm", 0.0))
		if progress >= 1.0 and peak > 0.0:
			var at := _to(plot, peak_rpm, peak, rpm_max, y_max)
			draw_circle(at, 5.0 * k, color)
			draw_circle(at, 2.5 * k, BG)
			_text(at + Vector2(-60.0 * k, -12.0 * k), "%.1f @ %d" % [peak, roundi(peak_rpm)], 15, INK, 120.0 * k, HORIZONTAL_ALIGNMENT_CENTER)


func _points(run: Dictionary, key: String, plot: Rect2, rpm_max: float, y_max: float, upto: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var xs: Array = run.get("rpm", [])
	var ys: Array = run.get(key, [])
	if xs.is_empty() or upto < 0.0:
		return out
	var last := float(xs[-1])
	var stop := lerpf(float(xs[0]), last, clampf(upto, 0.0, 1.0))
	for i in mini(xs.size(), ys.size()):
		var x := float(xs[i])
		if x > stop + 0.5:
			if i > 0:
				# Finish the line part-way to the next sample, so it grows smoothly.
				var x0 := float(xs[i - 1])
				var f := (stop - x0) / maxf(x - x0, 1.0)
				out.append(_to(plot, stop, lerpf(float(ys[i - 1]), float(ys[i]), f), rpm_max, y_max))
			break
		out.append(_to(plot, x, float(ys[i]), rpm_max, y_max))
	return out


func _to(plot: Rect2, x: float, y: float, x_max: float, y_max: float) -> Vector2:
	return Vector2(plot.position.x + plot.size.x * clampf(x / x_max, 0.0, 1.0),
		plot.end.y - plot.size.y * clampf(y / y_max, 0.0, 1.0))


## A round number at or above `v` for an axis top: 1, 2 or 5 times a power of ten, times 2..10.
func _nice(v: float) -> float:
	var mag := pow(10.0, floorf(log(maxf(v, 1.0)) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if v <= m * mag:
			return m * mag
	return 10.0 * mag


func _grid(plot: Rect2, x_max: float, y_max: float, x_labels: bool, x_unit := "rpm", x_step := 1000.0) -> void:
	var k := _k()
	for i in 5:
		var y := plot.end.y - plot.size.y * i / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID if i > 0 else AXIS, 1.0)
		_text(Vector2(plot.position.x - 50.0 * k, y + 5.0 * k), "%d" % roundi(y_max * i / 4.0), 13, INK_DIM, 44.0 * k, HORIZONTAL_ALIGNMENT_RIGHT)
	var steps := int(x_max / x_step)
	var every := maxi(1, ceili(steps / 8.0))
	for i in range(0, steps + 1, every):
		var x := plot.position.x + plot.size.x * (i * x_step) / x_max
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), GRID, 1.0)
		if x_labels:
			var t := "%d" % roundi(i * x_step) if x_unit != "rpm" else ("%dk" % roundi(i * x_step / 1000.0))
			_text(Vector2(x - 30.0 * k, plot.end.y + 18.0 * k), t, 13, INK_DIM, 60.0 * k, HORIZONTAL_ALIGNMENT_CENTER)
	if x_labels:
		_text(Vector2(plot.end.x - 120.0 * k, plot.end.y + 36.0 * k), x_unit, 13, INK_DIM, 120.0 * k, HORIZONTAL_ALIGNMENT_RIGHT)


## Road speed against rpm in each gear: one line per gear, labelled at the rev limiter.
func _gear_chart(r: Rect2) -> void:
	var k := _k()
	draw_rect(r, PANEL)
	_text(r.position + Vector2(10.0 * k, 22.0 * k), "SPEED IN EACH GEAR (rpm)", 15, INK_DIM)
	var plot := Rect2(r.position + Vector2(52.0 * k, 34.0 * k), r.size - Vector2(70.0 * k, 92.0 * k))
	var latest := _latest()
	var prev := _previous()
	var v_max := 50.0
	for run in runs:
		for v in run.get("gears", []):
			v_max = maxf(v_max, _speed(float(v)))
		v_max = maxf(v_max, _speed(float(run.get("top_kmh", 0.0))))
	v_max = ceilf(v_max * 1.08 / 20.0) * 20.0
	var rpm_max := _rpm_max()
	var step := 20.0 if v_max <= 160.0 else 40.0
	_grid(plot, v_max, rpm_max, true, Units.speed_unit(), step)
	if not prev.is_empty():
		for v in prev.get("gears", []):
			draw_dashed_line(_to(plot, 0.0, 0.0, v_max, rpm_max), _to(plot, _speed(float(v)), float(prev["redline"]), v_max, rpm_max),
				Color(GEARS, 0.35), 1.5 * k, 6.0 * k)
	if progress >= 0.0:
		var gears: Array = latest.get("gears", [])
		for g in gears.size():
			var end := _to(plot, _speed(float(gears[g])), float(latest["redline"]), v_max, rpm_max)
			draw_line(_to(plot, 0.0, 0.0, v_max, rpm_max), end, GEARS, 2.0 * k, true)
			_text(end + Vector2(-8.0 * k, -8.0 * k), str(g + 1), 16, INK)
		# Where drag says it tops out.
		var top := _speed(float(latest.get("top_kmh", 0.0)))
		if top > 0.0:
			var x := _to(plot, top, 0.0, v_max, rpm_max).x
			draw_dashed_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), POWER, 1.5 * k, 4.0 * k)
			_text(Vector2(x - 90.0 * k, plot.end.y + 54.0 * k), "top speed %s" % Units.kmh(float(latest["top_kmh"])), 14, INK,
				180.0 * k, HORIZONTAL_ALIGNMENT_CENTER)


func _speed(kmh: float) -> float:
	return kmh / Units.KM_PER_MILE if Units.imperial() else kmh


## The headline numbers, each with its change since the previous run.
func _tiles(r: Rect2) -> void:
	var k := _k()
	var latest := _latest()
	var prev := _previous()
	var done := progress >= 1.0
	var z := float(latest.get("zero_100", -1.0))
	var tiles := [
		["PEAK POWER", "%.1f hp" % float(latest.get("peak_hp", 0.0)), "@ %d rpm" % roundi(float(latest.get("peak_hp_rpm", 0.0))), "peak_hp", 1.0, "%+.1f hp", 0.05],
		["PEAK TORQUE", "%.1f Nm" % float(latest.get("peak_nm", 0.0)), "@ %d rpm" % roundi(float(latest.get("peak_nm_rpm", 0.0))), "peak_nm", 1.0, "%+.1f Nm", 0.05],
		["TOP SPEED", Units.kmh(float(latest.get("top_kmh", 0.0))), "limiter %d rpm" % roundi(float(latest.get("redline", 0.0))), "top_kmh", 1.0, "%+.1f km/h", 0.05],
		["POWER TO WEIGHT", "%d hp/t" % roundi(float(latest.get("hp_per_tonne", 0.0))), "%s dry" % Units.mass(float(latest.get("mass", 0.0))), "hp_per_tonne", 1.0, "%+.0f hp/t", 0.5],
		["0-100 KM/H", "%.2f s" % z if z > 0.0 else "--", "estimate", "zero_100", -1.0, "%+.2f s", 0.005],
	]
	var w := (r.size.x - 12.0 * k * (tiles.size() - 1)) / tiles.size()
	for i in tiles.size():
		var t: Array = tiles[i]
		var box := Rect2(r.position + Vector2(i * (w + 12.0 * k), 0.0), Vector2(w, r.size.y))
		draw_rect(box, PANEL)
		_text(box.position + Vector2(12.0 * k, 24.0 * k), t[0], 14, INK_DIM)
		_text(box.position + Vector2(12.0 * k, 62.0 * k), t[1] if done else "--", 30, INK)
		_text(box.position + Vector2(12.0 * k, 90.0 * k), t[2] if done else "running...", 14, INK_DIM)
		if done and not prev.is_empty():
			var a := float(latest.get(t[3], 0.0))
			var b := float(prev.get(t[3], 0.0))
			if a > 0.0 and b > 0.0 and absf(a - b) >= float(t[6]):
				var better: bool = (a - b) * float(t[4]) > 0.0
				_text(box.position + Vector2(box.size.x - 140.0 * k, 90.0 * k), t[5] % (a - b), 15, GOOD if better else BAD,
					128.0 * k, HORIZONTAL_ALIGNMENT_RIGHT)
