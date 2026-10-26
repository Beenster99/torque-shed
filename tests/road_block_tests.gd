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


## A roundabout of eight one-way edges, 16 m across from the middle, round (100, 100), with four roads off it.
static func roundabout() -> RealRegion:
	var nodes := []
	var edges := []
	for k in 8:
		var a := TAU * k / 8.0
		nodes.append([100.0 + sin(a) * 16.0, 100.0 - cos(a) * 16.0])
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
		"oneway": TYPE_INT, "a": TYPE_INT, "b": TYPE_INT, "ring": TYPE_BOOL}
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
	var cn := RoadNet.new(cross(), flat)
	var c := cn.junction_of(0)
	check(c["kind"] == "cross" and c["arms"].size() == 4, "a crossroads has four arms")
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
	var sn := RoadNet.new(staggered(), flat)
	check(sn.junction_of(0)["kind"] == "staggered" and int(sn.junction_of(0)["pair"]) == 1, "a tee with one opposite 30 m on is staggered")
	check(sn.junction_of(1)["kind"] == "staggered" and int(sn.junction_of(1)["pair"]) == 0, "both ways")
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
	var rn := RoadNet.new(roundabout(), flat)
	var ring := rn.locate(100.0 + 16.0, 100.0)
	check(int(ring.get("node", -1)) == 0 and rn.on_ring(int(ring["edge"])), "on the ring, at the roundabout")


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


## A road crossing from one block into the next is in both, the two meeting at the seam; the same block twice is the
## same; every piece of road is in a block.
func test_blocks() -> void:
	var r := graph([[-300, 100], [300, 100], [300, 700]], [[0, 1, "primary"], [1, 2, "tertiary", 0, [400, 300, 350, 500]]])
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
