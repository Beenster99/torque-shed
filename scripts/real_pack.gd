class_name RealPack
extends RefCounted
## A real road planned across a region by RoutePlanner from the crew's pins, ridden as an adventure (see
## AdventureRoute.plan_real): the road as knots every 4 m with its height, per 128 m chunk its surface, width, class
## and name, the turn-by-turn instructions, and the land beside it (RealTerrain). Everything is in the adventure's
## route frame: metres from the start, +x east, -z north. Packs are read-only once planned, so one can be shared by
## every thread.

## What covers the land (RealTerrain.cover), by id: the baker's list (tools/land_bake.py COVER).
const COVER: Array[String] = ["grass", "forest", "crop", "shrub", "barren", "urban", "sand", "wetland", "water", "rock"]
## The kinds of building (tools/land_bake.py BUILDING_KINDS), by id.
const BUILDING_KINDS: Array[String] = ["house", "shed", "barn", "shop", "block", "industrial", "worship", "civic"]

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
## The planned road's length (m), including the run-out past the last pin.
var length_m := 0.0
var run_out_m := 600.0
var step := 4.0
var x := PackedFloat64Array()
var z := PackedFloat64Array()
## Height of the road's surface at each knot, metres above sea level (graded, see the baker).
var e := PackedFloat32Array()
## The road's bridges, as knot ranges: [first knot, last knot, ...] (RoutePlanner.bridges_along). Their heights run
## straight from end to end, over the land rather than on a bank of it.
var bridges := PackedInt32Array()
## Per 128 m chunk: [surface, width, class, name index, speed limit (km/h)].
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
## Where side roads join the road: [{k (the nearest knot), type ("tee", "cross", "roundabout", "mini"), arms: [{side (1
## the right), skew (degrees off square), cls, name, w, surf}], ri, ro (a roundabout's island and outer radius)}].
var junctions: Array = []
## Real places beside the road to stop at: [{kind ("fuel", "cafe", "pub", "inn", "campsite", "layby", "viewpoint"),
## name ("" when it has none we can print), x, z, k (the nearest knot), lat (m to the right of the road), conf}].
var pois: Array = []
## Second ways between two junctions of the road, for the crew to vote on: [{i0, i1 (knots of the main road, on chunk
## boundaries), kinds ("main" then "scenic" or "gravel"), names {kind: name}, way: {n, x, z, e, chunks: [[surface, width,
## class, name, limit]]}}], in order along the road.
var forks: Array = []
var fork_count := 0
## What the data says about the road: {from, to (the issue's words), roads (the named roads it follows, longest first),
## climb_m, top_m, low_m}.
var summary := {}
## The country's speed-limit rules the baker used ("uk", "jp" or "world").
var region := "world"


## The planned pack `pack_id` (see register), or null when this game hasn't planned it.
static func get_pack(pack_id: String) -> RealPack:
	_cache_lock.lock()
	var got: RealPack = _cache.get(pack_id)
	_cache_lock.unlock()
	return got


## Makes a pack planned in the game (RoutePlanner) available by its id: get_pack finds it.
static func register(pack: RealPack) -> void:
	_cache_lock.lock()
	_cache[pack.id] = pack
	_cache_lock.unlock()


## The speed limit (km/h) at `s` metres along the road.
func limit_at(s: float) -> float:
	if chunks.is_empty():
		return 0.0
	var row: Array = chunks[clampi(int(s / 128.0), 0, chunks.size() - 1)]
	return float(row[4]) if row.size() > 4 else 0.0


## The places of `kind` beside the road, nearest the road first.
func pois_of(kind: String) -> Array:
	return pois.filter(func(q): return q["kind"] == kind)


## The buildings whose nearest road knot is in chunk `c` ([[x, z, w, d, yaw, h, kind, knot]], route frame), or [].
func buildings_in(c: int) -> Array:
	return buildings.get(c, [])


## The landmarks of `kind` ("" for all) within `reach` metres of route-frame (x, z).
func landmarks_near(x: float, z: float, reach: float, kind := "") -> Array:
	return landmarks.filter(func(m): return (kind == "" or m["kind"] == kind) and Vector2(float(m["x"]) - x, float(m["z"]) - z).length() <= reach)


## A few lines for the magazine, from the data: how far, along which roads, how much climbing, and what's on the way.
func summary_text() -> String:
	var km := floori(max_km())
	var lines: PackedStringArray = []
	var from := str(summary.get("from", ""))
	var to := str(summary.get("to", ""))
	var head := "%d km" % km if from == "" or to == "" else "%d km from %s to %s" % [km, from, to]
	var roads: Array = summary.get("roads", [])
	if not roads.is_empty():
		head += ", along the " + (", ".join(roads.slice(0, -1)) + " and " + str(roads[-1]) if roads.size() > 1 else str(roads[0]))
	lines.append(head + ".")
	if int(summary.get("climb_m", 0)) > 0:
		lines.append("%d metres of climbing, between %d and %d metres above the sea." % [int(summary["climb_m"]), int(summary["low_m"]), int(summary["top_m"])])
	var stops: PackedStringArray = []
	for kind in ["fuel", "cafe", "inn"]:
		var n := pois_of(kind).size()
		if n > 0:
			stops.append("%d %s" % [n, {"fuel": "filling stations", "cafe": "cafes", "inn": "inns and hotels"}[kind]])
	if not stops.is_empty():
		lines.append("Real places beside the road: " + ", ".join(stops) + ".")
	return " ".join(lines)


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
