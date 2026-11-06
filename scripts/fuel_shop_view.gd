class_name FuelShopView
extends Node
## Your side of a fuel station's shop out on an adventure (see FuelShop for the rules): walk up
## to the counter at the kiosk's door (an "adv_counter" node of a "fuel" site, see
## AdventureStops.fuel_shop) and {interact} opens the parts computer as the station's shop, what's
## bought put down next to the bike you left on the forecourt.

## How close (m) you have to be to the counter.
const REACH := 2.5

var trip: AdventureTrip
var _layer: CanvasLayer
var _prompt: Label
## The counter you're close enough to use, or null.
var near: Node3D
var _near_timer := 0.0
var last_ridden := 0   # the bike you were last on (what you came to the forecourt on)


func _ready() -> void:
	name = "FuelShop"
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_prompt = UITheme.label("", 18, UITheme.ACCENT)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -520
	_prompt.offset_right = 520
	_prompt.offset_top = -180
	_prompt.offset_bottom = -150
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_prompt)


func _on() -> bool:
	return trip != null and trip.on_trip() and trip.main != null and trip.main.bike == null and trip.main.walker != null


func _physics_process(delta: float) -> void:
	if trip != null and trip.main != null and trip.main.bike != null:
		last_ridden = int(trip.main.riding_id)
	if not _on():
		near = null
		if _prompt and _prompt.text != "":
			_prompt.text = ""
		return
	_near_timer -= delta
	if _near_timer <= 0.0:
		_near_timer = 0.15
		near = find_near(trip.main.walker.global_position)
	var shown: bool = near != null and not trip.main.computer.visible
	_prompt.text = Controls.hint("{interact}: the %s shop: every part for a bike, on the business's account" % station_of(near)) if shown else ""


## The fuel station shop's counter within REACH of `at`, or null.
func find_near(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := REACH
	for node in get_tree().get_nodes_in_group(AdventureStops.COUNTER_GROUP):
		var n3 := node as Node3D
		if n3 == null or not n3.is_inside_tree() or str(n3.get_meta("site_kind", "")) != "fuel" or absf(n3.global_position.y - at.y) > 2.0:
			continue
		var d := Vector2(n3.global_position.x - at.x, n3.global_position.z - at.z).length()
		if d < best_d:
			best = n3
			best_d = d
	return best


## The station a counter's at ("Fuel station" when it has no name).
static func station_of(counter: Node3D) -> String:
	if counter == null:
		return "fuel station"
	var n := str(counter.get_meta("site", ""))
	return n if n != "" else "fuel station"


## The bike on the forecourt to strap what's bought on: of the bikes stood at the roadside within
## FuelShop.FORECOURT of `at`, the one you got off last, else the nearest; 0 for none.
func forecourt_bike(at: Vector3) -> int:
	var best := 0
	var best_d := FuelShop.FORECOURT
	var mine := last_ridden
	for id in Shed.bikes:
		if not Roadside.parked(int(id)):
			continue
		var xf := Roadside.xf_in(trip.world, Roadside.spot_of(int(id)))
		var d := xf.origin.distance_to(at)
		if d > FuelShop.FORECOURT:
			continue
		if int(id) == mine:
			return int(id)
		if d < best_d:
			best = int(id)
			best_d = d
	return best


## Opens the shop at `counter`. "" when it's open, else why not.
func open_at(counter: Node3D) -> String:
	if counter == null:
		return "There's no shop here."
	var main: Node = trip.main
	if main.bike != null:
		return "Get off the bike first."
	main.computer.open_shop(station_of(counter), forecourt_bike(counter.global_position))
	main._capture_mouse(false)
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if not _on() or near == null or event.is_echo() or not event.is_action_pressed("interact"):
		return
	var main: Node = trip.main
	if main.menu.visible or main.computer.visible:
		return
	get_viewport().set_input_as_handled()
	var why := open_at(near)
	if why != "":
		main.hud.flash(why, 2.5, true)
