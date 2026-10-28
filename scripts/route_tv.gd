class_name RouteTv
extends Control
## The crew's route planner on a shed TV (a Dashboard page of kind "route": the Route planner channel every TV has, see
## TvChannels): the world (WorldView), from the whole globe down to the roads, with everyone's pins on it (Shed.journey,
## shared by the whole crew), the style of ride, the road the game plans between the pins, a search for places, and
## the host's Start. It is drawn in the TV's own 1024 x 576 page (under the header) and touched with the shed's touch
## cursor (ScreenTouch): there is no wheel or keyboard, so the map has zoom and move buttons, a touch on the world looks
## closer there, and the search has a keyboard of its own.
##
## What the crew does goes through Shed requests: adventure_pin (anywhere there are roads), adventure_unpin,
## adventure_mode, adventure_in (each rider's "I'm in" to the ride as it stands: the host's Start waits for the crew,
## see AdventureJourney.start_reason), adventure_load (a past ride, from this machine's diaries, or a journey code
## pasted: pinned again for the crew), adventure_clear and adventure_start. What the screen shows (where, how far in, the tab, what is typed
## in the search) is the crew's too (Shed.route_tv, changed by adventure_view): every Route planner TV in the shed, on
## every player's machine, shows the same, and a button pressed asks the host rather than moving this screen alone.

signal changed

const SIZE := Vector2(1024, 506)
const INK := Color(0.93, 0.95, 0.98)
const DIM := Color(0.62, 0.68, 0.74)
const PANEL_X := 616.0
const MODES := ["main", "scenic", "tracks"]
const REFRESH := 0.1
## Where the map looks when nobody has moved it and nothing is pinned: the world.
const WORLD := [30.0, 10.0, 30000000.0]
## How close a place found looks (metres across): close enough for its roads.
const FOUND_SPAN := 30000.0
const KEYS := ["ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ "]
const RESULTS := 5
## The most past rides listed.
const PAST := 5
## The buttons' look: a raised plate with an edge, so they stand out from the words round them (filled with the accent
## when they're on, the Start a green go when it can be pressed).
const BUTTON := Color(0.15, 0.2, 0.27)
const BUTTON_EDGE := Color(0.45, 0.58, 0.72)
const BUTTON_ON := Color(0.95, 0.6, 0.2)
const GO := Color(0.16, 0.55, 0.3)

var view: WorldView
var _pins: VBoxContainer
var _plan_box: VBoxContainer
var _plan_scroll: ScrollContainer
var _actions: HBoxContainer
var _credits_button: Button
var _find_box: VBoxContainer
var _rides_box: VBoxContainer
var _past: VBoxContainer
var _query: Label
var _results: VBoxContainer
var _facts: Label
var _credits: Label
var _paste_task := -1
var _pasted := [Vector2.INF]   # where the link pasted points (a worker sets it), see paste_link
var _note: Label
var _crew: Label
var _in: Button
var _start: Button
var _survey: Button
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
	view = WorldView.new()
	view.big = true
	view.position = Vector2(6, 6)
	view.size = Vector2(PANEL_X - 12, SIZE.y - 12)
	add_child(view)
	view.changed.connect(func(): changed.emit())
	view.asked_pin.connect(func(lat: float, lon: float, place: String):
		Shed.request({"a": "adventure_pin", "lat": lat, "lon": lon, "name": place})
		_timer = 0.0)
	view.asked_unpin.connect(func(i: int):
		Shed.request({"a": "adventure_unpin", "i": i})
		_timer = 0.0)
	view.asked_view.connect(func(lat: float, lon: float, span: float): ask({"lat": lat, "lon": lon, "span": span}))
	# Zoom and move, over the map's corner.
	var pad := GridContainer.new()
	pad.columns = 3
	pad.position = Vector2(16, SIZE.y - 168)
	for spec in [["+", func(): zoom(2.0)], ["^", func(): pan(Vector2(0, -0.3))], ["-", func(): zoom(0.5)],
		["<", func(): pan(Vector2(-0.3, 0))], ["o", fit], [">", func(): pan(Vector2(0.3, 0))],
		["", Callable()], ["v", func(): pan(Vector2(0, 0.3))], ["", Callable()]]:
		var b := _button(str(spec[0]), 44.0, 26)
		if (spec[1] as Callable).is_valid():
			b.pressed.connect(spec[1])
		else:
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0)
		pad.add_child(b)
	add_child(pad)
	# Survey, where nobody has mapped the roads (over the map's top corner).
	_survey = _button("Survey here", 180.0, 20)
	_survey.position = Vector2(PANEL_X - 12.0 - 190.0, 16.0)
	_survey.visible = false
	_survey.pressed.connect(survey)
	add_child(_survey)
	# The panel: tabs, the ride or the search.
	var panel := VBoxContainer.new()
	panel.position = Vector2(PANEL_X, 6)
	panel.size = Vector2(SIZE.x - PANEL_X - 6, SIZE.y - 12)
	panel.add_theme_constant_override("separation", 6)
	add_child(panel)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	panel.add_child(tabs)
	for t in [["plan", "The ride"], ["find", "Find a place"], ["rides", "Past rides"]]:
		var b := _button(str(t[1]), 0.0, 20)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): ask({"tab": str(t[0])}))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	# The ride: what's planned scrolls in the space it has, the buttons to act on it stay along the bottom.
	_plan_scroll = ScrollContainer.new()
	_plan_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_plan_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_plan_scroll)
	_plan_box = VBoxContainer.new()
	_plan_box.add_theme_constant_override("separation", 5)
	_plan_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan_scroll.add_child(_plan_box)
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
	_facts = _label("", 16, INK)
	_plan_box.add_child(_facts)
	_note = _label("", 16, Color(1.0, 0.82, 0.4))
	_plan_box.add_child(_note)
	_crew = _label("", 16, INK)
	_plan_box.add_child(_crew)
	# Where the map's data comes from: kept out of the way behind a small button.
	_credits_button = _button("Map data", 0.0, 13)
	_credits_button.toggle_mode = true
	_credits_button.custom_minimum_size = Vector2(0.0, 24.0)
	_credits_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_credits_button.toggled.connect(func(on: bool):
		_credits.visible = on
		changed.emit())
	_plan_box.add_child(_credits_button)
	_credits = _label("", 11, DIM)
	_credits.visible = false
	_plan_box.add_child(_credits)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	panel.add_child(_actions)
	var clear := _button("Clear", 0.0, 20)
	clear.pressed.connect(func(): Shed.request({"a": "adventure_clear"}))
	_actions.add_child(clear)
	_in = _button("I'm in", 0.0, 20)
	_in.toggle_mode = true
	_in.pressed.connect(im_in)
	_actions.add_child(_in)
	_start = _button("Start the ride", 0.0, 22, GO)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start.pressed.connect(start)
	_actions.add_child(_start)
	# The search: what's typed, a keyboard, and what it finds.
	_find_box = VBoxContainer.new()
	_find_box.add_theme_constant_override("separation", 4)
	_find_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_find_box)
	_query = _label("", 20, INK)
	_query.autowrap_mode = TextServer.AUTOWRAP_OFF
	_find_box.add_child(_query)
	for keys: String in KEYS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		_find_box.add_child(line)
		for ch in keys:
			var b := _button("_" if ch == " " else ch, 40.0, 18)   # (a gap between words)
			b.custom_minimum_size = Vector2(40.0, 34.0)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): type(ch))
			line.add_child(b)
	var edits := HBoxContainer.new()
	edits.add_theme_constant_override("separation", 4)
	_find_box.add_child(edits)
	for spec in [["Back", func(): ask({"q": _q().left(maxi(_q().length() - 1, 0))})], ["Clear", func(): ask({"q": ""})],
			["Paste a map link", func(): paste_link(DisplayServer.clipboard_get())]]:
		var b := _button(str(spec[0]), 0.0, 18)
		b.custom_minimum_size = Vector2(0.0, 34.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		edits.add_child(b)
	_results = VBoxContainer.new()
	_results.add_theme_constant_override("separation", 3)
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_find_box.add_child(_results)
	# Past rides: this machine's diaries, to pin again; a journey's code to send a mate, or one to paste.
	_rides_box = VBoxContainer.new()
	_rides_box.add_theme_constant_override("separation", 4)
	_rides_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_rides_box)
	_rides_box.add_child(_label("Ride one again: a touch pins it for the crew.", 17, DIM))
	_past = VBoxContainer.new()
	_past.add_theme_constant_override("separation", 3)
	_past.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rides_box.add_child(_past)
	var codes := HBoxContainer.new()
	codes.add_theme_constant_override("separation", 4)
	_rides_box.add_child(codes)
	for spec in [["Copy its code", copy_code], ["Paste a code", func(): paste_code(DisplayServer.clipboard_get())]]:
		var b := _button(str(spec[0]), 0.0, 18)
		b.custom_minimum_size = Vector2(0.0, 34.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		codes.add_child(b)
	refresh()


func _exit_tree() -> void:
	if _paste_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_paste_task)
		_paste_task = -1


func _label(text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, width: float, size_px: int, fill := BUTTON) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size_px)
	b.focus_mode = Control.FOCUS_NONE
	if width > 0.0:
		b.custom_minimum_size = Vector2(width, 44.0)
	else:
		b.custom_minimum_size = Vector2(0.0, 36.0)
	var on := fill.lerp(BUTTON_ON, 0.85) if fill == BUTTON else fill.lightened(0.2)
	for st in [["normal", fill, BUTTON_EDGE], ["hover", fill.lightened(0.15), BUTTON_EDGE.lightened(0.3)], ["pressed", on, BUTTON_ON],
			["hover_pressed", on.lightened(0.1), BUTTON_ON], ["disabled", Color(0.09, 0.11, 0.14), Color(0.25, 0.3, 0.36)]]:
		b.add_theme_stylebox_override(str(st[0]), button_box(st[1], st[2]))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.03) if fill == BUTTON else Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.06, 0.03) if fill == BUTTON else Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.5, 0.56))
	return b


## A button's plate: filled `fill`, edged `edge`, rounded.
static func button_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


# ---------------------------------------------------------------------------- the crew's view

## Asks the host to change what every Route planner TV shows (see Shed.route_tv): `fields` of {lat, lon, span, tab, q}.
## The screen changes when the host's answer comes back, the same moment as everyone else's.
func ask(fields: Dictionary) -> void:
	Shed.request({"a": "adventure_view", "view": fields})
	_timer = 0.0   # (the host's answer is looked for next frame: at once, on the host)


func _tab() -> String:
	return str(Shed.route_tv.get("tab", "plan"))


func _q() -> String:
	return str(Shed.route_tv.get("q", ""))


## Types `ch` into the crew's search.
func type(ch: String) -> void:
	ask({"q": _q() + ch.to_lower()})


## Where the crew's view is, [lat, lon, span]: the host's, else the crew's pins, else the world.
func _view() -> Array:
	var v: Dictionary = Shed.route_tv
	if v.has("lat"):
		return [float(v["lat"]), float(v["lon"]), float(v["span"])]
	return _fit_view()


## [lat, lon, span] showing all of the crew's pins (and room round them), else the world.
func _fit_view() -> Array:
	var geo: Array = []
	for i in (Shed.journey.get("pins", []) as Array).size():
		geo.append(AdventureJourney.pin_geo(Shed.journey, i))
	return _fit_geo(geo)


## [lat, lon, span] showing all of `geo` ((lat, lon) each; Vector2.INF ones left out), else the world.
static func _fit_geo(geo: Array) -> Array:
	var box := Rect2()
	var n := 0
	for g: Vector2 in geo:
		if g == Vector2.INF:
			continue
		box = Rect2(g, Vector2.ZERO) if n == 0 else box.expand(g)
		n += 1
	if n == 0:
		return WORLD.duplicate()
	var mid := box.get_center()
	var across := maxf(box.size.y * WorldMap.metres_per_unit(mid.x) / 360.0, box.size.x * WorldMap.EARTH / 360.0 * 1.4)
	return [mid.x, mid.y, clampf(across * 1.6, 15000.0, AdventureJourney.SPAN_MAX)]


## Asks the surveyors (through the host, see Survey) to map the roads of the cells in view nobody has mapped yet.
func survey() -> void:
	var cells: Array = []
	for c in view.unmapped.slice(0, Survey.MAX_CELLS):
		cells.append("%d_%d" % [c.x, c.y])
	if not cells.is_empty():
		Shed.request({"a": "adventure_survey", "cells": cells})
		_timer = 0.0


## Takes the crew's view to where map link `text` points (a short link is followed on a worker, see MapLink). A
## journey code is pinned instead (paste_code).
func paste_link(text: String) -> void:
	if _paste_task >= 0:
		return
	if text.contains(AdventureJourney.CODE_PREFIX):
		paste_code(text)
		return
	var at := MapLink.parse(text)
	if at != Vector2.INF or not MapLink.needs_following(text):
		_go_to_pasted(at)
		return
	_pasted[0] = Vector2.INF
	var got := _pasted
	_paste_task = WorkerThreadPool.add_task(func(): got[0] = MapLink.resolve(text))


func _go_to_pasted(at: Vector2) -> void:
	if at == Vector2.INF:
		Shed.feedback.emit("Copy a map link (or a place's lat, lon) first: that one doesn't say where.", false)
		return
	ask({"lat": at.x, "lon": at.y, "span": FOUND_SPAN, "tab": "plan", "q": ""})


## Copies the code of the journey on the board (AdventureJourney.code_of), to send a mate.
func copy_code() -> void:
	var code := AdventureJourney.code_of(AdventureJourney.kept_of(Shed.journey))
	if code == "":
		Shed.feedback.emit("Pin a start and somewhere to get to first: then there's a journey to copy.", false)
		return
	DisplayServer.clipboard_set(code)
	Shed.feedback.emit("Copied the journey's code: paste it to your mates, and they paste it on their Route planner.", true)


## Pins the journey in code `text` (AdventureJourney.from_code) for the crew.
func paste_code(text: String) -> void:
	var kept := AdventureJourney.from_code(text)
	if kept.is_empty():
		Shed.feedback.emit("Copy a journey's code (it starts %s) first." % AdventureJourney.CODE_PREFIX, false)
		return
	pin_again(kept)


## Pins kept journey `kept` again, for the crew (in place of what's on the board), and shows it.
func pin_again(kept: Dictionary) -> void:
	Shed.request({"a": "adventure_load", "journey": kept})
	var v := _fit_geo((kept["pins"] as Array).map(func(p): return Vector2(float(p[0]), float(p[1]))))
	ask({"lat": v[0], "lon": v[1], "span": v[2], "tab": "plan"})


## The data a planned road is drawn from, said short: [credit...] -> one line.
static func credits_line(credits: Array) -> String:
	var said := PackedStringArray()
	var all := " ".join(credits)
	if all.contains("OpenStreetMap"):
		said.append("roads © OpenStreetMap contributors and Overture Maps (ODbL)")
	if all.contains("Mapterhorn"):
		said.append("heights Mapterhorn")
	if all.contains("Canopy Height"):
		said.append("trees Meta and WRI (CC BY 4.0)")
	if all.contains("ESA WorldCover"):
		said.append("place Natural Earth, Beck et al. 2023 and ESA WorldCover 2021 with Copernicus Sentinel data (CC BY 4.0), CRU TS (OGL)")
	return ("Map data: " + "; ".join(said) + ".") if not said.is_empty() else ""


## Looks closer (factor over 1) or further out, about the middle.
func zoom(factor: float) -> void:
	var v := _view()
	ask({"lat": v[0], "lon": v[1], "span": float(v[2]) / factor})


## Moves the crew's view by a fraction of the map (to the right and down for positive).
func pan(frac: Vector2) -> void:
	var g := view.to_geo(view.size * (Vector2(0.5, 0.5) + frac))
	ask({"lat": g.x, "lon": g.y, "span": _view()[2]})


## Shows the crew all of their pins, or the world.
func fit() -> void:
	var v := _fit_view()
	ask({"lat": v[0], "lon": v[1], "span": v[2]})


func _process(delta: float) -> void:
	if view != null and view.poll():
		changed.emit()
		_sig = ""   # (the roads in view came, or the world's map: the search may find more)
	var can_survey := view != null and view.span <= WorldView.ROADS_SPAN and not view.unmapped.is_empty() and view.surveying().is_empty() \
		and not view.busy()
	if _survey != null and _survey.visible != can_survey:
		_survey.visible = can_survey
		changed.emit()
	if _warm < 8:
		_warm += 1   # (the controls lay themselves out over the first frames: the TV is redrawn as they settle)
		changed.emit()
	if _paste_task >= 0 and WorkerThreadPool.is_task_completed(_paste_task):
		WorkerThreadPool.wait_for_task_completion(_paste_task)
		_paste_task = -1
		_go_to_pasted(_pasted[0])
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
	var crew := PackedStringArray()
	for peer in Shed.crew:
		crew.append("%d:%s" % [peer, Shed.crew[peer].get("name", "")])
	return "%s|%s|%s|%s|%s|%s" % [JSON.stringify(Shed.journey), JSON.stringify(Shed.route_tv), str(not res.is_empty()), str(Shed.is_authority()),
		str(Adventure.active()), ",".join(crew)]


## Brings the panel and the map up to date with the crew's view, the board and the plan, and says the TV should be
## redrawn.
func refresh() -> void:
	_sig = _signature()
	var v := _view()
	view.show_view(v[0], v[1], v[2])
	var tab := _tab()
	for t in _tab_buttons:
		(_tab_buttons[t] as Button).set_pressed_no_signal(t == tab)
	_plan_scroll.visible = tab == "plan"
	_actions.visible = tab == "plan"
	_find_box.visible = tab == "find"
	_rides_box.visible = tab == "rides"
	_refresh_plan()
	if tab == "find":
		_refresh_find()
	if tab == "rides":
		_refresh_rides()
	changed.emit()


func _refresh_plan() -> void:
	for c in _pins.get_children():
		c.queue_free()
	var journey: Dictionary = Shed.journey
	var pins: Array = journey.get("pins", [])
	if pins.is_empty():
		_pins.add_child(_label("Find a place or touch the map to look closer, then touch a road to pin where you start.", 17, DIM))
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
	view.route_geo = PackedVector2Array()
	_note.text = ""
	_credits.text = ""
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
			_credits.text = credits_line(pack.credits)
			var frame := RealRegion.frame_of(str(plan["region"]))
			if frame != Vector2.INF:
				for k in range(0, pack.x.size(), 6):
					view.route_geo.append(RealRegion.from_frame(frame, pack.x[k], pack.z[k]))
				view.route_geo.append(RealRegion.from_frame(frame, pack.x[pack.x.size() - 1], pack.z[pack.z.size() - 1]))
	var why := AdventureJourney.start_reason(journey)
	_start.disabled = why != "" or plan.is_empty() or not JourneyMap.plan_ok(plan)
	_note.text = why if why != "" and pins.size() >= 2 else ""
	# Who's in: each rider's say-so, when there's a crew to agree.
	var marked := AdventureJourney.riders_in(journey)
	_in.visible = AdventureJourney.needs_crew()
	_in.disabled = pins.size() < 2 or Adventure.active()
	_in.set_pressed_no_signal(marked.has(Shed.me()))
	_crew.visible = AdventureJourney.needs_crew() and pins.size() >= 2
	_credits_button.visible = _credits.text != ""
	_credits.visible = _credits_button.visible and _credits_button.button_pressed
	_crew.text = AdventureJourney.crew_line(journey)
	_start.text = "Start the ride" if not AdventureJourney.needs_crew() or marked.size() == Shed.crew.size() \
		else "Start (%d of %d in)" % [marked.size(), Shed.crew.size()]
	view.queue_redraw()


## What the search finds: the towns and villages of the roads in view first, then the world's towns and cities:
## [{name, lat, lon, what}].
func found() -> Array:
	var q := _q().strip_edges()
	var out: Array = []
	if q == "":
		return out
	if view.roads != null:
		var frame := Vector2(view.roads.frame_lat, view.roads.frame_lon)
		for p: Dictionary in view.roads.places:
			if out.size() >= RESULTS:
				break
			if WorldMap.fold(str(p["name"])).begins_with(q):
				var g := RealRegion.from_frame(frame, float(p["x"]), float(p["z"]))
				out.append({"name": str(p["name"]), "lat": g.x, "lon": g.y, "what": str(p["kind"])})
	for p: Array in WorldMap.search(q, RESULTS):
		if out.size() >= RESULTS:
			break
		if out.any(func(h): return h["name"] == str(p[0]) and absf(float(h["lat"]) - float(p[1])) < 0.2):
			continue
		out.append({"name": str(p[0]), "lat": float(p[1]), "lon": float(p[2]), "what": str(p[4])})
	return out


func _refresh_find() -> void:
	_query.text = "Find: %s_" % _q().to_upper()
	for c in _results.get_children():
		c.queue_free()
	var hits := found()
	for h: Dictionary in hits:
		var b := _button("%s  (%s)" % [str(h["name"]), str(h["what"])], 0.0, 18)
		b.custom_minimum_size = Vector2(0.0, 34.0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.pressed.connect(func(): ask({"lat": float(h["lat"]), "lon": float(h["lon"]), "span": FOUND_SPAN, "tab": "plan", "q": ""}))
		_results.add_child(b)
	if hits.is_empty():
		_results.add_child(_label("Type the start of a town's name." if _q() == "" else "Nowhere by that name.", 17, DIM))


## Says this rider is in on the ride as it stands, or isn't after all.
func im_in() -> void:
	Shed.request({"a": "adventure_in", "in": not AdventureJourney.riders_in(Shed.journey).has(Shed.me())})
	_timer = 0.0


## The rides this machine's diaries keep journeys of, newest first: [{title, km, date, journey}], PAST at most.
static func past_rides() -> Array:
	var out: Array = []
	for d: Dictionary in AdventureDiary.list():
		if out.size() >= PAST:
			break
		if not (d.get("journey", {}) as Dictionary).is_empty():
			out.append(d)
	return out


func _refresh_rides() -> void:
	for c in _past.get_children():
		c.queue_free()
	var rides := past_rides()
	for d: Dictionary in rides:
		var b := _button("%s  (%d km, %s)" % [str(d["title"]), roundi(float(d["km"])), str(d["date"])], 0.0, 17)
		b.custom_minimum_size = Vector2(0.0, 34.0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		var kept: Dictionary = d["journey"]
		b.pressed.connect(func(): pin_again(kept))
		_past.add_child(b)
	if rides.is_empty():
		_past.add_child(_label("No rides in your diaries yet: the ones you ride are kept here.", 17, DIM))


## Host: starts the ride along the pinned journey, for the whole crew.
func start() -> void:
	JourneyMap.start_journey()
