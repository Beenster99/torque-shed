class_name StaffNav
extends RefCounted
## How the garage's staff (see Staff) find their way about: a small graph of walkways through the
## shed, the extension, the paint shop and mixing bay, the yard, the wash bay, the sales office and
## the cafe next door, joined at the doorways. Every place a worker goes (a bike, the parts
## computer, a booth hook, the cafe counter...) hangs off one of its nodes by a short approach.
## A walk is back out of the place they're at, the shortest way along the graph, and in to the
## next place: plain points every machine works out the same, so each game draws them walking the
## same way (see StaffView), and the host knows where they are without sending it.
##
## A place is {n: its node, p: [points out from the node, the last where they stand], yaw: which
## way they face there (no yaw: the way they walked in)}, plain data kept in Shed.staff.

const WALK_SPEED := 1.35        # m/s on foot
const PUSH_SPEED := 0.95        # wheeling a bike
const BIKE_AHEAD := 1.05        # how far ahead of them a bike they're wheeling stands
const CART_AHEAD := 0.85        # and a trolley's middle, pushed by its handle
## Room kept between a walk cut straight (see pull) and anything in the way: on foot, and
## wheeling a bike or a trolley.
const CLEAR := 0.35
const PUSH_CLEAR := 0.55
## Rooms a walk can cut straight across between two points in the same one ("" is outside).
const OPEN_ROOMS: Array[String] = ["shed", "paint", "storage", "mixing", "wash", "annex", ""]
## How far off the delivery area's lines a walk cut straight keeps (boxes stand right up to them).
const DELIVERY_CLEAR := 0.45
## The middle of the aisle between the delivery floor and its racking.
const AISLE_Z := 76.15
## A parked bike's half size (across, along) for keeping clear of it.
const BIKE_HALF := Vector2(0.32, 1.05)
## Fixed things on the floor that aren't equipment: the workbench, the parts computer's desk and
## the bins by the roller door (x/z rectangles).
const FIXED_BOXES: Array[Rect2] = [Rect2(-6.5, 63.2, 0.95, 4.85), Rect2(5.65, 66.25, 0.8, 1.35), Rect2(-4.2, 69.85, 1.75, 0.65)]

## The walkways' corners (x, z on the floor).
const NODES := {
	"shed": Vector2(0.0, 65.5), "shed_w": Vector2(-4.0, 65.3), "shed_e": Vector2(4.0, 65.6),
	"shed_ne": Vector2(5.85, 63.3), "shed_door": Vector2(0.0, 69.0), "paint_gap": Vector2(5.8, 68.45),
	"wing_door": Vector2(5.75, 60.0), "wing": Vector2(5.75, 58.2), "wing_mid": Vector2(8.6, 55.6),
	"paint": Vector2(7.7, 68.45), "paint_front": Vector2(8.4, 69.6), "mix_door": Vector2(13.6, 69.6),
	"mix": Vector2(15.25, 69.1),
	"yard": Vector2(0.0, 72.2), "yard_aisle": Vector2(1.7, 76.1), "yard_s": Vector2(1.6, 78.6),
	"yard_se": Vector2(14.0, 78.6), "sales_front": Vector2(24.5, 78.2), "sales_door": Vector2(24.5, 70.4),
	"sales": Vector2(24.5, 67.4), "sales_desk": Vector2(22.6, 65.3),
	"yard_sw": Vector2(-6.5, 72.3), "wash_front": Vector2(-9.3, 70.6), "yard_w": Vector2(-16.5, 74.7),
	"cafe_aisle": Vector2(-25.25, 74.7), "cafe_walk": Vector2(-25.25, 70.5), "cafe_door": Vector2(-25.25, 63.6),
	"cafe": Vector2(-24.7, 62.2),
	"shed_nw": Vector2(-5.85, 62.95), "store_door": Vector2(-5.95, 60.5), "store": Vector2(-7.7, 60.5),
	"annex_door": Vector2(GarageUpgrades.ANNEX_DOOR_X, 55.0), "annex": Vector2(GarageUpgrades.ANNEX_DOOR_X, 51.0),
	"dyno_door": Vector2(0.0, 60.4), "dyno": Vector2(0.0, 57.4),
}
const EDGES := [["shed", "shed_w"], ["shed", "shed_e"], ["shed", "shed_door"], ["shed_w", "shed_door"],
	["shed_e", "shed_door"], ["shed_e", "paint_gap"], ["shed_door", "paint_gap"], ["shed_e", "shed_ne"],
	["shed_ne", "wing_door"], ["wing_door", "wing"], ["wing", "wing_mid"],
	["paint_gap", "paint"], ["paint", "paint_front"], ["paint_front", "mix_door"], ["mix_door", "mix"],
	["shed_door", "yard"], ["yard", "yard_aisle"], ["yard_aisle", "yard_s"], ["yard", "yard_s"], ["yard_s", "yard_se"],
	["yard_se", "sales_front"], ["sales_front", "sales_door"], ["sales_door", "sales"], ["sales", "sales_desk"],
	["yard", "yard_sw"], ["yard_sw", "wash_front"], ["yard_sw", "yard_w"], ["yard_w", "cafe_aisle"],
	["cafe_aisle", "cafe_walk"], ["cafe_walk", "cafe_door"], ["cafe_door", "cafe"],
	["shed_w", "shed_nw"], ["shed_nw", "store_door"], ["store_door", "store"],
	["store", "annex_door"], ["annex_door", "annex"], ["shed", "dyno_door"], ["dyno_door", "dyno"]]
## Corners in rooms the garage builds on (GarageUpgrades): only walked once it has them.
const NODE_NEEDS := {"wing_door": "wing", "wing": "wing", "wing_mid": "wing", "annex_door": "annex", "annex": "annex"}
## How high off the floor they reach for a part (the tallest racking's top board, not a
## mezzanine or an upstairs room).
const REACH_HIGH := 2.6

## Where the staff wait about between jobs, by role (a spot each, a little apart).
const IDLE := {"mechanic": Vector2(-4.6, 64.6), "expert": Vector2(-4.6, 66.3), "paint": Vector2(7.6, 66.8),
	"detailer": Vector2(-7.6, 69.2), "sales": Vector2(25.6, 65.6), "reception": Vector2(21.1, 63.5)}

static var _adj := {}


static func _v(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## The neighbours of each node, worked out once.
static func _graph() -> Dictionary:
	if _adj.is_empty():
		for n in NODES:
			_adj[n] = []
		for e in EDGES:
			(_adj[e[0]] as Array).append(e[1])
			(_adj[e[1]] as Array).append(e[0])
	return _adj


## A place: off `node` along `pts` (Vector3s, the last where they stand), facing `yaw`.
static func place(node: String, pts: Array, yaw := NAN) -> Dictionary:
	var out := []
	for p in pts:
		out.append(Vector3(p.x, 0.0, p.z))
	var pl := {"n": node if NODES.has(node) else "shed", "p": out}
	if not is_nan(yaw):
		pl["yaw"] = yaw
	return pl


## Where a place has them stand.
static func spot(pl: Dictionary) -> Vector3:
	var pts: Array = pl.get("p", [])
	if pts.is_empty():
		return _v(NODES.get(str(pl.get("n", "shed")), NODES["shed"]))
	return pts[pts.size() - 1]


## Whether corner `n` is there to walk through (its room's built).
static func is_open(n: String) -> bool:
	return NODES.has(n) and (not NODE_NEEDS.has(n) or Shed.upgrades.has(NODE_NEEDS[n]))


## The node nearest `at` that they can walk straight to from it: one in the same room (or, out in
## the open, one with no building in between), so a walk never cuts through a wall to get there.
## Only when there's none, the nearest of all.
static func nearest_node(at: Vector3, only: Array = []) -> String:
	var rooms := _walls()
	var room := _room(at, rooms)
	var q := Vector2(at.x, at.z)
	var best := ""
	var d := INF
	var any := "shed"
	var d_any := INF
	for n in NODES:
		if (not only.is_empty() and not only.has(n)) or not is_open(n):
			continue
		var p: Vector2 = NODES[n]
		var dd := p.distance_squared_to(q)
		if dd < d_any:
			d_any = dd
			any = n
		if dd < d and _room(_v(p), rooms) == room and (room != "" or not _crosses_building(q, p, rooms)):
			d = dd
			best = n
	return best if best != "" else any


## Whether they can walk to `at` at all: on the floor round the garage (in a room the walkways
## reach, or outside nearby) and within reach of it, not upstairs or out on the roads.
static func reachable(at: Vector3) -> bool:
	if not Shed.in_work_area(at) or at.y > REACH_HIGH:
		return false
	return Workshop.room_at(at) in ["", "shed", "paint", "storage", "mixing", "dyno", "sales", "cafe", "wing", "annex"]


## The nodes of the shortest way from node `a` to node `b`, both ends included.
static func node_path(a: String, b: String) -> Array:
	var g := _graph()
	if not g.has(a) or not g.has(b):
		return [a, b]
	if a == b:
		return [a]
	var dist := {a: 0.0}
	var prev := {}
	var open := [a]
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[best]]):
				best = i
		var u: String = open[best]
		open.remove_at(best)
		if u == b:
			break
		for v in g[u]:
			if not is_open(v) and v != b:
				continue
			var nd := float(dist[u]) + (NODES[u] as Vector2).distance_to(NODES[v])
			if not dist.has(v) or nd < float(dist[v]):
				dist[v] = nd
				prev[v] = u
				if not open.has(v):
					open.append(v)
	if not prev.has(b):
		return [a, b]
	var out := [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out


## The walk from `from` (the place they're at, standing at `pos`) to the place `to`: back out of
## the one, along the graph and in to the other, then pulled straight (see pull): any corner
## they can see past is cut, so they don't wander out to the middle of the shed to cross it.
## Corners closer together than a few centimetres are merged. `ignore`: {bike, furniture} they're
## wheeling, which isn't in their way.
static func route(from: Dictionary, to: Dictionary, pos: Vector3, ignore := {}) -> PackedVector3Array:
	var pts := PackedVector3Array([Vector3(pos.x, 0.0, pos.z)])
	var back: Array = from.get("p", [])
	for i in range(back.size() - 2, -1, -1):
		_add(pts, back[i])
	for n in node_path(str(from.get("n", "shed")), str(to.get("n", "shed"))):
		_add(pts, _v(NODES[n]))
	for p in to.get("p", []):
		_add(pts, p)
	if pts.size() == 1:
		pts.append(pts[0])
		return pts
	return pull(pts, PUSH_CLEAR if not ignore.is_empty() else CLEAR, ignore)


# ---------------------------------------------------------------------------- straight lines

## A walk with every corner they can see past cut out: from each point, straight on to the
## furthest one further along that's in plain sight (the same room, or both out in the open, and
## nothing in the way with `clear` metres to spare). The start and end stay where they are.
static func pull(pts: PackedVector3Array, clear := CLEAR, ignore := {}) -> PackedVector3Array:
	if pts.size() <= 2:
		return pts
	var obs := obstacles(ignore)
	var rooms := _walls()
	var out := PackedVector3Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var next := i + 1
		for j in range(pts.size() - 1, i + 1, -1):
			if sees(pts[i], pts[j], obs, rooms, clear):
				next = j
				break
		out.append(pts[next])
		i = next
	return out


## Whether the straight line from `a` to `b` is a clear walk: both ends in the same open room
## (or both outside, crossing no building), and nothing in `obs` within `clear` of it.
static func sees(a: Vector3, b: Vector3, obs: Array, rooms: Dictionary, clear := CLEAR) -> bool:
	var ra := _room(a, rooms)
	if ra != _room(b, rooms) or not OPEN_ROOMS.has(ra):
		return false
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	if ra == "" and _crosses_building(a2, b2, rooms):
		return false
	for o in obs:
		if _hits_box(a2, b2, o[0], o[1] + Vector2(clear, clear), o[2], o[3], true):
			return false
	return true


## Whether the straight line from `a` to `b` (x/z) passes through a building.
static func _crosses_building(a: Vector2, b: Vector2, rooms: Dictionary) -> bool:
	for r in rooms.values():
		if _hits_box(a, b, (r as Rect2).get_center(), (r as Rect2).size * 0.5 + Vector2(0.25, 0.25), Vector2.RIGHT, Vector2.DOWN, false):
			return true
	return false


## Which room a point's in for walking straight across ("wash" for the wash bay lean-to, which
## has walls but no room of its own; "" outside).
static func _room(p: Vector3, rooms: Dictionary) -> String:
	var q := Vector2(p.x, p.z)
	for r in rooms:
		if (rooms[r] as Rect2).has_point(q):
			return str(r)
	return ""


## The rooms' floors, and the wash bay's, as x/z rectangles (the shed's upstairs rooms left out).
static func _walls() -> Dictionary:
	var out := Workshop.rooms()
	out.erase("sales_office")
	out.erase("lounge")
	out["wash"] = Rect2(Workshop.WASH_CENTER.x - Workshop.WASH_HALF.x, Workshop.WASH_CENTER.z - Workshop.WASH_HALF.y,
		Workshop.WASH_HALF.x * 2.0, Workshop.WASH_HALF.y * 2.0)
	return out


## What's in the way on the floor: [centre, half size, x axis, z axis] boxes for the bikes, the
## equipment standing about, the fixed workbench, parts computer and bins, and the delivery
## area's boxes (kept well clear of, with DELIVERY_CLEAR round its lines). `ignore` leaves out
## what they're wheeling.
static func obstacles(ignore := {}) -> Array:
	var out := []
	for id in Shed.bikes:
		var b: Dictionary = Shed.bikes[id]
		if int(id) == int(ignore.get("bike", 0)) or int(b.get("rider", 0)) != 0 or not (b.get("xf") is Transform3D):
			continue
		out.append(_box(b["xf"], BIKE_HALF))
	for id in Shed.furniture:
		var f: Dictionary = Shed.furniture[id]
		if int(id) == int(ignore.get("furniture", 0)) or int(f.get("mover", 0)) != 0 or not (f.get("xf") is Transform3D):
			continue
		if Equipment.WALL_KINDS.has(str(f.get("kind", ""))) or Equipment.is_wall(str(f.get("model", ""))):
			continue
		var size := Shed.furniture_size(f)
		out.append(_box(f["xf"], Vector2(size.x, size.z) * 0.5))
	for r in FIXED_BOXES:
		out.append([Vector2(r.get_center().x, r.get_center().y), r.size * 0.5, Vector2.RIGHT, Vector2.DOWN])
	var d: Rect2 = Shed.DELIVERY_FLOOR.grow(DELIVERY_CLEAR)
	out.append([d.get_center(), d.size * 0.5, Vector2.RIGHT, Vector2.DOWN])
	return out


static func _box(xf: Transform3D, half: Vector2) -> Array:
	var ax := Vector2(xf.basis.x.x, xf.basis.x.z)
	var az := Vector2(xf.basis.z.x, xf.basis.z.z)
	return [Vector2(xf.origin.x, xf.origin.z), half, ax.normalized() if ax.length() > 0.001 else Vector2.RIGHT,
		az.normalized() if az.length() > 0.001 else Vector2.DOWN]


## Whether segment a..b passes through a box (centre `c`, half size `h` along axes `ax`, `az`).
## With `skip_inside`, a box either end's already in doesn't count (they're stood at it).
static func _hits_box(a: Vector2, b: Vector2, c: Vector2, h: Vector2, ax: Vector2, az: Vector2, skip_inside: bool) -> bool:
	var la := Vector2((a - c).dot(ax), (a - c).dot(az))
	var lb := Vector2((b - c).dot(ax), (b - c).dot(az))
	var inside := func(p: Vector2) -> bool: return absf(p.x) <= h.x and absf(p.y) <= h.y
	if skip_inside and (inside.call(la) or inside.call(lb)):
		return false
	# Slabs: the part of the segment inside each pair of sides.
	var t0 := 0.0
	var t1 := 1.0
	var d := lb - la
	for k in 2:
		var p := la.x if k == 0 else la.y
		var dv := d.x if k == 0 else d.y
		var e := h.x if k == 0 else h.y
		if absf(dv) < 0.000001:
			if absf(p) > e:
				return false
			continue
		var ta := (-e - p) / dv
		var tb := (e - p) / dv
		if ta > tb:
			var s := ta
			ta = tb
			tb = s
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


static func _add(pts: PackedVector3Array, p: Vector3) -> void:
	var q := Vector3(p.x, 0.0, p.z)
	if pts.is_empty() or pts[pts.size() - 1].distance_to(q) > 0.05:
		pts.append(q)


## How long a walk is, in metres.
static func length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## The point `s` metres along a walk (its start before it, its end past it).
static func along(pts: PackedVector3Array, s: float) -> Vector3:
	if pts.is_empty():
		return Vector3.ZERO
	var left := s
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if left <= seg:
			return pts[i - 1].lerp(pts[i], left / seg) if seg > 0.0001 else pts[i]
		left -= seg
	return pts[pts.size() - 1]


## Which way someone faces `s` metres along a walk (yaw, -Z forward), or `fallback` on a walk
## that goes nowhere.
static func heading(pts: PackedVector3Array, s: float, fallback := 0.0) -> float:
	var left := s
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if left <= seg or i == pts.size() - 1:
			if seg < 0.0001:
				continue
			var d := pts[i] - pts[i - 1]
			return atan2(-d.x, -d.z)
		left -= seg
	return fallback


# ---------------------------------------------------------------------------- the places

## Standing in a bay (or nearly): which one, or -1.
static func bay_of(at: Vector3) -> int:
	for b in Workshop.bay_count():
		if Workshop.bay_transform(b).origin.distance_to(Vector3(at.x, 0.0, at.z)) < 0.6:
			return b
	return -1


## Beside a bike, facing it, to work on it: in its bay down the gap on its right, out in the
## yard (or anywhere else) at its side.
static func bike(bike_id: int) -> Dictionary:
	var b: Dictionary = Shed.bikes.get(bike_id, {})
	if b.is_empty():
		return idle("mechanic")
	var xf: Transform3D = b["xf"]
	var at := xf.origin
	var bay := bay_of(at)
	if bay >= 0 and bay < Workshop.BAY_COUNT:
		return place("shed", [Vector3(at.x + 0.95, 0.0, 63.9), Vector3(at.x + 0.95, 0.0, at.z + 0.1)], PI * 0.5)
	if bay >= Workshop.BAY_COUNT:
		return place("wing_mid", [Vector3(at.x + 0.95, 0.0, 55.0), Vector3(at.x + 0.95, 0.0, at.z + 0.1)], PI * 0.5)
	var side := at + xf.basis.x.normalized() * 0.95
	var yaw := atan2(xf.basis.x.x, xf.basis.x.z)   # facing back in at the bike
	return place(nearest_node(side), [side], yaw)


## Where a bike's wheeled from: the point in front of it they push it out to (its bay's mouth),
## and the node that joins.
static func bike_out(bike_id: int) -> Dictionary:
	var b: Dictionary = Shed.bikes.get(bike_id, {})
	if b.is_empty():
		return place("shed", [])
	var at: Vector3 = (b["xf"] as Transform3D).origin
	var bay := bay_of(at)
	if bay >= 0 and bay < Workshop.BAY_COUNT:
		return place("shed", [Vector3(at.x, 0.0, 64.4), at])
	if bay >= Workshop.BAY_COUNT:
		return place("wing_mid", [Vector3(at.x, 0.0, 55.2), at])
	return place(nearest_node(at), [at])


## Wheeling a bike into bay `bay` (in nose first; the paddock stand turns it round).
static func bay_in(bay: int) -> Dictionary:
	var at := Workshop.bay_transform(bay).origin
	if bay >= Workshop.BAY_COUNT:
		return place("wing_mid", [Vector3(at.x, 0.0, 55.2), at])
	return place("shed", [Vector3(at.x, 0.0, 64.4), at])


## The parts computer by the east wall, facing its screen.
static func computer() -> Dictionary:
	return place("shed_e", [Vector3(5.2, 0.0, 66.9)], -PI * 0.5)


## The workbench along the west wall.
static func bench(i := 1) -> Dictionary:
	return place("shed_w", [Vector3(-5.15, 0.0, 63.8 + 1.2 * clampi(i, 0, 3))], PI * 0.5)


## A machine's spot (a work place on it, see Shed.spot_transform): stood in front of it.
static func at_spot(spot: String) -> Dictionary:
	var xf := Shed.spot_transform(spot)
	var at := xf.origin
	match Shed.spot_role(spot):
		"bench":
			return place("shed_w", [Vector3(-5.15, 0.0, at.z)], PI * 0.5)
		"repair", "washer":
			return place("shed_door", [Vector3(at.x, 0.0, 68.85)], PI)
		"changer":
			return place("shed_w", [Vector3(-5.2, 0.0, at.z)], PI * 0.5)
		"booth":
			return place("paint", [Vector3(8.0, 0.0, at.z), Vector3(at.x - 0.85, 0.0, at.z)], -PI * 0.5)
		"stand":
			return place("shed_e", [Vector3(at.x - 0.85, 0.0, at.z)], -PI * 0.5)
	var p := Vector3(at.x, 0.0, at.z)
	return place(nearest_node(p), [p])


## Beside a part put down loose (on the floor, a bench top or a delivery box), facing it. Boxes
## in the delivery area are reached from the aisle behind them.
static func at_item(item_id: int) -> Dictionary:
	var it: Dictionary = Shed.items.get(item_id, {})
	if it.is_empty():
		return idle("mechanic")
	if it["at"] == "spot":
		var spot := str(it["ref"])
		if Shed.spot_role(spot) == "shelf":
			var s := StaffJobs.item_at(item_id)
			if Shed.DELIVERY_AREA.grow(0.6).has_point(Vector2(s.x, s.z)):
				return place("yard_aisle", [Vector3(s.x, 0.0, 76.2)], 0.0 if s.z < 76.2 else PI)
			return shelf_front(Shed.furniture_of_spot(spot), s)
		if Shed.surface_of_spot(spot) == "":
			return at_spot(spot)
	var at := StaffJobs.item_at(item_id)
	if Shed.DELIVERY_AREA.grow(0.6).has_point(Vector2(at.x, at.z)):
		# A box on the delivery floor: reached from whichever side's nearer, the front line or the
		# aisle behind, never stood in among the boxes.
		var front := Shed.DELIVERY_AREA.position.y - DELIVERY_CLEAR
		if at.z - front < AISLE_Z - at.z:
			return place("yard", [Vector3(at.x, 0.0, front)], PI)
		return place("yard_aisle", [Vector3(at.x, 0.0, AISLE_Z)], 0.0)
	if Shed.in_work_area(at) and Workshop.room_at(at) == "shed":
		var p := Vector3(clampf(at.x, -5.2, 5.0), 0.0, clampf(at.z + 0.6, 63.4, 68.8))
		var node := "shed_w" if p.x < -2.0 else ("shed_e" if p.x > 2.0 else "shed")
		return place(node, [p], atan2(-(at.x - p.x), -(at.z - p.z)) if p.distance_to(Vector3(at.x, 0.0, at.z)) > 0.1 else NAN)
	var q := Vector3(at.x, 0.0, at.z + 0.6)
	return place(nearest_node(q), [q], PI)


## Stood in front of a shelving unit (its +Z side, the side it's loaded from) level with point
## `s` on it, facing it.
static func shelf_front(f: Dictionary, s: Vector3) -> Dictionary:
	if not (f.get("xf") is Transform3D):
		var q := Vector3(s.x, 0.0, s.z)
		return place(nearest_node(q), [q])
	var xf: Transform3D = f["xf"]
	var size := Shed.furniture_size(f)
	var local := xf.affine_inverse() * s
	var stand := xf * Vector3(clampf(local.x, -size.x * 0.5, size.x * 0.5), 0.0, size.z * 0.5 + 0.45)
	stand.y = 0.0
	var fz := xf.basis.z.normalized()
	return place(nearest_node(stand), [stand], atan2(fz.x, fz.z))


## Somewhere on the floor beside a bike to put a part taken off it down, out of the way.
static func floor_by(bike_id: int, k: int) -> Transform3D:
	var b: Dictionary = Shed.bikes.get(bike_id, {})
	var xf: Transform3D = b.get("xf", Transform3D())
	var at := xf.origin + xf.basis.x.normalized() * 1.35 + xf.basis.z.normalized() * (0.55 * (k % 4) - 0.8)
	at.y = 0.0
	return Transform3D(Basis(Vector3.UP, 0.3 * k), at)


## The paint mixing bench in the mixing bay, facing it.
static func mix_bench() -> Dictionary:
	return place("mix", [Vector3(15.3, 0.0, 66.8), PaintBay.BENCH_STAND], -PI * 0.5)


## Beside the wash bay's lift, where the lance reaches all of a bike on it.
static func wash() -> Dictionary:
	return place("wash_front", [Vector3(-8.2, 0.0, 68.0), Vector3(-8.2, 0.0, 65.6)], PI * 0.5)


## Wheeling a bike onto the wash bay's lift (it faces the back wall).
static func wash_in() -> Dictionary:
	var at := Wash.lift_xf().origin
	return place("wash_front", [Vector3(at.x, 0.0, 69.6), at])


## Wheeling a bike onto showroom plinth `i`.
static func show_in(i: int) -> Dictionary:
	var at := SalesOffice.SHOWROOM_SPOTS[clampi(i, 0, 3)].origin
	return place("sales", [Vector3(at.x, 0.0, 67.2), Vector3(at.x, 0.0, at.z)])


## Standing by showroom plinth `i`, as if showing a buyer round the bike on it.
static func show_side(i: int) -> Dictionary:
	var at := SalesOffice.SHOWROOM_SPOTS[clampi(i, 0, 3)].origin
	# The aisle side of the plinth (the far ones are close to the wall), facing the bike.
	var side := Vector3(at.x - 1.45, 0.0, at.z + 0.5)
	return place("sales", [Vector3(side.x, 0.0, 67.2), side], -PI * 0.5)


## Behind the reception desk, facing the counter.
static func reception() -> Dictionary:
	var at := SalesOffice.RECEPTION_DESK.origin
	return place("sales_desk", [Vector3(21.3, 0.0, 65.0), at], -PI * 0.5)


## At the cafe counter, to order.
static func cafe_counter() -> Dictionary:
	return place("cafe", [Vector3(-22.9, 0.0, 61.0), CoffeeShop.ORDER_SPOT], 0.0)


## Where the teas go down: the end of the workbench.
static func tea_spot() -> Dictionary:
	return place("shed_w", [Vector3(-5.15, 0.0, 67.9)], PI * 0.5)


## The point on the workbench a tray goes down at.
static func tea_xf() -> Transform3D:
	return Transform3D(Basis(), Vector3(-6.0, 0.96, 68.0))


## In front of the staff parts rack in the storage room, facing it.
static func rack() -> Dictionary:
	var at := Shed.STAFF_RACK_XF.origin
	return place("store", [Vector3(at.x - 0.65, 0.0, at.z)], -PI * 0.5)


## At a trolley's handle (its +Z end), to take hold of it.
static func cart_handle(furniture_id: int) -> Dictionary:
	var f: Dictionary = Shed.furniture.get(furniture_id, {})
	if f.is_empty():
		return idle("expert")
	var xf: Transform3D = f["xf"]
	var at := xf.origin + xf.basis.z.normalized() * CART_AHEAD
	return place(nearest_node(at), [at], atan2(xf.basis.z.x, xf.basis.z.z))


## Where a trolley's left to load the deliveries onto: just off the delivery area's corner by the
## roller door, clear of the boxes.
static func cart_delivery() -> Dictionary:
	return place("yard", [Vector3(1.9, 0.0, 73.0), Vector3(1.9, 0.0, 73.7)])


## Where a trolley's left by a bike to work from: at the mouth of its bay, out of the way of
## their own way in down its right-hand side, or beside it anywhere else.
static func cart_by_bike(bike_id: int) -> Dictionary:
	var b: Dictionary = Shed.bikes.get(bike_id, {})
	if b.is_empty():
		return cart_park()
	var xf: Transform3D = b["xf"]
	var at := xf.origin
	var bay := bay_of(at)
	if bay >= 0 and bay < Workshop.BAY_COUNT:
		return place("shed", [Vector3(at.x - 0.25, 0.0, 64.6), Vector3(at.x - 0.25, 0.0, 63.75)])
	if bay >= Workshop.BAY_COUNT:
		return place("wing_mid", [Vector3(at.x - 0.25, 0.0, 55.4), Vector3(at.x - 0.25, 0.0, 56.0)])
	var side := at - xf.basis.x.normalized() * 1.2
	return place(nearest_node(side), [side])


## The staff trolley's own place, beside the parts rack.
static func cart_park() -> Dictionary:
	var at := Shed.STAFF_TROLLEY_XF.origin
	return place("store", [Vector3(at.x + 1.0, 0.0, at.z), at])


## Their own spot to wait at between jobs (`k` spreads two of the same role apart).
static func idle(role: String, k := 0) -> Dictionary:
	var p: Vector2 = IDLE.get(role, IDLE["mechanic"])
	match role:
		"reception":
			return reception()
		"sales":
			return place("sales", [Vector3(p.x + 0.8 * k, 0.0, p.y)], PI * 0.5)
		"paint":
			return place("paint", [Vector3(p.x, 0.0, p.y - 0.8 * k)], -PI * 0.5)
		"detailer":
			return place("wash_front", [Vector3(p.x - 0.7 * k, 0.0, p.y)], 0.0)
	return place("shed_w", [Vector3(p.x + 0.8 * k, 0.0, p.y)], PI * 0.5)
