extends Node
## Player settings and input bindings, saved to user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name := "Rider"
var last_ip := "127.0.0.1"
var assist := 0.5          # 0 = full sim, 1 = maximum riding assistance
var auto_shift := true
var high_quality := true
var sfx_volume := 0.8
var radio_volume := 0.6
var units := "metric"     # or "imperial"
var day_night_cycle := true
var day_length := 20       # real minutes per 24 h game day
var time_of_day := 9.0     # hours; kept up to date while playing so the clock carries on next time


func _ready() -> void:
	_setup_inputs()
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_name = cfg.get_value("player", "name", player_name)
		last_ip = cfg.get_value("player", "last_ip", last_ip)
		assist = cfg.get_value("riding", "assist", assist)
		auto_shift = cfg.get_value("riding", "auto_shift", auto_shift)
		high_quality = cfg.get_value("video", "high_quality", high_quality)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		radio_volume = cfg.get_value("audio", "radio", radio_volume)
		units = cfg.get_value("display", "units", units)
		day_night_cycle = cfg.get_value("world", "day_night_cycle", day_night_cycle)
		day_length = int(cfg.get_value("world", "day_length", day_length))
		time_of_day = float(cfg.get_value("world", "time_of_day", time_of_day))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.set_value("riding", "assist", assist)
	cfg.set_value("riding", "auto_shift", auto_shift)
	cfg.set_value("video", "high_quality", high_quality)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "radio", radio_volume)
	cfg.set_value("display", "units", units)
	cfg.set_value("world", "day_night_cycle", day_night_cycle)
	cfg.set_value("world", "day_length", day_length)
	cfg.set_value("world", "time_of_day", time_of_day)
	cfg.save(PATH)


## Keyboard, mouse and gamepad-button bindings. Gamepad sticks and triggers are read by the
## Controls autoload instead, so a stuck or odd axis can't hold an action down.
func _setup_inputs() -> void:
	# Riding
	_bind("throttle", [KEY_W, KEY_UP], [])
	_bind("front_brake", [KEY_S, KEY_DOWN], [])
	_bind("rear_brake", [KEY_SPACE], [JOY_BUTTON_B])
	_bind("lean_left", [KEY_A, KEY_LEFT], [])
	_bind("lean_right", [KEY_D, KEY_RIGHT], [])
	_bind("body_back", [KEY_SHIFT], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("body_forward", [KEY_CTRL], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("shift_up", [KEY_E], [JOY_BUTTON_A])
	_bind("shift_down", [KEY_Q], [JOY_BUTTON_X])
	_bind("respawn", [KEY_R], [JOY_BUTTON_BACK])
	_bind("camera", [KEY_C], [JOY_BUTTON_RIGHT_STICK])
	_bind("toggle_auto_shift", [KEY_T], [])
	_bind("ignition", [KEY_I], [JOY_BUTTON_DPAD_UP])
	_bind("horn", [KEY_H], [JOY_BUTTON_DPAD_DOWN])
	_bind("stopwatch", [KEY_P], [JOY_BUTTON_DPAD_LEFT])
	# On foot in the shed
	_bind("move_forward", [KEY_W, KEY_UP], [])
	_bind("move_back", [KEY_S, KEY_DOWN], [])
	_bind("move_left", [KEY_A, KEY_LEFT], [])
	_bind("move_right", [KEY_D, KEY_RIGHT], [])
	_bind("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	_bind("act", [], [JOY_BUTTON_A], [MOUSE_BUTTON_LEFT])
	_bind("tool_next", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [MOUSE_BUTTON_WHEEL_DOWN])
	_bind("tool_prev", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [MOUSE_BUTTON_WHEEL_UP])
	for i in 8:
		_bind("tool_%d" % (i + 1), [KEY_1 + i], [])
	_bind("spray_colour", [KEY_R], [JOY_BUTTON_X], [MOUSE_BUTTON_RIGHT])
	_bind("spray_finish", [KEY_T], [JOY_BUTTON_B])
	# Point at something and ping it for the crew to see.
	_bind("ping", [KEY_G], [JOY_BUTTON_DPAD_RIGHT], [MOUSE_BUTTON_MIDDLE])
	_bind("rename", [KEY_N], [])
	# The second work button: drains fluids into a held container.
	_bind("alt_act", [KEY_R], [JOY_BUTTON_X], [MOUSE_BUTTON_RIGHT])
	_bind("crouch", [KEY_C, KEY_CTRL], [JOY_BUTTON_RIGHT_STICK])
	# At the whiteboard: write a line of text, undo your last mark (Z or Ctrl+Z), hold to wipe it.
	_bind("board_text", [KEY_T], [])
	_bind("board_undo", [KEY_Z], [JOY_BUTTON_DPAD_LEFT])
	_bind("board_wipe", [KEY_X], [])
	# Both
	_bind("interact", [KEY_F], [JOY_BUTTON_Y])
	_bind("menu", [KEY_ESCAPE], [JOY_BUTTON_START])


func _bind(action: String, keys: Array, buttons: Array, mouse := []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button in buttons:
		var ev := InputEventJoypadButton.new()
		ev.device = -1   # any controller, not just the first one Windows lists
		ev.button_index = button
		InputMap.action_add_event(action, ev)
	for button in mouse:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)
