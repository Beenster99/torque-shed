class_name FerryScenery
extends RefCounted
## Ferries (Ride Anywhere v2, phase D round 3, D7: interfaces/scenery.md): the boats that sail the map's ferry routes,
## and at each terminal the ramp (a linkspan) where the road meets the water and the ticket office. The routes and
## which roads they join are FerryLinks'; the crew's own crossing is FerryCrossing's, on a boat made here (boat_mesh).
##
## Three sizes of boat, by the route (FerryLinks.size_of), all small (two to four cars: Simon's crew is four bikes at
## most) and all drive-through, a ramp at each end and the cabin to one side of the vehicle deck (so the crew ride on at
## one end and off at the other: FerryCrossing): a chain ferry (a floating bridge, its wheelhouse at the side) on the
## short ones, a roll-on roll-off car ferry (a long cabin down one side, the bridge on top) on most, and an island ferry
## (bigger, the same way about) on the long ones. Their
## colours are their region's (the kit library's ferry rows), with a default for anywhere a region has none.
##
## Every boat sails its route from the start, back and forth on a timetable from the route alone (its length and its
## id) and the crew's clock (Daylight's hours, the host's on a co-op ride), so every machine sees the same boat in the
## same place without a word between them. A block draws the boats whose middles are in it (dress); at dusk their
## windows and mast lights come on. A route the crew is crossing on is left to their own boat (crew_ids).
##
## Simon's first rule, as here: nothing has collision, nothing stands on a road (a ticket office is stood off it, by
## SceneryStreamer.stand), and a ramp starts where the road already ends at the water (or up its slipway, where it's
## dry) and goes out over it. The crew's own boat, and the ramps at its terminals, are made solid by FerryCrossing.

const Clock := preload("res://scripts/scenery/rail_train.gd")

## Part of what a block lays out: bump it with the look (SceneryStreamer folds the scripts' versions into its own).
const VERSION := 4
## How fast the scenery's boats sail (m/s) and how long each waits at either end (s).
const SPEED := 9.0
const DWELL := 90.0
## Each size's boat: its length, beam and deck height above the water (m); how far its open deck runs either side of
## its middle (m, bow at -z), the lane along it a bike can ride (x from, x to: clear of the rails and the cabin) and the
## cabin standing on it to one side ({x, z (its middle), w, l (its footprint), h}). All three are drive-through, as the
## small Scottish car ferries are: a ramp at each end and the cabin beside the vehicle deck, never across it, so the
## crew ride on at one end and off at the other (and the boat never turns round: its bow's always towards its route's
## b end, FerryCrossing).
const BOATS := {
	"chain": {"len": 20.0, "beam": 9.0, "deck": 0.7, "half": 8.0, "lane": Vector2(-4.2, 2.5), "rail": 0.9,
		"house": {"x": 3.55, "z": 0.0, "w": 1.6, "l": 2.4, "h": 3.0}},
	"roro": {"len": 24.0, "beam": 8.5, "deck": 1.0, "half": 11.0, "lane": Vector2(-3.9, 1.4), "rail": 1.2,
		"house": {"x": 2.75, "z": 0.0, "w": 2.4, "l": 10.0, "h": 2.6}},
	"ship": {"len": 32.0, "beam": 10.0, "deck": 1.6, "half": 15.0, "lane": Vector2(-4.6, 1.3), "rail": 1.2,
		"house": {"x": 3.25, "z": -2.0, "w": 3.2, "l": 16.0, "h": 3.0}},
}
## How long a boat's end ramp is (m), and how far up it's raised at sea (radians): it's the gate across the deck's end.
const FLAP_LEN := 4.0
const FLAP_UP := 1.25
## The linkspan's size (m) and how far it drops to the water over its length.
const RAMP_LEN := 14.0
const RAMP_W := 8.0
## A ramp starts where the road's this high (m) over the water at least, this far (m) up a slipway at most (dry_foot).
const DRY := 0.4
const DRY_MOST := 120.0
## How far out from the road's end (m) a boat lies, at least and at most: where the route itself sets out from (the
## slipway's end), as near as that allows.
const BERTH_LEAST := 10.0
const BERTH_MOST := 60.0
## Where a boat lies: on from its ramp to where the ground's this far (m) under the water, looked for every WET_STEP (m)
## and as far as WET_MOST (or near half the route).
const WET := 1.5
const WET_STEP := 8.0
const WET_MOST := 3000.0
## How steeply a ramp may climb or fall to a boat's deck (rise over run).
const RAMP_STEEP := 0.25
## How far under a ramp's surface the shore has to be all along it (m), so a bike's wheels ride over the joint.
const RAMP_CLEAR := 0.12
## How far over the road's end a ramp may start out on its bank (m): higher, it's left as it is.
const KNEE_UP := 0.5
## A route's water is the sea unless both its ends are higher than this (m): then it's a lake, just under its banks.
const LAKE_FROM := 15.0
## Bikes on a deck stand this far apart (m) across and along it.
const SLOT_X := 3.2
const SLOT_Z := 3.6

## The routes the crew is crossing on just now (FerryCrossing): {route id: true}; the scenery leaves them be.
static var crew_ids := {}
static var _meshes := {}
static var _lies := {}
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
			var ramp := ramp_of(n, links, i, end)
			if ramp.is_empty():
				out["skipped"] += 1
				continue
			var rb: Basis = ramp["basis"]
			var foot: Vector3 = ramp["foot"] - o
			_add(out, "ramp", Transform3D(rb, foot))
			_add(out, "gantry", Transform3D(Basis(Vector3.UP, -float(ramp["h"])), foot + rb * Vector3(0, 0, -RAMP_LEN + 0.6)))
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
		var water := water_of(n, pts)
		var back := pts.duplicate()
		back.reverse()
		boats.append({"pts": pts, "m": m, "id": str(route["id"]), "size": FerryLinks.size_of(str(route["name"]), m),
			"kit": SceneryStreamer.kit("ferry", region_id), "water": water,
			"afloat": Vector2(lies(pts, n.height, water, 0.0), lies(back, n.height, water, 0.0))})
	if not boats.is_empty() or lamps:
		out["dress"] = {"corner": corner, "boats": boats, "lamps": lamps}
	return out


## The ramp (linkspan) at end `end` of link `i` (FerryLinks), in the region frame: {road (the road's end it's reached
## from), foot (where it starts, on the road's or the ground's surface), tip (its outer end, on its surface), basis (the
## "ramp" model's: turned, tilted and stretched), h (its heading)}; {} where the ground's not there yet. It starts at
## the road's end, or on up the road from there where the road runs on down a slipway under the water (DRY over it),
## and runs out to where the boat lies, down (or up) to its deck; where the shore bulges up over that straight line
## (a ramp ridden into the bank would stop a bike dead), it starts further out instead, on the ground where it
## clears it all the way (the shore ridden over to it).
static func ramp_of(n: RoadNet, links: FerryLinks, i: int, end: int) -> Dictionary:
	var at := n.region.node_pos[end]
	var line := links.line_from(i, end)
	var out_dir := _out_of(line)
	var level := water_of(n, line)
	var road := dry_foot(n, end, out_dir, level)
	if is_nan(road.y):
		return {}
	var tip_at := at + out_dir * berth(line)
	var deck := float(BOATS[str(links.links[i]["size"])]["deck"])
	var ramp := _ramp_from(road, tip_at, out_dir, level, deck)
	for k in 3:
		var knee := _knee(n, ramp, tip_at)
		if is_nan(knee.y) or knee.y > road.y + KNEE_UP:
			break   # (clear; or a bank higher than the road there, never ridden up onto)
		ramp = _ramp_from(knee, tip_at, out_dir, level, deck)
	road.y += 0.02
	ramp["road"] = road
	return ramp


## A straight ramp from `foot` (on a surface) out to `tip_at`, down (or up) to the deck.
static func _ramp_from(foot: Vector3, tip_at: Vector2, out_dir: Vector2, level: float, deck: float) -> Dictionary:
	var run := tip_at - Vector2(foot.x, foot.z)
	var long := maxf(run.length(), RAMP_LEN * 0.5)
	var dir := run.normalized() if run.length() > 0.5 else out_dir
	var h := atan2(dir.x, -dir.y)
	var rb := ramp_basis(h, long, foot.y - level - deck)
	foot.y += 0.02
	return {"foot": foot, "tip": foot + rb * Vector3(0, 0, -RAMP_LEN), "basis": rb, "h": h}


## Where on the ground a `ramp` that runs into the shore (the ground within RAMP_CLEAR of its surface)
## should start instead: the point it can run straight on from to its tip clear of it all (y NAN where it's clear as it
## is). Kept RAMP_LEN / 2 from the tip at least.
static func _knee(n: RoadNet, ramp: Dictionary, tip_at: Vector2) -> Vector3:
	var foot: Vector3 = ramp["foot"]
	var tip: Vector3 = ramp["tip"]
	var from := Vector2(foot.x, foot.z)
	var long := from.distance_to(tip_at)
	var most := long - RAMP_LEN * 0.5
	var hit := false
	var best := -INF
	var knee := Vector3(0, NAN, 0)
	var side := (tip_at - from).normalized().orthogonal() * RAMP_W * 0.4
	var s := 1.0
	while s < long - 0.5:
		var p := from.lerp(tip_at, s / long)
		var g := surface_at(n, p)   # (the highest across it: a bike rides on at an angle from the road)
		for q: Vector2 in [p - side, p + side]:
			var gq := surface_at(n, q)
			if not is_nan(gq) and (is_nan(g) or gq > g):
				g = gq
		if not is_nan(g):
			if g > lerpf(foot.y, tip.y, s / long) - RAMP_CLEAR:
				hit = true
			var slope := (g - tip.y) / (long - s)
			if s <= most and slope > best:
				best = slope
				knee = Vector3(p.x, g, p.y)
		s += 1.0
	return knee if hit else Vector3(0, NAN, 0)


## The height of the ground at `p` (region frame; NAN where it's not there yet).
static func surface_at(n: RoadNet, p: Vector2) -> float:
	return float(n.height.call(p.x, p.y))


## Where a ramp at terminal junction `node` starts (region frame, on the road; y NAN where the ground's not there yet):
## the road's end, or as far on up the road leading away from the water (`out_dir`) as it takes to be DRY over the water
## at `level` (a slipway runs on down under it), DRY_MOST at most.
static func dry_foot(n: RoadNet, node: int, out_dir: Vector2, level: float) -> Vector3:
	var r := n.region
	var at := r.node_pos[node]
	var on := n.locate(at.x, at.y)
	var y := float(on["y"]) if not on.is_empty() and bool(on.get("on_road", false)) else float(n.height.call(at.x, at.y))
	if is_nan(y) or y >= level + DRY:
		return Vector3(at.x, y, at.y)
	var best := -1
	var best_dot := INF
	for e in r.adjacent[node]:
		var line := r.line_from(e, node)
		var d := (line[mini(1, line.size() - 1)] - line[0]).normalized()
		if d.dot(out_dir) < best_dot:
			best_dot = d.dot(out_dir)
			best = e
	if best < 0:
		return Vector3(at.x, y, at.y)
	var len := r.edge_len[best]
	var s := 4.0
	while true:
		var last := s >= minf(DRY_MOST, len)
		s = minf(s, len)
		var p := n.point_at(best, s if r.edge_a[best] == node else len - s)
		var got := n.locate(p.x, p.y, best)
		var py := float(got["y"]) if not got.is_empty() else float(n.height.call(p.x, p.y))
		if is_nan(py):
			return Vector3(p.x, NAN, p.y)
		if py >= level + DRY or last:
			return Vector3(p.x, py, p.y)
		s += 4.0
	return Vector3(at.x, y, at.y)


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


## Where bike `slot` stands on a `size` boat's deck, in the boat's frame (bow at -z): two abreast down the lane, from the
## stern on.
static func slot_at(size: String, slot: int) -> Vector3:
	var b: Dictionary = BOATS.get(size, BOATS["roro"])
	var lane: Vector2 = b["lane"]
	var across := maxi(1, int((lane.y - lane.x) / SLOT_X))
	var row := slot / across
	var col := slot % across
	var x := (lane.x + lane.y) * 0.5 + (col - (across - 1) * 0.5) * SLOT_X
	var z := float(b["half"]) - 3.0 - row * SLOT_Z
	return Vector3(x, float(b["deck"]), maxf(z, -float(b["half"]) + 3.0))


## The solid parts of a `size` boat over the water, in its frame (bow at -z), as [[middle, size], ...] boxes: the deck
## (its top the deck's height), the rails down either side, the bits of each end beside the lane, and the cabin. The
## crew's boat stands on them (FerryCrossing); the ends' gates and ramps are the ramps' own (flap).
static func solids(size: String) -> Array:
	var b: Dictionary = BOATS.get(size, BOATS["roro"])
	var B := float(b["beam"])
	var D := float(b["deck"])
	var H := float(b["half"])
	var R := float(b["rail"])
	var lane: Vector2 = b["lane"]
	var house: Dictionary = b["house"]
	var out: Array = [[Vector3(0, D - 0.6, 0), Vector3(B, 1.2, H * 2.0)]]
	for side: float in [-1.0, 1.0]:
		out.append([Vector3(side * (B * 0.5 - 0.15), D + R * 0.5, 0), Vector3(0.3, R, H * 2.0)])
	var beside := B * 0.5 - 0.3 - lane.y
	if beside > 0.05:
		for end: float in [-1.0, 1.0]:
			out.append([Vector3(lane.y + beside * 0.5, D + R * 0.5, end * (H - 0.15)), Vector3(beside, R, 0.3)])
	out.append([Vector3(float(house["x"]), D + float(house["h"]) * 0.5, float(house["z"])),
		Vector3(float(house["w"]), float(house["h"]), float(house["l"]))])
	return out


## Whether boat-frame point `p` is over a `size` boat's deck (anywhere inside its rails, from just under the deck to well
## over it): what stands there is aboard, and goes where the boat goes.
static func on_deck(size: String, p: Vector3, margin := 0.0) -> bool:
	var b: Dictionary = BOATS.get(size, BOATS["roro"])
	return absf(p.x) <= float(b["beam"]) * 0.5 + margin and absf(p.z) <= float(b["half"]) + margin \
		and p.y > float(b["deck"]) - 1.2 and p.y < float(b["deck"]) + 4.5


## Where the end ramp at end `end` (+1 the stern, -1 the bow) of a `size` boat is hinged, in its frame: the lane's
## middle at the deck's end.
static func hinge(size: String, end: float) -> Vector3:
	var b: Dictionary = BOATS.get(size, BOATS["roro"])
	var lane: Vector2 = b["lane"]
	return Vector3((lane.x + lane.y) * 0.5, float(b["deck"]), end * float(b["half"]))


## An end ramp: the lane wide, FLAP_LEN long, hinged at the origin running out along -z (turned to each end and raised or
## lowered by the crew's boat, FerryCrossing; the scenery's boats have theirs part raised).
static func flap_mesh(size: String, kit: Dictionary) -> Mesh:
	var key := "flap|%s|%s" % [size, kit.get("deck", "")]
	_lock.lock()
	var have: Mesh = _meshes.get(key)
	_lock.unlock()
	if have != null:
		return have
	var b: Dictionary = BOATS.get(size, BOATS["roro"])
	var lane: Vector2 = b["lane"]
	var w := lane.y - lane.x
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := _col(kit, "deck", Color(0.33, 0.35, 0.33))
	_box(st, Vector3(0, -0.12, -FLAP_LEN * 0.5), Vector3(w, 0.24, FLAP_LEN), deck)
	for k in 6:
		# (the ribs across it, for grip)
		_box(st, Vector3(0, 0.01, -0.4 - k * 0.65), Vector3(w - 0.2, 0.04, 0.08), deck.darkened(0.25))
	var out := _finish(st, lit)
	_lock.lock()
	_meshes[key] = out
	_lock.unlock()
	return out


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
			var half := float(FerryScenery.BOATS[str(r["size"])]["len"]) * 0.5 + 2.0   # (its stern by the route's end, afloat)
			var afloat: Vector2 = r.get("afloat", Vector2.ZERO)
			var p := FerryScenery.along(r["pts"], FerryScenery.sailed(float(r["m"]), at.x, half + afloat.x, half + afloat.y))
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
## waterline at y 0, its bow at -z; with its end ramps part raised unless `flaps` is off (the crew's boat moves its own,
## flap_mesh). Made once a look, shared.
static func boat_mesh(size: String, kit: Dictionary, flaps := true) -> Mesh:
	var key := "%s|%s|%s|%s|%s|%s|%s" % [size, kit.get("hull", ""), kit.get("upper", ""), kit.get("funnel", ""),
		kit.get("stripe", ""), kit.get("deck", ""), flaps]
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
	var B := float(b["beam"])
	var D := float(b["deck"])
	var H := float(b["half"])
	var R := float(b["rail"])
	var lane: Vector2 = b["lane"]
	var house: Dictionary = b["house"]
	var hx := float(house["x"])
	var hz := float(house["z"])
	var hw := float(house["w"])
	var hl := float(house["l"])
	var hh := float(house["h"])
	var draft := 0.9 if size == "chain" else (1.5 if size == "roro" else 2.0)
	# The hull, a little blunt at either end (they're alike: it sails either way), the band along its top, the deck.
	_box(st, Vector3(0, (D - draft) * 0.5, 0), Vector3(B, D + draft, H * 2.0), hull)
	for end: float in [-1.0, 1.0]:
		_box(st, Vector3(0, (D - draft) * 0.5 + 0.3, end * (H + 0.5)), Vector3(B - 1.6, D + draft - 0.6, 1.0), hull)
	_box(st, Vector3(0, D - 0.35, 0), Vector3(B + 0.04, 0.25, H * 2.0 - 0.2), stripe)
	_box(st, Vector3(0, D + 0.02, 0), Vector3(B - 0.6, 0.04, H * 2.0 - 0.2), deck)
	# (the lane's lines, for the crew to keep to)
	for x: float in [lane.x + 0.15, lane.y - 0.15]:
		_box(st, Vector3(x, D + 0.045, 0), Vector3(0.12, 0.01, H * 2.0 - 1.0), Color(0.85, 0.8, 0.3))
	for part: Array in solids(size).slice(1):
		var c: Vector3 = part[0]
		var sz: Vector3 = part[1]
		if absf(c.x - hx) < 0.01 and absf(c.z - hz) < 0.01:
			continue   # (the cabin's drawn below)
		_box(st, c, sz, hull)
	# The cabin beside the deck: its windows in a band, the wheelhouse on top, the funnel and the mast.
	_box(st, Vector3(hx, D + hh * 0.5, hz), Vector3(hw, hh, hl), upper)
	_box(lit, Vector3(hx, D + hh * 0.62, hz), Vector3(hw + 0.04, minf(0.8, hh * 0.3), hl - 0.6), Color.WHITE)
	var top := D + hh
	if size == "chain":
		_box(st, Vector3(hx, top + 0.1, hz), Vector3(hw + 0.4, 0.2, hl + 0.4), funnel)
	else:
		var wl := minf(4.0, hl * 0.4)
		var wz := hz - hl * 0.5 + wl * 0.5 + 0.6
		_box(st, Vector3(hx - 0.3, top + 0.9, wz), Vector3(hw + 0.6, 1.8, wl), upper)
		_box(lit, Vector3(hx - 0.3, top + 1.15, wz), Vector3(hw + 0.64, 0.7, wl + 0.04), Color.WHITE)
		_box(st, Vector3(hx, top + 0.8, hz + hl * 0.25), Vector3(1.2, 1.6, 1.4), funnel)
		_box(st, Vector3(hx, top + 2.8, wz), Vector3(0.15, 2.4, 0.15), upper)
		_box(lit, Vector3(hx, top + 4.1, wz), Vector3(0.35, 0.3, 0.35), Color.WHITE)
	if flaps:
		var w := lane.y - lane.x
		for end: float in [-1.0, 1.0]:
			# (hinged at the deck's end, half up)
			var r := Basis(Vector3.RIGHT, -end * 0.7)
			var hinge_at := hinge(size, end)
			var mid := hinge_at + r * Vector3(0, 0, end * FLAP_LEN * 0.5)
			_box(st, mid + Vector3(0, -0.12, 0), Vector3(w, 0.24, FLAP_LEN), deck, r)
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
## junction, then the route): the route's own start, kept to BERTH_LEAST..BERTH_MOST. (Where the boat itself lies is
## afloat: lies.)
static func berth(line: PackedVector2Array) -> float:
	return clampf(line[0].distance_to(line[mini(1, line.size() - 1)]), BERTH_LEAST, BERTH_MOST)


## How far along `line` (m) a boat lies at rest, from `from` on (the ramp's end, berth(line), when it's less than 0): the
## first point on from there where the ground (`height`, a RoadNet's) is WET under the water at `level`. The map's
## routes are drawn roughly, often over a headland or a quay by either shore, and a boat there would sit on the land.
## Where the heights aren't all there yet, `from` (and not kept: asked again later).
static func lies(line: PackedVector2Array, height: Callable, level: float, from := -1.0) -> float:
	if from < 0.0:
		from = berth(line)
	if not height.is_valid() or line.size() < 2:
		return from
	var key := "%d|%s|%s|%s|%d|%.1f|%.1f" % [height.hash(), line[0], line[1], line[line.size() - 1], line.size(), level, from]
	_lock.lock()
	var kept = _lies.get(key)
	_lock.unlock()
	if kept != null:
		return float(kept)
	var most := minf(WET_MOST, FerryLinks._length(line) * 0.45)
	var s := from
	var out := from
	while s <= most:
		var p := along(line, s)
		var h := float(height.call(p.x, p.y))
		if is_nan(h):
			return from
		if h < level - WET:
			out = s
			break
		s += WET_STEP
	_lock.lock()
	if _lies.size() > 512:
		_lies.clear()
	_lies[key] = out
	_lock.unlock()
	return out


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
