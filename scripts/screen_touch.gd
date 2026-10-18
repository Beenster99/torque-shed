class_name ScreenTouch
extends Node
## The shed's screens as touch screens (the bay screens, the crew board and the wall TVs). Look
## at one up close and a cursor ring shows where you're pointing, with the button under it lit
## (see Dashboard): click ({act}, or RT on a pad) and that's touched. Press {interact} at a
## built-in screen, or one out of the hands' reach, (or {act} off the buttons, on a pad) and
## the cursor is yours to move about on it, with the mouse, the keys or either stick, while you
## stand still: {act} or A touches, {back} leaves. What a button does is a Shed request, so it's
## done for the whole crew.

const REACH := 4.5             # m from the screen's middle (plus half its width)
const PAD_SPEED := 620.0       # page pixels a second, stick full over
const MOUSE_SPEED := 1.1       # page pixels per pixel of mouse movement

var walker: Walker
var focused := ""              # the screen whose cursor you hold, or ""
var _dash: Dashboard           # the screen with the cursor on it
var _px := Vector2.ZERO
var _froze := false


func _init(w: Walker) -> void:
	walker = w
	name = "ScreenTouch"


func _workshop() -> Node:
	return get_tree().get_first_node_in_group("workshop") if is_inside_tree() else null


## The screen the crosshair is on, near enough to touch, and where on its page: [key, dash, px] or [].
## That's the screen you're looking at, or with nothing nearer under the crosshair (a screen high
## on the wall behind a bike is out of the hands' reach) the nearest one the crosshair is on.
func screen_under() -> Array:
	var ws := _workshop()
	if ws == null or walker.camera == null:
		return []
	var key := walker._screen_key()
	if key == "" and not walker.target.is_empty():
		return []
	var from := walker.camera.global_position
	var dir := -walker.camera.global_transform.basis.z
	var all: Dictionary = ws.screens()
	var best := []
	var best_d := INF
	for k in ([key] if key != "" else all.keys()):
		var dash: Dashboard = all.get(k)
		if dash == null or not dash.is_inside_tree() or not dash.is_visible_in_tree():
			continue
		var d := dash.global_position.distance_to(from)
		if d > REACH + dash.width * 0.5 or d >= best_d:
			continue
		var px = dash.page_point(from, dir)
		if px != null:
			best = [k, dash, px]
			best_d = d
	return best


func _set_dash(dash: Dashboard) -> void:
	if _dash != dash and is_instance_valid(_dash):
		_dash.set_cursor(null)
	_dash = dash


func _process(delta: float) -> void:
	if not is_instance_valid(walker):
		return
	if focused != "":
		if not is_instance_valid(_dash) or not _dash.is_inside_tree() or not TvChannels.screen_exists(focused):
			leave()
			return
		var move := Controls.stick() + Controls.stick(true) + Vector2(Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_forward", "move_back"))
		if move != Vector2.ZERO:
			move_cursor(move.limit_length(1.0) * PAD_SPEED * delta)
		return
	if not walker.controls_enabled:
		_set_dash(null)
		return
	var hit := screen_under()
	if hit.is_empty():
		_set_dash(null)
		return
	_set_dash(hit[1])
	_px = hit[2]
	_dash.set_cursor(_px)


func move_cursor(by: Vector2) -> void:
	_px = (_px + by).clamp(Vector2.ZERO, Vector2(Dashboard.PX) - Vector2.ONE)
	if is_instance_valid(_dash):
		_dash.set_cursor(_px)


## Holds the cursor on the screen the crosshair is on (true when there is one).
func focus() -> bool:
	var hit := screen_under()
	if hit.is_empty():
		return false
	focused = hit[0]
	_set_dash(hit[1])
	_px = hit[2]
	_dash.set_cursor(_px)
	if walker.controls_enabled:
		walker.controls_enabled = false
		_froze = true
	Shed.feedback.emit(Controls.hint("Touch screen: {move} or the mouse moves the cursor, {act} touches, {back} leaves."), true)
	return true


func leave() -> void:
	focused = ""
	_set_dash(null)
	if _froze:
		walker.controls_enabled = true
		_froze = false


## Touches the screen with the cursor on it where the cursor is: the button there does its
## request (or says why it can't). True when the touch landed on a screen.
func touch() -> bool:
	if not is_instance_valid(_dash) or not _dash.cursor_on():
		return false
	var b := _dash.tap(_px)
	if b.is_empty():
		return true
	if str(b.get("off", "")) != "":
		Shed.feedback.emit(Controls.hint(str(b["off"])), false)
		Sfx.play_at("beep", _dash.global_position, -20.0)
		return true
	Shed.request(b["act"])
	Sfx.play_at("beep", _dash.global_position, -12.0)
	return true


func _input(event: InputEvent) -> void:
	if focused != "":
		if event is InputEventMouseMotion:
			move_cursor(event.relative * MOUSE_SPEED)
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
			leave()
		elif event.is_action_pressed("act") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			touch()
		elif not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton):
			return
		get_viewport().set_input_as_handled()
		return
	if not walker.controls_enabled or not is_instance_valid(_dash) or not _dash.cursor_on():
		return
	if event.is_action_pressed("act"):
		get_viewport().set_input_as_handled()
		var on_button := not _dash.hovered().is_empty()
		if not on_button and Controls.using_pad:
			focus()
		else:
			touch()
	elif event.is_action_pressed("interact") and (walker.target.is_empty() or str(walker.target.get("kind", "")) == "screen"):
		get_viewport().set_input_as_handled()
		focus()
