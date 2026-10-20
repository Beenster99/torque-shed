extends Node
## Gamepad sticks and triggers. Reads whichever controller was used last, and measures each
## axis at rest so a controller (or a stray device such as a wheel or RGB hub) that reports an
## axis stuck at one end can't hold the bike leaned over or the throttle open.
##
## It also knows whether the player is on keyboard and mouse or a pad right now (using_pad),
## and names the key for any action on that device (key, hint): every prompt in the game asks
## here, so the hints follow the player's own bindings and switch the moment they pick up the
## other controls.

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.06

## Mouse moves smaller than this (screen pixels) don't count as switching back to keyboard and mouse.
const MOUSE_SWITCH_PX := 6.0

## The input device a player used last changed: true for a controller, false for keyboard and mouse.
signal device_changed(pad: bool)

var active_device := -1
## Whether the hints show controller buttons: the last real input was a pad button or a stick or
## trigger past its deadzone (true), or a key, mouse button or mouse move (false).
var using_pad := false
var _rest := {}          # device -> {axis: resting value}
var _bound := []         # [weakref to a node, property] whose text follows the device (see bind_text)
var _pad_down := {}      # pad buttons held now, for the chords (see PAD_CHORDS)
var _chord := ""         # the chord held now (its action), "" when none


func _ready() -> void:
	Input.joy_connection_changed.connect(func(device: int, connected: bool):
		_pad_down.clear()
		if connected:
			_rest.erase(device)
		elif device == active_device:
			active_device = -1
			if Input.get_connected_joypads().is_empty():
				set_using_pad(false))
	# Every event passes the window before any node sees it, so a handled key still counts.
	get_tree().root.window_input.connect(_note_device)
	get_tree().root.window_input.connect(_note_chord)
	device_changed.connect(_rebind_texts)


func _input(event: InputEvent) -> void:
	_note_chord(event)
	if event is InputEventJoypadButton and event.pressed:
		active_device = event.device
	elif event is InputEventJoypadMotion:
		var rest := _rest_value(event.device, event.axis)
		if absf(event.axis_value - rest) > 0.5:
			active_device = event.device
	_note_device(event)


## Switches the hints between the controller and keyboard and mouse on real input.
func _note_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if event.pressed:
			set_using_pad(true)
	elif event is InputEventJoypadMotion:
		# A stray device (a wheel, an RGB hub) that chatters an axis mustn't flip the hints: only
		# a standard pad, or one whose buttons have been pressed, counts.
		if not (Input.is_joy_known(event.device) or event.device == active_device):
			return
		var trig: bool = event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT
		var rest := _rest_value(event.device, event.axis)
		var v: float = event.axis_value - rest
		if trig and rest < -0.5:
			v *= 0.5
		if absf(v) > (TRIGGER_DEADZONE * 4.0 if trig else STICK_DEADZONE * 1.5):
			set_using_pad(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.pressed:
			set_using_pad(false)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).screen_relative.length() > MOUSE_SWITCH_PX:
			set_using_pad(false)


func set_using_pad(pad: bool) -> void:
	if pad == using_pad:
		return
	using_pad = pad
	device_changed.emit(pad)


# ---------------------------------------------------------------------------- hint labels

## What the pad does for an action without a button of its own: the triggers are the throttle
## and front brake; the left stick walks and leans.
const PAD_FIXED := {"throttle": "RT", "front_brake": "LT"}
const PAD_STICKS := {"move_forward": "Left stick", "move_back": "Left stick", "move_left": "Left stick",
	"move_right": "Left stick", "lean_left": "Left stick", "lean_right": "Left stick",
	"body_back": "Left stick", "body_forward": "Left stick"}
## Pad buttons pressed together for an action of their own: LB and RB start the engine (each on
## its own is the clutch and the look over your shoulder). Fixed, as the sticks are.
const PAD_CHORDS := {"ignition": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]}
## Hint names that aren't one rebindable action: [keyboard and mouse, controller].
const VIRTUAL := {"look": ["Mouse", "Right stick"], "aim": ["Mouse", "Right stick"],
	"scroll": ["Mouse wheel", "LB / RB"]}
## Holding work (or work-two) is the right (left) trigger on a pad as well as its button; a tap
## is the button. "work" and "work2" name the hold: the act and alt_act keys, or RT and LT.
const HOLDS := {"work": ["act", "RT"], "work2": ["alt_act", "LT"]}


## The key, mouse button or pad button that does `action` on the device in use, as a player
## reads it ("F", "Left mouse", "Y", "RT"), from the player's own bindings (Key bindings tab).
## Also takes "work" and "work2" (holding act or alt_act), "move" (W A S D or the left stick),
## "lean" (A / D or the left stick), "back" (closing a screen: the menu key, or B), "look", "aim"
## and "scroll".
func key(action: String, pad := using_pad) -> String:
	match action:
		"move":
			if pad:
				return "Left stick"
			return " ".join(["move_forward", "move_left", "move_back", "move_right"].map(func(a): return key(a, false)))
		"lean":
			return "Left stick" if pad else keys("lean_left", "lean_right", false)
		"back":
			return key("ui_cancel", true) if pad else key("menu", false)
	if HOLDS.has(action):
		return HOLDS[action][1] if pad else key(HOLDS[action][0], false)
	if VIRTUAL.has(action):
		return VIRTUAL[action][1 if pad else 0]
	if pad and PAD_FIXED.has(action):
		return PAD_FIXED[action]
	var label := _first_label(action, pad)
	if label == "" and pad:
		label = fixed_pad(action)
	if label == "":
		# Nothing on this device: the other device's binding is still the way to do it.
		label = _first_label(action, not pad)
	return label if label != "" else "-"


## What the pad does an action with that isn't a button of its own: a chord ("LB + RB"), a
## trigger ("RT") or a stick ("Left stick"); "" when it has none.
func fixed_pad(action: String) -> String:
	if PAD_CHORDS.has(action):
		return " + ".join(PAD_CHORDS[action].map(func(b): return str(Settings.PAD_NAMES.get(b, b))))
	return str(PAD_FIXED.get(action, PAD_STICKS.get(action, "")))


## Whether a chord's buttons are held (see PAD_CHORDS): from the press that made it till all of
## them are let go, so the buttons' own actions (the look back) can stand aside meanwhile.
func chord_held() -> bool:
	return _chord != ""


## Watches the pad buttons for a chord: the last of its buttons going down does its action, as if
## its own button had been pressed. Called from both the window and _input (the same press only
## counts once), so a press a node has handled still counts.
func _note_chord(event: InputEvent) -> void:
	if not event is InputEventJoypadButton:
		return
	var b: int = (event as InputEventJoypadButton).button_index
	if not event.pressed:
		_pad_down.erase(b)
		if _chord != "" and not PAD_CHORDS[_chord].any(func(c): return _pad_down.has(c)):
			_chord = ""
		return
	if _pad_down.has(b):
		return
	_pad_down[b] = true
	for action in PAD_CHORDS:
		var chord: Array = PAD_CHORDS[action]
		if chord.has(b) and chord.all(func(c): return _pad_down.has(c)):
			_chord = action
			_press_action.call_deferred(action)


## The action pressed and let go again, through the input like a real button.
func _press_action(action: String) -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		ev.strength = 1.0 if down else 0.0
		Input.parse_input_event(ev)


## Two actions' labels for a pair of hints: "Q / E", "LB / RB".
func keys(a: String, b: String, pad := using_pad) -> String:
	var ka := key(a, pad)
	var kb := key(b, pad)
	if [ka, kb] in [["Wheel up", "Wheel down"], ["Wheel down", "Wheel up"]]:
		return "Mouse wheel"
	return ka if ka == kb else "%s / %s" % [ka, kb]


## A hint with each {action} (or {action|action} for a pair) swapped for its key on the device
## in use: "{interact}: get on" reads "F: get on" or "Y: get on". Braces round anything that
## isn't an action stay as they are. Messages the host sends keep their {action}s, so each
## player reads their own keys: the HUD and the computers' status lines run them through this.
func hint(text: String, pad := using_pad) -> String:
	if text.find("{") < 0:
		return text
	var out := ""
	var i := 0
	while i < text.length():
		var open := text.find("{", i)
		var close := text.find("}", open + 1) if open >= 0 else -1
		if close < 0:
			out += text.substr(i)
			break
		var bits := text.substr(open + 1, close - open - 1).split("|")
		if bits.size() > 2 or not Array(bits).all(_known):
			out += text.substr(i, open + 1 - i)
			i = open + 1
			continue
		out += text.substr(i, open - i)
		out += keys(bits[0], bits[1], pad) if bits.size() == 2 else key(bits[0], pad)
		i = close + 1
	return out


## Sets a label's or button's text from a hint (see hint) and keeps it in step with the
## device: it reads again whenever the player switches between pad and keyboard.
func bind_text(node: Object, template: String, prop := "text") -> void:
	var meta := "hint_" + prop
	if template.find("{") < 0 and not node.has_meta(meta):
		node.set(prop, template)
		return
	if not node.has_meta(meta):
		_bound.append([weakref(node), prop])
	node.set_meta(meta, template)
	node.set(prop, hint(template))


func _rebind_texts(_pad: bool) -> void:
	var keep := []
	for b in _bound:
		var node: Object = b[0].get_ref()
		if node != null:
			node.set(b[1], hint(str(node.get_meta("hint_" + b[1], ""))))
			keep.append(b)
	_bound = keep


func _known(action: String) -> bool:
	return action in ["move", "lean", "back"] or HOLDS.has(action) or VIRTUAL.has(action) or (action != "" and InputMap.has_action(action))


## The action's first binding on the device; the mouse's main buttons and wheel come before keys
## (work is the left mouse, the wheel picks tools), but G beats the middle button for ping.
func _first_label(action: String, pad: bool) -> String:
	if not InputMap.has_action(action):
		return ""
	var evs := Settings.events_of(action, pad)
	if evs.is_empty():
		return ""
	var pick: InputEvent = evs[0]
	for e in evs:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT,
				MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			pick = e
			break
	var label := Settings.code_text(Settings.code_of(pick))
	return str(SHORT_NAMES.get(label, label))


## Key names as they read best in a hint: ", / ." to turn, not "Comma / Period".
const SHORT_NAMES := {"Escape": "Esc", "Comma": ",", "Period": ".", "Slash": "/", "Equal": "=", "Minus": "-",
	"Kp Add": "Num +", "Kp Subtract": "Num -"}


## The controller to read: the last one used, else the first one with a standard layout.
func device() -> int:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return -1
	if pads.has(active_device):
		return active_device
	for d in pads:
		if Input.is_joy_known(d):
			return d
	return pads[0]


## Forgets the resting values so they are measured again (hands off the controller).
func recalibrate() -> void:
	_rest.clear()


func _rest_value(dev: int, axis: int) -> float:
	if not _rest.has(dev):
		_rest[dev] = {}
	var r: Dictionary = _rest[dev]
	if not r.has(axis):
		var v := Input.get_joy_axis(dev, axis)
		# Only treat a far-off value as the resting point; a centred stick reads near zero.
		r[axis] = v if absf(v) > 0.5 else 0.0
	return r[axis]


func axis(axis_id: int) -> float:
	var dev := device()
	if dev < 0:
		return 0.0
	return clampf(Input.get_joy_axis(dev, axis_id) - _rest_value(dev, axis_id), -1.0, 1.0)


func stick(right := false) -> Vector2:
	var v := Vector2(axis(JOY_AXIS_RIGHT_X if right else JOY_AXIS_LEFT_X), axis(JOY_AXIS_RIGHT_Y if right else JOY_AXIS_LEFT_Y))
	var len := v.length()
	if len < STICK_DEADZONE:
		return Vector2.ZERO
	return v / len * minf((len - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)


func trigger(right := true) -> float:
	var dev := device()
	if dev < 0:
		return 0.0
	var id := JOY_AXIS_TRIGGER_RIGHT if right else JOY_AXIS_TRIGGER_LEFT
	var rest := _rest_value(dev, id)
	var v := (Input.get_joy_axis(dev, id) - rest) / (2.0 if rest < -0.5 else 1.0)
	return 0.0 if v < TRIGGER_DEADZONE else clampf(v, 0.0, 1.0)


## Text for the controller check in the Esc menu.
func diagnostics() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "No controller found. Plug it in, then press any button."
	var lines := []
	for d in pads:
		var tag := "  <- in use" if d == device() else ""
		lines.append("#%d %s%s" % [d, Input.get_joy_name(d), tag])
		lines.append("    %s" % ("Standard layout" if Input.is_joy_known(d) else "Unknown layout (buttons may be swapped)"))
	var l := stick()
	var r := stick(true)
	lines.append("Left stick  %+.2f  %+.2f" % [l.x, l.y])
	lines.append("Right stick %+.2f  %+.2f" % [r.x, r.y])
	lines.append("Triggers    L %.2f   R %.2f" % [trigger(false), trigger(true)])
	var held := []
	var dev := device()
	for b in JOY_BUTTON_SDL_MAX:
		if Input.is_joy_button_pressed(dev, b):
			held.append(str(b))
	lines.append("Buttons held: %s" % (", ".join(held) if held else "none"))
	return "\n".join(lines)
