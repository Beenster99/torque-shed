class_name Furniture
extends RefCounted
## Street furniture (Ride Anywhere v2, phase D round 3, D9: interfaces/scenery.md): the things along a street or a lane
## that the map has where they really are. Street lamps (lit at dusk, a pool of light on the road under each), benches
## and picnic tables, post boxes in their country's shape and colour, bus stops (a shelter in a town, a flag on a pole
## out of one), charging points, cattle grids (the white wings either side of the road), field gates, kissing gates,
## stiles, bollards and barriers.
##
## The streamer (SceneryStreamer) hands lay_out a block's rows of the kinds whose kit row names "furniture:MODEL", each
## with its kit (the default with the place's region laid over it), and draws what comes back: one MultiMesh a model a
## block. dress adds the ticker that brings the lamps on at dusk.
##
## Simon's first rule, as here: nothing stands in a carriageway or on its verge (a thing the map puts on a road is stood
## off it, SceneryStreamer.stand; a gate or a cattle grid across the road becomes its posts or wings either side, the
## gate swung open against the verge), the lamps' pools of light are only light, and nothing here has collision. The
## second: every kind wherever the map has it, its look by region (and a post box by country) from the kit library's
## rows, with a default for anywhere; nothing is keyed to a place.

## Part of what a block lays out: bump it with the look. SceneryStreamer folds the scripts' versions into the builder
## hash.
const VERSION := 1
const SIZE := 512.0   # RoadBlock.SIZE
## How far past a road's verge a thing beside it keeps (m: SceneryStreamer.CLEAR's).
const CLEAR := 1.5
## A gate or a cattle grid this near a road's middle (past its half width and verge, m) is across that road.
const ACROSS := 1.0
## A gate's posts and a cattle grid's wings stand this far past the verge (m).
const WING_OUT := 0.3
## How far a street lamp's arm reaches over towards the road (m), and its pool of light's radius on the ground.
const ARM := 2.2
const POOL_R := 7.0
## How many bus stops have a shelter, by how built up the place is (PlaceProfile's densities): a flag on a pole only,
## out in the country.
const SHELTERED := {"city": 1.0, "town": 0.6, "village": 0.3}
## Post boxes: how each shape is drawn, and their colours.
const POST_SHAPES := ["pillar", "box", "drop"]
const POST_COLOURS := {"red": Color(0.72, 0.08, 0.06), "yellow": Color(0.95, 0.75, 0.08), "blue": Color(0.1, 0.22, 0.52),
	"green": Color(0.08, 0.35, 0.2), "orange": Color(0.95, 0.45, 0.06), "black": Color(0.1, 0.1, 0.1)}
## Street lamp styles: a column with an arm over the road, a lantern on a post-top, a concrete column with a long
## outreach, and the light each gives.
const LAMP_STYLES := ["column", "lantern", "concrete"]
const LIGHTS := {"white": Color(0.95, 0.95, 1.0), "warm": Color(1.0, 0.82, 0.55), "sodium": Color(1.0, 0.62, 0.25)}
const STEEL := Color(0.52, 0.54, 0.56)
const DARK := Color(0.1, 0.1, 0.11)
const WOOD := Color(0.42, 0.3, 0.2)
const GREY_WOOD := Color(0.5, 0.48, 0.44)
const WHITE := Color(0.9, 0.9, 0.88)
const GLASS := Color(0.55, 0.65, 0.7)
## Shader flags, a vertex's UV2.x: a lamp's glow (a square to the camera, lit at night: UV2.y its size), a lamp's
## glass (lit at night), a screen (a little lit by day, more at night).
const GLOW := 3.0
const LIT := 4.0
const SCREEN := 6.0

static var _meshes := {}
static var _meshes_lock := Mutex.new()
static var _material: ShaderMaterial
static var _pool_material: ShaderMaterial
static var _ticked := -1


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of the rows (SceneryStreamer's: {points, lines, areas}, each [row, kit]) whose kit names
## this script: {items: {model: [Transform3D in the block's frame]}, dress: true}. Safe on a worker.
static func lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var b := _Block.new(net, key)
	for pair: Array in rows.get("points", []):
		var row: Array = pair[0]
		var p := Vector2(float(row[1]), float(row[2]))
		if b.mine(p):
			_point(b, str(row[0]), p, row, pair[1], Vector2.ZERO)
	for part: String in ["lines", "areas"]:
		for pair: Array in rows.get(part, []):
			# (a gate mapped as a line across a way, or anything as an outline: at its middle, along its run)
			var row: Array = pair[0]
			var line: PackedVector2Array = row[1]
			if line.is_empty():
				continue
			if part == "lines" and str(row[0]) == "region_border":
				_boundary(b, row, pair[1])
				continue
			var mid := (line[0] + line[line.size() - 1]) * 0.5
			if not b.mine(mid):
				continue
			var run := (line[line.size() - 1] - line[0]).normalized() if line.size() > 1 else Vector2.ZERO
			_point(b, str(row[0]), mid, [row[0], mid.x, mid.y, null, null, null, row[5] if part == "lines" else row[4],
				row[6] if part == "lines" else row[5]], pair[1], run)
	# (a block with lamps, a charging point or a lit shelter in it gets the ticker that lights them at dusk)
	var lit := false
	for m: String in b.items:
		lit = lit or m.begins_with("lamp_") or m == "charger" or m == "shelter_glass"
	return {"items": b.items, "moved": b.moved, "skipped": b.skipped, "dress": lit}


## The lamps' ticker, once a block with lamps in it is in the world (main thread).
static func dress(node: Node3D, data) -> void:
	if not data is bool or not data:
		return
	var t := _Tick.new()
	t.name = "FurnitureTick"
	node.add_child(t)


class _Tick extends Node:
	func _process(_delta: float) -> void:
		Furniture.tick()


## A block's laying out: where it is, the roads, what it has made so far.
class _Block:
	var n: RoadNet
	var key: Vector2i
	var corner: Vector2
	var box: Rect2
	var items := {}
	var memo := {}
	var moved := 0
	var skipped := 0
	var _at_p := Vector2.INF
	var _at_on := {}

	func _init(net: RoadNet, k: Vector2i) -> void:
		n = net
		key = k
		corner = Vector2(k) * SIZE
		box = Rect2(corner, Vector2.ONE * SIZE)

	func mine(p: Vector2) -> bool:
		return box.has_point(p)

	func put(model: String, xf: Transform3D) -> void:
		if not items.has(model):
			items[model] = []
		(items[model] as Array).append(xf)

	## A model at region point `p` (y up), its front (+z) turned to `face` (none: as it is).
	func put_at(model: String, p: Vector2, y: float, face: Vector2) -> void:
		var yaw := atan2(face.x, face.y) if face != Vector2.ZERO else 0.0
		put(model, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x - corner.x, y, p.y - corner.y)))

	## The land as drawn at `p`, the roads' banks cut in (RoadNet.ground_at); NAN beyond the land held.
	func ground(p: Vector2) -> float:
		var bare := float(n.height.call(p.x, p.y))
		if is_nan(bare) or n._near(p.x, p.y).is_empty():
			return bare
		return n.ground_at(p.x, p.y, bare, memo)

	## Which road `p` is on or nearest (RoadNet.locate, without heights; {} with none near), the last point's kept:
	## a thing's stand and the road it faces ask once between them.
	func where(p: Vector2) -> Dictionary:
		if p != _at_p:
			_at_p = p
			_at_on = {} if n._near(p.x, p.y).is_empty() else n.locate(p.x, p.y, -1, false)
		return _at_on

	## Where a thing at `p` stands, off any road (as SceneryStreamer.stand, which a thing on a road's verge is handed
	## to), in the region frame; NAN where it can't.
	func stand(p: Vector2) -> Vector3:
		var on := where(p)
		if not on.is_empty():
			if int(on["node"]) >= 0:
				skipped += 1
				return Vector3(NAN, NAN, NAN)
			if absf(float(on["lat"])) < float(on["width"]) * 0.5 + RoadNet.VERGE + CLEAR:
				var at := SceneryStreamer.stand(n, p, memo)
				if is_nan(at.x):
					skipped += 1
				else:
					moved += 1
				return at
		var bare := float(n.height.call(p.x, p.y))
		if is_nan(bare):
			skipped += 1
			return Vector3(NAN, NAN, NAN)
		# (past the reach of the nearest road's bank, and so of every road's, the land is as it is)
		var banked := not on.is_empty() and (absf(float(on["lat"])) - float(on["width"]) * 0.5 - RoadNet.VERGE
			< RoadNet.BANK_MAX + RoadNet.LAND_PAD or not n.flats.is_empty())
		return Vector3(p.x, (n.ground_at(p.x, p.y, bare, memo) if banked else bare) - 0.1, p.y)

	## The road nearest `p` within 60 m: {centre, along (unit, the way the road goes), out (unit, from the road to `p`'s
	## side), lat (m from its middle, + to its right), half (its half width)}; {} where there's none or `p` is in a
	## junction.
	func road(p: Vector2) -> Dictionary:
		var on := where(p)
		if on.is_empty() or int(on["node"]) >= 0:
			return {}
		var e := int(on["edge"])
		var s := float(on["s"])
		var len := n.length_of(e)
		var along := n.point_at(e, minf(s + 1.0, len)) - n.point_at(e, maxf(s - 1.0, 0.0))
		if along.length() < 1e-4:
			return {}
		along = along.normalized()
		var lat := float(on["lat"])
		var c := n.point_at(e, s)
		if c.distance_to(p) > 60.0 + float(on["width"]) * 0.5:
			return {}
		var right := Vector2(-along.y, along.x)
		return {"centre": c, "along": along, "out": right * (1.0 if lat >= 0.0 else -1.0), "right": right, "lat": lat,
			"half": float(on["width"]) * 0.5}


## Whether region-frame `p` is `pad` past the verge of every road near it and out of every junction.
static func clear_of_roads(n: RoadNet, p: Vector2, pad := CLEAR) -> bool:
	return History.clear_of_roads(n, p, pad)


# ---------------------------------------------------------------------------- the things at a point

## A point's thing as its kit says, `run` the way a line it was mapped as runs (ZERO for a point).
static func _point(b: _Block, kind: String, p: Vector2, row: Array, k: Dictionary, run: Vector2) -> void:
	var model := str(k.get("model", "")).get_slice(":", 1)
	if model == "" or model == "none":
		return
	match model:
		"lamp":
			_lamp(b, p, row, k)
		"post_box":
			_post_box(b, p, row, k)
		"bus_stop":
			_bus_stop(b, p, row, k)
		"gate", "kissing_gate", "stile", "lift_gate":
			_crossing(b, model, p, row, k, run)
		"cattle_grid":
			_cattle_grid(b, p, row)
		"boundary":
			pass   # (a line's: _boundary)
		_:
			# (a bench, a picnic table, a charging point, a bollard: where the map has it, facing the road)
			var at := b.stand(p)
			if is_nan(at.x):
				return
			var q := Vector2(at.x, at.z)
			var r := b.road(q)
			var face: Vector2 = -(r["out"] as Vector2) if not r.is_empty() else _dir_of(row, p)
			var style := str(k.get("style", ""))
			b.put_at(model + ("_" + style if style != "" else ""), q, at.y, face)


## A street lamp: its column stood where the map has it, its arm out over the road (or a lantern on top, the post's
## own), and its pool of light on the ground under the lamp.
static func _lamp(b: _Block, p: Vector2, row: Array, k: Dictionary) -> void:
	var at := b.stand(p)
	if is_nan(at.x):
		return
	var q := Vector2(at.x, at.z)
	var r := b.road(q)
	var face: Vector2 = -(r["out"] as Vector2) if not r.is_empty() else _dir_of(row, p)
	var style := str(k.get("style", "column"))
	if not style in LAMP_STYLES:
		style = "column"
	var light := str(k.get("light", "white"))
	if not LIGHTS.has(light):
		light = "white"
	b.put_at("lamp_%s_%s" % [style, light], q, at.y, face)
	# The pool under the lamp's head, tilted to the ground there.
	var reach := lamp_reach(style)
	var c := q + face * reach
	var y := b.ground(c)
	if is_nan(y):
		return
	var side := Vector2(-face.y, face.x)
	var gx := b.ground(c + side * 3.0) - y
	var gz := b.ground(c + face * 3.0) - y
	var up := Vector3(0, 1, 0)
	if not is_nan(gx) and not is_nan(gz):
		# (the ground's slope across the pool: its normal from the rises either way over 3 m)
		var sx := Vector3(side.x * 3.0, gx, side.y * 3.0)
		var sz := Vector3(face.x * 3.0, gz, face.y * 3.0)
		up = sz.cross(sx).normalized()
		if up.y < 0.0:
			up = -up
	var fwd := Vector3(face.x, 0, face.y)
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var basis := Basis(up.cross(fwd).normalized(), up, fwd)
	b.put("pool_" + light, Transform3D(basis, Vector3(c.x - b.corner.x, y + 0.12, c.y - b.corner.y)))


## How far out from its post a lamp of `style` puts its light (m).
static func lamp_reach(style: String) -> float:
	match style:
		"lantern":
			return 0.0
		"concrete":
			return ARM + 0.8
	return ARM


## A post box in its country's shape and colour (the kit's "countries", by the code RegionKit has for the place; its
## "style" anywhere else), its slot to the road.
static func _post_box(b: _Block, p: Vector2, row: Array, k: Dictionary) -> void:
	var at := b.stand(p)
	if is_nan(at.x):
		return
	var q := Vector2(at.x, at.z)
	var r := b.road(q)
	var face: Vector2 = -(r["out"] as Vector2) if not r.is_empty() else _dir_of(row, p)
	b.put_at(post_box_model(b.n, q, k), q, at.y, face)


## The post box model ("SHAPE_COLOUR") for region point `q` of `n`'s region, by its kit `k`.
static func post_box_model(n: RoadNet, q: Vector2, k: Dictionary) -> String:
	var style := str(k.get("style", "box_red"))
	var by: Dictionary = k.get("countries", {})
	if not by.is_empty():
		var code := str(RegionKit.at_frame(n.region.frame_lat, n.region.frame_lon, q.x, q.y).get("country", ""))
		style = str(by.get(code, style))
	var shape := style.get_slice("_", 0)
	var colour := style.get_slice("_", 1)
	if not shape in POST_SHAPES:
		shape = "box"
	if not POST_COLOURS.has(colour):
		colour = "red"
	return shape + "_" + colour


## A bus stop: its flag on a pole at the kerb, and in a built-up place a shelter behind it facing the road.
static func _bus_stop(b: _Block, p: Vector2, row: Array, k: Dictionary) -> void:
	var at := b.stand(p)
	if is_nan(at.x):
		return
	var q := Vector2(at.x, at.z)
	var r := b.road(q)
	var face: Vector2 = -(r["out"] as Vector2) if not r.is_empty() else _dir_of(row, p)
	var flag := str(k.get("flag", "bus_flag"))
	b.put_at(flag, q, at.y, face)
	if r.is_empty():
		return
	var density := str(RegionKit.at_frame(b.n.region.frame_lat, b.n.region.frame_lon, q.x, q.y).get("density", ""))
	var sheltered := _seeded(row, 1.0) < float(SHELTERED.get(density, 0.0))
	if not sheltered:
		return
	# (the shelter a little along from the flag and back from the kerb, where there's room for it)
	var along: Vector2 = r["along"]
	var s := q - face * 1.6 + along * 2.5
	if not clear_of_roads(b.n, s - face * 1.2, CLEAR) or not clear_of_roads(b.n, s + along * 2.0, 0.3) \
			or not clear_of_roads(b.n, s - along * 2.0, 0.3):
		return
	var y := b.ground(s)
	if is_nan(y):
		return
	b.put_at("shelter_" + str(k.get("shelter", "glass")), s, y - 0.05, face)


## A way through a wall or fence the map has at `p` (a field gate, a kissing gate, a stile, a barrier). Across one of
## the ride's roads, its posts either side and the gate swung open along the verge; anywhere else, closed across the
## way, which runs (by `run` for a line, else by the nearest road the way meets) from the road.
static func _crossing(b: _Block, model: String, p: Vector2, row: Array, k: Dictionary, run: Vector2) -> void:
	var r := b.road(p)
	if not r.is_empty() and absf(float(r["lat"])) < float(r["half"]) + RoadNet.VERGE + ACROSS:
		if model != "gate" and model != "lift_gate":
			# (a stile or a kissing gate by the road: the path's, off to the side the map has it)
			_beside(b, model, p, row, r)
			return
		# Across the road: a post either side, the gate (or the barrier's arm) open beside the road on one side.
		var c: Vector2 = r["centre"]
		var right: Vector2 = r["right"]
		var along: Vector2 = r["along"]
		var out := float(r["half"]) + RoadNet.VERGE + WING_OUT
		for side: float in [-1.0, 1.0]:
			var q := c + right * out * side
			if not clear_of_roads(b.n, q, WING_OUT - 0.05):
				continue
			var y := b.ground(q)
			if is_nan(y):
				continue
			var face := -right * side
			if model == "lift_gate":
				b.put_at("barrier_post" if side > 0.0 else "barrier_rest", q, y - 0.05, face)
			else:
				b.put_at("gate_post", q, y - 0.05, face)
				if side > 0.0:
					# (the leaf swung back along the verge, hung from this post: its +x along the road)
					var leaf_to := along if _seeded(row, 2.0) < 1.0 else -along
					var yaw := atan2(-leaf_to.y, leaf_to.x)
					b.put("gate_leaf", Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x - b.corner.x, y - 0.05, q.y - b.corner.y)))
		b.moved += 1
		return
	var at := b.stand(p)
	if is_nan(at.x):
		return
	var q := Vector2(at.x, at.z)
	# The way it's across runs along `run` (a line) or from the road the way meets: the gate spans across it.
	var way: Vector2 = run
	if way == Vector2.ZERO:
		way = -(r["out"] as Vector2) if not r.is_empty() else _dir_of(row, p)
	b.put_at(model + _style(k), q, at.y, way)


## A stile or kissing gate the map puts by the road: where it is, along the road (the path it's on runs off it).
static func _beside(b: _Block, model: String, p: Vector2, row: Array, r: Dictionary) -> void:
	var at := b.stand(p)
	if is_nan(at.x):
		return
	var q := Vector2(at.x, at.z)
	b.put_at(model, q, at.y, -(r["out"] as Vector2) if not r.is_empty() else _dir_of(row, p))


## A cattle grid: across one of the ride's roads, its white wings either side, out from the verge (the grid itself is
## the road's, not ours to paint); anywhere else (a farm track's), its wings and rails where the map has it.
static func _cattle_grid(b: _Block, p: Vector2, row: Array) -> void:
	var r := b.road(p)
	if not r.is_empty() and absf(float(r["lat"])) < float(r["half"]) + RoadNet.VERGE + ACROSS:
		var c: Vector2 = r["centre"]
		var right: Vector2 = r["right"]
		var out := float(r["half"]) + RoadNet.VERGE + WING_OUT
		for side: float in [-1.0, 1.0]:
			var q := c + right * out * side
			if not clear_of_roads(b.n, q, WING_OUT - 0.05):
				continue
			var y := b.ground(q)
			if not is_nan(y):
				# (a wing's +x runs out from the road, its foot at the verge)
				var w := right * side
				b.put("grid_wing", Transform3D(Basis(Vector3.UP, atan2(-w.y, w.x)), Vector3(q.x - b.corner.x, y - 0.05, q.y - b.corner.y)))
		b.moved += 1
		return
	var at := b.stand(p)
	if is_nan(at.x):
		return
	var q := Vector2(at.x, at.z)
	b.put_at("grid_track", q, at.y, -(r["out"] as Vector2) if not r.is_empty() else _dir_of(row, p))


## Where block `b`'s roads cross a boundary between two of a country's regions (a county's, a state's: named
## "LEFT|RIGHT" for the regions either side, D8's), a small boundary sign each way on the side of the road its traffic
## keeps to, facing it, and a boundary stone on the verge at the line. Not on a track or a path.
static func _boundary(b: _Block, row: Array, k: Dictionary) -> void:
	var line: PackedVector2Array = row[1]
	var near := b.box.grow(32.0)
	var segs := PackedVector2Array()
	for j in line.size() - 1:
		if Rect2(line[j], Vector2.ZERO).expand(line[j + 1]).intersects(near, true):
			segs.append(line[j])
			segs.append(line[j + 1])
	if segs.is_empty():
		return
	var n := b.n
	var colour := str(k.get("plate", "white"))
	for e in n.edges_in(b.key):
		if not n.region.class_of(e) in JourneyMarks.BOARD_ROADS:
			continue
		var road := n.line_of(e)
		for i in road.size() - 1:
			var a := road[i]
			var c := road[i + 1]
			for j in range(0, segs.size(), 2):
				var x = Geometry2D.segment_intersects_segment(a, c, segs[j], segs[j + 1])
				if x == null or not b.mine(x):
					continue
				var dir := (c - a).normalized()
				var code := str(RegionKit.at_frame(n.region.frame_lat, n.region.frame_lon, x.x, x.y).get("country", ""))
				var left := str(RegionKit.facts(code).get("drive", "right")) == "left"
				var half := n.width_of(e) * 0.5 + RoadNet.VERGE + CLEAR
				for w in 2:
					var way := dir if w == 0 else -dir
					var right := Vector2(-way.y, way.x)
					var side := -right if left else right
					# (just past the line, where the rider has crossed into the next region, facing them)
					var at: Vector2 = x + way * 6.0 + side * (half + 0.6)
					if clear_of_roads(n, at, CLEAR):
						var y := b.ground(at)
						if not is_nan(y):
							b.put_at("boundary_" + colour, at, y - 0.05, -way)
				var stone: Vector2 = x + Vector2(-dir.y, dir.x) * (half + 0.3)
				if clear_of_roads(n, stone, CLEAR - 0.2):
					var ys := b.ground(stone)
					if not is_nan(ys):
						b.put_at("boundary_stone", stone, ys - 0.05, Vector2(-dir.y, dir.x) * -1.0)


static func _style(k: Dictionary) -> String:
	var s := str(k.get("style", ""))
	return "_" + s if s != "" else ""


## A point's heading as a direction on the ground, or one from its id where the map gives none.
static func _dir_of(row: Array, p: Vector2) -> Vector2:
	var a := deg_to_rad(float(row[5])) if row.size() > 5 and row[5] != null else _seeded(row, TAU, p)
	return Vector2(sin(a), -cos(a))


## A number in [0, top) from the row's id (or where it is): the same on every machine.
static func _seeded(row: Array, top: float, p := Vector2.INF) -> float:
	var seed_of := str(row[7]) if row.size() > 7 and row[7] != null else ""
	if seed_of == "":
		var at := p if p != Vector2.INF else Vector2(float(row[1]), float(row[2]))
		seed_of = "%.1f,%.1f" % [at.x, at.y]
	return float(seed_of.hash() & 0xffff) / 65536.0 * top


# ---------------------------------------------------------------------------- the models

## Every model this script draws, in each of its styles: for the tests, and anyone who'd list them.
static func all_models() -> Array[String]:
	var out: Array[String] = []
	for s: String in LAMP_STYLES:
		for l: String in LIGHTS:
			out.append("lamp_%s_%s" % [s, l])
	for l: String in LIGHTS:
		out.append("pool_" + l)
	for s: String in POST_SHAPES:
		for c: String in POST_COLOURS:
			out.append("%s_%s" % [s, c])
	out.append_array(["bench", "bench_stone", "picnic_table", "charger", "bollard", "bollard_white", "bollard_stone",
		"bus_flag", "bus_flag_pole", "shelter_glass", "shelter_wood", "gate", "gate_metal", "gate_post", "gate_leaf",
		"kissing_gate", "stile", "lift_gate", "barrier_post", "barrier_rest", "grid_wing", "grid_track", "boundary_white",
		"boundary_brown", "boundary_green", "boundary_stone"])
	return out


## The mesh of `model` (built once).
static func mesh(model: String) -> Mesh:
	_meshes_lock.lock()
	var got = _meshes.get(model)
	_meshes_lock.unlock()
	if got != null:
		return got
	var b := _Build.new()
	var head := model.get_slice("_", 0)
	var m: Mesh
	if head == "pool":
		m = _pool(LIGHTS.get(model.get_slice("_", 1), LIGHTS["white"]))
	else:
		match head:
			"lamp":
				_lamp_mesh(b, model.get_slice("_", 1), LIGHTS.get(model.get_slice("_", 2), LIGHTS["white"]))
			"pillar", "box", "drop":
				_post_box_mesh(b, head, POST_COLOURS.get(model.get_slice("_", 1), POST_COLOURS["red"]))
			_:
				match model:
					"bench": _bench(b, WOOD, STEEL)
					"bench_stone": _bench_stone(b)
					"picnic_table": _picnic_table(b)
					"charger": _charger(b)
					"bollard": _bollard(b, DARK, WHITE)
					"bollard_white": _bollard(b, WHITE, Color(0.85, 0.12, 0.1))
					"bollard_stone": _bollard_stone(b)
					"bus_flag": _bus_flag(b, false)
					"bus_flag_pole": _bus_flag(b, true)
					"shelter_glass": _shelter(b, true)
					"shelter_wood": _shelter(b, false)
					"gate": _gate(b, WOOD.lightened(0.15), true)
					"gate_metal": _gate(b, Color(0.42, 0.5, 0.42), true)
					"gate_post": _gate_post(b)
					"gate_leaf": _gate_leaf(b, Color(0.42, 0.5, 0.42))
					"kissing_gate": _kissing_gate(b)
					"stile": _stile(b)
					"lift_gate": _lift_gate(b)
					"barrier_post": _barrier_post(b)
					"barrier_rest": _barrier_rest(b)
					"grid_wing": _grid_wing(b)
					"grid_track": _grid_track(b)
					"boundary_white": _boundary_sign(b, WHITE, Color(0.1, 0.1, 0.1))
					"boundary_brown": _boundary_sign(b, Color(0.4, 0.22, 0.12), WHITE)
					"boundary_green": _boundary_sign(b, Color(0.08, 0.36, 0.2), WHITE)
					"boundary_stone": _boundary_stone(b)
					_: b.box(Vector3(0, 1.0, 0), Vector3(0.3, 2.0, 0.3), Basis(), Color(1, 0, 1))
		m = b.commit(material())
	_meshes_lock.lock()
	_meshes[model] = m
	_meshes_lock.unlock()
	return m


## Builds a mesh of boxes and lathes, vertex coloured, its flags in UV2 (GLOW, LIT, SCREEN).
class _Build:
	var st := SurfaceTool.new()
	var any := false
	var flag := 0.0   # (the flag the next faces take, while set)

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var nrm := (b - a).cross(c - a).normalized()
		for p in [a, b, c]:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.set_uv2(Vector2(flag, 0.0))
			st.add_vertex(p)
		any = true

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	## A box centred `c`, `size`, turned by `basis`.
	func box(c: Vector3, size: Vector3, basis: Basis, col: Color) -> void:
		var h := size * 0.5
		var p := []
		for i in 8:
			p.append(c + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
		var shade := [1.0, 0.92, 0.85, 1.05, 0.95, 0.88]
		var f := 0
		for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			quad(p[q[0]], p[q[1]], p[q[2]], p[q[3]], col * float(shade[f]))
			f += 1

	## A bar from `a` to `b`, `w` square.
	func bar(a: Vector3, b: Vector3, w: float, col: Color) -> void:
		var d := b - a
		var l := d.length()
		if l < 1e-4:
			return
		var y := d / l
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		box((a + b) * 0.5, Vector3(w, l, w), Basis(x, y, z), col)

	## A lathe round the y axis through `at`: rings [[y, r], ...] (from the bottom), `sides` round, capped on top.
	func lathe(at: Vector3, rings: Array, sides: int, col: Color, cap := true) -> void:
		for i in range(rings.size() - 1):
			var y0 := float(rings[i][0])
			var r0 := float(rings[i][1])
			var y1 := float(rings[i + 1][0])
			var r1 := float(rings[i + 1][1])
			for s in sides:
				var a0 := TAU * s / sides
				var a1 := TAU * (s + 1) / sides
				quad(at + Vector3(cos(a0) * r0, y0, sin(a0) * r0), at + Vector3(cos(a0) * r1, y1, sin(a0) * r1),
					at + Vector3(cos(a1) * r1, y1, sin(a1) * r1), at + Vector3(cos(a1) * r0, y0, sin(a1) * r0), col)
		if cap:
			var top: Array = rings[rings.size() - 1]
			var yt := float(top[0])
			var rt := float(top[1])
			if rt > 0.0:
				for s in sides:
					var a0 := TAU * s / sides
					var a1 := TAU * (s + 1) / sides
					tri(at + Vector3(0, yt, 0), at + Vector3(cos(a1) * rt, yt, sin(a1) * rt), at + Vector3(cos(a0) * rt, yt, sin(a0) * rt), col)

	## A lamp's glow at `at`, `size` across, that the shader turns to the camera and lights at night.
	func glow(at: Vector3, size: float, col: Color) -> void:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			st.set_normal(Vector3.UP)
			st.set_color(col)
			st.set_uv(corner)
			st.set_uv2(Vector2(Furniture.GLOW, size))
			st.add_vertex(at)
		any = true

	func commit(mat: Material) -> Mesh:
		var m := st.commit() if any else ArrayMesh.new()
		if m.get_surface_count() > 0:
			m.surface_set_material(0, mat)
		return m


## A street lamp, its foot at the origin, its light out over +z (the road): `style` "column" (a galvanised column
## curving over into a slim LED head), "lantern" (a black post with a four-sided lantern on top), "concrete" (a tapered
## concrete column, a long outreach and a bowl head); `light` its colour.
static func _lamp_mesh(b: _Build, style: String, light: Color) -> void:
	match style:
		"lantern":
			b.lathe(Vector3.ZERO, [[0.0, 0.16], [0.35, 0.14], [0.45, 0.09], [3.2, 0.06], [3.35, 0.09], [3.45, 0.07]], 8, DARK)
			b.lathe(Vector3(0, 3.45, 0), [[0.0, 0.12], [0.1, 0.26]], 4, DARK, false)
			b.flag = LIT
			b.lathe(Vector3(0, 3.55, 0), [[0.0, 0.24], [0.55, 0.3]], 4, light.darkened(0.15), false)
			b.flag = 0.0
			b.lathe(Vector3(0, 4.1, 0), [[0.0, 0.36], [0.3, 0.06], [0.42, 0.0]], 4, DARK)
			b.glow(Vector3(0, 3.8, 0), 0.35, light)
		"concrete":
			var con := Color(0.66, 0.65, 0.62)
			b.lathe(Vector3.ZERO, [[0.0, 0.17], [8.6, 0.09]], 8, con)
			var top := Vector3(0, 8.6, 0)
			var end := Vector3(0, 8.95, ARM + 0.8)
			b.bar(top, end, 0.07, STEEL)
			b.lathe(end + Vector3(0, -0.22, 0), [[0.0, 0.0], [0.08, 0.3], [0.2, 0.32], [0.24, 0.12]], 8, Color(0.45, 0.46, 0.48))
			b.flag = LIT
			b.lathe(end + Vector3(0, -0.24, 0), [[0.0, 0.0], [0.03, 0.28]], 8, light, false)
			b.flag = 0.0
			b.glow(end + Vector3(0, -0.3, 0), 0.45, light)
		_:
			b.lathe(Vector3.ZERO, [[0.0, 0.11], [0.6, 0.1], [7.6, 0.06]], 8, STEEL)
			# (the column bends over towards the road in three short bars, to a flat head)
			var pts := [Vector3(0, 7.6, 0), Vector3(0, 7.95, 0.35), Vector3(0, 8.1, 0.9), Vector3(0, 8.1, ARM)]
			for i in range(pts.size() - 1):
				b.bar(pts[i], pts[i + 1], 0.09, STEEL)
			var head: Vector3 = pts[pts.size() - 1]
			b.box(head + Vector3(0, -0.02, 0.05), Vector3(0.28, 0.1, 0.62), Basis(), Color(0.38, 0.4, 0.42))
			b.flag = LIT
			b.box(head + Vector3(0, -0.08, 0.05), Vector3(0.22, 0.02, 0.5), Basis(), light)
			b.flag = 0.0
			b.glow(head + Vector3(0, -0.14, 0.05), 0.4, light)


## A lamp's pool of light on the ground: a disc POOL_R across, only drawn at night, added to what's under it.
static func _pool(light: Color) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for v: Vector3 in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]:
			st.set_normal(Vector3.UP)
			st.set_color(light)
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v * POOL_R)
	var m := st.commit()
	m.surface_set_material(0, pool_material())
	return m


## A post box, its slot to +z: a round "pillar" (a cap on top), a "box" on a post, or a US-style "drop" on legs.
static func _post_box_mesh(b: _Build, shape: String, col: Color) -> void:
	match shape:
		"pillar":
			b.lathe(Vector3.ZERO, [[0.0, 0.3], [0.12, 0.3], [0.14, 0.25], [1.25, 0.25], [1.32, 0.29], [1.42, 0.27],
				[1.52, 0.18], [1.58, 0.0]], 12, col)
			b.box(Vector3(0, 1.08, 0.24), Vector3(0.28, 0.04, 0.04), Basis(), DARK)
			b.box(Vector3(0, 0.82, 0.25), Vector3(0.22, 0.16, 0.02), Basis(), WHITE)
		"drop":
			for x: float in [-0.22, 0.22]:
				for z: float in [-0.2, 0.2]:
					b.box(Vector3(x, 0.25, z), Vector3(0.05, 0.5, 0.05), Basis(), col.darkened(0.2))
			b.box(Vector3(0, 0.82, 0), Vector3(0.5, 0.65, 0.48), Basis(), col)
			b.lathe(Vector3(0, 1.14, 0), [[0.0, 0.25], [0.12, 0.2], [0.2, 0.0]], 8, col)
			b.box(Vector3(0, 1.0, 0.25), Vector3(0.28, 0.1, 0.03), Basis(), col.darkened(0.3))
		_:
			b.box(Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), Basis(), Color(0.3, 0.32, 0.33))
			b.box(Vector3(0, 1.2, 0.04), Vector3(0.45, 0.55, 0.3), Basis(), col)
			b.box(Vector3(0, 1.5, 0.04), Vector3(0.5, 0.06, 0.34), Basis(), col.darkened(0.15))
			b.box(Vector3(0, 1.35, 0.2), Vector3(0.3, 0.03, 0.02), Basis(), DARK)
			b.box(Vector3(0, 1.15, 0.2), Vector3(0.2, 0.12, 0.01), Basis(), WHITE)


## A bench (`seat`, on legs of `legs`), its seat to +z.
static func _bench(b: _Build, seat: Color, legs: Color) -> void:
	for x: float in [-0.75, 0.75]:
		b.box(Vector3(x, 0.22, 0), Vector3(0.07, 0.44, 0.48), Basis(), legs)
		b.box(Vector3(x, 0.62, -0.23), Vector3(0.07, 0.4, 0.06), Basis(), legs)
		b.box(Vector3(x, 0.62, 0.02), Vector3(0.06, 0.06, 0.5), Basis(), legs)
	for z: float in [-0.14, 0.0, 0.14]:
		b.box(Vector3(0, 0.46, z), Vector3(1.8, 0.04, 0.11), Basis(), seat.darkened(absf(z)))
	for y: float in [0.62, 0.78]:
		b.box(Vector3(0, y, -0.25), Vector3(1.8, 0.11, 0.035), Basis(Vector3.RIGHT, -0.15), seat)


## A stone bench: a slab on two blocks.
static func _bench_stone(b: _Build) -> void:
	var stone := Color(0.7, 0.67, 0.6)
	for x: float in [-0.6, 0.6]:
		b.box(Vector3(x, 0.2, 0), Vector3(0.3, 0.4, 0.4), Basis(), stone.darkened(0.08))
	b.box(Vector3(0, 0.45, 0), Vector3(1.8, 0.1, 0.48), Basis(), stone)


## A picnic table with its benches, along x.
static func _picnic_table(b: _Build) -> void:
	b.box(Vector3(0, 0.74, 0), Vector3(1.9, 0.05, 0.75), Basis(), WOOD.lightened(0.1))
	for z: float in [-0.62, 0.62]:
		b.box(Vector3(0, 0.44, z), Vector3(1.9, 0.045, 0.28), Basis(), WOOD)
	for x: float in [-0.7, 0.7]:
		# (the A-frame legs, splayed under the top, and the bearer the benches sit on)
		for s: float in [-1.0, 1.0]:
			b.bar(Vector3(x, 0.0, 0.62 * s), Vector3(x, 0.72, 0.12 * s), 0.07, WOOD.darkened(0.1))
		b.box(Vector3(x, 0.4, 0), Vector3(0.07, 0.07, 1.6), Basis(), WOOD.darkened(0.1))


## A charging point: a white pillar on a plinth, its screen and sockets to +z, a ring of green light round its top.
static func _charger(b: _Build) -> void:
	b.box(Vector3(0, 0.06, 0), Vector3(0.6, 0.12, 0.45), Basis(), Color(0.6, 0.6, 0.58))
	b.box(Vector3(0, 0.85, 0), Vector3(0.42, 1.5, 0.28), Basis(), Color(0.92, 0.93, 0.92))
	b.box(Vector3(0, 1.62, 0), Vector3(0.44, 0.06, 0.3), Basis(), Color(0.15, 0.6, 0.35))
	b.flag = SCREEN
	b.box(Vector3(0, 1.3, 0.141), Vector3(0.24, 0.18, 0.01), Basis(), Color(0.3, 0.7, 0.9))
	b.flag = 0.0
	for x: float in [-0.1, 0.1]:
		b.box(Vector3(x, 1.0, 0.15), Vector3(0.1, 0.1, 0.04), Basis(), DARK)
	# (a cable hung on its side)
	b.bar(Vector3(0.22, 1.0, 0.05), Vector3(0.3, 0.45, 0.08), 0.03, DARK)
	b.bar(Vector3(0.3, 0.45, 0.08), Vector3(0.24, 0.85, 0.1), 0.03, DARK)


## A bollard (`col`, banded `band` near the top).
static func _bollard(b: _Build, col: Color, band: Color) -> void:
	b.lathe(Vector3.ZERO, [[0.0, 0.08], [0.9, 0.08], [0.98, 0.06], [1.02, 0.0]], 8, col)
	b.lathe(Vector3(0, 0.78, 0), [[0.0, 0.085], [0.07, 0.085]], 8, band, false)


## A stone bollard: a squat dressed block with a rounded top.
static func _bollard_stone(b: _Build) -> void:
	var stone := Color(0.66, 0.63, 0.57)
	b.box(Vector3(0, 0.3, 0), Vector3(0.28, 0.6, 0.28), Basis(), stone)
	b.lathe(Vector3(0, 0.6, 0), [[0.0, 0.18], [0.1, 0.12], [0.16, 0.0]], 6, stone)


## A bus stop's flag: a sign on a pole (on a plain painted pole, or a sturdier one with a timetable case), its face
## along x so it's read from up and down the road.
static func _bus_flag(b: _Build, plain: bool) -> void:
	b.box(Vector3(0, 1.45, 0), Vector3(0.07, 2.9, 0.07), Basis(), STEEL if plain else Color(0.2, 0.22, 0.24))
	b.box(Vector3(0.0, 2.6, 0), Vector3(0.02, 0.45, 0.45), Basis(), Color(0.9, 0.9, 0.86))
	b.box(Vector3(0.0, 2.6, 0), Vector3(0.025, 0.3, 0.3), Basis(), Color(0.15, 0.35, 0.65))
	if not plain:
		b.box(Vector3(0.0, 1.5, 0), Vector3(0.04, 0.5, 0.32), Basis(), Color(0.85, 0.85, 0.82))


## A bus shelter, its open side to +z (the road): steel frame and glass (or wood, open-fronted, a country one).
static func _shelter(b: _Build, glass: bool) -> void:
	var frame := Color(0.25, 0.27, 0.3) if glass else WOOD
	for x: float in [-1.6, 1.6]:
		for z: float in [-0.65, 0.65]:
			b.box(Vector3(x, 1.15, z), Vector3(0.07, 2.3, 0.07), Basis(), frame)
	b.box(Vector3(0, 2.35, 0.05), Vector3(3.5, 0.08, 1.6), Basis(Vector3.RIGHT, -0.05), frame.darkened(0.1) if glass else Color(0.35, 0.3, 0.28))
	var pane := GLASS if glass else WOOD.lightened(0.08)
	b.box(Vector3(0, 1.25, -0.65), Vector3(3.2, 1.9, 0.02), Basis(), pane)
	for x: float in [-1.6, 1.6]:
		b.box(Vector3(x, 1.25, 0.0), Vector3(0.02, 1.9, 1.2), Basis(), pane)
	b.box(Vector3(0, 0.48, -0.42), Vector3(2.0, 0.05, 0.3), Basis(), frame)
	if glass:
		# (the advert panel at one end, lit at night)
		b.flag = SCREEN
		b.box(Vector3(1.62, 1.25, 0.0), Vector3(0.03, 1.5, 0.95), Basis(), Color(0.85, 0.82, 0.7))
		b.flag = 0.0


## A field gate, closed across the way (along x, 3.6 m between its posts), five bars and a brace.
static func _gate(b: _Build, col: Color, posts: bool) -> void:
	if posts:
		for x: float in [-1.9, 1.9]:
			b.box(Vector3(x, 0.65, 0), Vector3(0.18, 1.4, 0.18), Basis(), GREY_WOOD)
	for i in 5:
		b.box(Vector3(0, 0.25 + i * 0.21, 0), Vector3(3.6, 0.07, 0.04), Basis(), col)
	for x: float in [-1.75, 1.75]:
		b.box(Vector3(x, 0.66, 0), Vector3(0.08, 1.15, 0.05), Basis(), col)
	b.bar(Vector3(-1.7, 0.25, 0), Vector3(1.6, 1.05, 0), 0.05, col)


## A gatepost at a road's verge.
static func _gate_post(b: _Build) -> void:
	b.box(Vector3(0, 0.7, 0), Vector3(0.2, 1.5, 0.2), Basis(), GREY_WOOD)
	b.lathe(Vector3(0, 1.45, 0), [[0.0, 0.1], [0.08, 0.0]], 4, GREY_WOOD.darkened(0.1))


## A gate's leaf hung open from its post at the origin, running along +x (3.6 m), five bars and a brace.
static func _gate_leaf(b: _Build, col: Color) -> void:
	for i in 5:
		b.box(Vector3(1.9, 0.25 + i * 0.21, 0), Vector3(3.6, 0.06, 0.04), Basis(), col)
	for x: float in [0.15, 3.65]:
		b.box(Vector3(x, 0.66, 0), Vector3(0.07, 1.15, 0.05), Basis(), col)
	b.bar(Vector3(0.2, 0.25, 0), Vector3(3.5, 1.05, 0), 0.05, col)


## A kissing gate: a little half-round pen of rails, its gate swinging inside it, the way through along z.
static func _kissing_gate(b: _Build) -> void:
	for x: float in [-1.1, 1.1]:
		b.box(Vector3(x, 0.6, 0), Vector3(0.14, 1.25, 0.14), Basis(), GREY_WOOD)
	for i in 5:
		var a := PI * i / 4.0
		var p := Vector3(cos(a) * 0.9, 0, -sin(a) * 0.9)
		b.box(p + Vector3(0, 0.55, 0), Vector3(0.1, 1.1, 0.1), Basis(), GREY_WOOD)
		if i > 0:
			var a0 := PI * (i - 1) / 4.0
			var q := Vector3(cos(a0) * 0.9, 0, -sin(a0) * 0.9)
			for y: float in [0.45, 0.95]:
				b.bar(q + Vector3(0, y, 0), p + Vector3(0, y, 0), 0.05, GREY_WOOD)
	b.box(Vector3(0.45, 0.6, -0.4), Vector3(0.9, 0.9, 0.04), Basis(Vector3.UP, 0.6), WOOD.lightened(0.15))
	# (the wall it's in, either side, a little way)
	for x: float in [-1.75, 1.75]:
		b.box(Vector3(x, 0.5, 0), Vector3(1.2, 1.0, 0.5), Basis(), Color(0.45, 0.43, 0.38))


## A stile: steps over a short run of dry-stone wall, the way over along z.
static func _stile(b: _Build) -> void:
	var stone := Color(0.45, 0.43, 0.38)
	b.box(Vector3(0, 0.55, 0), Vector3(3.0, 1.1, 0.55), Basis(), stone)
	for z: float in [-0.5, 0.5]:
		b.box(Vector3(0, 0.38, z), Vector3(0.6, 0.06, 0.25), Basis(), GREY_WOOD)
		b.box(Vector3(-0.25, 0.19, z), Vector3(0.06, 0.38, 0.06), Basis(), GREY_WOOD)
		b.box(Vector3(0.25, 0.19, z), Vector3(0.06, 0.38, 0.06), Basis(), GREY_WOOD)
	b.box(Vector3(0.38, 1.0, 0), Vector3(0.08, 2.0, 0.08), Basis(), GREY_WOOD)


## A barrier across a way: a post, its red and white arm down across it (along x, 4 m), its rest at the far end.
static func _lift_gate(b: _Build) -> void:
	_barrier_post(b)
	_arm(b, Vector3(0.15, 1.0, 0), Vector3(4.2, 1.0, 0))
	b.box(Vector3(4.3, 0.5, 0), Vector3(0.1, 1.0, 0.1), Basis(), WHITE)


## A barrier's post and its arm raised up out of the road.
static func _barrier_post(b: _Build) -> void:
	b.box(Vector3(0, 0.55, 0), Vector3(0.35, 1.1, 0.3), Basis(), Color(0.85, 0.82, 0.25))
	b.box(Vector3(0, 1.0, 0), Vector3(0.1, 0.14, 0.4), Basis(), STEEL)
	_arm(b, Vector3(0, 1.1, 0.12), Vector3(0, 5.0, 0.4))


## The rest a barrier's arm lies on, the far side.
static func _barrier_rest(b: _Build) -> void:
	b.box(Vector3(0, 0.5, 0), Vector3(0.1, 1.0, 0.1), Basis(), WHITE)
	b.box(Vector3(0, 1.0, 0), Vector3(0.12, 0.08, 0.3), Basis(), WHITE)


## A barrier's arm from `a` to `b`, banded red and white.
static func _arm(b: _Build, a: Vector3, c: Vector3) -> void:
	var n := 8
	for i in n:
		b.bar(a.lerp(c, float(i) / n), a.lerp(c, float(i + 1) / n), 0.08,
			Color(0.82, 0.1, 0.08) if i % 2 == 0 else WHITE)


## A cattle grid's wing: a short run of white rails from the verge out (along +x, 2.4 m) to a stone post.
static func _grid_wing(b: _Build) -> void:
	for x: float in [0.0, 1.2, 2.4]:
		b.box(Vector3(x, 0.55, 0), Vector3(0.14, 1.1, 0.14), Basis(), WHITE)
	for y: float in [0.45, 0.9]:
		b.box(Vector3(1.2, y, 0), Vector3(2.5, 0.08, 0.06), Basis(), WHITE)
	b.box(Vector3(2.9, 0.6, 0), Vector3(0.45, 1.2, 0.45), Basis(), Color(0.47, 0.45, 0.4))


## A cattle grid on a farm track: its rails over a pit (along x, the way over along z), a wing either side.
static func _grid_track(b: _Build) -> void:
	b.box(Vector3(0, -0.02, 0), Vector3(3.2, 0.04, 2.4), Basis(), Color(0.06, 0.06, 0.06))
	for i in 12:
		b.box(Vector3(0, 0.03, -1.1 + i * 0.2), Vector3(3.2, 0.06, 0.07), Basis(), Color(0.32, 0.3, 0.28))
	for x: float in [-1.75, 1.75]:
		b.box(Vector3(x, 0.5, 0), Vector3(0.12, 1.0, 2.2), Basis(), WHITE)


## A region's boundary sign: a plate on two posts, its face (+z) `plate` with a band of `ink` over a crest's shield
## (the words a region's own name would need aren't in the map's data).
static func _boundary_sign(b: _Build, plate: Color, ink: Color) -> void:
	for x: float in [-0.55, 0.55]:
		b.box(Vector3(x, 0.8, -0.03), Vector3(0.07, 1.6, 0.07), Basis(), STEEL)
	b.box(Vector3(0, 1.45, 0), Vector3(1.4, 0.8, 0.04), Basis(), plate)
	b.box(Vector3(0, 1.45, 0.022), Vector3(1.3, 0.7, 0.01), Basis(), plate.lightened(0.05))
	b.box(Vector3(0.18, 1.5, 0.03), Vector3(0.8, 0.09, 0.01), Basis(), ink)
	b.box(Vector3(0.12, 1.32, 0.03), Vector3(0.68, 0.06, 0.01), Basis(), ink)
	b.box(Vector3(-0.48, 1.45, 0.03), Vector3(0.24, 0.3, 0.01), Basis(), Color(0.72, 0.12, 0.1))
	b.box(Vector3(-0.48, 1.32, 0.03), Vector3(0.12, 0.08, 0.01), Basis(), Color(0.72, 0.12, 0.1))


## An old boundary stone: a squat stone, rounded on top, its faces lettered either way.
static func _boundary_stone(b: _Build) -> void:
	var stone := Color(0.68, 0.66, 0.6)
	b.box(Vector3(0, 0.3, 0), Vector3(0.4, 0.6, 0.22), Basis(), stone)
	b.lathe(Vector3(0, 0.6, 0), [[0.0, 0.2], [0.1, 0.15], [0.16, 0.0]], 8, stone)
	for z: float in [-0.112, 0.112]:
		b.box(Vector3(0, 0.42, z), Vector3(0.26, 0.04, 0.01), Basis(), Color(0.2, 0.2, 0.2))


# ---------------------------------------------------------------------------- the shaders

static func material() -> ShaderMaterial:
	if _material == null:
		var s := Shader.new()
		s.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = s
	return _material


static func pool_material() -> ShaderMaterial:
	if _pool_material == null:
		var s := Shader.new()
		s.code = POOL_SHADER
		_pool_material = ShaderMaterial.new()
		_pool_material.shader = s
	return _pool_material


## Moves the night on (the lamps, their pools and the screens): once a frame, by whichever block's ticker gets there
## first.
static func tick() -> void:
	var f := Engine.get_process_frames()
	if f == _ticked:
		return
	_ticked = f
	var night := Daylight.current.lamps if Daylight.current != null else 0.0
	material().set_shader_parameter("night", night)
	pool_material().set_shader_parameter("night", night)


const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float night = 0.0;   // 0 by day .. 1 with the lamps on (Daylight.lamps)
varying float glow;
varying float lit;

void vertex() {
	glow = 0.0;
	lit = 0.0;
	float flag = UV2.x;
	if (flag > 2.5 && flag < 3.5) {
		// A lamp's glow: a square to the camera, kept a few pixels across however far, there only at night.
		vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float size = max(UV2.y, -c.z * 0.003) * step(0.01, night);
		c.xy += UV * size;
		POSITION = PROJECTION_MATRIX * c;
		glow = night;
	} else {
		POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
		if (flag > 3.5 && flag < 4.5) {
			lit = night;
		} else if (flag > 5.5) {
			lit = 0.15 + 0.6 * night;
		}
	}
}

void fragment() {
	if (glow > 0.0) {
		ALBEDO = vec3(0.0);
		EMISSION = COLOR.rgb * 8.0 * glow;
	} else {
		ALBEDO = COLOR.rgb;
		EMISSION = COLOR.rgb * 4.0 * lit;
	}
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
"""

const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float night = 0.0;   // 0 by day .. 1 with the lamps on (Daylight.lamps)

void vertex() {
	// (nothing at all by day: the disc folded to a point)
	VERTEX *= step(0.01, night);
}

void fragment() {
	float r = length(UV);
	float fall = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = COLOR.rgb * fall * fall * 0.35 * night;
}
"""
