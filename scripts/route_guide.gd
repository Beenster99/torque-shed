class_name RouteGuide
extends RefCounted
## The satnav's brain: where you are on a RouteJourney's planned route, how far is left, what the next
## instruction is and how far off, and when you have strayed from the route. SatnavPanel draws it.

## Further than this from the route line (metres) and you are off route.
const OFF_ROUTE := 45.0
## How far ahead (metres) a turn is announced, and when it counts as "now".
const ANNOUNCE := 1200.0
const NOW := 40.0

var journey: RouteJourney
## Metres along the route, from the shed's loop, and how far from the line.
var d := 0.0
var off := 0.0
## The next instruction that matters ({d, turn, onto...}), or {} when there is none.
var next_turn := {}
var next_dist := 0.0
var remaining := 0.0
var off_route := false
## Unit direction (route coordinates) towards the nearest bit of route, when off route.
var back_dir := Vector2.ZERO
## Index of the nearest route point, kept between updates so finding it is cheap.
var hint := 0
var _turn_index := 0


func _init(j: RouteJourney) -> void:
	journey = j


## Takes the rider's position `p` in route coordinates.
func update(p: Vector2) -> void:
	var pr := journey.progress(p, hint)
	hint = int(pr["i"])
	d = float(pr["d"])
	off = float(pr["off"])
	off_route = off > OFF_ROUTE
	remaining = maxf(journey.length_m - d, 0.0)
	back_dir = Vector2.ZERO
	if off_route:
		back_dir = ((pr["at"] as Vector2) - p).normalized()
	# Turns come in order along the route: carry on from the last one, or back up if we have moved back.
	while _turn_index > 0 and float(journey.turns[_turn_index - 1]["d"]) > d:
		_turn_index -= 1
	while _turn_index < journey.turns.size() and (float(journey.turns[_turn_index]["d"]) < d - 10.0 \
			or journey.turns[_turn_index]["turn"] == "straight"):
		_turn_index += 1
	if _turn_index < journey.turns.size():
		next_turn = journey.turns[_turn_index]
		next_dist = maxf(float(next_turn["d"]) - d, 0.0)
	else:
		next_turn = {}
		next_dist = 0.0


## "Turn left onto Route 27", "Bear right", "Arrive at your destination".
func instruction() -> String:
	if off_route:
		return "Off route: head back to the route"
	if next_turn.is_empty():
		return "Follow the road"
	var t := str(next_turn["turn"])
	if t == "arrive":
		return "Arrive at your destination"
	var words := {"left": "Turn left", "right": "Turn right", "slight_left": "Bear left", "slight_right": "Bear right",
		"sharp_left": "Sharp left", "sharp_right": "Sharp right"}
	var text: String = words.get(t, "Continue")
	var onto := str(next_turn.get("onto", ""))
	return text + (" onto " + onto if onto != "" else "")


## The arrow to draw, as degrees clockwise from straight ahead: 0 for straight on, 90 for a right turn.
func arrow_degrees() -> float:
	if off_route:
		return 0.0
	var t := str(next_turn.get("turn", "straight"))
	var sign := -1.0 if t.ends_with("left") else 1.0
	if t.begins_with("slight"):
		return 40.0 * sign
	if t.begins_with("sharp"):
		return 140.0 * sign
	if t == "left" or t == "right":
		return 90.0 * sign
	return 0.0


## Distance as a rider reads it: "350 m", "1.2 km".
static func distance_text(metres: float) -> String:
	if metres < 950.0:
		return "%d m" % (roundi(metres / 10.0) * 10 if metres >= 100.0 else roundi(metres / 5.0) * 5)
	return "%.1f km" % (metres / 1000.0)
