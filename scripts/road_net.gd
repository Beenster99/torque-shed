class_name RoadNet
extends RefCounted
## Every road of a ride's region as something to ride on (Ride Anywhere v2, T6): the region's graph (RealRegion) with
## the heights of its roads, the shape of its junctions, where a point is on it ("which road am I on") and how the land
## is cut and banked round it. RoadBlock lays the roads of one 512 m square out from it; the streamer (AdventureWorld)
## builds the blocks round each rider. The interface the other threads build on is written down in
## ride-anywhere-v2/interfaces/road-block.md and pinned by tests/road_block_tests.gd.
##
## Everything is in the region's frame (metres from its frame point, +x east, -z north) and comes from the region and
## the bare ground's height by position (`height`) alone, so it's the same on every machine. The net is read-only once
## made but for its caches (each worked out the first time it's asked for, under a lock), so one net is shared by
## every worker thread.

## The road's heights are kept this often along an edge (m), as the single-line ride's knots are.
const STEP := 4.0
## locate finds a road whose centre line is within its half width and this much more (m).
const REACH := 30.0
## How far (m) the land lies under the road's deck, across the carriageway and its verges (ground_at).
const UNDER := 0.12
## The verge either side of the carriageway, level with it (m).
const VERGE := 1.5
## The cutting or embankment past the verge, as the planned road's (AdventureRoute._bank_height): BANK_BASE wide and
## BANK_WIDEN more for each metre of height it makes up (so the steeper the difference, the further out it runs, never a
## sheer wall), between BANK_MIN and BANK_MAX (m); the land eases from the road's height to its own across it.
const BANK_BASE := 12.5
const BANK_WIDEN := 0.9
const BANK_MIN := 8.0
const BANK_MAX := 40.0
## Where the land would rise past the road (a cutting, sidelong ground), it's held down level with the road this much
## further out past the verge before its bank starts (m): RealLand draws the land the roads cut into in 2 m cells
## (RealLand.FINE), and a cell with a corner up the bank and another under the deck would lie over the road. A cell's
## diagonal and a little. Nowhere this near a road's verge is the land higher than that road, whatever other road is
## near (a dual carriageway's other half, a roundabout's ring), so no cell reaching over a deck can stand up through it.
const LAND_PAD := 3.0
## Where the land falls away from the road (an embankment), it's held level with the road this much past the verge
## before its bank starts, so the verge's skirt is never left in the air over a cell of land that has already fallen.
const FALL_PAD := 1.5
## A tee with another on the far side of its main road within this distance (m) is a staggered junction.
const STAGGER := 40.0
## The heights along an edge are smoothed over this many STEPs, three times over (much like a bell curve some 60 m
## across: as the single-line ride's roads are, AdventureRoute.fair_heights), then eased over EASE m at each end onto
## the height of the node there, which every road meeting there shares.
const FAIR_STEPS := AdventureRoute.FAIR_KNOTS
const EASE := 40.0
## A road ending at a junction eases onto it over at least EASE m and as much as EASE_MOST, longer the further it has to
## come: sqrt(the height to make up times EASE_BEND), so a 1 m ease takes some 60 m.
const EASE_MOST := 160.0
const EASE_BEND := 3200.0
## A road that ends at a junction (a side road, or one onto a roundabout) runs on its through road's height for this far
## (m) along it from the junction before it's smoothed (_pin_y), so it comes in level with the junction.
const PIN := 24.0
## Before that they're smoothed over PRE_STEPS, as the planned road's are (RoutePlanner._heights).
const PRE_STEPS := 9
## The smoothed heights are worked out PAGE samples at a time, from the bare ones PAGE_PAD either side (as far as a pass
## of PRE_STEPS and three of FAIR_STEPS reach).
const PAGE := 64
const PAGE_PAD := 31
## A junction's arm starts its plain road at least this far (m) past where its kerbs clear the arms either side, and at
## most MOUTH_MOST from the node (and never past half the edge).
const FILLET := 3.0
const MOUTH_MOST := 30.0
## A roundabout whose map line keeps within this share of its radius of a circle is drawn as one; any other shape has
## its corners cut this many times.
const RING_ROUND := 0.2
const RING_ROUNDS := 4
## A junction's kerb between two arms is a curve of this many pieces.
const KERB_STEPS := 6
## A three-armed junction whose straightest pair of arms is within this much (radians) of straight on is a tee;
## otherwise it's a fork.
const TEE_STRAIGHT := deg_to_rad(35.0)
## The crown of the road (m): its middle is this much higher than its edges, as the single-line road's.
const CROWN := 0.04
## The grid locate and ground_at look a point up in (m a side), within each 512 m block.
const GRID := 32.0
## A bridge's deck (the map's bridges, the region's spans of kind 0) runs straight from one end to the other, over what
## it crosses rather than down into it, and goes this far under the road (m): the land under it stays below that.
const BRIDGE_DEPTH := AdventureRoute.BRIDGE_DEPTH
## Over another road a bridge leaves it this much headroom (m, a British bridge's 16 ft 6 in) under its deck, and a
## little more for the land the road below is laid on (it's often up on a bank of its own).
const HEADROOM := 5.3
const HEADROOM_PAD := 0.7
## Where a bridge has to climb to clear a road under it, it's level for this far either side of the road (m), then
## falls away at RAMP (rise over run) to where it meets the land: its approaches, on banks of their own.
const CROWN_FLAT := 20.0
const RAMP := 0.05
## A bridge's deck eases onto the land over this many STEPs at each end (its abutments).
const DECK_EASE := AdventureRoute.DECK_EASE
var _none := [PackedInt32Array(), []]   # (what _near_at gives where no road is)

var region: RealRegion
## height(x, z) -> float: the bare ground in the region frame (T5's terrain, asked by position and nothing else).
var height: Callable
## ready(area: Rect2) -> bool: whether the ground under `area` is final (RealTerrain.ready). Heights worked out where it
## isn't are used but not kept, so the net never holds on to a coarse guess. None: always final.
var ready: Callable
## 12 hex of the block builder's version and the region's hash.
var version_hash := ""
## What the blocks dress the land round the roads with (RoadBlock.trees), or {} for bare land: {terrain: RealTerrain
## (its canopy map, trees_at, and its cover), look: the place's look (PlaceLook: broad, needle, autumn)}. The ride sets
## it; the tests leave it off.
var dress := {}
## Level ground beside the roads for the ride's stops (T7: NetSites), [] for none: each {edge, s (m along it from its a
## end), side (1 the right of a to b, -1 the left), out (m past the verge), along (m either way)}. Set once with
## set_flats, before any block is laid out, the same on every machine (from the plan). ground_at levels the land
## inside each to the road's height there, banked out as a road's is; no tree or building of a block stands in one.
var flats: Array[Dictionary] = []
var _flats_by_block := {}   # Vector2i -> PackedInt32Array: the flats whose ground (with its bank) reaches the block

var _lock := Mutex.new()
var _edges_by_block := {}   # Vector2i -> PackedInt32Array: the edges whose line's box (with GROUND_REACH) meets it
var _nodes_by_block := {}   # Vector2i -> PackedInt32Array
var _buildings_by_block := {}   # Vector2i -> Array of rows
var _lines := {}            # edge -> PackedVector2Array: its line smoothed (line_of)
var _cum := {}              # edge -> PackedFloat32Array: distance along its line at each point
var _strands := {}          # edge -> Dictionary: the height strand it's on (_strand_of)
var _mains := {}            # node -> Vector2i: its through road's edges (_main_edges)
var _fixes := {}            # strand's first edge -> Vector4: how it eases onto the junctions at its ends (_strand_fix)
var _raw_y := {}            # node -> float (_raw_node_y)
var _fair := {}             # Vector3i(strand's first edge, page, pinned) -> PackedFloat32Array: its heights smoothed (_fair_page)
var _node_y := {}           # node -> float
var _junction := {}         # node -> Dictionary ({} for a plain join)
var _ring_of := {}          # edge -> PackedInt32Array: the ring of nodes it's part of, or empty
var _bridges := {}          # edge -> PackedInt32Array: its bridges, as samples [first, last, ...] (bridges_of)
var _decks := {}            # edge -> Dictionary: its bridges' heights (_deck_plan)
var _mapped_of := {}        # edge -> PackedInt32Array: its bridges as the map has them (_mapped)
var _over := {}             # edge -> Array of Vector4: the roads its bridges cross (_crossings)
var _grids := {}            # Vector2i block -> {Vector2i cell -> {edge -> PackedInt32Array of its line's pieces}}


## How far round a road the land is shaped by it (m past the centre line, at the widest).
static func ground_reach() -> float:
	return 4.0 + VERGE + LAND_PAD + BANK_MAX


func _init(r: RealRegion, h: Callable, final := Callable()) -> void:
	region = r
	height = h
	ready = final
	version_hash = ("%d|%s" % [RoadBlock.VERSION, r.hash]).sha1_text().substr(0, 12)
	var pad := ground_reach() + 8.0
	for ei in r.edge_count():
		var box := Rect2(r.edge_line[ei][0], Vector2.ZERO)
		for p in r.edge_line[ei]:
			box = box.expand(p)
		box = box.grow(pad)
		var k0 := RoadBlock.key_of(box.position.x, box.position.y)
		var k1 := RoadBlock.key_of(box.end.x, box.end.y)
		for bz in range(k0.y, k1.y + 1):
			for bx in range(k0.x, k1.x + 1):
				var key := Vector2i(bx, bz)
				var list: PackedInt32Array = _edges_by_block.get(key, PackedInt32Array())
				list.append(ei)
				_edges_by_block[key] = list
	for n in r.node_count():
		var key := RoadBlock.key_of(r.node_pos[n].x, r.node_pos[n].y)
		var list: PackedInt32Array = _nodes_by_block.get(key, PackedInt32Array())
		list.append(n)
		_nodes_by_block[key] = list
	for b: Array in r.buildings:
		var key := RoadBlock.key_of(float(b[0]), float(b[1]))
		if not _buildings_by_block.has(key):
			_buildings_by_block[key] = []
		(_buildings_by_block[key] as Array).append(b)


## The edges that run through or near block `key`.
func edges_in(key: Vector2i) -> PackedInt32Array:
	return _edges_by_block.get(key, PackedInt32Array())


## The nodes in block `key`.
func nodes_in(key: Vector2i) -> PackedInt32Array:
	return _nodes_by_block.get(key, PackedInt32Array())


## The buildings standing in block `key` (RealRegion.buildings rows).
func buildings_in(key: Vector2i) -> Array:
	return _buildings_by_block.get(key, [])


# ---------------------------------------------------------------------------- what a road is

## The carriageway's full width (m), by the road's class.
func width_of(edge: int) -> float:
	return float(RoutePlanner.WIDTH.get(region.class_of(edge), 4.6))


## 1 or 2: a one-way road, and a lane too narrow for two, has one.
func lanes_of(edge: int) -> int:
	return 1 if region.edge_oneway[edge] != 0 or width_of(edge) < 5.0 else 2


## Edge `edge`'s line, a to b, smoothed as the planned road is (RoutePlanner.smooth_line, by its class): no corner the
## map drew stays a corner, and the bike's road and the net's lie one on the other. It's smoothed a strand at a time
## (the edges joined end to end through plain joins), so it flows on through a join: a junction's or a dead end's node
## stays where it is, a plain join's moves onto the curve. A roundabout's ring is left as the map drew it.
func line_of(edge: int) -> PackedVector2Array:
	_lock.lock()
	var l = _lines.get(edge)
	_lock.unlock()
	if l != null:
		return l
	var got := _smooth_strand(edge)
	if not got.has(edge):
		got[edge] = region.edge_line[edge]   # (one with both ends on a ring that the way round it doesn't take)
	# (the first line an edge is given stays its line: the grid and its other caches were worked out from it)
	_lock.lock()
	for ei: int in got:
		if not _lines.has(ei):
			_lines[ei] = got[ei]
	var line: PackedVector2Array = _lines[edge]
	_lock.unlock()
	return line


## The edge on through plain join `node` from edge `from`, or -1 where the strand ends there.
func _through(node: int, from: int) -> int:
	var adj := region.adjacent[node]
	if adj.size() != 2 or adj[0] == adj[1]:
		return -1
	var next := adj[1] if adj[0] == from else adj[0]
	if region.edge_a[next] == region.edge_b[next] or not _ring_of_edge(next).is_empty() or not _ring_of_edge(from).is_empty():
		return -1
	return next


## The roundabout edge `edge` goes round (its nodes, as _ring), or empty: its own ring, or, for one too long to be
## found as part of one (RoutePlanner.RING_EDGE_M), the ring of a short edge at its a node that has its b node too.
func _ring_of_edge(edge: int) -> PackedInt32Array:
	if on_ring(edge):
		return _ring(edge)
	for e2 in region.adjacent[region.edge_a[edge]]:
		if e2 != edge and on_ring(e2):
			var ring := _ring(e2)
			if ring.has(region.edge_b[edge]) and ring.has(region.edge_a[edge]):
				return ring
	return PackedInt32Array()


## The smoothed lines of the strand edge `edge` is part of: {edge: line, a to b}.
func _smooth_strand(edge: int) -> Dictionary:
	var ring := _ring_of_edge(edge)
	if not ring.is_empty():
		return _smooth_ring(ring, edge)
	if region.edge_a[edge] == region.edge_b[edge]:
		return {edge: region.edge_line[edge]}
	# The strand in order, each [edge, the node it's entered from].
	var seen := {edge: true}
	var behind := []
	var ahead := []
	for dir: int in [0, 1]:
		var cur := edge
		var node := region.edge_a[edge] if dir == 0 else region.edge_b[edge]
		while true:
			var next := _through(node, cur)
			if next < 0 or seen.has(next):
				break
			seen[next] = true
			var far := region.other_end(next, node)
			if dir == 0:
				behind.append([next, far])
			else:
				ahead.append([next, node])
			node = far
			cur = next
	behind.reverse()
	var strand: Array = behind + [[edge, region.edge_a[edge]]] + ahead
	var raw := PackedVector2Array()
	var owner := PackedInt32Array()
	var joins := PackedFloat64Array()   # how far along raw each join is
	var run := 0.0
	for st: Array in strand:
		var line := region.line_from(int(st[0]), int(st[1]))
		if not raw.is_empty():
			joins.append(run)
		for k in range(0 if raw.is_empty() else 1, line.size()):
			if not raw.is_empty():
				run += raw[raw.size() - 1].distance_to(line[k])
			raw.append(line[k])
			owner.append(int(st[0]))
	var out := {}
	if raw.size() < 3 or run < 1.0:
		for st: Array in strand:
			out[int(st[0])] = region.edge_line[int(st[0])]
		return out
	var sm := RoutePlanner.smooth_line(raw, RoutePlanner.MIN_RADIUS, RoutePlanner.fair_of(region, owner))
	sm[0] = raw[0]
	if sm[sm.size() - 1].distance_to(raw[raw.size() - 1]) > 0.25:
		sm.append(raw[raw.size() - 1])
	else:
		sm[sm.size() - 1] = raw[raw.size() - 1]
	var cum := PackedFloat64Array([0.0])
	for k in range(1, sm.size()):
		cum.append(cum[k - 1] + sm[k].distance_to(sm[k - 1]))
	var total := cum[cum.size() - 1]
	# Each join is cut where the curve passes nearest its node, near as far along it as the join is along the map's line.
	var cuts := PackedFloat64Array([0.0])
	for i in joins.size():
		var at := region.node_pos[int(strand[i + 1][1])]
		var guess := joins[i] / run * total
		var best := guess
		var best_d := INF
		for k in range(1, sm.size()):
			if cum[k] < guess - 40.0 or cum[k - 1] > guess + 40.0:
				continue
			var ab := sm[k] - sm[k - 1]
			var l2 := ab.length_squared()
			var t := clampf((at - sm[k - 1]).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var d := (sm[k - 1] + ab * t).distance_squared_to(at)
			if d < best_d:
				best_d = d
				best = cum[k - 1] + sqrt(l2) * t
		cuts.append(clampf(best, cuts[cuts.size() - 1], total))
	cuts.append(total)
	for i in strand.size():
		var piece := _cut(sm, cum, cuts[i], cuts[i + 1])
		var ei := int(strand[i][0])
		if int(strand[i][1]) != region.edge_a[ei]:
			piece.reverse()
		out[ei] = piece
	return out


## The lines of the roundabout edge `edge` is on, round: {edge: line, a to b}. A ring near enough a circle is drawn as
## one (each edge an arc between where its nodes' bearings from the middle meet it); any other shape is rounded off
## (corners cut, RING_ROUNDS times) and each edge cut from it where its nodes are nearest. As the map drew it where its
## edges don't run one after another round it.
func _smooth_ring(ring: PackedInt32Array, edge: int) -> Dictionary:
	var set := {}
	for n in ring:
		set[n] = true
	var order := PackedInt32Array()
	var froms := PackedInt32Array()   # the node each is gone round from
	var used := {}
	var n0 := ring[0]
	var node := n0
	for _i in ring.size() + 1:
		var next := -1
		for ei in region.adjacent[node]:
			if not used.has(ei) and set.has(region.other_end(ei, node)) and region.edge_a[ei] != region.edge_b[ei]:
				next = ei
				break
		if next < 0:
			break
		used[next] = true
		order.append(next)
		froms.append(node)
		node = region.other_end(next, node)
		if node == n0:
			break
	if node != n0 or order.size() < 2:
		return {edge: region.edge_line[edge]}
	var raw := PackedVector2Array()
	for i in order.size():
		var line := region.line_from(order[i], froms[i])
		for k in range(0 if raw.is_empty() else 1, line.size()):
			raw.append(line[k])
	raw.resize(raw.size() - 1)   # (it closes on its first point)
	var c := Vector2.ZERO
	for p in raw:
		c += p
	c /= raw.size()
	var r := 0.0
	for n in froms:
		r += region.node_pos[n].distance_to(c)
	r /= order.size()
	var round := r > 1.0
	for p in raw:
		round = round and absf(p.distance_to(c) - r) <= r * RING_ROUND
	var out := {}
	if round:
		for i in order.size():
			var ei := order[i]
			var line := region.line_from(ei, froms[i])
			var a := region.node_pos[froms[i]] - c
			var b := region.node_pos[region.other_end(ei, froms[i])] - c
			var mid := line[line.size() / 2] - c if line.size() > 2 else (a + b) * 0.5
			var t0 := atan2(a.y, a.x)
			var sweep := wrapf(atan2(b.y, b.x) - t0, -PI, PI)
			# (the way round the map's line goes: the side its middle is on)
			var way := signf(wrapf(atan2(mid.y, mid.x) - t0, -PI, PI))
			if way != 0.0 and signf(sweep) != way:
				sweep += TAU * way
			var steps := maxi(2, ceili(absf(sweep) * r / 3.0))
			var pts := PackedVector2Array()
			for k in steps + 1:
				var t := t0 + sweep * float(k) / steps
				pts.append(c + Vector2(cos(t), sin(t)) * r)
			if froms[i] != region.edge_a[ei]:
				pts.reverse()
			out[ei] = pts
		return out
	# Rounded off: corners cut, then each node's nearest point on it is where its edges meet.
	var loop := raw
	for _round in RING_ROUNDS:
		var cut := PackedVector2Array()
		for k in loop.size():
			var p := loop[k]
			var q := loop[(k + 1) % loop.size()]
			cut.append(p.lerp(q, 0.25))
			cut.append(p.lerp(q, 0.75))
		loop = cut
	var at := {}   # node -> [index of the piece it's cut into, its point]
	for n in froms:
		var np := region.node_pos[n]
		var best := INF
		for k in loop.size():
			var p := loop[k]
			var q := loop[(k + 1) % loop.size()]
			var pq := q - p
			var t := clampf((np - p).dot(pq) / pq.length_squared(), 0.0, 1.0) if pq.length_squared() > 0.0 else 0.0
			var d := (p + pq * t).distance_squared_to(np)
			if d < best:
				best = d
				at[n] = [k, p + pq * t]
	for i in order.size():
		var ei := order[i]
		var from: Array = at[froms[i]]
		var to: Array = at[region.other_end(ei, froms[i])]
		var pts := PackedVector2Array([from[1]])
		var k := (int(from[0]) + 1) % loop.size()
		if int(from[0]) != int(to[0]) or (from[1] as Vector2).distance_to(loop[(int(from[0]) + 1) % loop.size()]) < (to[1] as Vector2).distance_to(loop[(int(from[0]) + 1) % loop.size()]):
			while true:
				pts.append(loop[k])
				if k == int(to[0]):
					break
				k = (k + 1) % loop.size()
		pts.append(to[1])
		if froms[i] != region.edge_a[ei]:
			pts.reverse()
		out[ei] = pts
	return out


## The stretch of line `pts` (`cum` the distance along it at each point) from `s0` to `s1`, its ends cut in exactly.
static func _cut(pts: PackedVector2Array, cum: PackedFloat64Array, s0: float, s1: float) -> PackedVector2Array:
	var out := PackedVector2Array([_along(pts, cum, s0)])
	for k in pts.size():
		if cum[k] > s0 + 0.01 and cum[k] < s1 - 0.01:
			out.append(pts[k])
	out.append(_along(pts, cum, s1))
	return out


static func _along(pts: PackedVector2Array, cum: PackedFloat64Array, s: float) -> Vector2:
	for k in range(1, pts.size()):
		if cum[k] >= s:
			var seg := cum[k] - cum[k - 1]
			return pts[k - 1].lerp(pts[k], (s - cum[k - 1]) / seg if seg > 0.0 else 0.0)
	return pts[pts.size() - 1]


## The distance along edge `edge`'s line at each of its points.
func _cum_of(edge: int) -> PackedFloat32Array:
	_lock.lock()
	var c = _cum.get(edge)
	_lock.unlock()
	if c != null:
		return c
	var line := line_of(edge)
	var out := PackedFloat32Array()
	out.resize(line.size())
	for k in range(1, line.size()):
		out[k] = out[k - 1] + line[k].distance_to(line[k - 1])
	_lock.lock()
	_cum[edge] = out
	_lock.unlock()
	return out


## The edge's length (m, along its line).
func length_of(edge: int) -> float:
	var c := _cum_of(edge)
	return c[c.size() - 1]


## The point `s` m along edge `edge` from its a node (clamped to its ends).
func point_at(edge: int, s: float) -> Vector2:
	var line := line_of(edge)
	var cum := _cum_of(edge)
	if s <= 0.0:
		return line[0]
	if s >= cum[cum.size() - 1]:
		return line[line.size() - 1]
	var k := cum.bsearch(s, true)   # the first at or past s
	k = clampi(k, 1, cum.size() - 1)
	var seg := cum[k] - cum[k - 1]
	return line[k - 1].lerp(line[k], (s - cum[k - 1]) / seg if seg > 0.0 else 0.0)


## The way edge `edge` runs (a to b) at `s`: radians clockwise from north (-z).
func heading_at(edge: int, s: float) -> float:
	var len := length_of(edge)
	var d := minf(2.0, len * 0.5)
	var p0 := point_at(edge, clampf(s - d, 0.0, len))
	var p1 := point_at(edge, clampf(s + d, 0.0, len))
	return _bearing(p1 - p0)


## The bearing of `v` (x east, z south), radians clockwise from north, 0 to TAU.
static func _bearing(v: Vector2) -> float:
	return fposmod(atan2(v.x, -v.y), TAU)


# ---------------------------------------------------------------------------- heights

## How many height samples edge `edge` has (one every STEP-ish, both ends included).
func samples_of(edge: int) -> int:
	return maxi(2, int(ceil(length_of(edge) / STEP)) + 1)


## Whether the ground round (x, z) is final out to `r` m (the terrain's ready; always, with none given).
func _final(p: Vector2, r: float) -> bool:
	return not ready.is_valid() or bool(ready.call(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)))


## The edge on from edge `from` through node `node` that the road's heights run on along without a break (its height
## strand, see _strand_of): through a plain join the other edge, and through a junction its through road's other arm
## (a roundabout's and a self-loop's ends are a strand's ends); -1 where the strand ends at `node`.
func _height_on(node: int, from: int) -> int:
	var adj := region.adjacent[node]
	if adj.size() == 2:
		return _through(node, from)
	if adj.size() < 3:
		return -1
	for ei in adj:
		if on_ring(ei) or region.edge_a[ei] == region.edge_b[ei]:
			return -1
	var main := _main_edges(node)
	if main.x < 0 or not _ring_of_edge(main.x).is_empty() or not _ring_of_edge(main.y).is_empty():
		return -1
	return main.y if from == main.x else (main.x if from == main.y else -1)


## The two edges of junction `node`'s through road (_main_pair), or (-1, -1) where it has none (fewer than three roads
## meet there, or its through road is one edge both ways).
func _main_edges(node: int) -> Vector2i:
	_lock.lock()
	var got = _mains.get(node)
	_lock.unlock()
	if got != null:
		return got
	var out := Vector2i(-1, -1)
	if region.adjacent[node].size() >= 3:
		var arms := _arms(PackedInt32Array([node]), {})
		var main := _main_pair(arms)
		out = Vector2i(int(arms[main.x]["edge"]), int(arms[main.y]["edge"]))
		if out.x == out.y:
			out = Vector2i(-1, -1)
	_lock.lock()
	_mains[node] = out
	_lock.unlock()
	return out


## The height of junction `node`'s surface at (x, z) `p`: its through road's, level across from the nearest point on
## it, so the through road runs on through it as it rides either side (node_y where it has none: a roundabout, a dead
## end).
func surface_y(node: int, p: Vector2) -> float:
	var main := _main_edges(node)
	if main.x < 0 or not _ring(main.x).is_empty():
		return node_y(node)
	var a := _project(main.x, p)
	var b := _project(main.y, p)
	return road_y(main.x, float(a[0])) if float(a[2]) <= float(b[2]) else road_y(main.y, float(b[0]))


## The height strand edge `edge` is on: the edges the road's heights run on along without a break, as the planned road's
## do (one edge after another through plain joins and along each junction's through road: _height_on), so they're
## smoothed along it as one road, never eased into a node part way. {edges: PackedInt32Array in order, fwd:
## PackedByteArray (1 where the strand runs an edge a to b), start: PackedFloat64Array (how far along the strand each
## edge starts, m), length (m), count: its samples, index: {edge: where it is in edges}}. The same whichever of its edges
## asks first: it runs from the end whose edge is the lower, and a loop from its lowest edge, a to b. Its heights are
## kept every STEP m along it exactly (its edges' own samples are a little closer, each edge's evenly spread).
func _strand_of(edge: int) -> Dictionary:
	_lock.lock()
	var got = _strands.get(edge)
	_lock.unlock()
	if got != null:
		return got
	var seen := {edge: true}
	var behind := []   # [edge, the node it's left by, walking away from `edge`]
	var ahead := []
	var loop := false
	if region.edge_a[edge] != region.edge_b[edge] and _ring_of_edge(edge).is_empty():
		for dir: int in [0, 1]:
			var cur := edge
			var node := region.edge_a[edge] if dir == 0 else region.edge_b[edge]
			while true:
				var next := _height_on(node, cur)
				if next == edge:
					loop = true
				if next < 0 or seen.has(next):
					break
				seen[next] = true
				var far := region.other_end(next, node)
				(behind if dir == 0 else ahead).append([next, far])
				node = far
				cur = next
	# In order: [edge, its far node going along], from behind's far end.
	var order := []
	for k in range(behind.size() - 1, -1, -1):
		var e := int(behind[k][0])
		var far := int(behind[k][1])
		order.append([e, region.other_end(e, far)])   # (walked back towards `edge`, it's left by the node nearer it)
	order.append([edge, region.edge_b[edge]])
	for st: Array in ahead:
		order.append([int(st[0]), int(st[1])])
	if loop:
		var low := 0
		for k in order.size():
			if int(order[k][0]) < int(order[low][0]):
				low = k
		order = order.slice(low) + order.slice(0, low)
		if int(order[0][1]) != region.edge_b[int(order[0][0])]:
			order.reverse()
			for st: Array in order:
				st[1] = region.other_end(int(st[0]), int(st[1]))
			order = order.slice(order.size() - 1) + order.slice(0, order.size() - 1)
	elif order.size() > 1 and int(order[order.size() - 1][0]) < int(order[0][0]):
		order.reverse()
		for st: Array in order:
			st[1] = region.other_end(int(st[0]), int(st[1]))
	var out := {"edges": PackedInt32Array(), "fwd": PackedByteArray(), "start": PackedFloat64Array(), "length": 0.0, "count": 0,
		"index": {}}
	var at := 0.0
	for st: Array in order:
		var e := int(st[0])
		out["index"][e] = (out["edges"] as PackedInt32Array).size()
		out["edges"].append(e)
		out["fwd"].append(1 if int(st[1]) == region.edge_b[e] else 0)
		out["start"].append(at)
		at += length_of(e)
	out["length"] = at
	out["count"] = int(ceil(at / STEP)) + 1
	_lock.lock()
	for e in out["edges"]:
		if not _strands.has(e):
			_strands[e] = out
	out = _strands[edge]
	_lock.unlock()
	return out


## Where `d` m along strand `st` is: Vector2(which of its edges, how far along that edge from its a end, m).
func _strand_at(st: Dictionary, d: float) -> Vector2:
	var start: PackedFloat64Array = st["start"]
	var i := clampi(start.bsearch(d, false) - 1, 0, start.size() - 1)
	var e: int = st["edges"][i]
	var len := length_of(e)
	var s := clampf(d - start[i], 0.0, len)
	return Vector2(i, s if st["fwd"][i] == 1 else len - s)


## The bare heights along strand `st`, smoothed, for its samples in page `page` (PAGE of them): as the planned road's
## are (RoutePlanner._heights, then AdventureRoute.fair_heights), a moving average PRE_STEPS long and then three of
## FAIR_STEPS, worked out from the bare heights PAGE_PAD samples either side, so a page is the same as the whole strand
## done at once and needs only the ground near it. A bridge's deck is in the bare heights (_decked) and its climb over
## a road put back after (_lifted). Kept once the ground there is final.
func _fair_page(st: Dictionary, page: int, pinned := true) -> PackedFloat32Array:
	var edges: PackedInt32Array = st["edges"]
	var key := Vector3i(edges[0], page, 1 if pinned else 0)
	_lock.lock()
	var f = _fair.get(key)
	_lock.unlock()
	if f != null:
		return f
	var n: int = st["count"]
	var k0 := page * PAGE
	var k1 := mini(n, k0 + PAGE)
	# (past its ends the bare heights run on straight out of it, so it's smoothed through a junction, not up to it)
	var lo := k0 - PAGE_PAD
	var hi := k1 + PAGE_PAD
	var h := PackedFloat32Array()
	h.resize(hi - lo)
	var box := Rect2()
	var final := true
	var e_first: int = edges[0]
	var e_last: int = edges[edges.size() - 1]
	var first_out := _end_way(e_first, st["fwd"][0] == 0)
	var last_out := _end_way(e_last, st["fwd"][edges.size() - 1] == 1)
	# (where it ends at a junction it's on the junction's through road there, out to PIN m along it)
	var pin_a := NAN
	var pin_b := NAN
	if pinned and lo * STEP < PIN:
		pin_a = _pin_y(region.edge_a[e_first] if st["fwd"][0] == 1 else region.edge_b[e_first], e_first)
	if pinned and hi * STEP > float(st["length"]) - PIN:
		pin_b = _pin_y(region.edge_b[e_last] if st["fwd"][edges.size() - 1] == 1 else region.edge_a[e_last], e_last)
	var total: float = st["length"]
	for j in range(lo, hi):
		var p: Vector2
		var y := NAN
		var d := j * STEP
		if d < 0.0 or d > total:
			var w: Array = first_out if d < 0.0 else last_out
			p = (w[0] as Vector2) + (w[1] as Vector2) * (-d if d < 0.0 else d - total)
			y = float(height.call(p.x, p.y))
		else:
			var at := _strand_at(st, d)
			var e: int = edges[int(at.x)]
			p = point_at(e, at.y)
			y = float(height.call(p.x, p.y))
			var plan := _deck_plan(e)
			if not (plan["level"] as Array).is_empty():
				var sp := length_of(e) / float(samples_of(e) - 1)
				y = _decked(plan, at.y / sp, y, sp)
				final = final and _decks.has(e)
		box = Rect2(p, Vector2.ZERO) if j == lo else box.expand(p)
		if d < PIN and not is_nan(pin_a):
			y = pin_a
		elif d > total - PIN and not is_nan(pin_b):
			y = pin_b
		h[j - lo] = y
	# (where the ground isn't in yet, the nearest that is: one sample with no height would spread to the whole page, and
	# the land laid from it would have holes; it's laid again once the ground comes)
	var last := NAN
	for k in h.size():
		if is_nan(h[k]):
			h[k] = last
		else:
			last = h[k]
	last = NAN
	for k in range(h.size() - 1, -1, -1):
		if is_nan(h[k]):
			h[k] = last
		else:
			last = h[k]
	h = _averaged(h, PRE_STEPS / 2)
	for _pass in 3:
		h = _averaged(h, FAIR_STEPS / 2)
	var res := h.slice(k0 - lo, k1 - lo)
	for j in range(k0, k1):
		var at := _strand_at(st, minf(j * STEP, total))
		var e: int = edges[int(at.x)]
		var plan := _deck_plan(e)
		if not (plan["lifts"] as PackedVector2Array).is_empty() and not is_nan(res[j - k0]):
			var sp := length_of(e) / float(samples_of(e) - 1)
			res[j - k0] = maxf(res[j - k0], _lifted(plan, at.y / sp, sp))   # (smoothing would take the top off its climb over a road)
	if final and (not ready.is_valid() or bool(ready.call(box.grow(STEP)))):
		_lock.lock()
		_fair[key] = res
		_lock.unlock()
	return res


## The height a road ending at junction `node` (from edge `from`) is pinned to there (_fair_page): its through road's
## smoothed height at the node (unpinned: its own ends' pins can't come back round to this one), or a roundabout's
## ring's; NAN at a plain join or a dead end, or where `from` is the through road.
func _pin_y(node: int, from: int) -> float:
	var adj := region.adjacent[node]
	if adj.size() < 3:
		return NAN
	var sum := 0.0
	var count := 0
	for ei in adj:
		if ei == from or not (on_ring(ei) or _height_on(node, ei) >= 0):
			continue
		var st := _strand_of(ei)
		var i: int = st["index"][ei]
		var at_a := region.edge_a[ei] == node
		var d: float = st["start"][i] + (0.0 if at_a == (st["fwd"][i] == 1) else length_of(ei))
		var f := d / STEP
		var j := clampi(int(f), 0, int(st["count"]) - 2)
		sum += lerpf(_fair_page(st, j / PAGE, false)[j % PAGE], _fair_page(st, (j + 1) / PAGE, false)[(j + 1) % PAGE], clampf(f - j, 0.0, 1.0))
		count += 1
	return sum / float(count) if count > 0 else NAN


## Where edge `edge`'s a end (or b, `at_b`) is and the way out of it there (unit): [Vector2, Vector2].
func _end_way(edge: int, at_b: bool) -> Array:
	var len := length_of(edge)
	if at_b:
		return [point_at(edge, len), (point_at(edge, len) - point_at(edge, maxf(len - 2.0, 0.0))).normalized()]
	return [point_at(edge, 0.0), (point_at(edge, 0.0) - point_at(edge, minf(2.0, len))).normalized()]


## The average of `h` over `half` samples either way at each (fewer near its ends).
static func _averaged(h: PackedFloat32Array, half: int) -> PackedFloat32Array:
	var sums := PackedFloat64Array()
	sums.resize(h.size() + 1)
	for k in h.size():
		sums[k + 1] = sums[k] + h[k]
	var out := PackedFloat32Array()
	out.resize(h.size())
	for k in h.size():
		var a := maxi(0, k - half)
		var b := mini(h.size() - 1, k + half)
		out[k] = (sums[b + 1] - sums[a]) / float(b - a + 1)
	return out


## Edge `edge`'s bridges: the map's (_mapped), each run on over any road it crosses (_crossings) far enough to clear that
## road, its verges and the land held level with it (a bridge's ends on the map are often its abutments' faces, short
## of the land the road under it is cut into), as its samples [first, last, ...].
func bridges_of(edge: int) -> PackedInt32Array:
	_lock.lock()
	var got = _bridges.get(edge)
	_lock.unlock()
	if got != null:
		return got
	var mapped := _mapped(edge)
	var out := PackedInt32Array()
	var over := []
	if not mapped.is_empty():
		var n := samples_of(edge)
		var sp := length_of(edge) / float(n - 1)
		var spans: Array[Vector2i] = []
		for k in range(0, mapped.size() - 1, 2):
			spans.append(Vector2i(mapped[k], mapped[k + 1]))
			for hit: Vector4 in _crossings(edge, sp * mapped[k], sp * mapped[k + 1]):
				over.append(hit)
				spans.append(Vector2i(maxi(0, floori((hit.z - hit.w) / sp)), mini(n - 1, ceili((hit.z + hit.w) / sp))))
		spans.sort()
		for sv in spans:
			var m := out.size()
			if m >= 2 and sv.x <= out[m - 1]:
				out[m - 1] = maxi(out[m - 1], sv.y)
			else:
				out.append(sv.x)
				out.append(sv.y)
	_lock.lock()
	_over[edge] = over
	_bridges[edge] = out
	_lock.unlock()
	return out


## Edge `edge`'s bridges as the map has them (the region's spans of kind 0, RoutePlanner.spans_along), as its samples
## [first, last, ...].
func _mapped(edge: int) -> PackedInt32Array:
	_lock.lock()
	var got = _mapped_of.get(edge)
	_lock.unlock()
	if got != null:
		return got
	var n := samples_of(edge)
	var sp := length_of(edge) / float(n - 1)
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	xs.resize(n)
	zs.resize(n)
	for k in n:
		var p := point_at(edge, sp * k)
		xs[k] = p.x
		zs[k] = p.y
	var out := RoutePlanner.spans_along(region, xs, zs, 0)
	_snap_ends(out, xs, zs)
	_lock.lock()
	_mapped_of[edge] = out
	_lock.unlock()
	return out


## Bridges `b` ([first, last, ...] samples at `xs`, `zs`, as RoutePlanner.spans_along finds them: any pair about as
## far apart as the bridge is long) each moved to the samples nearest the ends of the map's bridge it is, so its deck
## runs from the land at its very ends, not from a little way down into what it crosses.
func _snap_ends(b: PackedInt32Array, xs: PackedFloat64Array, zs: PackedFloat64Array) -> void:
	for k in range(0, b.size() - 1, 2):
		var p0 := Vector2(xs[b[k]], zs[b[k]])
		var p1 := Vector2(xs[b[k + 1]], zs[b[k + 1]])
		var best := INF
		var ends := Vector2i(b[k], b[k + 1])
		for sp: Array in region.spans:
			if int(sp[0]) != 0:
				continue
			var a := Vector2(float(sp[1]), float(sp[2]))
			var c := Vector2(float(sp[3]), float(sp[4]))
			for pair: Array in [[a, c], [c, a]]:
				var d: float = p0.distance_to(pair[0]) + p1.distance_to(pair[1])
				if d < best and d < RoutePlanner.BRIDGE_REACH * 4.0:
					best = d
					ends = Vector2i(_nearest_sample(pair[0], xs, zs, b[k]), _nearest_sample(pair[1], xs, zs, b[k + 1]))
		if ends.y > ends.x:
			b[k] = ends.x
			b[k + 1] = ends.y


## The sample at `xs`, `zs` nearest `p`, looking within a few either side of `near`.
static func _nearest_sample(p: Vector2, xs: PackedFloat64Array, zs: PackedFloat64Array, near: int) -> int:
	var best := near
	var best_d := INF
	var reach := int(ceil(RoutePlanner.BRIDGE_REACH * 2.0 / STEP)) + 1
	for k in range(maxi(0, near - reach), mini(xs.size(), near + reach + 1)):
		var d := Vector2(xs[k], zs[k]).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = k
	return best


## How far edge `edge` is out onto a bridge `s` m along it: 1 out over what it crosses, easing from 0 over DECK_EASE
## samples at each end (its abutments, where the land comes up to it), 0 off it.
func bridge_at(edge: int, s: float) -> float:
	return _deck_weight(edge, bridges_of(edge), s)


## How far out onto bridges `b` (edge `edge`'s samples [first, last, ...]) it is `s` m along: see bridge_at.
func _deck_weight(edge: int, b: PackedInt32Array, s: float) -> float:
	if b.is_empty():
		return 0.0
	var n := samples_of(edge)
	var f := clampf(s / maxf(length_of(edge), 0.001), 0.0, 1.0) * float(n - 1)
	var w := 0.0
	for k in range(0, b.size() - 1, 2):
		var i0 := float(b[k])
		var i1 := float(b[k + 1])
		if f < i0 or f > i1:
			continue
		# (no abutment at an end where the bridge carries on through the node into another road's)
		var from_a := f - i0 if b[k] > 0 or not _deck_on(edge, region.edge_a[edge]) else INF
		var from_b := i1 - f if b[k + 1] < n - 1 or not _deck_on(edge, region.edge_b[edge]) else INF
		var ease := minf(DECK_EASE, (i1 - i0) * 0.5) if from_a < INF and from_b < INF else float(DECK_EASE)
		w = maxf(w, clampf(minf(from_a, from_b) / maxf(ease, 0.5), 0.0, 1.0))
	return w


## Whether another road at node `node` (than edge `edge`) is on one of the map's bridges right up to it.
func _deck_on(edge: int, node: int) -> bool:
	for ei in region.adjacent[node]:
		if ei == edge:
			continue
		var b := _mapped(ei)
		if b.is_empty():
			continue
		var last := samples_of(ei) - 1
		if (region.edge_a[ei] == node and b[0] == 0) or (region.edge_b[ei] == node and b[b.size() - 1] == last):
			return true
	return false


## Edge `edge`'s bridges' heights: {"level": [[first sample, last, height there, there], ...] (each straight from the
## land at one end to the land at the other), "lifts": PackedVector2Array of (sample, height) where one crosses
## another road and its deck must clear it (HEADROOM)}. Kept once the ground they're taken from is final.
func _deck_plan(edge: int) -> Dictionary:
	_lock.lock()
	var got = _decks.get(edge)
	_lock.unlock()
	if got != null:
		return got
	var b := _mapped(edge)
	bridges_of(edge)   # (finds the roads it crosses: _over)
	_lock.lock()
	var over: Array = _over.get(edge, [])
	_lock.unlock()
	var plan := {"level": [], "lifts": PackedVector2Array()}
	var final := true
	if not b.is_empty():
		var sp := length_of(edge) / float(samples_of(edge) - 1)
		for k in range(0, b.size() - 1, 2):
			var p0 := point_at(edge, sp * b[k])
			var p1 := point_at(edge, sp * b[k + 1])
			(plan["level"] as Array).append([b[k], b[k + 1], float(height.call(p0.x, p0.y)), float(height.call(p1.x, p1.y))])
			final = final and _final(p0, STEP) and _final(p1, STEP)
		var lifts := PackedVector2Array()
		for hit: Vector4 in over:
			lifts.append(Vector2(hit.z / sp, float(height.call(hit.x, hit.y)) + HEADROOM + HEADROOM_PAD + BRIDGE_DEPTH))
			final = final and _final(Vector2(hit.x, hit.y), STEP)
		plan["lifts"] = lifts
	if final:
		_lock.lock()
		_decks[edge] = plan
		_lock.unlock()
	return plan


## The other roads crossing edge `edge`'s line between `s0` and `s1` m along it without meeting it (an overpass: not
## near a node of either), and not on a bridge of their own there: [Vector4(x, z, s along edge, how far either side of
## it (m along edge) the bridge must run to clear that road, its verges and the land held level with it, and then
## ease onto its abutments), ...].
func _crossings(edge: int, s0: float, s1: float) -> Array:
	var out := []
	var line := line_of(edge)
	var cum := _cum_of(edge)
	var ends: Array[Vector2] = [region.node_pos[region.edge_a[edge]], region.node_pos[region.edge_b[edge]]]
	var seen := {}
	for i in range(1, line.size()):
		if cum[i] < s0 or cum[i - 1] > s1:
			continue
		var a := line[i - 1]
		# (the grid's cells are filed with every piece within ground_reach of them: one look every GRID along will do)
		var from := maxf(cum[i - 1], s0)
		var to := minf(cum[i], s1)
		var looks := int(ceil((to - from) / GRID)) + 1
		for l in looks:
			var q0 := a.lerp(line[i], (lerpf(from, to, float(l) / maxf(looks - 1, 1)) - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001))
			var near := _near_at(q0.x, q0.y)
			var cands: PackedInt32Array = near[0]
			for c in cands.size():
				var oe := cands[c]
				if oe == edge:
					continue
				var ol := line_of(oe)
				for j: int in near[1][c]:
					var key := Vector3i(i, oe, j)
					if seen.has(key):
						continue
					seen[key] = true
					var hit = Geometry2D.segment_intersects_segment(a, line[i], ol[j - 1], ol[j])
					if hit == null:
						continue
					var at: Vector2 = hit
					var s := cum[i - 1] + a.distance_to(at)
					if s < s0 or s > s1:
						continue
					var meets := false
					for q: Vector2 in ends + [region.node_pos[region.edge_a[oe]], region.node_pos[region.edge_b[oe]]]:
						meets = meets or q.distance_to(at) < 6.0
					if meets or _deck_weight(oe, _mapped(oe), _cum_of(oe)[j - 1] + ol[j - 1].distance_to(at)) > 0.0:
						continue
					var cross := absf((line[i] - a).normalized().cross((ol[j] - ol[j - 1]).normalized()))
					var clear := (width_of(oe) * 0.5 + VERGE + LAND_PAD) / maxf(cross, 0.35) + width_of(edge) * 0.5 + DECK_EASE * STEP
					out.append(Vector4(at.x, at.y, s, clear))
	return out


## The height a bridge holds edge `edge`'s sample `k` (a fraction, or past either end) up to, by plan `plan`
## (_deck_plan), from the land there `bare`: straight across its span, and up to clear any road under it, falling away
## at RAMP to the land either side.
static func _decked(plan: Dictionary, k: float, bare: float, sp: float) -> float:
	var y := bare
	for lv: Array in plan["level"]:
		if k >= float(lv[0]) and k <= float(lv[1]) and not is_nan(float(lv[2]) + float(lv[3])):
			y = lerpf(float(lv[2]), float(lv[3]), (k - float(lv[0])) / maxf(float(lv[1]) - float(lv[0]), 1.0))
	return y if is_nan(y) else maxf(y, _lifted(plan, k, sp))


## The height plan `plan`'s lifts hold sample `k` up to (-INF where none does).
static func _lifted(plan: Dictionary, k: float, sp: float) -> float:
	var y := -INF
	for lift: Vector2 in plan["lifts"]:
		if not is_nan(lift.y):
			y = maxf(y, lift.y - maxf(absf(k - lift.x) * sp - CROWN_FLAT, 0.0) * RAMP)
	return y


## The smoothed bare height of edge `edge`'s sample `k`.
func _fair_at(edge: int, k: int) -> float:
	var st := _strand_of(edge)
	var i: int = st["index"][edge]
	var s := length_of(edge) * float(k) / float(samples_of(edge) - 1)
	var f := (float(st["start"][i]) + (s if st["fwd"][i] == 1 else length_of(edge) - s)) / STEP
	var j := clampi(int(f), 0, int(st["count"]) - 2)
	return lerpf(_fair_j(st, j), _fair_j(st, j + 1), clampf(f - j, 0.0, 1.0))


## Strand `st`'s smoothed height at its sample `j`.
func _fair_j(st: Dictionary, j: int) -> float:
	return _fair_page(st, j / PAGE)[j % PAGE]


## The height of the road at node `node`, which every road meeting there shares: where a strand runs through it (a
## plain join, a junction's through road) that strand's height there; at a roundabout, its ring's; at a dead end, its
## road's. A road that ends at a junction (a side road) eases onto it (_strand_fix).
func node_y(node: int) -> float:
	_lock.lock()
	var y = _node_y.get(node)
	_lock.unlock()
	if y != null:
		return y
	var out := _node_mean(node, false)
	if _final(region.node_pos[node], PAGE_PAD * STEP + STEP * 2.0 + EASE_MOST):
		_lock.lock()
		_node_y[node] = out
		_lock.unlock()
	return out


## node_y from the strands' smoothed heights alone, before any is eased onto a junction: what a road ending at the
## junction eases onto (so no height eases onto another that is itself easing).
func _raw_node_y(node: int) -> float:
	_lock.lock()
	var y = _raw_y.get(node)
	_lock.unlock()
	if y != null:
		return y
	var out := _node_mean(node, true)
	if _final(region.node_pos[node], PAGE_PAD * STEP + STEP * 2.0 + PIN):
		_lock.lock()
		_raw_y[node] = out
		_lock.unlock()
	return out


## The mean of the heights at node `node` of the roads node_y takes it from: smoothed only (`raw`), or as ridden.
func _node_mean(node: int, raw: bool) -> float:
	var counts := {}
	var adj := region.adjacent[node]
	if adj.size() >= 3:
		for ei in adj:
			if on_ring(ei):
				counts[ei] = true
		if counts.size() < 2:
			counts = {}
			var arms := _arms(PackedInt32Array([node]), {})
			var main := _main_pair(arms)
			counts[int(arms[main.x]["edge"])] = true
			counts[int(arms[main.y]["edge"])] = true
	var sum := 0.0
	var count := 0
	for ei in adj:
		if not counts.is_empty() and not counts.has(ei):
			continue
		var last := samples_of(ei) - 1
		for k: int in ([0] if region.edge_a[ei] == node else []) + ([last] if region.edge_b[ei] == node else []):
			sum += _fair_at(ei, k) if raw else _profile_at(ei, k)
			count += 1
	var at := region.node_pos[node]
	return sum / float(count) if count > 0 else float(height.call(at.x, at.y))


## How strand `st`'s smoothed heights are eased at its ends onto the junctions there (_raw_node_y): Vector4(how much at
## its start, over how far, how much at its end, over how far); nothing at a plain join or a dead end (or round a loop).
## The further it has to come, the longer it takes (EASE to EASE_MOST m, no more than half the strand), so it never
## bends sharply.
func _strand_fix(st: Dictionary) -> Vector4:
	var edges: PackedInt32Array = st["edges"]
	_lock.lock()
	var got = _fixes.get(edges[0])
	_lock.unlock()
	if got != null:
		return got
	var e0 := edges[0]
	var e1 := edges[edges.size() - 1]
	var n0 := region.edge_a[e0] if st["fwd"][0] == 1 else region.edge_b[e0]
	var n1 := region.edge_b[e1] if st["fwd"][edges.size() - 1] == 1 else region.edge_a[e1]
	var total: float = st["length"]
	var out := Vector4.ZERO
	var final := true
	var loop := edges.size() > 1 and _height_on(n0, e0) == e1
	for end: int in ([] if loop else [0, 1]):
		var node := n0 if end == 0 else n1
		if region.adjacent[node].size() < 3:
			continue
		var e := e0 if end == 0 else e1
		var at_a := region.edge_a[e] == node
		var d := _raw_node_y(node) - _fair_at(e, 0 if at_a else samples_of(e) - 1)
		var reach := minf(clampf(sqrt(absf(d) * EASE_BEND), EASE, EASE_MOST), total * 0.5)
		if end == 0:
			out.x = d
			out.y = reach
		else:
			out.z = d
			out.w = reach
		final = final and _raw_y.has(node) and _final(region.node_pos[node], EASE_MOST + PAGE_PAD * STEP)
	if final:
		_lock.lock()
		_fixes[edges[0]] = out
		_lock.unlock()
	return out


## The road's height at edge `edge`'s sample `k`: its strand's smoothed height, eased at the strand's ends onto the
## junctions there (_strand_fix).
func _profile_at(edge: int, k: int) -> float:
	var st := _strand_of(edge)
	var y := _fair_at(edge, k)
	var fix := _strand_fix(st)
	if fix == Vector4.ZERO:
		return y
	var i: int = st["index"][edge]
	var s := length_of(edge) * float(k) / float(samples_of(edge) - 1)
	var d: float = st["start"][i] + (s if st["fwd"][i] == 1 else length_of(edge) - s)
	if fix.y > 0.0:
		y += fix.x * (1.0 - smoothstep(0.0, fix.y, d))
	if fix.w > 0.0:
		y += fix.z * (1.0 - smoothstep(0.0, fix.w, float(st["length"]) - d))
	return y


## The road's height at every sample along edge `edge` (samples_of of them, evenly from a to b).
func profile(edge: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples_of(edge))
	for k in out.size():
		out[k] = _profile_at(edge, k)
	return out


## The road's height `s` m along edge `edge` (its centre line, before the crown).
func road_y(edge: int, s: float) -> float:
	var n := samples_of(edge)
	var len := length_of(edge)
	if len <= 0.0:
		return _profile_at(edge, 0)
	var f := clampf(s / len, 0.0, 1.0) * float(n - 1)
	var k := mini(int(f), n - 2)
	return lerpf(_profile_at(edge, k), _profile_at(edge, k + 1), f - k)


# ---------------------------------------------------------------------------- junctions

## The ring of road (a roundabout) edge `edge` is part of: its nodes, or empty.
func _ring(edge: int) -> PackedInt32Array:
	_lock.lock()
	var r = _ring_of.get(edge)
	_lock.unlock()
	if r != null:
		return r
	var ring := RoutePlanner.find_ring(region, edge) if region.edge_len[edge] <= RoutePlanner.RING_EDGE_M else PackedInt32Array()
	if not ring.is_empty():
		# (the ring as a set, in order of node, so it's the same whichever edge found it)
		var sorted := ring.duplicate()
		sorted.sort()
		var uniq := PackedInt32Array()
		for n in sorted:
			if uniq.is_empty() or uniq[uniq.size() - 1] != n:
				uniq.append(n)
		ring = uniq
		# Only an edge with both ends on the ring is on it.
		var set := {}
		for n in ring:
			set[n] = true
		if not (set.has(region.edge_a[edge]) and set.has(region.edge_b[edge])):
			ring = PackedInt32Array()
	_lock.lock()
	_ring_of[edge] = ring
	_lock.unlock()
	return ring


## Whether edge `edge` is part of a roundabout's carriageway.
func on_ring(edge: int) -> bool:
	return not _ring(edge).is_empty()


## The junction at node `node` (see road-block.md), or {} where just two roads join end to end.
func junction_of(node: int) -> Dictionary:
	_lock.lock()
	var j = _junction.get(node)
	_lock.unlock()
	if j != null:
		return j
	var out := _make_junction(node)
	# (its heights are kept only once the ground round it is final)
	if not _final(region.node_pos[node], MOUTH_MOST + EASE + PAGE_PAD * STEP + RoutePlanner.RING_TOTAL_M * 0.5):
		return out
	_lock.lock()
	if out.has("nodes"):
		for n in out["nodes"]:
			_junction[n] = out
	else:
		_junction[node] = out
	_lock.unlock()
	return out


func _make_junction(node: int) -> Dictionary:
	for ei in region.adjacent[node]:
		var ring := _ring(ei)
		if not ring.is_empty():
			return _roundabout(ring)
	var deg := region.adjacent[node].size()
	if deg == 2:
		return {}
	var arms := _arms(PackedInt32Array([node]), {})
	var kind := "end"
	var main := Vector2i(-1, -1)
	if deg >= 3:
		main = _main_pair(arms)
		if deg == 3:
			var bend := absf(PI - _angle_between(float(arms[main.x]["heading"]), float(arms[main.y]["heading"])))
			kind = "tee" if bend <= TEE_STRAIGHT else "fork"
		elif deg == 4:
			kind = "cross"
		else:
			kind = "multi"
	for k in arms.size():
		arms[k]["main"] = k == main.x or k == main.y
	var pair := -1
	if kind == "tee":
		pair = _stagger_pair(node, arms)
		if pair >= 0:
			kind = "staggered"
	var pos := region.node_pos[node]
	var y := node_y(node)
	var out := {"node": node, "nodes": PackedInt32Array([node]), "kind": kind, "pos": Vector3(pos.x, y, pos.y),
		"island": 0.0, "pair": pair, "arms": arms}
	_shape(out)
	return out


## The arms out of the nodes `nodes` (leaving out the edges in `skip`), clockwise from north: each {edge, node, heading,
## width, class, mouth (filled in by _shape), main}.
func _arms(nodes: PackedInt32Array, skip: Dictionary) -> Array:
	var arms := []
	for n in nodes:
		for ei in region.adjacent[n]:
			if skip.has(ei):
				continue
			var len := length_of(ei)
			var from_a := region.edge_a[ei] == n
			# (a self-loop leaves from both its ends)
			var ends := [true, false] if region.edge_a[ei] == region.edge_b[ei] else [from_a]
			for fa: bool in ends:
				var s := minf(12.0, len * 0.5)
				var p := point_at(ei, s if fa else len - s)
				var head := _bearing(p - region.node_pos[n])
				arms.append({"edge": ei, "node": n, "heading": head, "width": width_of(ei), "class": region.class_of(ei),
					"mouth": Vector3.ZERO, "main": false, "_from_a": fa})
	arms.sort_custom(func(p, q): return float(p["heading"]) < float(q["heading"]) or \
		(float(p["heading"]) == float(q["heading"]) and int(p["edge"]) < int(q["edge"])))
	return arms


## The angle between two bearings, 0 to PI.
static func _angle_between(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## The junction's through road: the pair of arms nearest straight on, the widest first.
func _main_pair(arms: Array) -> Vector2i:
	var best := Vector2i(0, 1)
	var best_key := INF
	for i in arms.size():
		for k in range(i + 1, arms.size()):
			var off := PI - _angle_between(float(arms[i]["heading"]), float(arms[k]["heading"]))
			var w := minf(float(arms[i]["width"]), float(arms[k]["width"]))
			var key := off - w * 0.05   # (a metre's width is worth about three degrees of straightness)
			if key < best_key - 1e-6:
				best_key = key
				best = Vector2i(i, k)
	return best


## The node of another tee on the far side of this tee's main road within STAGGER m along it, or -1.
func _stagger_pair(node: int, arms: Array) -> int:
	var side_arm: Dictionary
	var mains := []
	for a in arms:
		if bool(a["main"]):
			mains.append(a)
		else:
			side_arm = a
	if side_arm.is_empty():
		return -1
	for a in mains:
		var ei := int(a["edge"])
		if length_of(ei) > STAGGER:
			continue
		var other := region.other_end(ei, node)
		if other == node or region.adjacent[other].size() != 3:
			continue
		# Its side road leaves the main road on the other side from ours.
		var along := float(a["heading"])
		var ours := wrapf(float(side_arm["heading"]) - along, -PI, PI)
		var o_arms := _arms(PackedInt32Array([other]), {})
		var o_main := _main_pair(o_arms)
		if absf(PI - _angle_between(float(o_arms[o_main.x]["heading"]), float(o_arms[o_main.y]["heading"]))) > TEE_STRAIGHT:
			continue
		for k in o_arms.size():
			if k == o_main.x or k == o_main.y:
				continue
			var theirs := wrapf(float(o_arms[k]["heading"]) - along, -PI, PI)
			if signf(theirs) != signf(ours) and absf(theirs) > 0.3 and absf(ours) > 0.3:
				return other
	return -1


## A roundabout: the ring of `ring` nodes, its arms the roads off it.
func _roundabout(ring: PackedInt32Array) -> Dictionary:
	var set := {}
	for n in ring:
		set[n] = true
	var skip := {}
	var centre := Vector2.ZERO
	var count := 0
	var ring_w := 0.0
	for n in ring:
		for ei in region.adjacent[n]:
			if set.has(region.edge_a[ei]) and set.has(region.edge_b[ei]) and not skip.has(ei):
				skip[ei] = true
				ring_w = maxf(ring_w, width_of(ei))
				for p in region.edge_line[ei]:
					centre += p
					count += 1
	centre /= maxf(count, 1)
	var radius := 0.0
	var y := 0.0
	for n in ring:
		radius += region.node_pos[n].distance_to(centre)
		y += node_y(n)
	radius /= ring.size()
	y /= ring.size()
	var arms := _arms(ring, skip)
	# Its arms' headings are from the middle, so "clockwise from north" means round the ring.
	for a in arms:
		var at := region.node_pos[int(a["node"])]
		var len := length_of(int(a["edge"]))
		var s := minf(12.0, len * 0.5)
		var p := point_at(int(a["edge"]), s if bool(a["_from_a"]) else len - s)
		a["heading"] = _bearing(p - centre) if p.distance_to(centre) > 0.5 else _bearing(p - at)
	arms.sort_custom(func(p, q): return float(p["heading"]) < float(q["heading"]))
	var main := _main_pair(arms) if arms.size() >= 2 else Vector2i(-1, -1)
	for k in arms.size():
		arms[k]["main"] = k == main.x or k == main.y
	# (the island stops short of the ring as it's drawn, rounded: line_of)
	var inner := radius
	for ei: int in skip:
		for p in line_of(ei):
			inner = minf(inner, p.distance_to(centre))
	var island := maxf(0.0, inner - ring_w * 0.5 - 0.5)
	var out := {"node": ring[0], "nodes": ring, "kind": "mini" if radius <= RoutePlanner.MINI_RING_M else "roundabout",
		"pos": Vector3(centre.x, y, centre.y), "island": island, "pair": -1, "arms": arms, "ring_w": ring_w,
		"ring_r": radius}
	_shape(out)
	return out


## Works out how far each arm's plain road starts from its node (its mouth), the junction's radius and its outline.
func _shape(j: Dictionary) -> void:
	var arms: Array = j["arms"]
	var n := arms.size()
	var centre := Vector2(j["pos"].x, j["pos"].z)
	var ring: bool = j["kind"] in ["roundabout", "mini"]
	for i in n:
		var a: Dictionary = arms[i]
		var half := float(a["width"]) * 0.5
		var m := 0.0
		if ring:
			m = float(j["ring_w"]) * 0.5 + FILLET
		elif n >= 2:
			for k: int in [(i + n - 1) % n, (i + 1) % n]:
				if k == i:
					continue
				var th := clampf(_angle_between(float(a["heading"]), float(arms[k]["heading"])), 0.2, PI)
				var b := float(arms[k]["width"]) * 0.5
				m = maxf(m, (b + half * cos(th)) / sin(th))
			m = maxf(m, 1.0) + FILLET
		m = minf(m, MOUTH_MOST)
		m = minf(m, length_of(int(a["edge"])) * 0.5)
		var ei := int(a["edge"])
		var s := m if bool(a["_from_a"]) else length_of(ei) - m
		var p := point_at(ei, s)
		a["mouth_s"] = m
		a["mouth"] = Vector3(p.x, road_y(ei, s), p.y)
	var radius := 0.0
	var outline := PackedVector2Array()
	var outline_y := PackedFloat32Array()
	var kerb := PackedByteArray()   # 1 where the outline runs on from point k along a kerb, 0 across an arm's mouth
	var corners := []
	for a in arms:
		var p: Vector3 = a["mouth"]
		var ei := int(a["edge"])
		var s := float(a["mouth_s"]) if bool(a["_from_a"]) else length_of(ei) - float(a["mouth_s"])
		var out_head := heading_at(ei, s) + (0.0 if bool(a["_from_a"]) else PI)
		var right := Vector2(cos(out_head), sin(out_head))
		var half := float(a["width"]) * 0.5
		corners.append([Vector2(p.x, p.z) - right * half, Vector2(p.x, p.z) + right * half, Vector2(sin(out_head), -cos(out_head)), p.y])
	for i in n:
		var c: Array = corners[i]
		outline.append(c[0])
		outline.append(c[1])
		outline_y.append_array([c[3], c[3]])
		kerb.append_array([0, 1])
		if ring or n < 2:
			continue
		# The kerb round to the next arm's left edge: a curve into the corner where the two edges would meet (none where
		# they wouldn't, the far side of a tee: a straight kerb).
		var d: Array = corners[(i + 1) % n]
		var x = _meet(c[1], -(c[2] as Vector2), d[0], -(d[2] as Vector2))
		if x == null:
			continue
		for q in range(1, KERB_STEPS):
			var t := float(q) / KERB_STEPS
			outline.append((c[1] as Vector2).lerp(x, t).lerp((x as Vector2).lerp(d[0], t), t))
			outline_y.append(lerpf(c[3], d[3], t))
			kerb.append(1)
	for p in outline:
		radius = maxf(radius, p.distance_to(centre))
	if ring:
		# A roundabout's surface is its ring, out to its outer edge (its arms' mouths run on from that).
		var outer := float(j["ring_r"]) + float(j["ring_w"]) * 0.5
		radius = maxf(radius, outer)
		outline = PackedVector2Array()
		for k in 24:
			var b := TAU * k / 24.0
			outline.append(centre + Vector2(sin(b), -cos(b)) * outer)
		outline_y = PackedFloat32Array()
		outline_y.resize(outline.size())
		outline_y.fill(float(j["pos"].y))
		kerb = PackedByteArray()
		kerb.resize(outline.size())
	if n == 1:
		# A dead end: its outline is the half circle of the road's end.
		var a: Dictionary = arms[0]
		var half := float(a["width"]) * 0.5
		var h := float(a["heading"])
		outline = PackedVector2Array()
		for k in 9:
			var b := h + PI * 0.5 + PI * float(k) / 8.0   # round behind the node, from the road's right edge to its left
			outline.append(centre + Vector2(sin(b), -cos(b)) * half)
		radius = half
		outline_y = PackedFloat32Array()
		outline_y.resize(outline.size())
		outline_y.fill(float(j["pos"].y))
		kerb = PackedByteArray()
		kerb.resize(outline.size())
		kerb.fill(1)
	j["radius"] = maxf(radius, 0.5)
	j["outline"] = outline
	j["outline_y"] = outline_y
	j["kerb"] = kerb


## Where the line from `p` along `u` meets the one from `q` along `v`, both ahead of where they start and within
## MOUTH_MOST and a half of it, or null.
static func _meet(p: Vector2, u: Vector2, q: Vector2, v: Vector2):
	var den := u.cross(v)
	if absf(den) < 0.05:
		return null
	var w := q - p
	var a := w.cross(v) / den
	var b := w.cross(u) / den
	if a <= 0.0 or b <= 0.0 or a > MOUTH_MOST * 1.5 or b > MOUTH_MOST * 1.5:
		return null
	return p + u * a


## The distance (m along `edge` from `node`) where its plain road starts: 0 at a plain join.
func mouth(edge: int, node: int) -> float:
	var j := junction_of(node)
	if j.is_empty():
		return 0.0
	if j["kind"] in ["roundabout", "mini"] and on_ring(edge):
		return 0.0
	for a in j["arms"]:
		if int(a["edge"]) == edge and int(a["node"]) == node:
			return float(a["mouth_s"])
	return 0.0


# ---------------------------------------------------------------------------- where you are

## The edges filed under each GRID square of block `key` (any whose line comes within ground_reach of the square), with
## the pieces of each one's line that do: {Vector2i cell -> [PackedInt32Array edges, Array of PackedInt32Array (each
## edge's pieces: k for the piece from point k - 1 to k)]}.
func _grid_of(key: Vector2i) -> Dictionary:
	_lock.lock()
	var g = _grids.get(key)
	_lock.unlock()
	if g != null:
		return g
	var out := {}
	var o := Vector2(key) * RoadBlock.SIZE
	var cells := int(RoadBlock.SIZE / GRID)
	var pad := ground_reach()
	for ei in edges_in(key):
		var line := line_of(ei)
		var mine := {}
		for k in range(1, line.size()):
			var box := Rect2(line[k - 1], Vector2.ZERO).expand(line[k]).grow(pad)
			var c0 := Vector2i(floori((box.position.x - o.x) / GRID), floori((box.position.y - o.y) / GRID))
			var c1 := Vector2i(floori((box.end.x - o.x) / GRID), floori((box.end.y - o.y) / GRID))
			for cz in range(maxi(c0.y, 0), mini(c1.y, cells - 1) + 1):
				for cx in range(maxi(c0.x, 0), mini(c1.x, cells - 1) + 1):
					var c := Vector2i(cx, cz)
					var segs: PackedInt32Array = mine.get(c, PackedInt32Array())
					segs.append(k)
					mine[c] = segs
		for c: Vector2i in mine:
			if not out.has(c):
				out[c] = [PackedInt32Array(), []]
			var edges: PackedInt32Array = out[c][0]
			edges.append(ei)   # (a packed array is a copy: put back)
			out[c][0] = edges
			(out[c][1] as Array).append(mine[c])
	_lock.lock()
	_grids[key] = out
	_lock.unlock()
	return out


## The edges filed near (x, z), and the pieces of their lines near it (_grid_of).
func _near_at(x: float, z: float) -> Array:
	var key := RoadBlock.key_of(x, z)
	var o := Vector2(key) * RoadBlock.SIZE
	return _grid_of(key).get(Vector2i(floori((x - o.x) / GRID), floori((z - o.y) / GRID)), _none)


## The edges filed near (x, z).
func _near(x: float, z: float) -> PackedInt32Array:
	return _near_at(x, z)[0]


## The nearest point of edge `edge`'s line to `p`: [distance along the line, signed distance right of it (a to b),
## distance from it]. Only the pieces `segs` of the line are looked at (all of them, empty).
func _project(edge: int, p: Vector2, segs := PackedInt32Array()) -> Array:
	var line := line_of(edge)
	var cum := _cum_of(edge)
	var best_d := INF
	var best_s := 0.0
	var best_lat := 0.0
	var count := segs.size() if not segs.is_empty() else line.size() - 1
	for i in count:
		var k := segs[i] if not segs.is_empty() else i + 1
		var a := line[k - 1]
		var b := line[k]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var q := a + ab * t
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best_s = cum[k - 1] + sqrt(l2) * t
			# Right of a to b: x east, z south, so right of (dx, dz) is (-dz, dx).
			best_lat = (p - q).dot(Vector2(-ab.y, ab.x).normalized()) if l2 > 0.0 else 0.0
	return [best_s, best_lat, sqrt(best_d)]


## Which road (x, z) is on, or nearest within REACH of its edge: see road-block.md. `hint` (the edge from last time) is
## tried first; the answer doesn't depend on it.
func locate(x: float, z: float, hint := -1) -> Dictionary:
	var p := Vector2(x, z)
	var best := -1
	var best_key := INF
	var best_proj := []
	var near := _near_at(x, z)
	var cands: PackedInt32Array = near[0]
	if hint >= 0 and hint < region.edge_count() and not cands.has(hint):
		cands = cands.duplicate()
		cands.append(hint)
	for c in cands.size():
		var ei := cands[c]
		var pr := _project(ei, p, near[1][c] if c < (near[1] as Array).size() else PackedInt32Array())
		var off := float(pr[2]) - width_of(ei) * 0.5
		if off > REACH:
			continue
		# Inside a carriageway, the one whose centre line is nearest; else the nearest edge of one. Still on the hint's,
		# that one (where one road crosses over another, the one it was on).
		var key := maxf(off, 0.0) * 1000.0 + float(pr[2])
		if ei == hint and off <= 0.0:
			key = -1.0
		if key < best_key or (key == best_key and ei < best):
			best_key = key
			best = ei
			best_proj = pr
	if best < 0:
		return {}
	var s: float = best_proj[0]
	var lat: float = best_proj[1]
	var w := width_of(best)
	var f := clampf(lat / maxf(w * 0.5, 0.1), -1.0, 1.0)
	var y := road_y(best, s) + CROWN * (1.0 - f * f)
	var node := -1
	var on := float(best_proj[2]) <= w * 0.5   # (its distance, not lat: past a dead end isn't on it)
	for n: int in [region.edge_a[best], region.edge_b[best]]:
		var j := junction_of(n)
		if j.is_empty() or j["kind"] == "end":
			continue
		if Geometry2D.is_point_in_polygon(p, j["outline"]) or Vector2(j["pos"].x, j["pos"].z).distance_to(p) <= _inner(j):
			node = int(j["node"])
			on = true
			break
	return {"edge": best, "s": s, "lat": lat, "y": y, "width": w, "heading": heading_at(best, s), "on_road": on,
		"node": node}


# ---------------------------------------------------------------------------- flat ground for the stops

## Sets the stops' flat ground (flats) from `list` ({edge, s, side, out, along} each).
func set_flats(list: Array) -> void:
	flats.clear()
	_flats_by_block.clear()
	for f: Dictionary in list:
		var e := int(f["edge"])
		var s := float(f["s"])
		var h := heading_at(e, s)
		var g := {"edge": e, "s": s, "side": signf(float(f["side"])), "out": float(f["out"]), "along": float(f["along"]),
			"c": point_at(e, s), "fwd": Vector2(sin(h), -cos(h)), "right": Vector2(cos(h), sin(h)),
			"in": width_of(e) * 0.5 + VERGE + float(f["out"])}
		var reach := Vector2(float(g["along"]), float(g["in"])).length() + BANK_MAX
		g["box"] = Rect2(g["c"], Vector2.ZERO).grow(reach)
		var i := flats.size()
		flats.append(g)
		var box: Rect2 = g["box"]
		var k0 := RoadBlock.key_of(box.position.x, box.position.y)
		var k1 := RoadBlock.key_of(box.end.x, box.end.y)
		for bz in range(k0.y, k1.y + 1):
			for bx in range(k0.x, k1.x + 1):
				var key := Vector2i(bx, bz)
				var list2: PackedInt32Array = _flats_by_block.get(key, PackedInt32Array())
				list2.append(i)
				_flats_by_block[key] = list2


## What the flats of block `k` add to its hash ("" for none).
func flats_hash_of(k: Vector2i) -> String:
	var ids: PackedInt32Array = _flats_by_block.get(k, PackedInt32Array())
	if ids.is_empty():
		return ""
	var text := ""
	for i in ids:
		var f: Dictionary = flats[i]
		text += "|%d,%.1f,%d,%.1f,%.1f" % [int(f["edge"]), float(f["s"]), int(f["side"]), float(f["out"]), float(f["along"])]
	return text.sha1_text().substr(0, 12)


## How far (x, z) is outside a flat `f` (m: 0 inside it), out from its side of the road and along it; INF over the road's
## other side.
static func _flat_out(f: Dictionary, x: float, z: float) -> float:
	var d := Vector2(x, z) - (f["c"] as Vector2)
	var v := d.dot(f["right"]) * float(f["side"])
	if v < 0.0:
		return INF
	return maxf(maxf(absf(d.dot(f["fwd"])) - float(f["along"]), v - float(f["in"])), 0.0)


## The flat ground at (x, z) whose bare ground is `bare`: Vector2(how much it holds the land, 1 inside one easing to 0
## over a road's bank past its edge; the height it holds it to), the strongest.
func _flat_at(x: float, z: float, bare: float) -> Vector2:
	var best := Vector2.ZERO
	for i in _flats_by_block.get(RoadBlock.key_of(x, z), PackedInt32Array()):
		var f: Dictionary = flats[i]
		if not (f["box"] as Rect2).has_point(Vector2(x, z)):
			continue
		var y := road_y(int(f["edge"]), float(f["s"])) - UNDER
		if is_nan(y):
			continue
		var bank := _bank_width(absf(bare - y))
		var t := 1.0 - smoothstep(0.0, bank, _flat_out(f, x, z))
		if t > best.x:
			best = Vector2(t, y)
	return best


## How wide a road's bank is (m past where it starts) where it makes up `rise` m of height.
static func _bank_width(rise: float) -> float:
	return clampf(BANK_BASE + rise * BANK_WIDEN, BANK_MIN, BANK_MAX)


## Whether (x, z) is within `pad` m of a flat (no tree or building stands there).
func in_flat(x: float, z: float, pad := 0.0) -> bool:
	for i in _flats_by_block.get(RoadBlock.key_of(x, z), PackedInt32Array()):
		if _flat_out(flats[i], x, z) <= pad:
			return true
	return false


## The radius about a junction's middle that is all its surface (m): a roundabout's ring out to its outer edge.
static func _inner(j: Dictionary) -> float:
	if j["kind"] in ["roundabout", "mini"]:
		return float(j["ring_r"]) + float(j["ring_w"]) * 0.5
	return 0.0


## The land's height at (x, z) with the roads cut in, from the bare ground `bare` there: see road-block.md. Under a
## carriageway or its verges it's the road's, just under its deck (the lowest, where two overlap); further out each
## road near holds it to its own height as much as its bank says, the nearest holding it most.
func ground_at(x: float, z: float, bare: float) -> float:
	if is_nan(bare):
		return bare
	var p := Vector2(x, z)
	var most := 0.0
	var sum_w := 0.0
	var sum_y := 0.0
	var deck := INF
	var below := INF   # (the lowest road within LAND_PAD of its verge: no land there is higher, see LAND_PAD)
	var near := _near_at(x, z)
	var cands: PackedInt32Array = near[0]
	for c in cands.size():
		var ei := cands[c]
		var pr := _project(ei, p, near[1][c])
		var off := float(pr[2]) - width_of(ei) * 0.5 - VERGE
		if off > BANK_MAX + LAND_PAD:
			continue
		var y := road_y(ei, float(pr[0])) - UNDER
		if is_nan(y):
			continue   # (no ground under it yet)
		# (out on a bridge the land is left as it is under the deck, and only kept below it)
		var on_bridge := bridge_at(ei, float(pr[0]))
		if off <= 0.0:
			if on_bridge >= 1.0:
				below = minf(below, y - BRIDGE_DEPTH)
			else:
				deck = minf(deck, lerpf(y, minf(bare, y - BRIDGE_DEPTH), on_bridge))
			continue
		if off < LAND_PAD:
			below = minf(below, y - BRIDGE_DEPTH * on_bridge)
		# (land rising past the road waits LAND_PAD before its bank; land falling away, FALL_PAD)
		var from := FALL_PAD if bare <= y else LAND_PAD
		var t := 1.0 - on_bridge
		if off > from:
			var bank := _bank_width(absf(bare - y))
			t *= 1.0 - smoothstep(from, from + bank, off)
		if t <= 0.0:
			continue
		var w := t * t * t * t   # (so the road it's nearest the bank of has its way)
		most = maxf(most, t)
		sum_w += w
		sum_y += w * y
	if deck < INF:
		return minf(deck, below)
	var land := bare if sum_w <= 0.0 else lerpf(bare, sum_y / sum_w, most)
	if not flats.is_empty():
		var f := _flat_at(x, z, bare)
		if f.x > 0.0:
			land = lerpf(land, f.y, f.x)
	return minf(land, below)


## Whether any road (or a stop's flat ground: flats) shapes the land in `rect` (region frame).
func roads_near(rect: Rect2) -> bool:
	for f: Dictionary in flats:
		if (f["box"] as Rect2).intersects(rect):
			return true
	var k0 := RoadBlock.key_of(rect.position.x, rect.position.y)
	var k1 := RoadBlock.key_of(rect.end.x, rect.end.y)
	for bz in range(k0.y, k1.y + 1):
		for bx in range(k0.x, k1.x + 1):
			var key := Vector2i(bx, bz)
			var o := Vector2(key) * RoadBlock.SIZE
			for c: Vector2i in _grid_of(key):
				if Rect2(o + Vector2(c) * GRID, Vector2(GRID, GRID)).intersects(rect):
					return true
	return false


## The roads of block `key`, laid out (pure: a worker's job).
func block(key: Vector2i) -> RoadBlock:
	return RoadBlock.build(self, key)
