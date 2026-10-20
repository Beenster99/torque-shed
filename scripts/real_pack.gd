class_name RealPack
extends RefCounted
## A real road baked by tools/route_bake.py, ridden as an adventure (see AdventureRoute.plan_real): the road as
## knots every 4 m with its height, per 128 m chunk its surface, width, class and name, the turn-by-turn
## instructions, and the land beside it (RealTerrain). A pack is a folder under data/routes/ holding pack.json,
## route.json and tiles/. Everything is in the adventure's route frame: metres from the start, +x east, -z north.
## Packs are read-only once loaded, so one can be shared by every thread.

const FORMAT := 4
## What covers the land (RealTerrain.cover), by id: the baker's list (tools/land_bake.py COVER).
const COVER: Array[String] = ["grass", "forest", "crop", "shrub", "barren", "urban", "sand", "wetland", "water", "rock"]
## The kinds of building (tools/land_bake.py BUILDING_KINDS), by id.
const BUILDING_KINDS: Array[String] = ["house", "shed", "barn", "shop", "block", "industrial", "worship", "civic"]
const DIR := "res://data/routes"

static var _cache := {}
static var _cache_lock := Mutex.new()

var id := ""
var title := ""
## A short hash of the whole pack's data, the same on every machine that has it: co-op checks it matches.
var hash := ""
var credits: Array = []
## The theme the adventure is dressed as ("coastal" where there is sea, else "hills").
var theme := "hills"
var sea := false
## The baked road's length (m), including the run-out past the longest ride it offers.
var length_m := 0.0
var run_out_m := 600.0
var step := 4.0
var x := PackedFloat64Array()
var z := PackedFloat64Array()
## Height of the road's surface at each knot, metres above sea level (graded, see the baker).
var e := PackedFloat32Array()
## Per 128 m chunk: [surface, width, class, name index].
var chunks: Array = []
var names: Array = []
## [{d, x, z, turn, onto, branches}] and a last {"turn": "arrive"}.
var turns: Array = []
var terrain: RealTerrain
## The buildings beside the road, by the 128 m chunk of the nearest road knot: chunk -> [[x, z, w, d, yaw, h, kind, knot]].
var buildings := {}
var building_count := 0
## Named peaks, lighthouses and the like: [{kind, name, x, z}].
var landmarks: Array = []


## The ids of the packs the game has.
static func list() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for name in d.get_directories():
		if FileAccess.file_exists(DIR.path_join(name).path_join("pack.json")):
			out.append(name)
	out.sort()
	return out


## The pack `pack_id` (read once, then shared), or null with the reason in the log.
static func get_pack(pack_id: String) -> RealPack:
	_cache_lock.lock()
	if _cache.has(pack_id):
		var got: RealPack = _cache[pack_id]
		_cache_lock.unlock()
		return got
	_cache_lock.unlock()
	var pack := _load(pack_id)
	_cache_lock.lock()
	_cache[pack_id] = pack
	_cache_lock.unlock()
	return pack


static func _load(pack_id: String) -> RealPack:
	var dir := DIR.path_join(pack_id)
	var meta = _json(dir.path_join("pack.json"))
	if not meta is Dictionary:
		if FileAccess.file_exists(dir.path_join("pack.json")):
			push_error("Real road: no readable pack.json in %s" % dir)
		return null
	if int(meta.get("format", 0)) != FORMAT:
		push_error("Real road: %s is format %s, this game reads %d" % [dir, meta.get("format"), FORMAT])
		return null
	var route = _json(dir.path_join("route.json"))
	if not route is Dictionary or not route.get("x") is Array or (route["x"] as Array).size() < 10:
		push_error("Real road: no readable route.json in %s" % dir)
		return null
	var p := RealPack.new()
	p.id = pack_id
	p.title = str(meta.get("title", pack_id))
	p.hash = str(meta.get("hash", ""))
	p.credits = meta.get("credits", [])
	p.theme = str(meta.get("theme", "hills"))
	p.sea = bool(meta.get("sea", false))
	p.length_m = float(meta.get("length_m", 0.0))
	p.run_out_m = float(meta.get("run_out_m", 600.0))
	p.step = float(route.get("step", 4.0))
	var n := int(route["n"])
	p.x.resize(n)
	p.z.resize(n)
	p.e.resize(n)
	var xs: Array = route["x"]
	var zs: Array = route["z"]
	var es: Array = route["e"]
	for i in n:
		p.x[i] = float(xs[i])
		p.z[i] = float(zs[i])
		p.e[i] = float(es[i])
	p.chunks = route["chunks"]
	p.names = route["names"]
	p.turns = route.get("turns", [])
	var knots_per_chunk := int(128.0 / p.step)
	var rows = _json(dir.path_join("buildings.json"))
	if rows is Array:
		for b: Array in rows:
			var c := int(b[7]) / knots_per_chunk
			if not p.buildings.has(c):
				p.buildings[c] = []
			(p.buildings[c] as Array).append(b)
		p.building_count = (rows as Array).size()
	var marks = _json(dir.path_join("landmarks.json"))
	if marks is Array:
		p.landmarks = marks
	p.terrain = RealTerrain.new(dir.path_join("tiles"), meta)
	return p


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The buildings whose nearest road knot is in chunk `c` ([[x, z, w, d, yaw, h, kind, knot]], route frame), or [].
func buildings_in(c: int) -> Array:
	return buildings.get(c, [])


## The landmarks of `kind` ("" for all) within `reach` metres of route-frame (x, z).
func landmarks_near(x: float, z: float, reach: float, kind := "") -> Array:
	return landmarks.filter(func(m): return (kind == "" or m["kind"] == kind) and Vector2(float(m["x"]) - x, float(m["z"]) - z).length() <= reach)


## The longest ride (km) this pack offers: what is baked less the run-out.
func max_km() -> float:
	return maxf((length_m - run_out_m) / 1000.0, 0.0)


## The name of the road at `s` metres along it.
func name_at(s: float) -> String:
	var c := clampi(int(s / 128.0), 0, chunks.size() - 1)
	return str(names[int((chunks[c] as Array)[3])]) if c >= 0 and not chunks.is_empty() else ""


## The next instruction that is a turn (not going straight on) after `s` metres, or {}.
func next_turn(s: float) -> Dictionary:
	for t: Dictionary in turns:
		if float(t["d"]) > s and str(t["turn"]) != "straight":
			return t
	return {}
