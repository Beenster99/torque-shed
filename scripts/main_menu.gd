class_name MainMenu
extends Control
## Title screen and the Esc menu. The Esc menu is short: Continue, Settings, saving, Leave and
## return to title, and Exit game. Settings opens its own tabs (Graphics, Sound, Gameplay,
## Controller and Debug). The badge in the top left corner (the garage's name) opens the
## garage's panel: Money, Staff, Contracts, the Recovery truck, Blueprints and the Workshop
## (adventure rides, ordering a project bike, geometry mode). The profile picture in the top
## right opens yours: your profile, your Character (level, tools, skills, goals) and the Shop
## for rider gear.

signal ride_solo
signal host_game
signal join_game(ip: String)
signal resume
## "Back to the garage": out in the world, home with the bike you're on (see Main.go_home).
signal go_home
signal leave_session
signal order_bike
signal geometry_mode
signal save_requested
## A save game picked on the Load screen, to play solo or host (see SaveBrowser).
signal load_game(id: String, as_host: bool)
signal save_as(called: String)
signal save_renamed(id: String, called: String)
signal quitting

const CONTROLS_TEXT := """ON FOOT
W A S D / left stick: walk      Shift: run      Mouse / right stick: look      C / Ctrl / R3: crouch
V / View: first or third person (spraying, washing, the sandblaster and the tyre changer are always first person)
1-6, Q / E, mouse wheel, LB / RB: pick a tool (hands, wrench, brush, grinder, spray can, pressure washer)
Hold left mouse / RT / A: work on what you're looking at, or put a held part down anywhere
Holding a can of fluid: left mouse pours it in, right mouse / LT drains into it
Spray can or gun: R / right mouse / X picks the colour, T / mouse back button / B the finish
G / middle mouse / D-pad right: ping   (Key bindings tab: change any of these)
F / Y: get on a finished bike (hold to wheel it about), use the parts computer, switch the
  radio on or off, unpack a box, take hold of an engine stand or shelving unit (F again lets go)
Carrying equipment: mouse wheel / LB RB pushes it further away or closer, R / X snaps to walls on or off
Hands on a bolted-on stand: kick the side stand down or heave the bike onto the centre stand
F2 at a bike: geometry mode (click a part, drag the handles; W move, E rotate, R scale, Ctrl snap, Z undo)

RIDING
I / D-pad up: start or stop the engine      W / RT: throttle      S / LT: front brake
Space / B: rear brake      A D / left stick: lean      Shift / LB: weight back      Ctrl / RB: forward
E Q / A X: gear up / down      T: auto-shift      C / R3: chase or first-person camera
Neutral (N) sits between 1st and 2nd: at a standstill E from 1st or Q from 2nd finds it; Q from N is 1st
Mouse / right stick: swing the camera round      V: ride-by camera (watch yourself go past)
L / D-pad up: headlight (off, low, high, high with fog lights)      S + W / LT + RT: burnout (lean to spin round)
, . / D-pad left, right: indicators (again to cancel; they cancel themselves after the turn)      H / L3: horn
R / View: reset after a crash      F / Y: get off (when stopped)      F3: telemetry overlay
' (apostrophe): flick your helmet visor or goggles up or down (on foot too; the crew see it)"""

var _name: LineEdit
var _home: Button
## Starts an adventure ride for the crew, or ends the one on (the host; see Adventure.menu_action).
var _adventure: Button
## Carries on the adventure a night's sleep put away (the host; see Adventure.continue_text).
var _continue_adventure: Button
## Out on an adventure: the paper map of the route (once you've stopped; see AdventureMap).
var _paper_map: Button
## Says whether "Back to the garage" can be used now ("" yes, "home" already there, else why not); set by Main.
var home_check := Callable()
var _ip: LineEdit
var _status: Label
var _start_box: VBoxContainer
var _pause_box: VBoxContainer
var _assist: HSlider
var _auto: CheckBox
var _snap: CheckBox
var _free_rotate: CheckBox
var _third_person: CheckBox
var _host_info: Label
var _crew: Label
var _pad: Label
## The Settings panel's tabs: Graphics, Sound, Gameplay, Controller and Debug.
var _tabs: TabContainer
## The garage's panel (the top left badge) and yours (the profile picture, top right).
var _garage_tabs: TabContainer
var _profile_tabs: TabContainer
var _garage_badge: MenuBadge
var _profile_badge: MenuBadge
var _profile_info: Label
var _profile_pic: MenuBadge
var _gameplay: Control
var _controller: TabContainer
## The garage's name on its badge (the save game's name; on a co-op client, the host's shed).
var _garage_name := ""
var _cycle: CheckBox
var _day_length: OptionButton
var _time: HSlider
var _time_label: Label
var _time_note: Label
var _weather: OptionButton
var _weather_now: Label
var debug: DebugTab
var money: MoneyTab
var staff: StaffTab
var shop: ShopTab
## Gameplay: riders look into the corner (Settings.look_into_corner).
var look_corner: CheckBox
## Profile: your riding style (see RiderStyle), and what it's like.
var rider_style: OptionButton
var _style_desc: Label
## Set when the player chose New game: the next solo or hosted start begins a fresh shed (and
## character), saved as `new_name`.
var new_shed := false
var new_name := ""
var _solo: Button
var _host: Button
var _save_line: Label
var _new_game: Button
var _load_button: Button
var _save_status: Label
var _save_button: Button
var _save_as_button: Button
var _saves_button: Button
## The Load screen, in place of the tabs while it's open.
var saves: SaveBrowser
var _row: HBoxContainer
var _resume: Button
var _settings_button: Button
var _title_settings: Button
var keybinds: KeybindTab
var graphics: GraphicsTab
var blueprints: BlueprintTab
## Bikes left out on the road, each with a button to have it brought back to the yard.
var _retrieve_box: VBoxContainer
var _retrieve_shown := []   # the abandoned bike ids the buttons were made for


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var row := HBoxContainer.new()
	_row = row
	row.position = Vector2(60, 96)
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
	_build_save_choice()
	_solo = _button("Open the shed (solo)", func(): _save(); ride_solo.emit())
	_start_box.add_child(_solo)
	_host = _button("Host a co-op shed", func(): _save(); host_game.emit())
	_start_box.add_child(_host)
	var game_row := HBoxContainer.new()
	game_row.add_theme_constant_override("separation", 10)
	game_row.add_child(_new_game)
	game_row.add_child(_load_button)
	_start_box.add_child(game_row)
	var join_row := HBoxContainer.new()
	_ip = LineEdit.new()
	_ip.text = Settings.last_ip
	_ip.placeholder_text = "Host IP address (port optional, e.g. 81.2.3.4:24680)"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip)
	join_row.add_child(_button("Join", func(): _save(); join_game.emit(_ip.text.strip_edges())))
	_start_box.add_child(join_row)

	_title_settings = _button("Settings", func(): toggle_panel(_tabs))
	_start_box.add_child(_title_settings)

	_pause_box = VBoxContainer.new()
	_pause_box.add_theme_constant_override("separation", 10)
	_pause_box.visible = false
	col.add_child(_pause_box)
	_resume = _button("Continue", func(): _save(); resume.emit())
	_pause_box.add_child(_resume)
	_settings_button = _button("Settings", func(): toggle_panel(_tabs))
	_pause_box.add_child(_settings_button)
	# Only out in the world, stranded: you and the bike you're on go home.
	_home = _button("Respawn at the garage (stranded? you and the bike you're on go home)", func(): go_home.emit())
	_pause_box.add_child(_home)
	_host_info = UITheme.label("", 15, Color(1, 1, 1, 0.75))
	_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_info.custom_minimum_size.x = 400.0
	_pause_box.add_child(_host_info)
	_crew = UITheme.label("", 15, Color(1, 1, 1, 0.85))
	_crew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crew.custom_minimum_size.x = 400.0
	_pause_box.add_child(_crew)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 10)
	_save_button = _button("Save now", func(): save_requested.emit())
	save_row.add_child(_save_button)
	_save_as_button = _button("Save as...", func():
		saves.ask_name("Save as a new game", "Save", SaveGame.unique_name(saves._current_name() + " copy"), "",
			func(called, _alt): save_as.emit(called)))
	save_row.add_child(_save_as_button)
	_saves_button = _button("Save games...", func(): show_saves(true))
	save_row.add_child(_saves_button)
	_pause_box.add_child(save_row)
	_save_status = UITheme.label("", 15, Color(1, 1, 1, 0.7))
	_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_status.custom_minimum_size.x = 400.0
	_pause_box.add_child(_save_status)
	_pause_box.add_child(_button("Leave and return to title", func(): _save(); leave_session.emit()))
	col.add_child(_button("Exit game", func(): _save(); quitting.emit(); get_tree().quit()))
	_status = UITheme.label("", 15, Color(1, 0.75, 0.6))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 400.0
	col.add_child(_status)

	_build_settings()
	_build_garage()
	_build_profile()
	_build_badges()
	# The Load screen: save games to load, save as, rename and delete (see SaveBrowser).
	saves = SaveBrowser.new()
	saves.visible = false
	row.add_child(saves)
	saves.load_game.connect(func(id, as_host):
		_save()
		load_game.emit(id, as_host))
	saves.save_now.connect(func(): save_requested.emit())
	saves.save_as.connect(func(called): save_as.emit(called))
	saves.save_renamed.connect(func(id, called): save_renamed.emit(id, called))
	saves.changed.connect(_refresh_save_choice)
	saves.closed.connect(func(): _show_panel(null))
	_show_panel(_tabs)


## The Settings panel's tabs: Graphics, Sound, Gameplay, Controller (the controls list, key
## bindings and a controller check) and Debug.
func _build_settings() -> void:
	_tabs = _panel_tabs("Settings")
	# Graphics: presets, display, upscaling, anti-aliasing, quality and the driver (see GraphicsTab).
	graphics = GraphicsTab.new()
	_tabs.add_child(graphics)
	var sound := _scroll_tab("Sound")
	_build_sound_settings(sound)
	# Gameplay: riding, the camera, units, placing things, and the time of day and weather.
	var settings := _scroll_tab("Gameplay")
	_gameplay = settings.get_parent() as Control
	_build_riding_settings(settings)
	_auto = CheckBox.new()
	_auto.text = "Automatic gearbox"
	_auto.button_pressed = Settings.auto_shift
	_auto.toggled.connect(func(v): Settings.auto_shift = v)
	settings.add_child(_auto)
	var recentre := CheckBox.new()
	recentre.text = "Chase camera swings back behind the bike after you let go of the mouse or right stick"
	recentre.button_pressed = Settings.camera_recentre
	recentre.toggled.connect(func(v): Settings.camera_recentre = v)
	settings.add_child(recentre)
	look_corner = CheckBox.new()
	look_corner.name = "LookIntoCorner"
	look_corner.text = "Riders look into the corner: the head turns towards the inside and the exit of a bend, and your view does in first person"
	look_corner.button_pressed = Settings.look_into_corner
	look_corner.toggled.connect(func(v): Settings.look_into_corner = v)
	settings.add_child(look_corner)
	_third_person = CheckBox.new()
	_third_person.text = "Third person on foot: the camera behind your shoulder, your whole figure in view (V / View toggles it)"
	_third_person.button_pressed = Settings.walk_third_person
	_third_person.toggled.connect(func(v): Settings.walk_third_person = v)
	settings.add_child(_third_person)
	settings.add_child(UITheme.label("Units", 15))
	var units := OptionButton.new()
	units.add_item("Metric (km/h, km, kg, L/100 km)")
	units.add_item("Imperial (mph, miles, lb, mpg)")
	units.selected = 1 if Settings.units == "imperial" else 0
	units.item_selected.connect(func(i): Settings.units = "imperial" if i == 1 else "metric")
	settings.add_child(units)
	_snap = CheckBox.new()
	_snap.text = "Snap equipment to walls and corners when placing it (R toggles it while carrying)"
	_snap.button_pressed = Settings.snap_placement
	_snap.toggled.connect(func(v): Settings.snap_placement = v)
	settings.add_child(_snap)
	_free_rotate = CheckBox.new()
	Controls.bind_text(_free_rotate, "Free rotate: the rotate keys turn what you hold to any angle, not a quarter a press ({rotate_free} toggles it)")
	_free_rotate.button_pressed = Settings.free_rotate
	_free_rotate.toggled.connect(func(v): Settings.free_rotate = v)
	settings.add_child(_free_rotate)
	_build_time_settings(settings)
	# Controller: the controls list, key bindings and a check that the pad's sticks read true.
	_controller = TabContainer.new()
	_controller.name = "Controller"
	_tabs.add_child(_controller)
	var controls_scroll := ScrollContainer.new()
	controls_scroll.name = "Controls"
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controller.add_child(controls_scroll)
	var controls := UITheme.label(CONTROLS_TEXT, 15)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_scroll.add_child(controls)
	keybinds = KeybindTab.new()
	_controller.add_child(keybinds)
	var pad := VBoxContainer.new()
	pad.name = "Controller check"
	pad.add_theme_constant_override("separation", 10)
	_controller.add_child(pad)
	pad.add_child(UITheme.label("Move the sticks and press buttons: the numbers should follow. If a stick shows a value while you're not touching it, let go and press Recalibrate.", 15, Color(1, 1, 1, 0.7)))
	_pad = UITheme.label("", 16)
	pad.add_child(_pad)
	pad.add_child(_button("Recalibrate (hands off the controller)", func(): Controls.recalibrate()))
	# Testing helpers: XP, money, contracts, punctures, fixing the bike, the profiler.
	debug = DebugTab.new()
	_tabs.add_child(debug)


## The garage's panel (its badge, top left): the money, the staff, contracts under way, the
## recovery truck (with the bikes left out on the road), blueprints, and the Workshop.
func _build_garage() -> void:
	_garage_tabs = _panel_tabs("Garage")
	# The cash, the business's account, sending money, loans and the ledger (see Money).
	money = MoneyTab.new()
	_garage_tabs.add_child(money)
	# The garage's staff and the hiring board (see Staff).
	staff = StaffTab.new()
	_garage_tabs.add_child(staff)
	_garage_tabs.add_child(ContractsTab.new())
	# The recovery truck: bikes left out on the road to bring back, and its jobs (see Recovery).
	var truck := VBoxContainer.new()
	truck.name = "Recovery truck"
	truck.add_theme_constant_override("separation", 8)
	_garage_tabs.add_child(truck)
	_retrieve_box = VBoxContainer.new()
	_retrieve_box.add_theme_constant_override("separation", 6)
	truck.add_child(_retrieve_box)
	var jobs := RecoveryTab.new()
	jobs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	truck.add_child(jobs)
	blueprints = BlueprintTab.new()
	_garage_tabs.add_child(blueprints)
	# The Workshop: adventure rides, a project bike to order and geometry mode.
	var shop_floor := _scroll_tab("Workshop", _garage_tabs)
	shop_floor.add_child(UITheme.label("Adventure rides", 15, UITheme.ACCENT))
	_adventure = _button("Adventure ride", func():
		Adventure.menu_action()
		resume.emit())
	shop_floor.add_child(_adventure)
	_continue_adventure = _button("Continue adventure", func():
		Shed.request({"a": "adventure_resume"})
		resume.emit())
	shop_floor.add_child(_continue_adventure)
	_paper_map = _button("Paper map of the route", func():
		resume.emit()
		if AdventureTrip.current:
			AdventureTrip.current.open_map())
	shop_floor.add_child(_paper_map)
	shop_floor.add_child(UITheme.label("Bikes", 15, UITheme.ACCENT))
	shop_floor.add_child(_button("Order a project bike", func(): order_bike.emit()))
	shop_floor.add_child(_button("Build from blueprint", show_blueprints))
	shop_floor.add_child(_button("Geometry mode: fit the parts of the bike you're at ({geometry_mode})", func(): geometry_mode.emit()))


## Your panel (the profile picture, top right): who you are, your Character, and the Shop.
func _build_profile() -> void:
	_profile_tabs = _panel_tabs("Profile")
	var me := _scroll_tab("Profile", _profile_tabs)
	_profile_pic = MenuBadge.new("profile")
	_profile_pic.disabled = true
	_profile_pic.custom_minimum_size = Vector2(320, 60)
	me.add_child(_profile_pic)
	_profile_info = UITheme.label("", 15, Color(1, 1, 1, 0.85))
	_profile_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	me.add_child(_profile_info)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.add_child(_button("Character: level, tools and skills", func(): _profile_tabs.current_tab = 1))
	buttons.add_child(_button("Shop: improve your rider's gear", func(): _profile_tabs.current_tab = 2))
	me.add_child(buttons)
	_build_style_choice(me)
	me.add_child(_profile_note())
	# Your level, tool upgrades, skills tree and goals (see Progress).
	_profile_tabs.add_child(CharacterTab.new())
	# Rider gear and shed trinkets bought with your own money (see ShopTab).
	shop = ShopTab.new()
	_profile_tabs.add_child(shop)


## The Rider style choice on the Profile tab: how you sit on the bike and move on it through a
## corner (see RiderStyle). It's kept with your gear, so it goes with you and everyone sees it.
func _build_style_choice(me: VBoxContainer) -> void:
	me.add_child(UITheme.label("Rider style", 15, UITheme.ACCENT))
	rider_style = OptionButton.new()
	rider_style.name = "RiderStyle"
	for id in RiderStyle.STYLES:
		rider_style.add_item(RiderStyle.style_name(id))
	rider_style.item_selected.connect(func(i: int): pick_style(RiderStyle.STYLES[i]))
	me.add_child(rider_style)
	_style_desc = UITheme.label("", 14, Color(1, 1, 1, 0.7))
	_style_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	me.add_child(_style_desc)
	_show_style(RiderStyle.DEFAULT)   # your own once the profile's up (see _refresh_badges)


## Rides in riding style `id` from now on: saved with your gear, your own bike's rider sits that
## way at once, and the crew's machines redraw you as your summary reaches them.
func pick_style(id: String) -> void:
	RiderGear.set_style(id)
	for b in get_tree().get_nodes_in_group("ridden_bike"):
		if b is Bike and (b as Bike).model:
			(b as Bike).rider_gear = RiderGear.worn_of(Shed.me())
			(b as Bike).model.redress((b as Bike).rider_gear)
	_show_style(id)


func _show_style(id: String) -> void:
	if rider_style == null:
		return
	var i := RiderStyle.STYLES.find(RiderStyle.clean(id))
	if rider_style.selected != i:
		rider_style.select(i)
	_style_desc.text = str(RiderStyle.INFO[RiderStyle.clean(id)]["desc"]) + " Only looks: the bike rides the same."


func _profile_note() -> Label:
	var l := UITheme.label("Your name is set on the title screen. Your gear shows on your figure on foot and on the bike; " +
		"the Third person setting (Settings, Gameplay) puts your whole figure in view.", 14, Color(1, 1, 1, 0.6))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The corner badges: the garage's (top left) and your profile picture (top right).
func _build_badges() -> void:
	_garage_badge = MenuBadge.new("garage")
	_garage_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_garage_badge.position = Vector2(16, 16)
	_garage_badge.tooltip_text = "The garage: money, staff, contracts, the recovery truck and the workshop"
	_garage_badge.pressed.connect(func(): toggle_panel(_garage_tabs))
	add_child(_garage_badge)
	_profile_badge = MenuBadge.new("profile")
	_profile_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_profile_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_profile_badge.offset_left = -16.0 - _profile_badge.custom_minimum_size.x
	_profile_badge.offset_right = -16.0
	_profile_badge.offset_top = 16.0
	_profile_badge.tooltip_text = "Your profile: your character and the shop for your rider's gear"
	_profile_badge.pressed.connect(func(): toggle_panel(_profile_tabs))
	add_child(_profile_badge)
	_garage_badge.visible = false
	_profile_badge.visible = false


## A panel of tabs beside the menu, shown one at a time (see _show_panel).
func _panel_tabs(panel_name: String) -> TabContainer:
	var tabs := TabContainer.new()
	tabs.name = panel_name
	tabs.custom_minimum_size = Vector2(760, 600)
	tabs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tabs.visible = false
	_row.add_child(tabs)
	return tabs


## A tab that scrolls (taller than the screen), with its column of rows returned.
func _scroll_tab(tab_name: String, tabs: TabContainer = null) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	(tabs if tabs else _tabs).add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	return box


## The panel open beside the menu (Settings, the garage's or yours), or null.
func open_panel() -> TabContainer:
	for p in [_tabs, _garage_tabs, _profile_tabs]:
		if p.visible:
			return p
	return null


## Shows `panel` beside the menu (null for none), closing the others and the Load screen.
func _show_panel(panel: TabContainer) -> void:
	for p in [_tabs, _garage_tabs, _profile_tabs]:
		p.visible = p == panel
	if panel and saves:
		saves.visible = false


## Opens `panel`, or closes it if it's the one open.
func toggle_panel(panel: TabContainer) -> void:
	_show_panel(null if panel.visible else panel)


## Opens whichever panel holds `tab` with that tab showing (a tab inside the Controller tab too).
func open_tab(tab: Control) -> void:
	var c := tab
	while c and c.get_parent() is TabContainer:
		var tabs := c.get_parent() as TabContainer
		tabs.current_tab = tabs.get_tab_idx_from_control(c)
		if tabs in [_tabs, _garage_tabs, _profile_tabs]:
			_show_panel(tabs)
			return
		c = tabs


## The Sound tab's rows: the effects (tools, the washer, knocks,
## dings, horns), the engines and the radio each have their own bus and slider (see Sfx).
func _build_sound_settings(settings: VBoxContainer) -> void:
	settings.add_child(UITheme.label("Sound effects volume", 15))
	settings.add_child(_volume_slider("SfxVolume", Settings.sfx_volume, func(v): Settings.sfx_volume = v; Sfx.apply_volumes()))
	settings.add_child(UITheme.label("Engines volume", 15))
	settings.add_child(_volume_slider("EngineVolume", Settings.engine_volume, func(v): Settings.engine_volume = v; Sfx.apply_volumes()))
	settings.add_child(UITheme.label("Radio volume", 15))
	settings.add_child(_volume_slider("RadioVolume", Settings.radio_volume, func(v): Settings.radio_volume = v; Sfx.apply_volumes()))


## The riding rows at the top of the Gameplay tab: the Riding realism slider (what each end means shows
## under it) and the telemetry overlay.
func _build_riding_settings(settings: VBoxContainer) -> void:
	settings.add_child(UITheme.label("Riding realism (0 = full sim, 1 = easy)", 15))
	_assist = HSlider.new()
	_assist.min_value = 0.0
	_assist.max_value = 1.0
	_assist.step = 0.05
	var value := UITheme.label("", 14, UITheme.ACCENT)
	var show := func(v: float) -> void:
		value.text = "%.2f: %s" % [v, realism_text(v)]
	_assist.value_changed.connect(func(v):
		Settings.assist = v
		show.call(v))
	_assist.value = Settings.assist
	show.call(Settings.assist)
	settings.add_child(_assist)
	settings.add_child(value)
	var bars := CheckBox.new()
	bars.text = "Direct bars: steering pushes on the handlebars (push right to lean right)"
	bars.button_pressed = Settings.direct_bars
	bars.toggled.connect(func(v): Settings.direct_bars = v)
	settings.add_child(bars)
	var tele := CheckBox.new()
	Controls.bind_text(tele, "Telemetry overlay while riding ({telemetry})")
	tele.button_pressed = Settings.telemetry_overlay
	tele.toggled.connect(func(v): Settings.telemetry_overlay = v)
	settings.add_child(tele)
	var nav := CheckBox.new()
	Controls.bind_text(nav, "Sat nav map on the HUD, on a bike with one fitted ({satnav_hud})")
	nav.button_pressed = Settings.satnav_hud
	nav.toggled.connect(func(v): Settings.satnav_hud = v)
	settings.add_child(nav)


## What a Riding realism setting does, in a few words.
static func realism_text(v: float) -> String:
	if v < 0.15:
		return "full sim: nothing saves the front, slides can high-side"
	if v < 0.45:
		return "mostly sim: the rider barely saves the front"
	if v < 0.8:
		return "the rider protects the front and smooths the throttle"
	return "easy: the rider also balances the bike for you"


func _process(_delta: float) -> void:
	var pt := Perf.t0()
	_process_body(_delta)
	Perf.add("menus", pt)


func _process_body(_delta: float) -> void:
	if visible and _pad.is_visible_in_tree():
		_pad.text = Controls.diagnostics()
	if visible and _gameplay.is_visible_in_tree():
		_refresh_time_settings(false)
	if visible and _pause_box.visible:
		_refresh_badges()
		var names := []
		for peer in Shed.crew:
			names.append(Shed.crew[peer]["name"] + (" (you)" if peer == Shed.me() else ""))
		_crew.text = "In the shed: " + ", ".join(names)
		_save_status.text = SaveGame.status_text()
		var client := Net.is_online() and not Net.is_host()
		_save_button.visible = not client
		_save_as_button.visible = not client
		_saves_button.visible = not client
		if Shed.abandoned_bikes() != _retrieve_shown:
			refresh_retrieve()


func show_title(status := "") -> void:
	_start_box.visible = true
	_pause_box.visible = false
	_garage_badge.visible = false
	_profile_badge.visible = false
	_status.text = status
	SaveGame.migrate(Settings.player_name)
	_hide_saves()
	_refresh_save_choice()
	show()
	(_solo if _solo.visible else _new_game).grab_focus()


func show_pause() -> void:
	_start_box.visible = false
	_pause_box.visible = true
	_status.text = ""
	_hide_saves()
	_show_panel(null)
	_garage_name = garage_name()
	_garage_badge.visible = true
	_profile_badge.visible = true
	_refresh_badges()
	if Net.is_host():
		_host_info.text = "Hosting on port %d.\n%s" % [Net.PORT, Net.join_instructions()]
	elif Net.is_online():
		_host_info.text = "Connected to a co-op shed."
	else:
		_host_info.text = "Working solo."
	_auto.button_pressed = Settings.auto_shift
	_snap.button_pressed = Settings.snap_placement
	_free_rotate.button_pressed = Settings.free_rotate
	_third_person.button_pressed = Settings.walk_third_person
	_refresh_time_settings(true)
	_refresh_debug()
	refresh_retrieve()
	_refresh_home()
	_refresh_adventure()
	show()
	_resume.grab_focus()


## The Debug tab is the host's alone: a player who has joined someone's shed doesn't see it
## (and their bike isn't fixed up by itself).
func _refresh_debug() -> void:
	var client := Net.is_online() and not Net.is_host()
	var at := _tabs.get_tab_idx_from_control(debug)
	if client and _tabs.current_tab == at:
		_tabs.current_tab = 0
	_tabs.set_tab_hidden(at, client)
	if client:
		debug.auto_fix = false


## Shows "Back to the garage" while you're out in the world, greyed out (and saying why) when
## it can't be used just now.
func _refresh_home() -> void:
	var why: String = home_check.call() if home_check.is_valid() else "home"
	_home.visible = why != "home"
	_home.disabled = why != ""
	_home.tooltip_text = Controls.hint(why) if why != "home" else ""


## The adventure button: start one or end it, greyed out (saying why) for anyone but the host.
func _refresh_adventure() -> void:
	var t := Adventure.menu_text()
	_adventure.text = str(t[0])
	_adventure.disabled = str(t[1]) != ""
	_adventure.tooltip_text = str(t[1])
	var c := Adventure.continue_text()
	_continue_adventure.visible = not c.is_empty()
	if not c.is_empty():
		_continue_adventure.text = str(c[0])
		_continue_adventure.disabled = str(c[1]) != ""
		_continue_adventure.tooltip_text = str(c[1])
	var trip := AdventureTrip.current
	_paper_map.visible = trip != null and trip.on_trip()
	var why := trip.map_reason() if _paper_map.visible else ""
	_paper_map.disabled = why != ""
	_paper_map.tooltip_text = why


## Lists bikes left out on the road (nobody riding them, away from the shed) with a button each
## to have the recovery truck bring it back to the yard by the roller door, for a small fee.
func refresh_retrieve() -> void:
	_retrieve_shown = Shed.abandoned_bikes()
	for child in _retrieve_box.get_children():
		child.queue_free()
	if _retrieve_shown.is_empty():
		return
	_retrieve_box.add_child(UITheme.label("Left out on the road:", 14, UITheme.ACCENT))
	for id in _retrieve_shown:
		var bike_id: int = id
		var b := _button("Retrieve %s (recovery truck, %s from the garage)" % [str(Shed.bikes[bike_id]["name"]),
			TvChannels.money_text(Shed.RETRIEVE_FEE)], func(): Shed.request({"a": "retrieve_bike", "bike": bike_id}))
		var why := Shed.retrieve_check({"bike": bike_id})
		b.disabled = why != ""
		b.tooltip_text = Controls.hint(why)
		_retrieve_box.add_child(b)


## On a pad: B goes back to the shed, LB / RB turn over the tabs of the panel that's open.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventJoypadButton or not event.is_pressed() or not keybinds.listening.is_empty():
		return
	if event.is_action_pressed("ui_cancel") and _pause_box.visible:
		_save()
		resume.emit()
	elif (event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev")) and open_panel():
		var step := 1 if event.is_action_pressed("tool_next") else -1
		var tabs := open_panel()
		tabs.current_tab = posmod(tabs.current_tab + step, tabs.get_tab_count())
	else:
		return
	get_viewport().set_input_as_handled()


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
	# One line, not wrapped: a wrapping label squeezed into a row stands its words on end.
	row.add_child(_row_label("Day length"))
	_day_length = OptionButton.new()
	_day_length.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	_time_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_row.add_child(_time_note)
	settings.add_child(time_row)
	_build_weather_settings(settings)
	_refresh_time_settings(true)


## A label for the start of a settings row: one line, centred on the row.
func _row_label(text: String) -> Label:
	var l := UITheme.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Weather: changing by itself, or held at one kind. On a co-op client the host's weather rules.
func _build_weather_settings(settings: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_row_label("Weather"))
	_weather = OptionButton.new()
	_weather.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weather.add_item("Changes by itself")
	for st in Weather.STATES:
		_weather.add_item("Always " + Weather.state_name(st).to_lower())
	_weather.selected = maxi(Weather.STATES.find(Settings.weather) + 1, 0)
	_weather.item_selected.connect(func(i):
		Settings.weather = "auto" if i == 0 else Weather.STATES[i - 1]
		Settings.save_settings())
	row.add_child(_weather)
	_weather_now = _row_label("")
	_weather_now.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	row.add_child(_weather_now)
	settings.add_child(row)

func _refresh_time_settings(move_slider: bool) -> void:
	var by_host := Daylight.set_by_host()
	_cycle.disabled = by_host
	_day_length.disabled = by_host
	_time.editable = not by_host
	_time_note.visible = by_host
	if _weather:
		_weather.disabled = by_host
		if not by_host:
			_weather.selected = maxi(Weather.STATES.find(Settings.weather) + 1, 0)
		var now := Weather.state_name(Weather.current.state) if Weather.current else Weather.state_name(Settings.weather_now)
		_weather_now.text = "Now: %s%s" % [now, "  (set by the host)" if by_host else ""]
	var h := Daylight.time_of_day() if Daylight.current else Settings.time_of_day
	_time_label.text = "Time of day  %s" % Daylight.clock_text(h)
	if move_slider or by_host:
		_time.set_value_no_signal(h)


## The game the start buttons carry on with (the one played last), with New game (it asks for
## the new save's name) and Load game (the Load screen) under them.
func _build_save_choice() -> void:
	_save_line = UITheme.label("", 14, Color(1, 1, 1, 0.7))
	_save_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_line.custom_minimum_size.x = 400.0
	_start_box.add_child(_save_line)
	_new_game = _button("New game...", func(): ask_new_game())
	_load_button = _button("Load game...", func(): show_saves(false))


## New game: asks for the save's name, then opens a new shed with a new character solo, or hosted.
func ask_new_game() -> void:
	saves.ask_name("New game", "Start solo", SaveGame.unique_name("%s's shed" % player_name()), "", func(called, as_host):
		new_shed = true
		new_name = called
		_save()
		if as_host:
			host_game.emit()
		else:
			ride_solo.emit(), "Host co-op")


## Opens the Load screen in place of the tabs; `in_game` from the Esc menu.
func show_saves(in_game: bool) -> void:
	_show_panel(null)
	saves.open(in_game)


func _hide_saves() -> void:
	if saves:
		saves.visible = false


func _refresh_save_choice() -> void:
	var all := SaveGame.list_saves()
	if not SaveGame.has_save(SaveGame.active_slot()) and not all.is_empty() and SaveGame.characters_in_saves():
		SaveGame.use_slot(str(all[0]["id"]))
	var saved := SaveGame.can_continue()
	var meta := SaveGame.read_meta(SaveGame.active_slot()) if saved else {}
	var called := str(meta.get("name", "the saved shed"))
	_solo.text = "Continue %s (solo)" % called if saved else "Open a new shed (solo)"
	_host.text = "Host %s as co-op" % called if saved else "Host a new co-op shed"
	_solo.visible = saved
	_host.visible = saved
	_save_line.visible = saved
	_save_line.text = "%s: %s" % [called, SaveGame.summary_text(meta)] if not meta.is_empty() \
		else "The saved shed can't be read; a new one will be opened."
	_load_button.text = "Load game... (%d)" % all.size() if all.size() > 0 else "Load game..."
	_load_button.disabled = all.is_empty()


func set_status(text: String) -> void:
	_status.text = text


func player_name() -> String:
	var n := _name.text.strip_edges()
	return n if n != "" else "Rider"


func _save() -> void:
	Settings.player_name = player_name()
	Settings.last_ip = _ip.text.strip_edges()
	Settings.save_settings()


func _volume_slider(slider_name: String, value: float, cb: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.value_changed.connect(cb)
	return slider


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	Controls.bind_text(b, text)
	b.pressed.connect(cb)
	return b


## Opens the garage's Blueprints tab, where a blueprint is built in an empty bay.
func show_blueprints() -> void:
	open_tab(blueprints)


## The garage's name for its badge: the save game's, or on a co-op client the host's shed.
func garage_name() -> String:
	if Net.is_online() and not Net.is_host():
		return "%s's shed" % str(Shed.crew.get(1, {}).get("name", "The host"))
	return str(SaveGame.read_meta(SaveGame.active_slot()).get("name", "Torque Shed"))


## The corner badges' lines and the profile picture's colours, and your Profile tab.
func _refresh_badges() -> void:
	_garage_badge.set_lines(_garage_name, "Account %s  ·  %d staff" % [TvChannels.money_text(Money.balance()), Staff.workers().size()])
	var tint: Color = Shed.PAINTS[Net.local_slot() % Shed.PAINTS.size()]
	var gear := RiderGear.worn_of(Shed.me())
	var helmet := RiderFigure.color_of(RiderGear.ITEMS.get(str(gear.get("helmet", "")), {}), "base", tint)
	if RiderGear.shell_color(gear, tint).a > 0.0:
		helmet = RiderGear.shell_color(gear, tint)   # painted another colour in the Shop
	var jacket := RiderFigure.color_of(RiderGear.ITEMS.get(str(gear.get("jacket", "")), {}), "base", tint)
	var line := "Level %d  ·  %s" % [Progress.level(), TvChannels.money_text(Progress.money())]
	for b: MenuBadge in [_profile_badge, _profile_pic]:
		b.set_rider(helmet, jacket, tint.darkened(0.5))
		b.set_lines(player_name(), line)
	if _profile_info.is_visible_in_tree():
		var worn := []
		for slot in RiderGear.SLOTS:
			worn.append(str(RiderGear.ITEMS.get(str(gear.get(slot, "")), {}).get("name", "-")))
		_profile_info.text = "Playing in: %s\nXP: %d in total\nYour cash: %s\nWearing: %s" % [_garage_name,
			int(Progress.profile.get("xp", 0)), TvChannels.money_text(Progress.money()), ", ".join(worn)]
		_show_style(RiderGear.style_of(gear))
