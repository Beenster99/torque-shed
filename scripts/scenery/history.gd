class_name History
extends RefCounted
## History (Ride Anywhere v2, phase D round 2, D6: interfaces/scenery.md): the walled towns, their walls along the
## line the map has them on with towers along the top and a gate over every road that goes through, floodlit at night;
## gates and sally ports where the map has them; monuments, statues, memorials and stone circles; artwork with its name
## on a board; viewpoints as a gravelled pull-in with a bench and a panorama board; fountains, milestones and the
## information boards along the way. (The buildings' own looks, from the same map, are BuildingLooks' and
## RegionBuildings': a church, a mosque, a hangar, a town's real roofs.)
##
## The streamer (SceneryStreamer) hands lay_out a block's rows of the kinds whose kit row names "history:MODEL", each
## with its kit (the default with the place's region laid over it), and draws what comes back: one MultiMesh a model a
## block. Everything is built of a few unit pieces stood and stretched by its transform (a wall a mile round is a few
## hundred pieces of one mesh); the names on the boards are put up by dress, on the main thread.
##
## Simon's first rule, as here: nothing stands on a road or its verge (a wall stops CLEAR past the verge either side of
## a road through it, and a thing the map puts on a road is stood off it), a gate's arch over a road clears it by the
## bridges' headroom (RoadNet.HEADROOM and its pad) all the way across, and nothing here has collision. The second: every
## kind wherever the map has it, its stone and towers by region from the kit library's rows, with a default for
## anywhere; nothing is keyed to a place.

## Part of what a block lays out (with BuildingLooks' after it): bump it with the look. SceneryStreamer folds the
## scripts' versions into the builder hash.
const VERSION := 100 + BuildingLooks.VERSION
const SIZE := 512.0   # RoadBlock.SIZE
## A wall's pieces are this long (m), measured from its first point, so a wall over two blocks meets itself.
const STEP := 3.0
## How far past a road's verge a wall's face (or anything here) keeps (m: SceneryStreamer.CLEAR's).
const CLEAR := 1.5
## A run of a wall over a road no longer than this (m) is a gate; a longer one is a wall the road runs along, left out.
const GATE_MOST := 40.0
## Clear under a gate's arch over a road (m): the bridges' headroom and its pad.
const HEADROOM := RoadNet.HEADROOM + RoadNet.HEADROOM_PAD
## No tower of the wall's own within this of a mapped one (m: the skyline draws those) or of a gate.
const TOWER_NEAR := 22.0
## How far a wall's floodlights are apart (m).
const FLOOD_EVERY := 24.0
## A line's ends within this of another's (m) are one wall (the baker cuts lines at each cell's edge).
const JOIN := 0.6
## A monument by its name (lower case, any word of it): which model it is. Anything else named is a board only.
const MONUMENT_WORDS := {
	"stones": ["stone circle", "standing stone", "stones", "menhir", "dolmen", "cromlech", "henge", "megalith", "cairn",
		"carn", "quoit", "maen", "sten", "pierre", "dolmen"],
	"obelisk": ["obelisk", "column", "pillar", "needle", "monument"],
	"cross": ["cross", "cenotaph", "memorial", "war memorial", "calvary", "calvaire", "kreuz", "marterl"],
	"statue": ["statue", "figure", "bust", "sculpture", "estatua", "statua", "denkmal"],
}
## The stones walls and gates come in (a kit's "stone"), as vertex colours.
const STONES := {"grey": Color(0.42, 0.41, 0.37), "sand": Color(0.76, 0.66, 0.5), "brick": Color(0.52, 0.28, 0.21),
	"earth": Color(0.72, 0.52, 0.36), "dark": Color(0.36, 0.35, 0.33), "white": Color(0.86, 0.84, 0.78),
	"red": Color(0.62, 0.36, 0.26)}
const WOOD := Color(0.36, 0.26, 0.18)
const BROWN := Color(0.36, 0.2, 0.12)
const STEEL := Color(0.3, 0.32, 0.34)
const LAMP := Color(1.0, 0.86, 0.6)
## Shader flags, a vertex's UV2.x: a face lit by floodlight at night (UV2.y how much), a lamp lit at night.
const FLOOD := 5.0
const STEADY := 3.0

static var _meshes := {}
static var _meshes_lock := Mutex.new()
static var _walls := {}          # region instance id -> {"walls": [{pts, kit, ...}], "plans": {wall index: plan}}
static var _walls_lock := Mutex.new()
static var _material: ShaderMaterial
static var _ticked := -1


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of the rows (SceneryStreamer's: {points, lines, areas}, each [row, kit]) whose kit names
## this script: {items: {model: [Transform3D in the block's frame]}, dress: {labels: [[text, Transform3D]]}}. Safe on
## a worker.
static func lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var b := _Block.new(net, key)
	for pair: Array in rows.get("points", []):
		var row: Array = pair[0]
		var p := Vector2(float(row[1]), float(row[2]))
		if b.mine(p):
			_point(b, str(row[0]), p, row, pair[1])
	var walls := false
	for pair: Array in rows.get("areas", []):
		var row: Array = pair[0]
		var ring: PackedVector2Array = row[1]
		if str(row[0]) == "city_wall":
			walls = true   # (a wall mapped as an outline: its ring is the wall, _join_walls)
		elif ring.size() >= 3 and b.mine(_centre(ring)):
			# (an area's thing at its middle, sized to it: a fountain's basin, an artwork's plot)
			_point(b, str(row[0]), _centre(ring), [row[0], 0.0, 0.0, row[2], row[3], null, row[4], row[5]], pair[1],
				sqrt(absf(_signed_area(ring)) / PI))
	for pair: Array in rows.get("lines", []):
		if str(pair[0][0]) == "city_wall":
			walls = true
		elif b.mine(pair[0][1][0]):
			# (any other line: its first point's thing, as a point of it)
			var row: Array = pair[0]
			var p: Vector2 = row[1][0]
			_point(b, str(row[0]), p, [row[0], p.x, p.y, row[2], null, null, row[5], row[6]], pair[1])
	if walls:
		_walls_in(b)
	# (dress puts the names up, and the ticker that brings the floodlights and lamps on at dusk)
	return {"items": b.items, "moved": b.moved, "skipped": b.skipped, "dress": {"labels": b.labels}}


## The names on a block's boards: Label3Ds on the main thread, once the block is in the world.
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary:
		return
	var t := _Tick.new()
	t.name = "HistoryTick"
	node.add_child(t)
	for l: Array in (data as Dictionary).get("labels", []):
		var label := Label3D.new()
		label.text = str(l[0])
		label.transform = l[1]
		label.pixel_size = 0.004
		label.font_size = 48
		label.outline_size = 0
		label.modulate = Color(0.97, 0.95, 0.88)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = 380.0
		label.double_sided = false
		label.visibility_range_end = 120.0
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(label)


class _Tick extends Node:
	func _process(_delta: float) -> void:
		History.tick()


## A block's laying out: where it is, the roads, what it has made so far.
class _Block:
	var n: RoadNet
	var key: Vector2i
	var corner: Vector2
	var box: Rect2
	var items := {}
	var labels := []
	var memo := {}
	var moved := 0
	var skipped := 0

	func _init(net: RoadNet, k: Vector2i) -> void:
		n = net
		key = k
		corner = Vector2(k) * SIZE
		box = Rect2(corner, Vector2.ONE * SIZE)

	## Whether region-frame `p` is this block's (each thing is the block's its middle is in).
	func mine(p: Vector2) -> bool:
		return box.has_point(p)

	func put(model: String, xf: Transform3D) -> void:
		if not items.has(model):
			items[model] = []
		(items[model] as Array).append(xf)

	## Region-frame (x, y, z) into the block's frame.
	func local(p: Vector2, y: float) -> Vector3:
		return Vector3(p.x - corner.x, y, p.y - corner.y)

	## The land as drawn at `p`, the roads' banks cut in (RoadNet.ground_at); NAN beyond the land held.
	func ground(p: Vector2) -> float:
		var bare := float(n.height.call(p.x, p.y))
		if is_nan(bare) or n._near(p.x, p.y).is_empty():
			return bare
		return n.ground_at(p.x, p.y, bare, memo)

	## Where a thing at `p` stands, off any road (SceneryStreamer.stand), in the region frame; NAN where it can't.
	func stand(p: Vector2) -> Vector3:
		var at := SceneryStreamer.stand(n, p, memo)
		if is_nan(at.x):
			skipped += 1
		elif not is_equal_approx(at.x, p.x) or not is_equal_approx(at.z, p.y):
			moved += 1
		return at

	## Whether `p` is `pad` past the verge of every road (and out of every junction).
	func clear(p: Vector2, pad := CLEAR) -> bool:
		return History.clear_of_roads(n, p, pad)

	## The way from `p` to the nearest road within 60 m (a unit direction on the ground), or ZERO where none is.
	func to_road(p: Vector2) -> Vector2:
		if n._near(p.x, p.y).is_empty():
			return Vector2.ZERO
		var on := n.locate(p.x, p.y, -1, false)
		if on.is_empty():
			return Vector2.ZERO
		var q := n.point_at(int(on["edge"]), float(on["s"]))
		return (q - p).normalized() if q.distance_to(p) > 0.5 and q.distance_to(p) < 60.0 else Vector2.ZERO


## Whether region-frame `p` is `pad` past the verge of every road near it and out of every junction.
static func clear_of_roads(n: RoadNet, p: Vector2, pad := CLEAR) -> bool:
	if n._near(p.x, p.y).is_empty():
		return true
	var on := n.locate(p.x, p.y, -1, false)
	if on.is_empty():
		return true
	if int(on["node"]) >= 0:
		return false
	return absf(float(on["lat"])) >= float(on["width"]) * 0.5 + RoadNet.VERGE + pad


# ---------------------------------------------------------------------------- the things at a point

## A point's thing (or an area's, at its middle, `r` its size), as its kit's model says.
static func _point(b: _Block, kind: String, p: Vector2, row: Array, k: Dictionary, r := 0.0) -> void:
	var model := _model_of(k)
	if model == "" or model == "none":
		return
	var name := str(row[6]) if row[6] != null else ""
	match model:
		"monument":
			_monument(b, p, row, name, k)
		"viewpoint":
			_viewpoint(b, p, row, k)
		"sally":
			_sally(b, p, row, k)
		_:
			var at := b.stand(p)
			if is_nan(at.x):
				return
			var face := _facing(b, p, row)
			var scale := 1.0
			if model == "fountain" and r > 1.5:
				scale = clampf(r / 2.5, 0.8, 3.0)
			b.put(model, Transform3D(Basis(Vector3.UP, _yaw(face)).scaled(Vector3.ONE * scale), b.local(Vector2(at.x, at.z), at.y)))
			if name != "" and bool(k.get("named", false)):
				_name_board(b, Vector2(at.x, at.z), at.y, face, name, 1.6 * scale + 1.0)


## A monument by its name: a stone circle or a standing stone, an obelisk, a cross, a statue on its plinth, or (a
## name that says none of them) its name on a board at the roadside.
static func _monument(b: _Block, p: Vector2, row: Array, name: String, k: Dictionary) -> void:
	var what := monument_model(name)
	if what == "stones" and not b.clear(p, 14.0):
		what = "standing_stone"   # (no room for the ring this near a road)
	if what == "":
		what = "heritage"
	var at := b.stand(p)
	if is_nan(at.x):
		return
	var face := _facing(b, p, row)
	var spin := _seeded(row, TAU) if what in ["stones", "standing_stone"] else _yaw(face)
	b.put(what, Transform3D(Basis(Vector3.UP, spin), b.local(Vector2(at.x, at.z), at.y)))
	if name != "" and what != "heritage":
		# (its name on a board in front of it, on the road's side)
		var off := (face if face != Vector2.ZERO else Vector2(0, 1)) * (11.0 if what == "stones" else 2.6)
		var q := Vector2(at.x, at.z) + off
		if b.clear(q):
			var y := b.ground(q)
			if not is_nan(y):
				_name_board(b, q, y, face, name, 0.0)
	elif name != "":
		_label(b, Vector2(at.x, at.z), at.y, face, name, 1.95, 1.5)


## Which model a monument named `name` is ("stones", "obelisk", "cross", "statue"), or "" for a board only.
static func monument_model(name: String) -> String:
	var low := " " + name.to_lower() + " "
	for model: String in ["stones", "cross", "statue", "obelisk"]:
		for w: String in MONUMENT_WORDS[model]:
			if low.contains(" " + w + " ") or low.contains(" " + w + ",") or (w.length() > 6 and low.contains(w)):
				return model
	return ""


## A viewpoint: a gravelled pull-in beside the road, a bench looking out and a panorama board, facing away from the
## road (or the way the map says).
static func _viewpoint(b: _Block, p: Vector2, row: Array, k: Dictionary) -> void:
	var road := b.to_road(p)
	var out := -road if road != Vector2.ZERO else _dir_of(row)
	if row[5] != null:
		out = _dir_of(row)
	# (stood back from the road: the pull-in's road edge CLEAR past the verge, never on it)
	var q := p
	if road != Vector2.ZERO and not b.clear(p, 5.0):
		for _i in 6:
			q -= road * 2.0
			if b.clear(q, 5.0):
				break
	if not b.clear(q, 4.0):
		b.skipped += 1
		return
	var y := b.ground(q)
	if is_nan(y):
		b.skipped += 1
		return
	var yaw := _yaw(out)
	b.put("pull_in", Transform3D(Basis(Vector3.UP, yaw), b.local(q, y - 0.08)))
	var side := Vector2(out.y, -out.x)
	for spot: Array in [["bench", q + out * 1.6 - side * 1.6], ["panorama", q + out * 2.2 + side * 1.8]]:
		var s: Vector2 = spot[1]
		var sy := b.ground(s)
		if not is_nan(sy):
			b.put(str(spot[0]), Transform3D(Basis(Vector3.UP, yaw), b.local(s, sy - 0.05)))
	var name := str(row[6]) if row[6] != null else ""
	if name != "":
		_label(b, q + out * 2.2 + side * 1.8, b.ground(q + out * 2.2 + side * 1.8), -out, name, 1.25, 1.1)


## A sally port or a mapped city gate: a small gateway through the wall it's in, turned along the wall.
static func _sally(b: _Block, p: Vector2, row: Array, k: Dictionary) -> void:
	var walls := _walls_of(b.n)
	var along := Vector2.ZERO
	var best := 30.0
	for w: Dictionary in walls["walls"]:
		var pts: PackedVector2Array = w["pts"]
		for i in range(1, pts.size()):
			var c := Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])
			if c.distance_to(p) < best:
				best = c.distance_to(p)
				along = (pts[i] - pts[i - 1]).normalized()
	if along == Vector2.ZERO:
		along = _dir_of(row)
	if not b.clear(p, 2.0):
		b.skipped += 1
		return   # (a gate a road goes through: the wall's own gate over the road stands there)
	var y := b.ground(p)
	if is_nan(y):
		return
	var h := float(k.get("h", 8.0))
	var stone := str(k.get("stone", "grey"))
	b.put("sally_" + stone, Transform3D(Basis(Vector3.UP, _yaw(Vector2(along.y, -along.x))).scaled(Vector3(1, clampf(h / 8.0, 0.6, 1.6), 1)),
		b.local(p, y - 0.5)))


## A board with `name` on it, `ahead` m from `q` towards `face` (the road: in front of a statue's plinth), on the
## ground, facing that way; none where that would be on a road.
static func _name_board(b: _Block, q: Vector2, y: float, face: Vector2, name: String, ahead: float) -> void:
	var f := face if face != Vector2.ZERO else Vector2(0, 1)
	var at := q + f * ahead
	if ahead > 0.0:
		if not b.clear(at):
			return
		y = b.ground(at)
		if is_nan(y):
			return
	b.put("name_board", Transform3D(Basis(Vector3.UP, _yaw(f)), b.local(at, y)))
	_label(b, at, y, f, name, 1.55, 1.4)


## A name's label on a board at `q` (ground `y`), its face `face`, its middle `up` m up, `wide` m across at most.
static func _label(b: _Block, q: Vector2, y: float, face: Vector2, name: String, up: float, wide: float) -> void:
	if is_nan(y):
		return
	var f := face if face != Vector2.ZERO else Vector2(0, 1)
	var basis := Basis(Vector3.UP, _yaw(f))
	var text := name if name.length() <= 60 else name.left(57) + "..."
	var at := b.local(q, y) + basis * Vector3(0, up, 0.07)
	var xf := Transform3D(basis.scaled(Vector3.ONE * clampf(wide / 1.52, 0.4, 1.5)), at)
	b.labels.append([text, xf])


## Which way a thing at `p` faces: its mapped heading, else towards the road near it, else its own seeded way.
static func _facing(b: _Block, p: Vector2, row: Array) -> Vector2:
	if row[5] != null:
		return _dir_of(row)
	var r := b.to_road(p)
	if r != Vector2.ZERO:
		return r
	var a := _seeded(row, TAU)
	return Vector2(sin(a), cos(a))


# ---------------------------------------------------------------------------- the walls

## The walls of block `b`: their pieces, merlons, towers, gates and floodlights filed in it (each in the one block its
## middle is in, the same whichever block asks).
static func _walls_in(b: _Block) -> void:
	var walls := _walls_of(b.n)
	for wi in (walls["walls"] as Array).size():
		var w: Dictionary = walls["walls"][wi]
		if not (w["box"] as Rect2).grow(SIZE * 0.1).intersects(b.box):
			continue
		var plan := _plan_of(b.n, walls, wi)
		var k: Dictionary = w["kit"]
		var h: float = w["h"]
		var thick := float(k.get("thick", 2.4))
		var stone := str(k.get("stone", "grey"))
		var pts: Array = plan["samples"]
		for i: int in plan["pieces"]:
			var a: Vector2 = pts[i]
			var c: Vector2 = pts[i + 1]
			if not b.mine((a + c) * 0.5):
				continue
			var ya := b.ground(a)
			var yc := b.ground(c)
			if is_nan(ya) or is_nan(yc):
				continue
			var la := b.local(a, ya - 1.2)
			var lc := b.local(c, yc - 1.2)
			b.put("wall_" + stone, _slope(la, lc, thick, h + 1.2))
			b.put("merlons_" + stone, _slope(la + Vector3(0, h + 1.2, 0), lc + Vector3(0, h + 1.2, 0), thick, 1.0))
		for t: Dictionary in plan["towers"]:
			var p: Vector2 = t["p"]
			if not b.mine(p):
				continue
			var y := b.ground(p)
			if is_nan(y):
				continue
			var model := str(k.get("tower", "round"))
			var r := thick * 1.9
			b.put("tower_%s_%s" % [model, stone], Transform3D(Basis(Vector3.UP, _yaw(t["dir"])).scaled(Vector3(r, h + 4.0, r)),
				b.local(p, y - 1.2)))
		for g: Dictionary in plan["gates"]:
			_gate(b, g, h, thick, stone)
		if bool(k.get("floodlit", true)):
			for f: Dictionary in plan["floods"]:
				var p: Vector2 = f["p"]
				if not b.mine(p):
					continue
				var y := b.ground(p)
				if not is_nan(y):
					b.put("flood", Transform3D(Basis(Vector3.UP, _yaw(f["dir"])), b.local(p, y)))


## A gate where a road goes through a wall: a tower either side of the road, clear of it, and an arch between them
## whose underside clears the road by HEADROOM all the way across (left out where the land or the road can't tell).
static func _gate(b: _Block, g: Dictionary, h: float, thick: float, stone: String) -> void:
	var a: Vector2 = g["a"]
	var c: Vector2 = g["c"]
	if not b.mine((a + c) * 0.5):
		return
	var ya := b.ground(a)
	var yc := b.ground(c)
	if is_nan(ya) or is_nan(yc):
		return
	# The road's highest under the arch, from the road's own heights where the wall crosses it.
	var top := -INF
	for q: Vector2 in g["over"]:
		var on := b.n.locate(q.x, q.y, -1, true)
		if on.is_empty() or is_nan(float(on["y"])):
			continue
		top = maxf(top, float(on["y"]))
	if top == -INF:
		return
	var under := maxf(top + HEADROOM, maxf(ya, yc) + 2.0)
	var crown := maxf(under + 2.4, maxf(ya, yc) + h)
	var dir: Vector2 = (c - a).normalized()
	var tall := crown - minf(ya, yc) + 3.0
	for e: Array in [[a, ya], [c, yc]]:
		var p: Vector2 = e[0]
		var w := thick * 1.5
		b.put("gate_tower_" + stone, Transform3D(Basis(Vector3.UP, _yaw(dir)).scaled(Vector3(w, crown + 3.0 - float(e[1]) + 1.2, w)),
			b.local(p, float(e[1]) - 1.2)))
	b.put("arch_" + stone, _slope(b.local(a, under), b.local(c, under), thick * 1.2, crown - under))


## The walls of `net`'s region (its city_wall lines joined where the baker cut them), each with its kit, height and
## box: {"walls": [{pts, kit, h, box, closed}], "plans": {}}. Worked out once a region, under a lock.
static func _walls_of(net: RoadNet) -> Dictionary:
	var id := net.region.get_instance_id()
	_walls_lock.lock()
	var got = _walls.get(id)
	if got == null:
		if _walls.size() > 4:
			_walls.clear()
		got = {"walls": _join_walls(net.region), "plans": {}, "towers": _mapped_towers(net.region)}
		_walls[id] = got
	_walls_lock.unlock()
	return got


## The region's city wall lines joined end to end: [{pts, kit, h, box, closed}].
static func _join_walls(region: RealRegion) -> Array:
	var pieces: Array = []
	for row: Array in region.features.get("lines", []):
		if str(row[0]) == "city_wall" and (row[1] as PackedVector2Array).size() >= 2:
			pieces.append({"pts": (row[1] as PackedVector2Array).duplicate(), "h": row[2], "row": row})
	# A wall mapped as an outline (the old town it rings, or the wall's own footprint): its ring, less any side the baker
	# cut along a cell's edge (that's no wall), each run of it a line.
	for row: Array in region.features.get("areas", []):
		if str(row[0]) == "city_wall" and (row[1] as PackedVector2Array).size() >= 3:
			for run in _ring_runs(region, row[1]):
				pieces.append({"pts": run, "h": row[2], "row": row})
	var joined := true
	while joined:
		joined = false
		for i in pieces.size():
			for j in range(i + 1, pieces.size()):
				var a: PackedVector2Array = pieces[i]["pts"]
				var c: PackedVector2Array = pieces[j]["pts"]
				var got := _join2(a, c)
				if got.is_empty():
					continue
				pieces[i]["pts"] = got
				if pieces[i]["h"] == null:
					pieces[i]["h"] = pieces[j]["h"]
				pieces.remove_at(j)
				joined = true
				break
			if joined:
				break
	var out: Array = []
	for pc: Dictionary in pieces:
		var pts: PackedVector2Array = pc["pts"]
		var mid := pts[0]
		var kit_id := str(RegionKit.at_frame(region.frame_lat, region.frame_lon, mid.x, mid.y).get("region", ""))
		var k := SceneryStreamer.kit("city_wall", kit_id)
		var h := float(pc["h"]) if pc["h"] != null and float(pc["h"]) > 1.0 else float(k.get("h", 8.0))
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		out.append({"pts": pts, "kit": k, "h": clampf(h, 3.0, 25.0), "box": box.grow(20.0),
			"closed": pts[0].distance_to(pts[pts.size() - 1]) < JOIN})
	return out


## Ring `ring` (region frame) closed and split where a side runs along a cell's edge (both its ends on the same 0.25
## degree line): its runs, each 2 points or more.
static func _ring_runs(region: RealRegion, ring: PackedVector2Array) -> Array:
	var frame := Vector2(region.frame_lat, region.frame_lon)
	var on_edge := func(p: Vector2) -> Vector2:
		# (which cell edges, lat and lon, the point is on: NAN for none)
		var ll := RealRegion.from_frame(frame, p.x, p.y)
		var lat := ll.x * 4.0
		var lon := ll.y * 4.0
		return Vector2(roundf(lat) if absf(lat - roundf(lat)) < 1e-4 else NAN, roundf(lon) if absf(lon - roundf(lon)) < 1e-4 else NAN)
	var pts := ring.duplicate()
	pts.append(ring[0])
	var runs: Array = []
	var run := PackedVector2Array([pts[0]])
	var prev: Vector2 = on_edge.call(pts[0])
	for i in range(1, pts.size()):
		var e: Vector2 = on_edge.call(pts[i])
		if (not is_nan(e.x) and e.x == prev.x) or (not is_nan(e.y) and e.y == prev.y):
			if run.size() >= 2:
				runs.append(run)
			run = PackedVector2Array()
		run.append(pts[i])
		prev = e
	if run.size() >= 2:
		runs.append(run)
	return runs


## Lines `a` and `c` joined where an end of one meets an end of the other, or empty where none do.
static func _join2(a: PackedVector2Array, c: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if a[a.size() - 1].distance_to(c[0]) < JOIN:
		out = a.duplicate()
		out.append_array(c.slice(1))
	elif c[c.size() - 1].distance_to(a[0]) < JOIN:
		out = c.duplicate()
		out.append_array(a.slice(1))
	elif a[a.size() - 1].distance_to(c[c.size() - 1]) < JOIN:
		out = a.duplicate()
		var r := c.duplicate()
		r.reverse()
		out.append_array(r.slice(1))
	elif a[0].distance_to(c[0]) < JOIN:
		out = a.duplicate()
		out.reverse()
		out.append_array(c.slice(1))
	return out


## Where the map's own towers on walls stand (the skyline's defensive towers and watchtowers): [Vector2].
static func _mapped_towers(region: RealRegion) -> Array:
	var out: Array = []
	for row: Array in region.features.get("points", []):
		if str(row[0]) in ["defensive_tower", "watchtower"]:
			out.append(Vector2(float(row[1]), float(row[2])))
	for row: Array in region.features.get("areas", []):
		if str(row[0]) in ["defensive_tower", "watchtower"]:
			out.append(_centre(row[1]))
	return out


## Wall `wi`'s plan, worked out once (the same whichever block asks first): its samples every STEP, which of its
## pieces stand (both ends clear of every road), its gates (a short run over a road between clear ends), its towers
## (every kit "tower_every" m, not near a mapped one or a gate) and its floodlights (outside it).
static func _plan_of(net: RoadNet, walls: Dictionary, wi: int) -> Dictionary:
	_walls_lock.lock()
	var got = (walls["plans"] as Dictionary).get(wi)
	_walls_lock.unlock()
	if got != null:
		return got
	var w: Dictionary = walls["walls"][wi]
	var k: Dictionary = w["kit"]
	var thick := float(k.get("thick", 2.4))
	var pts: PackedVector2Array = w["pts"]
	var samples := _resample(pts, STEP)
	var clear := PackedByteArray()
	clear.resize(samples.size())
	for i in samples.size():
		clear[i] = 1 if clear_of_roads(net, samples[i], CLEAR + thick * 0.5) else 0
	var pieces := PackedInt32Array()
	for i in range(samples.size() - 1):
		if clear[i] == 1 and clear[i + 1] == 1:
			pieces.append(i)
	# Gates: a run over a road with a clear sample either side, no longer than GATE_MOST.
	var gates: Array = []
	var i := 0
	while i < samples.size():
		if clear[i] == 1:
			i += 1
			continue
		var j := i
		while j < samples.size() and clear[j] == 0:
			j += 1
		if i > 0 and j < samples.size() and (j - i + 1) * STEP <= GATE_MOST:
			var over: Array = []
			for q in range(i, j):
				over.append(samples[q])
			gates.append({"a": samples[i - 1], "c": samples[j], "over": over})
		i = j
	# Towers.
	var every := float(k.get("tower_every", 55.0))
	var towers: Array = []
	var outside := _outside_sign(pts) if w["closed"] else 1.0
	var floods: Array = []
	var s := 0.0
	var next_tower := every * 0.5
	var next_flood := FLOOD_EVERY * 0.5
	for q in range(samples.size() - 1):
		var a := samples[q]
		var c := samples[q + 1]
		var dir := (c - a).normalized()
		if s >= next_tower:
			next_tower = s + every
			if clear[q] == 1 and _far_from(a, walls["towers"], TOWER_NEAR) and _far_from_gates(a, gates, TOWER_NEAR * 0.6):
				towers.append({"p": a, "dir": dir})
		if s >= next_flood:
			next_flood = s + FLOOD_EVERY
			var out := Vector2(-dir.y, dir.x) * outside
			var fp := a + out * (thick * 0.5 + 3.0)
			if clear[q] == 1 and clear_of_roads(net, fp, CLEAR):
				floods.append({"p": fp, "dir": -out})
		s += a.distance_to(c)
	got = {"samples": samples, "pieces": pieces, "gates": gates, "towers": towers, "floods": floods}
	_walls_lock.lock()
	walls["plans"][wi] = got
	_walls_lock.unlock()
	return got


## Points along `pts` every `step` m from its first (and its last).
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var c := pts[i]
		var l := a.distance_to(c)
		var t := step - carry
		while t <= l:
			out.append(a.lerp(c, t / l))
			t += step
		carry = l - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.5:
		out.append(pts[pts.size() - 1])
	return out


## Which side of a closed ring its outside is, as a sign on the left normal (-dir.y, dir.x).
static func _outside_sign(pts: PackedVector2Array) -> float:
	# (x east, z south: a ring whose signed area is positive runs clockwise on the map, its outside on the left)
	return 1.0 if _signed_area(pts) > 0.0 else -1.0


static func _far_from(p: Vector2, list: Array, d: float) -> bool:
	for q: Vector2 in list:
		if q.distance_to(p) < d:
			return false
	return true


static func _far_from_gates(p: Vector2, gates: Array, d: float) -> bool:
	for g: Dictionary in gates:
		if (g["a"] as Vector2).distance_to(p) < d or (g["c"] as Vector2).distance_to(p) < d:
			return false
	return true


# ---------------------------------------------------------------------------- small helpers

## A unit piece (its middle at the bottom, x across, y up, z along) from `a` to `c` (block frame, its bottom's
## middle), `w` across, `h` up, its sides kept upright (a sheared box, so pieces down a hill meet end to end).
static func _slope(a: Vector3, c: Vector3, w: float, h: float) -> Transform3D:
	var d := Vector2(c.x - a.x, c.z - a.z)
	var f := d.normalized() if d.length() > 1e-4 else Vector2(0, 1)
	return Transform3D(Basis(Vector3(f.y, 0.0, -f.x) * w, Vector3.UP * h, c - a), (a + c) * 0.5)


## A kit's model without its script ("history:monument" -> "monument"), "" for another script's.
static func _model_of(k: Dictionary) -> String:
	var m := str(k.get("model", ""))
	return m.get_slice(":", 1) if m.begins_with("history:") else ""


## A yaw (about +y) that turns local +z to `dir` (region x, z).
static func _yaw(dir: Vector2) -> float:
	return atan2(dir.x, dir.y) if dir.length_squared() > 1e-8 else 0.0


## A row's mapped heading as a direction on the ground (x east, z south), +z where it has none.
static func _dir_of(row: Array) -> Vector2:
	if row[5] == null:
		return Vector2(0, 1)
	var a := deg_to_rad(float(row[5]))
	return Vector2(sin(a), -cos(a))


## A number in [0, top) from the row's id (or where it is): the same on every machine.
static func _seeded(row: Array, top: float) -> float:
	var seed_of := str(row[7]) if row.size() > 7 and row[7] != null else "%.1f,%.1f" % [float(row[1]), float(row[2])]
	return float(seed_of.hash() & 0xffff) / 65536.0 * top


static func _centre(ring: PackedVector2Array) -> Vector2:
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


# ---------------------------------------------------------------------------- the models

## The mesh of `model` (built once). Models with a stone after them ("wall_sand") are built in that stone.
static func mesh(model: String) -> Mesh:
	_meshes_lock.lock()
	var got = _meshes.get(model)
	_meshes_lock.unlock()
	if got != null:
		return got
	var b := _Build.new()
	var stone: Color = STONES.get(model.get_slice("_", model.get_slice_count("_") - 1), STONES["grey"])
	var base := model
	if STONES.has(model.get_slice("_", model.get_slice_count("_") - 1)):
		base = model.left(model.rfind("_"))
	match base:
		"wall": _wall(b, stone)
		"merlons": _merlons(b, stone)
		"tower_round": _tower(b, stone, true)
		"tower_square": _tower(b, stone, false)
		"gate_tower": _gate_tower(b, stone)
		"arch": _arch(b, stone)
		"sally": _sally_gate(b, stone)
		"flood": _flood(b)
		"stones": _stone_circle(b)
		"standing_stone": _standing_stone(b, Vector3.ZERO, 0.0, 1.0)
		"obelisk": _obelisk(b)
		"cross": _cross(b)
		"statue": _statue(b)
		"sculpture": _sculpture(b)
		"heritage": _heritage(b)
		"name_board": _board(b, 1.6, 0.9, 1.1, BROWN)
		"board": _board(b, 1.2, 0.9, 0.8, Color(0.16, 0.24, 0.2))
		"panorama": _panorama(b)
		"bench": _bench(b)
		"pull_in": _pull_in(b)
		"fountain": _fountain(b)
		"milestone": _milestone(b)
		_: b.box(Vector3(0, 1.0, 0), Vector3(0.3, 2.0, 0.3), Basis(), Color(1, 0, 1))
	var m := b.commit(material())
	_meshes_lock.lock()
	_meshes[model] = m
	_meshes_lock.unlock()
	return m


## Builds a mesh of boxes and lathes, vertex coloured, its flags in UV2 (FLOOD, STEADY).
class _Build:
	var st := SurfaceTool.new()
	var any := false
	var glow := 0.0   # (the floodlight a face takes at night, while set)

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var nrm := (b - a).cross(c - a).normalized()
		for p in [a, b, c]:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			# (a floodlit face is lit most at its foot)
			st.set_uv2(Vector2(History.FLOOD, glow * clampf(1.0 - p.y * 0.35, 0.35, 1.0)) if glow > 0.0 else Vector2.ZERO)
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

	## A lamp at `at`, `size` across, that the shader turns to the camera and lights at night.
	func lamp(at: Vector3, size: float, col: Color) -> void:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			st.set_normal(Vector3.UP)
			st.set_color(col)
			st.set_uv(corner)
			st.set_uv2(Vector2(History.STEADY, size))
			st.add_vertex(at)
		any = true

	func commit(mat: Material) -> Mesh:
		var m := st.commit() if any else ArrayMesh.new()
		if m.get_surface_count() > 0:
			m.surface_set_material(0, mat)
		return m


## A stretch of wall: a unit piece (1 across, 1 up, 1 along, its bottom's middle at the origin), floodlit, a little
## battered at its foot.
static func _wall(b: _Build, stone: Color) -> void:
	b.glow = 1.0
	b.box(Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 1.0), Basis(), stone)
	b.box(Vector3(0, 0.08, 0), Vector3(1.12, 0.16, 1.0), Basis(), stone.darkened(0.06))
	b.glow = 0.0


## The merlons along a stretch of wall's outer edge and the walk's low inner parapet (1 m up, the piece's length
## along).
static func _merlons(b: _Build, stone: Color) -> void:
	b.glow = 0.7
	for z: float in [-0.25, 0.25]:
		b.box(Vector3(0.38, 0.45, z), Vector3(0.24, 0.9, 0.3), Basis(), stone.darkened(0.03))
	b.box(Vector3(-0.42, 0.25, 0), Vector3(0.16, 0.5, 1.0), Basis(), stone.darkened(0.05))
	b.glow = 0.0


## A tower on the wall (unit: 1 m radius, 1 up): round or square, its battlements a little proud.
static func _tower(b: _Build, stone: Color, round: bool) -> void:
	b.glow = 1.0
	if round:
		b.lathe(Vector3.ZERO, [[0.0, 1.06], [0.15, 1.0], [0.92, 1.0], [0.92, 1.08], [1.0, 1.08]], 14, stone)
		for i in 8:
			var a := TAU * i / 8.0
			b.box(Vector3(cos(a) * 1.0, 1.04, sin(a) * 1.0), Vector3(0.28, 0.08, 0.28), Basis(Vector3.UP, -a), stone.darkened(0.04))
	else:
		b.box(Vector3(0, 0.46, 0), Vector3(2.0, 0.92, 2.0), Basis(), stone)
		b.box(Vector3(0, 0.96, 0), Vector3(2.12, 0.08, 2.12), Basis(), stone.darkened(0.04))
		for sx: float in [-0.8, 0.0, 0.8]:
			for sz: float in [-1.0, 1.0]:
				b.box(Vector3(sx, 1.04, sz), Vector3(0.3, 0.08, 0.14), Basis(), stone.darkened(0.04))
				b.box(Vector3(sz, 1.04, sx), Vector3(0.14, 0.08, 0.3), Basis(), stone.darkened(0.04))
	b.glow = 0.0
	# (a slit window up the outside)
	b.box(Vector3(0, 0.55, 1.03 if round else 1.01), Vector3(0.12, 0.12, 0.04), Basis(), Color(0.05, 0.05, 0.06))


## A gate's tower (unit: 1 m square, 1 up), square, its top battlemented.
static func _gate_tower(b: _Build, stone: Color) -> void:
	b.glow = 1.0
	b.box(Vector3(0, 0.47, 0), Vector3(1.0, 0.94, 1.0), Basis(), stone)
	b.glow = 0.4
	for c in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
		b.box(Vector3(c.x, 0.97, c.y), Vector3(0.2, 0.06, 0.2), Basis(), stone.darkened(0.04))
	b.glow = 0.0


## A gate's arch over the road: a unit piece (1 across, 1 up, 1 along) whose underside curves up from its ends (at
## its bottom, y 0) to a third of its height in the middle, so all of it is at or above its bottom: the headroom.
static func _arch(b: _Build, stone: Color) -> void:
	b.glow = 0.8
	var n := 8
	for i in n:
		var z0 := -0.5 + float(i) / n
		var z1 := -0.5 + float(i + 1) / n
		var y0 := 0.33 * sin(PI * (z0 + 0.5))
		var y1 := 0.33 * sin(PI * (z1 + 0.5))
		for x: float in [-0.5, 0.5]:
			b.quad(Vector3(x, y0, z0), Vector3(x, 1.0, z0), Vector3(x, 1.0, z1), Vector3(x, y1, z1), stone)
		b.quad(Vector3(-0.5, y0, z0), Vector3(-0.5, y1, z1), Vector3(0.5, y1, z1), Vector3(0.5, y0, z0), stone.darkened(0.25))
	b.box(Vector3(0, 1.0, 0), Vector3(1.04, 0.04, 1.0), Basis(), stone.darkened(0.04))
	for z: float in [-0.35, -0.12, 0.12, 0.35]:
		b.box(Vector3(0.45, 1.08, z), Vector3(0.12, 0.12, 0.1), Basis(), stone.darkened(0.04))
		b.box(Vector3(-0.45, 1.08, z), Vector3(0.12, 0.12, 0.1), Basis(), stone.darkened(0.04))
	b.glow = 0.0


## A sally port or a postern: a small arched doorway framed in dressed stone across a wall (8 m high, its door both
## sides).
static func _sally_gate(b: _Build, stone: Color) -> void:
	var dressed := stone.lightened(0.12)
	for x: float in [-1.4, 1.4]:
		b.box(Vector3(x, 1.8, 0), Vector3(0.6, 3.6, 2.8), Basis(), dressed)
	b.box(Vector3(0, 3.9, 0), Vector3(3.4, 0.6, 2.8), Basis(), dressed)
	for z: float in [-1.42, 1.42]:
		b.box(Vector3(0, 1.6, z), Vector3(2.2, 3.2, 0.04), Basis(), Color(0.12, 0.1, 0.09))


## A floodlight at a wall's foot: a low black box, its lamp aimed at the wall (+z), lit at night.
static func _flood(b: _Build) -> void:
	b.box(Vector3(0, 0.2, 0), Vector3(0.5, 0.4, 0.35), Basis(), Color(0.12, 0.12, 0.13))
	b.lamp(Vector3(0, 0.32, 0.2), 0.22, LAMP)


## A stone circle: a ring of standing stones, about 10 m across, a few fallen.
static func _stone_circle(b: _Build) -> void:
	var n := 11
	for i in n:
		var a := TAU * i / n + 0.13 * sin(i * 3.1)
		var tall := 1.2 + 0.9 * absf(sin(i * 2.3))
		_standing_stone(b, Vector3(cos(a) * 5.0, 0, sin(a) * 5.0), -a + 0.3 * cos(i * 1.7), tall)


## A standing stone at `at`, turned `yaw`, `tall` m high: a weathered slab leaning a touch.
static func _standing_stone(b: _Build, at: Vector3, yaw: float, tall: float) -> void:
	var col := Color(0.5, 0.49, 0.45).lerp(Color(0.42, 0.44, 0.36), absf(sin(at.x + at.z)))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.06)
	b.box(at + Vector3(0, tall * 0.5 - 0.3, 0), Vector3(0.9, tall + 0.6, 0.45), basis, col)
	b.box(at + basis * Vector3(0.05, tall + 0.05, 0), Vector3(0.7, 0.2, 0.38), basis, col.darkened(0.06))


## An obelisk on its stepped plinth.
static func _obelisk(b: _Build) -> void:
	var stone := Color(0.72, 0.7, 0.64)
	b.box(Vector3(0, 0.2, 0), Vector3(3.0, 0.4, 3.0), Basis(), stone.darkened(0.1))
	b.box(Vector3(0, 0.7, 0), Vector3(2.0, 0.6, 2.0), Basis(), stone.darkened(0.05))
	b.lathe(Vector3(0, 1.0, 0), [[0.0, 0.85], [7.5, 0.55], [8.2, 0.0]], 4, stone)


## A memorial cross on its steps (a war memorial, a calvary).
static func _cross(b: _Build) -> void:
	var stone := Color(0.74, 0.72, 0.66)
	for i in 3:
		b.box(Vector3(0, 0.15 + i * 0.3, 0), Vector3(3.0 - i * 0.8, 0.3, 3.0 - i * 0.8), Basis(), stone.darkened(0.08 - i * 0.02))
	b.box(Vector3(0, 1.4, 0), Vector3(0.8, 1.0, 0.8), Basis(), stone)
	b.box(Vector3(0, 3.6, 0), Vector3(0.36, 3.6, 0.36), Basis(), stone)
	b.box(Vector3(0, 4.4, 0), Vector3(1.6, 0.34, 0.34), Basis(), stone)


## A statue on a plinth: a figure in bronze gone green.
static func _statue(b: _Build) -> void:
	var stone := Color(0.7, 0.68, 0.62)
	var bronze := Color(0.24, 0.38, 0.32)
	b.box(Vector3(0, 0.15, 0), Vector3(2.4, 0.3, 2.4), Basis(), stone.darkened(0.1))
	b.box(Vector3(0, 1.3, 0), Vector3(1.5, 2.0, 1.5), Basis(), stone)
	b.box(Vector3(0, 2.4, 0), Vector3(1.7, 0.2, 1.7), Basis(), stone.darkened(0.05))
	b.lathe(Vector3(0, 2.5, 0), [[0.0, 0.32], [0.9, 0.24], [1.6, 0.3], [1.9, 0.18]], 8, bronze)
	b.lathe(Vector3(0, 4.4, 0), [[0.0, 0.1], [0.12, 0.17], [0.34, 0.15], [0.44, 0.0]], 8, bronze)
	b.box(Vector3(0.38, 3.8, 0.05), Vector3(0.14, 0.7, 0.14), Basis(Vector3.BACK, -0.4), bronze)


## A piece of art: a twisted column of shapes on a low base.
static func _sculpture(b: _Build) -> void:
	var metal := Color(0.62, 0.6, 0.56)
	b.box(Vector3(0, 0.15, 0), Vector3(1.8, 0.3, 1.8), Basis(), Color(0.5, 0.49, 0.46))
	for i in 5:
		b.box(Vector3(0, 0.6 + i * 0.6, 0), Vector3(0.9 - i * 0.1, 0.5, 0.4), Basis(Vector3.UP, i * 0.5), metal.darkened(i * 0.04))
	b.lathe(Vector3(0, 3.4, 0), [[0.0, 0.0], [0.3, 0.45], [0.6, 0.0]], 8, Color(0.75, 0.42, 0.2))


## A brown heritage board on two posts: the name of a place worth stopping for.
static func _heritage(b: _Build) -> void:
	_board(b, 1.6, 0.9, 1.5, BROWN)


## A board `w` wide, `h` tall, its bottom `up` m up two posts, coloured `col` (its face to +z).
static func _board(b: _Build, w: float, h: float, up: float, col: Color) -> void:
	for x: float in [-w * 0.4, w * 0.4]:
		b.box(Vector3(x, (up + h) * 0.5, -0.05), Vector3(0.08, up + h, 0.08), Basis(), WOOD)
	b.box(Vector3(0, up + h * 0.5, 0), Vector3(w, h, 0.06), Basis(), col)
	b.box(Vector3(0, up + h + 0.04, 0), Vector3(w + 0.1, 0.08, 0.12), Basis(), WOOD)


## A panorama board: a slanting table on a post, its face up and out (+z), drawn with the view's skyline.
static func _panorama(b: _Build) -> void:
	b.box(Vector3(0, 0.5, 0), Vector3(0.14, 1.0, 0.14), Basis(), STEEL)
	var tilt := Basis(Vector3.RIGHT, -0.7)
	b.box(Vector3(0, 1.08, 0.05), Vector3(1.4, 0.04, 0.7), tilt, Color(0.16, 0.24, 0.3))
	b.box(Vector3(0, 1.1, 0.05), Vector3(1.2, 0.02, 0.5), tilt, Color(0.82, 0.84, 0.78))
	b.box(Vector3(0, 1.12, 0.05), Vector3(1.1, 0.01, 0.08), tilt * Basis(Vector3.UP, 0.0), Color(0.3, 0.42, 0.3))


## A bench, its seat to +z.
static func _bench(b: _Build) -> void:
	for x: float in [-0.7, 0.7]:
		b.box(Vector3(x, 0.22, 0), Vector3(0.08, 0.44, 0.45), Basis(), STEEL)
	b.box(Vector3(0, 0.46, 0), Vector3(1.7, 0.06, 0.45), Basis(), WOOD)
	b.box(Vector3(0, 0.75, -0.22), Vector3(1.7, 0.3, 0.05), Basis(), WOOD)


## A gravelled pull-in: a flat patch 8 m along and 4 m deep (+z away from the road), a low kerb of stones at its back.
static func _pull_in(b: _Build) -> void:
	b.box(Vector3(0, 0.0, 1.0), Vector3(8.0, 0.24, 4.0), Basis(), Color(0.56, 0.53, 0.47))
	for x in range(-3, 4):
		b.box(Vector3(x * 1.2, 0.2, 3.1), Vector3(0.6, 0.35, 0.4), Basis(Vector3.UP, x * 0.7), Color(0.5, 0.48, 0.44))


## A fountain: an eight-sided basin with water in it and a column spouting in the middle (2.5 m across: scaled to a
## mapped basin's size).
static func _fountain(b: _Build) -> void:
	var stone := Color(0.74, 0.7, 0.62)
	b.lathe(Vector3.ZERO, [[0.0, 2.5], [0.6, 2.5], [0.6, 2.2], [0.1, 2.2]], 8, stone, false)
	b.lathe(Vector3.ZERO, [[0.5, 2.25], [0.5, 0.0]], 8, Color(0.22, 0.36, 0.42), false)
	b.lathe(Vector3.ZERO, [[0.0, 0.35], [1.4, 0.25], [1.5, 0.8], [1.7, 0.8], [1.7, 0.2], [2.4, 0.08]], 8, stone)
	b.lathe(Vector3(0, 2.4, 0), [[0.0, 0.06], [0.5, 0.25], [0.9, 0.0]], 6, Color(0.7, 0.82, 0.88))


## A milestone: a small white-painted stone with a rounded top and black lettering band.
static func _milestone(b: _Build) -> void:
	b.box(Vector3(0, 0.3, 0), Vector3(0.45, 0.6, 0.25), Basis(), Color(0.9, 0.89, 0.85))
	b.lathe(Vector3(0, 0.6, 0), [[0.0, 0.22], [0.12, 0.18], [0.2, 0.0]], 8, Color(0.9, 0.89, 0.85))
	b.box(Vector3(0, 0.42, 0.13), Vector3(0.36, 0.12, 0.01), Basis(), Color(0.1, 0.1, 0.1))


# ---------------------------------------------------------------------------- the shader

static func material() -> ShaderMaterial:
	if _material == null:
		var s := Shader.new()
		s.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = s
	return _material


## Moves the night on (the walls' floodlights and the lamps): once a frame, by whichever block's ticker gets there first.
static func tick() -> void:
	var f := Engine.get_process_frames()
	if f == _ticked:
		return
	_ticked = f
	material().set_shader_parameter("night", Daylight.current.lamps if Daylight.current != null else 0.0)


const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float night = 0.0;   // 0 by day .. 1 with the lamps on (Daylight.lamps)
varying float glow;
varying float flood;

void vertex() {
	glow = 0.0;
	flood = 0.0;
	float flag = UV2.x;
	if (flag > 2.5 && flag < 3.5) {
		// A lamp: a square to the camera, kept a few pixels across however far, lit only at night.
		vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float size = max(UV2.y, -c.z * 0.003) * step(0.01, night);
		c.xy += UV * size;
		POSITION = PROJECTION_MATRIX * c;
		glow = night;
	} else {
		POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
		if (flag > 4.5) {
			flood = UV2.y * night;
		}
	}
}

void fragment() {
	if (glow > 0.0) {
		ALBEDO = vec3(0.0);
		EMISSION = COLOR.rgb * 8.0 * glow;
	} else {
		ALBEDO = COLOR.rgb;
		// A floodlit face: warm light washing up it from below.
		EMISSION = COLOR.rgb * vec3(1.0, 0.82, 0.58) * flood * 0.9;
	}
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
"""
