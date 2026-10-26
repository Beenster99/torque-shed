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
## The deck's points across (edge, quarter, crown, quarter, edge), as the single-line road's.
const ACROSS := 5
## The verge's skirt: from the verge's outer edge it runs this far further out and down under the land (m).
const SKIRT_OUT := 0.8
const SKIRT_DOWN := 0.6
## The white lines: an edge line this far in from the edge (m), this wide, on roads at least EDGE_LINE_MIN wide; a
## centre line's dashes DASH on, GAP off (m), on two-lane roads; all LINE_LIFT above the deck.
const LINE_IN := 0.3
const LINE_W := 0.12
const EDGE_LINE_MIN := 4.5
const DASH := 3.0
const GAP := 6.0
const LINE_LIFT := 0.012
## A roundabout's island stands this high, its kerb this wide (m).
const ISLAND_H := 0.15
const ISLAND_KERB := 0.3
const ISLAND_GRASS := Color(0.3, 0.42, 0.2)
const KERB := Color(0.62, 0.62, 0.6)
## The debug ground's cells (m): a plain grid of the land, roads cut in, under each block until the terrain's own land
## follows the network (T5).
const GROUND_CELL := 8.0

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
## Set by the streamer when the ground under it sharpened while it was being laid out (it's laid out again).
var stale := false


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
	b._lay_out()
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


# ---------------------------------------------------------------------------- the meshes

## The block's corner in the region frame: its meshes are laid out from here (small numbers however far out it is).
func anchor() -> Vector3:
	return Vector3(rect.position.x, 0.0, rect.position.y)


## Lays the block's meshes and collision out into `arrays`: {deck: {surface: grid arrays}, verge, lines, island,
## buildings (AdventureProps arrays; the buildings as the single-line ride draws them until T8's kits), faces: {surface:
## collision triangles}, and with the net's debug_ground its ground}.
func _lay_out() -> void:
	arrays = {"deck": {}, "verge": AdventureProps.new_arrays(), "lines": AdventureProps.new_arrays(),
		"island": AdventureProps.new_arrays(), "faces": {}}
	for p in pieces:
		_piece_mesh(p)
	for j in junctions:
		_junction_mesh(j)
	_join_caps()
	var houses := AdventureProps.new_arrays()
	var o := anchor()
	for row: Array in buildings:
		AdventureProps.real_building(houses, Vector3(float(row[0]), float(row[row.size() - 1]), float(row[1])) - o, float(row[2]),
			float(row[3]), float(row[4]), float(row[5]), RealPack.BUILDING_KINDS[clampi(int(row[6]), 0, RealPack.BUILDING_KINDS.size() - 1)])
	arrays["buildings"] = houses
	if net.debug_ground:
		_ground_mesh()
	for surf in arrays["deck"]:
		_finish_grid(arrays["deck"][surf])


## An empty indexed mesh's arrays.
static func _grid_arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(),
		"i": PackedInt32Array()}


func _deck_of(surf: String) -> Dictionary:
	var d: Dictionary = arrays["deck"]
	if not d.has(surf):
		d[surf] = _grid_arrays()
	return d[surf]


func _faces_of(surf: String) -> PackedVector3Array:
	var f: Dictionary = arrays["faces"]
	if not f.has(surf):
		f[surf] = PackedVector3Array()
	return f[surf]


## Adds triangle (p0, p1, p2) facing up to collision `surf`.
func _face(surf: String, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	_faces_of(surf)
	arrays["faces"][surf].append_array([p0, p1, p2])


## Adds triangle (p0, p1, p2) to AdventureProps arrays `a`, facing up whichever way round it's given.
static func _up(a: Dictionary, p0: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
	if (p1 - p0).cross(p2 - p0).y >= 0.0:
		AdventureProps._tri(a, p0, p1, p2, col)
	else:
		AdventureProps._tri(a, p0, p2, p1, col)


## Adds triangle (i0, i1, i2) of grid `g` (its vertices `v`, which may not be in it yet) facing up.
static func _grid_tri(g: Dictionary, v: PackedVector3Array, i0: int, i1: int, i2: int) -> void:
	if (v[i1] - v[i0]).cross(v[i2] - v[i0]).y < 0.0:
		var t := i1
		i1 = i2
		i2 = t
	# (Godot's front faces are clockwise: stored the other way round from how the normal is worked out)
	g["i"].append_array([i0, i2, i1])


## Grid `g`'s normals, from its faces.
static func _finish_grid(g: Dictionary) -> void:
	var v: PackedVector3Array = g["v"]
	var idx: PackedInt32Array = g["i"]
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	for k in range(0, idx.size(), 3):
		var n := (v[idx[k + 2]] - v[idx[k]]).cross(v[idx[k + 1]] - v[idx[k]])
		nrm[idx[k]] += n
		nrm[idx[k + 1]] += n
		nrm[idx[k + 2]] += n
	for k in nrm.size():
		nrm[k] = nrm[k].normalized() if nrm[k].length_squared() > 0.0 else Vector3.UP
	g["n"] = nrm


## The way along a piece's points at point `k` (radians clockwise from north).
static func _heading(pts: PackedVector3Array, k: int) -> float:
	var a := pts[maxi(k - 1, 0)]
	var b := pts[mini(k + 1, pts.size() - 1)]
	return RoadNet._bearing(Vector2(b.x - a.x, b.z - a.z))


## A piece's deck (ACROSS points across, crowned), its verges and skirts, its lines, and their collision.
func _piece_mesh(p: Dictionary) -> void:
	var pts: PackedVector3Array = p["points"]
	var rows := pts.size()
	if rows < 2:
		return
	var surf := str(p["surface"])
	var col: Color = AdventureSurface.ROAD_COLOR.get(surf, AdventureSurface.ROAD_COLOR["tarmac"])
	var verge_col: Color = AdventureSurface.VERGE_COLOR.get(surf, AdventureSurface.VERGE_COLOR["tarmac"])
	var e := float(p["width"]) * 0.5
	var o := anchor()
	var g := _deck_of(surf)
	var base := (g["v"] as PackedVector3Array).size()
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var cols := PackedColorArray()
	var s0 := float(p["s0"])
	var s := s0
	var rights := []
	for k in rows:
		if k > 0:
			s += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
		var h := _heading(pts, k)
		var right := Vector3(cos(h), 0.0, sin(h))
		rights.append(right)
		var c := pts[k] - o
		for q in ACROSS:
			var f := float(q) / float(ACROSS - 1) * 2.0 - 1.0
			v.append(c + right * (f * e) + Vector3(0.0, RoadNet.CROWN * (1.0 - f * f), 0.0))
			uv.append(Vector2(f * e / 3.0, s / 3.0))
			cols.append(col)
	var faces := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in rows - 1:
		for q in ACROSS - 1:
			var bl := k * ACROSS + q
			for tri: Array in [[bl, bl + ACROSS, bl + ACROSS + 1], [bl, bl + ACROSS + 1, bl + 1]]:
				var i0: int = tri[0]
				var i1: int = tri[1]
				var i2: int = tri[2]
				if (v[i1] - v[i0]).cross(v[i2] - v[i0]).y < 0.0:
					var t := i1
					i1 = i2
					i2 = t
				idx.append_array([base + i0, base + i2, base + i1])
				faces.append_array([v[i0], v[i1], v[i2]])
	g["v"].append_array(v)
	g["uv"].append_array(uv)
	g["c"].append_array(cols)
	g["i"].append_array(idx)
	_faces_of(surf)
	arrays["faces"][surf].append_array(faces)
	# The verges, level with the road's edge, then the skirt down under the land.
	var verge: Dictionary = arrays["verge"]
	for k in rows - 1:
		for side: float in [-1.0, 1.0]:
			var a := pts[k] - o
			var b := pts[k + 1] - o
			var ra: Vector3 = rights[k] * side
			var rb: Vector3 = rights[k + 1] * side
			var a0 := a + ra * e
			var b0 := b + rb * e
			var a1 := a + ra * (e + RoadNet.VERGE) + Vector3(0.0, -0.03, 0.0)
			var b1 := b + rb * (e + RoadNet.VERGE) + Vector3(0.0, -0.03, 0.0)
			var a2 := a + ra * (e + RoadNet.VERGE + SKIRT_OUT) + Vector3(0.0, -SKIRT_DOWN, 0.0)
			var b2 := b + rb * (e + RoadNet.VERGE + SKIRT_OUT) + Vector3(0.0, -SKIRT_DOWN, 0.0)
			_up(verge, a0, b0, b1, verge_col)
			_up(verge, a0, b1, a1, verge_col)
			_up(verge, a1, b1, b2, verge_col.darkened(0.1))
			_up(verge, a1, b2, a2, verge_col.darkened(0.1))
			_face("grass", a0, b0, b1)
			_face("grass", a0, b1, a1)
	if surf == "tarmac":
		_piece_lines(p, pts, rights, e, s0)


## A tarmac piece's edge lines and centre dashes.
func _piece_lines(p: Dictionary, pts: PackedVector3Array, rights: Array, e: float, s0: float) -> void:
	var lines: Dictionary = arrays["lines"]
	var o := anchor()
	var white := Color(0.88, 0.88, 0.84)
	var lift := Vector3(0.0, LINE_LIFT, 0.0)
	var offs := []
	if e * 2.0 >= EDGE_LINE_MIN:
		offs.append(-(e - LINE_IN))
		offs.append(e - LINE_IN)
	var s := s0
	for k in pts.size() - 1:
		var step := Vector2(pts[k + 1].x - pts[k].x, pts[k + 1].z - pts[k].z).length()
		var a := pts[k] - o + lift
		var b := pts[k + 1] - o + lift
		var ra: Vector3 = rights[k]
		var rb: Vector3 = rights[k + 1]
		for lat: float in offs:
			var f := lat / maxf(e, 0.1)
			var crown := Vector3(0.0, RoadNet.CROWN * (1.0 - f * f), 0.0)
			_up(lines, a + ra * (lat - LINE_W * 0.5) + crown, b + rb * (lat - LINE_W * 0.5) + crown, b + rb * (lat + LINE_W * 0.5) + crown, white)
			_up(lines, a + ra * (lat - LINE_W * 0.5) + crown, b + rb * (lat + LINE_W * 0.5) + crown, a + ra * (lat + LINE_W * 0.5) + crown, white)
		if int(p["lanes"]) == 2:
			# Dashes by distance along the edge, so they carry on across a block's seam.
			var d0 := fposmod(s, DASH + GAP)
			if d0 < DASH:
				var len := minf(DASH - d0, step)
				var t := len / maxf(step, 0.01)
				var bb := a.lerp(b, t)
				var rr: Vector3 = ra.lerp(rb, t)
				var c := Vector3(0.0, RoadNet.CROWN, 0.0)
				_up(lines, a - ra * LINE_W * 0.5 + c, bb - rr * LINE_W * 0.5 + c, bb + rr * LINE_W * 0.5 + c, white)
				_up(lines, a - ra * LINE_W * 0.5 + c, bb + rr * LINE_W * 0.5 + c, a + ra * LINE_W * 0.5 + c, white)
		s += step


## A junction's surface: a fan from its middle over its outline (a roundabout: its island, and the mouths of the roads
## onto its ring), at the heights of the roads meeting it.
func _junction_mesh(j: Dictionary) -> void:
	var o := anchor()
	var arms: Array = j["arms"]
	var surf := "tarmac"
	for a in arms:
		if net.region.surface_of(int(a["edge"])) != "tarmac":
			surf = net.region.surface_of(int(a["edge"]))
		else:
			surf = "tarmac"
			break
	var col: Color = AdventureSurface.ROAD_COLOR.get(surf, AdventureSurface.ROAD_COLOR["tarmac"])
	var g := _deck_of(surf)
	var centre: Vector3 = j["pos"]
	if j["kind"] in ["roundabout", "mini"]:
		for a in arms:
			var node := int(a["node"])
			var np := net.region.node_pos[node]
			var at := Vector3(np.x, net.node_y(node), np.y)
			var m: Vector3 = a["mouth"]
			var out := RoadNet._bearing(Vector2(m.x - at.x, m.z - at.z))
			var right := Vector3(cos(out), 0.0, sin(out)) * float(a["width"]) * 0.5
			var ring_e := float(j.get("ring_w", 7.0)) * 0.5
			var back := Vector3(sin(out), 0.0, -cos(out)) * -ring_e
			_fan(g, surf, col, at - o, [at + back - right * 1.6 - o, m - right - o, m + right - o, at + back + right * 1.6 - o])
		_island(j)
		return
	var outline: PackedVector2Array = j["outline"]
	var pts := []
	for k in outline.size():
		var y := centre.y
		if j["kind"] != "end":
			y = float((arms[k / 2]["mouth"] as Vector3).y)
		pts.append(Vector3(outline[k].x, y, outline[k].y) - o)
	_fan(g, surf, col, centre - o, pts, j["kind"] != "end")


## A fan of triangles from `c` round `pts` (closed if `closed`), into grid `g` and collision `surf`.
func _fan(g: Dictionary, surf: String, col: Color, c: Vector3, pts: Array, closed := false) -> void:
	var base := (g["v"] as PackedVector3Array).size()
	var v := PackedVector3Array([c])
	for p: Vector3 in pts:
		v.append(p)
	for k in v.size():
		g["uv"].append(Vector2(v[k].x, v[k].z) / 3.0)
		g["c"].append(col)
	var count := pts.size() if closed else pts.size() - 1
	for k in count:
		var i1 := 1 + k
		var i2 := 1 + (k + 1) % pts.size()
		if (v[i1] - v[0]).cross(v[i2] - v[0]).y < 0.0:
			var t := i1
			i1 = i2
			i2 = t
		g["i"].append_array([base, base + i2, base + i1])
		_face(surf, v[0], v[i1], v[i2])
	g["v"].append_array(v)


## A roundabout's island: a kerbed disc of grass a little above the ring.
func _island(j: Dictionary) -> void:
	var r := float(j["island"])
	if r <= 0.5:
		return
	var a: Dictionary = arrays["island"]
	var c: Vector3 = j["pos"] - anchor()
	var n := 24
	for k in n:
		var t0 := TAU * k / n
		var t1 := TAU * (k + 1) / n
		var d0 := Vector3(sin(t0), 0.0, -cos(t0))
		var d1 := Vector3(sin(t1), 0.0, -cos(t1))
		var top := Vector3(0.0, ISLAND_H, 0.0)
		var low := Vector3(0.0, -0.1, 0.0)
		_up(a, c + top, c + d0 * (r - ISLAND_KERB) + top, c + d1 * (r - ISLAND_KERB) + top, ISLAND_GRASS)
		_up(a, c + d0 * (r - ISLAND_KERB) + top, c + d0 * r + top, c + d1 * r + top, KERB)
		_up(a, c + d0 * (r - ISLAND_KERB) + top, c + d1 * r + top, c + d1 * (r - ISLAND_KERB) + top, KERB)
		# The kerb's face, out towards the ring.
		AdventureProps._quad(a, c + d0 * r + low, c + d1 * r + low, c + d1 * r + top, c + d0 * r + top, KERB)
		_face("grass", c + top, c + d0 * r + top, c + d1 * r + top)


## Where two roads join end to end (no junction) at an angle or with different widths, a disc of road at the node
## fills the wedge between their ends.
func _join_caps() -> void:
	var r := net.region
	var o := anchor()
	for node in net.nodes_in(key):
		if r.adjacent[node].size() != 2 or not net.junction_of(node).is_empty():
			continue
		var e0 := r.adjacent[node][0]
		var e1 := r.adjacent[node][1]
		var w := maxf(net.width_of(e0), net.width_of(e1))
		var h0 := net.heading_at(e0, 0.0 if r.edge_a[e0] == node else net.length_of(e0))
		var h1 := net.heading_at(e1, 0.0 if r.edge_a[e1] == node else net.length_of(e1))
		var turn := absf(PI - RoadNet._angle_between(h0, h1)) if (r.edge_a[e0] == node) != (r.edge_a[e1] == node) else RoadNet._angle_between(h0, h1)
		if turn < deg_to_rad(4.0) and is_equal_approx(net.width_of(e0), net.width_of(e1)):
			continue
		var surf := r.surface_of(e0)
		var col: Color = AdventureSurface.ROAD_COLOR.get(surf, AdventureSurface.ROAD_COLOR["tarmac"])
		var c := Vector3(r.node_pos[node].x, net.node_y(node), r.node_pos[node].y)
		var ring := []
		for k in 12:
			var t := TAU * k / 12.0
			ring.append(c + Vector3(sin(t), 0.0, -cos(t)) * w * 0.5 - o)
		_fan(_deck_of(surf), surf, col, c - o, ring, true)


## The debug ground: the land of the whole block on a GROUND_CELL grid, the roads cut in (RoadNet.ground_at).
func _ground_mesh() -> void:
	var cells := int(SIZE / GROUND_CELL)
	var g := _grid_arrays()
	var land: Color = AdventureSurface.LAND_COLOR["tarmac"]
	for iz in cells + 1:
		for ix in cells + 1:
			var x := rect.position.x + ix * GROUND_CELL
			var z := rect.position.y + iz * GROUND_CELL
			var bare := float(net.height.call(x, z))
			var y := net.ground_at(x, z, bare)
			g["v"].append(Vector3(ix * GROUND_CELL, y, iz * GROUND_CELL))
			g["uv"].append(Vector2(x, z) * 0.1)
			g["c"].append(land.lerp(AdventureSurface.LAND_PATCH["tarmac"], 0.5 + 0.5 * sin(x * 0.013 + z * 0.021)))
	var v: PackedVector3Array = g["v"]
	for iz in cells:
		for ix in cells:
			var bl := iz * (cells + 1) + ix
			_grid_tri(g, v, bl, bl + 1, bl + cells + 2)
			_grid_tri(g, v, bl, bl + cells + 2, bl + cells + 1)
			_face("grass", v[bl], v[bl + 1], v[bl + cells + 2])
			_face("grass", v[bl], v[bl + cells + 2], v[bl + cells + 1])
	_finish_grid(g)
	arrays["ground"] = g
