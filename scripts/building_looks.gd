class_name BuildingLooks
extends RefCounted
## What the map says a ride's buildings look like (phase D round 2, D6): their roofs' shape and colour, what their
## walls are made of, and what they are (a church, a mosque, a hangar, a trullo), from the features' "buildings"
## (tools/feature_bake.py, RealRegion.add_features), matched to RealRegion.buildings' rows by where they stand. The
## regional kit still decides how a building is drawn; where the map says something, that wins, so a town's roofs are
## its own. Where it says nothing a building is drawn as it always was (no look at all: `of` gives {}).
##
## Nothing here changes where a building stands or what a road does: it only colours and shapes what RoadBlock already
## draws. Its VERSION is folded into History's (scripts/scenery/history.gd), which is in the builder hash.

## Bumped when what a look does to a building changes (History.VERSION goes up with it).
const VERSION := 1
## The looks are filed in squares this size (m).
const GRID := 24.0
## A look stands for a building when its middle is inside the building's box grown by this much (m).
const MARGIN := 1.5
## How far a mapped colour is weathered towards its own grey (colour).
const WEATHER := 0.35

## The map's roof shapes as the kits' roof forms (RegionBuildings._roof).
const SHAPES := {"gabled": "gable", "hipped": "hip", "half_hipped": "hip", "side_hipped": "hip", "pyramidal": "hip",
	"flat": "flat", "skillion": "tin", "lean_to": "tin", "gambrel": "gable", "mansard": "hip", "saltbox": "gable",
	"quadruple_saltbox": "hip", "round": "tin", "sawtooth": "tin", "butterfly": "tin", "dome": "dome",
	"spherical": "dome", "onion": "onion", "cone": "cone", "conical": "cone"}
## A roof's colour by what it's made of, where the map gives no colour.
const ROOF_MATERIALS := {"slate": "#41454b", "roof_tiles": "#a24a32", "tiles": "#a24a32", "tile": "#a24a32",
	"metal": "#8a8e90", "tin": "#8a8e90", "copper": "#4f8a72", "zinc": "#9aa0a4", "thatch": "#a08850",
	"tar_paper": "#2a2a2c", "asphalt": "#2e2e30", "concrete": "#9a9890", "stone": "#7a7468", "wood": "#6a4a32",
	"grass": "#4a6a32", "glass": "#8ab0c0", "asbestos": "#a8a8a0", "eternit": "#8a8a84", "plastic": "#c8c8c0",
	"gravel": "#8a867c"}
## A wall's colour by what it's made of, where the map gives no colour.
const FACADE_MATERIALS := {"brick": "#8c4a36", "stone": "#a49a87", "plaster": "#e4dcc8", "wood": "#8a6a48",
	"glass": "#7a98a8", "concrete": "#b0aca4", "metal": "#9a9ea0", "cement_block": "#a8a49c", "clay": "#b0784a",
	"timber_framing": "#e8e0cc", "sandstone": "#c8a878", "limestone": "#d8d0bc", "granite": "#8a8680",
	"mud": "#a8784a", "adobe": "#b8885a", "plastic": "#e0e0d8", "render": "#e4dcc8"}

static var _index := {}     # region instance id -> {"grid": {Vector2i: [index]}, "rows": Array}
static var _lock := Mutex.new()


## The look of RealRegion.buildings row `row` ([x, z, w, d, yaw, ...] in `region`'s frame): {class, roof (a kit roof
## form), roof_colour, wall_colour (Colors), timber (bool), lat (degrees north, for choosing a style)}, only the keys the
## map gives, or {} where it says nothing. Safe on a worker.
static func of(region: RealRegion, row: Array) -> Dictionary:
	if region == null or not region.features.has("buildings"):
		return {}
	var idx := _index_of(region)
	var bx := float(row[0])
	var bz := float(row[1])
	var w := float(row[2])
	var d := float(row[3])
	var yaw := float(row[4])
	var reach := Vector2(w, d).length() * 0.5 + MARGIN
	var rows: Array = idx["rows"]
	var best := -1
	var best_d := INF
	var c := Vector2i(floori(bx / GRID), floori(bz / GRID))
	var span := ceili(reach / GRID)
	for gx in range(c.x - span, c.x + span + 1):
		for gz in range(c.y - span, c.y + span + 1):
			for i: int in (idx["grid"] as Dictionary).get(Vector2i(gx, gz), []):
				var r: Array = rows[i]
				var dx := float(r[0]) - bx
				var dz := float(r[1]) - bz
				# (in the building's own frame, as RoadBlock._corners lays its box out)
				var u := dx * cos(yaw) - dz * sin(yaw)
				var v := dx * sin(yaw) + dz * cos(yaw)
				if absf(u) > w * 0.5 + MARGIN or absf(v) > d * 0.5 + MARGIN:
					continue
				var dist := dx * dx + dz * dz
				if dist < best_d:
					best_d = dist
					best = i
	if best < 0:
		return {}
	return look_of(rows[best], RealRegion.from_frame(Vector2(region.frame_lat, region.frame_lon), bx, bz).x)


## A features "buildings" row ([x, z, class, roof_shape, roof_color, roof_material, facade_material, facade_color]) as
## a look (see `of`), at latitude `lat`.
static func look_of(r: Array, lat := 0.0) -> Dictionary:
	var out := {"lat": lat}
	var cls := str(r[2])
	if cls != "":
		out["class"] = cls
	var shape := str(r[3]).to_lower()
	if SHAPES.has(shape):
		out["roof"] = SHAPES[shape]
	var rc = colour(str(r[4]))
	if rc == null:
		rc = colour(str(ROOF_MATERIALS.get(str(r[5]).to_lower(), "")))
	if rc != null:
		out["roof_colour"] = rc
	var material := str(r[6]).to_lower()
	var wc = colour(str(r[7]))
	if wc == null:
		wc = colour(str(FACADE_MATERIALS.get(material, "")))
	if wc != null:
		out["wall_colour"] = wc
	if material == "timber_framing":
		out["timber"] = true
	return out if out.size() > 1 else {}


## A map colour ("#778899", "#789", "red") as a Color, or null: a third of the way to its own grey and a touch darker,
## as paint and slate weather (the map's colours are names picked from a short list, brighter than the real thing).
static func colour(text: String):
	if text == "":
		return null
	var c := Color.from_string(text, Color(-1, -1, -1))
	if c.r < 0.0:
		return null
	var grey := c.get_luminance()
	return Color(c.r, c.g, c.b).lerp(Color(grey, grey, grey), WEATHER).darkened(0.08)


## Kit `kit` (a RegionKit) with building look `look` laid over it: its roof form and colours, its walls' colours, so
## RegionBuildings draws the building as the map says and the kit's way for the rest.
static func dress_kit(kit: Dictionary, look: Dictionary) -> Dictionary:
	if look.is_empty():
		return kit
	var out := kit.duplicate()
	if look.has("roof"):
		var form := str(look["roof"])
		out["roof"] = "hip" if form in ["dome", "onion", "cone"] else form
		out["flat"] = 1.0 if form == "flat" else 0.0
		if form != "flat" and float(out.get("pitch", 0.0)) < 0.2:
			out["pitch"] = 0.45   # (a pitched roof the map gives, in a flat-roofed kit)
	if look.has("roof_colour"):
		out["roofs"] = [look["roof_colour"]]
	if look.has("wall_colour"):
		out["walls"] = [look["wall_colour"]]
		out["barn"] = [look["wall_colour"]]
	if bool(look.get("timber", false)) and not (out.get("timber") is Color):
		out["timber"] = Color(0.36, 0.25, 0.17)
	return out


## The looks of `region`, filed in GRID squares: worked out once a region, under a lock (the road blocks' workers ask).
static func _index_of(region: RealRegion) -> Dictionary:
	var id := region.get_instance_id()
	_lock.lock()
	var got = _index.get(id)
	if got == null or got["n"] != (region.features["buildings"] as Array).size():
		if _index.size() > 4:
			_index.clear()   # (rides come and go: keep only the last few regions')
		var grid := {}
		var rows: Array = region.features["buildings"]
		for i in rows.size():
			var k := Vector2i(floori(float(rows[i][0]) / GRID), floori(float(rows[i][1]) / GRID))
			if not grid.has(k):
				grid[k] = []
			(grid[k] as Array).append(i)
		got = {"grid": grid, "rows": rows, "n": rows.size()}
		_index[id] = got
	_lock.unlock()
	return got
