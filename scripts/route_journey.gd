class_name RouteJourney
extends RefCounted
## A baked real-world route (tools/route_bake.py): a long road across real land, made of 4 km legs the
## game swaps between as you ride, with the planned route line and its turn-by-turn instructions for the
## satnav (see RouteGuide). A journey is a folder: pack.json, route.json and legs/legNN/.
##
## Everything here is in the route's own frame (metres, +x east, -z north); a leg's local map coordinates
## plus its origin are route coordinates.

const FORMAT := 2

var dir := ""
var name := ""
var title := ""
## A short hash of the data, the same on every machine that has this route.
var id := ""
var credits: Array = []
var legs: Array = []          # each leg's entry in pack.json
## The planned route's line and the distance along it of each point, from the shed's loop.
var points := PackedVector2Array()
var dists := PackedFloat32Array()
var length_m := 0.0
## [{d, x, z, turn, onto, branches}] and the final "arrive".
var turns: Array = []
var requested_km := 0.0


## Reads the route in folder `dir`, or returns null with the reason in the log.
static func load_journey(dir: String) -> RouteJourney:
	var meta = RoutePack._json(dir.path_join("pack.json"))
	if not meta is Dictionary:
		push_error("Route: no readable pack.json in %s" % dir)
		return null
	if int(meta.get("format", 0)) != FORMAT:
		push_error("Route: %s is format %s, this game reads %d" % [dir, meta.get("format"), FORMAT])
		return null
	var grid: Dictionary = meta.get("grid", {})
	if int(grid.get("size", 0)) != WorldTerrain.SIZE or not is_equal_approx(float(grid.get("spacing", 0.0)), WorldTerrain.SPACING):
		push_error("Route: %s has a %s grid, the map needs %d samples %g m apart" % [dir, grid, WorldTerrain.SIZE, WorldTerrain.SPACING])
		return null
	var route = RoutePack._json(dir.path_join("route.json"))
	if not route is Dictionary or not meta.get("legs") is Array or (meta["legs"] as Array).is_empty():
		push_error("Route: %s has no readable route.json or legs" % dir)
		return null
	var j := RouteJourney.new()
	j.dir = dir
	j.name = str(meta.get("name", ""))
	j.title = str(meta.get("title", j.name))
	j.id = str(meta.get("hash", j.name))
	j.credits = meta.get("credits", [])
	j.legs = meta["legs"]
	j.length_m = float(route.get("length_m", 0.0))
	j.requested_km = float(meta.get("route", {}).get("requested_km", 0.0) if meta.get("route", {}).get("requested_km") != null else 0.0)
	var d := 0.0
	var prev := Vector2.ZERO
	for i in (route["points"] as Array).size():
		var q: Array = route["points"][i]
		var v := Vector2(float(q[0]), float(q[1]))
		if i > 0:
			d += prev.distance_to(v)
		j.points.append(v)
		j.dists.append(d)
		prev = v
	j.turns = route.get("turns", [])
	return j


func leg_count() -> int:
	return legs.size()


## Leg `i` of the route, loaded from its files (a second or so), or null.
func load_leg(i: int) -> RoutePack:
	if i < 0 or i >= legs.size():
		return null
	return RoutePack.load_leg(dir, legs[i], i, id, name)


## Where leg `i`'s origin is in route coordinates.
func origin_of(i: int) -> Vector2:
	var o: Array = legs[i]["origin"]
	return Vector2(float(o[0]), float(o[1]))


## The shift that turns a position in leg `i`'s frame into one in leg `i + 1`'s.
func shift_to_next(i: int) -> Vector2:
	var s = legs[i].get("to_next")
	return Vector2(float(s[0]), float(s[1])) if s is Array else Vector2.ZERO


## How far along the route you must be for leg `i` to hand over to the next, or -1 for the last leg.
func hand_over_at(i: int) -> float:
	var h = legs[i].get("hand_over_d")
	return float(h) if h != null else -1.0


## Which leg should be loaded when you are `d` metres along the route.
func leg_for_distance(d: float) -> int:
	for i in legs.size() - 1:
		if d < hand_over_at(i):
			return i
	return legs.size() - 1


## Where `p` (route coordinates) is on the route line: {d: metres along it, off: how far from it, i: the
## index of the nearest segment's start, at: the nearest point on the line}. `hint` is the index you were
## last at, searched first and either side.
func progress(p: Vector2, hint := 0, reach := 60) -> Dictionary:
	if points.size() < 2:
		return {"d": 0.0, "off": INF, "i": 0, "at": p}
	var found := _nearest_segment(p, maxi(hint - reach, 0), mini(hint + reach, points.size() - 2))
	# Lost: nothing near the hint, so look along the whole route.
	if float(found["off"]) > 150.0:
		found = _nearest_segment(p, 0, points.size() - 2)
	return found


func _nearest_segment(p: Vector2, lo: int, hi: int) -> Dictionary:
	var best := {"d": 0.0, "off": INF, "i": lo, "at": p}
	for i in range(lo, hi + 1):
		var a := points[i]
		var seg := points[i + 1] - a
		var len2 := seg.length_squared()
		var t := clampf((p - a).dot(seg) / len2, 0.0, 1.0) if len2 > 0.0001 else 0.0
		var q := a + seg * t
		var off := q.distance_to(p)
		if off < float(best["off"]):
			best = {"d": lerpf(dists[i], dists[i + 1], t), "off": off, "i": i, "at": q}
	return best
