class_name RouteTv
extends Control
## The crew's route planner on a shed TV (a Dashboard page of kind "route": the Route planner channel every TV has, see TvChannels): the map of a real
## region with everyone's pins on it (Shed.journey, shared by the whole crew), the style of ride, the road the game
## plans between the pins, places to pin from a list, and the host's Start. It is drawn in the TV's own 1024 x 576 page
## (under the header) and touched with the shed's touch cursor (ScreenTouch): there is no wheel or keyboard, so the map
## has zoom and move buttons and places are picked from a list.
##
## What the crew does goes through the same Shed requests as the full-screen map (JourneyMap): adventure_pin,
## adventure_unpin, adventure_mode, adventure_clear and adventure_start.

signal changed

const SIZE := Vector2(1024, 506)
const INK := Color(0.93, 0.95, 0.98)
const DIM := Color(0.62, 0.68, 0.74)
const PANEL_X := 616.0
const MODES := ["main", "scenic", "tracks"]
const CATEGORIES := [["Towns", ["town", "village"]], ["Sights", ["lighthouse", "castle", "viewpoint", "beach", "peak", "worship"]],
	["Eat and drink", ["cafe", "pub", "inn"]], ["Fuel", ["fuel"]]]
const PER_PAGE := 7
const REFRESH := 0.25

var region: RealRegion
var view: JourneyView
var _tab := "plan"            # "plan" or "places"
var _category := 0
var _page := 0
var _region_row: HBoxContainer
var _pins: VBoxContainer
var _plan_box: VBoxContainer
var _places_box: VBoxContainer
var _place_list: VBoxContainer
var _facts: Label
var _note: Label
var _start: Button
var _mode_buttons := {}
var _tab_buttons := {}
var _sig := ""
var _timer := 0.0
var _warm := 0


func _init() -> void:
	name = "RouteTv"
	position = Vector2(0, 70)
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.06, 0.09)
	back.size = SIZE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	view = JourneyView.new()
	view.big = true
	view.position = Vector2(6, 6)
	view.size = Vector2(PANEL_X - 12, SIZE.y - 12)
	add_child(view)
	view.moved.connect(func(): changed.emit())
	# Zoom and move, over the map's corner.
	var pad := GridContainer.new()
	pad.columns = 3
	pad.position = Vector2(16, SIZE.y - 168)
	for spec in [["+", func(): view.zoom_by(1.6)], ["^", func(): view.pan_by(Vector2(0, -0.3))], ["-", func(): view.zoom_by(1.0 / 1.6)],
		["<", func(): view.pan_by(Vector2(-0.3, 0))], ["o", func(): view.fit()], [">", func(): view.pan_by(Vector2(0.3, 0))],
		["", Callable()], ["v", func(): view.pan_by(Vector2(0, 0.3))], ["", Callable()]]:
		var b := _button(str(spec[0]), 44.0, 26)
		if (spec[1] as Callable).is_valid():
			b.pressed.connect(spec[1])
		else:
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0)
		pad.add_child(b)
	add_child(pad)
	# The panel: region, tabs, the plan or the places.
	var panel := VBoxContainer.new()
	panel.position = Vector2(PANEL_X, 6)
	panel.size = Vector2(SIZE.x - PANEL_X - 6, SIZE.y - 12)
	panel.add_theme_constant_override("separation", 6)
	add_child(panel)
	_region_row = HBoxContainer.new()
	_region_row.add_theme_constant_override("separation", 6)
	panel.add_child(_region_row)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	panel.add_child(tabs)
	for t in [["plan", "The ride"], ["places", "Places"]]:
		var b := _button(str(t[1]), 0.0, 20)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			_tab = str(t[0])
			_page = 0
			refresh())
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	_plan_box = VBoxContainer.new()
	_plan_box.add_theme_constant_override("separation", 5)
	_plan_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_plan_box)
	_pins = VBoxContainer.new()
	_pins.add_theme_constant_override("separation", 3)
	_plan_box.add_child(_pins)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 5)
	_plan_box.add_child(modes)
	for m in MODES:
		var b := _button(str(JourneyMap.MODE_TEXT[m][0]), 0.0, 20)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): Shed.request({"a": "adventure_mode", "mode": m}))
		modes.add_child(b)
		_mode_buttons[m] = b
	_facts = _label("", 17, INK)
	_facts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plan_box.add_child(_facts)
	_note = _label("", 16, Color(1.0, 0.82, 0.4))
	_plan_box.add_child(_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_plan_box.add_child(row)
	var clear := _button("Clear", 0.0, 20)
	clear.pressed.connect(func(): Shed.request({"a": "adventure_clear"}))
	row.add_child(clear)
	_start = _button("Start the ride", 0.0, 22)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start.pressed.connect(start)
	row.add_child(_start)
	_places_box = VBoxContainer.new()
	_places_box.add_theme_constant_override("separation", 5)
	_places_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_places_box)
	var cats := GridContainer.new()
	cats.columns = 2
	cats.add_theme_constant_override("h_separation", 5)
	cats.add_theme_constant_override("v_separation", 5)
	_places_box.add_child(cats)
	for i in CATEGORIES.size():
		var b := _button(str(CATEGORIES[i][0]), 0.0, 18)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			_category = i
			_page = 0
			refresh())
		cats.add_child(b)
		b.set_meta("cat", i)
	_place_list = VBoxContainer.new()
	_place_list.add_theme_constant_override("separation", 3)
	_place_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_places_box.add_child(_place_list)
	var paging := HBoxContainer.new()
	paging.add_theme_constant_override("separation", 6)
	_places_box.add_child(paging)
	var up := _button("Back", 0.0, 18)
	up.pressed.connect(func():
		_page = maxi(_page - 1, 0)
		refresh())
	paging.add_child(up)
	var down := _button("More", 0.0, 18)
	down.pressed.connect(func():
		_page += 1
		refresh())
	paging.add_child(down)
	_places_box.set_meta("cats", cats)
	_show_region(Shed.journey.get("region", ""))
	refresh()


func _label(text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, width: float, size_px: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size_px)
	b.focus_mode = Control.FOCUS_NONE
	if width > 0.0:
		b.custom_minimum_size = Vector2(width, 44.0)
	else:
		b.custom_minimum_size = Vector2(0.0, 36.0)
	return b


## The region the board is on: the one the crew's pins are on, else the first the game has.
func _region_id() -> String:
	var id := str(Shed.journey.get("region", ""))
	return id if RealRegion.list().has(id) else (RealRegion.list()[0] if not RealRegion.list().is_empty() else "")


func _show_region(id: String) -> void:
	var rid := id if RealRegion.list().has(id) else _region_id()
	var r := RealRegion.get_region(rid) if rid != "" else null
	if r != region:
		region = r
		view.show_region(r)


func _process(delta: float) -> void:
	if view != null and view.poll_shade():
		changed.emit()
	if _warm < 8:
		_warm += 1   # (the controls lay themselves out over the first frames: the TV is redrawn as they settle)
		changed.emit()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	AdventurePlans.poll()
	if _signature() != _sig:
		refresh()


func _signature() -> String:
	var plan := AdventureJourney.plan_of(Shed.journey)
	var res := AdventurePlans.result(plan) if not plan.is_empty() else {}
	return "%s|%s|%s|%s|%s|%s" % [JSON.stringify(Shed.journey), str(not res.is_empty()), str(Shed.is_authority()), str(Adventure.active()), _tab, _page]


## Brings the panel and the route up to date with the board and the plan, and says the TV should be redrawn.
func refresh() -> void:
	_sig = _signature()
	var journey_region := str(Shed.journey.get("region", ""))
	_show_region(journey_region if journey_region != "" else (region.id if region != null else ""))
	if region == null:
		_facts.text = "This game has no map to plan on."
		changed.emit()
		return
	# Which regions there are to pick (the one the board is on lit).
	for c in _region_row.get_children():
		c.queue_free()
	for id in RealRegion.list():
		var r := RealRegion.get_region(id)
		if r == null:
			continue
		var b := _button(r.title, 0.0, 20)
		b.toggle_mode = true
		b.button_pressed = id == region.id
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if id != region.id:
				Shed.request({"a": "adventure_clear"})
				_show_region(id)
				refresh())
		_region_row.add_child(b)
	for t in _tab_buttons:
		(_tab_buttons[t] as Button).set_pressed_no_signal(t == _tab)
	_plan_box.visible = _tab == "plan"
	_places_box.visible = _tab == "places"
	if _tab == "plan":
		_refresh_plan()
	else:
		_refresh_places()
	changed.emit()


func _refresh_plan() -> void:
	for c in _pins.get_children():
		c.queue_free()
	var journey: Dictionary = Shed.journey if str(Shed.journey.get("region", "")) == region.id else {}
	var pins: Array = journey.get("pins", [])
	if pins.is_empty():
		_pins.add_child(_label("Touch the map or pick a place to pin where you start.", 17, DIM))
	for i in pins.size():
		var p: Dictionary = pins[i]
		var row := HBoxContainer.new()
		var l := _label("%d  %s" % [i + 1, JourneyMap.pin_label(i, pins.size(), p)], 17, INK)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true
		l.custom_minimum_size.x = 300.0
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var x := _button("x", 40.0, 18)
		x.pressed.connect(func(): Shed.request({"a": "adventure_unpin", "i": i}))
		row.add_child(x)
		_pins.add_child(row)
	var mode := str(journey.get("mode", "main"))
	for m in _mode_buttons:
		(_mode_buttons[m] as Button).set_pressed_no_signal(m == mode)
	var plan := AdventureJourney.plan_of(journey)
	view.route_pts = PackedVector2Array()
	_note.text = ""
	if pins.size() < 2:
		_facts.text = "Pin where you start and where you want to get to. More pins in between make it your way."
	elif plan.is_empty():
		_facts.text = "Those pins can't be planned."
	else:
		var res := AdventurePlans.result(plan)
		if res.is_empty():
			_facts.text = "Planning the road..."
		elif not bool(res["ok"]):
			_facts.text = str(res["error"])
		else:
			var pack: RealPack = res["pack"]
			_facts.text = JourneyMap.journey_text(pack)
			for k in range(0, pack.x.size(), 6):
				view.route_pts.append(Vector2(pack.x[k], pack.z[k]))
			view.route_pts.append(Vector2(pack.x[pack.x.size() - 1], pack.z[pack.z.size() - 1]))
	var why := AdventureJourney.start_reason(journey)
	_start.disabled = why != "" or plan.is_empty() or not JourneyMap.plan_ok(plan)
	_note.text = why if why != "" and pins.size() >= 2 else ""
	view.queue_redraw()


func _refresh_places() -> void:
	var cats: GridContainer = _places_box.get_meta("cats")
	for c in cats.get_children():
		(c as Button).set_pressed_no_signal(int(c.get_meta("cat")) == _category)
	for c in _place_list.get_children():
		c.queue_free()
	var kinds: Array = CATEGORIES[_category][1]
	var hits := JourneyMap.all_places(region).filter(func(h): return kinds.has(str(h["kind"])))
	var pages := maxi(int(ceil(float(hits.size()) / PER_PAGE)), 1)
	_page = clampi(_page, 0, pages - 1)
	for h: Dictionary in hits.slice(_page * PER_PAGE, (_page + 1) * PER_PAGE):
		var b := _button("%s  (%s)" % [str(h["name"]), str(h["kind"])], 0.0, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.pressed.connect(func():
			Shed.request({"a": "adventure_pin", "region": region.id, "x": float(h["x"]), "z": float(h["z"])})
			view.look_at_point(Vector2(float(h["x"]), float(h["z"])))
			_tab = "plan"
			refresh())
		_place_list.add_child(b)
	if hits.is_empty():
		_place_list.add_child(_label("Nothing of that kind here.", 17, DIM))
	_place_list.add_child(_label("Page %d of %d" % [_page + 1, pages], 15, DIM))
	view.queue_redraw()


## Host: starts the ride along the pinned journey, for the whole crew.
func start() -> void:
	JourneyMap.start_journey()
