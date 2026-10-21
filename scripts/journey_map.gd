class_name JourneyMap
extends Control
## The shed's map of a real region, where the crew plans a journey together: click to pin a start, stops and a finish
## (anyone's pin shows to everyone, see AdventureJourney), pick the style of ride, and see the road the game plans
## between the pins (RoutePlanner, on a worker thread as you go). The host starts the ride from here, for everyone.
##
## The wheel zooms, dragging with the right or middle button moves the map, a click on a pin takes it off.

signal closed

const PAPER := Color(0.93, 0.89, 0.78)
const MODE_TEXT := {
	"main": ["Quick", "the main roads, the sensible way"],
	"scenic": ["Scenic", "the quiet back roads, a bit slower"],
	"tracks": ["Tracks", "gravel and dirt wherever there are any"],
}
const REFRESH := 0.25

var region: RealRegion
var _view: JourneyView
var _pin_box: VBoxContainer
var _search: LineEdit
var _found: VBoxContainer
var _facts: Label
var _note: Label
var _start: Button
var _clear: Button
var _mode_buttons := {}
var _sig := ""
var _timer := 0.0


func _ready() -> void:
	name = "JourneyMap"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28.0
	row.offset_top = 28.0
	row.offset_right = -28.0
	row.offset_bottom = -28.0
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_content_margin_all(4)
	style.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 2.2
	row.add_child(frame)
	_view = JourneyView.new()
	frame.add_child(_view)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	side.add_child(UITheme.title("Plan a journey", 26))
	var how := UITheme.label("Click the map to pin a start, stops and a finish: everyone in the shed sees the pins. Click a pin to take it off. "
		+ "The wheel zooms; drag the map to move it.", 14, Color(0.85, 0.85, 0.85))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(how)
	_pin_box = VBoxContainer.new()
	_pin_box.add_theme_constant_override("separation", 3)
	side.add_child(_pin_box)
	_search = LineEdit.new()
	_search.placeholder_text = "Find a town, village or place"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill_found())
	side.add_child(_search)
	_found = VBoxContainer.new()
	_found.add_theme_constant_override("separation", 2)
	side.add_child(_found)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	side.add_child(modes)
	for m in ["main", "scenic", "tracks"]:
		var b := Button.new()
		b.toggle_mode = true
		b.text = str(MODE_TEXT[m][0])
		b.tooltip_text = str(MODE_TEXT[m][1])
		b.pressed.connect(func(): Shed.request({"a": "adventure_mode", "mode": m}))
		modes.add_child(b)
		_mode_buttons[m] = b
	_facts = UITheme.label("", 15, Color(0.92, 0.92, 0.92))
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_facts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_facts)
	_note = UITheme.label("", 14, Color(0.9, 0.8, 0.5))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_note)
	_clear = Button.new()
	_clear.text = "Clear the pins"
	_clear.pressed.connect(func(): Shed.request({"a": "adventure_clear"}))
	side.add_child(_clear)
	_start = Button.new()
	_start.text = "Start this ride for everyone"
	_start.pressed.connect(start)
	side.add_child(_start)
	var diaries := Button.new()
	diaries.text = "Adventure diaries"
	diaries.pressed.connect(func():
		if AdventureTrip.current:
			AdventureTrip.current.open_diary())
	side.add_child(diaries)
	var close := Button.new()
	Controls.bind_text(close, "Fold the map away ({menu})")
	close.pressed.connect(func(): closed.emit())
	side.add_child(close)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		closed.emit()


## Opens the map of region `region_id` (the one the crew's pins are on, if they have some).
func open(region_id: String) -> void:
	region = RealRegion.get_region(region_id)
	visible = true
	if region == null:
		_facts.text = "This game doesn't have that map."
		return
	_view.show_region(region)
	_sig = ""
	_fill_found()
	refresh()


## The places that match what's typed (or, with nothing typed, a few suggested destinations), each a button that pins
## it: the region's towns and villages, then its named places to stop and landmarks.
func _fill_found() -> void:
	for c in _found.get_children():
		c.queue_free()
	if region == null:
		return
	var hits := find_places(region, _search.text)
	if hits.is_empty():
		_found.add_child(UITheme.label("Nothing by that name here." if _search.text.strip_edges() != "" else "", 13, Color(0.7, 0.7, 0.7)))
		return
	if _search.text.strip_edges() == "":
		_found.add_child(UITheme.label("Worth a ride:", 13, Color(0.7, 0.7, 0.7)))
	for h: Dictionary in hits:
		var b := Button.new()
		b.text = "%s  (%s)" % [str(h["name"]), str(h["kind"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Pin %s" % str(h["name"])
		b.pressed.connect(func():
			Shed.request({"a": "adventure_pin", "region": region.id, "x": float(h["x"]), "z": float(h["z"])})
			_view.look_at_point(Vector2(float(h["x"]), float(h["z"]))))
		_found.add_child(b)


## The region's places whose names contain `text` (any case), up to `limit`: towns and villages first (the bigger
## first), then places to stop and landmarks with names. With nothing typed: suggested destinations, the biggest towns
## and villages, then the lighthouses, castles and beaches, spread about the region.
static func find_places(region: RealRegion, text: String, limit := 8) -> Array:
	var q := text.strip_edges().to_lower()
	var out: Array = []
	var seen := {}
	var rank := {"town": 0, "village": 1, "lighthouse": 2, "castle": 2, "viewpoint": 3, "beach": 3, "peak": 4, "cafe": 5, "inn": 5, "pub": 5, "fuel": 6, "campsite": 5, "layby": 7, "worship": 4}
	var rows: Array = []
	for p: Dictionary in region.places:
		rows.append({"name": str(p["name"]), "kind": str(p["kind"]), "x": float(p["x"]), "z": float(p["z"]), "pop": int(p.get("pop", 0))})
	for m: Dictionary in region.landmarks:
		if str(m.get("name", "")) != "":
			rows.append({"name": str(m["name"]), "kind": str(m["kind"]), "x": float(m["x"]), "z": float(m["z"]), "pop": 0})
	for m: Dictionary in region.pois:
		if str(m.get("name", "")) != "":
			rows.append({"name": str(m["name"]), "kind": str(m["kind"]), "x": float(m["x"]), "z": float(m["z"]), "pop": 0})
	for row: Dictionary in rows:
		if q != "" and not str(row["name"]).to_lower().contains(q):
			continue
		if q == "" and int(rank.get(row["kind"], 9)) > 2:
			continue
		var key := "%s|%s" % [row["name"], row["kind"]]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(row)
	out.sort_custom(func(a, b):
		var ra := int(rank.get(a["kind"], 9))
		var rb := int(rank.get(b["kind"], 9))
		if ra != rb:
			return ra < rb
		if int(a["pop"]) != int(b["pop"]):
			return int(a["pop"]) > int(b["pop"])
		return str(a["name"]) < str(b["name"]))
	if q == "":
		# Spread about: no two suggestions within 3 km of each other.
		var spread: Array = []
		for row: Dictionary in out:
			var near := false
			for s: Dictionary in spread:
				if Vector2(float(s["x"]) - float(row["x"]), float(s["z"]) - float(row["z"])).length() < 3000.0:
					near = true
					break
			if not near:
				spread.append(row)
		out = spread
	return out.slice(0, limit)


func _process(delta: float) -> void:
	if not visible or region == null:
		return
	_view.poll_shade()
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		AdventurePlans.poll()
		var sig := _signature()
		if sig != _sig:
			refresh()


func _signature() -> String:
	var plan := AdventureJourney.plan_of(Shed.journey)
	var res := AdventurePlans.result(plan) if not plan.is_empty() else {}
	return "%s|%s|%s|%s" % [JSON.stringify(Shed.journey), str(not res.is_empty()), str(Shed.is_authority()), str(Adventure.active())]


## Brings the panel and the route up to date with the board and the plan.
func refresh() -> void:
	_sig = _signature()
	for c in _pin_box.get_children():
		c.queue_free()
	var journey: Dictionary = Shed.journey if str(Shed.journey.get("region", "")) == region.id else {}
	var pins: Array = journey.get("pins", [])
	if pins.is_empty():
		var empty := UITheme.label("No pins yet.", 15, Color(0.7, 0.7, 0.7))
		_pin_box.add_child(empty)
	for i in pins.size():
		var p: Dictionary = pins[i]
		var line := HBoxContainer.new()
		var label := UITheme.label("%d  %s" % [i + 1, pin_label(i, pins.size(), p)], 15, Color(0.95, 0.95, 0.95))
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 200.0
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		line.add_child(label)
		var x := Button.new()
		x.text = "x"
		x.tooltip_text = "Take this pin off"
		x.pressed.connect(func(): Shed.request({"a": "adventure_unpin", "i": i}))
		line.add_child(x)
		_pin_box.add_child(line)
	var mode := str(journey.get("mode", "main"))
	for m in _mode_buttons:
		(_mode_buttons[m] as Button).set_pressed_no_signal(m == mode)
	_clear.disabled = pins.is_empty()
	var plan := AdventureJourney.plan_of(journey)
	_view.route_pts = PackedVector2Array()
	_note.text = ""
	if pins.size() < 2:
		_facts.text = "Pin where you start and where you want to get to; more pins in between make it your way.\n\n%s" % _region_text()
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
			_facts.text = "%s\n\n%s" % [journey_text(pack), "\n".join(pack.credits)]
			var step := 6
			for k in range(0, pack.x.size(), step):
				_view.route_pts.append(Vector2(pack.x[k], pack.z[k]))
			_view.route_pts.append(Vector2(pack.x[pack.x.size() - 1], pack.z[pack.z.size() - 1]))
	var why := AdventureJourney.start_reason(journey)
	_start.disabled = why != "" or plan.is_empty() or not plan_ok(plan)
	_note.text = why if why != "" and pins.size() >= 2 else ""
	_view.queue_redraw()


static func plan_ok(plan: Dictionary) -> bool:
	var res := AdventurePlans.result(plan)
	return not res.is_empty() and bool(res["ok"]) and (res["pack"] as RealPack).max_km() >= Adventure.MIN_KM


static func pin_label(i: int, count: int, p: Dictionary) -> String:
	var name := str(p.get("name", ""))
	var role := "Start" if i == 0 else ("Finish" if i == count - 1 else "Stop")
	var by := str(p.get("by", ""))
	var text := role if name == "" else "%s: %s" % [role, name]
	return text if by == "" else "%s (%s)" % [text, by]


func _region_text() -> String:
	return "%s: %d junctions, %d roads, %d places to stop." % [region.title, region.node_count(), region.edge_count(), region.pois.size()]


static func journey_text(pack: RealPack) -> String:
	var km := pack.max_km()
	var lines := ["%.1f km, %s of riding%s." % [km, AdventureDest.time_text(km), ", with a night's stop" if AdventureDest.overnight(km) else ""]]
	var roads: Array = pack.summary.get("roads", [])
	if not roads.is_empty():
		lines.append("Along " + (", ".join(roads.slice(0, -1)) + " and " + str(roads[-1]) if roads.size() > 1 else str(roads[0])) + ".")
	if int(pack.summary.get("climb_m", 0)) > 0:
		lines.append("%d metres of climbing, up to %d m above the sea." % [int(pack.summary["climb_m"]), int(pack.summary["top_m"])])
	var stops: PackedStringArray = []
	for kind in ["fuel", "cafe", "inn"]:
		var n := pack.pois_of(kind).size()
		if n > 0:
			stops.append("%d %s" % [n, {"fuel": "filling stations", "cafe": "cafes", "inn": "inns and hotels"}[kind]])
	if not stops.is_empty():
		lines.append("On the way: " + ", ".join(stops) + ".")
	return "\n".join(lines)


## Host: starts the ride along the pinned journey, for the whole crew.
func start() -> void:
	if start_journey():
		closed.emit()


## Starts the ride along the crew's board (the host), or says why it can't (true when it started).
static func start_journey() -> bool:
	var plan := AdventureJourney.plan_of(Shed.journey)
	var why := AdventureJourney.start_reason(Shed.journey)
	if why != "" or plan.is_empty():
		Shed.feedback.emit(why if why != "" else "Pin a start and somewhere to get to.", false)
		return false
	var res := AdventurePlans.result(plan, true)
	if not bool(res["ok"]):
		Shed.feedback.emit(str(res["error"]), false)
		return false
	var pack: RealPack = res["pack"]
	var names: Array = plan.get("names", [])
	var region := RealRegion.get_region(str(plan["region"]))
	var title := "Across %s" % (region.title if region != null else "the map")
	if names.size() >= 2 and str(names[0]) != "" and str(names[names.size() - 1]) != "" and names[0] != names[names.size() - 1]:
		title = "%s to %s" % [names[0], names[names.size() - 1]]
	Shed.request({"a": "adventure_start", "plan": plan, "seed": int(("0x" + pack.hash.left(7)).hex_to_int()), "title": title,
		"dest": AdventureDest.default_for(pack.theme, 1)})
	return true


## Every named place of the region (towns and villages, landmarks, places to stop), the biggest towns first.
static func all_places(region: RealRegion) -> Array:
	var rows: Array = []
	for p: Dictionary in region.places:
		rows.append({"name": str(p["name"]), "kind": str(p["kind"]), "x": float(p["x"]), "z": float(p["z"]), "pop": int(p.get("pop", 0))})
	for m: Dictionary in region.landmarks:
		if str(m.get("name", "")) != "":
			rows.append({"name": str(m["name"]), "kind": str(m["kind"]), "x": float(m["x"]), "z": float(m["z"]), "pop": 0})
	for m: Dictionary in region.pois:
		if str(m.get("name", "")) != "":
			rows.append({"name": str(m["name"]), "kind": str(m["kind"]), "x": float(m["x"]), "z": float(m["z"]), "pop": 0})
	rows.sort_custom(func(a, b):
		if int(a["pop"]) != int(b["pop"]):
			return int(a["pop"]) > int(b["pop"])
		return str(a["name"]) < str(b["name"]))
	return rows
