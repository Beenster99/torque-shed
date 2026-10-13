class_name MainMenu
extends Control
## Title screen and the Esc menu. The Esc menu holds everything that isn't the shed itself:
## ordering bikes, who's playing, riding settings, the controls list and a controller check.

signal ride_solo
signal host_game
signal join_game(ip: String)
signal resume
signal leave_session
signal order_bike

const CONTROLS_TEXT := """ON FOOT
W A S D / left stick: walk      Shift: run      Mouse / right stick: look      C / Ctrl / R3: crouch
1-6, Q / E, mouse wheel, LB / RB: pick a tool (hands, wrench, brush, grinder, spray can, pressure washer)
Hold left mouse / RT / A: work on what you're looking at, or put a held part down anywhere
Holding a can of fluid: left mouse pours it in, right mouse / LT drains into it
Spray can: R / right mouse / X picks the colour, T / middle mouse / B the finish
F / Y: get on a finished bike (hold to wheel it about), use the parts computer, switch the
  radio on or off, unpack a box, take hold of an engine stand or shelving unit (F again lets go)
Hands on a bolted-on stand: kick the side stand down or heave the bike onto the centre stand

RIDING
I / D-pad up: start or stop the engine      W / RT: throttle      S / LT: front brake
Space / B: rear brake      A D / left stick: lean      Shift / LB: weight back      Ctrl / RB: forward
E Q / A X: gear up / down      T: auto-shift      C / R3: chase or first-person camera
R / View: reset after a crash      F / Y: get off (when stopped)"""

var _name: LineEdit
var _ip: LineEdit
var _status: Label
var _start_box: VBoxContainer
var _pause_box: VBoxContainer
var _assist: HSlider
var _auto: CheckBox
var _quality: CheckBox
var _host_info: Label
var _crew: Label
var _pad: Label
var _tabs: TabContainer
var _cycle: CheckBox
var _day_length: OptionButton
var _time: HSlider
var _time_label: Label
var _time_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var row := HBoxContainer.new()
	row.position = Vector2(60, 60)
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UITheme.title("TORQUE SHED", 46))
	col.add_child(UITheme.label("Strip it. Clean it. Fix it. Ride it.", 16, Color(1, 1, 1, 0.6)))

	_start_box = VBoxContainer.new()
	_start_box.add_theme_constant_override("separation", 10)
	col.add_child(_start_box)
	_start_box.add_child(UITheme.label("Your name", 14, UITheme.ACCENT))
	_name = LineEdit.new()
	_name.text = Settings.player_name
	_name.max_length = 24
	_start_box.add_child(_name)
	_start_box.add_child(_button("Open the shed (solo)", func(): _save(); ride_solo.emit()))
	_start_box.add_child(_button("Host a co-op shed", func(): _save(); host_game.emit()))
	var join_row := HBoxContainer.new()
	_ip = LineEdit.new()
	_ip.text = Settings.last_ip
	_ip.placeholder_text = "Host IP address (port optional, e.g. 81.2.3.4:24680)"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip)
	join_row.add_child(_button("Join", func(): _save(); join_game.emit(_ip.text.strip_edges())))
	_start_box.add_child(join_row)

	_pause_box = VBoxContainer.new()
	_pause_box.add_theme_constant_override("separation", 10)
	_pause_box.visible = false
	col.add_child(_pause_box)
	_pause_box.add_child(_button("Back to the shed", func(): _save(); resume.emit()))
	_pause_box.add_child(_button("Order a project bike", func(): order_bike.emit()))
	_host_info = UITheme.label("", 15, Color(1, 1, 1, 0.75))
	_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_info.custom_minimum_size.x = 560.0
	_pause_box.add_child(_host_info)
	_crew = UITheme.label("", 15, Color(1, 1, 1, 0.85))
	_pause_box.add_child(_crew)
	_pause_box.add_child(_button("Leave and return to title", func(): _save(); leave_session.emit()))
	col.add_child(_button("Quit", func(): _save(); get_tree().quit()))
	_status = UITheme.label("", 15, Color(1, 0.75, 0.6))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 560.0
	col.add_child(_status)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(660, 460)
	_tabs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_tabs)
	var settings := VBoxContainer.new()
	settings.name = "Settings"
	settings.add_theme_constant_override("separation", 10)
	_tabs.add_child(settings)
	settings.add_child(UITheme.label("Rider assist (0 = full sim)", 15))
	_assist = HSlider.new()
	_assist.min_value = 0.0
	_assist.max_value = 1.0
	_assist.step = 0.05
	_assist.value = Settings.assist
	_assist.value_changed.connect(func(v): Settings.assist = v)
	settings.add_child(_assist)
	_auto = CheckBox.new()
	_auto.text = "Automatic gearbox"
	_auto.button_pressed = Settings.auto_shift
	_auto.toggled.connect(func(v): Settings.auto_shift = v)
	settings.add_child(_auto)
	settings.add_child(UITheme.label("Units", 15))
	var units := OptionButton.new()
	units.add_item("Metric (km/h, km, kg, L/100 km)")
	units.add_item("Imperial (mph, miles, lb, mpg)")
	units.selected = 1 if Settings.units == "imperial" else 0
	units.item_selected.connect(func(i): Settings.units = "imperial" if i == 1 else "metric")
	settings.add_child(units)
	_quality = CheckBox.new()
	_quality.text = "High quality lighting (restart to apply)"
	_quality.button_pressed = Settings.high_quality
	_quality.toggled.connect(func(v): Settings.high_quality = v)
	settings.add_child(_quality)
	_build_time_settings(settings)
	settings.add_child(UITheme.label("Sound effects volume", 15))
	settings.add_child(_volume_slider(Settings.sfx_volume, func(v): Settings.sfx_volume = v; Sfx.apply_volumes()))
	settings.add_child(UITheme.label("Radio volume", 15))
	settings.add_child(_volume_slider(Settings.radio_volume, func(v): Settings.radio_volume = v; Sfx.apply_volumes()))
	var controls := VBoxContainer.new()
	controls.name = "Controls"
	_tabs.add_child(controls)
	controls.add_child(UITheme.label(CONTROLS_TEXT, 15))
	var pad := VBoxContainer.new()
	pad.name = "Controller check"
	pad.add_theme_constant_override("separation", 10)
	_tabs.add_child(pad)
	pad.add_child(UITheme.label("Move the sticks and press buttons: the numbers should follow. If a stick shows a value while you're not touching it, let go and press Recalibrate.", 15, Color(1, 1, 1, 0.7)))
	_pad = UITheme.label("", 16)
	pad.add_child(_pad)
	pad.add_child(_button("Recalibrate (hands off the controller)", func(): Controls.recalibrate()))


func _process(_delta: float) -> void:
	if visible and _tabs.current_tab == 2:
		_pad.text = Controls.diagnostics()
	if visible and _tabs.current_tab == 0:
		_refresh_time_settings(false)
	if visible and _pause_box.visible:
		var names := []
		for peer in Shed.crew:
			names.append(Shed.crew[peer]["name"] + (" (you)" if peer == Shed.me() else ""))
		_crew.text = "In the shed: " + ", ".join(names)


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
		_host_info.text = "Hosting on port %d.\n%s" % [Net.PORT, Net.join_instructions()]
	elif Net.is_online():
		_host_info.text = "Connected to a co-op shed."
	else:
		_host_info.text = "Working solo."
	_auto.button_pressed = Settings.auto_shift
	_refresh_time_settings(true)
	show()


## Day/night cycle on or off, how long a day lasts and a clock slider. On a co-op client the
## host's clock rules, so these are shown greyed out.
func _build_time_settings(settings: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_cycle = CheckBox.new()
	_cycle.text = "Day/night cycle"
	_cycle.button_pressed = Settings.day_night_cycle
	_cycle.toggled.connect(func(v): Settings.day_night_cycle = v)
	row.add_child(_cycle)
	row.add_child(UITheme.label("Day length", 15))
	_day_length = OptionButton.new()
	for m in Daylight.DAY_LENGTHS:
		_day_length.add_item("%d minutes" % m if m < 60 else ("1 hour" if m == 60 else "%d hours" % (m / 60)))
	if not Daylight.DAY_LENGTHS.has(Settings.day_length):
		Settings.day_length = 120
	_day_length.selected = maxi(Daylight.DAY_LENGTHS.find(Settings.day_length), 0)
	_day_length.item_selected.connect(func(i): Settings.day_length = Daylight.DAY_LENGTHS[i])
	row.add_child(_day_length)
	settings.add_child(row)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 16)
	_time_label = UITheme.label("Time of day", 15)
	_time_label.custom_minimum_size.x = 170.0
	time_row.add_child(_time_label)
	_time = HSlider.new()
	_time.min_value = 0.0
	_time.max_value = 24.0
	_time.step = 0.25
	_time.value = Settings.time_of_day
	_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time.value_changed.connect(func(v):
		if Daylight.current:
			Daylight.current.set_time(v)
		else:
			Settings.time_of_day = v)
	time_row.add_child(_time)
	_time_note = UITheme.label("set by the host", 14, Color(1, 1, 1, 0.55))
	time_row.add_child(_time_note)
	settings.add_child(time_row)
	_refresh_time_settings(true)


func _refresh_time_settings(move_slider: bool) -> void:
	var by_host := Daylight.set_by_host()
	_cycle.disabled = by_host
	_day_length.disabled = by_host
	_time.editable = not by_host
	_time_note.visible = by_host
	var h := Daylight.time_of_day() if Daylight.current else Settings.time_of_day
	_time_label.text = "Time of day  %s" % Daylight.clock_text(h)
	if move_slider or by_host:
		_time.set_value_no_signal(h)


func set_status(text: String) -> void:
	_status.text = text


func player_name() -> String:
	var n := _name.text.strip_edges()
	return n if n != "" else "Rider"


func _save() -> void:
	Settings.player_name = player_name()
	Settings.last_ip = _ip.text.strip_edges()
	Settings.save_settings()


func _volume_slider(value: float, cb: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.value_changed.connect(cb)
	return slider


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
