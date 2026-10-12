class_name HUD
extends Control
## Speedometer, tachometer, gear, riding hints and the player list.

var bike: Bike
var _help: PanelContainer
var _message: Label
var _players: Label
var _info: Label
var _message_timer := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message = UITheme.title("", 40, Color(1, 0.85, 0.7))
	_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message.position = Vector2(-300, 120)
	_message.size = Vector2(600, 60)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_message)
	_info = UITheme.label("", 16, Color(1, 1, 1, 0.75))
	_info.position = Vector2(24, 20)
	_info.size = Vector2(700, 80)
	add_child(_info)
	_players = UITheme.label("", 16, Color(1, 1, 1, 0.85))
	_players.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_players.position = Vector2(-280, 20)
	_players.size = Vector2(260, 300)
	_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_players)
	_help = PanelContainer.new()
	_help.position = Vector2(24, 90)
	var help_text := UITheme.label("""W / Up: throttle      S / Down: front brake      Space: rear brake
A / D: lean left / right      Shift: weight back (wheelie)      Ctrl: weight forward
E / Q: shift up / down      T: toggle auto-shift      R: reset bike
G: garage (when stopped)      C: camera      Esc: menu      F1: hide this help
A gamepad works too: triggers for throttle and brake, left stick to lean.""", 16)
	help_text.custom_minimum_size = Vector2(640, 0)
	_help.add_child(help_text)
	add_child(_help)


func toggle_help() -> void:
	_help.visible = not _help.visible


func flash(text: String, seconds := 2.5) -> void:
	_message.text = text
	_message_timer = seconds


func set_players(names: Array) -> void:
	_players.text = "" if names.is_empty() else "Riders online\n" + "\n".join(names)


func _process(delta: float) -> void:
	_message_timer -= delta
	if _message_timer <= 0.0 and _message.text != "":
		_message.text = ""
	if bike and bike.build:
		var shift := "auto" if bike.auto_shift else "manual"
		_info.text = "Surface: %s     Gearbox: %s     Assist: %d%%" % [bike.surface, shift, roundi(bike.assist * 100)]
		if bike.is_crashed:
			_message.text = "Crashed! Press R to get back on"
			_message_timer = 0.1
	queue_redraw()


func _draw() -> void:
	if bike == null or bike.build == null:
		return
	var font := get_theme_default_font()
	var center := Vector2(size.x - 170, size.y - 150)
	var radius := 115.0
	draw_circle(center, radius + 14, Color(0.02, 0.02, 0.03, 0.6))
	# Tacho arc from 225 deg to -45 deg.
	var a0 := deg_to_rad(135.0)
	var a1 := deg_to_rad(405.0)
	var max_rpm := ceilf(bike.build.redline / 1000.0 + 1.0) * 1000.0
	draw_arc(center, radius, a0, a1, 64, Color(1, 1, 1, 0.15), 10.0, true)
	var red_from := lerpf(a0, a1, bike.build.redline / max_rpm)
	draw_arc(center, radius, red_from, a1, 24, Color(1, 0.15, 0.1, 0.7), 10.0, true)
	var frac := clampf(bike.rpm / max_rpm, 0.0, 1.0)
	var col := UITheme.ACCENT if bike.rpm < bike.build.redline * 0.92 else Color(1, 0.2, 0.15)
	draw_arc(center, radius, a0, lerpf(a0, a1, frac), 64, col, 10.0, true)
	var k := 0
	while k <= int(max_rpm / 1000.0):
		var a := lerpf(a0, a1, k * 1000.0 / max_rpm)
		var p := center + Vector2(cos(a), sin(a)) * (radius - 26)
		draw_string(font, p - Vector2(6, -6), str(k), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 1, 1, 0.6))
		k += 1
	var kmh := roundi(absf(bike.speed) * 3.6)
	draw_string(font, center + Vector2(-60, 14), "%d" % kmh, HORIZONTAL_ALIGNMENT_CENTER, 120, 54, Color.WHITE)
	draw_string(font, center + Vector2(-60, 40), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(1, 1, 1, 0.6))
	draw_string(font, center + Vector2(-60, 82), "GEAR %d" % bike.gear, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, UITheme.ACCENT)
	# Throttle and brake bars.
	var bx := center.x - radius - 40
	draw_rect(Rect2(bx, center.y - 60, 10, 120), Color(1, 1, 1, 0.1))
	draw_rect(Rect2(bx, center.y + 60 - 120 * bike.throttle, 10, 120 * bike.throttle), Color(0.3, 0.9, 0.4))
	draw_rect(Rect2(bx - 16, center.y - 60, 10, 120), Color(1, 1, 1, 0.1))
	var brake := maxf(bike.front_brake, bike.rear_brake)
	draw_rect(Rect2(bx - 16, center.y + 60 - 120 * brake, 10, 120 * brake), Color(1, 0.3, 0.25))
