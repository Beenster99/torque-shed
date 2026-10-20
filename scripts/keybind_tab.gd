class_name KeybindTab
extends VBoxContainer
## The Esc menu's Key bindings tab: every action with its key or mouse button and its pad
## button. Click one and press the new key, mouse button or pad button (Esc cancels); Clear
## takes it off, and Reset to defaults puts everything back. Keys that would do two things at
## once (in the same place: on foot, riding, with a spray can out or at the whiteboard) are
## flagged in red. Saved in the settings file with the rest (see Settings.rebind).

## Waiting for a key: {action, pad}, or empty.
var listening := {}
var _warn: Label
var _rows := {}      # action -> {name: Label, kbm: Button, pad: Button}


func _ready() -> void:
	name = "Key bindings"
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var help := UITheme.label("Click a binding, then press the key, mouse button or pad button to use. Esc cancels. "
		+ "Sticks, triggers and LB + RB together (the engine) can't be changed.", 14, Color(1, 1, 1, 0.65))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(help)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		listening = {}
		Settings.reset_bindings()
		refresh())
	top.add_child(reset)
	add_child(top)
	_warn = UITheme.label("", 14, Color(1, 0.55, 0.45))
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_warn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	for head in ["Action", "Keyboard / mouse", "", "Gamepad", ""]:
		grid.add_child(UITheme.label(head, 14, UITheme.ACCENT))
	for a in Settings.ACTIONS:
		var action: String = a[0]
		var nm := UITheme.label(a[1], 15)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(nm)
		var kbm := _bind_button(action, false)
		grid.add_child(kbm)
		grid.add_child(_clear_button(action, false))
		var pad := _bind_button(action, true)
		grid.add_child(pad)
		grid.add_child(_clear_button(action, true))
		_rows[action] = {"name": nm, "kbm": kbm, "pad": pad}
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			listening = {}
		refresh())
	refresh()


func _bind_button(action: String, pad: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170 if not pad else 120, 30)
	b.clip_text = true
	b.pressed.connect(func(): listen(action, pad))
	return b


func _clear_button(action: String, pad: bool) -> Button:
	var b := Button.new()
	b.text = "Clear"
	b.tooltip_text = "Take this binding off"
	b.pressed.connect(func():
		listening = {}
		Settings.clear_binding(action, pad)
		refresh())
	return b


## Waits for the next key, mouse button or pad button to put on `action`.
func listen(action: String, pad: bool) -> void:
	listening = {"action": action, "pad": pad}
	refresh()


func _input(event: InputEvent) -> void:
	if listening.is_empty() or not is_visible_in_tree():
		return
	if not event.is_pressed() or event.is_echo():
		return
	var pad: bool = listening["pad"]
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		listening = {}
		refresh()
	elif (pad and event is InputEventJoypadButton) or (not pad and (event is InputEventKey or event is InputEventMouseButton)):
		var action: String = listening["action"]
		listening = {}
		Settings.rebind(action, event)
		refresh()
	else:
		return   # the other kind of button: keep waiting, and let it through to work the menu
	get_viewport().set_input_as_handled()


## Brings the labels and clash warnings up to date.
func refresh() -> void:
	var found := Settings.clashes()
	var clashing := {}
	for c in found:
		clashing[c["a"]] = true
		clashing[c["b"]] = true
	for action in _rows:
		var row: Dictionary = _rows[action]
		for pad in [false, true]:
			var b: Button = row["pad" if pad else "kbm"]
			var waiting: bool = listening.get("action", "") == action and listening.get("pad", false) == pad
			var text := Settings.binding_text(action, pad)
			if text == "" and pad:
				text = Controls.fixed_pad(action)   # LB + RB for the engine, the triggers, the sticks
			b.text = ("Press a pad button..." if pad else "Press a key...") if waiting else (text if text != "" else "-")
		(row["name"] as Label).add_theme_color_override("font_color", Color(1, 0.5, 0.4) if clashing.has(action) else Color(0.85, 0.87, 0.9))
		(row["name"] as Label).tooltip_text = Settings.clash_text(action, found) if clashing.has(action) else ""
	var lines := []
	for c in found.slice(0, 6):
		lines.append("%s does both %s and %s (%s)" % [Settings.code_text(c["code"]), Settings.action_name(c["a"]),
			Settings.action_name(c["b"]), Settings.CONTEXT_NAMES[c["context"]]])
	if found.size() > 6:
		lines.append("and %d more" % (found.size() - 6))
	_warn.text = ("Clash: " + "; ".join(lines) + ".") if not lines.is_empty() else ""
	_warn.visible = not lines.is_empty()


## The clash warning shown at the top, "" when there's none (for the tests).
func warning() -> String:
	return _warn.text
