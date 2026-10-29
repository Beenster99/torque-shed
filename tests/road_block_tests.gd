extends RefCounted
## The road network's checks (RoadNet and RoadBlock, Ride Anywhere v2 T6), run from tests/run_tests.gd: its
## _test_road_* functions hand over to these. Small graphs of their own, no scene and no network.
## test_interface pins ride-anywhere-v2/interfaces/road-block.md: change one, change the other.

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A region of `nodes` ([x, z]) and `edges` ([a, b, class, oneway?, [x, z, ...] between?]).
static func graph(nodes: Array, edges: Array) -> RealRegion:
	var classes := ["primary", "secondary", "tertiary", "residential", "track"]
	var rows := []
	for e: Array in edges:
		rows.append({"a": e[0], "b": e[1], "c": classes.find(e[2]), "s": 0, "l": 0, "n": 0,
			"o": e[3] if e.size() > 3 else 0, "p": e[4] if e.size() > 4 else []})
	var r := RealRegion.from_rows({"classes": classes, "surfaces": ["tarmac"], "names": [""], "nodes": nodes,
		"edges": rows})
	r.hash = "fixture"
	return r


static func flat(_x: float, _z: float) -> float:
	return 10.0


## A main road east to west with a side road off it to the south (a tee at node 0, at 100, 100).
static func tee() -> RealRegion:
	return graph([[100, 100], [-200, 100], [400, 100], [100, 400]],
		[[1, 0, "primary"], [0, 2, "primary"], [0, 3, "residential"]])


## A main road crossing a track (mixed widths).
static func cross() -> RealRegion:
	return graph([[100, 100], [-200, 100], [400, 100], [100, -200], [100, 400]],
		[[1, 0, "primary"], [0, 2, "primary"], [3, 0, "track"], [0, 4, "track"]])


## A roundabout of eight one-way edges, `radius` m from the middle, round (100, 100), with four roads off it.
static func roundabout(radius := 16.0) -> RealRegion:
	var nodes := []
	var edges := []
	for k in 8:
		var a := TAU * k / 8.0
		nodes.append([100.0 + sin(a) * radius, 100.0 - cos(a) * radius])
	for k in 8:
		edges.append([k, (k + 1) % 8, "secondary", 1])
	var outs := [[100, -300], [500, 100], [100, 500], [-300, 100]]
	for k in 4:
		nodes.append(outs[k])
		edges.append([k * 2, 8 + k, "secondary"])
	return graph(nodes, edges)


## A staggered junction: a side road north at x = 80, another south at x = 110, off one main road.
static func staggered() -> RealRegion:
	return graph([[80, 100], [110, 100], [-200, 100], [400, 100], [80, -200], [110, 400]],
		[[2, 0, "primary"], [0, 1, "primary"], [1, 3, "primary"], [0, 4, "residential"], [1, 5, "residential"]])


## Heights along whole roads (RoadNet's height strands): a road runs on through its plain joins and its junctions'
## through road without a kink, smoothed as the planned road is; a side road eases onto the junction.
func test_strands() -> void:
	# A main road west to east over rolling ground, split at a plain join (node 4) and a tee (node 0), a side road south.
	var roll := func(x: float, z: float) -> float: return 60.0 + sin(x * 0.012) * 9.0 + x * 0.02 + maxf(0.0, z - 100.0) * 0.1
	var r := graph([[100, 100], [-400, 100], [600, 100], [100, 400], [-150, 100]],
		[[1, 4, "primary"], [4, 0, "primary"], [0, 2, "primary"], [0, 3, "residential"]])
	var net := RoadNet.new(r, roll)
	var st: Dictionary = net._strand_of(2)
	check(st == net._strand_of(0) and st == net._strand_of(1) and (st["edges"] as PackedInt32Array).size() == 3,
		"the main road is one strand through its plain join and its junction, whichever edge asks first")
	check((net._strand_of(3)["edges"] as PackedInt32Array).size() == 1, "and the side road a strand of its own")
	# Ridden west to east, every 4 m or so: how sharply the grade changes (per metre).
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var run := 0.0
	for e: int in [0, 1, 2]:
		var len := net.length_of(e)
		var steps := int(ceil(len / 4.0))
		for k in range(0 if e == 0 else 1, steps + 1):
			xs.append(run + len * k / steps)
			ys.append(net.road_y(e, len * k / steps))
		run += len
	var bend := 0.0
	for k in range(1, ys.size() - 1):
		var h0 := xs[k] - xs[k - 1]
		var h1 := xs[k + 1] - xs[k]
		bend = maxf(bend, absf(((ys[k + 1] - ys[k]) / h1 - (ys[k] - ys[k - 1]) / h0) * 2.0 / (h0 + h1)))
	check(bend < 0.002, "it rides on through the join and the junction with no kink (the sharpest bend %.4f a metre)" % bend)
	# The side road comes in at the junction's height and eases onto its own over the hill, never sharply.
	var side := net.profile(3)
	var sp := net.length_of(3) / float(side.size() - 1)
	var sharp := 0.0
	for k in range(1, side.size() - 1):
		sharp = maxf(sharp, absf(side[k + 1] - 2.0 * side[k] + side[k - 1]) / (sp * sp))
	check(absf(side[0] - net.node_y(0)) < 0.01 and sharp < 0.003,
		"the side road meets the junction at its height and eases away (the sharpest bend %.4f a metre)" % sharp)
	# Through roads that themselves ease away (onto other roads they end at, nearby): every side road meets each where
	# it is, not where it would be without those eases. A grid of streets on a lumpy hillside: every street ends on
	# another, so the eases chain from junction to junction.
	var lumps := func(x: float, z: float) -> float: return 20.0 + x * 0.05 + sin(x * 0.07) * 4.0 + cos(z * 0.05) * 5.0
	var gn := []
	var ge := []
	for gz in 4:
		for gx in 4:
			gn.append([gx * 90 + (gz % 2) * 25, gz * 80])
	for gz in 4:
		for gx in 4:
			var k := gz * 4 + gx
			if gx < 3:
				ge.append([k, k + 1, "secondary" if gz % 2 == 0 else "residential"])
			if gz < 3:
				ge.append([k, k + 4, "residential" if gx % 2 == 0 else "tertiary"])
	var grid := RoadNet.new(graph(gn, ge), lumps)
	var meet := 0.0
	for n in grid.region.node_count():
		if grid.region.adjacent[n].size() < 3:
			continue
		for ei in grid.region.adjacent[n]:
			meet = maxf(meet, absf(grid.road_y(ei, 0.0 if grid.region.edge_a[ei] == n else grid.length_of(ei)) - grid.node_y(n)))
	check(meet < 0.01, "every road meets its junctions at their height, through roads easing away from them too (%.3f m off at most)" % meet)
	# A side road leaving at a slant comes away level with the road it leaves, so the junction between the two isn't
	# folded across, and only then climbs its own way.
	var hillside := func(x: float, z: float) -> float: return 10.0 + z * 0.12
	var fork := RoadNet.new(graph([[100, 100], [-300, 100], [500, 100], [400, 200]],
		[[1, 0, "primary"], [0, 2, "primary"], [0, 3, "residential"]]), hillside)
	var across := 0.0
	for d in range(10, 30, 2):
		var s := float(d)
		var p := fork.point_at(2, s)
		across = maxf(across, absf(fork.road_y(2, s) - fork._across_y(Vector2i(0, 1), p)) / maxf(fork._project(1, p)[2] - 3.0, 1.0))
	check(across < 0.15, "a side road leaving at a slant keeps near the through road's height while beside it (%.2f m a metre between them at most)" % across)
	# The same where the junction is drawn as one with another just along the road (Simon's step on Route 273 in
	# Kamikawa: the side road came away at its own height, a slab of it over the through road beside it).
	var fork2 := RoadNet.new(graph([[100, 100], [-300, 100], [500, 100], [400, 200], [115, 100], [115, -300]],
		[[1, 0, "primary"], [0, 4, "primary"], [4, 2, "primary"], [0, 3, "residential"], [4, 5, "residential"]]), hillside)
	var across2 := 0.0
	for d in range(10, 30, 2):
		var s := float(d)
		var p := fork2.point_at(3, s)
		across2 = maxf(across2, absf(fork2.road_y(3, s) - fork2._across(fork2._main_edges(0), p).x) / maxf(minf(fork2._project(1, p)[2], fork2._project(2, p)[2]) - 3.0, 1.0))
	check(fork2._cluster(0).size() > 1 and across2 < 0.15,
		"and so it does where the junction's drawn as one with the next along (%.2f m a metre at most)" % across2)
	# The junction's surface follows the through road across it.
	var mid := Vector2(100.0, 103.0)
	check(absf(net.surface_y(0, mid) - net.road_y(1, net.length_of(1))) < 0.05 and
		absf(net.surface_y(0, Vector2(120.0, 98.0)) - net.road_y(2, 20.0)) < 0.05,
		"the junction's surface is the through road's height across from each point")


## What the interface says a block holds, key by key, with its type.
func test_interface() -> void:
	var net := RoadNet.new(tee(), flat)
	check(net.region != null and net.version_hash.length() == 12, "a net has its region and a 12 hex version hash")
	var b := net.block(RoadBlock.key_of(100, 100))
	check(b is RoadBlock and RoadBlock.SIZE == 512.0 and RoadBlock.VERSION >= 1, "a block of 512 m with a version")
	check(b.key == Vector2i(0, 0) and b.rect == Rect2(0, 0, 512, 512), "block (0, 0) is the square from the frame point")
	check(RoadBlock.key_of(-1.0, 513.0) == Vector2i(-1, 1), "key_of floors (x, z) by 512")
	check(b.hash.length() == 12 and b.hash == RoadBlock.hash_of("fixture", b.key), "its hash is 12 hex of version, region and key")
	check(b.hash != net.block(Vector2i(-1, 0)).hash, "another block, another hash")
	check(b.arrays is Dictionary and b.ms >= 0.0 and b.buildings is Array, "arrays, ms and buildings")
	var piece_keys := {"edge": TYPE_INT, "s0": TYPE_FLOAT, "s1": TYPE_FLOAT, "points": TYPE_PACKED_VECTOR3_ARRAY,
		"width": TYPE_FLOAT, "lanes": TYPE_INT, "class": TYPE_STRING, "surface": TYPE_STRING, "name": TYPE_STRING,
		"oneway": TYPE_INT, "a": TYPE_INT, "b": TYPE_INT, "ring": TYPE_BOOL, "at": TYPE_PACKED_FLOAT32_ARRAY}
	check(not b.pieces.is_empty(), "the block has pieces of road (%d)" % b.pieces.size())
	for p in b.pieces:
		for k in piece_keys:
			check(p.has(k) and typeof(p[k]) == piece_keys[k], "a piece's %s is a %s" % [k, type_string(piece_keys[k])])
		break
	var j_keys := {"node": TYPE_INT, "nodes": TYPE_PACKED_INT32_ARRAY, "kind": TYPE_STRING, "pos": TYPE_VECTOR3,
		"radius": TYPE_FLOAT, "arms": TYPE_ARRAY, "island": TYPE_FLOAT, "pair": TYPE_INT, "outline": TYPE_PACKED_VECTOR2_ARRAY}
	var tees := b.junctions.filter(func(j): return j["kind"] == "tee")
	check(tees.size() == 1, "the block has its tee")
	if tees.is_empty():
		return
	var j: Dictionary = tees[0]
	for k in j_keys:
		check(j.has(k) and typeof(j[k]) == j_keys[k], "a junction's %s is a %s" % [k, type_string(j_keys[k])])
	var arm_keys := {"edge": TYPE_INT, "node": TYPE_INT, "heading": TYPE_FLOAT, "width": TYPE_FLOAT, "class": TYPE_STRING,
		"mouth": TYPE_VECTOR3, "main": TYPE_BOOL}
	for k in arm_keys:
		check((j["arms"][0] as Dictionary).has(k) and typeof(j["arms"][0][k]) == arm_keys[k], "an arm's %s is a %s" % [k, type_string(arm_keys[k])])
	check((j["arms"][0] as Dictionary).size() == arm_keys.size(), "an arm has those keys and no others")
	check((j as Dictionary).size() == j_keys.size(), "a junction has those keys and no others")
	var hit := net.locate(250.0, 101.0)
	var hit_keys := {"edge": TYPE_INT, "s": TYPE_FLOAT, "lat": TYPE_FLOAT, "y": TYPE_FLOAT, "width": TYPE_FLOAT,
		"heading": TYPE_FLOAT, "on_road": TYPE_BOOL, "node": TYPE_INT}
	for k in hit_keys:
		check(hit.has(k) and typeof(hit[k]) == hit_keys[k], "locate's %s is a %s" % [k, type_string(hit_keys[k])])
	check(b.locate(250.0, 101.0) == hit, "a block locates as the net does")
	check(net.width_of(0) > net.width_of(2) and net.lanes_of(0) == 2 and net.lanes_of(2) == 1, "a main road is wider than a street, with two lanes")
	check(net.profile(0).size() >= 2 and is_equal_approx(net.road_y(0, 5.0), 10.0), "a profile, and the road's height along it")
	check(net.junction_of(1)["kind"] == "end" and net.junction_of(0)["kind"] == "tee", "junction_of an end and a tee")
	check(net.mouth(2, 0) > 0.0 and net.mouth(0, 1) == 0.0, "a mouth at a junction, none at a dead end")
	check(net.ground_at(250.0, 100.0, 50.0) < 10.0 and is_equal_approx(net.ground_at(250.0, 300.0, 50.0), 50.0), "ground_at cuts the road in, and leaves the land be away from it")
	check(net.roads_near(Rect2(240, 90, 20, 20)) and not net.roads_near(Rect2(1500, 1500, 20, 20)), "roads_near")


## The kinds of junction, and their arms clockwise from north with the through road marked.
func test_kinds() -> void:
	var tn := RoadNet.new(tee(), flat)
	var j := tn.junction_of(0)
	var heads: Array = j["arms"].map(func(a): return snappedf(rad_to_deg(float(a["heading"])), 1.0))
	check(heads == [90.0, 180.0, 270.0], "a tee's arms go east, south, west, clockwise from north (%s)" % str(heads))
	check(j["arms"].map(func(a): return a["main"]) == [true, false, true], "its main road is east to west")
	check(float(j["arms"][1]["width"]) < float(j["arms"][0]["width"]), "the side road is narrower")
	# A town's block (a loop of straight one-way streets, 60 m a side, a street off each corner) is four junctions,
	# not a roundabout: it's "round" by its corners' distance from its middle, but turns square at each.
	var block := RoadNet.new(graph([[100, 100], [160, 100], [160, 160], [100, 160], [100, -200], [460, 100], [160, 460], [-200, 160]],
		[[0, 1, "residential", 1], [1, 2, "residential", 1], [2, 3, "residential", 1], [3, 0, "residential", 1],
		[0, 4, "residential"], [1, 5, "residential"], [2, 6, "residential"], [3, 7, "residential"]]), flat)
	var kinds := []
	for n in 4:
		kinds.append(block.junction_of(n)["kind"])
	check(not block.on_ring(0) and not kinds.has("roundabout"), "a town's square block isn't a roundabout (%s)" % str(kinds))
	var cn := RoadNet.new(cross(), flat)
	var c := cn.junction_of(0)
	check(c["kind"] == "cross" and c["arms"].size() == 4, "a crossroads has four arms")
	var corner := (c["outline"] as PackedVector2Array).size() == 4 * (2 + RoadNet.KERB_STEPS - 1)
	for p: Vector2 in c["outline"]:
		corner = corner and p.distance_to(Vector2(c["pos"].x, c["pos"].z)) <= float(c["radius"]) + 0.01
	check(corner, "its kerbs curve round from one arm to the next (%d points round it)" % (c["outline"] as PackedVector2Array).size())
	var mains: Array = c["arms"].filter(func(a): return a["main"])
	check(mains.size() == 2 and mains.all(func(a): return a["class"] == "primary"), "its through road is the wider one")
	# The narrow track's mouth is further out than the main road's: it has the wide road's width to clear.
	var track_m := cn.mouth(2, 0)
	var main_m := cn.mouth(0, 0)
	check(track_m > main_m, "mixed widths: the track starts past the main road's edge (%.1f m), the main road sooner (%.1f m)" % [track_m, main_m])
	check(track_m >= RoutePlanner.WIDTH["primary"] * 0.5 + RoadNet.FILLET - 0.01, "and clear of its kerb")
	var rn := RoadNet.new(roundabout(), flat)
	var ra := rn.junction_of(3)
	check(ra["kind"] == "roundabout" and ra["nodes"].size() == 8 and int(ra["node"]) == 0, "the ring is one roundabout (%s)" % str(ra.get("kind")))
	check(rn.junction_of(5) == ra, "every node on it is the same roundabout")
	check(ra["arms"].size() == 4 and float(ra["island"]) > 5.0, "four arms, and an island (%.1f m)" % float(ra["island"]))
	check(Vector2(ra["pos"].x, ra["pos"].z).distance_to(Vector2(100, 100)) < 0.5, "its middle is the ring's")
	check(rn.on_ring(0) and not rn.on_ring(8), "the ring's edges are on it, the roads off it aren't")
	# Two side roads off the ring meeting just outside it make a little triangle with the ring's edge between them: that
	# edge is still the roundabout's (the triangle, the fewer edges round, turns too sharply to be one).
	var tri := roundabout()
	var ta := TAU * 1.5 / 8.0
	tri.node_pos.append(Vector2(100.0 + sin(ta) * 30.0, 100.0 - cos(ta) * 30.0))
	tri.node_pos.append(Vector2(100.0 + sin(ta) * 300.0, 100.0 - cos(ta) * 300.0))
	var tg := graph(Array(tri.node_pos).map(func(v: Vector2): return [v.x, v.y]),
		[[0, 1, "secondary", 1], [1, 2, "secondary", 1], [2, 3, "secondary", 1], [3, 4, "secondary", 1], [4, 5, "secondary", 1],
		[5, 6, "secondary", 1], [6, 7, "secondary", 1], [7, 0, "secondary", 1], [0, 8, "secondary"], [2, 9, "secondary"],
		[4, 10, "secondary"], [6, 11, "secondary"], [1, 12, "residential"], [2, 12, "residential"], [12, 13, "residential"]])
	var trn := RoadNet.new(tg, flat)
	var tj := trn.junction_of(1)
	check(trn.on_ring(1) and tj["kind"] == "roundabout" and (tj["nodes"] as PackedInt32Array).size() == 8 and not trn.on_ring(12),
		"a little triangle of side roads beside a roundabout leaves the ring whole (%s, %d nodes)" % [tj.get("kind"), (tj.get("nodes", []) as Array).size()])
	var sn := RoadNet.new(staggered(), flat)
	check(sn.junction_of(0)["kind"] == "staggered" and int(sn.junction_of(0)["pair"]) == 1, "a tee with one opposite 30 m on is staggered")
	check(sn.junction_of(1)["kind"] == "staggered" and int(sn.junction_of(1)["pair"]) == 0, "both ways")
	# A divided road's two carriageways 20 m apart, crossed by a lane: one junction, the lane between them under it.
	var dn := RoadNet.new(graph([[0, -10], [0, 10], [-300, -10], [300, -10], [-300, 10], [300, 10], [0, -300], [0, 300]],
		[[3, 0, "primary", 1], [0, 2, "primary", 1], [4, 1, "primary", 1], [1, 5, "primary", 1], [6, 0, "residential"],
		[0, 1, "residential"], [1, 7, "residential"]]), flat)
	var dj := dn.junction_of(0)
	check(dj["nodes"] == PackedInt32Array([0, 1]) and dn.junction_of(1) == dj, "a divided road's crossing is one junction (%s)" % str(dj.get("nodes")))
	check(dj["arms"].size() == 6 and dj["arms"].filter(func(a): return a["main"]).size() == 4,
		"six arms, the divided road's four its main roads")
	check(dn.mouth(5, 0) >= dn.length_of(5) - 0.01, "the lane between the carriageways is all under it")
	check(Geometry2D.is_point_in_polygon(Vector2(0, 0), dj["outline"]) and int(dn.locate(0.0, 0.0)["node"]) == 0,
		"between them is on it")
	check(absf(dn.surface_y(1, Vector2(0, 0)) - 10.0) < 0.01, "level on level ground")
	var fork := RoadNet.new(graph([[0, 0], [0, 300], [-260, -150], [260, -150]],
		[[1, 0, "primary"], [0, 2, "primary"], [0, 3, "secondary"]]), flat)
	check(fork.junction_of(0)["kind"] == "fork", "a Y is a fork")
	var five := []
	var five_nodes := [[0, 0]]
	for k in 5:
		five_nodes.append([sin(TAU * k / 5.0) * 300.0, -cos(TAU * k / 5.0) * 300.0])
		five.append([0, k + 1, "tertiary"])
	check(RoadNet.new(graph(five_nodes, five), flat).junction_of(0)["kind"] == "multi", "five arms is a multi")
	check(tn.junction_of(2).is_empty() == false and RoadNet.new(graph([[0, 0], [100, 0], [200, 50]],
		[[0, 1, "primary"], [1, 2, "primary"]]), flat).junction_of(1).is_empty(), "a plain join is no junction")


## Which road you're on: along it, which side, how high, at a junction or not.
func test_locate() -> void:
	var slope := func(x: float, z: float) -> float: return 20.0 + x * 0.05
	var net := RoadNet.new(tee(), slope)
	var on := net.locate(250.0, 102.0)
	check(on.get("edge") == 1 and absf(float(on["s"]) - 150.0) < 0.5, "150 m along the east road (%s)" % str(on))
	# Edge 1 runs east from the tee: right of it is south (+z).
	check(float(on["lat"]) > 1.9 and float(on["lat"]) < 2.1 and bool(on["on_road"]) and int(on["node"]) == -1, "2 m right of its middle, on the road, at no junction")
	check(absf(rad_to_deg(float(on["heading"])) - 90.0) < 0.5, "heading east")
	check(absf(float(on["y"]) - net.road_y(1, float(on["s"]))) < RoadNet.CROWN + 0.001, "at the road's height")
	var off := net.locate(250.0, 115.0)
	check(not off.is_empty() and not bool(off["on_road"]), "15 m off it, it's still the nearest road but you're off it")
	check(net.locate(250.0, 200.0).is_empty(), "100 m off, no road")
	var mid := net.locate(101.0, 102.0)
	check(int(mid.get("node", -1)) == 0 and bool(mid["on_road"]), "in the middle of the tee, at its junction")
	check(net.locate(250.0, 102.0, 2) == on, "a hint doesn't change the answer")
	# One way: a dual carriageway's two carriageways 16 m apart, and a slip road on its own.
	var dual := RoadNet.new(graph([[-300, 100], [300, 100], [300, 116], [-300, 116], [-300, 400], [300, 400], [-300, 600], [300, 600]],
		[[0, 1, "primary", 1], [2, 3, "primary", 1], [4, 5, "tertiary", 1], [6, 7, "tertiary"]]), flat)
	var east := dual.one_way_at(Vector2(0, 100), PI * 0.5)
	var west := dual.one_way_at(Vector2(0, 100), PI * 1.5)
	check(east.x == 1.0 and absf(east.y - 16.0) < 0.5 and west.x == -1.0 and absf(west.y + 16.0) < 0.5,
		"a dual carriageway is one way, its other carriageway 16 m across (%s, %s)" % [east, west])
	var slip := dual.one_way_at(Vector2(0, 400), PI * 0.5)
	check(slip.x == 1.0 and is_nan(slip.y), "a slip road is one way with no other carriageway beside it (%s)" % slip)
	check(dual.one_way_at(Vector2(0, 600), PI * 0.5).x == 0.0, "and an ordinary road both ways")
	var rn := RoadNet.new(roundabout(), flat)
	var ring := rn.locate(100.0 + 16.0, 100.0)
	check(int(ring.get("node", -1)) == 0 and rn.on_ring(int(ring["edge"])), "on the ring, at the roundabout")
	# A right-angled corner the map drew at a plain join, and another inside an edge: both become curves, the strand's
	# ends stay put and its edges meet end to end.
	var bn := RoadNet.new(graph([[0, 0], [200, 0], [400, 200]], [[0, 1, "secondary"], [1, 2, "secondary", 0, [200, 200]]]), flat)
	var l0 := bn.line_of(0)
	var l1 := bn.line_of(1)
	var worst := 0.0
	var line := PackedVector2Array()
	for p in l0 + l1:
		if line.is_empty() or p.distance_to(line[line.size() - 1]) > 1.0:
			line.append(p)
	for k in range(1, line.size() - 1):
		var turn := absf((line[k] - line[k - 1]).angle_to(line[k + 1] - line[k]))
		worst = maxf(worst, turn / ((line[k].distance_to(line[k - 1]) + line[k].distance_to(line[k + 1])) * 0.5))
	check(l0[0] == Vector2(0, 0) and l1[l1.size() - 1] == Vector2(400, 200) and l0[l0.size() - 1] == l1[0],
		"a strand's ends stay put and its edges meet")
	check(1.0 / worst >= RoutePlanner.MIN_RADIUS * 0.9, "its corners are curves (the tightest a %.1f m radius)" % (1.0 / worst))
	var corner := bn.locate(200.0, 0.0)
	check(not corner.is_empty() and absf(float(corner["lat"])) > 2.0 and bn.length_of(0) + bn.length_of(1) < 600.0,
		"the corner the map drew is cut (%.1f m off the curve)" % absf(float(corner.get("lat", 0.0))))


## Heights: every road meeting at a junction meets it at its height; the road is smooth; the land is cut to it.
func test_heights() -> void:
	var hill := func(x: float, z: float) -> float: return 50.0 + x * 0.08 + sin(z * 0.03) * 6.0
	var net := RoadNet.new(cross(), hill)
	var y0 := net.node_y(0)
	var ends := []
	for ei in 4:
		var s := 0.0 if net.region.edge_a[ei] == 0 else net.length_of(ei)
		ends.append(net.road_y(ei, s))
	check(ends.all(func(y): return is_equal_approx(float(y), y0)), "all four roads meet at the junction's height (%.2f)" % y0)
	# A side road climbing steeply away from a level main road: the junction is at the main road's height, and the side
	# road eases onto it (the main road isn't lifted into a hump).
	var climb := func(_x: float, z: float) -> float: return 10.0 + maxf(0.0, z - 100.0) * 0.6
	var tn := RoadNet.new(tee(), climb)
	check(absf(tn.node_y(0) - 10.0) < 0.2 and absf(tn.road_y(1, 30.0) - 10.0) < 0.2,
		"a junction sits at its through road's height, not lifted by a side road climbing away (%.2f)" % tn.node_y(0))
	var worst := 0.0
	for ei in 4:
		var pr := net.profile(ei)
		for k in range(1, pr.size() - 1):
			worst = maxf(worst, absf(pr[k + 1] - 2.0 * pr[k] + pr[k - 1]))
	check(worst < 0.2, "no kinks along them (the worst bend of grade between steps %.3f m)" % worst)
	var hit := net.locate(300.0, 100.0)
	var under := net.ground_at(300.0, 100.0, float(hill.call(300.0, 100.0)))
	check(absf(under - (net.road_y(int(hit["edge"]), float(hit["s"])) - RoadNet.UNDER)) < 0.01, "the land lies just under the road")
	var bare := float(hill.call(300.0, 160.0))
	check(is_equal_approx(net.ground_at(300.0, 160.0, bare), bare), "and is bare 60 m off it")
	var prev := net.ground_at(300.0, 100.0, float(hill.call(300.0, 100.0)))
	var jump := 0.0
	for k in range(1, 60):
		var z := 100.0 + k
		var g := net.ground_at(300.0, z, float(hill.call(300.0, z)))
		jump = maxf(jump, absf(g - prev))
		prev = g
	check(jump < 1.0, "it eases out to the bare land without a step (the biggest a metre %.2f m)" % jump)
	# In a cutting the land is held level with the road a cell's width past the verge, so the land's 2 m cells there
	# never lie over the deck; where it falls away it falls from a little past the verge.
	var vee := func(_x: float, z: float) -> float: return 50.0 + absf(z - 100.0) * 0.5
	var cut := RoadNet.new(cross(), vee)
	var road := cut.road_y(int(hit["edge"]), float(hit["s"]))
	var edge := 100.0 + cut.width_of(int(hit["edge"])) * 0.5 + RoadNet.VERGE
	var held := cut.ground_at(300.0, edge + RoadNet.LAND_PAD - 0.5, float(vee.call(300.0, edge + RoadNet.LAND_PAD - 0.5)))
	check(held <= road - RoadNet.UNDER + 0.01, "in a cutting the land is level with the road %.0f m past the verge (%.2f m against the road's %.2f)" % [RoadNet.LAND_PAD, held, road])
	check(cut.ground_at(300.0, edge + RoadNet.LAND_PAD + 20.0, float(vee.call(300.0, edge + RoadNet.LAND_PAD + 20.0))) > road + 2.0, "then climbs its bank")
	var dip := func(_x: float, z: float) -> float: return 50.0 - absf(z - 100.0) * 0.5
	var bank := RoadNet.new(cross(), dip)
	var shelf := bank.ground_at(300.0, edge + RoadNet.FALL_PAD - 0.5, float(dip.call(300.0, edge + RoadNet.FALL_PAD - 0.5)))
	check(absf(shelf - (road - RoadNet.UNDER)) < 0.01, "on an embankment the land is level with the road %.0f m past the verge, under its skirt (%.2f m against the road's %.2f)" % [RoadNet.FALL_PAD, shelf, road])
	var below := bank.ground_at(300.0, edge + RoadNet.FALL_PAD + 12.0, float(dip.call(300.0, edge + RoadNet.FALL_PAD + 12.0)))
	check(below < road - 1.0 and below > road - 6.0, "then falls away down its bank (%.2f m under the road %.0f m out)" % [road - below, RoadNet.FALL_PAD + 12.0])
	# A dual carriageway across a slope, its halves 16 m apart: no land between them or beside them stands higher than
	# the nearer half (it would lie over its deck).
	var slope := func(_x: float, z: float) -> float: return 10.0 + z * 0.15
	var dual := RoadNet.new(graph([[-300, 92], [300, 92], [300, 108], [-300, 108]], [[0, 1, "primary", 1], [2, 3, "primary", 1]]), slope)
	var over := 0.0
	for z in range(80, 121):
		var g := dual.ground_at(0.0, float(z), float(slope.call(0.0, float(z))))
		for e in 2:
			var off := absf(float(z) - (92.0 if e == 0 else 108.0)) - dual.width_of(e) * 0.5 - RoadNet.VERGE
			if off < RoadNet.LAND_PAD:
				over = maxf(over, g - (dual.road_y(e, dual.length_of(e) * 0.5) - RoadNet.UNDER))
	check(over <= 0.01, "no land within a cell of either half's verge stands over its deck (the most %.2f m over)" % over)
	# A roundabout is round: its ring's lines keep to one circle round its middle.
	var rn := RoadNet.new(roundabout(), flat)
	var lo := INF
	var hi := 0.0
	for ei in 8:
		for q: Vector2 in rn.line_of(ei):
			var d := q.distance_to(Vector2(100, 100))
			lo = minf(lo, d)
			hi = maxf(hi, d)
	check(hi - lo < 0.3, "a roundabout's ring is a circle (%.2f to %.2f m from its middle)" % [lo, hi])
	# And on one plane: over a mound where it bends, a big ring doesn't hump between its arms, nor dip into a V at each
	# arm's node; tipped with the hill it's on.
	var ripple := RoadNet.new(roundabout(38.0), func(x: float, z: float) -> float: return 3.0 * exp(-(pow(x - 130.0, 2.0) + pow(z - 75.0, 2.0)) / 300.0) + x * 0.04)
	var ps := PackedVector2Array()
	var ys := PackedFloat32Array()
	for ei in 8:
		var h := ripple.profile(ei)
		for k in h.size():
			ps.append(ripple.point_at(ei, ripple.length_of(ei) * float(k) / float(h.size() - 1)) - Vector2(100, 100))
			ys.append(h[k])
	var pl := RoadNet._plane(ps, ys)
	var off_plane := 0.0
	for k in ps.size():
		off_plane = maxf(off_plane, absf(ys[k] - (pl.x + pl.y * ps[k].x + pl.z * ps[k].y)))
	check(off_plane < 0.01 and absf(pl.y - 0.04) < 0.02,
		"a roundabout's ring lies on one plane over a mound (%.3f m off it at most), tipped with the hill (%.3f)" % [off_plane, pl.y])
	# Its arms come onto it in one surface: across each arm's mouth, from the arm's road onto the ring's deck, the
	# collision never steps.
	var rb := RoadBlock.build(ripple, RoadBlock.key_of(100.0, 100.0))
	var faces := PackedVector3Array()
	for surf: String in rb.arrays["deck"]:
		var g: Dictionary = rb.arrays["deck"][surf]
		for i: int in g["i"]:
			faces.append((g["v"] as PackedVector3Array)[i] + rb.anchor())
	var step := 0.0
	for k in 4:
		var ang := TAU * k / 4.0
		var way := Vector2(sin(ang), -cos(ang))
		var last := NAN
		for d in range(30, 60):
			var q := Vector2(100, 100) + way * d * 1.0
			var y := _deck_y(faces, q)
			if not is_nan(y) and not is_nan(last):
				step = maxf(step, absf(y - last) - 0.1)
			last = y
	check(step < 0.03, "and its arms run onto its deck without a step (%.3f m past their own slope at most)" % step)


## The highest of `faces`' (triangles, region frame) heights at `p`, or NAN where none is.
static func _deck_y(faces: PackedVector3Array, p: Vector2) -> float:
	var best := NAN
	for t in faces.size() / 3:
		var a := faces[t * 3]
		var b := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-9:
			continue
		var u := ((b.z - c.z) * (p.x - c.x) + (c.x - b.x) * (p.y - c.z)) / den
		var v := ((c.z - a.z) * (p.x - c.x) + (a.x - c.x) * (p.y - c.z)) / den
		if u < -1e-4 or v < -1e-4 or u + v > 1.0 + 1e-4:
			continue
		var y := a.y * u + b.y * v + c.y * (1.0 - u - v)
		if is_nan(best) or y > best:
			best = y
	return best


## A road crossing from one block into the next is in both, the two meeting at the seam; the same block twice is the
## same; every piece of road is in a block.
func test_blocks() -> void:
	var r := graph([[-300, 100], [300, 100], [300, 700]], [[0, 1, "primary"], [1, 2, "tertiary", 0, [400, 300, 350, 500]]])
	# A house the map has standing on the road (drawn a little off), one beside it, and one fronting the street a metre
	# into its verge.
	var clear := float(RoutePlanner.WIDTH["primary"]) * 0.5 + RoadNet.VERGE + RoadBlock.CLEAR + 3.5
	r.buildings = [[100.0, 102.0, 9.0, 7.0, 0.0, 6.0, 0], [100.0, 125.0, 9.0, 7.0, 0.0, 6.0, 0], [150.0, 100.0 + clear - 1.0, 9.0, 7.0, 0.0, 6.0, 0]]
	var net := RoadNet.new(r, flat)
	var west := net.block(Vector2i(-1, 0))
	var east := net.block(Vector2i(0, 0))
	var pw: Array = west.pieces.filter(func(p): return p["edge"] == 0)
	var pe: Array = east.pieces.filter(func(p): return p["edge"] == 0)
	check(pw.size() == 1 and pe.size() == 1, "the road across x = 0 is in both blocks")
	if pw.size() == 1 and pe.size() == 1:
		var seam := float(pw[0]["s1"]) - float(pe[0]["s0"])
		check(seam > 0.0 and seam <= RoadBlock.SEAM * 2.0 + 0.01, "overlapping at the seam by %.3f m" % seam)
		check(absf(float(pw[0]["s1"]) - 300.0 - RoadBlock.SEAM) < 0.01, "cut at x = 0, 300 m along it")
	var zs: Array = east.buildings.map(func(b): return float(b[1]))
	check(east.buildings.size() == 2 and zs.has(125.0), "the house on the road is left out, the one beside it stands")
	var front: Array = east.buildings.filter(func(b): return is_equal_approx(float(b[0]), 150.0))
	check(front.size() == 1 and float(front[0][1]) >= 100.0 + clear - 0.01 and float(front[0][1]) < 100.0 + clear + 0.2,
		"the one in the verge is pushed back clear of it, not left out (%s)" % str(front.map(func(b): return snappedf(float(b[1]) - 100.0 - clear, 0.01))))
	check(net.block(Vector2i(0, 0)).pieces == east.pieces and net.block(Vector2i(0, 0)).junctions == east.junctions, "the same block twice is the same")
	# The bent street leaves block (0, 0) east and comes back: two pieces of it there, and one in (0, 1).
	var covered := 0.0
	for k in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, 1)]:
		for p in net.block(k).pieces:
			if p["edge"] == 1:
				covered += float(p["s1"]) - float(p["s0"])
	var plain := net.length_of(1) - net.mouth(1, 1) - net.mouth(1, 2)
	check(covered >= plain - 0.01 and covered <= plain + RoadBlock.SEAM * 4.0 + 0.01, "every metre of the street is in a block (%.1f of %.1f m)" % [covered, plain])
	var j := RoadNet.new(cross(), flat).block(Vector2i(0, 0)).junctions
	check(j.map(func(q): return q["kind"]) == ["cross", "end", "end"], "the block has the cross and the two dead ends in it, not the two out of it")
	var rb := RoadNet.new(roundabout(), flat).block(Vector2i(0, 0))
	check(rb.junctions.filter(func(q): return q["kind"] == "roundabout").size() == 1, "a roundabout is one junction, not eight")
	check(rb.pieces.filter(func(p): return p["ring"]).size() == 8, "its ring is eight pieces of road")


## A real cell (the Dales fixture, flat ground so no tiles are fetched): the blocks round its busiest one, every
## junction a kind the interface names, every point along every piece found on its own road, and quick to build.
func test_cell() -> void:
	var mid := RealRegion.cell_middle(Vector2i(577, 712))
	var r := RealRegion.stitch("roads", "Roads", ["res://tests/fixtures/cells/c577_712"] as Array[String], mid.x, mid.y)
	check(r != null and r.edge_count() > 1000, "the cell's roads are read")
	if r == null:
		return
	var t0 := Time.get_ticks_usec()
	var net := RoadNet.new(r, func(x: float, z: float) -> float: return 200.0 + x * 0.01)
	var make_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var busiest := Vector2i.ZERO
	var most := -1
	for k: Vector2i in net._nodes_by_block:
		if net.nodes_in(k).size() > most:
			most = net.nodes_in(k).size()
			busiest = k
	var kinds := {}
	var worst_ms := 0.0
	var pieces := 0
	var lost := 0
	var tried := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var b := net.block(busiest + Vector2i(dx, dz))
			worst_ms = maxf(worst_ms, b.ms)
			pieces += b.pieces.size()
			for j in b.junctions:
				kinds[j["kind"]] = int(kinds.get(j["kind"], 0)) + 1
			for p in b.pieces:
				var pts: PackedVector3Array = p["points"]
				for k in range(0, pts.size(), 7):
					tried += 1
					var hit := b.locate(pts[k].x, pts[k].z)
					if hit.is_empty() or not bool(hit["on_road"]) or absf(float(hit["y"]) - pts[k].y) > 0.5:
						lost += 1
	print("  road net: made in %.0f ms; 9 blocks round the busiest (%d nodes), %d pieces, worst block %.0f ms, kinds %s" % [make_ms, most, pieces, worst_ms, str(kinds)])
	check(kinds.keys().all(func(k): return k in ["end", "tee", "fork", "cross", "staggered", "multi", "roundabout", "mini"]), "every junction is a kind the interface names")
	check(int(kinds.get("tee", 0)) > 5, "a village has its tees")
	check(lost == 0, "every point along every piece is on a road at its height (%d of %d lost)" % [lost, tried])
	check(worst_ms < 1500.0, "a block lays out on a worker in good time (worst %.0f ms)" % worst_ms)
	# Dressed with the cell's own trees (its canopy map, or what covers the ground): none on a road or its verge.
	check(r.terrain != null, "the cell has its terrain (cover and trees)")
	if r.terrain == null:
		return
	net.dress = {"terrain": r.terrain, "look": {"broad": "oak", "needle": "pine"}}
	var trees := 0
	var on_road := 0
	var tree_ms := 0.0
	for dx in range(-1, 2):
		var b := net.block(busiest + Vector2i(dx, 1))
		tree_ms = maxf(tree_ms, b.ms)
		for kind: String in b.trees:
			for xf: Transform3D in b.trees[kind]:
				trees += 1
				var at := xf.origin + b.anchor()
				var hit := net.locate(at.x, at.z)
				if not hit.is_empty() and absf(float(hit["lat"])) < float(hit["width"]) * 0.5 + RoadNet.VERGE:
					on_road += 1
	print("  road net: %d trees in three blocks, worst block %.0f ms with them" % [trees, tree_ms])
	check(trees > 50, "the land round the roads has its trees (%d in three blocks)" % trees)
	check(on_road == 0, "none on a road or its verge (%d)" % on_road)
	check(tree_ms < 2000.0, "and a block still lays out in good time (%.0f ms)" % tree_ms)
	# A wood is of several kinds, as the place's look mixes them (here, a temperate one's), not one broadleaf and one
	# conifer.
	var mixed := RoadNet.new(r, flat)
	mixed.dress = {"terrain": r.terrain, "look": {"broad": "oak", "needle": "pine", "plants": PlaceLook.KIT["temperate"]["plants"]}}
	var kinds_seen := {}
	for dx in range(-1, 2):
		for kind: String in mixed.block(busiest + Vector2i(dx, 1)).trees:
			if kind in RoadBlock.BROADLEAVES or kind in RoadBlock.CONIFERS:
				kinds_seen[kind] = true
	check(kinds_seen.size() >= 4, "a wood is mixed from the place's kinds of tree (%s)" % str(kinds_seen.keys()))
	# Its town streets built up along their fronts where the map leaves gaps (RoadBlock._infill): none of the buildings
	# on a road, nor standing in another.
	var built := 0
	var in_road := 0
	var crowded := 0
	for dx in range(-1, 2):
		var b := net.block(busiest + Vector2i(dx, 1))
		built += b.buildings.size()
		for i in b.buildings.size():
			var row: Array = b.buildings[i]
			for c: Vector2 in RoadBlock._corners(row):
				var hit := net.locate(c.x, c.y, -1, false)
				if not hit.is_empty() and bool(hit["on_road"]):
					in_road += 1
			for k in range(i + 1, b.buildings.size()):
				var other: Array = b.buildings[k]
				var apart := Vector2(float(row[0]) - float(other[0]), float(row[1]) - float(other[1])).length()
				if apart < (minf(float(row[2]), float(row[3])) + minf(float(other[2]), float(other[3]))) * 0.25:
					crowded += 1
	print("  road net: %d buildings in three blocks" % built)
	check(in_road == 0 and crowded == 0, "no building's corner on a road (%d), none standing in another (%d)" % [in_road, crowded])


## The block's meshes: the deck and junctions facing up, indexed within bounds, with collision; lines on tarmac; a
## roundabout's island.
func test_meshes() -> void:
	var net := RoadNet.new(tee(), flat)
	var b := net.block(Vector2i(0, 0))
	var deck: Dictionary = b.arrays["deck"].get("tarmac", {})
	check(not deck.is_empty(), "a tarmac deck")
	if deck.is_empty():
		return
	var v: PackedVector3Array = deck["v"]
	var idx: PackedInt32Array = deck["i"]
	check(v.size() > 100 and idx.size() % 3 == 0 and idx.size() > 0, "%d vertices, %d triangles" % [v.size(), idx.size() / 3])
	var worst := INF
	var out_of := 0
	for k in range(0, idx.size(), 3):
		if idx[k] >= v.size() or idx[k + 1] >= v.size() or idx[k + 2] >= v.size():
			out_of += 1
			continue
		# Stored clockwise (Godot's front faces): the normal of (a, c, b) is the face's.
		var n := (v[idx[k + 2]] - v[idx[k]]).cross(v[idx[k + 1]] - v[idx[k]]).normalized()
		worst = minf(worst, n.y)
	check(out_of == 0, "every index is a vertex")
	check(worst > 0.9, "every triangle of road faces up (the least %.2f)" % worst)
	check((deck["n"] as PackedVector3Array).size() == v.size() and (deck["uv"] as PackedVector2Array).size() == v.size() and (deck["c"] as PackedColorArray).size() == v.size(), "a normal, uv and colour each")
	check((b.arrays["faces"]["tarmac"] as PackedVector3Array).size() == idx.size(), "its collision is the same triangles")
	check((b.arrays["faces"].get("grass", PackedVector3Array()) as PackedVector3Array).size() > 0, "the verges have collision (grass)")
	check((b.arrays["lines"]["v"] as PackedVector3Array).size() > 0, "white lines on the tarmac")
	# The deck under the tee's middle is at the junction's height (a ray down finds it).
	var hit := _down(b, Vector3(100.5, 20.0, 100.5) - b.anchor())
	check(not is_nan(hit) and absf(hit - 10.0) < 0.1, "the junction's surface is there at its height (%.2f)" % hit)
	var road := _down(b, Vector3(300.0, 20.0, 101.0) - b.anchor())
	check(not is_nan(road) and absf(road - (10.0 + RoadNet.CROWN * 0.92)) < 0.05, "and the road beside it (%.3f)" % road)
	var rb := RoadNet.new(roundabout(), flat).block(Vector2i(0, 0))
	check((rb.arrays["island"]["v"] as PackedVector3Array).size() > 0, "a roundabout has its island")
	# Across each of the tee's mouths the junction's surface meets the road's crowned deck all the way across: no lip
	# the crown's height in the middle.
	var tnet := RoadNet.new(tee(), flat)
	var tb3 := tnet.block(RoadBlock.key_of(100.0, 100.0))
	var o3 := Vector2(tb3.anchor().x, tb3.anchor().z)
	var lip := 0.0
	for arm: Dictionary in tnet.junction_of(0)["arms"]:
		var ei := int(arm["edge"])
		var len := tnet.length_of(ei)
		var m := tnet.mouth(ei, 0)
		var from_a := tee().edge_a[ei] == 0
		for f: float in [-0.6, 0.0, 0.6]:
			var hs := []
			for d: float in [-0.05, 0.05]:
				var sm := m + d if from_a else len - m - d
				var h := tnet.heading_at(ei, sm)
				var q := tnet.point_at(ei, sm) + Vector2(cos(h), sin(h)) * f * float(arm["width"]) * 0.5
				var got := _heights_at(tb3, q - o3)
				hs.append(got[got.size() - 1] if not got.is_empty() else NAN)
			lip = maxf(lip, absf(float(hs[1]) - float(hs[0])))
	check(lip < 0.008, "a road meets its junction's surface with no lip across its mouth (%.3f m at most)" % lip)
	# On a hill, its island tips with the ring and its kerb runs round the ring's own inner edge: tarmac just outside it
	# all the way round, the island's grass just inside it at the kerb's height above the ring, no gap and no step.
	var tipped := RoadNet.new(roundabout(), func(x: float, z: float) -> float: return 10.0 + x * 0.06 - z * 0.03)
	var tr := tipped.junction_of(0)
	var tb2 := tipped.block(RoadBlock.key_of(100.0, 100.0))
	var o2 := tb2.anchor()
	var c2 := Vector2(tr["pos"].x, tr["pos"].z)
	var worst_gap := 0.0
	var worst_kerb := 0.0
	for k in 32:
		var h := TAU * (k + 0.5) / 32.0
		var d := Vector2(sin(h), -cos(h))
		var rr := tipped.island_r(tr, h)
		var road_hs := _heights_at(tb2, c2 + d * (rr + 0.3) - Vector2(o2.x, o2.z))
		if road_hs.is_empty():
			worst_gap = maxf(worst_gap, 1.0)
		var inside := c2 + d * (rr - 0.4)
		var top := _down(tb2, Vector3(inside.x, 1000.0, inside.y) - o2) + o2.y
		worst_kerb = maxf(worst_kerb, absf(top - tipped.ring_y(tr, inside) - RoadBlock.ISLAND_H))
	check(worst_gap == 0.0 and worst_kerb < 0.02,
		"a roundabout's island sits on its ring's inner edge, tipped with it (no gap: %s; kerb height off by %.3f m)" % [worst_gap == 0.0, worst_kerb])
	# Three junctions drawn as one, with a road looping round from one to another (its mouths inside their outline,
	# which folds back seen from its middle), on rolling land: one surface over each spot, never two a step apart.
	var rolling := func(x: float, z: float) -> float: return 10.0 + x * 0.08 + 2.0 * sin(z / 12.0) + 1.5 * sin(x / 9.0)
	var three := RoadNet.new(graph([[100, 100], [120, 100], [110, 118], [-200, 100], [400, 100], [110, 400]],
		[[3, 0, "tertiary"], [0, 1, "tertiary"], [1, 4, "tertiary"], [0, 2, "residential"], [1, 2, "residential"],
		[2, 5, "residential"], [0, 1, "residential", 0, [110, 70]]]), rolling)
	var tj := three.junction_of(0)
	check(tj["kind"] == "multi" and (tj["nodes"] as PackedInt32Array).size() == 3, "the three drawn as one (%s)" % tj["kind"])
	var tb := three.block(RoadBlock.key_of(110.0, 100.0))
	var spread := 0.0
	for x in range(60, 161, 3):
		for z in range(50, 151, 3):
			var hs := _heights_at(tb, Vector2(x, z) - Vector2(tb.anchor().x, tb.anchor().z))
			if hs.size() > 1:
				spread = maxf(spread, hs[hs.size() - 1] - hs[0])
	check(spread < 0.03, "its surface lies as one sheet (two faces at most %.3f m apart over a spot)" % spread)


## The map's bridges: one over a valley runs level from end to end with the land left as it is under it, a parapet each
## side and piers down to the valley floor; one over another road climbs to clear it, and the road under it stays on
## the land, its own way through.
func test_bridges() -> void:
	var valley := func(x: float, _z: float) -> float: return 50.0 - maxf(0.0, 40.0 - absf(x - 100.0)) * 0.5
	var r := graph([[-300, 100], [300, 100]], [[0, 1, "primary"]])
	r.spans = [[0, 60.0, 100.0, 140.0, 100.0]]
	var net := RoadNet.new(r, valley)
	var mid := net.locate(100.0, 100.0)
	var s := float(mid["s"])
	check(net.bridge_at(0, s) >= 1.0 and net.bridge_at(0, 10.0) <= 0.0, "the road is out on its bridge over the valley, and only there")
	check(absf(net.road_y(0, s) - 50.0) < 0.6, "level across it, not down into the valley (%.2f m over the far side's 50)" % net.road_y(0, s))
	var floor_y := float(valley.call(100.0, 100.0))
	check(is_equal_approx(net.ground_at(100.0, 100.0, floor_y), floor_y), "the valley floor under it is left as it is")
	check(net.ground_at(100.0, 100.0, 80.0) <= net.road_y(0, s) - RoadNet.BRIDGE_DEPTH, "and land is never up through its deck")
	var b := net.block(Vector2i(0, 0))
	check((b.arrays["bridge"]["v"] as PackedVector3Array).size() > 0, "the bridge has its stonework")
	var deck := _down(b, Vector3(100.0, 70.0, 100.0) - b.anchor())
	check(not is_nan(deck) and absf(deck - net.road_y(0, s)) < 0.1, "its deck is ridden on at its height (%.2f)" % deck)
	var parapet := false
	for surf in b.arrays["faces"]:
		var f: PackedVector3Array = b.arrays["faces"][surf]
		for k in range(0, f.size(), 3):
			var n := (f[k + 1] - f[k]).cross(f[k + 2] - f[k]).normalized()
			parapet = parapet or (absf(n.y) < 0.1 and f[k].x + b.anchor().x > 70.0 and f[k].x + b.anchor().x < 130.0)
	check(parapet, "and its parapets are walls to ride into")
	# A bridge the map has in two, meeting at a node out over the valley (a slip road joining it there): no abutment
	# in the air at the join, the deck carries on through it.
	var two := graph([[-300, 100], [100, 100], [300, 100]], [[0, 1, "primary"], [1, 2, "primary"]])
	two.spans = [[0, 60.0, 100.0, 100.0, 100.0], [0, 100.0, 100.0, 140.0, 100.0]]
	var tn := RoadNet.new(two, valley)
	check(tn.bridge_at(0, tn.length_of(0) - 2.0) >= 1.0 and tn.bridge_at(1, 2.0) >= 1.0,
		"a bridge in two carries on through the node between them (%.2f, %.2f)" % [tn.bridge_at(0, tn.length_of(0) - 2.0), tn.bridge_at(1, 2.0)])
	check(is_equal_approx(tn.ground_at(98.0, 100.0, float(valley.call(98.0, 100.0))), float(valley.call(98.0, 100.0))), "and the valley floor under the join is left as it is")
	# Over another road on the flat: the bridge climbs to clear it, gently, and the road under it stays on the land.
	var o := graph([[-300, 100], [300, 100], [100, -200], [100, 400]], [[0, 1, "primary"], [2, 3, "secondary"]])
	o.spans = [[0, 88.0, 100.0, 112.0, 100.0]]   # (as the map often has them: the abutments' faces, the road between)
	var over := RoadNet.new(o, flat)
	var top := over.road_y(0, float(over.locate(100.0, 100.0, 0)["s"]))
	check(top >= 10.0 + RoadNet.HEADROOM + RoadNet.BRIDGE_DEPTH, "it climbs to clear the road under it (its deck %.2f m up)" % (top - 10.0))
	var steep := 0.0
	var pr := over.profile(0)
	for k in range(1, pr.size()):
		steep = maxf(steep, absf(pr[k] - pr[k - 1]) / (over.length_of(0) / float(pr.size() - 1)))
	check(steep < 0.08, "up and down approaches no steeper than one in twelve (%.3f)" % steep)
	var under := over.locate(100.0, 100.0, 1)
	check(int(under["edge"]) == 1 and absf(float(under["y"]) - 10.0) < 0.1, "the road under it is on the land, found from itself")
	check(over.bridge_at(1, float(under["s"])) <= 0.0, "and isn't a bridge itself")
	var clear := over.width_of(1) * 0.5 + RoadNet.VERGE + RoadNet.LAND_PAD
	var mid_s := float(over.locate(100.0, 100.0, 0)["s"])
	check(over.bridge_at(0, mid_s - clear) >= 1.0 and over.bridge_at(0, mid_s + clear) >= 1.0,
		"the bridge runs on over the road's verges and the land held level with it, not just the map's short span")
	var o_land := over.ground_at(100.0 - clear + 1.0, 100.0, 10.0)
	check(o_land <= 10.01, "where the land under it stays down with the road beneath (%.2f)" % o_land)


## The height of the first collision triangle of block `b` straight under local `p` (NAN if none).
## Every height of block `b`'s road deck (tarmac) over (x, z) `p` (block space), lowest first.
static func _heights_at(b: RoadBlock, p: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f: PackedVector3Array = b.arrays["faces"].get("tarmac", PackedVector3Array())
	for k in range(0, f.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, 1000.0, p.y), Vector3.DOWN, f[k], f[k + 1], f[k + 2])
		if hit != null:
			out.append(float(hit.y))
	out.sort()
	return out


static func _down(b: RoadBlock, p: Vector3) -> float:
	var best := NAN
	for surf in b.arrays["faces"]:
		var f: PackedVector3Array = b.arrays["faces"][surf]
		for k in range(0, f.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(p, Vector3.DOWN, f[k], f[k + 1], f[k + 2])
			if hit != null and (is_nan(best) or float(hit.y) > best):
				best = float(hit.y)
	return best


## The network ride (AdventureWorld.network), where riding is the point: a ride on a bundled region streams the road
## blocks round the rider, a bike set down on a road well off the planned one rides on it, and the planned road only
## answers near it.
func test_ride() -> void:
	var plan := AdventurePlans.sample(20.0)
	var region := RealRegion.get_region(str(plan["region"]))
	var was := AdventureWorld.network
	AdventureWorld.network = true
	var w := AdventureWorld.new()
	w.roads_region = region
	w.setup(AdventurePlans.pack_for(plan), 1, 20.0)
	AdventureWorld.network = was
	check(w.roads != null and w.land != null and w.land.roads == w.roads.net and RealLand.roam,
		"the network ride streams road blocks, on land that follows the network, free to roam")
	if w.roads == null:
		w.free()
		return
	# A junction 400 m and more off the planned road, with a road out of it.
	var net := w.roads.net
	var start := -1
	for n in region.node_count():
		var p := region.node_pos[n]
		var hit := w.route.locate(p.x, p.y)
		if region.adjacent[n].size() >= 3 and (hit.is_empty() or absf(float(hit["lat"])) > 400.0) and absf(p.x) < 3000.0 and absf(p.y) < 3000.0:
			start = n
			break
	check(start >= 0, "a junction well off the planned road")
	if start < 0:
		w.free()
		return
	var arm: Dictionary = net.junction_of(start)["arms"][0]
	var m: Vector3 = arm["mouth"]
	var h := float(arm["heading"])
	var bike := Bike.new()
	var focus := [Vector3.ZERO]
	w.focus = func(): return [bike.position if bike.is_inside_tree() else focus[0]]
	t.add_child(w)
	w.shift_origin_to(w.to_local_pos(m.x, 0.0, m.z))
	var at := w.to_local_pos(m.x, 0.0, m.z) + Vector3(sin(h), 0.0, -cos(h)) * 6.0
	focus[0] = at
	w.roads.preload_round([Vector2(m.x, m.z)], 300.0)
	check(w.roads.has_ground(m.x, m.z), "its block is in the world under the rider")
	var on := net.locate(m.x + sin(h) * 6.0, m.z - cos(h) * 6.0)
	bike.setup(BikeBuild.new({}))
	w.add_child(bike)
	bike.place(Vector3(at.x, float(on.get("y", m.y)) + 0.4, at.z), -h)
	bike.engine_on = true
	bike.assist = 1.0
	check(w.surface_local(at) == net.region.surface_of(int(arm["edge"])), "the surface under it is its road's (%s)" % w.surface_local(at))
	check(w.locate_local(at).is_empty(), "the planned road doesn't answer this far off it")
	var lowest := INF
	var start_pos := bike.position
	for i in 480:
		bike.throttle = 0.5
		await t.get_tree().physics_frame
		var xz := w.route_xz(bike.position)
		var hit := net.locate(xz[0], xz[1])
		if not hit.is_empty():
			lowest = minf(lowest, bike.position.y - float(hit["y"]))
	var ridden := Vector2(bike.position.x - start_pos.x, bike.position.z - start_pos.z).length()
	check(lowest > -0.6, "it rides on the road, not through it (lowest %.2f m from the deck)" % lowest)
	check(ridden > 15.0, "and goes (%.0f m in 4 s)" % ridden)
	check(w.roads.blocks.size() >= 1 and w.chunks.is_empty(), "blocks, and none of the planned road's chunks (%d blocks)" % w.roads.blocks.size())
	w.queue_free()
	RealLand.roam = false
	await t.get_tree().process_frame


## The land the roads cut into, on a real place (the postcards' Dales, offline): RealLand draws the cells the roads
## shape finer (RealLand.FINE), each finer point on the land the net cuts, or on the straight side of a cell next to it
## that isn't finer (so there's no crack between them), and no land stands over a road's deck.
func test_land() -> void:
	var was := [CellStore.dir, CellStore.offline, RealRegion.cell_dirs, HeightTiles.dirs, HeightTiles.offline, HeightTiles.disk,
		AdventureWorld.network]
	var pc = load("res://tests/postcards/postcards.gd")
	pc.use_own_world()
	HeightTiles.reset()
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://tests/postcards/places.json"))
	var place: Dictionary = (spec["places"] as Array).filter(func(p): return p["id"] == "dales")[0]
	var plan: Dictionary = pc.plan_of(place)
	var res := AdventurePlans.result(plan, true)
	check(bool(res.get("ok", false)), "the Dales ride plans from the postcards' world")
	if bool(res.get("ok", false)):
		var w := AdventureWorld.new()
		AdventureWorld.network = true
		w.roads_region = RealRegion.get_region(str(plan["region"]))
		w.setup(res["pack"], 1)
		var land: RealLand = w.land
		var net: RoadNet = land.roads
		var xz := w.route.xz_at(w.route.length * 0.35, 0.0)
		var key := Vector2i(floori(xz[0] / RealLand.BLOCK), floori(xz[1] / RealLand.BLOCK))
		var t0 := Time.get_ticks_msec()
		var arr = land._block_arrays(key, 0)
		var ms := Time.get_ticks_msec() - t0
		var n: int = RealLand.CELLS[0] + 1
		var fs: float = RealLand.BLOCK / RealLand.CELLS[0] / RealLand.FINE
		var o := Vector2(key) * RealLand.BLOCK
		var finer := 0
		var off_land := 0
		var over := 0.0
		if arr is Array:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var skirts := 4 * (RealLand.CELLS[0] * RealLand.FINE + 1)
			for i in range(n * n, v.size()):
				var p := v[i]
				var x := o.x + p.x
				var z := o.y + p.z
				if p.z < -0.01 or p.y < -1000.0:
					continue
				# (the skirts hang under the edge: only the ground's own points)
				if i >= v.size() - skirts and (is_zero_approx(p.x) or is_zero_approx(p.z) or is_equal_approx(p.x, RealLand.BLOCK) or is_equal_approx(p.z, RealLand.BLOCK)):
					continue
				finer += 1
				var I := roundi(p.x / fs)
				var J := roundi(p.z / fs)
				var on_side := I % RealLand.FINE == 0 or J % RealLand.FINE == 0
				# (the bare ground under a finer point is the cell's corners', in between: the tiles are coarser than a cell)
				var sp: float = fs * RealLand.FINE
				var cx := o.x + floorf(p.x / sp) * sp
				var cz := o.y + floorf(p.z / sp) * sp
				var tx := (x - cx) / sp
				var tz := (z - cz) / sp
				var bare := lerpf(lerpf(w.route.ground_at(cx, cz), w.route.ground_at(cx + sp, cz), tx),
						lerpf(w.route.ground_at(cx, cz + sp), w.route.ground_at(cx + sp, cz + sp), tx), tz)
				var want := net.ground_at(x, z, bare)
				if absf(p.y - want) > 0.02 and not on_side:
					off_land += 1
				var hit := net.locate(x, z)
				if not hit.is_empty() and bool(hit["on_road"]) and int(hit["node"]) < 0 and net.bridge_at(int(hit["edge"]), float(hit["s"])) <= 0.0:
					over = maxf(over, p.y - float(hit["y"]))
		print("  road land: a near block in %d ms, %d finer points" % [ms, finer])
		check(arr is Array and finer > 500, "the cells the roads cut into are drawn finer (%d finer points)" % finer)
		check(off_land == 0, "each finer point inside a cell is on the land the roads cut (%d off it)" % off_land)
		check(over <= 0.01, "and none stands over a road's deck (the most %.2f m over)" % over)
		check(ms < 3000, "a near block lays out in good time (%d ms)" % ms)
		# The roadside, as the planned road's: the Dales' marker posts on the verge, rocks and bushes out past it.
		var posts := 0
		var astray := 0
		var stones := 0
		var others := {}
		var b0 := RoadBlock.key_of(xz[0], xz[1])
		for dk: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var b := RoadBlock.build(net, b0 + dk)
			for kind: String in b.roadside:
				for xf: Transform3D in b.roadside[kind]:
					posts += 1
					var at := xf.origin + b.anchor()
					var hit := net.locate(at.x, at.z)
					if hit.is_empty() or int(hit["node"]) >= 0 or absf(float(hit["lat"])) < float(hit["width"]) * 0.5 + 0.5:
						astray += 1
			for kind: String in ["rock", "bush"]:
				stones += (b.trees.get(kind, []) as Array).size()
			for kind: String in b.trees:
				if not kind in AdventureChunk.TREES and not kind in ["rock", "bush"]:
					others[kind] = int(others.get(kind, 0)) + (b.trees[kind] as Array).size()
		print("  road land: %d posts by the road, %d rocks and bushes, in five blocks; and %s" % [posts, stones, str(others)])
		check(posts > 20, "the roads have their marker posts and fences (%d)" % posts)
		check(astray == 0, "each stands on the verge, off the road and out of the junctions (%d not)" % astray)
		check(stones > 20, "rocks and bushes stand out from the verge (%d)" % stones)
		var plants: Dictionary = net.dress.get("look", {}).get("plants", {})
		var missing := plants.keys().filter(func(k): return not k in AdventureChunk.TREES and int(plants[k]) >= 50 and not others.has(k) and not k in ["rock", "bush"])
		check(not others.is_empty() and missing.is_empty(), "and the place's other plants and beasts as the planned road has them (%s; %s missing)" % [str(others), str(missing)])
		w.free()
	CellStore.dir = was[0]
	CellStore.offline = was[1]
	RealRegion.cell_dirs = was[2]
	HeightTiles.dirs = was[3]
	HeightTiles.offline = was[4]
	HeightTiles.disk = was[5]
	AdventureWorld.network = was[6]
	HeightTiles.reset()
	PlaceProfile.forget()
