extends Node
## Player settings and input bindings, saved to user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name := "Rider"
var last_ip := "127.0.0.1"
var assist := 0.5          # 0 = full sim, 1 = maximum riding assistance
var auto_shift := true
var high_quality := true
var current_build: Dictionary = {}


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
		current_build = cfg.get_value("garage", "build", {})
	current_build = PartsDB.sanitize_build(current_build)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.set_value("riding", "assist", assist)
	cfg.set_value("riding", "auto_shift", auto_shift)
	cfg.set_value("video", "high_quality", high_quality)
	cfg.set_value("garage", "build", current_build)
	cfg.save(PATH)


func _setup_inputs() -> void:
	_bind("throttle", [KEY_W, KEY_UP], [JOY_AXIS_TRIGGER_RIGHT], [])
	_bind("front_brake", [KEY_S, KEY_DOWN], [JOY_AXIS_TRIGGER_LEFT], [])
	_bind("rear_brake", [KEY_SPACE], [], [JOY_BUTTON_B])
	_bind("lean_left", [KEY_A, KEY_LEFT], [], [])
	_bind("lean_right", [KEY_D, KEY_RIGHT], [], [])
	_bind("body_back", [KEY_SHIFT], [], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("body_forward", [KEY_CTRL], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("shift_up", [KEY_E], [], [JOY_BUTTON_A])
	_bind("shift_down", [KEY_Q], [], [JOY_BUTTON_X])
	_bind("respawn", [KEY_R], [], [JOY_BUTTON_Y])
	_bind("garage", [KEY_G], [], [JOY_BUTTON_BACK])
	_bind("camera", [KEY_C], [], [JOY_BUTTON_RIGHT_STICK])
	_bind("toggle_auto_shift", [KEY_T], [], [])
	_bind("help", [KEY_F1], [], [])
	_bind("menu", [KEY_ESCAPE], [], [JOY_BUTTON_START])
	# Left stick steers (leans) the bike.
	for pair in [["lean_left", -1.0], ["lean_right", 1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_X
		ev.axis_value = pair[1]
		InputMap.action_add_event(pair[0], ev)
	for pair in [["body_back", 1.0], ["body_forward", -1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_Y
		ev.axis_value = pair[1]
		InputMap.action_add_event(pair[0], ev)


func _bind(action: String, keys: Array, axes: Array, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for axis in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = 1.0
		InputMap.action_add_event(action, ev)
	for button in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)
