class_name HomePlots
extends RefCounted
## Where the crew's houses stand (Simon: "They are stored at a big house (of varying styles) with
## 4 garages and a large pea shingle courtyard in the front ... Houses should be no more than 1km
## from the shed"). One plot for every player a co-op shed can hold, each beside one of the map's
## tarmac roads within a kilometre of the shed, clear of the roads, the town, the yard, the
## villages and the farms (tests/collection_tests.gd checks it). Which player lives where, and in
## what style of house, is kept in Shed.homes (see Collection).
##
## A plot's own frame: its origin is the middle of the courtyard's display ring, +z points out
## through the gate to the road and -z back to the house; x runs across it. Laid out in it:
##   the house along the back (HOUSE), its garage block of four doors to the right (GARAGE,
##   DOOR_X), the pea shingle courtyard in front of both (COURTYARD) with the ring of the
##   collection's bikes in the middle of it (RING_R, facing in, an information stand in front of
##   each), a low wall along the front with the gate on the right (GATE_X), and the drive out
##   through it to the road.
## The ground under each plot is levelled to the road's height at its gate as the land is made
## (see level_ground), so the courtyard is flat and the drive meets the road without a step.

## Each plot: the middle of its display ring (x, z on the map) and which way its gate faces.
const PLOTS: Array[Dictionary] = [
	{"at": Vector2(88.3, -105.8), "yaw": -2.908},
	{"at": Vector2(185.0, 139.2), "yaw": 2.149},
	{"at": Vector2(-211.8, -46.0), "yaw": 1.801},
	{"at": Vector2(324.6, -14.4), "yaw": 2.736},
	{"at": Vector2(237.4, 401.4), "yaw": 1.450},
	{"at": Vector2(158.0, -339.2), "yaw": -3.133},
	{"at": Vector2(-522.6, 130.3), "yaw": -2.794},
	{"at": Vector2(-223.0, -456.5), "yaw": 2.275},
]
## The shed (its roller door), for how far a house is from it.
const SHED := Vector2(0.0, 70.0)
const MAX_FROM_SHED := 1000.0
## The architectural styles a house is built in (HomesView draws them).
const STYLES: Array[String] = ["victorian", "modern", "georgian", "farmhouse"]
const STYLE_NAMES := {"victorian": "Victorian brick villa", "modern": "Modern rendered house",
	"georgian": "Georgian stone house", "farmhouse": "Stone farmhouse"}

## The whole plot, in its frame (x across, y is z from the house's back to the front wall).
const RECT := Rect2(-19.0, -26.0, 38.0, 38.0)
## The house (main block) and its garage block, as x/z rectangles, and how tall their walls are.
const HOUSE := Rect2(-18.0, -25.0, 19.0, 11.0)
const GARAGE := Rect2(2.0, -22.0, 16.0, 8.0)
const HOUSE_WALL := 6.4
const GARAGE_WALL := 3.2
## Where each of the four garage doors is along the garage block's front (x), and how big.
const DOOR_X: Array[float] = [4.0, 7.7, 11.4, 15.1]
const DOOR_SIZE := Vector2(2.8, 2.35)
## The pea shingle courtyard in front of the house and garages.
const COURTYARD := Rect2(-19.0, -14.0, 38.0, 26.0)
## The display ring: how far out the bikes stand from its middle, and how many places it has.
const RING_R := 7.2
const RING_SPOTS := 20
## How far in from its bike each information stand is.
const STAND_IN := 1.75
## The gate in the front wall (x), and how far the drive runs out past the wall to the road.
const GATE_X := Vector2(8.5, 15.5)
const DRIVE_TO := 17.6
## Where a bike taken out of the collection is left to ride away: in front of the second garage
## door, facing the gate.
const PICKUP := Vector3(7.7, 0.0, -11.4)
## The gravel sits this much above the plot's level (the road's surface at the gate).
const GRAVEL_LIFT := 0.03

## The height of each plot's level (the road's surface at its gate), set as the land is made
## (see level_ground). 0 until then.
static var levels := PackedFloat32Array()


## The plot's frame on the map: its origin in the middle of the display ring at the level of the
## courtyard, +z out towards the road.
static func frame(plot: int) -> Transform3D:
	var p: Dictionary = PLOTS[clampi(plot, 0, PLOTS.size() - 1)]
	var at: Vector2 = p["at"]
	return Transform3D(Basis(Vector3.UP, float(p["yaw"])), Vector3(at.x, level(plot) + GRAVEL_LIFT, at.y))


static func level(plot: int) -> float:
	return levels[plot] if plot >= 0 and plot < levels.size() else 0.0


## A point in plot `plot`'s frame (x, z), on the map (x, z).
static func to_map(plot: int, local: Vector2) -> Vector2:
	var p := frame(plot) * Vector3(local.x, 0.0, local.y)
	return Vector2(p.x, p.z)


## A map point in plot `plot`'s frame (x, z).
static func to_local(plot: int, at: Vector3) -> Vector2:
	var p := frame(plot).affine_inverse() * at
	return Vector2(p.x, p.z)


## How far (metres) the middle of a plot is from the shed.
static func from_shed(plot: int) -> float:
	return (PLOTS[plot]["at"] as Vector2).distance_to(SHED)


## The place in the display ring for bike `spot` (0..RING_SPOTS-1): on the ring, facing in
## (a bike's forward is its -z), as a map transform. Spot 0 is at the front, by the gate.
static func ring_xf(plot: int, spot: int) -> Transform3D:
	var a := TAU * float(spot) / float(RING_SPOTS)
	var local := Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0.0, cos(a)) * RING_R)
	return frame(plot) * local


## Spot `spot`'s information stand: STAND_IN in from its bike, its board facing the middle of
## the ring (its +z), where people stand to read it.
static func stand_xf(plot: int, spot: int) -> Transform3D:
	var a := TAU * float(spot) / float(RING_SPOTS)
	var local := Transform3D(Basis(Vector3.UP, a + PI), Vector3(sin(a), 0.0, cos(a)) * (RING_R - STAND_IN))
	return frame(plot) * local


## Where a bike taken out of the collection is left, ready to ride out through the gate.
static func pickup_xf(plot: int) -> Transform3D:
	return frame(plot) * Transform3D(Basis(Vector3.UP, PI), PICKUP)


## The gate, in the middle of the opening in the front wall.
static func gate(plot: int) -> Vector3:
	return frame(plot) * Vector3((GATE_X.x + GATE_X.y) * 0.5, 0.0, COURTYARD.end.y)


## Whether `at` (on the map) is in plot `plot`'s courtyard or its drive, and not too far above
## or below it (so a bridge or a hill over it doesn't count).
static func in_courtyard(plot: int, at: Vector3) -> bool:
	if plot < 0 or plot >= PLOTS.size():
		return false
	var local := frame(plot).affine_inverse() * at
	if absf(local.y) > 2.5:
		return false
	var p := Vector2(local.x, local.z)
	return COURTYARD.grow(0.5).has_point(p) or Rect2(GATE_X.x, COURTYARD.end.y, GATE_X.y - GATE_X.x, DRIVE_TO - COURTYARD.end.y).has_point(p)


## The plot whose courtyard `at` is in, or -1.
static func plot_at(at: Vector3) -> int:
	for i in PLOTS.size():
		if in_courtyard(i, at):
			return i
	return -1


## The style of house player `player_name` lives in (the same in every shed: from their name).
static func style_for(player_name: String) -> String:
	return STYLES[absi(hash(player_name.strip_edges().to_lower() + "|house")) % STYLES.size()]


## The plot player `player_name` would like (the same in every shed); Collection takes the next
## free one round from it.
static func preferred_plot(player_name: String) -> int:
	return absi(hash(player_name.strip_edges().to_lower() + "|plot")) % PLOTS.size()


# ---------------------------------------------------------------------------- the land under them

## While the land is made (WorldTerrain.build): each plot's level is the road's surface at its
## gate, and the ground under it is levelled just under that, blending back into the land round
## it, before the roads cut in. Then (`again`, once they have) the plot itself is levelled once
## more, so a road's banking near the front doesn't tilt it (the plots are clear of the roads
## themselves, see test_plots); the road's ground round it is left be.
## Returns the levels (see `levels`).
static func level_ground(t: WorldTerrain, roads: WorldRoads, again := false) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(PLOTS.size())
	var yard := Rect2(WorldYard.CENTER - WorldYard.HALF, WorldYard.HALF * 2.0).grow(2.0)
	for i in PLOTS.size():
		var p: Dictionary = PLOTS[i]
		var at: Vector2 = p["at"]
		var b := Basis(Vector3.UP, float(p["yaw"]))
		var y := 0.0
		if again and i < levels.size():
			y = levels[i]
		else:
			var g3: Vector3 = b * Vector3((GATE_X.x + GATE_X.y) * 0.5, 0.0, DRIVE_TO + 3.0)
			var near := roads.nearest(at.x + g3.x, at.y + g3.z, 30.0)
			y = float(near["h"]) if not near.is_empty() else t.natural(at.x, at.y)
		out[i] = y
		var ground := y - 0.1
		var inv := b.inverse()
		var reach := 5.0 if again else 24.0
		var r := RECT.grow(1.0 if again else 2.0)
		var rad := Vector2(maxf(absf(r.position.x), absf(r.end.x)), maxf(absf(r.position.y), absf(r.end.y))).length() + reach
		var box := WorldTerrain._grid_box(Rect2(at - Vector2(rad, rad), Vector2(rad, rad) * 2.0))
		for gz in range(box.position.y, box.end.y):
			for gx in range(box.position.x, box.end.x):
				var wx := gx * WorldTerrain.SPACING - WorldTerrain.HALF
				var wz := gz * WorldTerrain.SPACING - WorldTerrain.HALF
				var lp: Vector3 = inv * Vector3(wx - at.x, 0.0, wz - at.y)
				var dx := maxf(maxf(r.position.x - lp.x, lp.x - r.end.x), 0.0)
				var dz := maxf(maxf(r.position.y - lp.z, lp.z - r.end.y), 0.0)
				var d := Vector2(dx, dz).length()
				if d >= reach:
					continue
				var k := gz * WorldTerrain.SIZE + gx
				if again and d > 0.0 and t.road_w[k] > 0.9:
					continue   # the road's own banking, just off the plot
				# The shed's yard stays flat to its edges (it meets the land without a kerb).
				var yd := Vector2(maxf(maxf(yard.position.x - wx, wx - yard.end.x), 0.0), maxf(maxf(yard.position.y - wz, wz - yard.end.y), 0.0)).length()
				var wgt := (1.0 - smoothstep(0.0, reach, d)) * smoothstep(0.0, 16.0, yd)
				t.heights[k] = lerpf(t.heights[k], ground, wgt)
	levels = out
	return out


## The plot's footprint on the map, as its four corners (for keeping other things off it).
static func corners(plot: int, grow := 0.0) -> Array[Vector2]:
	var r := RECT.grow(grow)
	var out: Array[Vector2] = []
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var p: Dictionary = PLOTS[plot]
		var o: Vector3 = Basis(Vector3.UP, float(p["yaw"])) * Vector3(c.x, 0.0, c.y)
		out.append((p["at"] as Vector2) + Vector2(o.x, o.z))
	return out


## Whether map point (x, z) is on a plot (grown by `grow` metres all round).
static func on_plot(x: float, z: float, grow := 0.0) -> bool:
	for i in PLOTS.size():
		var p: Dictionary = PLOTS[i]
		var at: Vector2 = p["at"]
		if at.distance_to(Vector2(x, z)) > 33.0 + grow:
			continue
		var lp: Vector3 = Basis(Vector3.UP, float(p["yaw"])).inverse() * Vector3(x - at.x, 0.0, z - at.y)
		if RECT.grow(grow).has_point(Vector2(lp.x, lp.z)):
			return true
	return false
