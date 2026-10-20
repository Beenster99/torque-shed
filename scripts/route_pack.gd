class_name RoutePack
extends RefCounted
## A real-world route baked by tools/route_bake.py: the land's heights and the roads of a stretch of a
## real place, in the riding map's own frame (+x east, -z north, the shed at the origin). When
## WorldLayout.pack is set the map is made from it instead of from noise and the hand-laid layout:
## WorldTerrain takes its heights from `heights`, and WorldRoads lays `roads` after the shed's own loop.
## A pack is a folder: pack.json (details), heights.u16 and roads.json.

const FORMAT := 1

var name := ""
var title := ""
## A short hash of the data, so every player can check they have the same route.
var id := ""
## Heights in metres over the start point, WorldTerrain.SIZE x WorldTerrain.SIZE, row by row (z then x).
var heights := PackedFloat32Array()
## Road definitions in WorldLayout.ROADS's shape (the loop is not in here; the shed has its own).
var roads: Array = []
## Where the route starts and where it ends, in map metres (end is Vector2.INF when it has none).
var start := Vector2.ZERO
var end := Vector2.INF
## Who to thank for the data, one line each.
var credits: Array = []


## Reads the pack in folder `dir`, or returns null (and says why in the log) if it can't be used.
static func load_pack(dir: String) -> RoutePack:
	var meta = null
	if FileAccess.file_exists(dir.path_join("pack.json")):
		meta = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pack.json")))
	if not meta is Dictionary:
		push_error("Route pack: no readable pack.json in %s" % dir)
		return null
	if int(meta.get("format", 0)) != FORMAT:
		push_error("Route pack: %s is format %s, this game reads %d" % [dir, meta.get("format"), FORMAT])
		return null
	var grid: Dictionary = meta.get("grid", {})
	if int(grid.get("size", 0)) != WorldTerrain.SIZE or not is_equal_approx(float(grid.get("spacing", 0.0)), WorldTerrain.SPACING):
		push_error("Route pack: %s has a %s grid, the map needs %d samples %g m apart" % [dir, grid, WorldTerrain.SIZE, WorldTerrain.SPACING])
		return null
	var raw := FileAccess.get_file_as_bytes(dir.path_join("heights.u16"))
	var n := WorldTerrain.SIZE * WorldTerrain.SIZE
	if raw.size() != n * 2:
		push_error("Route pack: heights.u16 in %s is %d bytes, expected %d" % [dir, raw.size(), n * 2])
		return null
	var defs = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("roads.json")))
	if not defs is Array:
		push_error("Route pack: no readable roads.json in %s" % dir)
		return null
	var p := RoutePack.new()
	p.name = str(meta.get("name", ""))
	p.title = str(meta.get("title", p.name))
	p.id = str(meta.get("hash", p.name))
	var lo := float(meta["height"]["min"])
	var scale := float(meta["height"]["scale"])
	p.heights.resize(n)
	for i in n:
		p.heights[i] = lo + raw.decode_u16(i * 2) * scale
	for d in defs:
		p.roads.append(_road_def(d))
	var s: Array = meta.get("start_world", [0.0, 0.0])
	p.start = Vector2(float(s[0]), float(s[1]))
	if meta.get("end_world") is Array:
		p.end = Vector2(float(meta["end_world"][0]), float(meta["end_world"][1]))
	p.credits = meta.get("credits", [])
	return p


## A road definition read from JSON, with its points as a Packed array (what WorldRoads wants).
static func _road_def(d: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	for q in d["pts"]:
		pts.append(Vector2(float(q[0]), float(q[1])))
	var out := d.duplicate()
	out["pts"] = pts
	return out


## The land's height at (x, z) in metres over the start point, from the grid (bilinear), clamped to its edge.
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
