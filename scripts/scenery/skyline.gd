class_name Skyline
extends RefCounted
## Phase D round 1, the skyline (interfaces/scenery.md): the things seen from miles off, placed wherever the map has
## them, in every country. Wind turbines at their real spots with blades turning in step with the weather's wind and red
## lamps at night; pylons, poles and the wires sagging between them along the power lines; substations and power
## stations as fenced yards; cooling towers with their steam; masts, phone towers, water towers, silos, tanks,
## gasometers, bell towers, minarets and lookouts; cable cars, gondolas, chair and drag lifts with their pylons,
## stations and cabins moving on the wire; piste poles down the ski runs.
##
## SceneryStreamer calls it for every row whose kit names "skyline:MODEL" (data/scenery_kits.json): lay_out on a worker
## for a block, mesh for each model, dress on the main thread for what isn't one MultiMesh of a model (the wires and
## fences of a block as one mesh, the cabins that move). Nothing here has collision or touches a road or the land: a
## thing the map puts on a road is stood off it (SceneryStreamer.stand), and a wire sags no lower than its clearance
## over the ground and the roads under it (CLEAR in its kit).
##
## Every model is built here from boxes and lathes, vertex coloured, with one shared shader (SHADER): the blades turn
## in it, the lamps are lit and blink in it (red aviation lamps blink together by the clock, so a crew sees them in step)
## and the wires keep at least a pixel wide in it, so a power line reads at a distance as it does in life.

## Bumped when what a block lays out changes (the kit library's rows are hashed by the streamer already).
const VERSION := 1
const SIZE := 512.0   # RoadBlock.SIZE

## Shader flags, in a vertex's UV2.x: a part that turns with the rotor (UV2.y its hub's height, UV.x its hub's z), a
## lamp that blinks red at night, a lamp lit steady at night, a wire (NORMAL its direction, UV.x its side, UV2.y its
## radius).
const ROTOR := 1.0
const BLINK := 2.0
const STEADY := 3.0
const WIRE := 4.0

## How far a mapped tower or pole may be from a line's own course to be one of its supports (m).
const SNAP := 12.0
## A line's bend sharper than this (degrees) gets a support of its own where no mapped one is near.
const BEND := 8.0
## Where a line's ends meet another piece's within this (m), they're joined (the baker cuts lines at each cell's edge).
const JOIN := 0.6
## A solar area smaller than this (m²) is a roof's, already on its building: only bigger ones are fields of panels.
const SOLAR_MIN := 2500.0
## At most this many panel rows an area a block (a big solar park is drawn by its outline's nearer part).
const SOLAR_MAX := 2500
## The wind's direction (the clouds', CloudSky.wind_for): every rotor faces into it.
const WIND := Vector2(11.0, 4.5)

const GREY := Color(0.56, 0.58, 0.59)
const WHITE := Color(0.9, 0.91, 0.91)
const WOOD := Color(0.36, 0.27, 0.19)
const STONE := Color(0.62, 0.58, 0.5)
const CONCRETE := Color(0.7, 0.69, 0.66)
const DARK := Color(0.14, 0.15, 0.16)
const RED := Color(1.0, 0.08, 0.04)
const LAMP_WHITE := Color(1.0, 0.95, 0.85)

## The supports: how tall the model is (m, what a mapped height scales it to), and where its wires hang (x out along
## its arms, y up; the line runs along z). Wires join a support's to the next's in this order.
const SUPPORTS := {
	"pylon": {"h": 46.0, "wires": [Vector3(-7.0, 23.5, 0), Vector3(-6.5, 29.5, 0), Vector3(-6.0, 35.5, 0),
		Vector3(7.0, 23.5, 0), Vector3(6.5, 29.5, 0), Vector3(6.0, 35.5, 0), Vector3(0, 46.0, 0)]},
	"pylon_danube": {"h": 40.0, "wires": [Vector3(-11.0, 26.0, 0), Vector3(-5.5, 26.0, 0), Vector3(-6.5, 32.5, 0),
		Vector3(11.0, 26.0, 0), Vector3(5.5, 26.0, 0), Vector3(6.5, 32.5, 0), Vector3(0, 40.0, 0)]},
	"pylon_wide": {"h": 30.0, "wires": [Vector3(-9.0, 20.5, 0), Vector3(0, 20.5, 0), Vector3(9.0, 20.5, 0),
		Vector3(-6.0, 30.0, 0), Vector3(6.0, 30.0, 0)]},
	"pylon_tall": {"h": 62.0, "wires": [Vector3(-7.5, 33.0, 0), Vector3(-7.0, 41.0, 0), Vector3(-6.5, 49.0, 0),
		Vector3(7.5, 33.0, 0), Vector3(7.0, 41.0, 0), Vector3(6.5, 49.0, 0), Vector3(0, 62.0, 0)]},
	"portal": {"h": 16.0, "wires": [Vector3(-4.0, 14.5, 0), Vector3(0, 14.5, 0), Vector3(4.0, 14.5, 0)]},
	"pole": {"h": 10.0, "wires": [Vector3(-1.0, 9.6, 0), Vector3(0, 10.0, 0), Vector3(1.0, 9.6, 0)]},
	"pole_concrete": {"h": 12.0, "wires": [Vector3(-1.0, 11.6, 0), Vector3(0, 12.0, 0), Vector3(1.0, 11.6, 0),
		Vector3(-0.8, 9.6, 0), Vector3(0.8, 9.6, 0)]},
	"pole_tel": {"h": 8.0, "wires": [Vector3(-0.4, 7.6, 0), Vector3(0.4, 7.6, 0)]},
	"lift_pylon": {"h": 15.0, "wires": [Vector3(-2.6, 15.0, 0), Vector3(2.6, 15.0, 0)]},
	"lift_station": {"h": 9.0, "wires": [Vector3(-2.6, 7.0, 0), Vector3(2.6, 7.0, 0)]},
	"lift_terminal": {"h": 6.0, "wires": [Vector3(-2.0, 5.5, 0), Vector3(2.0, 5.5, 0)]},
}
## The cabins on an aerialway, by the line's kit "cabin": how far apart (m) and how fast the rope runs (m/s). A cable
## car's two cabins shuttle end to end instead.
const CABINS := {
	"gondola": {"every": 70.0, "speed": 5.0}, "chair": {"every": 16.0, "speed": 2.4},
	"tbar": {"every": 22.0, "speed": 3.0}, "cable_car": {"every": 0.0, "speed": 8.0},
	"bucket": {"every": 40.0, "speed": 3.0},
}

static var _meshes := {}
static var _meshes_lock := Mutex.new()
static var _material: ShaderMaterial
static var _steam: ShaderMaterial
static var _regions := {}     # region instance id -> its lines' supports and spans (_lines_of)
static var _regions_lock := Mutex.new()
static var _spin := 0.0
static var _ticked := -1


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of the rows (SceneryStreamer's: {points, lines, areas}, each [row, kit]) whose kit names
## this script: {items: {model: [Transform3D in the block's frame]}, dress: {wires: arrays for one mesh of the block's
## wires and fences, movers: the cabins' paths}}. Safe on a worker.
static func lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var out := {"items": {}, "dress": {"wires": _Wires.new(), "movers": []}, "xfs": {}}
	var o := Vector3(key.x * SIZE, 0.0, key.y * SIZE)
	var memo := {}
	var lines := _lines_of(net)
	for pair: Array in rows.get("points", []):
		_point(net, key, o, pair[0], pair[1], lines, memo, out)
	for pair: Array in rows.get("areas", []):
		_area(net, key, o, pair[0], pair[1], memo, out)
	# (the lines are laid out from the whole region's joined lines, so a support or a span is the same whichever block
	# asks: each in the one block its middle is in)
	var filed: Dictionary = (lines["by_block"] as Dictionary).get(key, {})
	for ref: Vector2i in filed.get("supports", []):
		var line: Dictionary = lines["lines"][ref.x]
		var s: Dictionary = (line["supports"] as Array)[ref.y]
		var xf = _xf_of(net, s, memo, out)
		if xf != null:
			_add(out, str(s["model"]), Transform3D((xf as Transform3D).basis, (xf as Transform3D).origin - o))
	for ref: Vector2i in filed.get("spans", []):
		_span(net, lines["lines"][ref.x], ref.y, o, memo, out)
	for i: int in filed.get("movers", []):
		_mover(net, lines["lines"][i], o, memo, out)
	for i: int in filed.get("markers", []):
		_markers(net, key, o, lines["lines"][i], memo, out)
	out.erase("xfs")
	var w: _Wires = out["dress"]["wires"]
	out["dress"]["wires"] = w.arrays() if w.count > 0 else []
	if out["dress"]["wires"].is_empty() and (out["dress"]["movers"] as Array).is_empty():
		out.erase("dress")
	return out


static func _add(out: Dictionary, model: String, xf: Transform3D) -> void:
	if not (out["items"] as Dictionary).has(model):
		out["items"][model] = []
	(out["items"][model] as Array).append(xf)


## Where a thing stands (region frame): SceneryStreamer.stand's (off any road, on the land), or NAN.
static func _stand(net: RoadNet, p: Vector2, memo: Dictionary, sea := false) -> Vector3:
	return SceneryStreamer.stand(net, p, memo, sea)


## The ground at (x, z) with the roads in it (no moving off them): for a wire's clearance.
static func _ground(net: RoadNet, x: float, z: float, memo: Dictionary) -> float:
	var bare := float(net.height.call(x, z))
	# (away from every road the ground is the bare land: ground_at's answer there, without its look round)
	return bare if is_nan(bare) or net._near(x, z).is_empty() else net.ground_at(x, z, bare, memo)


static func _in(key: Vector2i, p: Vector2) -> bool:
	return SceneryStreamer.in_block(key, p)


## A yaw (about +y) that turns local +z to `dir` (region x, z).
static func _yaw(dir: Vector2) -> float:
	return atan2(dir.x, dir.y) if dir.length_squared() > 1e-8 else 0.0


## A point row: its model where it stands, scaled to its mapped height.
static func _point(net: RoadNet, key: Vector2i, o: Vector3, row: Array, k: Dictionary, lines: Dictionary,
		memo: Dictionary, out: Dictionary) -> void:
	var kind := str(row[0])
	var model := _model_of(k)
	if model == "" or model == "none" or (kind == "solar" and not bool(k.get("points", false))):
		return
	var p := Vector2(float(row[1]), float(row[2]))
	var h = row[3]
	if kind in ["power_tower", "power_pole", "power_portal", "aerialway_pylon", "aerialway_station"]:
		# (one of a line's supports: stood and turned as the line's own spans expect it, _lines_of)
		var s = (lines["mapped"] as Dictionary).get(_spot(p))
		var sup := {"p": p, "dir": (s as Dictionary)["dir"] if s != null else _dir_of(row), "model": model,
			"h": h}
		var xf = _xf_of(net, sup, memo, out)
		if xf != null:
			_add(out, model, Transform3D((xf as Transform3D).basis, (xf as Transform3D).origin - o))
		return
	var at := _stand(net, p, memo, bool(k.get("sea", false)))
	if is_nan(at.x):
		return
	var yaw := 0.0
	var scale := 1.0
	match kind:
		"wind_turbine":
			yaw = _yaw(WIND)
			scale = _hub(h, k, at.y) / 100.0
		_:
			yaw = deg_to_rad(float(row[5])) * -1.0 if row[5] != null else _seeded(row, 6.2832)
			scale = _scale(h, k)
	if model == "yard":
		_yard(net, o, Vector2(at.x, at.z), 1500.0, row, memo, out)
		return
	var size := Vector3.ONE * scale
	if k.has("r"):
		size = _sized(k, float(k.get("point_r", k["r"])), h)
	var tall := _variant(model, kind, h, k)
	if tall != model:
		size = Vector3.ONE * clampf(float(h) / float(k.get("tall_h", 1.0)), 0.5, 2.0)
		model = tall
	var basis := Basis(Vector3.UP, yaw).scaled(size)
	if kind == "wind_turbine" and at.y < 0.0:
		at.y = 0.0   # (offshore: from the sea, not the bed)
	_add(out, model, Transform3D(basis, at - o))
	if model == "cooling" and _seeded(row, 1.0) < 0.75:
		_add(out, "steam", Transform3D(basis, at - o))


## An area row: a thing at its middle (a turbine, a tower, a tank sized to it), a fenced yard round it, or a field of
## panels over the part of it in the block.
static func _area(net: RoadNet, key: Vector2i, o: Vector3, row: Array, k: Dictionary, memo: Dictionary,
		out: Dictionary) -> void:
	var kind := str(row[0])
	var ring: PackedVector2Array = row[1]
	if ring.size() < 3:
		return
	var model := _model_of(k)
	if model == "" or model == "none" or kind == "generator":
		return
	var mid := _centroid(ring)
	var area := absf(_signed_area(ring))
	if bool(k.get("fence", false)):
		_fence(net, key, o, ring, memo, out)
	if model == "fence":
		return
	if model == "piste":
		_markers(net, key, o, {"pts": ring, "kit": k.merged({"half_width": 0.0, "every": 50.0})}, memo, out)
		return
	if kind == "solar" or model == "solar_row":
		if area >= SOLAR_MIN:
			_solar(net, key, o, ring, memo, out)
		return
	if model == "yard":
		# (a substation's or a station's transformers in the middle of its yard)
		if _in(key, mid):
			_yard(net, o, mid, area, row, memo, out)
		return
	if not _in(key, mid):
		return
	var at := _stand(net, mid, memo, bool(k.get("sea", false)))
	if is_nan(at.x):
		return
	var h = row[2]
	var r := sqrt(area / PI)
	var scale := Vector3.ONE * _scale(h, k)
	match model:
		"turbine":
			scale = Vector3.ONE * _hub(h, k, at.y) / 100.0
			_add(out, model, Transform3D(Basis(Vector3.UP, _yaw(WIND)).scaled(scale), Vector3(at.x, maxf(at.y, 0.0), at.z) - o))
			return
		"cooling":
			scale = Vector3.ONE * (float(h) / 100.0 if h != null else clampf(r / 40.0, 0.5, 1.6))
		_:
			if k.has("r"):
				var rr := clampf(r, 2.0, 45.0)
				if k.has("big") and rr >= float(k.get("big_from", 1e9)):
					model = str(k["big"])
					scale = Vector3.ONE * rr / float(k.get("big_r", 8.0))
				else:
					scale = _sized(k, rr, h)
	var basis := Basis(Vector3.UP, _seeded(row, 6.2832)).scaled(scale)
	_add(out, model, Transform3D(basis, at - o))
	if model == "cooling" and _seeded(row, 1.0) < 0.75:
		_add(out, "steam", Transform3D(basis, at - o))


## A kit's model without its script ("skyline:pylon" -> "pylon"), "" for another script's.
static func _model_of(k: Dictionary) -> String:
	var m := str(k.get("model", ""))
	return m.get_slice(":", 1) if m.begins_with("skyline:") else ""


## The scale of a round thing of kit `k` (its model "r" m across and "h" tall) made `r` m across and `h` tall (or its
## kit's height for its radius where the map gives none).
static func _sized(k: Dictionary, r: float, h) -> Vector3:
	var hh := float(h) if h != null and float(h) > 0.0 else float(k.get("h_of_r", 0.0)) * r + float(k.get("h_plus", float(k.get("h", 1.0))))
	return Vector3(r / float(k["r"]), hh / float(k.get("h", 1.0)), r / float(k["r"]))


## A model's variant by the thing's mapped height: its kit's "tall" model from "tall_from" m (a mast past 140 m is a
## concrete TV tower).
static func _variant(model: String, kind: String, h, k: Dictionary) -> String:
	if h == null:
		return model
	var tall := float(k.get("tall_from", 0.0))
	if tall > 0.0 and float(h) >= tall and k.has("tall"):
		return str(k["tall"])
	return model


## How much a model of kit `k` is scaled for a mapped height `h` (its kit's "h" is the model's own; its "scale" where
## the map gives none).
static func _scale(h, k: Dictionary) -> float:
	if h == null or float(h) <= 0.0:
		return float(k.get("scale", 1.0))
	return clampf(float(h) / float(k.get("h", 1.0)), float(k.get("scale_min", 0.5)), float(k.get("scale_max", 2.0)))


## A turbine's hub height (m) from the map's height (taken as its tip's, Overture's height being the feature's whole
## height) or its region's default; offshore ones (standing in the sea) are the region's offshore size.
static func _hub(h, k: Dictionary, ground: float) -> float:
	if h != null and float(h) > 20.0:
		return clampf(float(h) / 1.55, 20.0, 170.0)
	return float(k.get("hub_sea", 110.0)) if ground < -1.0 else float(k.get("hub", 90.0))


## A number in [0, top) from the row's id (or where it is): the same on every machine.
static func _seeded(row: Array, top: float) -> float:
	var seed_of := str(row[row.size() - 1]) if row[row.size() - 1] != null else "%.1f,%.1f" % [float(row[1]) if row[1] is float else 0.0, float(row[2]) if row[2] is float else 0.0]
	return float(seed_of.hash() & 0xffff) / 65536.0 * top


static func _dir_of(row: Array) -> Vector2:
	if row[5] == null:
		return Vector2(0, 1)
	var a := deg_to_rad(float(row[5]))
	return Vector2(sin(a), -cos(a))


static func _spot(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))


static func _centroid(ring: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in ring.size():
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		var cr := p.cross(q)
		a += cr
		c += (p + q) * cr
	if absf(a) < 1e-6:
		var s := Vector2.ZERO
		for p in ring:
			s += p
		return s / ring.size()
	return c / (3.0 * a)


static func _signed_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size():
		a += ring[i].cross(ring[(i + 1) % ring.size()])
	return a * 0.5


# ---------------------------------------------------------------------------- lines: supports and wires

## The region's wire-carrying lines (power and phone lines, aerialways, pistes) joined across the cells' cuts, each with
## its supports (the mapped towers and poles along it, and ones of its own where the map has none for a span), filed by
## the block each support, span and moving cabin is laid out in. Worked out once a region, the same on every machine.
static func _lines_of(net: RoadNet) -> Dictionary:
	var id := net.region.get_instance_id()
	_regions_lock.lock()
	var got = _regions.get(id)
	if got == null:
		got = _work_out_lines(net.region)
		if _regions.size() > 4:
			_regions.clear()
		_regions[id] = got
	_regions_lock.unlock()
	return got


static func _work_out_lines(region: RealRegion) -> Dictionary:
	var feats := region.features
	var out := {"lines": [], "by_block": {}, "mapped": {}}
	# The mapped supports by kind, in a grid to find the ones along a line.
	var grid := {}   # Vector2i (64 m) -> [[index, kind]]
	var points: Array = feats.get("points", [])
	for i in points.size():
		var row: Array = points[i]
		var kind := str(row[0])
		if kind in ["power_tower", "power_pole", "power_portal", "aerialway_pylon", "aerialway_station"]:
			var g := Vector2i(floori(float(row[1]) / 64.0), floori(float(row[2]) / 64.0))
			if not grid.has(g):
				grid[g] = []
			(grid[g] as Array).append(i)
	var joined := _join(feats.get("lines", []))
	for piece: Array in joined:
		var kind: String = piece[0]
		var pts: PackedVector2Array = piece[1]
		var mid := pts[pts.size() / 2]
		var region_id := str(RegionKit.at_frame(region.frame_lat, region.frame_lon, mid.x, mid.y).get("region", ""))
		var k := SceneryStreamer.kit(kind, region_id)
		var m := _model_of(k)
		if m == "" or m == "none":
			continue
		var line := {"kind": kind, "pts": pts, "kit": k, "supports": [], "region": region_id}
		var idx: int = (out["lines"] as Array).size()
		(out["lines"] as Array).append(line)
		if m == "piste":
			_file(out, RoadBlock.key_of(mid.x, mid.y), "markers", idx)
			# (markers along all of it: filed by every block the line passes through)
			var seen := {}
			for p in pts:
				var b := RoadBlock.key_of(p.x, p.y)
				if not seen.has(b) and b != RoadBlock.key_of(mid.x, mid.y):
					seen[b] = true
					_file(out, b, "markers", idx)
			continue
		_supports(region, line, points, grid, out)
		var sups: Array = line["supports"]
		for j in sups.size():
			var s: Dictionary = sups[j]
			if int(s["point"]) < 0:
				_file(out, RoadBlock.key_of(s["p"].x, s["p"].y), "supports", Vector2i(idx, j))
			if j + 1 < sups.size():
				var c: Vector2 = (s["p"] + sups[j + 1]["p"]) * 0.5
				_file(out, RoadBlock.key_of(c.x, c.y), "spans", Vector2i(idx, j))
		if k.has("cabin") and sups.size() >= 2:
			var half := _along(pts, _length(pts) * 0.5)
			_file(out, RoadBlock.key_of(half.x, half.y), "movers", idx)
	return out


static func _file(out: Dictionary, key: Vector2i, what: String, v) -> void:
	var b: Dictionary = (out["by_block"] as Dictionary).get(key, {})
	if not b.has(what):
		b[what] = []
	(b[what] as Array).append(v)
	out["by_block"][key] = b


## The lines of `rows` (RealRegion.features') joined where one piece ends where another of its kind starts (the
## baker cut them at each cell's edge): [[kind, PackedVector2Array], ...].
static func _join(rows: Array) -> Array:
	var pieces: Array = []
	for row: Array in rows:
		var pts: PackedVector2Array = row[1]
		if pts.size() >= 2:
			pieces.append([str(row[0]), pts])
	var ends := {}   # "kind|x|z" -> [piece index, ...]
	for i in pieces.size():
		for at in [0, -1]:
			var p: Vector2 = (pieces[i][1] as PackedVector2Array)[at]
			var key := "%s|%d|%d" % [pieces[i][0], roundi(p.x / JOIN), roundi(p.y / JOIN)]
			if not ends.has(key):
				ends[key] = []
			(ends[key] as Array).append(i)
	var used := {}
	var out: Array = []
	for i in pieces.size():
		if used.has(i):
			continue
		used[i] = true
		var kind: String = pieces[i][0]
		var pts: PackedVector2Array = (pieces[i][1] as PackedVector2Array).duplicate()
		for forward in [true, false]:
			while true:
				var tip: Vector2 = pts[pts.size() - 1] if forward else pts[0]
				var key := "%s|%d|%d" % [kind, roundi(tip.x / JOIN), roundi(tip.y / JOIN)]
				var next := -1
				for j: int in ends.get(key, []):
					if not used.has(j):
						next = j
						break
				if next < 0:
					break
				used[next] = true
				var more: PackedVector2Array = (pieces[next][1] as PackedVector2Array).duplicate()
				if forward:
					if more[0].distance_to(tip) > more[more.size() - 1].distance_to(tip):
						more.reverse()
					more.remove_at(0)
					pts.append_array(more)
				else:
					if more[more.size() - 1].distance_to(tip) > more[0].distance_to(tip):
						more.reverse()
					more.remove_at(more.size() - 1)
					more.append_array(pts)
					pts = more
		out.append([kind, pts])
	return out


static func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i - 1].distance_to(pts[i])
	return l


static func _along(pts: PackedVector2Array, s: float) -> Vector2:
	for i in range(1, pts.size()):
		var d := pts[i - 1].distance_to(pts[i])
		if s <= d or i == pts.size() - 1:
			return pts[i - 1].lerp(pts[i], clampf(s / maxf(d, 1e-6), 0.0, 1.0))
		s -= d
	return pts[pts.size() - 1]


static func _tangent(pts: PackedVector2Array, s: float) -> Vector2:
	var a := _along(pts, maxf(s - 2.0, 0.0))
	var b := _along(pts, s + 2.0)
	return (b - a).normalized() if a.distance_squared_to(b) > 1e-6 else Vector2(0, 1)


## Line `line`'s supports: [{p, dir (along the line), model, h, point (its index in the region's points, -1 for one
## of its own)}, ...] in order along it. The mapped towers or poles of its kit's "snap" kinds within SNAP of it, its
## ends and its bends where none is near, and enough between to keep every span within the kit's "span".
static func _supports(region: RealRegion, line: Dictionary, points: Array, grid: Dictionary, out: Dictionary) -> void:
	var pts: PackedVector2Array = line["pts"]
	var k: Dictionary = line["kit"]
	var snap: Array = k.get("snap", [])
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total := cum[cum.size() - 1]
	if total < 1.0:
		return
	var found: Array = []   # [s, Vector2 p, point index, kind]
	var seen := {}
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var g0 := Vector2i(floori((minf(a.x, b.x) - SNAP) / 64.0), floori((minf(a.y, b.y) - SNAP) / 64.0))
		var g1 := Vector2i(floori((maxf(a.x, b.x) + SNAP) / 64.0), floori((maxf(a.y, b.y) + SNAP) / 64.0))
		for gx in range(g0.x, g1.x + 1):
			for gz in range(g0.y, g1.y + 1):
				for pi: int in grid.get(Vector2i(gx, gz), []):
					if seen.has(pi):
						continue
					var row: Array = points[pi]
					if str(row[0]) not in snap:
						continue
					var p := Vector2(float(row[1]), float(row[2]))
					var q := Geometry2D.get_closest_point_to_segment(p, a, b)
					if q.distance_to(p) <= SNAP:
						seen[pi] = true
						found.append([cum[i] + a.distance_to(q), p, pi, str(row[0]), row[3]])
	found.sort_custom(func(x, y): return x[0] < y[0])
	var stops: Array = []   # [s, p, point, model, h]
	var support_model := str(k.get("support", "pole"))
	var support_h = k.get("support_h")
	for f: Array in found:
		var fk := SceneryStreamer.kit(str(f[3]), str(line["region"]))
		stops.append([float(f[0]), f[1], int(f[2]), _model_of(fk) if _model_of(fk) != "" else support_model,
			f[4] if f[4] != null else support_h])
	# The ends (a station or a terminal for a lift), and the bends where nothing is mapped.
	var end_model := str(k.get("end", support_model))
	for s_end in [0.0, total]:
		if not stops.any(func(x): return absf(float(x[0]) - s_end) < 25.0):
			stops.append([s_end, _along(pts, s_end), -1, end_model, null if end_model != support_model else support_h])
	for i in range(1, pts.size() - 1):
		var d0 := (pts[i] - pts[i - 1]).normalized()
		var d1 := (pts[i + 1] - pts[i]).normalized()
		if rad_to_deg(absf(d0.angle_to(d1))) > BEND and not stops.any(func(x): return absf(float(x[0]) - cum[i]) < 20.0):
			stops.append([cum[i], pts[i], -1, support_model, support_h])
	stops.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var span := float(k.get("span", 300.0))
	var filled: Array = []
	for i in stops.size():
		if i > 0:
			var gap := float(stops[i][0]) - float(stops[i - 1][0])
			var n := int(ceil(gap / span)) - 1
			for j in n:
				var s := float(stops[i - 1][0]) + gap * float(j + 1) / float(n + 1)
				filled.append([s, _along(pts, s), -1, support_model, support_h])
		filled.append(stops[i])
	var sups: Array = []
	for f: Array in filled:
		var dir := _tangent(pts, float(f[0]))
		var s := {"p": f[1], "dir": dir, "model": f[3], "h": f[4], "point": f[2], "s": f[0]}
		sups.append(s)
		if int(f[2]) >= 0:
			out["mapped"][_spot(f[1])] = s
	line["supports"] = sups


## Where support `s` stands and how it's turned and scaled (region frame), or null where it can't stand.
static func _support_xf(net: RoadNet, s: Dictionary, memo: Dictionary):
	var at := _stand(net, s["p"], memo)
	if is_nan(at.x):
		return null
	var model := str(s["model"])
	var info: Dictionary = SUPPORTS.get(model, {"h": 10.0})
	var scale := 1.0
	if s["h"] != null and float(s["h"]) > 2.0:
		scale = clampf(float(s["h"]) / float(info["h"]), 0.6, 1.8)
	return Transform3D(Basis(Vector3.UP, _yaw(s["dir"])).scaled(Vector3.ONE * scale), at)


## _support_xf's, worked out once a block (a span asks after both its ends, and its neighbours after the same).
static func _xf_of(net: RoadNet, s: Dictionary, memo: Dictionary, out: Dictionary):
	var xfs: Dictionary = out["xfs"]
	var key := _spot(s["p"])
	if not xfs.has(key):
		xfs[key] = _support_xf(net, s, memo)
	return xfs[key]


## The wires of span `j` of `line` (from its support j to j + 1), sagging as a catenary, no lower than the kit's
## "clear" over the ground and roads under them.
static func _span(net: RoadNet, line: Dictionary, j: int, o: Vector3, memo: Dictionary, out: Dictionary) -> void:
	var sups: Array = line["supports"]
	var a: Dictionary = sups[j]
	var b: Dictionary = sups[j + 1]
	var xa = _xf_of(net, a, memo, out)
	var xb = _xf_of(net, b, memo, out)
	if xa == null or xb == null:
		return
	var wa: Array = (SUPPORTS.get(str(a["model"]), {}) as Dictionary).get("wires", [])
	var wb: Array = (SUPPORTS.get(str(b["model"]), {}) as Dictionary).get("wires", [])
	var n := mini(wa.size(), wb.size())
	if n == 0:
		return
	var k: Dictionary = line["kit"]
	var clear := float(k.get("clear", 6.0))
	var sag_k := float(k.get("sag", 0.02))
	var radius := float(k.get("wire", 0.03))
	var colour := Color(k.get("wire_colour", "#3a3d40"))
	var w: _Wires = out["dress"]["wires"]
	# (the lowest a wire may come: worked out once a span, from its lowest pair of attachments)
	var p0: Vector3 = (xa as Transform3D) * (wa[0] as Vector3)
	var p1: Vector3 = (xb as Transform3D) * (wb[0] as Vector3)
	var lowest := INF
	for i in n:
		lowest = minf(lowest, minf(((xa as Transform3D) * (wa[i] as Vector3)).y, ((xb as Transform3D) * (wb[i] as Vector3)).y))
	var length := Vector2(p0.x, p0.z).distance_to(Vector2(p1.x, p1.z))
	var sag := sag_k * length
	for t: float in [0.25, 0.5, 0.75]:
		var g := _ground(net, lerpf(p0.x, p1.x, t), lerpf(p0.z, p1.z, t), memo)
		if is_nan(g):
			continue
		var line_y := lerpf(minf(p0.y, lowest), minf(p1.y, lowest), t)
		sag = clampf((line_y - g - clear) / (4.0 * t * (1.0 - t)), 0.0, sag)
	for i in n:
		var u: Vector3 = (xa as Transform3D) * (wa[i] as Vector3) - o
		var v: Vector3 = (xb as Transform3D) * (wb[i] as Vector3) - o
		w.catenary(u, v, sag, radius, colour)


## The cabins of aerialway `line`: a path up one rope and down the other, laid out in the block its middle is in.
static func _mover(net: RoadNet, line: Dictionary, o: Vector3, memo: Dictionary, out: Dictionary) -> void:
	var sups: Array = line["supports"]
	var up := PackedVector3Array()
	var down := PackedVector3Array()
	for s: Dictionary in sups:
		var xf = _xf_of(net, s, memo, out)
		if xf == null:
			return
		var wires: Array = (SUPPORTS.get(str(s["model"]), {}) as Dictionary).get("wires", [])
		if wires.size() < 2:
			return
		up.append((xf as Transform3D) * (wires[1] as Vector3) - o)
		down.append((xf as Transform3D) * (wires[0] as Vector3) - o)
	down.reverse()
	var cabin := str(line["kit"].get("cabin", "gondola"))
	(out["dress"]["movers"] as Array).append({"cabin": cabin, "up": up, "down": down,
		"every": float((CABINS.get(cabin, {}) as Dictionary).get("every", 50.0)),
		"speed": float((CABINS.get(cabin, {}) as Dictionary).get("speed", 4.0))})


## The marker poles down a piste (both edges of a run, every 40 m) in block `key`.
static func _markers(net: RoadNet, key: Vector2i, o: Vector3, line: Dictionary, memo: Dictionary, out: Dictionary) -> void:
	var pts: PackedVector2Array = line["pts"]
	var total := _length(pts)
	var k: Dictionary = line["kit"]
	var every := float(k.get("every", 40.0))
	var half := float(k.get("half_width", 12.0))
	var model := str(k.get("marker", "piste_pole"))
	var s := every * 0.5
	while s < total:
		var c := _along(pts, s)
		var d := _tangent(pts, s)
		var side := Vector2(-d.y, d.x)
		for sign_ in ([-1.0, 1.0] if half > 0.0 else [0.0]):
			var p: Vector2 = c + side * half * sign_
			if _in(key, p):
				var at := _stand(net, p, memo)
				if not is_nan(at.x):
					_add(out, model, Transform3D(Basis(Vector3.UP, _yaw(d)), at - o))
		s += every


## The fence round a yard's outline (the part of it in block `key`), its posts and mesh in the block's wire mesh.
static func _fence(net: RoadNet, key: Vector2i, o: Vector3, ring: PackedVector2Array, memo: Dictionary, out: Dictionary) -> void:
	var w: _Wires = out["dress"]["wires"]
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var d := a.distance_to(b)
		var n := maxi(1, int(ceil(d / 6.0)))
		for j in n:
			var p := a.lerp(b, float(j) / n)
			var q := a.lerp(b, float(j + 1) / n)
			if not _in(key, (p + q) * 0.5):
				continue
			# (a fence along a road is the road's business, never ours: left out within its clearance)
			var sp := SceneryStreamer.off_road(net, (p + q) * 0.5)
			if is_nan(sp.x) or sp != (p + q) * 0.5:
				continue
			var yp := _ground(net, p.x, p.y, memo)
			var yq := _ground(net, q.x, q.y, memo)
			if is_nan(yp) or is_nan(yq):
				continue
			w.panel(Vector3(p.x, yp, p.y) - o, Vector3(q.x, yq, q.y) - o, 2.4, Color(0.42, 0.45, 0.43))
			out["dress"]["reach"] = maxf(float(out["dress"].get("reach", 0.0)), 1500.0)


## A yard's transformers and gantries round its middle `mid`, by its size.
static func _yard(net: RoadNet, o: Vector3, mid: Vector2, area: float, row: Array, memo: Dictionary, out: Dictionary) -> void:
	var n := clampi(int(area / 1500.0), 1, 6)
	var turn := _seeded(row, PI)
	var basis := Basis(Vector3.UP, turn)
	for i in n:
		var off := basis * Vector3((float(i) - (n - 1) * 0.5) * 9.0, 0.0, 0.0)
		var p := mid + Vector2(off.x, off.z)
		var at := _stand(net, p, memo)
		if is_nan(at.x):
			continue
		_add(out, "transformer", Transform3D(basis, at - o))
		if i % 2 == 0:
			_add(out, "portal", Transform3D(basis, at + basis * Vector3(0, 0, 8.0) - o))


## Rows of panels over the part of solar field `ring` in block `key`, facing the equator.
static func _solar(net: RoadNet, key: Vector2i, o: Vector3, ring: PackedVector2Array, memo: Dictionary, out: Dictionary) -> void:
	var box := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		box = box.expand(p)
	var blk := Rect2(Vector2(key) * SIZE, Vector2.ONE * SIZE)
	box = box.intersection(blk)
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	# (a row is 20 m along x and tilted to face the sun's side: south (+z) north of the equator, north south of it)
	var south := net.region.frame_lat >= 0.0
	var basis := Basis(Vector3.UP, 0.0 if south else PI)
	var made := 0
	var z := ceilf(box.position.y / 7.0) * 7.0
	while z < box.end.y and made < SOLAR_MAX:
		var x := ceilf(box.position.x / 21.0) * 21.0
		while x < box.end.x and made < SOLAR_MAX:
			var p := Vector2(x + 10.5, z + 3.5)
			if Geometry2D.is_point_in_polygon(p, ring) and net._near(p.x, p.y).is_empty():
				var y := _ground(net, p.x, p.y, memo)
				if not is_nan(y):
					_add(out, "solar_row", Transform3D(basis, Vector3(p.x, y, p.y) - o))
					made += 1
			x += 21.0
		z += 7.0


# ---------------------------------------------------------------------------- dressing a block (main thread)

## Puts block `node`'s wires and fences (one mesh) and moving cabins in, from lay_out's dress.
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary:
		return
	var reach := float(data.get("reach", 2500.0)) * clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	var arrays: Array = data.get("wires", [])
	if not arrays.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material())
		var mi := MeshInstance3D.new()
		mi.name = "SkylineWires"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = reach
		node.add_child(mi)
	for m: Dictionary in data.get("movers", []):
		var mover := _Mover.new()
		mover.setup(m)
		mover.visibility_range_end = minf(reach, 2500.0)
		node.add_child(mover)
	var t := _Tick.new()
	node.add_child(t)


## The blades' angle, the lamps and the wind: moved on once a frame by whichever block's ticker gets there first.
static func tick(delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == _ticked:
		return
	_ticked = f
	_spin = fmod(_spin + delta * rpm() / 60.0 * TAU, TAU)
	var m := material()
	m.set_shader_parameter("spin", _spin)
	m.set_shader_parameter("night", night())
	m.set_shader_parameter("blink", 1.0 if fmod(Time.get_unix_time_from_system(), 1.5) < 0.5 else 0.0)
	_steam_material().set_shader_parameter("night", night())


## How fast the rotors turn (rpm) in the weather: a gentle turn in fog's still air, faster with cloud and rain.
static func rpm() -> float:
	return clampf(10.0 + 4.0 * Weather.cover_level() + 6.0 * Weather.rain_level() - 8.0 * Weather.fog_level(), 3.0, 18.0)


static func night() -> float:
	return Daylight.current.lamps if Daylight.current != null else 0.0


## Moves a line's cabins along its ropes by the clock, so every machine in a crew has them in the same place.
class _Mover extends MultiMeshInstance3D:
	var up: PackedVector3Array
	var down: PackedVector3Array
	var cum_up := PackedFloat32Array()
	var cum_down := PackedFloat32Array()
	var every := 50.0
	var speed := 4.0
	var shuttle := false

	func setup(m: Dictionary) -> void:
		name = "Cabins"
		up = m["up"]
		down = m["down"]
		every = float(m["every"])
		speed = float(m["speed"])
		shuttle = every <= 0.0
		cum_up = _cum(up)
		cum_down = _cum(down)
		var n := 2 if shuttle else maxi(1, int((cum_up[cum_up.size() - 1] + cum_down[cum_down.size() - 1]) / every))
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = Skyline.mesh(str(m["cabin"]))
		multimesh.instance_count = n
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_move()

	func _cum(p: PackedVector3Array) -> PackedFloat32Array:
		var c := PackedFloat32Array([0.0])
		for i in range(1, p.size()):
			c.append(c[i - 1] + p[i - 1].distance_to(p[i]))
		return c

	func _at(p: PackedVector3Array, c: PackedFloat32Array, s: float) -> Transform3D:
		var i := c.bsearch(s)
		i = clampi(i, 1, p.size() - 1)
		var d := maxf(c[i] - c[i - 1], 1e-4)
		var at := p[i - 1].lerp(p[i], clampf((s - c[i - 1]) / d, 0.0, 1.0))
		var dir := p[i] - p[i - 1]
		return Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), at)

	func _process(_delta: float) -> void:
		if is_visible_in_tree():
			_move()

	func _move() -> void:
		var at := placed(Time.get_unix_time_from_system())
		for i in at.size():
			multimesh.set_instance_transform(i, at[i])

	## Where the cabins are at time `t` (seconds by the clock on the wall).
	func placed(t: float) -> Array[Transform3D]:
		var out: Array[Transform3D] = []
		var lu := cum_up[cum_up.size() - 1]
		var ld := cum_down[cum_down.size() - 1]
		if lu <= 0.0 or ld <= 0.0:
			return out
		if shuttle:
			# (two cabins shuttle end to end and back, passing in the middle, resting a while at each end)
			var period := 2.0 * lu / speed + 40.0
			var ph := fmod(t, period) / period
			var u := clampf(1.0 - absf(ph * 2.0 - 1.0) * 1.15, 0.0, 1.0)
			var s := (0.5 - 0.5 * cos(u * PI)) * lu
			out.append(_at(up, cum_up, s))
			out.append(_at(down, cum_down, ld - s * ld / lu))
			return out
		var loop := lu + ld
		for i in multimesh.instance_count:
			var s := fmod(t * speed + i * every, loop)
			out.append(_at(up, cum_up, s) if s < lu else _at(down, cum_down, s - lu))
		return out


class _Tick extends Node:
	func _process(delta: float) -> void:
		Skyline.tick(delta)


## One mesh's worth of thin things (a block's wires and fences), built on a worker.
class _Wires:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var count := 0

	## A wire from `a` to `b` sagging `sag` m in the middle, as a strip the shader turns to face the camera.
	func catenary(a: Vector3, b: Vector3, sag: float, radius: float, colour: Color) -> void:
		var steps := clampi(int(a.distance_to(b) / 25.0), 4, 16)
		var prev := a
		for i in range(1, steps + 1):
			var t := float(i) / steps
			var p := a.lerp(b, t)
			p.y -= sag * 4.0 * t * (1.0 - t)
			var dir := (p - prev).normalized()
			for corner in [[prev, -1.0], [p, -1.0], [p, 1.0], [prev, -1.0], [p, 1.0], [prev, 1.0]]:
				v.append(corner[0])
				n.append(dir)
				c.append(colour)
				uv.append(Vector2(corner[1], 0.0))
				uv2.append(Vector2(WIRE, radius))
			prev = p
		count += 1

	## A fence panel from `a` to `b` (on the ground), `h` tall.
	func panel(a: Vector3, b: Vector3, h: float, colour: Color) -> void:
		var up := Vector3(0, h, 0)
		var side := (b - a)
		var nrm := Vector3(-side.z, 0, side.x).normalized()
		for p in [a, b, b + up, a, b + up, a + up]:
			v.append(p)
			n.append(nrm)
			c.append(colour)
			uv.append(Vector2.ZERO)
			uv2.append(Vector2.ZERO)
		count += 1

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		return a


# ---------------------------------------------------------------------------- the models

## The mesh of `model` (built once).
static func mesh(model: String) -> Mesh:
	_meshes_lock.lock()
	var got = _meshes.get(model)
	_meshes_lock.unlock()
	if got != null:
		return got
	var b := _Build.new()
	match model:
		"turbine": _turbine(b)
		"pylon": _pylon(b, 46.0, 4.6, [23.5, 29.5, 35.5], [7.0, 6.5, 6.0], [GREY])
		"pylon_danube": _pylon_danube(b)
		"pylon_wide": _pylon_wide(b)
		"pylon_tall": _pylon(b, 62.0, 5.2, [33.0, 41.0, 49.0], [7.5, 7.0, 6.5], [Color(0.85, 0.2, 0.15), WHITE])
		"portal": _portal(b)
		"pole": _pole(b, 10.0, WOOD, 1)
		"pole_concrete": _pole(b, 12.0, CONCRETE, 2)
		"pole_tel": _pole_tel(b)
		"lift_pylon": _lift_pylon(b)
		"lift_station": _lift_station(b)
		"lift_terminal": _lift_terminal(b)
		"gondola", "chair", "tbar", "cable_car", "bucket": _cabin(b, model)
		"piste_pole": _piste_pole(b)
		"mast": _mast(b, 80.0)
		"tv_tower": _tv_tower(b)
		"monopole": _monopole(b)
		"radar": _radar(b)
		"lookout": _lookout(b)
		"watchtower": _watchtower(b)
		"round_tower": _round_tower(b)
		"campanile": _campanile(b)
		"bell_pavilion": _bell_pavilion(b)
		"minaret": _minaret(b, "cone")
		"minaret_square": _minaret_square(b)
		"minaret_dome": _minaret(b, "dome")
		"floodlight": _floodlight(b)
		"silo": _silo(b, Color(0.72, 0.74, 0.75))
		"silo_blue": _silo(b, Color(0.12, 0.2, 0.35))
		"elevator": _elevator(b)
		"tank": _tank(b)
		"water_tower": _water_legs(b)
		"water_sphere": _water_sphere(b)
		"water_chalice": _water_chalice(b)
		"water_square": _water_square(b)
		"gasometer": _gasometer(b)
		"cooling": _cooling(b)
		"transformer": _transformer(b)
		"kiosk": b.box(Vector3(0, 1.4, 0), Vector3(3.0, 2.8, 2.4), Basis(), CONCRETE)
		"solar_row": _solar_row(b)
		"steam": return _steam_mesh()
		_: b.box(Vector3(0, 1.5, 0), Vector3(0.3, 3.0, 0.3), Basis(), RED)
	var m := b.commit(material())
	_meshes_lock.lock()
	_meshes[model] = m
	_meshes_lock.unlock()
	return m


## Builds a mesh of boxes, lathes and lamps: vertex coloured, its flags in UV2 (see ROTOR).
class _Build:
	var st := SurfaceTool.new()
	var any := false

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, flag := Vector2.ZERO, uv := Vector2.ZERO) -> void:
		var nrm := (b - a).cross(c - a).normalized()
		for p in [a, b, c]:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(uv)
			st.set_uv2(flag)
			st.add_vertex(p)
		any = true

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flag := Vector2.ZERO, uv := Vector2.ZERO) -> void:
		tri(a, b, c, col, flag, uv)
		tri(a, c, d, col, flag, uv)

	## A box centred `c`, `size`, turned by `basis`.
	func box(c: Vector3, size: Vector3, basis: Basis, col: Color, flag := Vector2.ZERO, uv := Vector2.ZERO) -> void:
		var h := size * 0.5
		var p := []
		for i in 8:
			p.append(c + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
		for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, flag, uv)

	## A square beam from `a` to `b`, `w` thick.
	func beam(a: Vector3, b: Vector3, w: float, col: Color) -> void:
		var d := b - a
		if d.length() < 1e-4:
			return
		var y := d.normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		box((a + b) * 0.5, Vector3(w, d.length(), w), Basis(x, y, z), col)

	## A lathe round the y axis through `at`: rings [[y, r], ...] (from the bottom), `sides` round, capped on top.
	func lathe(at: Vector3, rings: Array, sides: int, col: Color, cap := true, flag := Vector2.ZERO) -> void:
		for i in range(rings.size() - 1):
			var y0 := float(rings[i][0])
			var r0 := float(rings[i][1])
			var y1 := float(rings[i + 1][0])
			var r1 := float(rings[i + 1][1])
			for s in sides:
				var a0 := TAU * s / sides
				var a1 := TAU * (s + 1) / sides
				quad(at + Vector3(cos(a0) * r0, y0, sin(a0) * r0), at + Vector3(cos(a0) * r1, y1, sin(a0) * r1),
					at + Vector3(cos(a1) * r1, y1, sin(a1) * r1), at + Vector3(cos(a1) * r0, y0, sin(a1) * r0), col, flag)
		if cap:
			var top: Array = rings[rings.size() - 1]
			var yt := float(top[0])
			var rt := float(top[1])
			if rt > 0.0:
				for s in sides:
					var a0 := TAU * s / sides
					var a1 := TAU * (s + 1) / sides
					tri(at + Vector3(0, yt, 0), at + Vector3(cos(a1) * rt, yt, sin(a1) * rt), at + Vector3(cos(a0) * rt, yt, sin(a0) * rt), col, flag)

	## A lamp at `at`, `size` across, that the shader turns to the camera and lights at night (`kind` BLINK or STEADY).
	func lamp(at: Vector3, size: float, kind: float, col: Color) -> void:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			st.set_normal(Vector3.UP)
			st.set_color(col)
			st.set_uv(corner)
			st.set_uv2(Vector2(kind, size))
			st.add_vertex(at)
		any = true

	func commit(mat: Material) -> Mesh:
		var m := st.commit() if any else ArrayMesh.new()
		if m.get_surface_count() > 0:
			m.surface_set_material(0, mat)
		return m


static func _turbine(b: _Build) -> void:
	# (a 100 m hub: scaled to the real one; the rotor faces -z, into the wind)
	b.lathe(Vector3.ZERO, [[0.0, 2.3], [96.0, 1.3]], 12, WHITE)
	b.box(Vector3(0, 100.0, 1.6), Vector3(3.4, 3.6, 10.0), Basis(), WHITE)
	var hub := Vector3(0, 100.0, -3.8)
	var spin := Vector2(ROTOR, 100.0)
	var sp := Vector2(-3.8, 0.0)
	b.box(hub, Vector3(2.6, 2.6, 2.4), Basis(), WHITE, spin, sp)
	for i in 3:
		var a := TAU * i / 3.0
		var dir := Vector3(sin(a), cos(a), 0.0)
		var side := Vector3(cos(a), -sin(a), 0.0)
		var root := hub + dir * 1.4 + Vector3(0, 0, -0.3)
		var tip := hub + dir * 58.0 + Vector3(0, 0, -0.6)
		var r0 := 1.9
		var r1 := 0.35
		# (a flat blade, a little thick so it reads edge on: the shader turns it with the hub)
		for t in [-0.18, 0.18]:
			b.quad(root - side * r0 + Vector3(0, 0, t), tip - side * r1 + Vector3(0, 0, t), tip + side * r1 + Vector3(0, 0, t),
				root + side * r0 + Vector3(0, 0, t), WHITE, spin, sp)
	b.lamp(Vector3(0, 102.2, 5.0), 0.9, BLINK, RED)


## A lattice pylon `h` tall (its legs `foot` m apart at the ground), arms at `arms` heights reaching `reach` out each
## side, in bands of `cols`.
static func _pylon(b: _Build, h: float, foot: float, arms: Array, reach: Array, cols: Array) -> void:
	var top_w := 1.1
	var body := float(arms[arms.size() - 1]) + 2.0
	var levels := 8
	var corner := func(y: float, sx: float, sz: float) -> Vector3:
		var w := lerpf(foot, top_w, clampf(y / body, 0.0, 1.0))
		return Vector3(sx * w, y, sz * w)
	for l in levels:
		var y0 := body * l / levels
		var y1 := body * (l + 1) / levels
		var col: Color = cols[l % cols.size()]
		for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
			b.beam(corner.call(y0, c[0], c[1]), corner.call(y1, c[0], c[1]), 0.35, col)
		for f in [[[1, 1], [1, -1]], [[1, -1], [-1, -1]], [[-1, -1], [-1, 1]], [[-1, 1], [1, 1]]]:
			b.beam(corner.call(y0, f[0][0], f[0][1]), corner.call(y1, f[1][0], f[1][1]), 0.12, col)
			b.beam(corner.call(y0, f[1][0], f[1][1]), corner.call(y1, f[0][0], f[0][1]), 0.12, col)
	b.beam(Vector3(0, body, 0), Vector3(0, h, 0), 0.3, cols[0])
	for i in arms.size():
		var y := float(arms[i])
		var r := float(reach[i])
		for s in [-1.0, 1.0]:
			b.beam(Vector3(s * 1.0, y, 0.6), Vector3(s * r, y, 0), 0.22, cols[0])
			b.beam(Vector3(s * 1.0, y, -0.6), Vector3(s * r, y, 0), 0.22, cols[0])
			b.beam(Vector3(s * r, y, 0), Vector3(s * r, y - 3.0, 0), 0.18, Color(0.75, 0.55, 0.4))


static func _pylon_danube(b: _Build) -> void:
	_pylon(b, 40.0, 4.2, [32.5], [6.5], [GREY])
	for s in [-1.0, 1.0]:
		b.beam(Vector3(s * 1.4, 29.0, 0.6), Vector3(s * 11.0, 29.0, 0), 0.24, GREY)
		b.beam(Vector3(s * 1.4, 29.0, -0.6), Vector3(s * 11.0, 29.0, 0), 0.24, GREY)
		for r in [5.5, 11.0]:
			b.beam(Vector3(s * r, 29.0, 0), Vector3(s * r, 26.0, 0), 0.18, Color(0.75, 0.55, 0.4))


static func _pylon_wide(b: _Build) -> void:
	# (a portal of two tapering legs with a beam across: the long lines of the Americas, the north and the south)
	for s in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			b.beam(Vector3(s * 6.5, 0, z * 2.5), Vector3(s * 4.0, 24.0, z * 0.6), 0.4, GREY)
		b.beam(Vector3(s * 4.0, 24.0, 0), Vector3(s * 6.0, 30.0, 0), 0.3, GREY)
	b.beam(Vector3(-11.0, 24.0, 0), Vector3(11.0, 24.0, 0), 0.7, GREY)
	for x in [-9.0, 0.0, 9.0]:
		b.beam(Vector3(x, 24.0, 0), Vector3(x, 20.5, 0), 0.2, Color(0.75, 0.55, 0.4))


static func _portal(b: _Build) -> void:
	for s in [-1.0, 1.0]:
		b.beam(Vector3(s * 5.5, 0, 0), Vector3(s * 5.5, 16.0, 0), 0.5, GREY)
	b.beam(Vector3(-6.0, 15.5, 0), Vector3(6.0, 15.5, 0), 0.5, GREY)
	for x in [-4.0, 0.0, 4.0]:
		b.beam(Vector3(x, 15.5, 0), Vector3(x, 14.5, 0), 0.15, Color(0.75, 0.55, 0.4))


static func _pole(b: _Build, h: float, col: Color, arms: int) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 0.16], [h, 0.12]], 6, col)
	b.box(Vector3(0, h - 0.4, 0), Vector3(2.4, 0.12, 0.12), Basis(), WOOD if col == WOOD else GREY)
	for x in [-1.0, 0.0, 1.0]:
		b.box(Vector3(x, h - 0.4 + (0.4 if x == 0.0 else 0.0) + 0.1, 0), Vector3(0.1, 0.25, 0.1), Basis(), Color(0.6, 0.65, 0.6))
	if arms > 1:
		b.box(Vector3(0, h - 2.4, 0), Vector3(1.8, 0.12, 0.12), Basis(), GREY)
		b.box(Vector3(0.3, h - 4.0, 0.4), Vector3(0.7, 1.0, 0.6), Basis(), GREY)


static func _pole_tel(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 0.13], [8.0, 0.1]], 6, WOOD)
	b.box(Vector3(0, 7.6, 0), Vector3(1.0, 0.1, 0.1), Basis(), WOOD)


static func _lift_pylon(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 0.5], [14.0, 0.35]], 8, GREY)
	b.box(Vector3(0, 14.6, 0), Vector3(6.0, 0.5, 0.6), Basis(), GREY)
	for s in [-1.0, 1.0]:
		b.box(Vector3(s * 2.6, 14.9, 0), Vector3(0.4, 0.3, 3.0), Basis(), DARK)


static func _lift_station(b: _Build) -> void:
	b.box(Vector3(0, 3.5, 4.0), Vector3(12.0, 7.0, 14.0), Basis(), Color(0.55, 0.5, 0.45))
	b.box(Vector3(0, 7.4, 4.0), Vector3(13.0, 0.8, 15.0), Basis(), Color(0.35, 0.36, 0.38))
	b.lathe(Vector3(0, 7.0, -3.0), [[-0.2, 2.8], [0.2, 2.8]], 14, DARK)


static func _lift_terminal(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 0.5], [5.2, 0.4]], 8, GREY)
	b.lathe(Vector3(0, 5.5, 0), [[-0.15, 2.1], [0.15, 2.1]], 12, DARK)


static func _cabin(b: _Build, model: String) -> void:
	# (hung from the rope at y 0)
	match model:
		"gondola":
			b.box(Vector3(0, -0.8, 0), Vector3(0.12, 1.6, 0.12), Basis(), DARK)
			b.box(Vector3(0, -2.8, 0), Vector3(2.0, 2.2, 2.0), Basis(), Color(0.8, 0.12, 0.1))
			b.box(Vector3(0, -2.5, 0), Vector3(2.04, 0.9, 1.6), Basis(), Color(0.25, 0.35, 0.45))
		"cable_car":
			b.box(Vector3(0, -2.0, 0), Vector3(0.25, 4.0, 0.25), Basis(), DARK)
			b.box(Vector3(0, -5.6, 0), Vector3(3.6, 3.2, 6.0), Basis(), Color(0.85, 0.85, 0.82))
			b.box(Vector3(0, -5.2, 0), Vector3(3.64, 1.4, 5.4), Basis(), Color(0.25, 0.35, 0.45))
		"chair":
			b.box(Vector3(0, -1.6, 0), Vector3(0.1, 3.2, 0.1), Basis(), DARK)
			b.box(Vector3(0, -3.2, 0), Vector3(2.4, 0.12, 0.6), Basis(), DARK)
			b.box(Vector3(0, -2.8, 0.3), Vector3(2.4, 0.8, 0.08), Basis(), Color(0.15, 0.3, 0.6))
		"tbar":
			b.box(Vector3(0, -2.0, 0), Vector3(0.08, 4.0, 0.08), Basis(), DARK)
			b.box(Vector3(0, -4.0, 0), Vector3(1.0, 0.08, 0.08), Basis(), DARK)
		_:
			b.box(Vector3(0, -0.8, 0), Vector3(0.08, 1.6, 0.08), Basis(), DARK)
			b.box(Vector3(0, -2.0, 0), Vector3(1.0, 0.8, 1.0), Basis(), GREY)


static func _piste_pole(b: _Build) -> void:
	b.box(Vector3(0, 1.0, 0), Vector3(0.08, 2.0, 0.08), Basis(), Color(0.95, 0.45, 0.05))
	b.box(Vector3(0, 1.85, 0), Vector3(0.09, 0.3, 0.09), Basis(), DARK)


static func _mast(b: _Build, h: float) -> void:
	var w := 1.2
	var levels := 12
	var corners := [Vector3(w, 0, 0), Vector3(-w * 0.5, 0, w * 0.866), Vector3(-w * 0.5, 0, -w * 0.866)]
	for l in levels:
		var y0 := h * l / levels
		var y1 := h * (l + 1) / levels
		for i in 3:
			var a: Vector3 = corners[i]
			var c: Vector3 = corners[(i + 1) % 3]
			var col := Color(0.85, 0.2, 0.15) if l % 2 == 0 else WHITE
			b.beam(a + Vector3(0, y0, 0), a + Vector3(0, y1, 0), 0.18, col)
			b.beam(a + Vector3(0, y0, 0), c + Vector3(0, y1, 0), 0.06, col)
	b.beam(Vector3(0, h, 0), Vector3(0, h * 1.1, 0), 0.2, GREY)
	b.lamp(Vector3(0, h * 1.1 + 0.4, 0), 0.9, BLINK, RED)
	b.lamp(Vector3(w, h * 0.5, 0), 0.7, STEADY, RED)


static func _tv_tower(b: _Build) -> void:
	# (a 200 m concrete tower with a pod at three quarters up: scaled to the mapped height)
	b.lathe(Vector3.ZERO, [[0.0, 7.0], [20.0, 4.5], [150.0, 3.2]], 14, CONCRETE)
	b.lathe(Vector3(0, 0, 0), [[140.0, 3.2], [146.0, 12.0], [156.0, 12.0], [160.0, 3.2]], 16, CONCRETE)
	b.lathe(Vector3.ZERO, [[150.0, 3.0], [200.0, 0.6]], 8, Color(0.85, 0.2, 0.15))
	b.lamp(Vector3(0, 200.5, 0), 1.2, BLINK, RED)
	b.lamp(Vector3(12.2, 156.0, 0), 1.0, STEADY, RED)


static func _monopole(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 0.6], [25.0, 0.35]], 8, GREY)
	for i in 3:
		var a := TAU * i / 3.0
		var at := Vector3(cos(a) * 1.0, 24.0, sin(a) * 1.0)
		b.box(at, Vector3(0.35, 2.4, 0.35), Basis(Vector3.UP, -a), Color(0.85, 0.85, 0.82))
	b.box(Vector3(0, 23.0, 0), Vector3(2.4, 0.2, 2.4), Basis(), GREY)


static func _radar(b: _Build) -> void:
	_mast(b, 25.0)
	b.lathe(Vector3(0, 27.5, 0), [[-5.0, 0.1], [-4.3, 2.5], [-2.5, 4.3], [0.0, 5.0], [2.5, 4.3], [4.3, 2.5], [5.0, 0.0]], 12, WHITE)


static func _lookout(b: _Build) -> void:
	for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
		b.beam(Vector3(c[0] * 3.0, 0, c[1] * 3.0), Vector3(c[0] * 1.6, 24.0, c[1] * 1.6), 0.4, WOOD)
	for y in [6.0, 12.0, 18.0]:
		b.box(Vector3(0, y, 0), Vector3(4.6, 0.25, 4.6), Basis(), WOOD)
	b.box(Vector3(0, 24.0, 0), Vector3(4.4, 0.3, 4.4), Basis(), WOOD)
	b.box(Vector3(0, 24.6, 2.1), Vector3(4.4, 1.0, 0.1), Basis(), WOOD)
	b.box(Vector3(0, 24.6, -2.1), Vector3(4.4, 1.0, 0.1), Basis(), WOOD)
	b.lathe(Vector3(0, 26.5, 0), [[0.0, 3.4], [1.6, 0.0]], 4, Color(0.3, 0.22, 0.16))


static func _watchtower(b: _Build) -> void:
	for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
		b.beam(Vector3(c[0] * 1.6, 0, c[1] * 1.6), Vector3(c[0] * 1.3, 7.0, c[1] * 1.3), 0.25, WOOD)
	b.box(Vector3(0, 8.0, 0), Vector3(3.0, 2.0, 3.0), Basis(), WOOD)
	b.lathe(Vector3(0, 9.0, 0), [[0.0, 2.4], [1.2, 0.0]], 4, Color(0.3, 0.22, 0.16))


static func _round_tower(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 4.6], [14.0, 4.0]], 16, STONE)
	for i in 8:
		var a := TAU * i / 8.0
		b.box(Vector3(cos(a) * 3.8, 14.6, sin(a) * 3.8), Vector3(1.2, 1.2, 1.2), Basis(Vector3.UP, -a), STONE)


static func _campanile(b: _Build) -> void:
	b.box(Vector3(0, 9.0, 0), Vector3(5.0, 18.0, 5.0), Basis(), STONE)
	b.box(Vector3(0, 20.0, 0), Vector3(5.2, 4.0, 5.2), Basis(), STONE.darkened(0.25))
	b.lathe(Vector3(0, 22.0, 0), [[0.0, 3.7], [5.0, 0.0]], 4, Color(0.55, 0.3, 0.22))


static func _bell_pavilion(b: _Build) -> void:
	for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
		b.beam(Vector3(c[0] * 1.8, 0, c[1] * 1.8), Vector3(c[0] * 1.8, 4.5, c[1] * 1.8), 0.35, Color(0.45, 0.15, 0.1))
	b.lathe(Vector3(0, 4.5, 0), [[0.0, 4.2], [0.6, 3.6], [2.4, 0.0]], 4, Color(0.25, 0.25, 0.27))
	b.lathe(Vector3(0, 2.4, 0), [[0.0, 0.9], [1.6, 0.7]], 10, Color(0.35, 0.3, 0.2))


static func _minaret(b: _Build, top: String) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 2.0], [3.0, 1.7], [24.0, 1.5]], 12, Color(0.88, 0.86, 0.8))
	b.lathe(Vector3(0, 0, 0), [[23.5, 1.5], [24.2, 2.4], [24.8, 2.4]], 12, Color(0.85, 0.83, 0.78))
	b.lathe(Vector3.ZERO, [[24.8, 1.2], [28.0, 1.1]], 12, Color(0.88, 0.86, 0.8))
	if top == "dome":
		b.lathe(Vector3(0, 28.0, 0), [[0.0, 1.5], [1.0, 1.4], [1.8, 0.9], [2.4, 0.0]], 12, WHITE)
	else:
		b.lathe(Vector3(0, 28.0, 0), [[0.0, 1.3], [6.0, 0.0]], 12, Color(0.35, 0.4, 0.45))
	b.lamp(Vector3(0, 24.9, 2.3), 0.35, STEADY, Color(0.4, 1.0, 0.5))


static func _minaret_square(b: _Build) -> void:
	b.box(Vector3(0, 11.0, 0), Vector3(4.5, 22.0, 4.5), Basis(), Color(0.85, 0.78, 0.62))
	b.box(Vector3(0, 22.5, 0), Vector3(4.9, 1.0, 4.9), Basis(), Color(0.15, 0.45, 0.35))
	b.box(Vector3(0, 25.0, 0), Vector3(2.0, 4.0, 2.0), Basis(), Color(0.85, 0.78, 0.62))
	b.lathe(Vector3(0, 27.0, 0), [[0.0, 1.0], [0.8, 0.8], [1.4, 0.0]], 8, Color(0.15, 0.45, 0.35))


static func _floodlight(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 0.5], [25.0, 0.3]], 8, GREY)
	b.box(Vector3(0, 25.5, 0), Vector3(4.0, 2.0, 0.4), Basis(), DARK)
	for x in [-1.4, 0.0, 1.4]:
		for y in [24.9, 26.1]:
			b.lamp(Vector3(x, y, -0.3), 0.5, STEADY, LAMP_WHITE)


static func _silo(b: _Build, col: Color) -> void:
	# (unit radius 3.5, 18 m tall: an area scales it to its own)
	b.lathe(Vector3.ZERO, [[0.0, 3.5], [18.0, 3.5]], 14, col, false)
	b.lathe(Vector3(0, 18.0, 0), [[0.0, 3.6], [2.4, 0.4]], 14, col.darkened(0.15))


static func _elevator(b: _Build) -> void:
	# (a prairie grain elevator: a bank of concrete bins with a headhouse)
	for i in 4:
		b.lathe(Vector3(-6.0 + i * 4.0, 0, 0), [[0.0, 2.0], [30.0, 2.0]], 10, CONCRETE, true)
	b.box(Vector3(0, 30.5, 0), Vector3(16.0, 1.0, 4.4), Basis(), CONCRETE)
	b.box(Vector3(2.0, 36.0, 0), Vector3(5.0, 10.0, 4.0), Basis(), CONCRETE)


static func _tank(b: _Build) -> void:
	# (unit radius and height: sized to its area)
	b.lathe(Vector3.ZERO, [[0.0, 1.0], [1.0, 1.0]], 18, Color(0.88, 0.88, 0.86), false)
	b.lathe(Vector3(0, 1.0, 0), [[0.0, 1.0], [0.08, 0.0]], 18, Color(0.8, 0.8, 0.78))


static func _water_legs(b: _Build) -> void:
	for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
		b.beam(Vector3(c[0] * 3.6, 0, c[1] * 3.6), Vector3(c[0] * 2.6, 22.0, c[1] * 2.6), 0.4, GREY)
	b.lathe(Vector3(0, 22.0, 0), [[0.0, 4.5], [7.0, 4.5]], 14, Color(0.6, 0.66, 0.68))
	b.lathe(Vector3(0, 29.0, 0), [[0.0, 4.6], [1.6, 0.0]], 14, Color(0.5, 0.55, 0.58))


static func _water_sphere(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 1.4], [26.0, 1.0]], 10, Color(0.85, 0.87, 0.88))
	var rings := []
	for i in 9:
		var a := PI * i / 8.0
		rings.append([30.0 - cos(a) * 6.0, sin(a) * 6.0 + 0.01])
	b.lathe(Vector3.ZERO, rings, 16, Color(0.85, 0.87, 0.88))


static func _water_chalice(b: _Build) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 2.6], [20.0, 2.0], [26.0, 8.0], [32.0, 8.5], [33.0, 0.5]], 16, CONCRETE)


static func _water_square(b: _Build) -> void:
	for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
		b.box(Vector3(c[0] * 3.0, 9.0, c[1] * 3.0), Vector3(0.9, 18.0, 0.9), Basis(), CONCRETE)
	b.box(Vector3(0, 21.0, 0), Vector3(9.0, 6.0, 9.0), Basis(), CONCRETE)


static func _gasometer(b: _Build) -> void:
	# (unit radius 25, 35 m tall)
	for i in 12:
		var a := TAU * i / 12.0
		b.beam(Vector3(cos(a) * 25.0, 0, sin(a) * 25.0), Vector3(cos(a) * 25.0, 35.0, sin(a) * 25.0), 0.8, Color(0.3, 0.33, 0.36))
	for y in [12.0, 24.0, 35.0]:
		for i in 12:
			var a0 := TAU * i / 12.0
			var a1 := TAU * (i + 1) / 12.0
			b.beam(Vector3(cos(a0) * 25.0, y, sin(a0) * 25.0), Vector3(cos(a1) * 25.0, y, sin(a1) * 25.0), 0.5, Color(0.3, 0.33, 0.36))
	b.lathe(Vector3.ZERO, [[0.0, 23.5], [20.0, 23.5], [22.0, 18.0]], 18, Color(0.45, 0.3, 0.22))


static func _cooling(b: _Build) -> void:
	# (a hyperboloid 100 m tall: scaled to the mapped height or its area)
	b.lathe(Vector3.ZERO, [[0.0, 40.0], [20.0, 34.0], [45.0, 28.5], [75.0, 26.0], [90.0, 27.0], [100.0, 28.5]], 24, CONCRETE, false)
	b.lathe(Vector3.ZERO, [[99.0, 27.8], [6.0, 39.0]], 24, CONCRETE.darkened(0.3), false)
	b.lamp(Vector3(28.6, 100.5, 0), 1.2, BLINK, RED)
	b.lamp(Vector3(-28.6, 100.5, 0), 1.2, BLINK, RED)


static func _transformer(b: _Build) -> void:
	b.box(Vector3(0, 0.3, 0), Vector3(5.0, 0.6, 3.6), Basis(), CONCRETE)
	b.box(Vector3(0, 2.0, 0), Vector3(3.6, 2.8, 2.4), Basis(), Color(0.45, 0.5, 0.45))
	for x in [-1.0, 0.0, 1.0]:
		b.lathe(Vector3(x, 3.4, 0), [[0.0, 0.2], [1.8, 0.12]], 6, Color(0.6, 0.35, 0.25))
	for z in [-1.4, 1.4]:
		b.box(Vector3(0, 2.0, z), Vector3(3.2, 2.2, 0.3), Basis(), Color(0.35, 0.38, 0.36))


static func _solar_row(b: _Build) -> void:
	# (a table 20 m long, 4 m deep, tilted 25 degrees to face +z)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-25.0))
	b.box(Vector3(0, 1.6, 0), Vector3(20.0, 0.08, 4.0), tilt, Color(0.08, 0.1, 0.18))
	for x in [-9.0, -3.0, 3.0, 9.0]:
		b.box(Vector3(x, 0.8, -1.0), Vector3(0.1, 2.2, 0.1), Basis(), GREY)
		b.box(Vector3(x, 0.5, 1.0), Vector3(0.1, 1.2, 0.1), Basis(), GREY)


## The steam over a cooling tower: soft columns that billow and drift, lit by the day.
static func _steam_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := PI * i / 3.0
		var x := Vector3(cos(a), 0, sin(a))
		var rows := 6
		for r in rows:
			var y0 := 96.0 + 26.0 * r
			var y1 := y0 + 26.0
			var w0 := 26.0 + 9.0 * r
			var w1 := w0 + 9.0
			var drift0 := Vector3(6.0 * r * r * 0.3, 0, 3.0 * r)
			var drift1 := Vector3(6.0 * (r + 1) * (r + 1) * 0.3, 0, 3.0 * (r + 1))
			var v0 := float(r) / rows
			var v1 := float(r + 1) / rows
			var quad := [[drift0 - x * w0 + Vector3(0, y0, 0), Vector2(0, v0)], [drift1 - x * w1 + Vector3(0, y1, 0), Vector2(0, v1)],
				[drift1 + x * w1 + Vector3(0, y1, 0), Vector2(1, v1)], [drift0 + x * w0 + Vector3(0, y0, 0), Vector2(1, v0)]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(quad[k][1])
				st.add_vertex(quad[k][0])
	var m := st.commit()
	m.surface_set_material(0, _steam_material())
	_meshes_lock.lock()
	_meshes["steam"] = m
	_meshes_lock.unlock()
	return m


# ---------------------------------------------------------------------------- the shaders

static func material() -> ShaderMaterial:
	if _material == null:
		var s := Shader.new()
		s.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = s
	return _material


static func _steam_material() -> ShaderMaterial:
	if _steam == null:
		var s := Shader.new()
		s.code = STEAM_SHADER
		_steam = ShaderMaterial.new()
		_steam.shader = s
	return _steam


const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float spin = 0.0;    // the rotors' angle (rad), the same for every turbine
uniform float night = 0.0;   // 0 by day .. 1 with the lamps on (Daylight.lamps)
uniform float blink = 1.0;   // the aviation lamps' flash, by the clock
varying float glow;

void vertex() {
	glow = 0.0;
	float flag = UV2.x;
	if (flag > 0.5 && flag < 1.5) {
		// A rotor's part: turned about the hub (0, UV2.y, UV.x) round z.
		vec3 c = vec3(0.0, UV2.y, UV.x);
		vec3 p = VERTEX - c;
		float s = sin(spin);
		float k = cos(spin);
		VERTEX = c + vec3(p.x * k - p.y * s, p.x * s + p.y * k, p.z);
		NORMAL = vec3(NORMAL.x * k - NORMAL.y * s, NORMAL.x * s + NORMAL.y * k, NORMAL.z);
	} else if (flag > 1.5 && flag < 3.5) {
		// A lamp: a square to the camera, kept a few pixels across however far, lit only at night.
		float on = flag < 2.5 ? night * blink : night;
		vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float size = max(UV2.y, -c.z * 0.002) * step(0.01, on);
		c.xy += UV * size;
		POSITION = PROJECTION_MATRIX * c;
		glow = on;
	} else if (flag > 3.5) {
		// A wire: a strip across the camera's view of it, at least about a pixel wide.
		vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		vec3 d = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 side = normalize(cross(d, c.xyz));
		float w = max(UV2.y, -c.z * 0.0009);
		c.xyz += side * UV.x * w;
		POSITION = PROJECTION_MATRIX * c;
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
}

void fragment() {
	if (glow > 0.0) {
		ALBEDO = vec3(0.0);
		EMISSION = COLOR.rgb * 8.0 * glow;
	} else {
		ALBEDO = COLOR.rgb;
	}
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
"""

const STEAM_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;

uniform float night = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float n = noise(vec2(uv.x * 4.0, uv.y * 3.0 - TIME * 0.12)) * 0.6 + noise(vec2(uv.x * 9.0, uv.y * 7.0 - TIME * 0.2)) * 0.4;
	float edge = sin(uv.x * 3.14159);
	float fade = (1.0 - uv.y) * smoothstep(0.0, 0.08, uv.y);
	ALBEDO = mix(vec3(0.92), vec3(0.08, 0.09, 0.11), night);
	ALPHA = clamp(edge * edge * fade * (n * 1.4 - 0.2), 0.0, 1.0) * 0.8;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
