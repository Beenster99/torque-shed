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
}
const EDGES := [["shed", "shed_w"], ["shed", "shed_e"], ["shed", "shed_door"], ["shed_w", "shed_door"],
	["shed_e", "shed_door"], ["shed_e", "paint_gap"], ["shed_door", "paint_gap"], ["shed_e", "shed_ne"],
	["shed_ne", "wing_door"], ["wing_door", "wing"], ["wing", "wing_mid"],
	["paint_gap", "paint"], ["paint", "paint_front"], ["paint_front", "mix_door"], ["mix_door", "mix"],
	["shed_door", "yard"], ["yard", "yard_aisle"], ["yard_aisle", "yard_s"], ["yard", "yard_s"], ["yard_s", "yard_se"],
	["yard_se", "sales_front"], ["sales_front", "sales_door"], ["sales_door", "sales"], ["sales", "sales_desk"],
	["yard", "yard_sw"], ["yard_sw", "wash_front"], ["yard_sw", "yard_w"], ["yard_w", "cafe_aisle"],
	["cafe_aisle", "cafe_walk"], ["cafe_walk", "cafe_door"], ["cafe_door", "cafe"]]

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


## The node nearest `at` (for a place out in the open, like a bike left in the yard).
static func nearest_node(at: Vector3, only: Array = []) -> String:
	var best := "shed"
	var d := INF
	for n in NODES:
		if not only.is_empty() and not only.has(n):
			continue
		var dd := (NODES[n] as Vector2).distance_squared_to(Vector2(at.x, at.z))
		if dd < d:
			d = dd
			best = n
	return best


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
## the one, along the graph and in to the other. Corners closer together than a few centimetres
## are merged.
static func route(from: Dictionary, to: Dictionary, pos: Vector3) -> PackedVector3Array:
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
			return place(nearest_node(s), [s + Vector3(0.0, 0.0, -0.7)], PI)
		if Shed.surface_of_spot(spot) == "":
			return at_spot(spot)
	var at := StaffJobs.item_at(item_id)
	if Shed.DELIVERY_AREA.grow(0.6).has_point(Vector2(at.x, at.z)):
		return place("yard_aisle", [Vector3(at.x, 0.0, 76.1), Vector3(at.x, 0.0, minf(at.z + 0.7, 76.1))], 0.0)
	if Shed.in_work_area(at) and Workshop.room_at(at) == "shed":
		var p := Vector3(clampf(at.x, -5.2, 5.0), 0.0, clampf(at.z + 0.6, 63.4, 68.8))
		var node := "shed_w" if p.x < -2.0 else ("shed_e" if p.x > 2.0 else "shed")
		return place(node, [p], atan2(-(at.x - p.x), -(at.z - p.z)) if p.distance_to(Vector3(at.x, 0.0, at.z)) > 0.1 else NAN)
	var q := Vector3(at.x, 0.0, at.z + 0.6)
	return place(nearest_node(q), [q], PI)


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
