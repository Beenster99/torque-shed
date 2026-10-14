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
var day_length := 120      # real minutes per 24 h game day
var time_of_day := 9.0     # hours; kept up to date while playing so the clock carries on next time
var snap_placement := true # equipment you carry snaps square and flush to walls and corners


## Every action a player can rebind, in the order the Key bindings tab lists them:
## [action, what it does, contexts]. Two actions clash when they share a key or button and a
## context: "foot" (walking about the shed), "ride" (on a bike), "spray" (a spray can or gun in
## your hand, on foot) and "board" (at the whiteboard, where its own keys take over).
const ACTIONS := [
	["move_forward", "Walk forward", ["foot"]], ["move_back", "Walk back", ["foot"]],
	["move_left", "Walk left", ["foot"]], ["move_right", "Walk right", ["foot"]],
	["sprint", "Run", ["foot"]], ["crouch", "Crouch", ["foot"]],
	["act", "Work / use (hold)", ["foot", "board"]], ["alt_act", "Second work button (hold)", ["foot", "board"]],
	["tool_next", "Next tool", ["foot", "board"]], ["tool_prev", "Previous tool", ["foot", "board"]],
	["tool_1", "Hands", ["foot", "board"]], ["tool_2", "Wrench", ["foot", "board"]], ["tool_3", "Brush", ["foot", "board"]],
	["tool_4", "Grinder", ["foot", "board"]], ["tool_5", "Spray can", ["foot", "board"]],
	["tool_6", "Pressure washer", ["foot", "board"]], ["tool_7", "Spray gun", ["foot", "board"]],
	["tool_8", "Stopwatch", ["foot", "board"]],
	["spray_colour", "Spray colour", ["spray"]], ["spray_finish", "Spray finish", ["spray"]],
	["rename", "Name a bike", ["foot"]],
	["interact", "Use / get on / get off", ["foot", "ride"]], ["ping", "Ping", ["foot", "ride"]],
	["stopwatch", "Stopwatch start / stop", ["foot", "ride"]], ["menu", "Menu", ["foot", "ride", "board"]],
	["board_text", "Whiteboard: write text", ["board"]], ["board_undo", "Whiteboard: undo", ["board"]],
	["board_wipe", "Whiteboard: wipe (hold)", ["board"]], ["board_colour", "Whiteboard: next colour", ["board"]],
	["board_image", "Whiteboard: add a picture", ["board"]], ["board_move", "Whiteboard: move a picture", ["board"]],
	["board_bigger", "Whiteboard: picture bigger", ["board"]], ["board_smaller", "Whiteboard: picture smaller", ["board"]],
	["board_poster", "Whiteboard: make a poster", ["board"]],
	["throttle", "Throttle", ["ride"]], ["front_brake", "Front brake", ["ride"]], ["rear_brake", "Rear brake", ["ride"]],
	["lean_left", "Lean left", ["ride"]], ["lean_right", "Lean right", ["ride"]],
	["body_back", "Weight back", ["ride"]], ["body_forward", "Weight forward", ["ride"]],
	["shift_up", "Shift up", ["ride"]], ["shift_down", "Shift down", ["ride"]],
	["toggle_auto_shift", "Auto-shift on / off", ["ride"]], ["ignition", "Engine on / off", ["ride"]],
	["respawn", "Reset after a crash", ["ride"]], ["camera", "Camera", ["ride"]],
	["horn", "Horn", ["ride"]], ["headlight", "Headlight", ["ride"]],
]
const CONTEXT_NAMES := {"foot": "on foot", "ride": "riding", "spray": "with a spray can or gun", "board": "at the whiteboard"}
## Sharing on purpose: with a spray can or gun out, the second button picks the colour.
const SHARED_OK := [["alt_act", "spray_colour"]]
## The spray context sits on top of on foot: a spray key also clashes with on-foot keys.
const CONTEXT_ALSO := {"spray": ["foot"]}

## action -> the events it had before any rebinding, for Reset to defaults.
var _defaults := {}


func _ready() -> void:
	_setup_inputs()
	_pad_ui()
	for a in ACTIONS:
		_defaults[a[0]] = InputMap.action_get_events(a[0]).duplicate()
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
		if cfg.has_section("bindings"):
			for action in cfg.get_section_keys("bindings"):
				var codes = cfg.get_value("bindings", action, [])
				if _defaults.has(action) and (codes is Array or codes is PackedStringArray):
					_set_events(action, codes)
		snap_placement = bool(cfg.get_value("building", "snap", snap_placement))


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
	# Only what differs from the defaults is kept, so new defaults reach everything else.
	for a in ACTIONS:
		var codes := binding_codes(a[0])
		if codes != _codes_of(_defaults.get(a[0], [])):
			cfg.set_value("bindings", a[0], codes)
	cfg.set_value("building", "snap", snap_placement)
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
	_bind("headlight", [KEY_L], [JOY_BUTTON_LEFT_STICK])
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
	# The finish is T or the mouse's back side button: the middle button is ping's.
	_bind("spray_finish", [KEY_T], [JOY_BUTTON_B], [MOUSE_BUTTON_XBUTTON1])
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
	_bind("board_colour", [], [JOY_BUTTON_B])
	# Pictures from your PC on the board: add one, move it about and size it.
	_bind("board_image", [KEY_U], [])
	_bind("board_move", [KEY_M], [JOY_BUTTON_DPAD_UP])
	_bind("board_bigger", [KEY_EQUAL, KEY_KP_ADD], [])
	_bind("board_smaller", [KEY_MINUS, KEY_KP_SUBTRACT], [])
	# Turn what's on the board into a poster to order from the parts computer.
	_bind("board_poster", [KEY_K], [JOY_BUTTON_DPAD_DOWN])
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


## The pad works the menus too: A presses the button in focus and B goes back. (Godot's own
## ui_accept and ui_cancel only have keys; the d-pad and left stick already move the focus.)
func _pad_ui() -> void:
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var ev := InputEventJoypadButton.new()
		ev.device = -1
		ev.button_index = pair[1]
		InputMap.action_add_event(pair[0], ev)


# ---------------------------------------------------------------------------- rebinding

## Whether an event is a gamepad button (as opposed to a key or mouse button).
static func is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton


## The action's bindings as saved: "key:<physical keycode>", "mouse:<button>", "joy:<button>".
func binding_codes(action: String) -> PackedStringArray:
	return _codes_of(InputMap.action_get_events(action) if InputMap.has_action(action) else [])


static func _codes_of(events: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for ev in events:
		var c := code_of(ev)
		if c != "":
			out.append(c)
	return out


static func code_of(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return "key:%d" % k
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "joy:%d" % ev.button_index
	return ""


static func event_of(code: String) -> InputEvent:
	var bits := code.split(":")
	if bits.size() != 2 or not bits[1].is_valid_int():
		return null
	var n := int(bits[1])
	match bits[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = n as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = n as MouseButton
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.device = -1
			j.button_index = n as JoyButton
			return j
	return null


func _set_events(action: String, codes) -> void:
	InputMap.action_erase_events(action)
	for c in codes:
		var ev := event_of(str(c))
		if ev:
			InputMap.action_add_event(action, ev)


## The action's keys and mouse buttons (pad = false) or its pad buttons (pad = true).
func events_of(action: String, pad: bool) -> Array:
	if not InputMap.has_action(action):
		return []
	return InputMap.action_get_events(action).filter(func(e): return code_of(e) != "" and is_pad(e) == pad)


## Puts `ev` on `action` in place of its keyboard and mouse bindings (or its pad button), and saves.
func rebind(action: String, ev: InputEvent) -> void:
	var code := code_of(ev)
	if code == "" or not InputMap.has_action(action):
		return
	var keep := InputMap.action_get_events(action).filter(func(e): return code_of(e) != "" and is_pad(e) != is_pad(ev))
	InputMap.action_erase_events(action)
	for e in keep:
		InputMap.action_add_event(action, e)
	InputMap.action_add_event(action, event_of(code))
	save_settings()


## Takes the action's keyboard and mouse (or pad) bindings off, and saves.
func clear_binding(action: String, pad: bool) -> void:
	for e in events_of(action, pad):
		InputMap.action_erase_event(action, e)
	save_settings()


## Every action back to how the game comes, and saves.
func reset_bindings() -> void:
	for action in _defaults:
		InputMap.action_erase_events(action)
		for e in _defaults[action]:
			InputMap.action_add_event(action, e)
	save_settings()


static func action_name(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


static func _contexts(action: String) -> Array:
	for a in ACTIONS:
		if a[0] == action:
			var out: Array = a[2].duplicate()
			for c in a[2]:
				out.append_array(CONTEXT_ALSO.get(c, []))
			return out
	return []


## Keys or buttons that do two things at once: [{a, b, code, context}].
func clashes() -> Array:
	var out := []
	for i in ACTIONS.size():
		var a: String = ACTIONS[i][0]
		var ca := _contexts(a)
		var mine := binding_codes(a)
		for j in range(i + 1, ACTIONS.size()):
			var b: String = ACTIONS[j][0]
			if SHARED_OK.has([a, b]) or SHARED_OK.has([b, a]):
				continue
			var shared := ""
			for c in _contexts(b):
				if ca.has(c):
					shared = c
					break
			if shared == "":
				continue
			for code in binding_codes(b):
				if mine.has(code):
					out.append({"a": a, "b": b, "code": code, "context": shared})
	return out


## "R is also Spray colour (on foot)" for each clash `action` is in, from `found` (see clashes()).
func clash_text(action: String, found := []) -> String:
	var lines := []
	for c in (found if not found.is_empty() else clashes()):
		if c["a"] == action or c["b"] == action:
			var other: String = c["b"] if c["a"] == action else c["a"]
			lines.append("%s is also %s (%s)" % [code_text(c["code"]), action_name(other), CONTEXT_NAMES[c["context"]]])
	return ", ".join(lines)


const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right", JOY_BUTTON_MISC1: "Share"}
const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down", MOUSE_BUTTON_WHEEL_LEFT: "Wheel left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel right", MOUSE_BUTTON_XBUTTON1: "Mouse back", MOUSE_BUTTON_XBUTTON2: "Mouse forward"}


## A binding as a player reads it: "G", "Middle mouse", "D-pad right".
static func code_text(code: String) -> String:
	var ev := event_of(code)
	if ev is InputEventKey:
		return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	if ev is InputEventMouseButton:
		var mb: int = (ev as InputEventMouseButton).button_index
		return str(MOUSE_NAMES.get(mb, "Mouse %d" % mb))
	if ev is InputEventJoypadButton:
		var jb: int = (ev as InputEventJoypadButton).button_index
		return str(PAD_NAMES.get(jb, "Button %d" % jb))
	return "?"


## The action's keyboard and mouse (or pad) bindings as text, "" when it has none.
func binding_text(action: String, pad: bool) -> String:
	return " / ".join(events_of(action, pad).map(func(e): return code_text(code_of(e))))
