class_name HUD
extends Control
## Kept small on purpose: a crosshair with what you're looking at, a work progress ring and the
## tool bar when on foot; a compact speedo when riding. Everything else lives in the Esc menu.

var walker: Walker
var bike: Bike
var _message: Label
var _message_timer := 0.0
var _info: Label
var _prompt: Label
var _top_kmh := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message = UITheme.title("", 28, Color(1, 0.85, 0.7))
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_left = -500
	_message.offset_right = 500
	_message.offset_top = 40
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_constant_override("outline_size", 8)
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_message)
	_info = UITheme.label("", 17, Color(1, 1, 1, 0.92))
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_info.offset_left = 40
	_info.offset_right = 560
	_info.offset_top = 30
	_info.offset_bottom = 200
	_info.add_theme_constant_override("outline_size", 6)
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_info)
	_prompt = UITheme.label("", 18, UITheme.ACCENT)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = 40
	_prompt.offset_right = 600
	_prompt.offset_top = -12
	_prompt.offset_bottom = 20
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_prompt)


func flash(text: String, seconds := 2.5, bad := false) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if bad else Color(1, 0.85, 0.7))
	_message_timer = seconds


func _process(delta: float) -> void:
	_message_timer -= delta
	if _message_timer <= 0.0 and _message.text != "":
		_message.text = ""
	var on_foot := walker != null and bike == null
	_info.visible = on_foot
	_prompt.visible = on_foot
	if on_foot:
		_info.text = walker.info
		var plan := walker.plan
		if plan.is_empty():
			_prompt.text = ""
		elif plan["blocked"] != "":
			_prompt.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
			_prompt.text = plan["blocked"]
		else:
			_prompt.add_theme_color_override("font_color", UITheme.ACCENT)
			_prompt.text = "Hold %s to %s" % [_act_key(), plan["verb"]]
	if bike and bike.is_crashed:
		_message.text = "Crashed! Press R to get back on"
		_message_timer = 0.1
	queue_redraw()


func _act_key() -> String:
	return "RT" if Controls.device() >= 0 and Controls.active_device >= 0 else "left mouse"


func _draw() -> void:
	if bike:
		_draw_speedo()
	elif walker:
		_draw_crosshair()
		_draw_toolbar()


func _draw_crosshair() -> void:
	var c := size * 0.5
	var col := UITheme.ACCENT if not walker.target.is_empty() else Color(1, 1, 1, 0.7)
	draw_circle(c, 3.0, Color(0, 0, 0, 0.5))
	draw_circle(c, 2.0, col)
	if walker.progress > 0.0:
		draw_arc(c, 18.0, 0.0, TAU, 40, Color(0, 0, 0, 0.4), 5.0, true)
		draw_arc(c, 18.0, -PI * 0.5, -PI * 0.5 + TAU * walker.progress, 40, UITheme.ACCENT, 5.0, true)


func _draw_toolbar() -> void:
	var font := get_theme_default_font()
	var n := Walker.TOOLS.size()
	var w := 120.0
	var x0 := size.x * 0.5 - n * (w + 8.0) * 0.5
	var y := size.y - 70.0
	for i in n:
		var t: String = Walker.TOOLS[i]
		var r := Rect2(x0 + i * (w + 8.0), y, w, 46)
		var active := t == walker.tool
		draw_rect(r, Color(0.05, 0.06, 0.08, 0.75 if active else 0.45))
		if active:
			draw_rect(r, UITheme.ACCENT, false, 2.0)
		draw_string(font, r.position + Vector2(8, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
		var label: String = {"hands": "Hands", "wrench": "Wrench", "brush": "Brush", "repair": "Grinder", "spray": "Spray can"}[t]
		draw_string(font, r.position + Vector2(0, 34), label, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color.WHITE if active else Color(1, 1, 1, 0.65))
	if walker.tool == "spray":
		_draw_spray_picker(font, y)
	var held := Shed.held_by(Shed.me())
	if held != 0:
		draw_string(font, Vector2(0, y - 10), "Carrying: " + Shed.item_title(held), HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, UITheme.ACCENT)


## The spray can's colour swatches and finishes, above the tool bar while it's in your hand.
func _draw_spray_picker(font: Font, toolbar_y: float) -> void:
	var n := Shed.PAINTS.size()
	var sw := 30.0
	var gap := 6.0
	var total := n * (sw + gap) - gap
	var x0 := size.x * 0.5 - total * 0.5
	var y := toolbar_y - 120.0
	draw_rect(Rect2(x0 - 14, y - 32, total + 28, 104), Color(0.05, 0.06, 0.08, 0.7))
	draw_string(font, Vector2(x0, y - 12), "SPRAY CAN  ·  %s" % walker.spray_text().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.ACCENT)
	for i in n:
		var r := Rect2(x0 + i * (sw + gap), y, sw, sw)
		if i == walker.spray_color:
			r = r.grow(4.0)
		draw_rect(r, Shed.PAINTS[i])
		if i == walker.spray_color:
			draw_rect(r.grow(2.0), Color.WHITE, false, 2.0)
	var fx := x0
	for i in Shed.FINISHES.size():
		var label: String = Shed.FINISH_NAMES[Shed.FINISHES[i]]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0
		var r := Rect2(fx, y + 42, w, 24)
		var on := i == walker.spray_finish
		draw_rect(r, Color(1, 1, 1, 0.18) if on else Color(1, 1, 1, 0.05))
		if on:
			draw_rect(r, UITheme.ACCENT, false, 2.0)
		draw_string(font, r.position + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if on else Color(1, 1, 1, 0.6))
		fx += w + 6.0
	var pad := Controls.device() >= 0 and Controls.active_device >= 0
	var hint := "X: colour   B: finish" if pad else "R or right mouse: colour   T or middle mouse: finish"
	draw_string(font, Vector2(x0, y + 90), hint, HORIZONTAL_ALIGNMENT_LEFT, total, 14, Color(1, 1, 1, 0.6))


## The speedo shows what the bike's dashboard can: an old analogue clock gives you only speed,
## a race logger adds revs, gear, a shift light and your top speed.
func _draw_speedo() -> void:
	if bike.build == null:
		return
	var features: Array = bike.build.dash_features
	var font := get_theme_default_font()
	var r := Rect2(size.x - 250, size.y - 120, 226, 96)
	draw_rect(r, Color(0.03, 0.03, 0.04, 0.6))
	var kmh := roundi(absf(bike.speed) * 3.6)
	_top_kmh = maxf(_top_kmh, absf(bike.speed) * 3.6)
	draw_string(font, r.position + Vector2(12, 58), "%d" % kmh, HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
	draw_string(font, r.position + Vector2(120, 34), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.6))
	if features.has("gear"):
		draw_string(font, r.position + Vector2(120, 60), "GEAR %d" % bike.gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.ACCENT)
	if features.has("top_speed"):
		draw_string(font, r.position + Vector2(170, 34), "TOP %d" % roundi(_top_kmh), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var frac := clampf(bike.rpm / bike.build.redline, 0.0, 1.0)
	if features.has("rpm"):
		draw_rect(Rect2(r.position + Vector2(12, 74), Vector2(202, 8)), Color(1, 1, 1, 0.12))
		var col := UITheme.ACCENT if frac < 0.92 else Color(1, 0.2, 0.15)
		draw_rect(Rect2(r.position + Vector2(12, 74), Vector2(202 * frac, 8)), col)
	if features.has("shift_light") and frac > 0.88:
		draw_circle(r.position + Vector2(206, 18), 8.0, Color(1, 0.15, 0.1) if frac > 0.94 else Color(1, 0.85, 0.1))
	if absf(bike.speed) < 2.0 and not bike.is_crashed:
		draw_string(font, Vector2(0, size.y - 40), "Press F (or Y) to get off", HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.7))
