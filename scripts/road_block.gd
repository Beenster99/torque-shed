class_name RoadBlock
extends RefCounted
## The roads of one 512 m square of a ride's region (Ride Anywhere v2, T6): every stretch of road in it (a piece: one
## edge's run inside the square, trimmed back to the junctions' mouths) and every junction whose node is in it, with
## the buildings standing there, laid out as plain data from the RoadNet alone (so it runs on a worker thread, and every
## machine lays out the same block). What a block holds is the interface the other threads build on: see
## ride-anywhere-v2/interfaces/road-block.md, pinned by tests/road_block_tests.gd.

## Bump when what a block holds, or how it's laid out, changes: it's in every block's hash, so a crew on mixed versions
## finds out at the lobby.
const VERSION := 1
const SIZE := 512.0
## A piece cut by the block's edge runs on this far (m) into the next block, so the two decks overlap at the seam.
const SEAM := 0.05

var key := Vector2i.ZERO
var rect := Rect2()
var hash := ""
var pieces: Array[Dictionary] = []
var junctions: Array[Dictionary] = []
var buildings: Array = []
## The mesh and collision arrays the streamer commits (T6's own business; their shape may change freely).
var arrays := {}
var ms := 0.0
var net: RoadNet


## The key of the block (x, z) is in.
static func key_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / SIZE), floori(z / SIZE))


## The hash of block `k` of a region whose hash is `region_hash`.
static func hash_of(region_hash: String, k: Vector2i) -> String:
	return ("%d|%s|%d,%d" % [VERSION, region_hash, k.x, k.y]).sha1_text().substr(0, 12)


## Lays out block `k` of `n`.
static func build(n: RoadNet, k: Vector2i) -> RoadBlock:
	var t0 := Time.get_ticks_usec()
	var b := RoadBlock.new()
	b.net = n
	b.key = k
	b.rect = Rect2(Vector2(k) * SIZE, Vector2(SIZE, SIZE))
	b.hash = hash_of(n.region.hash, k)
	var r := n.region
	var edges := n.edges_in(k)
	for ei in edges:
		b._add_pieces(ei)
	var seen := {}
	for node in n.nodes_in(k):
		var j := n.junction_of(node)
		if j.is_empty() or seen.has(int(j["node"])):
			continue
		# A roundabout is the block's that has its lowest node.
		if key_of(r.node_pos[int(j["node"])].x, r.node_pos[int(j["node"])].y) != k:
			continue
		seen[int(j["node"])] = true
		b.junctions.append(_public(j))
	b.junctions.sort_custom(func(p, q): return int(p["node"]) < int(q["node"]))
	for row: Array in n.buildings_in(k):
		var out := row.duplicate()
		out.append(b._building_y(row))
		b.buildings.append(out)
	b.ms = (Time.get_ticks_usec() - t0) / 1000.0
	return b


## A junction as the interface has it (the net's own working keys left off).
static func _public(j: Dictionary) -> Dictionary:
	var arms := []
	for a: Dictionary in j["arms"]:
		arms.append({"edge": a["edge"], "node": a["node"], "heading": a["heading"], "width": a["width"],
			"class": a["class"], "mouth": a["mouth"], "main": a["main"]})
	return {"node": j["node"], "nodes": j["nodes"], "kind": j["kind"], "pos": j["pos"], "radius": j["radius"],
		"arms": arms, "island": j["island"], "pair": j["pair"], "outline": j["outline"]}


## The pieces of edge `ei` inside this block: its plain road (between its mouths) cut where it crosses the block's
## edges, each run on SEAM past a cut.
func _add_pieces(ei: int) -> void:
	var r := net.region
	var len := net.length_of(ei)
	var s0 := net.mouth(ei, r.edge_a[ei])
	var s1 := len - net.mouth(ei, r.edge_b[ei])
	if s1 - s0 < 0.01:
		return
	# Every STEP along it, and where it crosses in and out of the block.
	var ss := PackedFloat32Array([s0])
	var s := (floorf(s0 / RoadNet.STEP) + 1.0) * RoadNet.STEP
	while s < s1 - 0.01:
		ss.append(s)
		s += RoadNet.STEP
	ss.append(s1)
	var runs := []
	var start := -1.0
	var prev_in := false
	for k in ss.size():
		var p := net.point_at(ei, ss[k])
		var inside := rect.has_point(p)
		if k > 0 and inside != prev_in:
			var cut := _crossing(ei, ss[k - 1], ss[k], prev_in)
			if inside:
				start = maxf(cut - SEAM, s0)
			else:
				runs.append(Vector2(start, minf(cut + SEAM, s1)))
				start = -1.0
		elif k == 0 and inside:
			start = s0
		prev_in = inside
	if prev_in and start >= 0.0:
		runs.append(Vector2(start, s1))
	for run: Vector2 in runs:
		if run.y - run.x < 0.01:
			continue
		var pts := PackedVector3Array()
		var at := PackedFloat32Array([run.x])
		var q := (floorf(run.x / RoadNet.STEP) + 1.0) * RoadNet.STEP
		while q < run.y - 0.01:
			at.append(q)
			q += RoadNet.STEP
		at.append(run.y)
		for a in at:
			var p := net.point_at(ei, a)
			pts.append(Vector3(p.x, net.road_y(ei, a), p.y))
		pieces.append({"edge": ei, "s0": run.x, "s1": run.y, "points": pts, "width": net.width_of(ei),
			"lanes": net.lanes_of(ei), "class": r.class_of(ei), "surface": r.surface_of(ei), "name": r.name_of(ei),
			"oneway": r.edge_oneway[ei], "a": r.edge_a[ei], "b": r.edge_b[ei], "ring": net.on_ring(ei)})


## Where (s) edge `ei` crosses the block's edge between `sa` (inside if `a_in`) and `sb`.
func _crossing(ei: int, sa: float, sb: float, a_in: bool) -> float:
	var lo := sa
	var hi := sb
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if rect.has_point(net.point_at(ei, mid)) == a_in:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## The ground a building stands on: the lowest of the land (roads cut in) under its middle and corners.
func _building_y(row: Array) -> float:
	var bx := float(row[0])
	var bz := float(row[1])
	var w := float(row[2])
	var d := float(row[3])
	var yaw := float(row[4])
	var y := INF
	for cx: float in [0.0, -0.5, 0.5]:
		for cz: float in [0.0, -0.5, 0.5]:
			if (cx == 0.0) != (cz == 0.0):
				continue
			var px := bx + (cx * w) * cos(yaw) + (cz * d) * sin(yaw)
			var pz := bz - (cx * w) * sin(yaw) + (cz * d) * cos(yaw)
			y = minf(y, net.ground_at(px, pz, float(net.height.call(px, pz))))
	return y


## Which road (x, z) is on (RoadNet.locate).
func locate(x: float, z: float) -> Dictionary:
	return net.locate(x, z)
