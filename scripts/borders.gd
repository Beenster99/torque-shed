class_name Borders
extends RefCounted
## The country borders running through a cell (Ride Anywhere v2, phase D round 3, D8): which country a point is in
## where a cell holds more than one, from the cell's features (tools/feature_bake.py names each "country_border" line
## "LEFT|RIGHT", the countries to its left and right facing along it). RegionKit.at_frame asks it, so the regional kit,
## the signs, the road paint and the side of the road switch at the border line itself rather than at a cell's edge.
##
## A cell with no named border (most of them, and every cell baked before the borders were named) answers "", and the
## cell's own country stands, as it always has. The answers are kept on a GRID-metre lattice, so the traffic asking many
## times a tick costs a dictionary lookup. Safe from any thread.

## Part of what the game builds (its kit by place): bump it when the answer for a point changes.
const VERSION := 1
## The lattice the answers are kept on (m), and at most this many kept a cell before they are dropped and begun again.
const GRID := 16.0
const KEPT_MOST := 200000

static var _lock := Mutex.new()
## "ROW_COL" -> {lines: [[PackedVector2Array (m east, north of the cell's middle), left, right]], memo: {Vector2i: code}}
## or {} for a cell with no named border.
static var _cells := {}
## Features given by hand ("ROW_COL" -> a cell's features file), before any on disk: the tests' and the places rigs'.
static var given := {}


## The country (ISO code) at (lat, lon) when the cell it's in has a named border, else "": the side of the nearest
## border line it is on.
static func country_at(lat: float, lon: float) -> String:
	var cell := RealRegion.cell_of(lat, lon)
	return country_in("%d_%d" % [cell.x, cell.y], cell, lat, lon)


## As country_at, for a point in cell `cell` ("ROW_COL" `key`), already known.
static func country_in(key: String, cell: Vector2i, lat: float, lon: float) -> String:
	var c := _cell(key, cell)
	if c.is_empty():
		return ""
	var mid := RealRegion.cell_middle(cell)
	var m := RealTerrain.metres_per_degree(mid.x)
	var p := Vector2((lon - mid.y) * m.y, (lat - mid.x) * m.x)
	var q := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	_lock.lock()
	var have = (c["memo"] as Dictionary).get(q)
	_lock.unlock()
	if have != null:
		return have
	var got := side_country(c["lines"], (Vector2(q) + Vector2(0.5, 0.5)) * GRID)
	_lock.lock()
	if (c["memo"] as Dictionary).size() > KEPT_MOST:
		(c["memo"] as Dictionary).clear()
	c["memo"][q] = got
	_lock.unlock()
	return got


## The country on the side of the nearest of `lines` ([[PackedVector2Array, left, right]]) point `p` is on ("" when the
## map didn't say). At a bend the side is the corner's: inside a corner turning left a point is left of both its lines,
## outside it, of either.
static func side_country(lines: Array, p: Vector2) -> String:
	var best := INF
	var code := ""
	for ln: Array in lines:
		var pts: PackedVector2Array = ln[0]
		for i in pts.size() - 1:
			var a := pts[i]
			var ab := pts[i + 1] - a
			var l2 := ab.length_squared()
			if l2 < 1e-6:
				continue
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_squared_to(a + ab * t)
			if d >= best:
				continue
			best = d
			var left := ab.cross(p - a) > 0.0   # (x east, y north: the left is anticlockwise)
			# (at a joint, the corner's side: its neighbour's line counts too)
			var j := -1
			if t <= 0.0 and i > 0:
				j = i - 1
			elif t >= 1.0 and i + 2 < pts.size():
				j = i + 1
			if j >= 0:
				var cd := pts[j + 1] - pts[j]
				var left_too := cd.cross(p - pts[j]) > 0.0
				var first := cd if j < i else ab
				var second := ab if j < i else cd
				var turns_left := first.cross(second) > 0.0
				left = (left and left_too) if turns_left else (left or left_too)
			code = str(ln[1]) if left else str(ln[2])
	return code


## The named country borders of a cell, parsed once.
static func _cell(key: String, cell: Vector2i) -> Dictionary:
	_lock.lock()
	var have = _cells.get(key)
	_lock.unlock()
	if have is Dictionary:
		return have
	var lines := lines_of(_features(key), RealRegion.cell_middle(cell))
	var c := {} if lines.is_empty() else {"lines": lines, "memo": {}}
	_lock.lock()
	_cells[key] = c
	_lock.unlock()
	return c


## A features file's named country borders, in metres east and north of `mid` (lat, lon): [[points, left, right]].
static func lines_of(f: Dictionary, mid: Vector2) -> Array:
	var out: Array = []
	var kinds: Array = f.get("kinds", [])
	var names: Array = f.get("names", [])
	var at := kinds.find("country_border")
	if at < 0:
		return out
	var m := RealTerrain.metres_per_degree(mid.x)
	for row: Array in f.get("lines", []):
		if int(row[0]) != at or row.size() < 10:
			continue
		var nm := str(names[int(row[4])]) if int(row[4]) < names.size() else ""
		var sides := nm.split("|")
		if sides.size() != 2 or (sides[0] == "" and sides[1] == ""):
			continue
		var pts := PackedVector2Array()
		var lat := 0.0
		var lon := 0.0
		for i in range(6, row.size() - 1, 2):
			lat += float(row[i])
			lon += float(row[i + 1])
			pts.append(Vector2((lon * 1e-5 - mid.y) * m.y, (lat * 1e-5 - mid.x) * m.x))
		if pts.size() >= 2:
			out.append([pts, sides[0], sides[1]])
	return out


## A cell's features: those given, else the copy CellStore keeps on disk ({} when there's none: never fetched here).
static func _features(key: String) -> Dictionary:
	_lock.lock()
	var g = given.get(key)
	_lock.unlock()
	if g is Dictionary:
		return g
	var path := CellStore.dir.path_join("feature").path_join("c%s.json" % key)
	if not FileAccess.file_exists(path):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


## Forgets every cell's borders (the tests change the features given).
static func forget() -> void:
	_lock.lock()
	_cells = {}
	_lock.unlock()
