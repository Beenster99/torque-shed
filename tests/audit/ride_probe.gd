extends RefCounted
## Rides the road network as a bike does: along the collision faces of the road blocks the game builds (RoadBlock.build,
## the very triangles the streamer hands the physics), following the surface it's on (where one road crosses over another,
## the one it was on). Each path is sampled every STEP m and judged as a rider feels it:
## - "ride_step": the surface jumping up or down from one metre to the next, off the slope it's on (a kerb-like edge, a
##   slab of road, a seam between a road and a junction) (m);
## - "ride_kink": the slope changing sharply over a couple of metres (an angle in the road, a junction folded across)
##   (the change in grade, as a fraction);
## - "ride_bump": the surface off the average over 30 m about it (a hump or a dip) (m);
## - "ride_hole": a stretch with no road surface under the wheels at all (m).
## Paths: along each road (its middle and either half of it), and through each junction and roundabout from every road
## into it out to every other, curving through its middle as a rider would.

const STEP := 1.0
## How far (m) out along each road a path through a junction starts and ends.
const OUT := 18.0
## What's a fault: a step over STEP_M m, a grade change over KINK in KINK_RUN m, a bump over BUMP_M m.
const STEP_M := 0.06
const KINK := 0.06
const KINK_RUN := 2
## A turn through a junction (or round a roundabout), taken slowly, may change its grade more (the roads either side of
## it climbing different ways): a grade change over KINK_TURN in KINK_RUN m; its bumps are the lie of the roads.
const KINK_TURN := 0.2
const BUMP_M := 0.12
## How far (m) above or below the surface it's on another is looked for (a road under a bridge is further).
const REACH_Y := 1.2
const CELL := 4.0
## How far (m) either side a path through a junction is averaged over to round its corners off (_rounded).
const ROUND := 3.0
## How far (m) past its edge a block's faces may run (a junction laid out by the block with its middle).
const SPILL := 80.0

var net: RoadNet
var _blocks := {}   # Vector2i -> {faces: PackedVector3Array in the region's frame, grid: {Vector2i: PackedInt32Array}}


func _init(n: RoadNet) -> void:
	net = n


## Block `key`'s collision faces, built once, filed in CELL squares.
func _block(key: Vector2i) -> Dictionary:
	if _blocks.has(key):
		return _blocks[key]
	var b := RoadBlock.build(net, key)
	var o := b.anchor()
	var faces := PackedVector3Array()
	# (the road's own decks, whatever they're made of: the same triangles as their collision, without the verges and
	# islands, which are grass)
	for surf: String in b.arrays.get("deck", {}):
		var g: Dictionary = b.arrays["deck"][surf]
		var v: PackedVector3Array = g["v"]
		for i: int in g["i"]:
			faces.append(v[i] + o)
	var grid := {}
	for t in faces.size() / 3:
		var a := faces[t * 3]
		var bb := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		for gz in range(floori(minf(a.z, minf(bb.z, c.z)) / CELL), floori(maxf(a.z, maxf(bb.z, c.z)) / CELL) + 1):
			for gx in range(floori(minf(a.x, minf(bb.x, c.x)) / CELL), floori(maxf(a.x, maxf(bb.x, c.x)) / CELL) + 1):
				var k := Vector2i(gx, gz)
				if not grid.has(k):
					grid[k] = PackedInt32Array()
				var list: PackedInt32Array = grid[k]
				list.append(t)
				grid[k] = list
	var got := {"faces": faces, "grid": grid}
	_blocks[key] = got
	return got


## The height of the road surface at (x, z) nearest `near_y` (within REACH_Y of it, or any when `near_y` is NAN), or NAN
## where there's none.
func height_at(x: float, z: float, near_y: float, reach := REACH_Y) -> float:
	var best := NAN
	var best_d := INF
	# (a road's deck and a junction run a little over into the next block: each is laid out by the block with its middle)
	var home := RoadBlock.key_of(x, z)
	var g := Vector2i(floori(x / CELL), floori(z / CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := home + Vector2i(dx, dz)
			if key != home and not Rect2(Vector2(key) * RoadBlock.SIZE, Vector2(RoadBlock.SIZE, RoadBlock.SIZE)).grow(SPILL).has_point(Vector2(x, z)):
				continue
			var y := _height_in(_block(key), g, x, z, near_y, reach)
			if not is_nan(y) and (is_nan(best) or (not is_nan(near_y) and absf(y - near_y) < best_d)):
				best = y
				best_d = 0.0 if is_nan(near_y) else absf(y - near_y)
	return best


func _height_in(blk: Dictionary, g: Vector2i, x: float, z: float, near_y: float, reach: float) -> float:
	var faces: PackedVector3Array = blk["faces"]
	var best := NAN
	var best_d := INF
	for t: int in blk["grid"].get(g, PackedInt32Array()):
		var a := faces[t * 3]
		var b := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-9:
			continue
		var u := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
		var v := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
		if u < -1e-4 or v < -1e-4 or u + v > 1.0 + 1e-4:
			continue
		var y := a.y * u + b.y * v + c.y * (1.0 - u - v)
		var d := 0.0 if is_nan(near_y) else absf(y - near_y)
		if d < best_d and (is_nan(near_y) or d <= reach):
			best_d = d
			best = y
	return best


## Rides `path` (region frame, any spacing) from height `y0`: {length, holes (m), step, kink, bump, and where each worst is}.
func ride(path: PackedVector2Array, y0: float) -> Dictionary:
	var pts := _resample(path)
	var h := PackedFloat32Array()
	h.resize(pts.size())
	var last := y0
	var holes := 0.0
	var lost := false
	for i in pts.size():
		var y := height_at(pts[i].x, pts[i].y, last)
		if is_nan(y) and lost:
			y = height_at(pts[i].x, pts[i].y, last, INF)   # (past a hole, onto whichever road's there nearest)
		if is_nan(y):
			holes += STEP
			lost = true
		else:
			last = y
			lost = false
		h[i] = y
	var out := {"length": pts.size() * STEP, "holes": holes, "step": 0.0, "kink": 0.0, "bump": 0.0,
		"step_at": Vector2.ZERO, "kink_at": Vector2.ZERO, "bump_at": Vector2.ZERO, "hole_at": Vector2.ZERO}
	for i in pts.size():
		if is_nan(h[i]):
			out["hole_at"] = pts[i]
			break
	# A step: one metre's rise off the slope either side of it.
	for i in range(1, pts.size() - 2):
		if is_nan(h[i - 1] + h[i] + h[i + 1] + h[i + 2]):
			continue
		var slope := ((h[i] - h[i - 1]) + (h[i + 2] - h[i + 1])) * 0.5
		var off := absf((h[i + 1] - h[i]) - slope)
		if off > float(out["step"]):
			out["step"] = off
			out["step_at"] = pts[i]
	# A kink: the grade over KINK_RUN m against the grade over the KINK_RUN m before.
	for i in range(KINK_RUN, pts.size() - KINK_RUN):
		if is_nan(h[i - KINK_RUN] + h[i] + h[i + KINK_RUN]):
			continue
		var g0 := (h[i] - h[i - KINK_RUN]) / (KINK_RUN * STEP)
		var g1 := (h[i + KINK_RUN] - h[i]) / (KINK_RUN * STEP)
		if absf(g1 - g0) > float(out["kink"]):
			out["kink"] = absf(g1 - g0)
			out["kink_at"] = pts[i]
	# A bump: off the average over 30 m about it.
	var half := 15
	for i in range(half, pts.size() - half):
		var sum := 0.0
		var n := 0
		for j in range(i - half, i + half + 1):
			if not is_nan(h[j]):
				sum += h[j]
				n += 1
		if n < half or is_nan(h[i]):
			continue
		var d := absf(h[i] - sum / n)
		if d > float(out["bump"]):
			out["bump"] = d
			out["bump_at"] = pts[i]
	return out


## `path` with its corners rounded off as a rider takes them (its points every STEP m, each the average of those
## ROUND m either side, a few times over; its ends kept).
static func _rounded(path: PackedVector2Array) -> PackedVector2Array:
	var pts := _resample(path)
	var half := int(ROUND / STEP)
	for _pass in 3:
		var out := pts.duplicate()
		for i in range(1, pts.size() - 1):
			var h := mini(half, mini(i, pts.size() - 1 - i))
			var sum := Vector2.ZERO
			for j in range(i - h, i + h + 1):
				sum += pts[j]
			out[i] = sum / float(2 * h + 1)
		pts = out
	return pts


## `path` every STEP m along it.
static func _resample(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.size() < 2:
		return out
	out.append(path[0])
	var carry := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var len := a.distance_to(b)
		var d := STEP - carry
		while d <= len:
			out.append(a.lerp(b, d / len))
			d += STEP
		carry = len - (d - STEP)
	return out


## The paths to ride in block `key`: [{path, y0, what, edge or node}]: each road through it, along its middle and either
## half (OUT m short of its ends, which the junctions' paths ride), and each junction with its middle in it, from every
## road into it out to every other.
func paths_in(key: Vector2i) -> Array:
	var out := []
	var rect := Rect2(Vector2(key) * RoadBlock.SIZE, Vector2(RoadBlock.SIZE, RoadBlock.SIZE))
	for ei in net.edges_in(key):
		var len := net.length_of(ei)
		if len < OUT * 2.0 + 10.0:
			continue
		var mid := net.point_at(ei, len * 0.5)
		if not rect.has_point(mid):
			continue   # (each road's in the block that has its middle)
		var quarter := net.width_of(ei) * 0.25
		for lat: float in [0.0, -quarter, quarter]:
			var path := PackedVector2Array()
			var s := OUT
			while s <= len - OUT:
				var h := net.heading_at(ei, s)
				path.append(net.point_at(ei, s) + Vector2(cos(h), sin(h)) * lat)
				s += 2.0
			out.append({"path": path, "y0": net.road_y(ei, OUT), "what": "road", "edges": [ei]})
	var seen := {}
	for node in net.nodes_in(key):
		if net.region.adjacent[node].size() < 3:
			continue
		var j := net.junction_of(node)
		if j.is_empty() or j["kind"] == "end" or seen.has(int(j["node"])):
			continue
		seen[int(j["node"])] = true
		var c: Vector3 = j["pos"]
		if not rect.has_point(Vector2(c.x, c.z)):
			continue
		var arms: Array = j["arms"]
		for ia in arms.size():
			for ib in arms.size():
				if ia == ib:
					continue
				var pa := _arm_out(arms[ia])
				if pa.is_empty() or _arm_out(arms[ib]).is_empty():
					continue
				var ma: Vector3 = arms[ia]["mouth"]
				var mb: Vector3 = arms[ib]["mouth"]
				var na := int(arms[ia]["node"])
				var nb := int(arms[ib]["node"])
				var path := _arm_line(arms[ia])
				path.reverse()
				if na != nb:
					# (round a roundabout's ring, or along the roads between a compound junction's nodes, the shorter
					# way from the one arm's node to the other's)
					path.append_array(_within(j, na, nb))
				else:
					# (through the middle on a curve from one mouth to the other, as a rider takes it)
					var mid := net.region.node_pos[na] if (j["nodes"] as PackedInt32Array).size() > 1 else Vector2(c.x, c.z)
					for k in range(1, 12):
						var t := k / 12.0
						path.append(Vector2(ma.x, ma.z).lerp(mid, t).lerp(mid.lerp(Vector2(mb.x, mb.z), t), t))
				path.append_array(_arm_line(arms[ib]))
				path = _rounded(path)
				var through: bool = arms[ia]["main"] and arms[ib]["main"] and not j["kind"] in ["roundabout", "mini"]
				out.append({"path": path, "y0": float(pa[1]), "what": str(j["kind"]), "node": int(j["node"]), "turn": not through,
					"edges": [int(arms[ia]["edge"]), int(arms[ib]["edge"])]})
	return out


## The way through junction `j` from its node `from` to its node `to` (round a roundabout's ring, or along the roads
## between a compound junction's nodes), the shorter way: their lines, every 2 m.
func _within(j: Dictionary, from: int, to: int) -> PackedVector2Array:
	var r := net.region
	var ring := {}
	for n in j["nodes"]:
		ring[n] = true
	# (the shortest way along the roads between them: a handful of nodes)
	var dist := {from: 0.0}
	var via := {}
	var open := [from]
	while not open.is_empty():
		var n: int = open.pop_front()
		for ei in r.adjacent[n]:
			var m := r.other_end(ei, n)
			if not ring.has(m) or m == n:
				continue
			var d := float(dist[n]) + net.length_of(ei)
			if d < float(dist.get(m, INF)):
				dist[m] = d
				via[m] = [ei, n]
				open.append(m)
	var out := PackedVector2Array()
	if not via.has(to):
		return out
	var legs := []
	var n := to
	while n != from:
		legs.push_front(via[n])
		n = int(via[n][1])
	for leg: Array in legs:
		var ei := int(leg[0])
		var len := net.length_of(ei)
		var fwd := r.edge_a[ei] == int(leg[1])
		var s := 0.0
		while s <= len:
			out.append(net.point_at(ei, s if fwd else len - s))
			s += 2.0
	return out


## Along arm `a` from its mouth out OUT m, every 2 m.
func _arm_line(a: Dictionary) -> PackedVector2Array:
	var ei := int(a["edge"])
	var len := net.length_of(ei)
	var from_a := net.region.edge_a[ei] == int(a["node"])
	var m := float(a.get("mouth_s", 0.0))
	var out := PackedVector2Array()
	var d := 0.0
	while d <= OUT + 0.01:
		out.append(net.point_at(ei, m + d if from_a else len - m - d))
		d += 2.0
	return out


## Where a path into a junction along arm `a` starts (OUT m out past its mouth) and the road's height there: [Vector2,
## y], or [] where the road's too short.
func _arm_out(a: Dictionary) -> Array:
	var ei := int(a["edge"])
	var len := net.length_of(ei)
	var from_a := net.region.edge_a[ei] == int(a["node"])
	var m := float(a.get("mouth_s", 0.0))
	var s := m + OUT if from_a else len - m - OUT
	if s < 0.0 or s > len:
		return []
	return [net.point_at(ei, s), net.road_y(ei, s)]


## (debugging) Every face's height at (x, z).
func heights_all(x: float, z: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var home := RoadBlock.key_of(x, z)
	var blk := _block(home)
	var faces: PackedVector3Array = blk["faces"]
	for t: int in blk["grid"].get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array()):
		var a := faces[t * 3]
		var b := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-9:
			continue
		var u := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
		var v := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
		if u < -1e-4 or v < -1e-4 or u + v > 1.0 + 1e-4:
			continue
		out.append(a.y * u + b.y * v + c.y * (1.0 - u - v))
	return out
