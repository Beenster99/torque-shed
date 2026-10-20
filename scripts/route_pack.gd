class_name RoutePack
extends RefCounted
## One leg of a baked real-world route (see RouteJourney and tools/route_bake.py): the heights, roads and
## buildings of a 4 km square of a real place, in the riding map's own frame (+x east, -z north, metres,
## the middle of the square at the origin). When WorldLayout.pack is set the map is made from it instead of
## from noise and the hand-laid layout: WorldTerrain takes its heights from `heights`, WorldRoads lays
## `roads` (after the shed's own loop in the first leg), and WorldProps stands `buildings` on the land.

const FORMAT := 2

var name := ""
## A short hash of the whole route's data, so every player can check they have the same route.
var id := ""
## This leg's number in the journey.
var index := 0
## Heights in metres in the leg's own frame, WorldTerrain.SIZE x WorldTerrain.SIZE, row by row (z then x).
var heights := PackedFloat32Array()
## Road definitions in WorldLayout.ROADS's shape (the loop is not in here; the shed has its own).
var roads: Array = []
## Footprints: [{x, z, w, d, yaw, h, kind}] with kind "house", "shed" or "barn".
var buildings: Array = []
## Where the sea's surface is in the heights' frame, or NAN when this leg has no sea.
var sea_level := NAN
## How far above real sea level the heights' zero is, so the ground's real height is `h + base_elev`.
var base_elev := 0.0
## The first leg has the shed at its origin; the rest are open country.
var shed := false
## Where this leg's origin is in the whole route's frame, in metres.
var origin := Vector2.ZERO


## Reads leg `index` of the route in `dir` (`leg` is its entry in pack.json), or returns null with the
## reason in the log.
static func load_leg(dir: String, leg: Dictionary, index: int, route_id: String, route_name: String) -> RoutePack:
	var d := dir.path_join(str(leg["dir"]))
	var raw := FileAccess.get_file_as_bytes(d.path_join("heights.u16"))
	var n := WorldTerrain.SIZE * WorldTerrain.SIZE
	if raw.size() != n * 2:
		push_error("Route pack: %s/heights.u16 is %d bytes, expected %d" % [d, raw.size(), n * 2])
		return null
	var defs = _json(d.path_join("roads.json"))
	var houses = _json(d.path_join("buildings.json"))
	if not defs is Array or not houses is Array:
		push_error("Route pack: no readable roads.json or buildings.json in %s" % d)
		return null
	var p := RoutePack.new()
	p.name = route_name
	p.id = route_id
	p.index = index
	var lo := float(leg["height"]["min"])
	var scale := float(leg["height"]["scale"])
	p.heights.resize(n)
	for i in n:
		p.heights[i] = lo + raw.decode_u16(i * 2) * scale
	for def in defs:
		p.roads.append(_road_def(def))
	p.buildings = houses
	p.sea_level = float(leg["sea_level"]) if leg.get("sea_level") != null else NAN
	p.base_elev = float(leg.get("base_elev", 0.0))
	p.shed = bool(leg.get("shed", false))
	var o: Array = leg.get("origin", [0.0, 0.0])
	p.origin = Vector2(float(o[0]), float(o[1]))
	return p


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## A road definition read from JSON, with its points as a Packed array (what WorldRoads wants).
static func _road_def(d: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	for q in d["pts"]:
		pts.append(Vector2(float(q[0]), float(q[1])))
	var out := d.duplicate()
	out["pts"] = pts
	return out


## The land's height at (x, z) in metres, from the grid (bilinear), clamped to its edge.
func height_at(x: float, z: float) -> float:
	var size := WorldTerrain.SIZE
	var fx := clampf((x + WorldTerrain.HALF) / WorldTerrain.SPACING, 0.0, size - 1.001)
	var fz := clampf((z + WorldTerrain.HALF) / WorldTerrain.SPACING, 0.0, size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * size + ix
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + size], heights[i + size + 1], tx), tz)
