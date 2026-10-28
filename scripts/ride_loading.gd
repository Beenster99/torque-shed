class_name RideLoading
extends CanvasLayer
## The card shown while a ride's road is got ready (AdventureTrip.enter): what's being made, step by step, with a bar
## for how far along it all is. The road is planned first (AdventurePlans: the map of that part of the world fetched,
## its roads, rivers and trees read, the road planned along them and the land along it shaped), then behind the fade
## the roads round the start are built (RoadStreamer.preload_round_async) and you're set down there. Over the fade, so
## it shows on the black too.

## Each step: what it says while it's on, and its share of the bar.
const STEPS := [["Fetching the map of this part of the world", 0.15], ["Reading its roads, rivers and trees", 0.08],
	["Planning the road", 0.07], ["Shaping the land along it", 0.35], ["Building the roads round the start", 0.3],
	["Setting you down at the start", 0.05]]
const BUILD := 4
const SET_DOWN := 5
const DONE_COL := Color(0.45, 0.8, 0.45)
const TO_COME_COL := Color(0.45, 0.47, 0.5)

## Where it's got to: the step on now, and how far through it (0..1).
var step := 0
var through := 0.0
var _bar: ProgressBar
var _detail: Label
var _route: Label
var _rows: Array = []   # [dot (ColorRect), label] for each step


func _init() -> void:
	layer = 95
	name = "RideLoading"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)
	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = UITheme.PANEL_BG
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", bg)
	panel.custom_minimum_size = Vector2(560, 0)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UITheme.title("Getting the road ready", 28))
	_route = _text("", 16, Color(0.85, 0.87, 0.9))
	_route.visible = false
	box.add_child(_route)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 20)
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	box.add_child(_bar)
	_detail = _text("", 16, UITheme.ACCENT)
	box.add_child(_detail)
	for st: Array in STEPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var l := _text(str(st[0]), 15, TO_COME_COL)
		row.add_child(l)
		box.add_child(row)
		_rows.append([dot, l])
	show_step(0)


static func _text(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The ride it's for, under the title ("Dales tour: 86 km").
func set_route(text: String) -> void:
	_route.text = text
	_route.visible = text != ""


## On step `i` (STEPS), `done` of `total` through it (total 0: not counted), with `detail` said under the bar (or
## the step's own words).
func show_step(i: int, done := 0, total := 0, detail := "") -> void:
	step = clampi(i, 0, STEPS.size() - 1)
	through = clampf(float(done) / total, 0.0, 1.0) if total > 0 else 0.0
	var at := 0.0
	for k in step:
		at += float(STEPS[k][1])
	at += float(STEPS[step][1]) * through
	_bar.value = at * 100.0
	var words: String = detail if detail != "" else str(STEPS[step][0])
	_detail.text = "%s, %d of %d..." % [words, done, total] if total > 0 and detail == "" else words + "..."
	for k in _rows.size():
		var dot: ColorRect = _rows[k][0]
		var l: Label = _rows[k][1]
		var col := DONE_COL if k < step else (UITheme.ACCENT if k == step else TO_COME_COL)
		dot.color = col
		l.add_theme_color_override("font_color", col if k != step else Color(0.95, 0.96, 0.97))


## How far along the bar is (0..1).
func fraction() -> float:
	return _bar.value / 100.0


## The words under the bar (tests).
func detail_text() -> String:
	return _detail.text
