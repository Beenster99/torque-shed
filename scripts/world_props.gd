class_name WorldProps
extends Node3D
## Everything that brings the riding map to life, placed from the seed (see plan()): woods of
## pines and broadleaf trees, boulders on the mountains and rock gardens on the hard tracks,
## armco barriers on the mountain roads' drops and hairpins with chevron boards, fingerposts
## at the junctions and name signs at the villages, villages of houses with a church and a
## pub, and farmyards with a barn, silos, a farmhouse, hay bales and fenced fields.
##
## Kept cheap to draw: trees, rocks, bales, fences and barriers are MultiMeshes split into
## CELL-sized squares that stop drawing past their range (times the draw distance setting),
## each village or farm is three merged meshes, and the collision for all of it is a few
## static bodies with shared shapes added straight to the physics server.

const CELL := 256.0
const TREE_RANGE := 1100.0
const ROCK_RANGE := 750.0
const BUILDING_RANGE := 1900.0
const SMALL_RANGE := 380.0
## Tree spacing in the woods: one chance of a tree per TREE_GRID metres square.
const TREE_GRID := 9.0

var _world: World
var _shapes := []        # shapes added straight to the physics server, kept alive here
var _bodies := []
var _mats := {}


# ---------------------------------------------------------------------------- the plan

## Where everything goes, worked out once per seed: {trees: [[xf, type, tint]], rocks:
## [[xf, variant, radius]], track_rocks, buildings: [{kind, site, xf, size, wall, roof}],
## fences: [[a, b]], armco: [[a, b]], chevrons: [xf], signs: [{xf, lines}], bales: [xf],
## lamps: [Vector3]}.
static func plan(t: WorldTerrain, r: WorldRoads, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var p := {"trees": [], "rocks": [], "track_rocks": [], "buildings": [], "fences": [], "armco": [], "chevrons": [],
		"signs": [], "bales": [], "lamps": []}
	var taken := {}
	_plan_sites(p, t, r, rng, taken)
	_plan_fields(p, t, r, taken)
	_plan_barriers(p, t, r)
	_plan_signs(p, t, r)
	_plan_rocks(p, t, r, rng, taken)
	_plan_trees(p, t, r, rng, taken)
	return p


## Marks the 8 m squares a footprint (centre, half size, turned `yaw`) covers as taken.
static func _take(taken: Dictionary, c: Vector2, half: Vector2, yaw: float, margin := 2.0) -> void:
	var rad := half.length() + margin
	for gx in range(floori((c.x - rad) / 8.0), floori((c.x + rad) / 8.0) + 1):
		for gz in range(floori((c.y - rad) / 8.0), floori((c.y + rad) / 8.0) + 1):
			taken[Vector2i(gx, gz)] = true


static func _is_taken(taken: Dictionary, x: float, z: float) -> bool:
	return taken.has(Vector2i(floori(x / 8.0), floori(z / 8.0)))


## Whether a building `half` in size (turned `yaw`) at `c` keeps `gap` metres off every road.
static func _clear_of_roads(r: WorldRoads, c: Vector2, half: Vector2, yaw: float, gap: float) -> bool:
	var b := Basis(Vector3.UP, yaw)
	for k: Vector2 in [Vector2(0, 0), Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
		var o: Vector3 = b * Vector3(half.x * k.x, 0.0, half.y * k.y)
		var near := r.nearest(c.x + o.x, c.y + o.z, 14.0 + gap)
		if not near.is_empty() and float(near["d"]) < float(r.roads[int(near["road"])]["hw"]) + gap:
			return false
	return true


## The lowest ground under a footprint, so a building's walls go down into it on a slope.
static func _base(t: WorldTerrain, c: Vector2, half: Vector2, yaw: float) -> float:
	var b := Basis(Vector3.UP, yaw)
	var lo := t.height_at(c.x, c.y)
	for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var o: Vector3 = b * Vector3(half.x * k.x, 0.0, half.y * k.y)
		lo = minf(lo, t.height_at(c.x + o.x, c.y + o.z))
	return lo


const WALLS := [Color(0.86, 0.82, 0.7), Color(0.9, 0.9, 0.87), Color(0.56, 0.3, 0.22), Color(0.63, 0.6, 0.54),
	Color(0.88, 0.8, 0.58), Color(0.72, 0.68, 0.6)]
const ROOFS := [Color(0.24, 0.26, 0.3), Color(0.5, 0.23, 0.16), Color(0.36, 0.28, 0.22), Color(0.3, 0.3, 0.32)]
const BARNS := [Color(0.55, 0.16, 0.12), Color(0.4, 0.42, 0.42), Color(0.45, 0.33, 0.22), Color(0.3, 0.38, 0.3)]


static func _building(p: Dictionary, kind: String, site: int, c: Vector2, base: float, yaw: float, size: Vector3,
		wall: Color, roof: Color) -> void:
	p["buildings"].append({"kind": kind, "site": site, "xf": Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, base, c.y)),
		"size": size, "wall": wall, "roof": roof})


## Villages: houses either side of the roads through them, set back a little and facing the
## road, with a church and a pub; farms: a farmhouse, a barn, silos, a shed and bales.
static func _plan_sites(p: Dictionary, t: WorldTerrain, r: WorldRoads, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	for si in WorldLayout.sites().size():
		var site: Dictionary = WorldLayout.sites()[si]
		var at: Vector2 = site["at"]
		var radius: float = site["r"]
		if site["kind"] == "village":
			var placed := 0
			var specials := ["church", "pub"]
			for ri in r.roads.size():
				var road: Dictionary = r.roads[ri]
				if road["kind"] != "tarmac":
					continue
				var xz: PackedVector2Array = road["xz"]
				var dirs: PackedVector2Array = road["dir"]
				var hw: float = road["hw"]
				var i := 0
				while i < xz.size():
					var d := xz[i].distance_to(at)
					if d > radius * 0.9:
						i += 4
						continue
					for side: float in [-1.0, 1.0]:
						var kind := "house"
						if not specials.is_empty() and d < radius * 0.45 and rng.randf() < 0.35:
							kind = specials.pop_front()
						var size := Vector3(rng.randf_range(7.0, 10.0), rng.randf_range(5.0, 6.5), rng.randf_range(6.0, 8.0))
						if kind == "church":
							size = Vector3(9.0, 8.0, 18.0)
						elif kind == "pub":
							size = Vector3(13.0, 6.5, 8.0)
						var right := Vector2(-dirs[i].y, dirs[i].x)
						var setback := hw + 5.0 + size.z * 0.5 + rng.randf_range(0.0, 3.0)
						var c := xz[i] + right * side * setback
						# The front (+Z) faces the road.
						var to_road := -right * side
						var yaw := atan2(to_road.x, to_road.y)
						var half := Vector2(size.x * 0.5, size.z * 0.5)
						if _is_taken(taken, c.x, c.y) or not _clear_of_roads(r, c, half, yaw, 3.0) \
								or t.slope_at(c.x, c.y) > 0.2:
							if kind != "house":
								specials.push_front(kind)
							continue
						_take(taken, c, half, yaw, 3.0)
						var wall: Color = WALLS[rng.randi() % WALLS.size()]
						var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
						if kind == "church":
							wall = Color(0.62, 0.6, 0.55)
							roof = ROOFS[0]
						_building(p, kind, si, c, _base(t, c, half, yaw), yaw, size, wall, roof)
						placed += 1
					# A street lamp now and then on the verge.
					if i % 30 == 0:
						var right2 := Vector2(-dirs[i].y, dirs[i].x)
						var lp := xz[i] + right2 * (hw + 1.6)
						p["lamps"].append(Vector3(lp.x, t.height_at(lp.x, lp.y), lp.y))
					i += rng.randi_range(9, 13)
		else:
			_plan_farm(p, t, r, rng, taken, si, at)


static func _plan_farm(p: Dictionary, t: WorldTerrain, r: WorldRoads, rng: RandomNumberGenerator, taken: Dictionary,
		si: int, at: Vector2) -> void:
	# Face the yard to the nearest road.
	var near := r.nearest(at.x, at.y, 300.0)
	var yaw := 0.0
	if not near.is_empty():
		var road: Dictionary = r.roads[int(near["road"])]
		var xz: PackedVector2Array = road["xz"]
		var to := xz[int(near["i"])] - at
		yaw = atan2(to.x, to.y)
	var b := Basis(Vector3.UP, yaw)
	var parts := [
		["farmhouse", Vector3(0.0, 0.0, 6.0), Vector3(10.0, 6.0, 7.0), 0.0],
		["barn", Vector3(-18.0, 0.0, -12.0), Vector3(14.0, 7.0, 24.0), 0.0],
		["silo", Vector3(6.0, 0.0, -20.0), Vector3(5.0, 13.0, 5.0), 0.0],
		["silo", Vector3(12.5, 0.0, -20.0), Vector3(4.2, 11.0, 4.2), 0.0],
		["shed", Vector3(18.0, 0.0, -4.0), Vector3(8.0, 4.0, 10.0), PI * 0.5],
	]
	var barn_col: Color = BARNS[rng.randi() % BARNS.size()]
	for part in parts:
		var off: Vector3 = b * (part[1] as Vector3)
		var c := at + Vector2(off.x, off.z)
		var size: Vector3 = part[2]
		var y: float = yaw + float(part[3])
		var half := Vector2(size.x * 0.5, size.z * 0.5)
		if not _clear_of_roads(r, c, half, y, 3.0):
			continue
		_take(taken, c, half, y, 2.0)
		var wall: Color = WALLS[rng.randi() % WALLS.size()]
		var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
		if part[0] == "barn" or part[0] == "shed":
			wall = barn_col
			roof = Color(0.32, 0.33, 0.33)
		elif part[0] == "silo":
			wall = Color(0.7, 0.72, 0.74)
			roof = Color(0.6, 0.62, 0.64)
		_building(p, str(part[0]), si, c, _base(t, c, half, y), y, size, wall, roof)
	# A stack of round bales by the barn.
	for k in 6:
		var off2: Vector3 = b * Vector3(-6.0 + (k % 3) * 1.9, 0.0, -24.0 - (k / 3) * 2.0)
		var c2 := at + Vector2(off2.x, off2.z)
		p["bales"].append(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(c2.x, t.height_at(c2.x, c2.y), c2.y)))
	_take(taken, at + Vector2((b * Vector3(-4.0, 0, -25.0)).x, (b * Vector3(-4.0, 0, -25.0)).z), Vector2(4.0, 3.0), yaw)


## Fences round the farms' fields (WorldTerrain.field_at), with gaps wherever a road or track
## passes, and bales left in some fields.
static func _plan_fields(p: Dictionary, t: WorldTerrain, r: WorldRoads, taken: Dictionary) -> void:
	for site in WorldLayout.sites():
		if site["kind"] != "farm":
			continue
		var at: Vector2 = site["at"]
		for cx in range(-5, 5):
			for cz in range(-8, 8):
				var x0 := at.x + cx * 70.0
				var z0 := at.y + cz * 45.0
				var mid := Vector2(x0 + 35.0, z0 + 22.5)
				var crop := WorldTerrain.field_at(mid.x, mid.y, at)
				if crop < 0:
					continue
				# Each field's north and west edges, and its south and east where the next field
				# along isn't a field: so shared edges get one fence.
				var edges := [[Vector2(x0, z0), Vector2(x0 + 70.0, z0)], [Vector2(x0, z0), Vector2(x0, z0 + 45.0)]]
				if WorldTerrain.field_at(mid.x, mid.y + 45.0, at) < 0:
					edges.append([Vector2(x0, z0 + 45.0), Vector2(x0 + 70.0, z0 + 45.0)])
				if WorldTerrain.field_at(mid.x + 70.0, mid.y, at) < 0:
					edges.append([Vector2(x0 + 70.0, z0), Vector2(x0 + 70.0, z0 + 45.0)])
				for e in edges:
					_fence_line(p, t, r, taken, e[0], e[1])
				if crop == 0:
					for k in 3:
						var bx := mid.x - 15.0 + k * 13.0
						var bz := mid.y + (k % 2) * 8.0 - 4.0
						if r.nearest(bx, bz, 12.0).is_empty() and not _is_taken(taken, bx, bz):
							p["bales"].append(Transform3D(Basis(Vector3.UP, k * 1.1), Vector3(bx, t.height_at(bx, bz), bz)))


## A fence from a to b in panels of up to 10 m, leaving out any panel near a road, a track
## or a building, or on a steep bank.
static func _fence_line(p: Dictionary, t: WorldTerrain, r: WorldRoads, taken: Dictionary, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var steps := ceili(length / 10.0)
	for k in steps:
		var p0 := a.lerp(b, float(k) / steps)
		var p1 := a.lerp(b, float(k + 1) / steps)
		var m := (p0 + p1) * 0.5
		# Clear of every road and track along the whole panel, not just at its middle.
		var crosses := false
		for q in [p0, m, p1, p0.lerp(p1, 0.25), p0.lerp(p1, 0.75)]:
			var near := r.nearest(q.x, q.y, 20.0)
			if not near.is_empty() and float(near["d"]) < float(r.roads[int(near["road"])]["hw"]) + 6.0:
				crosses = true
				break
		if crosses or _segment_crosses_road(r, p0, p1):
			continue
		if _is_taken(taken, m.x, m.y) or t.slope_at(m.x, m.y) > 0.3 or WorldTerrain.home_mask(m.x, m.y) < 0.5:
			continue
		p["fences"].append([Vector3(p0.x, t.height_at(p0.x, p0.y), p0.y), Vector3(p1.x, t.height_at(p1.x, p1.y), p1.y)])
		_take(taken, m, Vector2(2.0, 2.0), 0.0, 0.0)


## How many barrier samples (4 m each) of gap get filled in between two stretches of armco, and
## how far each stretch carries on past where it's needed.
const BARRIER_GAP_FILL := 5
const BARRIER_RUN_ON := 1


## `wants` with gaps of up to `fill` false entries between two trues made true, and each run
## of trues carried on `run_on` entries at both ends.
static func _join_runs(wants: Array, fill: int, run_on: int) -> Array:
	var out := wants.duplicate()
	var n := wants.size()
	var last := -1
	for i in n:
		if wants[i]:
			if last >= 0 and i - last - 1 <= fill:
				for j in range(last + 1, i):
					out[j] = true
			last = i
	var grown := out.duplicate()
	for i in n:
		if out[i]:
			for j in range(maxi(0, i - run_on), mini(n, i + run_on + 1)):
				grown[j] = true
	return grown


## Whether (x, z) is on (or within `margin` of) a road other than `road`.
static func _on_other_road(r: WorldRoads, road: Dictionary, x: float, z: float, margin: float) -> bool:
	var near := r.nearest(x, z, 30.0, "", r.roads.find(road))
	return not near.is_empty() and float(near["d"]) < float(r.roads[int(near["road"])]["hw"]) + margin


## Whether the line p0..p1 crosses any road's centre line.
static func _segment_crosses_road(r: WorldRoads, p0: Vector2, p1: Vector2) -> bool:
	var m := (p0 + p1) * 0.5
	var near := r.nearest(m.x, m.y, p0.distance_to(p1) + 8.0)
	if near.is_empty():
		return false
	var road: Dictionary = r.roads[int(near["road"])]
	var xz: PackedVector2Array = road["xz"]
	var i0 := maxi(int(near["i"]) - 12, 0)
	var i1 := mini(int(near["i"]) + 12, xz.size() - 1)
	for i in range(i0, i1):
		if Geometry2D.segment_intersects_segment(p0, p1, xz[i], xz[i + 1]) != null:
			return true
	return false


## Armco along tarmac where the ground drops away beside the road or round the outside of a
## hairpin, and chevron boards facing the traffic into each hairpin.
static func _plan_barriers(p: Dictionary, t: WorldTerrain, r: WorldRoads) -> void:
	for road in r.roads:
		if road["kind"] != "tarmac" or road["closed"]:
			continue
		var xz: PackedVector2Array = road["xz"]
		var hs: PackedFloat32Array = road["h"]
		var dirs: PackedVector2Array = road["dir"]
		var hw: float = road["hw"]
		var n := xz.size()
		var skip_a: float = float(road.get("start_skip", 0.0)) + 6.0
		var skip_b: float = float(road.get("end_skip", 0.0)) + 6.0
		var dist: PackedFloat32Array = road["dist"]
		for side: float in [-1.0, 1.0]:
			# Which samples want a barrier: a drop beside the road, or the outside of a bend.
			var wants := []
			for i in range(0, n, 2):
				var want := false
				if dist[i] > skip_a and dist[i] < float(road["length"]) - skip_b:
					var right := Vector2(-dirs[i].y, dirs[i].x) * side
					var out := xz[i] + right * (hw + 9.0)
					var drop := hs[i] - t.natural(out.x, out.y)
					var turn := 0.0
					if i > 2 and i < n - 3:
						var before := dirs[i - 3]
						var after := dirs[i + 3]
						turn = (before.x * after.y - before.y * after.x) / (6.0 * WorldRoads.STEP)
					var outside := turn * side < 0.0 and absf(turn) > 1.0 / 30.0
					want = drop > 4.0 or outside
				wants.append(want)
			# Short breaks between two stretches are filled in, and each stretch runs on a little
			# past its ends, so the barrier is one continuous rail rather than bits.
			wants = _join_runs(wants, BARRIER_GAP_FILL, BARRIER_RUN_ON)
			var run := []
			for k in wants.size():
				var i: int = k * 2
				var want: bool = wants[k]
				var at := Vector3.ZERO
				if want:
					var right2 := Vector3(-dirs[i].y, 0.0, dirs[i].x) * side
					at = Vector3(xz[i].x, hs[i], xz[i].y) + right2 * (hw + 0.9)
					# Never across another road (at a junction): the barrier stops short of it.
					if _on_other_road(r, road, at.x, at.z, 1.5):
						want = false
				if want:
					run.append(at)
				if not want or k == wants.size() - 1:
					if run.size() >= 3:
						for j in run.size() - 1:
							p["armco"].append([run[j], run[j + 1]])
					run = []
		# Chevrons: where a hairpin starts, on the outside, facing oncoming traffic both ways.
		var i := 6
		while i < n - 6:
			var before := dirs[i - 6]
			var after := dirs[i + 6]
			var bend := before.angle_to(after)
			if absf(bend) > PI * 0.45:
				var side := -signf(before.x * after.y - before.y * after.x)
				var right := Vector2(-dirs[i].y, dirs[i].x) * side
				var c := xz[i] + right * (hw + 2.6)
				var face := Vector2(-before.x, -before.y)
				p["chevrons"].append(Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), Vector3(c.x, t.height_at(c.x, c.y), c.y)))
				var face2 := after
				var c2 := xz[i] + right * (hw + 2.6) + after * 1.5
				p["chevrons"].append(Transform3D(Basis(Vector3.UP, atan2(face2.x, face2.y)), Vector3(c2.x, t.height_at(c2.x, c2.y), c2.y)))
				i += 24
			else:
				i += 2


## Fingerposts where each road or track leaves another, naming where it goes, and a name sign
## where roads come into each village or farm.
static func _plan_signs(p: Dictionary, t: WorldTerrain, r: WorldRoads) -> void:
	for road in r.roads:
		var j: Dictionary = road["start_join"]
		if j.is_empty():
			continue
		var xz: PackedVector2Array = road["xz"]
		var dirs: PackedVector2Array = road["dir"]
		var parent: Dictionary = r.roads[int(j["road"])]
		var k := mini(ceili((float(parent["hw"]) + 4.0) / WorldRoads.STEP), xz.size() - 1)
		var right := Vector2(-dirs[k].y, dirs[k].x)
		var c := xz[k] + right * (float(road["hw"]) + 2.2)
		var face := -dirs[k]
		var what := "%s  %.1f km" % [road["label"], float(road["length"]) / 1000.0]
		if road["kind"] == "dirt":
			what = "%s (track)%s" % [road["label"], "  - rough" if road["hard"] else ""]
		p["signs"].append({"xf": Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), Vector3(c.x, t.height_at(c.x, c.y), c.y)),
			"lines": [what], "style": "finger"})
	for site in WorldLayout.sites():
		var at: Vector2 = site["at"]
		var radius: float = site["r"]
		for road in r.roads:
			if road["kind"] != "tarmac":
				continue
			var xz: PackedVector2Array = road["xz"]
			var dirs: PackedVector2Array = road["dir"]
			for i in range(1, xz.size()):
				var d0 := xz[i - 1].distance_to(at)
				var d1 := xz[i].distance_to(at)
				var edge := radius * (0.95 if site["kind"] == "village" else 1.3)
				if (d0 > edge) != (d1 > edge):
					var inward := dirs[i] if d1 < d0 else -dirs[i]
					var right := Vector2(-inward.y, inward.x)
					var c := xz[i] + right * (float(road["hw"]) + 2.0)
					var face := -inward
					p["signs"].append({"xf": Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), Vector3(c.x, t.height_at(c.x, c.y), c.y)),
						"lines": [str(site["name"]).to_upper()], "style": "village" if site["kind"] == "village" else "farm"})


## Boulders: many on the mountains (more on the steep ground), a few in the lowlands, and rock
## gardens of small flat rocks on the hard mountain tracks.
static func _plan_rocks(p: Dictionary, t: WorldTerrain, r: WorldRoads, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var grid := 22.0
	var cells := int(WorldTerrain.HALF * 2.0 / grid)
	for gz in cells:
		for gx in cells:
			var x := -WorldTerrain.HALF + (gx + rng.randf()) * grid
			var z := -WorldTerrain.HALF + (gz + rng.randf()) * grid
			var h := t.height_at(x, z)
			var slope := t.slope_at(x, z)
			var chance := 0.012 + smoothstep(60.0, 200.0, h) * 0.25 + smoothstep(0.15, 0.5, slope) * 0.3
			if rng.randf() > chance:
				continue
			var i := WorldTerrain.index_of(x, z)
			if t.road_k[i] != 0 and t.road_d[i] < 14.0:
				continue
			if WorldTerrain.home_mask(x, z) < 0.6 or _is_taken(taken, x, z):
				continue
			var size := rng.randf_range(0.5, 1.6) * (1.0 + smoothstep(100.0, 250.0, h) * 1.4)
			if rng.randf() < 0.06:
				size *= 2.2
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * rng.randf_range(0.9, 1.4), size * rng.randf_range(0.55, 0.9), size)),
				Vector3(x, h - size * 0.25, z))
			p["rocks"].append([xf, rng.randi() % 3, size])
	for road in r.roads:
		if not road["hard"]:
			continue
		var xz: PackedVector2Array = road["xz"]
		var hs: PackedFloat32Array = road["h"]
		var dirs: PackedVector2Array = road["dir"]
		var hw: float = road["hw"]
		var i := 30
		while i < xz.size() - 30:
			# A rock garden: a dozen small rocks over 20 m of track, some just poking out of it.
			if rng.randf() < 0.35:
				for k in 12:
					var s := i + rng.randi_range(0, 10)
					var right := Vector3(-dirs[s].y, 0.0, dirs[s].x)
					var off := rng.randf_range(-hw - 1.5, hw + 1.5)
					var on_track := absf(off) < hw
					var size := rng.randf_range(0.35, 0.6) if on_track else rng.randf_range(0.4, 0.9)
					var base := Vector3(xz[s].x, hs[s], xz[s].y) + right * off
					var poke := rng.randf_range(0.06, 0.12) if on_track else size * 0.4
					var flat := 0.35
					var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * flat, size * 1.2)),
						base + Vector3.UP * (poke - size * flat * 0.8))
					p["track_rocks"].append([xf, rng.randi() % 3, size])
			i += 40


## Woods where the forest noise says, thinning out up the mountains and none on the roads,
## fields, yards or buildings; lone trees here and there in the open.
static func _plan_trees(p: Dictionary, t: WorldTerrain, r: WorldRoads, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var cells := int(WorldTerrain.HALF * 2.0 / TREE_GRID)
	var farms := []
	for site in WorldLayout.sites():
		if site["kind"] == "farm":
			farms.append(site["at"])
	for gz in cells:
		for gx in cells:
			var x := -WorldTerrain.HALF + (gx + rng.randf()) * TREE_GRID
			var z := -WorldTerrain.HALF + (gz + rng.randf()) * TREE_GRID
			var f := t.forest(x, z)
			var chance := smoothstep(0.12, 0.32, f) * 0.8 + 0.012
			var roll := rng.randf()
			if roll > chance:
				continue
			var h := t.height_at(x, z)
			if h > 285.0 or t.slope_at(x, z) > 0.5:
				continue
			if h > 200.0 and rng.randf() < smoothstep(200.0, 285.0, h):
				continue
			var i := WorldTerrain.index_of(x, z)
			var k := t.road_k[i]
			if k != 0 and t.road_d[i] < (11.0 if k == 1 else 7.5):
				continue
			if WorldTerrain.home_mask(x, z) < 0.35 or _is_taken(taken, x, z):
				continue
			var in_field := false
			for at: Vector2 in farms:
				if WorldTerrain.field_at(x, z, at) >= 0:
					in_field = true
			if in_field:
				continue
			var pine := h > 110.0 or t.forest(x * 0.3 + 77.0, z * 0.3) > 0.1
			var s := rng.randf_range(0.75, 1.35)
			var tint := Color.from_hsv(rng.randf_range(0.31, 0.38), rng.randf_range(0.45, 0.6), rng.randf_range(0.25, 0.36)) if pine \
				else Color.from_hsv(rng.randf_range(0.2, 0.29), rng.randf_range(0.5, 0.7), rng.randf_range(0.33, 0.5))
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, h - 0.2, z))
			p["trees"].append([xf, 0 if pine else 1, tint])


# ---------------------------------------------------------------------------- building it

func build(world: World, data: Dictionary) -> void:
	_world = world
	var p: Dictionary = data["props"]
	_build_trees(p["trees"])
	_build_rocks(p["rocks"], "Rocks", false)
	_build_rocks(p["track_rocks"], "TrackRocks", true)
	_build_buildings(p["buildings"])
	_build_fences(p["fences"])
	_build_armco(p["armco"])
	_build_chevrons(p["chevrons"])
	_build_signs(p["signs"])
	_build_bales(p["bales"])
	_build_lamps(p["lamps"])
	for body in _bodies:
		add_child(body)


## A static body for props' collision, tagged with `surface` for the tyres. It joins the
## scene once all its shapes are on it (see build), so the physics builds it just once.
func _body(body_name: String, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.set_meta("surface", surface)
	body.collision_layer = 1
	_bodies.append(body)
	return body


## Adds `shape` at `xf` to `body` straight on the physics server (no node per shape).
func _add_shape(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> void:
	PhysicsServer3D.body_add_shape(body.get_rid(), shape.get_rid(), xf)
	_shapes.append(shape)


## MultiMeshes of `mesh` at `xfs` (with `tints`, or none), one per CELL square, drawn out to
## `reach` metres times the draw distance.
func _scatter(node_name: String, mesh: Mesh, xfs: Array, tints: Array, reach: float, shadows := true) -> void:
	var cells := {}
	for i in xfs.size():
		var o: Vector3 = (xfs[i] as Transform3D).origin
		var key := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	var holder := Node3D.new()
	holder.name = node_name
	add_child(holder)
	for key in cells:
		var list: Array = cells[key]
		var center := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not tints.is_empty()
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			var xf: Transform3D = xfs[list[k]]
			mm.set_instance_transform(k, Transform3D(xf.basis, xf.origin - center))
			if mm.use_colors:
				mm.set_instance_color(k, tints[list[k]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = center
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
		_world.ranged(mmi, reach)


func _mat(key: String, color: Color, rough := 0.9, tinted := false) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.vertex_color_use_as_albedo = tinted
	_mats[key] = m
	return m


func _build_trees(trees: Array) -> void:
	var pines := []
	var pine_tints := []
	var oaks := []
	var oak_tints := []
	var body := _body("Trees", "grass")
	var trunks := {}
	for tr in trees:
		var xf: Transform3D = tr[0]
		var s := xf.basis.get_scale().x
		if int(tr[1]) == 0:
			pines.append(xf)
			pine_tints.append(tr[2])
		else:
			oaks.append(xf)
			oak_tints.append(tr[2])
		var bucket := snappedf(s, 0.1)
		if not trunks.has(bucket):
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.3 * bucket
			cyl.height = 4.0
			trunks[bucket] = cyl
		_add_shape(body, trunks[bucket], Transform3D(Basis(), xf.origin + Vector3.UP * 2.0))
	_scatter("Pines", _pine_mesh(), pines, pine_tints, TREE_RANGE)
	_scatter("Broadleaf", _broadleaf_mesh(), oaks, oak_tints, TREE_RANGE)


func _build_rocks(rocks: Array, node_name: String, convex: bool) -> void:
	var body := _body(node_name, "dirt")
	var by_variant := [[], [], []]
	var spheres := {}
	for rk in rocks:
		var xf: Transform3D = rk[0]
		by_variant[int(rk[1])].append(xf)
		if convex:
			var shape := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for v in _rock_points(int(rk[1])):
				pts.append(xf.basis * v)
			shape.points = pts
			_add_shape(body, shape, Transform3D(Basis(), xf.origin))
		else:
			var rad := snappedf(float(rk[2]) * 0.75, 0.25)
			if not spheres.has(rad):
				var sph := SphereShape3D.new()
				sph.radius = maxf(rad, 0.25)
				spheres[rad] = sph
			_add_shape(body, spheres[rad], Transform3D(Basis(), xf.origin + Vector3.UP * float(rk[2]) * 0.1))
	for v in 3:
		_scatter("%s%d" % [node_name, v], _rock_mesh(v), by_variant[v], [], ROCK_RANGE if not convex else SMALL_RANGE)


func _build_buildings(list: Array) -> void:
	var by_site := {}
	for b in list:
		var si: int = b["site"]
		if not by_site.has(si):
			by_site[si] = []
		by_site[si].append(b)
	var body := _body("Buildings", "tarmac")
	var walls_mat := _mat("walls", Color.WHITE, 0.9, true)
	var roof_mat := _mat("roofs", Color.WHITE, 0.75, true)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.14, 0.18)
	glass.roughness = 0.15
	glass.metallic = 0.3
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.8, 0.5)
	glass.emission_energy_multiplier = 0.05
	for si in by_site:
		var walls := SurfaceTool.new()
		var roofs := SurfaceTool.new()
		var windows := SurfaceTool.new()
		for st in [walls, roofs, windows]:
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var site: Dictionary = WorldLayout.sites()[si]
		var center := Vector3((site["at"] as Vector2).x, 0.0, (site["at"] as Vector2).y)
		for b in by_site[si]:
			var xf: Transform3D = b["xf"]
			var local := Transform3D(xf.basis, xf.origin - center)
			WorldBuildings.add(str(b["kind"]), local, b["size"], b["wall"], b["roof"], walls, roofs, windows)
			var size: Vector3 = b["size"]
			var box := BoxShape3D.new()
			var tall := size.y + 4.0 if b["kind"] in ["silo", "church"] else size.y
			box.size = Vector3(size.x, tall + 1.0, size.z)
			_add_shape(body, box, Transform3D(xf.basis, xf.origin + Vector3.UP * (tall * 0.5 - 0.5)))
		var holder := Node3D.new()
		holder.name = str(site["name"]).replace(" ", "")
		holder.position = center
		add_child(holder)
		for pair in [[walls, walls_mat, true], [roofs, roof_mat, true], [windows, glass, false]]:
			var st: SurfaceTool = pair[0]
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = pair[1]
			holder.add_child(mi)
			_world.ranged(mi, BUILDING_RANGE if pair[2] else 600.0)
			if not pair[2]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("night_emission", 2.5)
				mi.add_to_group(Daylight.NIGHT_LIGHTS)


func _build_fences(fences: Array) -> void:
	var posts := []
	var rails := []
	var body := _body("Fences", "grass")
	var panel := BoxShape3D.new()
	panel.size = Vector3(0.12, 1.2, 1.0)
	for f in fences:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var length := a.distance_to(b)
		var yaw := atan2(b.x - a.x, b.z - a.z)
		var basis := Basis(Vector3.UP, yaw)
		var tilt := atan2(b.y - a.y, Vector2(b.x - a.x, b.z - a.z).length())
		var n := ceili(length / 2.5)
		for k in n:
			posts.append(Transform3D(Basis(), a.lerp(b, float(k) / n)))
		for hgt: float in [0.45, 0.95]:
			var rail_basis := basis * Basis(Vector3.RIGHT, -tilt)
			rails.append(Transform3D(rail_basis.scaled(Vector3(1.0, 1.0, length)), (a + b) * 0.5 + Vector3.UP * hgt))
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.12, 1.2, length)
		_add_shape(body, shape, Transform3D(basis * Basis(Vector3.RIGHT, -tilt), (a + b) * 0.5 + Vector3.UP * 0.6))
	var wood := _mat("wood", Color(0.42, 0.32, 0.22))
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 1.2, 0.12)
	post_mesh.material = wood
	var post_shifted := _shifted(post_mesh, Vector3(0.0, 0.5, 0.0))
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.05, 0.1, 1.0)
	rail_mesh.material = wood
	_scatter("FencePosts", post_shifted, posts, [], SMALL_RANGE, false)
	_scatter("FenceRails", rail_mesh, rails, [], SMALL_RANGE, false)


## Galvanised barriers: a rail between each pair of points and a post at each.
func _build_armco(segs: Array) -> void:
	var rails := []
	var posts := []
	var body := _body("Barriers", "metal")
	for sgm in segs:
		var a: Vector3 = sgm[0]
		var b: Vector3 = sgm[1]
		var length := a.distance_to(b)
		var flat := Vector2(b.x - a.x, b.z - a.z)
		var yaw := atan2(flat.x, flat.y)
		var tilt := atan2(b.y - a.y, flat.length())
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt)
		rails.append(Transform3D(basis.scaled(Vector3(1.0, 1.0, length + 0.35)), (a + b) * 0.5 + Vector3.UP * 0.55))   # overlapping, so a bend has no gaps
		posts.append(Transform3D(Basis(Vector3.UP, yaw), a))
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.25, 0.9, length + 0.1)
		_add_shape(body, shape, Transform3D(basis, (a + b) * 0.5 + Vector3.UP * 0.45))
	var steel := _mat("armco", Color(0.72, 0.74, 0.76), 0.35)
	steel.metallic = 0.7
	var rail := BoxMesh.new()
	rail.size = Vector3(0.08, 0.32, 1.0)
	rail.material = steel
	var post := BoxMesh.new()
	post.size = Vector3(0.1, 0.75, 0.12)
	post.material = _mat("armco_post", Color(0.5, 0.52, 0.55), 0.6)
	_scatter("ArmcoRails", rail, rails, [], SMALL_RANGE * 1.5)
	_scatter("ArmcoPosts", _shifted(post, Vector3(0.0, 0.37, 0.0)), posts, [], SMALL_RANGE)


## Black and yellow chevron boards on two posts, pointing round the bend.
func _build_chevrons(xfs: Array) -> void:
	for xf in xfs:
		var root := Node3D.new()
		root.transform = xf
		add_child(root)
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.6, 0.05)
		board.mesh = bm
		board.material_override = _mat("chevron", Color(0.95, 0.78, 0.1), 0.6)
		board.position = Vector3(0.0, 1.3, 0.0)
		root.add_child(board)
		for side: float in [-0.6, 0.6]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.08, 1.0, 0.08)
			post.mesh = pm
			post.material_override = _mat("sign_post", Color(0.55, 0.56, 0.58), 0.6)
			post.position = Vector3(side, 0.5, 0.0)
			root.add_child(post)
		for face: float in [1.0, -1.0]:
			var l := Label3D.new()
			l.text = "> > >"
			l.font_size = 72
			l.pixel_size = 0.01
			l.modulate = Color(0.05, 0.05, 0.05)
			l.outline_size = 0
			l.position = Vector3(0.0, 1.3, 0.03 * face)
			l.rotation.y = 0.0 if face > 0.0 else PI
			root.add_child(l)
			l.visibility_range_end = SMALL_RANGE
		board.visibility_range_end = SMALL_RANGE * 1.5


## Fingerposts and village and farm name signs.
func _build_signs(signs: Array) -> void:
	for sg in signs:
		var root := Node3D.new()
		root.transform = sg["xf"]
		add_child(root)
		var style: String = sg["style"]
		var text: String = "\n".join(sg["lines"])
		var board_col := Color(0.95, 0.95, 0.92)
		var text_col := Color(0.05, 0.05, 0.05)
		var width := 0.25 + text.length() * 0.13
		var y := 2.0
		if style == "village":
			board_col = Color(0.92, 0.92, 0.9)
			width = 0.6 + text.length() * 0.22
			y = 1.5
		elif style == "farm":
			board_col = Color(0.15, 0.3, 0.18)
			text_col = Color(0.95, 0.95, 0.9)
			y = 1.3
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.1, y + 0.3, 0.1)
		post.mesh = pm
		post.material_override = _mat("sign_post", Color(0.55, 0.56, 0.58), 0.6)
		post.position = Vector3(0.0, (y + 0.3) * 0.5, 0.0)
		root.add_child(post)
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, 0.42 if style != "village" else 0.6, 0.04)
		board.mesh = bm
		board.material_override = _mat("board_" + style, board_col, 0.6)
		# A fingerpost's arm sticks out the way it points (towards the road it names).
		board.position = Vector3(width * 0.5 - 0.1 if style == "finger" else 0.0, y, 0.0)
		root.add_child(board)
		board.visibility_range_end = SMALL_RANGE
		post.visibility_range_end = SMALL_RANGE
		for face: float in [1.0, -1.0]:
			var l := Label3D.new()
			l.text = text
			l.font_size = 48 if style != "village" else 72
			l.pixel_size = 0.0055
			l.modulate = text_col
			l.outline_size = 0
			l.position = board.position + Vector3(0.0, 0.0, 0.025 * face)
			l.rotation.y = 0.0 if face > 0.0 else PI
			l.visibility_range_end = 120.0
			root.add_child(l)


func _build_bales(xfs: Array) -> void:
	var body := _body("Bales", "grass")
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.75
	cyl.height = 1.2
	var lying := []
	for xf in xfs:
		var on_side := Transform3D(xf.basis * Basis(Vector3.FORWARD, PI * 0.5), xf.origin + Vector3.UP * 0.72)
		lying.append(on_side)
		_add_shape(body, cyl, on_side)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.75
	mesh.bottom_radius = 0.75
	mesh.height = 1.2
	mesh.radial_segments = 14
	mesh.material = _mat("hay", Color(0.78, 0.66, 0.36))
	_scatter("HayBales", mesh, lying, [], SMALL_RANGE * 1.5)


## Street lamps in the villages that come on at dusk.
func _build_lamps(spots: Array) -> void:
	var pole_mat := _mat("lamp_pole", Color(0.25, 0.27, 0.3), 0.5)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.9, 0.88, 0.8)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.8, 0.5)
	head_mat.emission_energy_multiplier = 0.05
	for at in spots:
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.09
		cm.height = 5.5
		cm.radial_segments = 6
		pole.mesh = cm
		pole.material_override = pole_mat
		pole.position = at + Vector3.UP * 2.75
		pole.visibility_range_end = 500.0
		add_child(pole)
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.35, 0.18, 0.35)
		head.mesh = hm
		head.material_override = head_mat
		head.position = at + Vector3.UP * 5.55
		head.set_meta("night_emission", 4.0)
		head.add_to_group(Daylight.NIGHT_LIGHTS)
		head.visibility_range_end = 900.0
		add_child(head)
		var light := OmniLight3D.new()
		light.position = at + Vector3.UP * 5.3
		light.omni_range = 16.0
		light.light_color = Color(1.0, 0.82, 0.55)
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 180.0
		light.distance_fade_length = 40.0
		light.visible = false
		light.set_meta("night_energy", 2.2)
		light.add_to_group(Daylight.NIGHT_LIGHTS)
		add_child(light)


# ---------------------------------------------------------------------------- meshes

## `mesh` with its vertices moved by `offset` (a box resting on its base, say).
static func _shifted(mesh: PrimitiveMesh, offset: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += offset
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mesh.material)
	return out


## A pine: a trunk and three stacked cones of needles (tinted per tree), about 11 m tall.
func _pine_mesh() -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	WorldBuildings.cylinder(trunk, Transform3D(Basis(), Vector3.ZERO), 0.26, 0.16, 3.2, 7, Color(0.33, 0.24, 0.17), false)
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var base := 2.2 + k * 2.6
		WorldBuildings.cylinder(crown, Transform3D(Basis(), Vector3.UP * base), 2.6 - k * 0.65, 0.05, 4.2 - k * 0.5, 9, Color.WHITE, true)
	var mesh := trunk.commit()
	crown.commit(mesh)
	mesh.surface_set_material(0, _mat("bark", Color(0.33, 0.24, 0.17)))
	var needles := _mat("needles", Color.WHITE, 0.85, true)
	mesh.surface_set_material(1, needles)
	return mesh


## A broadleaf tree: a trunk and a lumpy round crown, about 9 m tall.
func _broadleaf_mesh() -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	WorldBuildings.cylinder(trunk, Transform3D(Basis(), Vector3.ZERO), 0.32, 0.22, 4.0, 7, Color(0.36, 0.28, 0.2), false)
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	WorldBuildings.blob(crown, Vector3(0.0, 6.0, 0.0), Vector3(3.4, 2.9, 3.4), 0)
	WorldBuildings.blob(crown, Vector3(1.3, 7.4, 0.6), Vector3(2.2, 2.0, 2.2), 1)
	WorldBuildings.blob(crown, Vector3(-1.1, 7.1, -0.9), Vector3(2.0, 1.9, 2.0), 2)
	var mesh := trunk.commit()
	crown.commit(mesh)
	mesh.surface_set_material(0, _mat("bark", Color(0.33, 0.24, 0.17)))
	mesh.surface_set_material(1, _mat("leaves", Color.WHITE, 0.8, true))
	return mesh


## A boulder: a lumpy ball, one of three shapes.
func _rock_mesh(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	WorldBuildings.blob(st, Vector3.ZERO, Vector3.ONE, 10 + variant, 0.35)
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat("rock", Color(0.48, 0.46, 0.43), 0.95))
	return mesh


## The corners of rock `variant`'s shape, for its collision.
static func _rock_points(variant: int) -> PackedVector3Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	WorldBuildings.blob(st, Vector3.ZERO, Vector3.ONE, 10 + variant, 0.35)
	var arrays := st.commit_to_arrays()
	return arrays[Mesh.ARRAY_VERTEX]
