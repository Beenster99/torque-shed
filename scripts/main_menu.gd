class_name MainMenu
extends Control
## Title screen and pause menu: name, ride solo, host or join a session, riding settings.

signal ride_solo
signal host_game
signal join_game(ip: String)
signal resume
signal leave_session

var _name: LineEdit
var _ip: LineEdit
var _status: Label
var _start_box: VBoxContainer
var _pause_box: VBoxContainer
var _assist: HSlider
var _auto: CheckBox
var _quality: CheckBox
var _host_info: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.25)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(60, 60)
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UITheme.title("TORQUE SHED", 46))
	col.add_child(UITheme.label("Build it. Ride it. Break it. Fix it.", 16, Color(1, 1, 1, 0.6)))

	_start_box = VBoxContainer.new()
	_start_box.add_theme_constant_override("separation", 10)
	col.add_child(_start_box)
	_start_box.add_child(UITheme.label("Your name", 14, UITheme.ACCENT))
	_name = LineEdit.new()
	_name.text = Settings.player_name
	_name.max_length = 24
	_start_box.add_child(_name)
	_start_box.add_child(_button("Ride solo", func(): _save(); ride_solo.emit()))
	_start_box.add_child(_button("Host a game", func(): _save(); host_game.emit()))
	var join_row := HBoxContainer.new()
	_ip = LineEdit.new()
	_ip.text = Settings.last_ip
	_ip.placeholder_text = "Host IP address"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip)
	join_row.add_child(_button("Join", func(): _save(); join_game.emit(_ip.text.strip_edges())))
	_start_box.add_child(join_row)

	_pause_box = VBoxContainer.new()
	_pause_box.add_theme_constant_override("separation", 10)
	_pause_box.visible = false
	col.add_child(_pause_box)
	_host_info = UITheme.label("", 15, Color(1, 1, 1, 0.75))
	_pause_box.add_child(_host_info)
	_pause_box.add_child(_button("Resume", func(): _save(); resume.emit()))
	_pause_box.add_child(_button("Leave and return to title", func(): _save(); leave_session.emit()))

	col.add_child(UITheme.label("RIDING", 14, UITheme.ACCENT))
	col.add_child(UITheme.label("Rider assist (0 = full sim)", 15))
	_assist = HSlider.new()
	_assist.min_value = 0.0
	_assist.max_value = 1.0
	_assist.step = 0.05
	_assist.value = Settings.assist
	_assist.value_changed.connect(func(v): Settings.assist = v)
	col.add_child(_assist)
	_auto = CheckBox.new()
	_auto.text = "Automatic gearbox"
	_auto.button_pressed = Settings.auto_shift
	_auto.toggled.connect(func(v): Settings.auto_shift = v)
	col.add_child(_auto)
	_quality = CheckBox.new()
	_quality.text = "High quality lighting (restart to apply)"
	_quality.button_pressed = Settings.high_quality
	_quality.toggled.connect(func(v): Settings.high_quality = v)
	col.add_child(_quality)
	col.add_child(_button("Quit", func(): _save(); get_tree().quit()))
	_status = UITheme.label("", 15, Color(1, 0.75, 0.6))
	col.add_child(_status)


func show_title(status := "") -> void:
	_start_box.visible = true
	_pause_box.visible = false
	_status.text = status
	show()


func show_pause() -> void:
	_start_box.visible = false
	_pause_box.visible = true
	_status.text = ""
	if Net.is_host():
		var addrs := Net.local_addresses()
		_host_info.text = "Hosting on port %d. Friends on your network join with: %s" % [Net.PORT, ", ".join(addrs)]
	elif Net.is_online():
		_host_info.text = "Connected to a hosted game."
	else:
		_host_info.text = "Riding solo."
	_auto.button_pressed = Settings.auto_shift
	show()


func set_status(text: String) -> void:
	_status.text = text


func player_name() -> String:
	var n := _name.text.strip_edges()
	return n if n != "" else "Rider"


func _save() -> void:
	Settings.player_name = player_name()
	Settings.last_ip = _ip.text.strip_edges()
	Settings.save_settings()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
