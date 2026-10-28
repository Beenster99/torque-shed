extends RefCounted
## The network ride's sat nav (NetRoute, NetNav: Ride Anywhere v2 T7), run from tests/run_tests.gd: its _test_net_*
## functions hand over to these. Small graphs of their own (as tests/road_block_tests.gd's), no scene.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A grid of streets 300 m apart, five across and three down (node = row * 5 + col, at (col * 300, row * 300): row 0
## the north), the top row a main road, and one more node east of the bottom right corner (15) for a run-out. `oneway`
## {Vector2i(a, b): 1 or -1} makes those streets one-way.
static func grid(oneway := {}) -> RealRegion:
	var nodes := []
	for row in 3:
		for col in 5:
			nodes.append([col * 300, row * 300])
	nodes.append([1500, 600])
	var edges := []
	for row in 3:
		for col in 4:
			var a := row * 5 + col
			edges.append([a, a + 1, "primary" if row == 0 else "secondary", int(oneway.get(Vector2i(a, a + 1), 0))])
	for row in 2:
		for col in 5:
			var a := row * 5 + col
			edges.append([a, a + 5, "secondary", int(oneway.get(Vector2i(a, a + 5), 0))])
	edges.append([14, 15, "secondary"])
	return Roads.graph(nodes, edges)


## The edge between nodes `a` and `b` of `r`.
static func edge(r: RealRegion, a: int, b: int) -> int:
	for e in r.adjacent[a]:
		if r.other_end(e, a) == b:
			return e
	return -1


## The agreed route over grid(): east along the main road from 0 to 2, south to 7 (the second pin), east to 9, south
## to 14 (the destination), and the run-out on to 15.
static func route_of(r: RealRegion) -> NetRoute:
	var path := [0, 1, 2, 7, 8, 9, 14, 15]
	var steps: Array[Vector2i] = []
	for i in path.size() - 1:
		steps.append(Vector2i(edge(r, path[i], path[i + 1]), path[i]))
	return NetRoute.new(r, steps, PackedInt32Array([0, 7, 14]), 6)


## The route read from a plan: its steps, legs, lengths and hash.
func test_route() -> void:
	var r := grid()
	var rt := route_of(r)
	check(rt.size() == 7 and rt.dest_step == 6 and rt.dest_node == 14, "seven steps, the destination after six (%d, %d)" % [rt.dest_step, rt.dest_node])
	check(Array(rt.leg_end) == [3, 3, 3, 6, 6, 6, 7], "each leg ends past its pin (%s)" % str(rt.leg_end))
	check(is_equal_approx(rt.at_m[1], 300.0) and is_equal_approx(rt.at_m[6], 1800.0), "metres along it")
	check(rt.at_c[3] - rt.at_c[2] > rt.at_c[1], "its costs: a side street dearer a metre than the main road")
	check(rt.hash.length() == 12 and rt.hash == route_of(grid()).hash, "a 12 hex hash, the same for the same route")
	var other: Array[Vector2i] = [Vector2i(edge(r, 0, 5), 0)]
	check(NetRoute.new(r, other).hash != rt.hash, "and another for another")
	check(rt.step_in(edge(r, 2, 7), 2, 0, 7) == 2 and rt.step_in(edge(r, 2, 7), 7, 0, 7) == -1, "a step ridden one way, not the other")
	check(is_equal_approx(rt.metres_on(edge(r, 7, 8), 100.0), 1000.0), "metres along the route of a point on it")
	var goals := rt.rejoin_goals(1)
	check(goals.size() == 2 and goals.has(NetRoute.key_of(r, edge(r, 1, 2), 1)) and goals.has(NetRoute.key_of(r, edge(r, 2, 7), 2)),
		"a way back from step 1 may rejoin at steps 1 and 2, not past the pin")
	check(float(goals[NetRoute.key_of(r, edge(r, 1, 2), 1)]) > float(goals[NetRoute.key_of(r, edge(r, 2, 7), 2)]), "rejoining sooner leaves more to ride")


## Finding the way: back to the route, turning round where that's quicker, never past the next pin, to the destination
## once the crew leave the route, and keeping to one-way streets.
func test_search() -> void:
	var r := grid()
	var rt := route_of(r)
	var side := edge(r, 5, 6)
	# Heading east along the street below the main road, just past the corner.
	var res := NetRoute.search(r, rt.costs, side, 100.0, true, rt.rejoin_goals(1), {})
	var want: Array[Vector2i] = [Vector2i(side, 5), Vector2i(edge(r, 1, 6), 6), Vector2i(edge(r, 1, 2), 1)]
	check(res["ok"] and not res["turn"] and res["steps"] == want, "on along the street, up to the main road and back on the route there (%s)" % str(res.get("steps")))
	# Heading west, nearly at the next corner: quicker to turn round.
	res = NetRoute.search(r, rt.costs, side, 280.0, false, rt.rejoin_goals(1), {})
	check(res["ok"] and res["turn"] and res["steps"][0] == Vector2i(side, 5), "facing away, near the way back: turn around (%s)" % str(res.get("steps")))
	# Just past the corner heading west: on round the block is quicker.
	res = NetRoute.search(r, rt.costs, side, 20.0, false, rt.rejoin_goals(1), {})
	check(res["ok"] and not res["turn"] and res["steps"][0] == Vector2i(side, 6), "facing away, the corner just behind: on round the block, no turning (%s)" % str(res.get("steps")))
	# Ahead of the second pin, heading south: back to it, not on to the route past it.
	var past := [NetRoute.key_of(r, edge(r, 7, 8), 7), NetRoute.key_of(r, edge(r, 8, 9), 8)]
	res = NetRoute.search(r, rt.costs, edge(r, 3, 8), 150.0, true, rt.rejoin_goals(1), {})
	var last: Vector2i = res["steps"][res["steps"].size() - 1] if res["ok"] else Vector2i(-1, -1)
	check(res["ok"] and last == Vector2i(edge(r, 2, 7), 2) and int(res["goal"]) == NetRoute.key_of(r, edge(r, 2, 7), 2),
		"past the route near the second pin: back to the route before it (%s)" % str(res.get("steps")))
	check(res["ok"] and (res["steps"] as Array).all(func(s): return not past.has(NetRoute.key_of(r, s.x, s.y))), "never rejoining past the pin")
	# The crew have left the route: the shortest way to the destination.
	res = NetRoute.search(r, rt.costs, side, 100.0, true, {}, {14: 0.0})
	var end: Vector2i = res["steps"][res["steps"].size() - 1] if res["ok"] else Vector2i(-1, -1)
	check(res["ok"] and res["node_goal"] and int(res["goal"]) == 14 and r.other_end(end.x, end.y) == 14 and res["steps"].size() == 5,
		"free: the shortest way to the destination (%s)" % str(res.get("steps")))
	# One-way streets kept to.
	var ow := grid({Vector2i(6, 7): -1, Vector2i(11, 12): -1})
	var rt2 := route_of(ow)
	res = NetRoute.search(ow, rt2.costs, edge(ow, 5, 6), 100.0, true, {}, {14: 0.0})
	check(res["ok"] and (res["steps"] as Array).all(func(s): return ow.passable(s.x, s.y)), "never the wrong way down a one-way street (%s)" % str(res.get("steps")))
	check(res["ok"] and not (res["steps"] as Array).has(Vector2i(edge(ow, 6, 7), 6)), "so not 6 to 7 here")
	check(not NetRoute.search(r, rt.costs, side, 100.0, true, {}, {})["ok"], "no goal: no way")


## What the sat nav says at the junctions: left and right, nothing on along the main road, and a roundabout's exits
## counted round the way it's ridden.
func test_junctions() -> void:
	var r := grid()
	var net := RoadNet.new(r, Roads.flat)
	var rt := route_of(r)
	var steps: Array[Vector2i] = []
	for i in rt.size():
		steps.append(Vector2i(rt.edges[i], rt.froms[i]))
	check(NetNav.instruction(net, steps, 0).is_empty(), "nothing to say on along the main road")
	var right := NetNav.instruction(net, steps, 1)
	check(str(right.get("text", "")) == "Turn right" and float(right.get("turn", 0.0)) > 1.0, "off the main road south: turn right (%s)" % str(right))
	var left := NetNav.instruction(net, steps, 2)
	check(str(left.get("text", "")) == "Turn left" and left["type"] == "cross", "south then east at a crossroads: turn left (%s)" % str(left))
	var ra := Roads.roundabout()
	var rn := RoadNet.new(ra, Roads.flat)
	# In from the south (node 10 to ring node 4), clockwise round past the west road, out north.
	var round_steps: Array[Vector2i] = [Vector2i(10, 10), Vector2i(4, 4), Vector2i(5, 5), Vector2i(6, 6), Vector2i(7, 7), Vector2i(8, 0)]
	var at := NetNav.instruction(rn, round_steps, 0)
	check(str(at.get("text", "")) == "At the roundabout, take the 2nd exit" and int(at.get("exit", 0)) == 2, "straight over a roundabout: the 2nd exit (%s)" % str(at))
	var first: Array[Vector2i] = [Vector2i(10, 10), Vector2i(4, 4), Vector2i(5, 5), Vector2i(11, 6)]
	check(int(NetNav.instruction(rn, first, 0).get("exit", 0)) == 1, "the first road off it: the 1st exit")
	check(NetNav.instruction(rn, round_steps, 2).is_empty(), "nothing to say round the ring")


## The sat nav following a rider: on the route, facing the wrong way, off it and back on it, and free once the crew
## leave it.
func test_nav() -> void:
	var r := grid()
	var net := RoadNet.new(r, Roads.flat)
	var nav := NetNav.new(null, net, route_of(r))
	nav.threaded = false
	var was: Dictionary = Shed.adventure
	Shed.adventure = {}
	var east := Vector2(1, 0)
	nav.update(Vector2(450, 0), east)
	check(nav.status == "on_route" and nav.progress == 1 and not nav.wrong, "on the main road heading east: on the route, step 1 (%s %d)" % [nav.status, nav.progress])
	check(absf(nav.to_go() - 1350.0) < 1.0, "1350 m to go (%.0f)" % nav.to_go())
	var j := nav.next_junction(400.0)
	check(str(j.get("text", "")) == "Turn right" and absf(float(j["distance"]) - 150.0) < 1.0, "turn right in 150 m (%s)" % str(j))
	_next_frame(nav)
	nav.update(Vector2(460, 0), -east)
	check(nav.status == "on_route" and nav.wrong, "turned round on the route: the wrong way")
	_next_frame(nav)
	nav.update(Vector2(100, 300), east)
	check(nav.status == "back" and not nav.wrong and nav.rejoin == 1 and nav.way.size() == 3, "off down a side street: the way back, rejoining at step 1 (%s %d)" % [nav.status, nav.rejoin])
	var line := nav.line_ahead(250.0)
	check(line.size() > 2 and line[0].distance_to(Vector2(100, 300)) < 1.0 and line[line.size() - 1].distance_to(Vector2(300, 250)) < 10.0,
		"the way ahead drawn from the rider round the corner (%s)" % str(line[line.size() - 1] if not line.is_empty() else null))
	check(absf(nav.to_go() - (200.0 + 300.0 + 1500.0)) < 1.0, "to go along the way back and on (%.0f)" % nav.to_go())
	check(nav.news() == "", "nothing to say yet")
	_next_frame(nav)
	nav.update(Vector2(300, 150), Vector2(0, -1))
	check(nav.status == "back" and nav.way_at == 1, "following the way")
	_next_frame(nav)
	nav.update(Vector2(400, 0), east)
	check(nav.status == "on_route" and nav.way.is_empty() and nav.news() == "Back on route", "back on the route: \"Back on route\"")
	_next_frame(nav)
	Shed.adventure = {"route": {"mode": "free"}}
	nav.update(Vector2(410, 0), east)
	check(nav.status == "free" and nav.rejoin == -1 and r.other_end(nav.way[-1].x, nav.way[-1].y) == 14, "the crew left the route: the way to the destination (%s)" % nav.status)
	check(absf(nav.to_go() - 1390.0) < 1.0, "and how far that is: on along the main road, the cheaper (%.0f)" % nav.to_go())
	_next_frame(nav)
	Shed.adventure = {}
	nav.update(Vector2(1000, 300), east)
	check(nav.status == "on_route" and nav.progress == 4, "the crew back on the route: on it from where you are (%d)" % nav.progress)
	Shed.adventure = was


## The route a real plan rides on its region's graph: joined end to end, from the first pin to the last.
func test_plan() -> void:
	var plan := AdventurePlans.tour("dales", 3)
	var pack := AdventurePlans.pack_for(plan)
	var region := RealRegion.get_region("dales")
	var rt := NetRoute.of_pack(pack, region)
	check(rt != null and rt.size() > 10, "the plan's route on the graph (%d steps)" % (rt.size() if rt else 0))
	if rt == null:
		return
	var joined := true
	for i in range(1, rt.size()):
		joined = joined and rt.froms[i] == rt.to_node(i - 1)
	check(joined, "each step starts where the last ended")
	check(rt.froms[0] == pack.pin_nodes[0] and rt.dest_node == pack.pin_nodes[pack.pin_nodes.size() - 1], "from the first pin to the last")
	var km := rt.at_m[rt.dest_step] / 1000.0
	check(absf(km - pack.length_m / 1000.0 + pack.run_out_m / 1000.0) < km * 0.08, "as long as the planned road, near enough (%.1f km, %.1f)" % [km, (pack.length_m - pack.run_out_m) / 1000.0])


## The sat nav on a real network ride (the Dales, as tests/road_block_tests.gd's test_ride): on the route at the start,
## and taken half a kilometre off it, the way back.
func test_world() -> void:
	var plan := AdventurePlans.tour("dales", 3)
	var region := RealRegion.get_region("dales")
	var was := AdventureWorld.network
	AdventureWorld.network = true
	var w := AdventureWorld.new()
	w.roads_region = region
	w.setup(AdventurePlans.pack_for(plan), 1)
	AdventureWorld.network = was
	RealLand.roam = false   # (set by a network ride's setup: not for the tests after this one)
	var nav := NetNav.new(w)
	nav.threaded = false
	check(nav.route != null and nav.net == w.roads.net, "the network ride's sat nav has the crew's route on the graph")
	if nav.route == null:
		w.free()
		return
	var xf := w.start_xf(0)
	var at := Vector2(xf.origin.x, xf.origin.z)
	var fwd := Vector2(-xf.basis.z.x, -xf.basis.z.z).normalized()
	var guide := nav.satnav_guide(at, fwd)
	check(nav.status == "on_route" and not bool(guide.get("wrong_way", true)) and nav.progress < 5, "at the start: on the route, the right way (%s, step %d)" % [nav.status, nav.progress])
	var whole := nav.to_go()
	check(absf(whole - (w.route.length - 48.0)) < w.route.length * 0.08, "the whole way to go (%.1f km of %.1f)" % [whole / 1000.0, w.route.length / 1000.0])
	check(nav.satnav_roads(at, 300.0).size() >= 1 and nav.satnav_route(at, fwd, 600.0).size() >= 10, "the roads round you and the way ahead")
	check(nav.satnav_points(at, fwd).any(func(p): return p["kind"] == "destination"), "the destination on it")
	# A junction off the route, between 400 m and 3 km from the start, and a little way along a road out of it.
	var on_route := {}
	for i in nav.route.size():
		on_route[nav.route.froms[i]] = true
	var start := Vector2(w.route.px[0], w.route.pz[0])
	var off := Vector2.INF
	var head := 0.0
	for n in region.node_count():
		var p := region.node_pos[n]
		if on_route.has(n) or region.adjacent[n].size() < 3 or p.distance_to(start) > 3000.0:
			continue
		var near := w.route.locate(p.x, p.y)
		if not near.is_empty() and absf(float(near["lat"])) < 400.0:
			continue
		var e := region.adjacent[n][0]
		var s := minf(60.0, region.edge_len[e] * 0.5)
		s = s if region.edge_a[e] == n else region.edge_len[e] - s
		off = nav.net.point_at(e, s)
		head = nav.net.heading_at(e, s)
		break
	check(off != Vector2.INF, "a road well off the route")
	if off != Vector2.INF:
		var l := w.to_local_pos(off.x, 0.0, off.y)
		_next_frame(nav)
		guide = nav.satnav_guide(Vector2(l.x, l.z), Vector2(sin(head), -cos(head)))
		check(nav.status == "back" and nav.rejoin >= 0 and nav.way.size() >= 1, "off the route: the way back to it (%s, %d steps)" % [nav.status, nav.way.size()])
		check(nav.to_go() > 0.0, "and how far it is from there (%.1f km)" % (nav.to_go() / 1000.0))
	nav.stop()
	w.free()


## Moves the nav's frame on, as a frame would (it works out where you are once a frame).
static func _next_frame(nav: NetNav) -> void:
	nav._memo = Vector3(-1, INF, INF)


## The stops' flat ground on the network (RoadNet.set_flats): the land in one levelled to the road, banked out past it
## and left as it was on the road's other side, no building in it, and its blocks' hash telling them apart.
func test_flats() -> void:
	var r := Roads.graph([[0, 100], [600, 100]], [[0, 1, "primary"]])
	var slope := func(_x: float, z: float) -> float: return 10.0 + (z - 100.0) * 0.5   # (rising to the south)
	var plain := RoadNet.new(r, slope)
	var net := RoadNet.new(r, slope)
	net.set_flats([{"edge": 0, "s": 300.0, "side": 1, "out": 40.0, "along": 40.0}])
	var y := net.road_y(0, 300.0) - RoadNet.UNDER
	var w := net.width_of(0) * 0.5 + RoadNet.VERGE
	var inside := Vector2(320.0, 100.0 + w + 35.0)
	var bare: float = slope.call(inside.x, inside.y)
	check(absf(net.ground_at(inside.x, inside.y, bare) - y) < 0.01 and plain.ground_at(inside.x, inside.y, bare) > y + 3.0,
		"in the flat, the land is level with the road (%.2f, %.2f without)" % [net.ground_at(inside.x, inside.y, bare), plain.ground_at(inside.x, inside.y, bare)])
	var edge := Vector2(300.0, 100.0 + w + 40.0 + 6.0)
	var e_bare: float = slope.call(edge.x, edge.y)
	var at_edge := net.ground_at(edge.x, edge.y, e_bare)
	check(at_edge > y + 0.1 and at_edge < plain.ground_at(edge.x, edge.y, e_bare), "just past it, banked up from it")
	for p: Vector2 in [Vector2(300.0, 100.0 - w - 20.0), Vector2(300.0, 100.0 + 200.0), Vector2(520.0, 100.0 + w + 35.0)]:
		var b: float = slope.call(p.x, p.y)
		check(is_equal_approx(net.ground_at(p.x, p.y, b), plain.ground_at(p.x, p.y, b)), "the land as it was at %s" % str(p))
	check(net.in_flat(inside.x, inside.y) and not net.in_flat(300.0, 100.0 - w - 20.0), "in_flat in it, not over the road")
	check(net.roads_near(Rect2(inside, Vector2.ONE)), "the land under it is shaped by the net")
	var k := RoadBlock.key_of(inside.x, inside.y)
	check(net.block(k).hash != plain.block(k).hash and net.block(Vector2i(5, 5)).hash == plain.block(Vector2i(5, 5)).hash,
		"a block with a flat in hashes apart, one without as before")


## The planned ride's places on the network ride (NetSites): every stop, fuel station, the start and the destination
## placed on a road (moved a little at most), the straight ones mostly, the ground beside a stop level with its road,
## and each built into its block once that's in.
func test_sites() -> void:
	var plan := AdventurePlans.tour("dales", 3)
	var region := RealRegion.get_region("dales")
	var planned := AdventureRoute.new()
	var pack := AdventurePlans.pack_for(plan)
	planned.plan_real(pack, 1, pack.max_km())
	var was := AdventureWorld.network
	AdventureWorld.network = true
	var w := AdventureWorld.new()
	w.roads_region = region
	w.setup(AdventurePlans.pack_for(plan), 1)
	AdventureWorld.network = was
	RealLand.roam = false
	var ns := w.net_sites
	check(ns != null and ns.places.size() > 3 and ns.hash.length() == 12, "the ride's places on the network (%d)" % (ns.places.size() if ns else 0))
	if ns == null:
		w.free()
		return
	var want := 0
	for st: Dictionary in planned.sites:
		if not NetSites.SKIP.has(str(st["kind"])):
			want += 1
	var placed := {}
	for p: Dictionary in ns.places:
		placed[str(p["site"]["kind"])] = int(placed.get(str(p["site"]["kind"]), 0)) + 1
	check(ns.places.size() >= want - 1 and placed.has("start") and placed.has("finish") and placed.has("fuel"),
		"all of them placed (%d of %d: %s)" % [ns.places.size(), want, str(placed)])
	var moved := 0.0
	var straight := 0
	for a: Dictionary in planned.sites:
		var near := INF
		for b: Dictionary in w.route.sites:
			if b["kind"] == a["kind"] and b["name"] == a["name"] and int(b.get("seed", 0)) == int(a.get("seed", 0)):
				near = minf(near, absf(float(b["s"]) - float(a["s"])))
		moved = maxf(moved, near)
	for p: Dictionary in ns.places:
		if float(p["bow"]) <= NetSites.BOW:
			straight += 1
	check(moved <= NetSites.NUDGE + 0.1, "none moved further than %d m (%.0f)" % [NetSites.NUDGE, moved])
	check(straight >= ns.places.size() * 0.7, "most on straight road (%d of %d)" % [straight, ns.places.size()])
	# The first stop: its ground, and it built into its block.
	var at := -1
	for i in ns.places.size():
		if AdventureStops.KINDS.has(str(ns.places[i]["site"]["kind"])):
			at = i
			break
	check(at >= 0, "a stop on the ride")
	if at >= 0:
		var p: Dictionary = ns.places[at]
		var net := w.roads.net
		var c := net.point_at(int(p["edge"]), float(p["s"]))
		w.roads.preload_round([c], 300.0)
		var y := net.road_y(int(p["edge"]), float(p["s"]))
		var xf := NetSites.frame_of(net, p, Vector2.ZERO)
		var out := xf.origin + xf.basis.x * 8.0
		var g := net.ground_at(out.x, out.z, float(net.height.call(out.x, out.z)))
		check(not is_nan(y) and absf(g - (y - RoadNet.UNDER)) < 0.05, "the ground beside it level with its road (%.2f, %.2f)" % [g, y])
		ns.build_some(100)
		var node = ns._built.get(at)
		check(node is Node3D and (node as Node).get_parent() == w.roads.blocks.get(p["key"]), "built into its block")
		if node is Node3D:
			var spots := 0
			for n: Node in (node as Node).find_children("*", "", true, false):
				if n.is_in_group(AdventureStops.SEAT_GROUP) or n.is_in_group(AdventureStops.COUNTER_GROUP):
					spots += 1
			check(spots > 0 or str(p["site"]["kind"]) == "layby", "with somewhere to sit or buy food (%d)" % spots)
			check(ns.build_some(100) == 0, "and not built again")
		# Slept at it: woken on the road beside it, facing on along the route, the next rider a bike length back.
		var bed := [xf.origin.x + xf.basis.x.x * 10.0, xf.origin.z + xf.basis.x.z * 10.0, 0.0]
		var wake = w.net_wake_xf(bed, 0)
		var wake2 = w.net_wake_xf(bed, 1)
		check(wake is Transform3D and wake2 is Transform3D, "woken on the network road by the stop")
		if wake is Transform3D and wake2 is Transform3D:
			var xz := w.route_xz((wake as Transform3D).origin)
			var on := net.locate(xz[0], xz[1])
			var fwd := -(wake as Transform3D).basis.z
			var rh := w.route.heading_at_s(float(p["site"]["s"]))
			check(not on.is_empty() and bool(on["on_road"]) and float(on["lat"]) * (1.0 if int(p["dir"]) > 0 else -1.0) < 0.0,
				"on the road's left half (%s)" % str(on.get("lat")))
			check(Vector2(fwd.x, fwd.z).dot(Vector2(sin(rh), -cos(rh))) > 0.7, "facing on along the route")
			check(absf((wake as Transform3D).origin.distance_to((wake2 as Transform3D).origin) - 4.0) < 0.5, "the next a bike length back")
	w.free()


## A night's save on the network ride keeps where each rider's bed is, and carries it on.
func test_saves() -> void:
	var was_adv: Dictionary = Shed.adventure
	var was_crew: Dictionary = Shed.crew
	Shed.crew = {1: {"name": "Sam"}, 2: {"name": "Jo"}}
	Shed.adventure = {"id": 7, "seed": 3, "km": 40.0, "needs": {1: {"food": 0.5, "drink": 0.5, "rest": 0.2, "bed": "inn:1", "bed_s": 12000.0,
		"bed_at": [1500.25, -320.5, 1.2]}, 2: {"food": 0.6, "drink": 0.6, "rest": 0.3, "bed": "inn:2", "bed_s": 12004.0}}}
	var save := AdventureNeeds.sanitize_save(AdventureNeeds.make_save())
	check((save["where"] as Dictionary).size() == 1 and save["where"]["Sam"] == [1500.25, -320.5, 1.2], "Sam's bed kept where it is (%s)" % str(save["where"]))
	check(not (save["adventure"] as Dictionary).has("needs"), "the road kept, not the meters as they ran")
	var bad := save.duplicate(true)
	bad["where"] = {"Sam": [1.0, NAN, 0.0], "Jo": "inn"}
	check((AdventureNeeds.sanitize_save(bad)["where"] as Dictionary).is_empty(), "a bed's place that isn't one is dropped")
	Shed.adventure = {"id": 8, "resume": save["at"], "resume_at": save["where"]}
	check(AdventureNeeds.resume_at("Sam") == [1500.25, -320.5, 1.2] and AdventureNeeds.resume_at("Jo").is_empty(),
		"carried on: Sam wakes where the bed was, Jo by the road's distance")
	check(is_equal_approx(AdventureNeeds.resume_s("Jo"), 12004.0), "Jo at %.0f m" % AdventureNeeds.resume_s("Jo"))
	Shed.adventure = was_adv
	Shed.crew = was_crew


## The loading card while a ride gets ready (RideLoading): each step's share of the bar, and the roads round the start
## built without holding the game up, counted out as they're laid (RoadStreamer.preload_round_async), till the
## ground's there to ride on.
func test_loading() -> void:
	var card := RideLoading.new()
	t.add_child(card)
	card.show_step(3, 40, 120)
	check(absf(card.fraction() - (0.15 + 0.08 + 0.07 + 0.35 / 3.0)) < 0.002 and card.detail_text().contains("40 of 120"),
		"shaping the land, 40 of 120 tiles: the bar %.0f%% along (\"%s\")" % [card.fraction() * 100.0, card.detail_text()])
	card.show_step(RideLoading.SET_DOWN)
	check(card.fraction() > 0.94 and card.fraction() < 0.96, "and nearly full setting you down at the start")
	card.queue_free()
	var plan := AdventurePlans.tour("dales", 3)
	var was := AdventureWorld.network
	AdventureWorld.network = true
	var w := AdventureWorld.new()
	w.roads_region = RealRegion.get_region("dales")
	w.setup(AdventurePlans.pack_for(plan), 1)
	AdventureWorld.network = was
	RealLand.roam = false
	t.add_child(w)
	var seen: Array = []
	var frames := [0]
	var count_frames := func(): frames[0] += 1
	t.get_tree().process_frame.connect(count_frames)
	await w.preload_range_async(0.0, 420.0, func(done: int, total: int): seen.append([done, total]))
	t.get_tree().process_frame.disconnect(count_frames)
	var rising := true
	for i in range(1, seen.size()):
		rising = rising and int(seen[i][0]) >= int(seen[i - 1][0])
	check(not seen.is_empty() and rising and int(seen[-1][0]) == int(seen[-1][1]) and int(seen[-1][1]) > 0,
		"the roads round the start counted out as they're built (%d reports, %s at the end)" % [seen.size(), str(seen[-1]) if not seen.is_empty() else "none"])
	check(frames[0] >= 2, "the game kept going while they were (%d frames)" % frames[0])
	check(w.has_ground(10.0) and w.has_ground(400.0), "and the ground's there to ride on at the start")
	w.queue_free()
	await t.get_tree().process_frame
