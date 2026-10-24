class_name JourneyMap
extends Control
## The Esc menu's route planner: the same planner as the shed TVs' Route planner channel (RouteTv: the world, the
## crew's pins and view, the style of ride, Start), full screen, with the mouse. A click is a touch; the wheel zooms
## about the pointer. Its view is the crew's like any TV's (Shed.route_tv), so whoever has it open and whoever is at a
## TV look at the same thing.
##
## It also holds what the planners share: the styles of ride, a pin's label, the journey's facts, starting it.

signal closed

const MODE_TEXT := {
	"main": ["Quick", "the main roads, the sensible way"],
	"scenic": ["Scenic", "the quiet back roads, a bit slower"],
	"tracks": ["Tracks", "gravel and dirt wherever there are any"],
}

## The planner, scaled to fill the screen.
var planner: RouteTv
var _frame: Control


func _ready() -> void:
	name = "JourneyMap"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_frame)
	planner = RouteTv.new()
	_frame.add_child(planner)
	planner.position = Vector2.ZERO
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -52.0
	bar.offset_bottom = -12.0
	bar.offset_left = 28.0
	bar.offset_right = -28.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	var diaries := Button.new()
	diaries.text = "Adventure diaries"
	diaries.pressed.connect(func():
		if AdventureTrip.current:
			AdventureTrip.current.open_diary())
	bar.add_child(diaries)
	var close := Button.new()
	Controls.bind_text(close, "Fold the map away ({menu})")
	close.pressed.connect(func(): closed.emit())
	bar.add_child(close)
	resized.connect(_fit)
	_fit()


## Scales the planner to fill the screen above the bar, keeping its shape.
func _fit() -> void:
	if planner == null:
		return
	var room := size - Vector2(56.0, 56.0 + 52.0)
	var k := maxf(minf(room.x / RouteTv.SIZE.x, room.y / RouteTv.SIZE.y), 0.1)
	_frame.scale = Vector2(k, k)
	_frame.position = Vector2((size.x - RouteTv.SIZE.x * k) * 0.5, 28.0)


func _process(_delta: float) -> void:
	if visible and Adventure.active():
		closed.emit()   # (the ride has started: off we go)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		closed.emit()


## Opens the planner (`_region_id` is from when the map was one region's: the crew's view says where it looks now).
func open(_region_id := "") -> void:
	visible = true
	_fit()
	if planner != null and planner.is_inside_tree():
		planner.refresh()


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


static func plan_ok(plan: Dictionary) -> bool:
	var res := AdventurePlans.result(plan)
	return not res.is_empty() and bool(res["ok"]) and (res["pack"] as RealPack).max_km() >= Adventure.MIN_KM


static func pin_label(i: int, count: int, p: Dictionary) -> String:
	var name := str(p.get("name", ""))
	var role := "Start" if i == 0 else ("Finish" if i == count - 1 else "Stop")
	var by := str(p.get("by", ""))
	var text := role if name == "" else "%s: %s" % [role, name]
	return text if by == "" else "%s (%s)" % [text, by]


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
	var title := "Across %s" % RealRegion.title_of(str(plan["region"]))
	if names.size() >= 2 and str(names[0]) != "" and str(names[names.size() - 1]) != "" and names[0] != names[names.size() - 1]:
		title = "%s to %s" % [names[0], names[names.size() - 1]]
	Shed.request({"a": "adventure_start", "plan": plan, "seed": int(("0x" + pack.hash.left(7)).hex_to_int()), "title": title})
	return true
