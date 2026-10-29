class_name WaterWorks
extends RefCounted
## Water and coast (Ride Anywhere v2, phase D round 1, D3: interfaces/scenery.md): dam walls across their valleys,
## waterfalls with their plume, weirs, canal locks with their gates and balance beams and a boat in the chamber,
## narrowboats moored along the canals with a towpath, aqueducts, harbour walls and breakwaters, piers on their legs,
## quays with bollards and boats along them, marinas of pontoons and yachts, fish passes, boardwalks, moats, hot springs
## and geysers steaming, blowholes spouting when the weather's up.
##
## The streamer (SceneryStreamer) hands lay_out a block's rows of the kinds whose kit row names this script, each with
## its kit (the default with the place's region laid over it), and draws what comes back: every model one MultiMesh a
## block. Everything is built of a few unit pieces (a block of stone, a wedge, an arch, a sheet of falling water) stood
## and stretched by its transform, so a dam a kilometre long is a few hundred instances of one mesh, not a mesh of its
## own. What moves (a geyser's jet, a blowhole's spout) and the lamps that come on at dusk are put in by dress, on the
## main thread; a jet keeps the crew's clock (Daylight's hours, set by the host), so every rider sees the same eruption.
##
## Simon's first rule, as here: nothing is put on a road or its verge (every piece's middle is checked against the
## roads: SceneryStreamer.off_road's CLEAR past the verge), a dam a road runs along stands under the road's surface,
## an aqueduct over a road clears it by the bridges' headroom (RoadNet.HEADROOM) or leaves the span out, and nothing
## here has collision. The second: every kind wherever the map has it, its look by region from the kit library's rows,
## with a default for anywhere a region has none; nothing is keyed to a place.

## Part of what a block lays out: bump it with the look (SceneryStreamer folds the scripts' versions into its own).
const VERSION := 1
## Pieces along a line, every STEP metres of it (measured from its first point, so a line over two blocks meets itself).
const STEP := 8.0
## How far past a road's verge a piece's middle must be (m: SceneryStreamer.CLEAR's).
const CLEAR := 1.5
## A dam's wall from this high (m); lower, the line is a sill or a weir in all but name and is drawn as one.
const DAM_LEAST := 1.5
## A dam this many times longer than it's high, and over EMBANK_FROM high, is an earth embankment (grass slopes); a
## shorter one a concrete or masonry wall with its batter downstream.
const EMBANK_RATIO := 6.0
const EMBANK_FROM := 4.0
## A dam's crest is at most this high above the lowest of its line (m).
const DAM_MOST := 300.0
## Clear under an aqueduct's deck over a road (m): the bridges' headroom.
const HEADROOM := 6.0
## A line longer than this (m) mapped as an aqueduct is a buried pipe across the land, not a bridge: left out.
const AQUEDUCT_MOST := 2000.0
## A pier this wide or more (m) is a solid stone one (a harbour pier), narrower one stands on legs.
const SOLID_PIER := 8.0
## A waterfall's drop where the map gives none and the land shows little (m), and the most it shows.
const FALL_LEAST := 2.0
const FALL_MOST := 60.0
## The sea's level in the region frame (m: heights are above sea level).
const SEA := 0.0
## At most this many boats a block (a marina's are many).
const BOATS_MOST := 160
## A geyser erupts once every PERIOD game minutes (each its own, by its id), for ERUPT of them.
const PERIOD := Vector2(24.0, 70.0)
const ERUPT := 0.18

## The stones and finishes the pieces come in (vertex colours).
const STONES := {
	"concrete": Color(0.64, 0.63, 0.6), "gritstone": Color(0.4, 0.38, 0.34), "sandstone": Color(0.6, 0.54, 0.44),
	"limestone": Color(0.78, 0.75, 0.68), "granite": Color(0.52, 0.5, 0.5), "basalt": Color(0.24, 0.24, 0.25),
	"laterite": Color(0.62, 0.42, 0.3), "brick": Color(0.52, 0.27, 0.2), "render": Color(0.88, 0.86, 0.8),
	"timber": Color(0.3, 0.22, 0.15), "rock": Color(0.44, 0.43, 0.41), "grass": Color(0.32, 0.43, 0.2),
	"gravel": Color(0.54, 0.5, 0.43), "sinter": Color(0.85, 0.8, 0.7), "black": Color(0.07, 0.07, 0.08),
	"white": Color(0.92, 0.92, 0.9), "steel": Color(0.32, 0.34, 0.36)}
## The narrowboats' and painted boats' colours, picked by each one's seed.
const LIVERIES := [Color(0.1, 0.3, 0.18), Color(0.5, 0.08, 0.1), Color(0.1, 0.18, 0.42), Color(0.32, 0.08, 0.16),
	Color(0.12, 0.35, 0.38), Color(0.55, 0.32, 0.08)]

static var _meshes := {}
static var _lock := Mutex.new()
static var _streams := {}   # RealRegion's instance id -> {Vector2i block -> PackedInt32Array of its streams}
static var _sheet_mat: ShaderMaterial
static var _foam_mat: ShaderMaterial
static var _steam_mat: ShaderMaterial
static var _lamp_mat: StandardMaterial3D
static var _red_mat: StandardMaterial3D
static var _green_mat: StandardMaterial3D


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of this script's rows (SceneryStreamer's: {"points": [[row, kit], ...], "lines": ...,
## "areas": ...}, in the region frame): {"items": {model: [Transform3D in the block's frame, its corner at key * SIZE]},
## "dress": the jets and lamps for dress}. Safe on a worker.
static func lay_out(n: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var b := _Block.new(n, key)
	var gates: Array = []   # the lock gates' middles (region frame), so a lock that has its own draws no more
	for pair: Array in rows.get("points", []):
		if str(pair[0][0]) == "lock_gate":
			gates.append(Vector2(float(pair[0][1]), float(pair[0][2])))
	for pair: Array in rows.get("lines", []):
		if str(pair[0][0]) == "lock_gate":
			var l: PackedVector2Array = pair[0][1]
			gates.append((l[0] + l[l.size() - 1]) * 0.5)
	for pair: Array in rows.get("points", []):
		var row: Array = pair[0]
		var k: Dictionary = pair[1]
		var p := Vector2(float(row[1]), float(row[2]))
		if not b.mine(p):
			continue
		match str(row[0]):
			"waterfall": _waterfall(b, p, row[3], k, str(row[7]))
			"rapids": _rapids(b, p, k)
			"weir": _weir_at(b, p, k)
			"lock_gate": _gates_at(b, p, row[5], k)
			"hot_spring": _spring(b, p, k, false, str(row[7]))
			"geyser": _spring(b, p, k, true, str(row[7]))
			"blowhole": _blowhole(b, p, k, str(row[7]))
			"dam", "pier", "breakwater", "quay", "groyne", "aqueduct", "boardwalk", "fish_pass":
				_marker(b, p, str(row[0]), k)
	for pair: Array in rows.get("lines", []):
		var row: Array = pair[0]
		var line: PackedVector2Array = row[1]
		if line.size() < 2:
			continue
		var k: Dictionary = pair[1]
		var id := str(row[6])
		var width = row[3]
		match str(row[0]):
			"dam": _dam(b, line, row[2], 0.0, k, id)
			"weir": _weir_line(b, line, k)
			"lock_gate": _gates_across(b, line, k)
			"breakwater": _harbour_wall(b, line, float(width) if width != null else 0.0, k, id)
			"groyne": _groyne(b, line, k)
			"pier": _pier(b, line, float(width) if width != null else 0.0, k, id)
			"quay": _quay(b, line, k, id, false)
			"aqueduct": _aqueduct(b, line, k)
			"boardwalk": _boardwalk(b, line, float(width) if width != null else 0.0, k)
			"fish_pass": _fish_pass(b, line, k)
			"rapids": _rapids_line(b, line, k)
	for pair: Array in rows.get("areas", []):
		var row: Array = pair[0]
		var ring: PackedVector2Array = row[1]
		if ring.size() < 3:
			continue
		var k: Dictionary = pair[1]
		var id := str(row[5])
		match str(row[0]):
			"dam":
				var ax := axis(ring)
				_dam(b, ax["line"], row[2], float(ax["width"]), k, id)
			"breakwater":
				var ax := axis(ring)
				_harbour_wall(b, ax["line"], minf(float(ax["width"]), 40.0), k, id)
			"pier":
				var ax := axis(ring)
				_pier(b, ax["line"], minf(float(ax["width"]), 60.0), k, id)
			"quay": _quay(b, closed(ring), k, id, false)
			"dock": _quay(b, closed(ring), k, id, true)
			"canal_lock": _lock_chamber(b, ring, k, id, gates)
			"marina": _marina(b, ring, k, id)
			"moat": _revetment(b, closed(ring), k)
			"rapids": _rapids(b, centre(ring), k)
			"hot_spring": _spring(b, centre(ring), k, false, id)
			"geyser": _spring(b, centre(ring), k, true, id)
			"waterfall": _waterfall(b, centre(ring), row[2], k, id)
	_canals(b, rows)
	return {"items": b.items, "dress": b.dress}


## The jets and the lamps of a block laid out (lay_out's "dress"): on the main thread, once it's in the world.
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary or ((data as Dictionary).get("jets", []) as Array).is_empty() and not bool(data.get("lamps", false)):
		return
	var life := Life.new()
	life.name = "WaterLife"
	for j: Dictionary in data.get("jets", []):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh("jet")
		mi.position = j["at"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		life.add_child(mi)
		life.jets.append({"node": mi, "height": float(j["height"]), "period": float(j["period"]), "phase": float(j["phase"]),
			"wind": bool(j["wind"])})
	node.add_child(life)


## A block's laying out: where it is, the roads, what it has made so far.
class _Block:
	var n: RoadNet
	var key: Vector2i
	var corner: Vector2
	var box: Rect2
	var items := {}
	var dress := {"jets": [], "lamps": false}
	var memo := {}
	var boats := 0
	var terrain = null

	func _init(net: RoadNet, k: Vector2i) -> void:
		n = net
		key = k
		corner = Vector2(k) * RoadBlock.SIZE
		box = Rect2(corner, Vector2.ONE * RoadBlock.SIZE)
		terrain = net.dress.get("terrain") if net.dress is Dictionary else null

	## Whether region-frame `p` is this block's (each piece is the block's its middle is in).
	func mine(p: Vector2) -> bool:
		return box.has_point(p)

	## Adds an instance of `model` at `xf` (block frame).
	func put(model: String, xf: Transform3D) -> void:
		if not items.has(model):
			items[model] = []
		(items[model] as Array).append(xf)

	## The bare land at region-frame `p` (NAN beyond the land held).
	func bare(p: Vector2) -> float:
		return float(n.height.call(p.x, p.y))

	## The land as drawn at `p`, the roads' banks cut in (RoadNet.ground_at).
	func ground(p: Vector2) -> float:
		var h := bare(p)
		return n.ground_at(p.x, p.y, h, memo) if not is_nan(h) else h

	## The water's surface at `p`: a lake's or river's (the land cover's water, whose heights are its surface), the
	## sea's under the shore, NAN on dry land.
	func water(p: Vector2) -> float:
		var h := bare(p)
		if is_nan(h):
			return h
		if terrain != null and terrain.has_method("cover") and int(terrain.cover(p.x, p.y)) == RealPack.WATER:
			return h
		return WaterWorks.SEA if h <= WaterWorks.SEA + 0.3 else NAN

	## The road at `p` if it's within `pad` (m) past the verge of one: locate's (with its "y" when `heights`), {} where
	## none is.
	func road(p: Vector2, pad := WaterWorks.CLEAR, heights := false) -> Dictionary:
		if n._near(p.x, p.y).is_empty():
			return {}
		var on := n.locate(p.x, p.y, -1, false)
		if on.is_empty() or int(on["node"]) < 0 and absf(float(on["lat"])) >= float(on["width"]) * 0.5 + RoadNet.VERGE + pad:
			return {}
		# (its height only for a road that's there: the faired heights are the costly part)
		return n.locate(p.x, p.y, int(on["edge"]), true) if heights else on

	## Whether `p` is clear of every road (past its verge and CLEAR more).
	func clear(p: Vector2, pad := WaterWorks.CLEAR) -> bool:
		return road(p, pad).is_empty()

	## Region-frame (x, y, z) into the block's frame.
	func local(p: Vector2, y: float) -> Vector3:
		return Vector3(p.x - corner.x, y, p.y - corner.y)


# ---------------------------------------------------------------------------- the pieces, stood and stretched

## A unit piece (its middle at the bottom, x across, y up, z along: a block, a wedge, an arch) at `at` (block frame),
## its z along `f` (a unit direction on the ground), `size` (across, up, along) big.
static func piece(at: Vector3, f: Vector2, size: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3(f.y, 0.0, -f.x) * size.x, Vector3.UP * size.y, Vector3(f.x, 0.0, f.y) * size.z), at)


## A unit piece along a slope: from `a` to `b` (block frame, both at its bottom's middle), `w` across, `h` up, its
## sides kept upright (a sheared box, so pieces down a hill meet end to end).
static func slope(a: Vector3, b: Vector3, w: float, h: float) -> Transform3D:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var f := d.normalized() if d.length() > 1e-4 else Vector2(0, 1)
	return Transform3D(Basis(Vector3(f.y, 0.0, -f.x) * w, Vector3.UP * h, b - a), (a + b) * 0.5)


## A sheet of falling water from `top` to `bottom` (block frame), `w` wide along `across`.
static func sheet(top: Vector3, bottom: Vector3, across: Vector3, w: float) -> Transform3D:
	var x := across.normalized() * w
	var y := top - bottom
	return Transform3D(Basis(x, y, x.cross(y).normalized()), top)


## The heading (a unit direction on the ground) a row's heading in degrees clockwise from north gives.
static func heading(deg: float) -> Vector2:
	var t := deg_to_rad(deg)
	return Vector2(sin(t), -cos(t))


## The pieces of `line` (region frame) every STEP from its first point: [[a, b], ...], each the block's whose
## middle it is.
static func steps(b: _Block, line: PackedVector2Array, step := STEP) -> Array:
	var out := []
	for i in line.size() - 1:
		var p := line[i]
		var q := line[i + 1]
		var l := p.distance_to(q)
		if l < 0.05:
			continue
		var count := maxi(1, int(ceil(l / step)))
		for j in count:
			var a := p.lerp(q, float(j) / count)
			var c := p.lerp(q, float(j + 1) / count)
			if b.mine((a + c) * 0.5):
				out.append([a, c])
	return out


## The long axis of `ring` (an area's outline): {"line": its two ends, "width": across it}, from its points' spread.
static func axis(ring: PackedVector2Array) -> Dictionary:
	var c := centre(ring)
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	for p in ring:
		var d := p - c
		sxx += d.x * d.x
		sxz += d.x * d.y
		szz += d.y * d.y
	var t := 0.5 * atan2(2.0 * sxz, sxx - szz)
	var f := Vector2(cos(t), sin(t))
	var s := Vector2(-f.y, f.x)
	var lo := INF
	var hi := -INF
	var w0 := INF
	var w1 := -INF
	for p in ring:
		var d := p - c
		lo = minf(lo, d.dot(f))
		hi = maxf(hi, d.dot(f))
		w0 = minf(w0, d.dot(s))
		w1 = maxf(w1, d.dot(s))
	var mid := c + s * (w0 + w1) * 0.5
	return {"line": PackedVector2Array([mid + f * lo, mid + f * hi]), "width": w1 - w0, "dir": f, "middle": mid + f * (lo + hi) * 0.5,
		"length": hi - lo}


static func centre(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	return c / maxf(1.0, ring.size())


## `ring` with its first point again at the end.
static func closed(ring: PackedVector2Array) -> PackedVector2Array:
	var out := ring.duplicate()
	out.append(ring[0])
	return out


static func length(line: PackedVector2Array) -> float:
	var l := 0.0
	for i in line.size() - 1:
		l += line[i].distance_to(line[i + 1])
	return l


## A number from 0 to 1 for `what`, the same on every machine (the row's id and what it's for).
static func roll(what: String) -> float:
	return float(hash(what) & 0xffffff) / float(0xffffff)


## The kit's stone (a STONES name) for `field`, or `fallback`.
static func stone(k: Dictionary, field: String, fallback: String) -> String:
	var s := str(k.get(field, fallback))
	return s if STONES.has(s) else fallback


## Region-frame `p`'s side of a line that runs along `f` (the x of a piece: left as you go along f).
static func side_of(f: Vector2) -> Vector2:
	return Vector2(f.y, -f.x)


# ---------------------------------------------------------------------------- dams

## A dam along `line`: its crest at the lower of the land at its two ends (the valley it fills), or the mapped height
## above its lowest point where that's lower; a wall of concrete or masonry with its batter downstream, or for a long
## low one an earth embankment grassed both sides. Where a road runs along it the crest stays under the road's surface,
## and its parapets past the verge. A spillway's water runs down the face of a wall dam at one end.
static func _dam(b: _Block, line: PackedVector2Array, mapped, thick: float, k: Dictionary, id: String) -> void:
	var l := length(line)
	if l < 4.0:
		return
	var g0 := b.bare(line[0])
	var g1 := b.bare(line[line.size() - 1])
	if is_nan(g0) or is_nan(g1):
		return
	var lo := minf(g0, g1)
	for i in line.size():
		var g := b.bare(line[i])
		if not is_nan(g):
			lo = minf(lo, g)
	# (the low point along it, sampled: a line's few points may all stand on its banks)
	var s := 0.0
	while s < l:
		var g := b.bare(_along(line, s))
		if not is_nan(g):
			lo = minf(lo, g)
		s += 12.0
	var crest := minf(g0, g1)
	if mapped != null and float(mapped) > 0.0:
		crest = minf(crest, lo + float(mapped)) if crest - lo > DAM_LEAST else lo + float(mapped)
	elif crest - lo < DAM_LEAST:
		crest = lo + DAM_LEAST + 1.0
	crest = minf(crest, lo + DAM_MOST)
	var high := crest - lo
	if high < DAM_LEAST:
		return
	var embank := str(k.get("type", "")) == "embankment" or (str(k.get("type", "")) != "wall" and l > high * EMBANK_RATIO and high > EMBANK_FROM)
	var wall_stone := stone(k, "stone", "concrete")
	var crest_w := maxf(thick, maxf(4.0, high * 0.1)) if not embank else maxf(thick * 0.25, 8.0)
	# Downstream: the lower land a little way off its middle.
	var mid := _along(line, l * 0.5)
	var f0 := (_along(line, minf(l, l * 0.5 + 2.0)) - _along(line, maxf(0.0, l * 0.5 - 2.0))).normalized()
	var off := maxf(30.0, high)
	var down := 1.0 if b.bare(mid + side_of(f0) * off) < b.bare(mid - side_of(f0) * off) else -1.0
	var spill_at := l * (0.15 if roll(id + "spill") < 0.5 else 0.85)
	for st: Array in steps(b, line):
		var a: Vector2 = st[0]
		var c: Vector2 = st[1]
		var f := (c - a).normalized()
		var m := (a + c) * 0.5
		var seg := a.distance_to(c)
		var foot := minf(b.bare(a), b.bare(c))
		if is_nan(foot):
			continue
		foot = minf(foot, crest) - 2.0
		var top := crest
		var on := b.road(m, crest_w * 0.5, true)
		if not on.is_empty() and not is_nan(float(on["y"])):
			top = minf(top, float(on["y"]) - 0.6)
		if top - foot < 0.5:
			continue
		var h := top - foot
		var ds := side_of(f) * down   # (towards the downstream side)
		if embank:
			b.put("block:grass", piece(b.local(m, foot), f, Vector3(crest_w, h, seg + 0.05)))
			# (the slopes, 1 in 2.5 downstream and 1 in 3 up, the wedge's long side out from the crest's edge)
			var run_d := h * 2.5
			var run_u := h * 3.0
			b.put("wedge:grass", piece(b.local(m + ds * crest_w * 0.5, foot), f * down,
				Vector3(run_d, h, seg + 0.05)))
			b.put("wedge:" + stone(k, "face", "rock"), piece(b.local(m - ds * crest_w * 0.5, foot), f * (-1.0 if down > 0.0 else 1.0),
				Vector3(run_u, h, seg + 0.05)))
		else:
			b.put("block:" + wall_stone, piece(b.local(m, foot), f, Vector3(crest_w, h, seg + 0.05)))
			b.put("wedge:" + wall_stone, piece(b.local(m + ds * crest_w * 0.5, foot), f * (1.0 if down > 0.0 else -1.0),
				Vector3(h * 0.7, maxf(0.0, h - 1.0), seg + 0.05)))
			if on.is_empty():
				# (parapets either side of the crest)
				for side: float in [-1.0, 1.0]:
					var pp := m + side_of(f) * side * (crest_w * 0.5 - 0.3)
					if b.clear(pp):
						b.put("block:" + wall_stone, piece(b.local(pp, top), f, Vector3(0.5, 1.1, seg + 0.05)))
			var along := _distance_to(line, m)
			if absf(along - spill_at) < 6.0 and on.is_empty() and h > 4.0:
				# The spillway: water over the crest and down the face.
				var t0 := b.local(m + ds * (crest_w * 0.5 + 0.2), top - 0.6)
				var t1 := b.local(m + ds * (crest_w * 0.5 + h * 0.7), foot + 1.0)
				b.put("sheet", sheet(t0, t1, Vector3(f.x, 0, f.y), seg + 0.1))
				if absf(along - spill_at) < STEP * 0.5:
					b.put("foam", piece(b.local(m + ds * (crest_w * 0.5 + h * 0.75), foot + 2.2), f, Vector3(14.0, 1.0, 14.0)))
					b.put("steam", piece(b.local(m + ds * (crest_w * 0.5 + h * 0.75), foot + 2.0), f, Vector3(12.0, minf(16.0, h * 0.4), 12.0)))


## The point `s` m along `line`.
static func _along(line: PackedVector2Array, s: float) -> Vector2:
	var left := s
	for i in line.size() - 1:
		var l := line[i].distance_to(line[i + 1])
		if left <= l and l > 0.0:
			return line[i].lerp(line[i + 1], left / l)
		left -= l
	return line[line.size() - 1]


## How far along `line` the point of it nearest `p` is (m).
static func _distance_to(line: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var at := 0.0
	var run := 0.0
	for i in line.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			at = run + line[i].distance_to(q)
		run += line[i].distance_to(line[i + 1])
	return at


# ---------------------------------------------------------------------------- falls, rapids and weirs

## A waterfall at `p`: a white sheet over the lip, down the way the land falls most steeply, as far as the map's
## height says (or the land shows), with foam and a plume of spray at its foot.
static func _waterfall(b: _Block, p: Vector2, mapped, k: Dictionary, id: String) -> void:
	if not b.clear(p, 4.0):
		return
	var top := b.ground(p)
	if is_nan(top):
		return
	var best := INF
	var dir := Vector2(0, 1)
	var run := 6.0
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0)
		for r: float in [5.0, 10.0, 18.0, 30.0]:
			var g := b.bare(p + d * r)
			if not is_nan(g) and g < best:
				best = g
				dir = d
				run = r
	var drop := top - best if best < INF else 0.0
	if mapped != null and float(mapped) > 0.0:
		drop = float(mapped)
	drop = clampf(drop if drop > FALL_LEAST else FALL_LEAST, FALL_LEAST, FALL_MOST)
	var w := clampf(float(k.get("width", 4.0 + drop * 0.25)) * (0.75 + 0.5 * roll(id + "w")), 2.0, 40.0)
	var lean := minf(run * 0.3, drop * 0.15)
	var across := Vector3(-dir.y, 0.0, dir.x)
	var lip := b.local(p, top + 0.15)
	var foot := b.local(p + dir * maxf(1.0, lean), top - drop)
	if not b.clear(p + dir * lean, 2.0):
		return
	b.put("sheet", sheet(lip, foot, across, w))
	if drop > 6.0:
		# (a second sheet a little behind and narrower: the fall is thick, not a sheet of paper)
		b.put("sheet", sheet(lip - Vector3(dir.x, 0, dir.y) * 0.6, foot - Vector3(dir.x, 0, dir.y) * 0.4, across, w * 0.7))
	var pool := p + dir * (lean + 1.5)
	var pool_y := b.ground(pool)
	pool_y = maxf(top - drop, pool_y if not is_nan(pool_y) else top - drop)
	b.put("foam", piece(b.local(pool, pool_y + 0.3), dir, Vector3(w * 1.6, 1.0, w * 1.3 + 2.0)))
	b.put("steam", piece(b.local(pool, pool_y), dir, Vector3(w * 1.2 + 2.0, clampf(drop * 0.6, 3.0, 30.0), w * 1.0 + 2.0)))


## White water where the map has rapids: a patch of foam on the stream.
static func _rapids(b: _Block, p: Vector2, k: Dictionary) -> void:
	if not b.clear(p, 2.0):
		return
	var y := b.bare(p)
	if is_nan(y):
		return
	var s := _stream_near(b, p, 40.0)
	var f: Vector2 = s.get("dir", Vector2(0, 1))
	var w := float(s.get("half", 4.0)) * 2.0
	b.put("foam", piece(b.local(p, y + 0.05), f, Vector3(w, 1.0, maxf(8.0, w * 2.0))))


static func _rapids_line(b: _Block, line: PackedVector2Array, k: Dictionary) -> void:
	for st: Array in steps(b, line, 12.0):
		_rapids(b, (st[0] + st[1]) * 0.5, k)


## A weir at `p`: a low wall across the stream it's on, the water spilling over it in a short white sheet.
static func _weir_at(b: _Block, p: Vector2, k: Dictionary) -> void:
	var s := _stream_near(b, p, 30.0)
	if s.is_empty():
		return
	var f: Vector2 = s["dir"]
	var half := float(s["half"]) + 1.0
	var a := p + side_of(f) * half
	var c := p - side_of(f) * half
	_weir(b, a, c, k, f)


static func _weir_line(b: _Block, line: PackedVector2Array, k: Dictionary) -> void:
	for st: Array in steps(b, line):
		var a: Vector2 = st[0]
		var c: Vector2 = st[1]
		var s := _stream_near(b, (a + c) * 0.5, 40.0)
		var f: Vector2 = s.get("dir", side_of((c - a).normalized()))
		_weir(b, a, c, k, f)


## A weir's wall from `a` to `c` (across the stream), its water falling the way `flow` goes.
static func _weir(b: _Block, a: Vector2, c: Vector2, k: Dictionary, flow: Vector2) -> void:
	var m := (a + c) * 0.5
	if not b.clear(m, 2.0) or a.distance_to(c) < 0.5:
		return
	var y := b.bare(m)
	if is_nan(y):
		return
	var f := (c - a).normalized()
	var sill := y + 0.15
	b.put("block:" + stone(k, "stone", "concrete"), piece(b.local(m, y - 1.5), f, Vector3(1.0, sill - y + 1.5, a.distance_to(c))))
	var down := flow.normalized() * (1.0 if flow.dot(side_of(f)) >= 0.0 else 1.0)
	var t0 := b.local(m + down * 0.5, sill)
	var t1 := b.local(m + down * 1.4, y - 0.7)
	b.put("sheet", sheet(t0, t1, Vector3(f.x, 0, f.y), a.distance_to(c)))
	b.put("foam", piece(b.local(m + down * 3.0, y - 0.6), f, Vector3(4.0, 1.0, a.distance_to(c) + 1.0)))


## The nearest stream's line within `reach` of `p`: {"dir" (the way it runs there), "half" (half its width), "kind",
## "at"}; {} where none is.
static func _stream_near(b: _Block, p: Vector2, reach: float) -> Dictionary:
	var streams: Array = b.n.region.streams
	var best := reach * reach
	var out := {}
	var mine := _streams_of(b.n.region)
	var kb := RoadBlock.key_of(p.x, p.y)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i in mine.get(kb + Vector2i(dx, dz), PackedInt32Array()):
				var pts: PackedVector2Array = streams[i][1]
				for j in pts.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
					var d := q.distance_squared_to(p)
					if d < best and pts[j].distance_squared_to(pts[j + 1]) > 1e-4:
						best = d
						out = {"dir": (pts[j + 1] - pts[j]).normalized(), "at": q, "kind": int(streams[i][0]),
							"half": float(RealPack.STREAM_HALF[clampi(int(streams[i][0]), 0, 2)])}
	return out


## Region `r`'s streams filed by block (once a region, any thread).
static func _streams_of(r: RealRegion) -> Dictionary:
	var id := r.get_instance_id()
	_lock.lock()
	var have = _streams.get(id)
	_lock.unlock()
	if have is Dictionary:
		return have
	var out := {}
	for i in r.streams.size():
		var pts: PackedVector2Array = r.streams[i][1]
		var seen := {}
		for p in pts:
			var kb := RoadBlock.key_of(p.x, p.y)
			if seen.has(kb):
				continue
			seen[kb] = true
			var list: PackedInt32Array = out.get(kb, PackedInt32Array())
			list.append(i)
			out[kb] = list
	_lock.lock()
	if _streams.size() > 8:
		_streams.clear()
	_streams[id] = out
	_lock.unlock()
	return out


# ---------------------------------------------------------------------------- canals and locks

## A lock's chamber (the map's water area of it): stone walls down its long sides, its gates at either end where
## the map has none of its own, and a boat in it more often than not.
static func _lock_chamber(b: _Block, ring: PackedVector2Array, k: Dictionary, id: String, gates: Array) -> void:
	var ax := axis(ring)
	var mid: Vector2 = ax["middle"]
	if not b.mine(mid):
		return
	var f: Vector2 = ax["dir"]
	var l := float(ax["length"])
	var w := clampf(float(ax["width"]), 2.0, 30.0)
	var y := b.bare(mid)
	if is_nan(y) or l < 6.0:
		return
	var st := stone(k, "stone", "gritstone")
	for side: float in [-1.0, 1.0]:
		var at := mid + side_of(f) * side * (w * 0.5 + 0.5)
		if b.clear(at):
			b.put("block:" + st, piece(b.local(at, y - 3.0), f, Vector3(1.0, 4.1, l)))
			# (the coping, pale)
			b.put("block:limestone", piece(b.local(at, y + 1.1), f, Vector3(1.2, 0.15, l)))
	var own := false
	for g: Vector2 in gates:
		if Geometry2D.is_point_in_polygon(g, ring) or g.distance_to(mid) < l * 0.5 + 6.0 and absf((g - mid).dot(side_of(f))) < w:
			own = true
	if not own:
		for end: float in [-1.0, 1.0]:
			_gate_pair(b, mid + f * end * (l * 0.5 - 0.5), f * end, w, y, k)
	if roll(id + "boat") < float(k.get("busy", 0.65)):
		var boat := str(k.get("lock_boat", "narrowboat" if w < 5.0 else "motor"))
		var bl := float(BOAT_LENGTH.get(boat.get_slice(":", 0), 10.0))
		var scale := minf(1.0, (l - 3.0) / bl)
		if scale > 0.3:
			_boat(b, boat, mid, f, y - 0.9, id, scale)


## Lock gates at a point the map has: a mitred pair across the canal there.
static func _gates_at(b: _Block, p: Vector2, head, k: Dictionary) -> void:
	var s := _stream_near(b, p, 25.0)
	var f: Vector2
	if not s.is_empty():
		f = s["dir"]
	elif head != null:
		f = heading(float(head))
	else:
		return
	var y := b.bare(p)
	if is_nan(y):
		return
	_gate_pair(b, p, f, float(k.get("lock_width", 4.4)), y, k)


## Lock gates along a line the map draws across the canal.
static func _gates_across(b: _Block, line: PackedVector2Array, k: Dictionary) -> void:
	var a := line[0]
	var c := line[line.size() - 1]
	var m := (a + c) * 0.5
	if not b.mine(m) or a.distance_to(c) < 1.0:
		return
	var y := b.bare(m)
	if is_nan(y):
		return
	_gate_pair(b, m, side_of((c - a).normalized()), clampf(a.distance_to(c), 2.0, 30.0), y, k)


## A pair of gates across a canal `w` wide at `p`, the water running along `f`: two leaves meeting in a shallow V
## upstream, each with its balance beam swung back over the bank.
static func _gate_pair(b: _Block, p: Vector2, f: Vector2, w: float, y: float, k: Dictionary) -> void:
	if not b.clear(p, 3.0):
		return
	var s := side_of(f)
	var leaf := w * 0.52
	for side: float in [-1.0, 1.0]:
		var hinge := p + s * side * w * 0.5
		var tip := p + f * 0.6
		var along := (tip - hinge).normalized()
		b.put("block:timber", piece(b.local((hinge + tip) * 0.5, y - 2.5), along, Vector3(0.35, 3.7, leaf)))
		# (its beam: out over the bank from the hinge, black and white)
		var beam_end := hinge + s * side * 4.5 - f * 1.0
		b.put("block:black", piece(b.local((hinge + beam_end) * 0.5, y + 1.15), (beam_end - hinge).normalized(), Vector3(0.32, 0.32, hinge.distance_to(beam_end) + 0.3)))
		b.put("block:white", piece(b.local(beam_end, y + 1.15), (beam_end - hinge).normalized(), Vector3(0.34, 0.34, 0.9)))
		# (and a walkway on top)
		b.put("block:timber", piece(b.local((hinge + tip) * 0.5 - f * 0.3, y + 1.2), along, Vector3(0.5, 0.08, leaf)))


## The canals of the block (the region's streams of the canal kind): a towpath along one bank and, where the kit has
## them, boats moored along it now and then.
static func _canals(b: _Block, rows: Dictionary) -> void:
	var r := b.n.region
	var mine: PackedInt32Array = _streams_of(r).get(b.key, PackedInt32Array())
	if not Array(mine).any(func(i): return int(r.streams[i][0]) == 2):
		return
	# (the canals take the "canal" kind's own row, by the region of the block's middle)
	var mid := b.corner + Vector2.ONE * RoadBlock.SIZE * 0.5
	var k := SceneryStreamer.kit("canal", str(RegionKit.at_frame(r.frame_lat, r.frame_lon, mid.x, mid.y).get("region", "")))
	if k.is_empty() or str(k.get("model", "")).get_slice(":", 0) != "water_works":
		return
	var boat := str(k.get("boat", ""))
	var every := float(k.get("moor_every", 0.0))
	for i in mine:
		if int(r.streams[i][0]) != 2:
			continue
		var pts: PackedVector2Array = r.streams[i][1]
		if pts.size() < 2:
			continue
		var tag := "%d,%d" % [int(pts[0].x), int(pts[0].y)]
		var side := 1.0 if roll(tag + "towpath") < 0.5 else -1.0
		var half := float(RealPack.STREAM_HALF[2])
		var run := 0.0
		var next_boat := every * (0.3 + roll(tag + "first")) if every > 0.0 else INF
		for j in pts.size() - 1:
			var a := pts[j]
			var c := pts[j + 1]
			var l := a.distance_to(c)
			if l < 0.1:
				continue
			var f := (c - a) / l
			var count := maxi(1, int(ceil(l / 6.0)))
			for q in count:
				var s0 := a.lerp(c, float(q) / count)
				var s1 := a.lerp(c, float(q + 1) / count)
				var m := (s0 + s1) * 0.5
				var here := run + l * (q + 0.5) / count
				if not b.mine(m):
					continue
				var t0 := s0 + side_of(f) * side * (half + 1.6)
				var t1 := s1 + side_of(f) * side * (half + 1.6)
				if b.clear((t0 + t1) * 0.5, 4.0):
					var y0 := b.ground(t0)
					var y1 := b.ground(t1)
					if not is_nan(y0) and not is_nan(y1):
						b.put("block:gravel", slope(b.local(t0, y0 - 0.12), b.local(t1, y1 - 0.12), 2.2, 0.2))
				if here >= next_boat and boat != "":
					next_boat += every * (0.5 + roll(tag + str(int(here))))
					var at := m + side_of(f) * side * (half - 1.4)
					var wy := b.bare(m)
					if not is_nan(wy) and b.clear(at, 12.0):
						_boat(b, boat, at, f * (1.0 if roll(tag + str(int(here)) + "way") < 0.5 else -1.0), wy - 0.75, tag + str(int(here)))
			run += l


# ---------------------------------------------------------------------------- harbours and the shore

## A harbour wall or breakwater along `line`, `w` wide (the map's, or the kit's): a mound of rock armour with a
## concrete cap, a wall of dressed stone with its parapet (kit "build": "wall"), or concrete armour units (kit
## "build": "tetrapods"), standing out of the sea or a lake; a light at the end out in the water.
static func _harbour_wall(b: _Block, line: PackedVector2Array, w: float, k: Dictionary, id: String) -> void:
	var build := str(k.get("build", "mound"))
	if w <= 0.0:
		w = float(k.get("width", 8.0))
	w = clampf(w, 3.0, 40.0)
	var st := stone(k, "stone", "granite")
	var rise := float(k.get("rise", 3.0))
	for s: Array in steps(b, line):
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var m := (a + c) * 0.5
		if not b.clear(m, w * 0.5):
			continue
		var f := (c - a).normalized()
		var seg := a.distance_to(c) + 0.05
		var g := b.bare(m)
		if is_nan(g):
			continue
		var wl := b.water(m)
		var level := maxf(g, wl if not is_nan(wl) else g)
		var top := level + rise
		var foot := minf(g, level) - 2.0
		match build:
			"wall":
				b.put("block:" + st, piece(b.local(m, foot), f, Vector3(w, top - foot, seg)))
				var pp := m + side_of(f) * (w * 0.5 - 0.4) * (1.0 if roll(id + "parapet") < 0.5 else -1.0)
				b.put("block:" + st, piece(b.local(pp, top), f, Vector3(0.8, 1.4, seg)))
			"tetrapods":
				b.put("block:concrete", piece(b.local(m, foot), f, Vector3(w * 0.45, top - foot, seg)))
				for side: float in [-1.0, 1.0]:
					for t in 2:
						var tp := m + side_of(f) * side * (w * 0.28 + t * 1.6) + f * (t - 0.5) * 2.5
						b.put("tetrapod", piece(b.local(tp, top - 1.2 - t * 1.4), f.rotated(roll(id + str(tp)) * TAU), Vector3.ONE * 1.0))
			_:
				b.put("mound:" + stone(k, "armour", "rock"), piece(b.local(m, foot), f, Vector3(w, top - foot - 0.4, seg)))
				b.put("block:concrete", piece(b.local(m, top - 0.5), f, Vector3(minf(4.0, w * 0.4), 0.9, seg)))
	_harbour_light(b, line, id, rise)


## A light at the end of a harbour wall or pier that stands out in the water: red or green, lit at night.
static func _harbour_light(b: _Block, line: PackedVector2Array, id: String, rise: float) -> void:
	if length(line) < 40.0:
		return
	for end: Vector2 in [line[0], line[line.size() - 1]]:
		if not b.mine(end):
			continue
		var wl := b.water(end)
		if is_nan(wl) or not b.clear(end, 3.0):
			continue
		var other: Vector2 = line[line.size() - 1] if end == line[0] else line[0]
		if is_nan(b.water(other)) or b.bare(end) < b.bare(other):
			var y := maxf(b.bare(end), wl) + rise
			var colour := "red" if roll(id + "light") < 0.5 else "green"
			b.put("light_tower:" + colour, piece(b.local(end, y), Vector2(0, 1), Vector3.ONE))
			b.put("beacon:" + colour, piece(b.local(end, y), Vector2(0, 1), Vector3.ONE))
			b.dress["lamps"] = true


## A groyne down the beach: timber posts and planks, low.
static func _groyne(b: _Block, line: PackedVector2Array, k: Dictionary) -> void:
	var st := stone(k, "stone", "timber")
	for s: Array in steps(b, line, 4.0):
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var m := (a + c) * 0.5
		if not b.clear(m):
			continue
		var ya := b.ground(a)
		var yc := b.ground(c)
		if is_nan(ya) or is_nan(yc):
			continue
		b.put("block:" + st, slope(b.local(a, ya - 0.6), b.local(c, yc - 0.6), 0.35, 1.6))


## A pier along `line`, `w` wide: its deck a little above the highest of the land and the water along it, on legs in
## pairs with railings and lamps (lit at night), or a solid stone one where it's wide (SOLID_PIER) or the kit says.
static func _pier(b: _Block, line: PackedVector2Array, w: float, k: Dictionary, id: String) -> void:
	var l := length(line)
	if l < 3.0:
		return
	if w <= 0.0:
		w = float(k.get("width", 3.5))
	w = clampf(w, 1.5, 60.0)
	var deck := -INF
	var s := 0.0
	while s <= l:
		var p := _along(line, s)
		var g := b.bare(p)
		var wl := b.water(p)
		if not is_nan(g):
			deck = maxf(deck, maxf(g, wl if not is_nan(wl) else g))
		s += 6.0
	if deck == -INF:
		return
	deck += float(k.get("rise", 1.6))
	var solid := w >= SOLID_PIER or bool(k.get("solid", false))
	var st := stone(k, "stone", "granite")
	var wood := stone(k, "deck", "timber")
	var legs := stone(k, "legs", "steel")
	for p: Array in steps(b, line, 6.0):
		var a: Vector2 = p[0]
		var c: Vector2 = p[1]
		var m := (a + c) * 0.5
		var f := (c - a).normalized()
		var seg := a.distance_to(c) + 0.05
		if not b.clear(m, minf(w, 8.0) * 0.5):
			continue
		var g := b.bare(m)
		if is_nan(g):
			continue
		if solid:
			b.put("block:" + st, piece(b.local(m, minf(g, deck) - 2.0), f, Vector3(w, deck - minf(g, deck) + 2.0, seg)))
			continue
		b.put("block:" + wood, piece(b.local(m, deck - 0.45), f, Vector3(w, 0.45, seg)))
		if deck - g > 0.8:
			for side: float in [-1.0, 1.0]:
				var leg := m + side_of(f) * side * (w * 0.5 - 0.3)
				b.put("block:" + legs, piece(b.local(leg, g - 1.0), f, Vector3(0.4, deck - 0.45 - g + 1.0, 0.4)))
		for side: float in [-1.0, 1.0]:
			var rail := m + side_of(f) * side * (w * 0.5 - 0.05)
			b.put("block:" + stone(k, "rail", "white"), piece(b.local(rail, deck + 0.95), f, Vector3(0.08, 0.08, seg)))
			b.put("block:" + stone(k, "rail", "white"), piece(b.local(rail, deck), f, Vector3(0.08, 1.0, 0.08)))
		var along := _distance_to(line, m)
		if l > 30.0 and fposmod(along, 24.0) < 6.0:
			var lamp := m + side_of(f) * (w * 0.5 - 0.2) * (1.0 if int(along / 24.0) % 2 == 0 else -1.0)
			b.put("lamp_post", piece(b.local(lamp, deck), f, Vector3.ONE))
			b.put("lamp_head:white", piece(b.local(lamp, deck), f, Vector3.ONE))
			b.dress["lamps"] = true
	if solid:
		_harbour_light(b, line, id, deck - maxf(b.bare(line[0]), SEA))


## A quay along `line` (or a dock basin's edge, `dock`): a stone face down into the water, a kerb of granite with
## bollards along it, and boats moored against it now and then on the water's side.
static func _quay(b: _Block, line: PackedVector2Array, k: Dictionary, id: String, dock: bool) -> void:
	var st := stone(k, "stone", "granite")
	var boats: Array = k.get("boats", [])
	var run := 0.0
	for s: Array in steps(b, line, 6.0):
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var m := (a + c) * 0.5
		var f := (c - a).normalized()
		var seg := a.distance_to(c) + 0.05
		if not b.clear(m, 1.0):
			continue
		var g := b.ground(m)
		if is_nan(g):
			continue
		# (the water's side: the lower land a few metres off)
		var left := b.bare(m + side_of(f) * 8.0)
		var right := b.bare(m - side_of(f) * 8.0)
		var wside := 1.0 if (left if not is_nan(left) else INF) < (right if not is_nan(right) else INF) else -1.0
		var wp := m + side_of(f) * wside * 8.0
		var wl := b.water(wp)
		var top := maxf(g, (wl if not is_nan(wl) else g) + 1.2) + 0.15
		b.put("block:" + st, piece(b.local(m, top - 5.0), f, Vector3(1.4, 5.0, seg)))
		var along := _distance_to(line, m)
		if fposmod(along, 18.0) < 6.0:
			var bol := m - side_of(f) * wside * 0.4
			b.put("bollard", piece(b.local(bol, top), f, Vector3.ONE))
		if not is_nan(wl) and not boats.is_empty() and fposmod(along + 9.0, 30.0) < 6.0:
			var tag := id + str(int(along))
			if roll(tag) < float(k.get("busy", 0.55)):
				var kind := str(boats[int(roll(tag + "k") * boats.size()) % boats.size()])
				var bw := float(BOAT_BEAM.get(kind.get_slice(":", 0), 3.0))
				var at := m + side_of(f) * wside * (bw * 0.5 + 0.9)
				if b.clear(at, 6.0):
					_boat(b, kind, at, f * (1.0 if roll(tag + "w") < 0.5 else -1.0), wl, tag)


## A marina: pontoons out across its water every so often, and yachts and motor boats moored either side of them.
static func _marina(b: _Block, ring: PackedVector2Array, k: Dictionary, id: String) -> void:
	var ax := axis(ring)
	var f: Vector2 = ax["dir"]
	var s := side_of(f)
	var mid: Vector2 = ax["middle"]
	var l := float(ax["length"])
	var w := float(ax["width"])
	var boats: Array = k.get("boats", ["yacht", "motor"])
	if boats.is_empty():
		return
	var gap := 24.0
	var rows := int(l / gap)
	for r in rows + 1:
		var along := -l * 0.5 + (l - rows * gap) * 0.5 + r * gap
		var t := -w * 0.5
		while t < w * 0.5:
			var p := mid + f * along + s * t
			t += 4.0
			if not b.mine(p) or not Geometry2D.is_point_in_polygon(p, ring):
				continue
			var wl := b.water(p)
			if is_nan(wl) or not b.clear(p, 6.0):
				continue
			b.put("block:" + stone(k, "deck", "timber"), piece(b.local(p, wl + 0.25), s, Vector3(2.0, 0.3, 4.05)))
			for side: float in [-1.0, 1.0]:
				var tag := id + "%d,%d,%d" % [r, int(t), int(side)]
				if roll(tag) < float(k.get("busy", 0.7)) and b.boats < BOATS_MOST:
					var kind := str(boats[int(roll(tag + "k") * boats.size()) % boats.size()])
					var at := p + f * side * (float(BOAT_LENGTH.get(kind.get_slice(":", 0), 9.0)) * 0.5 + 1.3)
					if Geometry2D.is_point_in_polygon(at, ring) and not is_nan(b.water(at)):
						_boat(b, kind, at, f * side, b.water(at), tag)


## A moat's edge in stone, the water standing below it.
static func _revetment(b: _Block, ring: PackedVector2Array, k: Dictionary) -> void:
	var st := stone(k, "stone", "gritstone")
	for s: Array in steps(b, ring, 6.0):
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var m := (a + c) * 0.5
		if not b.clear(m):
			continue
		var g := b.ground(m)
		if is_nan(g):
			continue
		b.put("block:" + st, piece(b.local(m, g - 2.5), (c - a).normalized(), Vector3(0.9, 2.8, a.distance_to(c) + 0.05)))


## An aqueduct along `line`: its trough a little above the land at its ends (sloping from one to the other), carried across the low
## ground on arches; over a road a flat span with the bridges' headroom under it, or nothing where it hasn't room.
## A long one is a pipe in the ground (AQUEDUCT_MOST) and isn't drawn.
static func _aqueduct(b: _Block, line: PackedVector2Array, k: Dictionary) -> void:
	var l := length(line)
	if l > AQUEDUCT_MOST or l < 10.0:
		return
	var g0 := b.bare(line[0])
	var g1 := b.bare(line[line.size() - 1])
	if is_nan(g0) or is_nan(g1):
		return
	var st := stone(k, "stone", "sandstone")
	var span := float(k.get("span", 14.0))
	for s: Array in steps(b, line, span):
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var m := (a + c) * 0.5
		var f := (c - a).normalized()
		var seg := a.distance_to(c)
		var deck := lerpf(g0, g1, clampf(_distance_to(line, m) / l, 0.0, 1.0)) + 1.5
		var g := minf(b.bare(a), b.bare(c))
		if is_nan(g) or deck - g < 1.5:
			continue
		var on := b.road(m, seg * 0.5, true)
		if not on.is_empty():
			var ry := float(on["y"])
			if is_nan(ry) or deck - 1.6 < ry + HEADROOM:
				continue
			b.put("block:" + st, piece(b.local(m, deck - 1.6), f, Vector3(3.6, 1.6, seg + 0.05)))
		elif deck - g > 4.0:
			b.put("arch:" + st, piece(b.local(m, g - 1.0), f, Vector3(3.2, deck - g + 1.0, seg + 0.05)))
		else:
			b.put("block:" + st, piece(b.local(m, g - 1.0), f, Vector3(3.2, deck - g + 1.0, seg + 0.05)))
		for side: float in [-1.0, 1.0]:
			b.put("block:" + st, piece(b.local(m + side_of(f) * side * 1.6, deck), f, Vector3(0.4, 0.9, seg + 0.05)))


## A boardwalk over the marsh or the dunes: a timber deck a little above the land, on posts.
static func _boardwalk(b: _Block, line: PackedVector2Array, w: float, k: Dictionary) -> void:
	w = clampf(w if w > 0.0 else float(k.get("width", 1.8)), 1.0, 6.0)
	for s: Array in steps(b, line, 4.0):
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		if not b.clear((a + c) * 0.5, w * 0.5 + 1.0):
			continue
		var ya := b.ground(a)
		var yc := b.ground(c)
		if is_nan(ya) or is_nan(yc):
			continue
		b.put("block:timber", slope(b.local(a, ya + 0.35), b.local(c, yc + 0.35), w, 0.12))
		b.put("block:timber", piece(b.local(a, ya - 0.3), (c - a).normalized(), Vector3(w + 0.2, 0.7, 0.2)))


## A fish pass beside a weir or dam: a stepped concrete channel down the bank, white water in it.
static func _fish_pass(b: _Block, line: PackedVector2Array, k: Dictionary) -> void:
	for s: Array in steps(b, line, 3.0):
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var m := (a + c) * 0.5
		if not b.clear(m):
			continue
		var ya := b.ground(a)
		var yc := b.ground(c)
		if is_nan(ya) or is_nan(yc):
			continue
		var f := (c - a).normalized()
		for side: float in [-1.0, 1.0]:
			b.put("block:concrete", slope(b.local(a + side_of(f) * side * 1.4, ya - 0.5), b.local(c + side_of(f) * side * 1.4, yc - 0.5), 0.3, 1.3))
		b.put("foam", piece(b.local(m, minf(ya, yc) + 0.2), f, Vector3(2.4, 1.0, a.distance_to(c))))


## A thing the map has as a point that is most often a line (a small dam, a jetty): a short stretch of it, turned to
## its heading or across the stream it's by.
static func _marker(b: _Block, p: Vector2, kind: String, k: Dictionary) -> void:
	var s := _stream_near(b, p, 30.0)
	var f: Vector2 = side_of(s["dir"]) if not s.is_empty() else Vector2(1, 0)
	var half := (float(s["half"]) + 2.0) if not s.is_empty() else 6.0
	var line := PackedVector2Array([p - f * half, p + f * half])
	match kind:
		"dam": _dam(b, line, null, 0.0, k, str(p))
		"pier": _pier(b, PackedVector2Array([p, p + f * 12.0]), 0.0, k, str(p))
		"breakwater": _harbour_wall(b, line, 0.0, k, str(p))
		"quay": _quay(b, line, k, str(p), false)
		"groyne": _groyne(b, line, k)
		"fish_pass": _fish_pass(b, line, k)
		"boardwalk": _boardwalk(b, line, 0.0, k)


# ---------------------------------------------------------------------------- springs, geysers and blowholes

## A hot spring (its pool's rim and the steam off it, always) or a geyser (a mound of sinter, steam, and its jet now
## and then: dress).
static func _spring(b: _Block, p: Vector2, k: Dictionary, geyser: bool, id: String) -> void:
	if not b.clear(p, 4.0):
		return
	var y := b.ground(p)
	if is_nan(y):
		return
	var r := float(k.get("pool", 3.0)) * (0.7 + 0.6 * roll(id + "r"))
	b.put("mound:" + stone(k, "stone", "sinter"), piece(b.local(p, y - 0.4), Vector2(0, 1), Vector3(r * 2.4, 0.8 if geyser else 0.55, r * 2.4)))
	b.put("pool", piece(b.local(p, y + (0.42 if geyser else 0.2)), Vector2(0, 1), Vector3(r * 1.6, 1.0, r * 1.6)))
	b.put("steam", piece(b.local(p, y), Vector2(0, 1), Vector3(r * 2.0 + 1.0, r * 1.6 + 3.0, r * 2.0 + 1.0)))
	if geyser:
		(b.dress["jets"] as Array).append({"at": b.local(p, y + 0.4), "height": float(k.get("jet", 25.0)) * (0.6 + 0.8 * roll(id + "h")),
			"period": lerpf(PERIOD.x, PERIOD.y, roll(id + "p")), "phase": roll(id + "phase"), "wind": false})


## A blowhole on the rocks: the sea spouts up through it when the weather's up (dress).
static func _blowhole(b: _Block, p: Vector2, k: Dictionary, id: String) -> void:
	if not b.clear(p, 4.0):
		return
	var y := b.ground(p)
	if is_nan(y):
		return
	(b.dress["jets"] as Array).append({"at": b.local(p, y), "height": float(k.get("jet", 12.0)) * (0.6 + 0.8 * roll(id + "h")),
		"period": 0.4 + roll(id + "p") * 0.4, "phase": roll(id + "phase"), "wind": true})


# ---------------------------------------------------------------------------- boats

## How long and broad each boat is (m).
const BOAT_LENGTH := {"narrowboat": 20.0, "barge": 32.0, "fishing": 11.0, "motor": 7.5, "yacht": 10.0, "pirogue": 9.0,
	"longtail": 10.0, "lifeboat": 14.0}
const BOAT_BEAM := {"narrowboat": 2.1, "barge": 5.0, "fishing": 3.8, "motor": 2.6, "yacht": 3.2, "pirogue": 1.3,
	"longtail": 1.6, "lifeboat": 4.6}


## A boat of kind `kind` ("narrowboat", "fishing", "yacht", ... : BOAT_LENGTH's) at `p`, its bow along `f`, sitting
## on water at `y`, its livery by `tag`.
static func _boat(b: _Block, kind: String, p: Vector2, f: Vector2, y: float, tag: String, scale := 1.0) -> void:
	if b.boats >= BOATS_MOST:
		return
	b.boats += 1
	var base := kind.get_slice(":", 0)
	var model := base
	if base in ["narrowboat", "fishing", "pirogue", "longtail"]:
		model = "%s:%d" % [base, int(roll(tag + "livery") * LIVERIES.size()) % LIVERIES.size()]
	b.put("boat:" + model, piece(b.local(p, y), f, Vector3.ONE * scale))


# ---------------------------------------------------------------------------- meshes

## The mesh of `model` (lay_out's names: "block:STONE", "wedge:STONE", "mound:STONE", "arch:STONE", "sheet", "foam",
## "steam", "pool", "jet", "tetrapod", "bollard", "lamp_post", "lamp_head:COLOUR", "light_tower:COLOUR", "beacon:COLOUR",
## "boat:KIND[:LIVERY]"), made once. "water_works:" in front is taken off.
static func mesh(model: String) -> Mesh:
	if model.begins_with("water_works:"):
		model = model.substr(12)
	_lock.lock()
	var have = _meshes.get(model)
	_lock.unlock()
	if have is Mesh:
		return have
	var out := _make(model)
	_lock.lock()
	_meshes[model] = out
	_lock.unlock()
	return out


static func _make(model: String) -> Mesh:
	var kind := model.get_slice(":", 0)
	var arg := model.get_slice(":", 1) if model.contains(":") else ""
	var col: Color = STONES.get(arg, STONES["concrete"])
	var a := AdventureProps.new_arrays()
	match kind:
		"block":
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0, 0)), Vector3.ONE, col)
			_bottom(a, col)
		"wedge":
			_wedge(a, col)
		"mound":
			_mound(a, col)
		"arch":
			_arch(a, col)
		"tetrapod":
			for d: Vector3 in [Vector3(0, 1, 0), Vector3(0.94, -0.33, 0), Vector3(-0.47, -0.33, 0.82), Vector3(-0.47, -0.33, -0.82)]:
				var bas := Basis(Quaternion(Vector3.UP, (d as Vector3).normalized()))
				AdventureProps.cone(a, Transform3D(bas, Vector3(0, 1.0, 0)), 0.55, 0.0, 1.3, STONES["concrete"], 6, 0.3)
		"bollard":
			AdventureProps.cone(a, Transform3D(), 0.16, 0.0, 0.6, STONES["black"], 8, 0.14)
			AdventureProps.cone(a, Transform3D(), 0.24, 0.6, 0.7, STONES["black"], 8, 0.2)
		"lamp_post":
			AdventureProps.box(a, Transform3D(), Vector3(0.12, 3.6, 0.12), Color(0.12, 0.2, 0.16))
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 3.55, 0)), Vector3(0.36, 0.08, 0.36), Color(0.12, 0.2, 0.16))
		"lamp_head":
			return _lamp_head(arg, Vector3(0, 3.75, 0), 0.22)
		"beacon":
			return _lamp_head(arg, Vector3(0, 6.4, 0), 0.38)
		"light_tower":
			AdventureProps.cone(a, Transform3D(), 1.0, 0.0, 6.0, STONES["white"], 10, 0.75)
			AdventureProps.cone(a, Transform3D(), 0.95, 3.6, 4.8, Color(0.75, 0.12, 0.1) if arg == "red" else Color(0.1, 0.5, 0.2), 10, 0.83)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 6.85, 0)), Vector3(0.9, 0.12, 0.9), STONES["black"])
		"sheet":
			return _quad_mesh(_sheet_material(), false)
		"foam":
			return _disc_mesh(_foam_material())
		"pool":
			return _disc_mesh(RealLand.water_material())
		"steam", "jet":
			return _plume_mesh(_steam_material())
		"boat":
			_boat_mesh(a, arg, int(model.get_slice(":", 2)) if model.count(":") >= 2 else 0)
	return AdventureProps.to_mesh(a)


## The underside of a unit block (AdventureProps.box leaves it open), seen from below on a pier's deck.
static func _bottom(a: Dictionary, col: Color) -> void:
	AdventureProps._quad(a, Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5), col.darkened(0.2))


## A unit wedge: across from its upright face at x 0 (1 high) out to x 1 (at the ground), z from -0.5 to 0.5.
static func _wedge(a: Dictionary, col: Color) -> void:
	var p := [Vector3(0, 0, -0.5), Vector3(1, 0, -0.5), Vector3(0, 1, -0.5), Vector3(0, 0, 0.5), Vector3(1, 0, 0.5), Vector3(0, 1, 0.5)]
	AdventureProps._quad(a, p[2], p[5], p[4], p[1], col.lightened(0.04))   # the slope
	AdventureProps._tri(a, p[0], p[2], p[1], col.darkened(0.08))
	AdventureProps._tri(a, p[3], p[4], p[5], col.darkened(0.08))


## A unit mound of rock armour: a trapezium across (1 wide at the foot, 0.36 at the top), z from -0.5 to 0.5.
static func _mound(a: Dictionary, col: Color) -> void:
	var t := 0.18
	var p := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(t, 1, -0.5), Vector3(-t, 1, -0.5),
		Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(t, 1, 0.5), Vector3(-t, 1, 0.5)]
	AdventureProps._quad(a, p[1], p[5], p[6], p[2], col)
	AdventureProps._quad(a, p[4], p[0], p[3], p[7], col.darkened(0.06))
	AdventureProps._quad(a, p[3], p[2], p[6], p[7], col.lightened(0.08))
	AdventureProps._quad(a, p[0], p[1], p[2], p[3], col.darkened(0.1))
	AdventureProps._quad(a, p[5], p[4], p[7], p[6], col.darkened(0.1))


## A unit arch: a wall 1 thick (x), 1 high, 1 along (z), with a round-headed opening through it between piers a tenth
## of the span each, springing at 0.55 of its height.
static func _arch(a: Dictionary, col: Color) -> void:
	var n := 16
	var r := 0.4
	var spring := 0.55
	var under := func(z: float) -> float:
		return spring + sqrt(maxf(0.0, r * r - z * z)) if absf(z) < r else 0.0
	var zs := [-0.5]
	for i in n + 1:
		zs.append(-r + 2.0 * r * i / n)
	zs.append(0.5)
	for i in zs.size() - 1:
		var z0: float = zs[i]
		var z1: float = zs[i + 1]
		var mid := (z0 + z1) * 0.5
		var y0: float = under.call(z0 + 1e-4 if mid > z0 else z0)
		var y1: float = under.call(z1 - 1e-4 if mid < z1 else z1)
		if absf(mid) > r:
			y0 = 0.0
			y1 = 0.0
		for x: float in [-0.5, 0.5]:
			if x < 0.0:
				AdventureProps._quad(a, Vector3(x, y0, z0), Vector3(x, y1, z1), Vector3(x, 1, z1), Vector3(x, 1, z0), col.darkened(0.05))
			else:
				AdventureProps._quad(a, Vector3(x, y1, z1), Vector3(x, y0, z0), Vector3(x, 1, z0), Vector3(x, 1, z1), col.darkened(0.05))
		if y0 > 0.0 or y1 > 0.0:
			AdventureProps._quad(a, Vector3(-0.5, y0, z0), Vector3(0.5, y0, z0), Vector3(0.5, y1, z1), Vector3(-0.5, y1, z1), col.darkened(0.25))
		AdventureProps._quad(a, Vector3(-0.5, 1, z1), Vector3(0.5, 1, z1), Vector3(0.5, 1, z0), Vector3(-0.5, 1, z0), col.lightened(0.05))
	# (the piers' inner faces, from the ground up to where the arch springs)
	AdventureProps._quad(a, Vector3(-0.5, 0, -r), Vector3(0.5, 0, -r), Vector3(0.5, spring, -r), Vector3(-0.5, spring, -r), col.darkened(0.15))
	AdventureProps._quad(a, Vector3(0.5, 0, r), Vector3(-0.5, 0, r), Vector3(-0.5, spring, r), Vector3(0.5, spring, r), col.darkened(0.15))
	for z: float in [-0.5, 0.5]:
		var s := 1.0 if z > 0.0 else -1.0
		AdventureProps._quad(a, Vector3(-0.5 * s, 0, z), Vector3(0.5 * s, 0, z), Vector3(0.5 * s, 1, z), Vector3(-0.5 * s, 1, z), col.darkened(0.08))


## A boat, real size, its bow along +z (pieces run along their z), its waterline at y 0.
static func _boat_mesh(a: Dictionary, kind: String, livery: int) -> void:
	var paint: Color = LIVERIES[clampi(livery, 0, LIVERIES.size() - 1)]
	var white: Color = STONES["white"]
	var black: Color = STONES["black"]
	var wood: Color = STONES["timber"].lightened(0.15)
	var l := float(BOAT_LENGTH.get(kind, 8.0))
	var w := float(BOAT_BEAM.get(kind, 2.5))
	var hull := func(col: Color, depth: float, free: float) -> void:
		# (a hull: a box with its bow drawn to a point)
		AdventureProps.box(a, Transform3D(Basis(), Vector3(0, -depth, -l * 0.08)), Vector3(w, depth + free, l * 0.84), col)
		var tip := Vector3(0, free, l * 0.5)
		var y0 := -depth
		var y1 := free
		var z0 := l * 0.34
		AdventureProps._quad(a, Vector3(w * 0.5, y0, z0), Vector3(w * 0.5, y1, z0), tip, Vector3(0, y0, l * 0.46), col.darkened(0.05))
		AdventureProps._quad(a, Vector3(-w * 0.5, y1, z0), Vector3(-w * 0.5, y0, z0), Vector3(0, y0, l * 0.46), tip, col.darkened(0.05))
		AdventureProps._tri(a, Vector3(-w * 0.5, y1, z0), tip, Vector3(w * 0.5, y1, z0), col.lightened(0.1))
	match kind:
		"narrowboat":
			hull.call(black, 0.5, 0.45)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.45, -1.2)), Vector3(w - 0.25, 1.15, l * 0.66), paint)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.6, -1.2)), Vector3(w - 0.15, 0.1, l * 0.67), Color(0.15, 0.15, 0.15))
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.02, -1.2)), Vector3(w - 0.2, 0.18, l * 0.64), Color(0.85, 0.7, 0.2))
			AdventureProps.box(a, Transform3D(Basis(), Vector3(w * 0.3, 1.7, 2.0)), Vector3(0.18, 0.7, 0.18), black)
		"barge":
			hull.call(black, 1.4, 1.0)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.0, -l * 0.38)), Vector3(w * 0.8, 2.6, 4.0), white)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.0, l * 0.05)), Vector3(w * 0.9, 0.6, l * 0.55), Color(0.25, 0.3, 0.35))
		"fishing":
			hull.call(paint, 1.0, 1.0)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, -0.2, -l * 0.08)), Vector3(w + 0.02, 0.25, l * 0.84), white)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.0, -l * 0.15)), Vector3(w * 0.6, 2.0, 2.6), white)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 3.0, -l * 0.15)), Vector3(0.12, 3.5, 0.12), black)
		"motor":
			hull.call(white, 0.5, 0.7)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.7, -0.6)), Vector3(w * 0.75, 0.9, 2.4), Color(0.2, 0.32, 0.5))
		"yacht":
			hull.call(white, 0.7, 0.8)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.8, -0.8)), Vector3(w * 0.6, 0.6, 3.6), white.darkened(0.06))
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.8, 0.8)), Vector3(0.14, 13.0, 0.14), Color(0.8, 0.8, 0.82))
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 2.2, -1.2)), Vector3(0.12, 0.12, 4.2), Color(0.8, 0.8, 0.82))
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 2.3, -1.2)), Vector3(0.3, 0.3, 4.0), Color(0.15, 0.2, 0.45))
		"pirogue":
			hull.call(paint, 0.35, 0.35)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.3, -0.4)), Vector3(w + 0.04, 0.12, l * 0.7), STONES["white"].darkened(0.1))
		"longtail":
			hull.call(wood, 0.35, 0.45)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.45, l * 0.42)), Vector3(0.2, 1.2, 0.4), paint)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.8, -l * 0.3)), Vector3(w * 0.9, 0.08, l * 0.4), Color(0.2, 0.3, 0.6))
		"lifeboat":
			hull.call(Color(0.12, 0.22, 0.45), 1.0, 1.2)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.2, -1.0)), Vector3(w * 0.7, 1.8, 5.0), Color(0.95, 0.45, 0.1))
		_:
			hull.call(white, 0.5, 0.6)


## A flat unit square (x from -0.5 to 0.5, y from 0 down to -1, facing +z), both sides drawn: a sheet of falling water.
static func _quad_mesh(mat: Material, _top: bool) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, -1, 0), Vector3(-0.5, -1, 0)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uv[i])
		st.add_vertex(v[i])
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


## A flat unit disc (radius 0.5) facing up at y 0: foam on the water, a pool.
static func _disc_mesh(mat: Material) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for p: Vector2 in [Vector2.ZERO, Vector2(cos(a1), sin(a1)) * 0.5, Vector2(cos(a0), sin(a0)) * 0.5]:
			st.set_normal(Vector3.UP)
			st.set_uv(p + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(p.x, 0, p.y))
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


## A unit plume: three upright squares crossed (1 across, from y 0 to 1), soft at the edges: spray, steam, a jet.
static func _plume_mesh(mat: Material) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var d := Vector2.from_angle(PI * k / 3.0) * 0.5
		var v := [Vector3(-d.x, 0, -d.y), Vector3(d.x, 0, d.y), Vector3(d.x, 1, d.y), Vector3(-d.x, 1, -d.y)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var nrm := Vector3(-d.y, 0, d.x).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm)
			st.set_uv(uv[i])
			st.add_vertex(v[i])
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


## A lamp's glass at `at`, lit at dusk (Daylight's lamps: Life keeps its glow).
static func _lamp_head(colour: String, at: Vector3, r: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	m.material = lamp_material(colour)
	var arrays := m.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += at
	arrays[Mesh.ARRAY_VERTEX] = v
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, m.material)
	return out


## The glass of a lamp of `colour` ("white", "red", "green"): its glow follows the dusk (Life).
static func lamp_material(colour: String) -> StandardMaterial3D:
	_lock.lock()
	if _lamp_mat == null:
		for c: String in ["white", "red", "green"]:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = {"white": Color(1.0, 0.92, 0.75), "red": Color(1.0, 0.15, 0.1), "green": Color(0.2, 1.0, 0.35)}[c]
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 0.05
			match c:
				"white": _lamp_mat = mat
				"red": _red_mat = mat
				"green": _green_mat = mat
	var out: StandardMaterial3D = {"white": _lamp_mat, "red": _red_mat, "green": _green_mat}.get(colour, _lamp_mat)
	_lock.unlock()
	return out


static func _sheet_material() -> ShaderMaterial:
	if _sheet_mat == null:
		var sh := Shader.new()
		sh.code = SHEET_SHADER
		_sheet_mat = ShaderMaterial.new()
		_sheet_mat.shader = sh
	return _sheet_mat


static func _foam_material() -> ShaderMaterial:
	if _foam_mat == null:
		var sh := Shader.new()
		sh.code = FOAM_SHADER
		_foam_mat = ShaderMaterial.new()
		_foam_mat.shader = sh
	return _foam_mat


static func _steam_material() -> ShaderMaterial:
	if _steam_mat == null:
		var sh := Shader.new()
		sh.code = STEAM_SHADER
		_steam_mat = ShaderMaterial.new()
		_steam_mat.shader = sh
	return _steam_mat


## Falling water: white streaks running down, thinner at the edges, a touch of the sky's light through it.
const SHEET_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_disabled;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
varying vec2 scale;
void vertex() {
	scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
}
void fragment() {
	vec2 p = vec2(UV.x * scale.x * 0.6, UV.y * scale.y * 0.25 - TIME * 1.6);
	float s = n(p * vec2(3.0, 1.0)) * 0.6 + n(p * vec2(9.0, 2.0)) * 0.4;
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	ALBEDO = mix(vec3(0.62, 0.7, 0.72), vec3(0.96, 0.97, 0.98), s);
	ROUGHNESS = 0.4;
	ALPHA = clamp((0.55 + s * 0.45) * edge * smoothstep(0.0, 0.04, UV.y), 0.0, 1.0);
}
"""

## Foam on the water: broken white, drifting.
const FOAM_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_disabled;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float s = n(UV * 14.0 + vec2(TIME * 0.3, TIME * 0.5)) * 0.6 + n(UV * 37.0 - TIME * 0.4) * 0.4;
	ALBEDO = vec3(0.93, 0.95, 0.96);
	ROUGHNESS = 0.6;
	ALPHA = clamp(smoothstep(1.0, 0.45, r) * (s * 1.3 - 0.25), 0.0, 0.9);
}
"""

## Spray, steam and a geyser's jet: soft white rising and thinning, turned to the camera's light.
const STEAM_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	float up = 1.0 - UV.y;
	vec2 p = vec2(UV.x * 3.0, UV.y * 2.0 + TIME * 0.35);
	float s = n(p * 2.0) * 0.6 + n(p * 5.0) * 0.4;
	float side = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = vec3(0.95);
	ROUGHNESS = 1.0;
	ALPHA = clamp(smoothstep(0.0, 0.5, side) * smoothstep(1.0, 0.2, up) * smoothstep(0.0, 0.08, up) * (s * 0.9 + 0.1) * 0.55, 0.0, 1.0);
}
"""


## What moves and what glows in a block (dress): the geysers' and blowholes' jets, rising and falling by the crew's
## clock (Daylight's hours, the host's: everyone sees the same eruption), and the lamps' glass at dusk.
class Life:
	extends Node3D
	var jets: Array = []

	func _process(_delta: float) -> void:
		var lamps: float = Daylight.current.lamps if Daylight.current != null else 0.0
		var glow := lerpf(0.05, 5.0, lamps)
		for c: String in ["white", "red", "green"]:
			var mat := WaterWorks.lamp_material(c)
			if not is_equal_approx(mat.emission_energy_multiplier, glow):
				mat.emission_energy_multiplier = glow
		if jets.is_empty():
			return
		var minutes := Daylight.time_of_day() * 60.0
		var rough := Weather.current != null and Weather.current.state in ["rain", "cloudy"]
		for j: Dictionary in jets:
			var mi: MeshInstance3D = j["node"]
			var t := fposmod(minutes / float(j["period"]) + float(j["phase"]), 1.0)
			var up := 0.0
			if bool(j["wind"]):
				# (a blowhole: the swell's every wave, only with the weather up)
				up = (pow(maxf(0.0, sin(t * TAU)), 6.0) if rough else 0.0)
			elif t < WaterWorks.ERUPT:
				up = sin(t / WaterWorks.ERUPT * PI)
			mi.visible = up > 0.02
			if mi.visible:
				var hgt := float(j["height"]) * up
				mi.scale = Vector3(maxf(1.5, hgt * 0.18), maxf(0.5, hgt), maxf(1.5, hgt * 0.18))
