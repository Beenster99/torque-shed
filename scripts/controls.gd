extends Node
## Gamepad sticks and triggers. Reads whichever controller was used last, and measures each
## axis at rest so a controller (or a stray device such as a wheel or RGB hub) that reports an
## axis stuck at one end can't hold the bike leaned over or the throttle open.

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.06

var active_device := -1
var _rest := {}          # device -> {axis: resting value}


func _ready() -> void:
	Input.joy_connection_changed.connect(func(device: int, connected: bool):
		if connected:
			_rest.erase(device)
		elif device == active_device:
			active_device = -1)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		active_device = event.device
	elif event is InputEventJoypadMotion:
		var rest := _rest_value(event.device, event.axis)
		if absf(event.axis_value - rest) > 0.5:
			active_device = event.device


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
