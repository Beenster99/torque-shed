class_name NetRoute
extends RefCounted
## The crew's agreed route on the road graph, for the network ride's sat nav (Ride Anywhere v2, T7), and the way to it
## from wherever a rider is. The crew agree the route before setting off (the planner's pins, RoutePlanner); it's kept
## here as the steps of the region's graph (RealRegion) it takes, each an edge entered from one of its ends. Leaving it
## is the crew's call en route (Shed.adventure "route", see Adventure); a rider who strays meanwhile is shown the way
## back to it, never past the next pin. Once the crew have agreed to leave it, the way is the shortest by road from
## wherever each rider is to the destination.
##
## A directed step's key is its edge * 2, plus 1 when it's entered from the edge's b end (ridden b to a). Distances are
## metres along the graph's lines (RealRegion.edge_len); costs are those metres weighed by the ride's style
## (RoutePlanner.CLASS_COST), as the planner weighed them, so a way back takes the roads the crew would.
##
## Everything here is plain data and pure functions of the region: search runs on a worker thread.

## Bumped whenever how the route is read from the plan changes: it's in the hash every rider's route carries.
const VERSION := 1
## Turning round in the road costs as much as riding this far (m of the dearest road's cost).
const U_TURN := 150.0
## A way back is looked for out to this cost (about this many metres of road); past it, the way to the destination.
const MAX_COST := 40000.0

var region: RealRegion
## The cost a metre of each road class (region.classes), for the ride's style.
var costs := PackedFloat64Array()
## Each step: its edge, the node it's entered from, and the metres and cost along the route at its start (one more
## than there are steps: the last is the route's whole length and cost).
var edges := PackedInt32Array()
var froms := PackedInt32Array()
var at_m := PackedFloat64Array()
var at_c := PackedFloat64Array()
## Per step, the step its leg ends at (the first step after the next pin): a way back never rejoins past it.
var leg_end := PackedInt32Array()
## The steps that reach the destination (the last pin); past it, the run-out.
var dest_step := 0
var dest_node := -1
## 12 hex of VERSION, the region's hash and the steps: the same on every machine with the same plan.
var hash := ""
var _steps_of := {}   # directed key -> PackedInt32Array of the steps that ride it (an edge may be ridden twice)


## The route of `pack` (planned on `region`, see RoutePlanner) in style `mode`, or null for a pack with no steps.
static func of_pack(pack: RealPack, r: RealRegion, mode := "main") -> NetRoute:
	if pack == null or r == null or pack.steps.size() < 3:
		return null
	var list: Array[Vector2i] = []
	for k in range(0, pack.steps.size() - 2, 3):
		list.append(Vector2i(pack.steps[k + 1], pack.steps[k]))
	return NetRoute.new(r, list, pack.pin_nodes, pack.run_start, mode)


## A route over `r` of `steps` (each Vector2i(edge, from node)), through the pins' nodes `pins` (the first is where
## it starts), reaching the last pin after `run_start` steps.
func _init(r: RealRegion, steps: Array[Vector2i], pins := PackedInt32Array(), run_start := -1, mode := "main") -> void:
	region = r
	costs = costs_of(r, mode)
	var m := 0.0
	var c := 0.0
	var text := "%d|%s" % [VERSION, r.hash]
	for st in steps:
		var i := edges.size()
		edges.append(st.x)
		froms.append(st.y)
		at_m.append(m)
		at_c.append(c)
		m += r.edge_len[st.x]
		c += r.edge_len[st.x] * costs[r.edge_class[st.x]]
		var k := key_of(r, st.x, st.y)
		var list: PackedInt32Array = _steps_of.get(k, PackedInt32Array())
		list.append(i)
		_steps_of[k] = list
		text += "|%d" % k
	at_m.append(m)
	at_c.append(c)
	var n := edges.size()
	dest_step = clampi(run_start if run_start >= 0 else n, 1, n) if n > 0 else 0
	dest_node = to_node(dest_step - 1) if n > 0 else -1
	hash = text.sha1_text().substr(0, 12)
	# Each pin's leg ends at the step after the one that reaches it (a pin the planner left off, a spur it trimmed,
	# is passed by).
	var ends := PackedInt32Array()
	var j := 0
	for p in range(1, pins.size()):
		var at := j
		while at < dest_step and to_node(at) != pins[p]:
			at += 1
		if at < dest_step:
			ends.append(at + 1)
			j = at + 1
	if ends.is_empty() or ends[ends.size() - 1] < dest_step:
		ends.append(dest_step)
	ends.append(n)
	leg_end.resize(n)
	var e := 0
	for i in n:
		while i >= ends[e]:
			e += 1
		leg_end[i] = ends[e]


## The cost a metre of each of `r`'s road classes in style `mode` (RoutePlanner.CLASS_COST).
static func costs_of(r: RealRegion, mode: String) -> PackedFloat64Array:
	var table: Dictionary = RoutePlanner.CLASS_COST.get(mode, RoutePlanner.CLASS_COST["main"])
	var out := PackedFloat64Array()
	for cls in r.classes:
		out.append(float(table.get(str(cls), 1.5)))
	return out


## A directed step's key: edge `edge` entered from node `from`.
static func key_of(r: RealRegion, edge: int, from: int) -> int:
	return edge * 2 + (0 if r.edge_a[edge] == from else 1)


## The node step `i` ends at.
func to_node(i: int) -> int:
	return region.other_end(edges[i], froms[i])


func size() -> int:
	return edges.size()


## The steps that ride edge `edge` entered from node `from`, in order.
func steps_of(edge: int, from: int) -> PackedInt32Array:
	return _steps_of.get(key_of(region, edge, from), PackedInt32Array())


## The first of the steps riding `edge` from `from` at or after `lo` and before `hi`, or -1.
func step_in(edge: int, from: int, lo: int, hi: int) -> int:
	for i in steps_of(edge, from):
		if i >= lo and i < hi:
			return i
	return -1


## The metres along the route of the point `s` m along edge `edge` (from its a end) on step `i`.
func metres_at(i: int, s: float) -> float:
	var e := edges[i]
	return at_m[i] + (s if froms[i] == region.edge_a[e] else region.edge_len[e] - s)


## The metres along the route of a point `s` m along edge `edge` that's on it, the one nearest `guess` m along when
## the route rides that edge more than once; -1 when the route never rides it.
func metres_on(edge: int, s: float, guess := 0.0) -> float:
	var best := -1.0
	for from in [region.edge_a[edge], region.edge_b[edge]]:
		for i in steps_of(edge, from):
			var m := metres_at(i, s)
			if best < 0.0 or absf(m - guess) < absf(best - guess):
				best = m
	return best


## Where a way back to the route from step `from_step` on may rejoin it: {key: cost from there to the end of the leg},
## from `from_step` to the end of its leg.
func rejoin_goals(from_step: int) -> Dictionary:
	var out := {}
	if size() == 0:
		return out
	var lo := clampi(from_step, 0, size() - 1)
	var hi := leg_end[lo]
	for i in range(lo, hi):
		var k := key_of(region, edges[i], froms[i])
		if not out.has(k):
			out[k] = at_c[hi] - at_c[i]
	return out


# ---------------------------------------------------------------------------- finding the way

## The cheapest way from a rider `s` m along edge `edge` (from its a end), riding it a to b (`forward`) or b to a, to
## the first of the goals: `enter` {directed key: cost from there on} (riding onto that edge from that end) or `arrive`
## {node: cost from there on}. Turning round where you are costs U_TURN more. One-way roads, banned turns and dead ends
## are kept to. Returns {ok, turn (it starts by turning round), steps: [Vector2i(edge, from)] (the first the edge the
## rider is on, the way they're to ride it; the last the goal's, for an `enter` goal), goal (the key or node reached),
## node_goal (whether it's a node), cost}, or {ok: false} when there's none within `max_cost`.
static func search(r: RealRegion, costs: PackedFloat64Array, edge: int, s: float, forward: bool, enter: Dictionary,
		arrive: Dictionary, max_cost := MAX_COST) -> Dictionary:
	var len := r.edge_len[edge]
	var per_m := costs[r.edge_class[edge]]
	var cheapest := INF
	for c in costs:
		cheapest = minf(cheapest, c)
	var turn_cost := U_TURN * cheapest
	# A* to a single node goal (straight-line distance at the cheapest cost a metre), else Dijkstra.
	var aim := -1
	if enter.is_empty() and arrive.size() == 1:
		aim = int(arrive.keys()[0])
	var aim_pos := r.node_pos[aim] if aim >= 0 else Vector2.ZERO
	var heap := RoutePlanner.Heap.new()
	var dist := {}    # state (edge * 2 + 0 ridden a to b, 1 b to a) -> cost on arriving at its far end
	var came := {}    # state -> the state before it, -1 for a start
	var turned := {}  # start state -> true when it's the way turned round
	var best := INF
	var best_goal := {}
	for d: int in [0, 1]:
		var from := r.edge_a[edge] if d == 0 else r.edge_b[edge]
		if not r.passable(edge, from):
			continue
		var turn := (d == 0) != forward
		var c := ((len - s) if d == 0 else s) * per_m + (turn_cost if turn else 0.0)
		var st := edge * 2 + d
		# On a goal's edge already, the right way (or once turned round).
		if enter.has(st):
			var g := (turn_cost if turn else 0.0) + float(enter[st]) - (s if d == 0 else len - s) * per_m
			if g < best:
				best = g
				best_goal = {"state": st, "via": -1, "key": st, "turn": turn}
		dist[st] = c
		came[st] = -1
		if turn:
			turned[st] = true
		heap.push(c + _h(r, st, aim, aim_pos, cheapest), st)
	var done := {}
	while not heap.is_empty():
		var st := heap.pop()
		if heap.top_cost >= best:
			break
		if done.has(st):
			continue
		done[st] = true
		var c := float(dist[st])
		if c > max_cost:
			continue
		var e := st / 2
		var n := r.edge_b[e] if st % 2 == 0 else r.edge_a[e]
		if arrive.has(n) and c + float(arrive[n]) < best:
			best = c + float(arrive[n])
			best_goal = {"state": st, "via": -1, "node": n}
		var dead_end := r.adjacent[n].size() == 1
		for e2 in r.adjacent[n]:
			if (e2 == e and not dead_end) or not r.passable(e2, n) or r.turn_banned(e, n, e2):
				continue
			var d2 := 0 if r.edge_a[e2] == n else 1
			var st2 := e2 * 2 + d2
			var c2 := c + (turn_cost if e2 == e else 0.0)
			if enter.has(st2) and c2 + float(enter[st2]) < best:
				best = c2 + float(enter[st2])
				best_goal = {"state": st, "via": st2, "key": st2}
			c2 += r.edge_len[e2] * costs[r.edge_class[e2]]
			if c2 < float(dist.get(st2, INF)):
				dist[st2] = c2
				came[st2] = st
				heap.push(c2 + _h(r, st2, aim, aim_pos, cheapest), st2)
	if best_goal.is_empty():
		return {"ok": false}
	# Back from the goal to the start.
	var chain: Array[int] = []
	var at := int(best_goal["state"])
	if best_goal.has("turn"):
		chain = [at]
	else:
		while at >= 0:
			chain.push_front(at)
			at = int(came[at])
		if int(best_goal["via"]) >= 0:
			chain.append(int(best_goal["via"]))
	var steps: Array[Vector2i] = []
	for x in chain:
		var e := x / 2
		steps.append(Vector2i(e, r.edge_a[e] if x % 2 == 0 else r.edge_b[e]))
	var out := {"ok": true, "turn": turned.has(chain[0]) or bool(best_goal.get("turn", false)), "steps": steps, "cost": best}
	if best_goal.has("node"):
		out["goal"] = int(best_goal["node"])
		out["node_goal"] = true
	else:
		out["goal"] = int(best_goal["key"])
		out["node_goal"] = false
	return out


## The A* estimate from state `st`'s far end to node `aim` (0 with none).
static func _h(r: RealRegion, st: int, aim: int, aim_pos: Vector2, per_m: float) -> float:
	if aim < 0:
		return 0.0
	var e := st / 2
	var n := r.edge_b[e] if st % 2 == 0 else r.edge_a[e]
	return r.node_pos[n].distance_to(aim_pos) * per_m
