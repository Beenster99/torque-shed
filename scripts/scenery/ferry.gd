class_name FerryScenery
extends RefCounted
## Ferries (Ride Anywhere v2, phase D round 3, D7: interfaces/scenery.md): the boats that sail the map's ferry routes,
## and at each terminal the ramp (a linkspan) where the road meets the water and the ticket office. The routes and
## which roads they join are FerryLinks'; the crew's own crossing is FerryCrossing's, on a boat made here (boat_mesh).
##
## Three sizes of boat, by the route (FerryLinks.size_of): a chain ferry (a floating bridge, ramps at both ends, its
## wheelhouse to one side) on the short ones, a roll-on roll-off car ferry (an open car deck, the bridge over the bow)
## on most, and a big car ferry (decks of cabins, two funnels, an open vehicle deck aft) on the long ones. Their
## colours are their region's (the kit library's ferry rows), with a default for anywhere a region has none.
##
## Every boat sails its route from the start, back and forth on a timetable from the route alone (its length and its
## id) and the crew's clock (Daylight's hours, the host's on a co-op ride), so every machine sees the same boat in the
## same place without a word between them. A block draws the boats whose middles are in it (dress); at dusk their
## windows and mast lights come on. A route the crew is crossing on is left to their own boat (crew_ids).
##
## Simon's first rule, as here: nothing has collision, nothing stands on a road (a ticket office is stood off it, by
## SceneryStreamer.stand), and a ramp starts where the road already ends at the water and goes out over it.

const Clock := preload("res://scripts/scenery/rail_train.gd")

## Part of what a block lays out: bump it with the look (SceneryStreamer folds the scripts' versions into its own).
const VERSION := 1
## How fast the scenery's boats sail (m/s) and how long each waits at either end (s).
const SPEED := 9.0
const DWELL := 90.0
## Each size's boat: its length, beam, deck height above the water (m) and where on its deck bikes stand (z from the
## middle, bow at -z, and how wide).
const BOATS := {
	"chain": {"len": 36.0, "beam": 14.0, "deck": 0.9, "slots": Vector3(-12.0, 12.0, 9.0)},
	"roro": {"len": 58.0, "beam": 15.0, "deck": 1.6, "slots": Vector3(-14.0, 24.0, 10.0)},
	"ship": {"len": 130.0, "beam": 24.0, "deck": 7.0, "slots": Vector3(24.0, 58.0, 16.0)},
}
## The linkspan's size (m) and how far it drops to the water over its length.
const RAMP_LEN := 14.0
const RAMP_W := 8.0
## How far out from the road's end (m) a boat lies, at least and at most: where the route itself sets out from (the
## slipway's end), as near as that allows.
const BERTH_LEAST := 10.0
const BERTH_MOST := 60.0
## How steeply a ramp may climb or fall to a boat's deck (rise over run).
const RAMP_STEEP := 0.25
## A route's water is the sea unless both its ends are higher than this (m): then it's a lake, just under its banks.
const LAKE_FROM := 15.0
## Bikes on a deck stand this far apart (m) across and along it.
const SLOT_X := 3.2
const SLOT_Z := 3.6

## The routes the crew is crossing on just now (FerryCrossing): {route id: true}; the scenery leaves them be.
static var crew_ids := {}
static var _meshes := {}
static var _lock := Mutex.new()
static var _lamp_mat: StandardMaterial3D


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of this script's rows ({"points": [[row, kit], ...], "lines": ...}, docs/scenery.md): the
## ticket offices at the terminals, a ramp at each end of a link in the block, and for dress the routes passing it.
static func lay_out(n: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var out := {"items": {}, "moved": 0, "skipped": 0}
	var corner := Vector2(key) * RoadBlock.SIZE
	var o := Vector3(corner.x, 0.0, corner.y)
	var memo := {}
	var lamps := false
	for got: Array in rows.get("points", []):
		var row: Array = got[0]
		var kit: Dictionary = got[1]
		var p := Vector2(float(row[1]), float(row[2]))
		var at := SceneryStreamer.stand(n, p, memo)
		if is_nan(at.x):
			out["skipped"] += 1
			continue
		if not is_equal_approx(at.x, p.x) or not is_equal_approx(at.z, p.y):
			out["moved"] += 1
		var turn := deg_to_rad(float(row[5])) if row[5] != null else float(absi(str(row[7]).hash()) % 360) * PI / 180.0
		_add(out, "hut_" + str(kit.get("hut", "#d8d2c4")).trim_prefix("#"), Transform3D(Basis(Vector3.UP, -turn), at - o))
		lamps = true
	var links := FerryLinks.of(n.region)
	for i in links.links.size():
		var l: Dictionary = links.links[i]
		for end: int in [int(l["a"]), int(l["b"])]:
			var at := n.region.node_pos[end]
			if not SceneryStreamer.in_block(key, at):
				continue
			var line := links.line_from(i, end)
			var out_dir := _out_of(line)
			var on := n.locate(at.x, at.y)
			var y := float(on["y"]) if not on.is_empty() and bool(on.get("on_road", false)) else float(n.height.call(at.x, at.y))
			if is_nan(y):
				out["skipped"] += 1
				continue
			# (the ramp's foot is the road's end: it runs on out to where the boat lies, down to its deck)
			var h := atan2(out_dir.x, -out_dir.y)
			var rb := ramp_basis(h, berth(line), y - water_of(n, line) - float(BOATS[str(l["size"])]["deck"]))
			var foot := Vector3(at.x, y + 0.02, at.y) - o
			_add(out, "ramp", Transform3D(rb, foot))
			_add(out, "gantry", Transform3D(Basis(Vector3.UP, -h), foot + rb * Vector3(0, 0, -RAMP_LEN + 0.6)))
	var boats: Array = []
	var box := Rect2(corner, Vector2.ONE * RoadBlock.SIZE).grow(BOATS["ship"]["len"])
	for route: Dictionary in links.routes:
		var pts: PackedVector2Array = route["pts"]
		if not _touches(pts, box):
			continue
		var m := FerryLinks._length(pts)
		if m < FerryLinks.SHORTEST:
			continue
		var region_id := str(RegionKit.at_frame(n.region.frame_lat, n.region.frame_lon, pts[0].x, pts[0].y).get("region", ""))
		boats.append({"pts": pts, "m": m, "id": str(route["id"]), "size": FerryLinks.size_of(str(route["name"]), m),
			"kit": SceneryStreamer.kit("ferry", region_id), "water": water_of(n, pts)})
	if not boats.is_empty() or lamps:
		out["dress"] = {"corner": corner, "boats": boats, "lamps": lamps}
	return out


static func _add(out: Dictionary, model: String, xf: Transform3D) -> void:
	if not (out["items"] as Dictionary).has(model):
		out["items"][model] = []
	(out["items"][model] as Array).append(xf)


## The way out over the water from the start of a link's line (the junction, then the route): the direction to the
## first point a few metres out.
static func _out_of(line: PackedVector2Array) -> Vector2:
	for k in range(1, line.size()):
		var d := line[k] - line[0]
		if d.length() > 6.0:
			return d.normalized()
	return Vector2(0, -1)


static func _touches(pts: PackedVector2Array, box: Rect2) -> bool:
	for k in range(1, pts.size()):
		var seg := Rect2(pts[k - 1], Vector2.ZERO).expand(pts[k])
		if seg.intersects(box, true):
			return true
	return pts.size() == 1 and box.has_point(pts[0])


## The water a route's boats float on (m, region frame): the sea's level, or a lake's just under its lower end.
static func water_of(n: RoadNet, pts: PackedVector2Array) -> float:
	var a := float(n.height.call(pts[0].x, pts[0].y))
	var b := float(n.height.call(pts[pts.size() - 1].x, pts[pts.size() - 1].y))
	if is_nan(a) or is_nan(b) or minf(a, b) < LAKE_FROM:
		return 0.0
	return minf(a, b) - 1.5


# ---------------------------------------------------------------------------- where the boats are

## Where along a route `m` metres long a boat on it is at time `t` (s on the crew's clock; `day` the day's length, 0
## for none) with timetable offset `offset`: Vector2(metres along, +1 sailing away from the route's start or -1 back).
static func boat_on(m: float, t: float, offset: float, day := 0.0) -> Vector2:
	var leg := Clock.trip(m, SPEED, 0.0).x
	var period := 2.0 * (leg + DWELL)
	if day > 0.0:
		period = day / maxf(1.0, roundf(day / period))   # (a whole number of trips a day: midnight moves no boat)
	var scale := period / (2.0 * (leg + DWELL))
	var u := fposmod(t + offset, period) / scale
	if u < DWELL:
		return Vector2(0.0, 1.0)
	u -= DWELL
	if u < leg:
		return Vector2(Clock.trip(m, SPEED, u).y, 1.0)
	u -= leg
	if u < DWELL:
		return Vector2(m, -1.0)
	u -= DWELL
	return Vector2(m - Clock.trip(m, SPEED, u).y, -1.0)


## A route's timetable offset (s): from its id, the same everywhere.
static func offset_of(id: String) -> float:
	return float(absi(id.hash()) % 86400)


## The point `s` m along `pts` and the heading there (radians clockwise from north, along the line): Vector3(x, z, heading).
static func along(pts: PackedVector2Array, s: float) -> Vector3:
	var left := maxf(s, 0.0)
	for k in range(1, pts.size()):
		var d := pts[k].distance_to(pts[k - 1])
		if d >= left and d > 0.0:
			var p := pts[k - 1].lerp(pts[k], left / d)
			var dir := pts[k] - pts[k - 1]
			return Vector3(p.x, p.y, atan2(dir.x, -dir.y))
		left -= d
	var n := pts.size()
	var last := pts[n - 1] - pts[maxi(n - 2, 0)]
	return Vector3(pts[n - 1].x, pts[n - 1].y, atan2(last.x, -last.y))


## Where bike `slot` stands on a `size` boat's deck, in the boat's frame (bow at -z).
static func slot_at(size: String, slot: int) -> Vector3:
	var b: Dictionary = BOATS.get(size, BOATS["roro"])
	var s: Vector3 = b["slots"]
	var across := maxi(1, int(s.z / SLOT_X))
	var row := slot / across
	var col := slot % across
	var x := (col - (across - 1) * 0.5) * SLOT_X
	var z := s.y - 3.0 - row * SLOT_Z
	return Vector3(x, float(b["deck"]), maxf(z, s.x))


# ---------------------------------------------------------------------------- dress: the boats sailing

## The boats passing a block (lay_out's dress), and the offices' lamps at dusk.
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary:
		return
	var life := Boats.new()
	life.name = "FerryBoats"
	life.corner = data.get("corner", Vector2.ZERO)
	life.routes = data.get("boats", [])
	node.add_child(life)


class Boats:
	extends Node3D
	var corner := Vector2.ZERO
	var routes: Array = []
	var _shown: Array = []   # a MeshInstance3D a route, made the first time its boat is in the block

	func _process(_delta: float) -> void:
		var lamps: float = Daylight.current.lamps if Daylight.current != null else 0.0
		var mat := FerryScenery.lamp_material()
		var glow := lerpf(0.05, 4.0, lamps)
		if not is_equal_approx(mat.emission_energy_multiplier, glow):
			mat.emission_energy_multiplier = glow
		if routes.is_empty():
			return
		if _shown.size() != routes.size():
			_shown.resize(routes.size())
		var clock := FerryScenery.Clock.clock()
		var box := Rect2(corner, Vector2.ONE * RoadBlock.SIZE)
		for i in routes.size():
			var r: Dictionary = routes[i]
			var at := FerryScenery.boat_on(float(r["m"]), clock.x, FerryScenery.offset_of(str(r["id"])), clock.y)
			var half := float(FerryScenery.BOATS[str(r["size"])]["len"]) * 0.5 + 2.0   # (its stern by the route's end)
			var p := FerryScenery.along(r["pts"], FerryScenery.sailed(float(r["m"]), at.x, half, half))
			var here := box.has_point(Vector2(p.x, p.y)) and not FerryScenery.crew_ids.has(str(r["id"]))
			var mi: MeshInstance3D = _shown[i]
			if not here:
				if mi != null:
					mi.visible = false
				continue
			if mi == null:
				mi = MeshInstance3D.new()
				mi.mesh = FerryScenery.boat_mesh(str(r["size"]), r["kit"])
				add_child(mi)
				_shown[i] = mi
			var h := p.z if at.y > 0.0 else p.z + PI
			mi.visible = true
			mi.position = Vector3(p.x - corner.x, float(r["water"]), p.y - corner.y)
			mi.basis = Basis(Vector3.UP, -h)


# ---------------------------------------------------------------------------- the models

## The model of `model`: "ramp" (a terminal's linkspan), "gantry" (over its outer end) or "hut_RRGGBB" (its ticket
## office, that colour).
static func mesh(model: String) -> Mesh:
	_lock.lock()
	var have: Mesh = _meshes.get(model)
	_lock.unlock()
	if have != null:
		return have
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	if model == "ramp":
		_ramp(st, lit)
	elif model == "gantry":
		_gantry(st, lit)
	else:
		_hut(st, lit, Color.html("#" + model.trim_prefix("hut_")) if Color.html_is_valid(model.trim_prefix("hut_")) else Color(0.85, 0.82, 0.76))
	var out := _finish(st, lit)
	_lock.lock()
	_meshes[model] = out
	_lock.unlock()
	return out


## A `size` boat ("chain", "roro" or "ship") in kit `kit`'s colours (hull, upper, funnel, stripe, deck), its
## waterline at y 0, its bow at -z. Made once a look, shared.
static func boat_mesh(size: String, kit: Dictionary) -> Mesh:
	var key := "%s|%s|%s|%s|%s|%s" % [size, kit.get("hull", ""), kit.get("upper", ""), kit.get("funnel", ""),
		kit.get("stripe", ""), kit.get("deck", "")]
	_lock.lock()
	var have: Mesh = _meshes.get(key)
	_lock.unlock()
	if have != null:
		return have
	var hull := _col(kit, "hull", Color(0.12, 0.13, 0.16))
	var upper := _col(kit, "upper", Color(0.93, 0.93, 0.9))
	var funnel := _col(kit, "funnel", Color(0.85, 0.3, 0.12))
	var stripe := _col(kit, "stripe", Color(0.15, 0.3, 0.6))
	var deck := _col(kit, "deck", Color(0.33, 0.35, 0.33))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b: Dictionary = BOATS.get(size, BOATS["roro"])
	var L := float(b["len"])
	var B := float(b["beam"])
	var D := float(b["deck"])
	match size:
		"chain":
			_box(st, Vector3(0, (D - 1.1) * 0.5, 0), Vector3(B, D + 1.1, L - 8.0), hull)
			_box(st, Vector3(0, D + 0.02, 0), Vector3(B - 1.0, 0.04, L - 8.0), deck)
			for e: float in [-1.0, 1.0]:
				# (the ramps at either end, hinged half up)
				var r := Basis(Vector3.RIGHT, e * deg_to_rad(18.0))
				_box(st, Vector3(0, D + 0.9, e * (L * 0.5 - 2.0)), Vector3(B - 3.0, 0.3, 4.6), deck, r)
			for side: float in [-1.0, 1.0]:
				_box(st, Vector3(side * (B * 0.5 - 0.15), D + 0.55, 0), Vector3(0.2, 1.1, L - 8.0), stripe)
			_box(st, Vector3(B * 0.5 - 1.6, D + 2.6, 0), Vector3(2.6, 5.2, 4.0), upper)
			_box(lit, Vector3(B * 0.5 - 1.6, D + 4.2, 0), Vector3(2.7, 0.9, 4.1), Color.WHITE)
			_box(st, Vector3(B * 0.5 - 1.6, D + 5.35, 0), Vector3(3.0, 0.3, 4.6), funnel)
		"roro":
			_box(st, Vector3(0, (D - 2.2) * 0.5, 4.0), Vector3(B, D + 2.2, L - 8.0), hull)
			_wedge(st, Vector3(0, (D - 2.2) * 0.5, -L * 0.5 + 4.0), Vector3(B, D + 2.2, 8.0), hull)
			_box(st, Vector3(0, D - 0.4, 4.0), Vector3(B, 0.25, L - 8.0), stripe)
			_box(st, Vector3(0, D + 0.02, 6.0), Vector3(B - 1.2, 0.04, L - 14.0), deck)
			for side: float in [-1.0, 1.0]:
				_box(st, Vector3(side * (B * 0.5 - 0.25), D + 1.3, 10.0), Vector3(0.4, 2.6, L - 24.0), hull)
			# (the bridge over the bow, its windows; the funnel and the mast)
			_box(st, Vector3(0, D + 3.4, -L * 0.5 + 9.0), Vector3(B - 1.0, 6.8, 9.0), upper)
			_box(lit, Vector3(0, D + 5.4, -L * 0.5 + 9.0), Vector3(B - 0.9, 1.0, 9.1), Color.WHITE)
			_box(st, Vector3(0, D + 2.2, -L * 0.5 + 9.0), Vector3(B - 0.9, 0.5, 9.1), stripe)
			_box(st, Vector3(B * 0.5 - 3.0, D + 8.3, -L * 0.5 + 12.0), Vector3(2.0, 3.2, 2.6), funnel)
			_box(st, Vector3(0, D + 9.5, -L * 0.5 + 7.0), Vector3(0.25, 5.4, 0.25), upper)
			_box(lit, Vector3(0, D + 12.3, -L * 0.5 + 7.0), Vector3(0.5, 0.4, 0.5), Color.WHITE)
		_:
			_box(st, Vector3(0, (D - 5.0) * 0.5, 8.0), Vector3(B, D + 5.0, L - 16.0), hull)
			_wedge(st, Vector3(0, (D - 5.0) * 0.5, -L * 0.5 + 8.0), Vector3(B, D + 5.0, 16.0), hull)
			_box(st, Vector3(0, D - 1.0, 8.0), Vector3(B + 0.05, 0.6, L - 16.0), stripe)
			_box(st, Vector3(0, D + 0.02, 41.0), Vector3(B - 2.0, 0.04, 36.0), deck)
			for side: float in [-1.0, 1.0]:
				_box(st, Vector3(side * (B * 0.5 - 0.3), D + 1.0, 41.0), Vector3(0.5, 2.0, 36.0), hull)
			# (the cabins, deck on deck, their windows in bands; two funnels)
			_box(st, Vector3(0, D + 6.0, -18.0), Vector3(B - 2.0, 12.0, 74.0), upper)
			for k in 3:
				_box(lit, Vector3(0, D + 1.8 + k * 3.6, -18.0), Vector3(B - 1.9, 1.0, 74.1), Color.WHITE)
			_box(st, Vector3(0, D + 12.4, -40.0), Vector3(B - 6.0, 2.8, 14.0), upper)
			_box(lit, Vector3(0, D + 12.6, -40.0), Vector3(B - 5.9, 1.0, 14.1), Color.WHITE)
			for side: float in [-1.0, 1.0]:
				_box(st, Vector3(side * 4.5, D + 15.0, 4.0), Vector3(3.2, 6.0, 5.0), funnel)
			_box(st, Vector3(0, D + 19.0, -36.0), Vector3(0.3, 7.0, 0.3), upper)
			_box(lit, Vector3(0, D + 22.6, -36.0), Vector3(0.6, 0.5, 0.6), Color.WHITE)
	var out := _finish(st, lit)
	_lock.lock()
	_meshes[key] = out
	_lock.unlock()
	return out


static func _col(kit: Dictionary, field: String, fallback: Color) -> Color:
	var v = kit.get(field)
	return Color.html(str(v)) if v != null and Color.html_is_valid(str(v)) else fallback


## The linkspan: a deck from the road's end out over the water, falling to it, its rails, and the lifting towers at
## its outer end. Its land end at the origin, running out along -z.
## (made level and RAMP_LEN long, its foot at the origin running out along -z: each one's stretched out to its boat
## and tilted down to its deck: ramp_basis)
static func _ramp(st: SurfaceTool, lit: SurfaceTool) -> void:
	var steel := Color(0.36, 0.38, 0.4)
	_box(st, Vector3(0, -0.25, -RAMP_LEN * 0.5), Vector3(RAMP_W, 0.5, RAMP_LEN), Color(0.3, 0.3, 0.31))
	for side: float in [-1.0, 1.0]:
		_box(st, Vector3(side * (RAMP_W * 0.5 - 0.1), 0.5, -RAMP_LEN * 0.5), Vector3(0.12, 1.0, RAMP_LEN), steel)


## The gantry the ramp's outer end hangs from, and its lamps (standing on its own: not stretched with the ramp).
static func _gantry(st: SurfaceTool, lit: SurfaceTool) -> void:
	for side: float in [-1.0, 1.0]:
		_box(st, Vector3(side * (RAMP_W * 0.5 + 0.6), 3.5, 0.0), Vector3(0.8, 7.0, 0.8), Color(0.75, 0.62, 0.12))
		_box(lit, Vector3(side * (RAMP_W * 0.5 + 0.6), 7.2, 0.0), Vector3(0.45, 0.45, 0.45), Color.WHITE)
	_box(st, Vector3(0, 7.0, 0.0), Vector3(RAMP_W + 2.0, 0.6, 0.6), Color(0.75, 0.62, 0.12))


## A ramp's basis: heading `h` (radians clockwise from north), `long` m out to its boat, falling `drop` m to its deck
## (kept to RAMP_STEEP).
static func ramp_basis(h: float, long: float, drop: float) -> Basis:
	var fall := clampf(drop, -long * RAMP_STEEP, long * RAMP_STEEP)
	return Basis(Vector3.UP, -h) * Basis(Vector3.RIGHT, -atan2(fall, long)) * Basis.from_scale(Vector3(1.0, 1.0, Vector2(long, fall).length() / RAMP_LEN))


## How far out from the road's end a boat lies, for a link's `line` from that end (FerryLinks.line_from: the
## junction, then the route): the route's own start, kept to BERTH_LEAST..BERTH_MOST.
static func berth(line: PackedVector2Array) -> float:
	return clampf(line[0].distance_to(line[mini(1, line.size() - 1)]), BERTH_LEAST, BERTH_MOST)


## Where along a route or link `m` m long a boat's middle is `s` m into its crossing (0 to m), lying `from_off` m off
## its start and `to_off` m off its end at rest (each its berth and half the boat).
static func sailed(m: float, s: float, from_off: float, to_off: float) -> float:
	var a := minf(from_off, m * 0.4)
	var b := minf(to_off, m * 0.4)
	return a + s * maxf(m - a - b, 1.0) / maxf(m, 1.0)


## The ticket office: a hut in `col` with its roof and a lit window.
static func _hut(st: SurfaceTool, lit: SurfaceTool, col: Color) -> void:
	_box(st, Vector3(0, 1.5, 0), Vector3(6.0, 3.0, 3.4), col)
	_box(st, Vector3(0, 3.15, 0), Vector3(6.6, 0.3, 4.0), Color(0.25, 0.27, 0.3))
	_box(lit, Vector3(0, 1.8, -1.71), Vector3(3.4, 1.0, 0.02), Color.WHITE)


static func _finish(st: SurfaceTool, lit: SurfaceTool) -> ArrayMesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	st.set_material(mat)
	var out := st.commit()
	lit.set_material(lamp_material())
	lit.commit(out)
	return out


## The windows' and lamps' glass, lit at dusk (Boats sets how bright).
static func lamp_material() -> StandardMaterial3D:
	_lock.lock()
	if _lamp_mat == null:
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.albedo_color = Color(0.32, 0.36, 0.4)
		_lamp_mat.emission_enabled = true
		_lamp_mat.emission = Color(1.0, 0.85, 0.6)
		_lamp_mat.emission_energy_multiplier = 0.05
	var m := _lamp_mat
	_lock.unlock()
	return m


## An axis-aligned box `s` big at `c` (turned by `b` about its middle) in `col`, its faces lit from outside.
static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, b := Basis.IDENTITY) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)],
	]
	for f: Array in faces:
		_quad(st, b * (f[0] as Vector3), [c + b * (f[1] as Vector3), c + b * (f[2] as Vector3), c + b * (f[3] as Vector3),
			c + b * (f[4] as Vector3)], col)


## A bow: `s` big at `c`, coming to a point at its -z end (the stem), its deck flat.
static func _wedge(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var stem_top := c + Vector3(0, h.y, -h.z)
	var stem_foot := c + Vector3(0, -h.y, -h.z * 0.4)
	var lt := c + Vector3(-h.x, h.y, h.z)
	var rt := c + Vector3(h.x, h.y, h.z)
	var lb := c + Vector3(-h.x, -h.y, h.z)
	var rb := c + Vector3(h.x, -h.y, h.z)
	_tri(st, [lt, rt, stem_top], col)
	_quad(st, (rt - stem_top).cross(rb - stem_top).normalized() * -1.0, [stem_foot, rb, rt, stem_top], col)
	_quad(st, (lt - stem_top).cross(lb - stem_top).normalized(), [lb, stem_foot, stem_top, lt], col)
	_tri(st, [lb, rb, stem_foot], col)


static func _quad(st: SurfaceTool, nrm: Vector3, v: Array, col: Color) -> void:
	_tri(st, [v[0], v[1], v[2]], col, nrm)
	_tri(st, [v[0], v[2], v[3]], col, nrm)


static func _tri(st: SurfaceTool, v: Array, col: Color, nrm := Vector3.ZERO) -> void:
	var n := nrm if nrm != Vector3.ZERO else ((v[1] as Vector3) - (v[0] as Vector3)).cross((v[2] as Vector3) - (v[0] as Vector3)).normalized()
	# (wound so each face is seen from the side its normal points to)
	var flip := ((v[1] as Vector3) - (v[0] as Vector3)).cross((v[2] as Vector3) - (v[0] as Vector3)).dot(n) > 0.0
	var order := [0, 2, 1] if flip else [0, 1, 2]
	for k in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v[k])
