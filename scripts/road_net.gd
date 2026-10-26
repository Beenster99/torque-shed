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
## The cutting or embankment past the verge: as wide as the height it makes up times BANK_SLOPE, between BANK_MIN and
## BANK_MAX (m).
const BANK_SLOPE := 1.5
const BANK_MIN := 4.0
const BANK_MAX := 40.0
## A tee with another on the far side of its main road within this distance (m) is a staggered junction.
const STAGGER := 40.0
## The heights along an edge are smoothed over this many STEPs, three times over (much like a bell curve some 50 m
## across), then eased over EASE m at each end onto the height of the node there, which every road meeting there shares.
const FAIR_STEPS := 7
const EASE := 40.0
## The smoothed heights are worked out PAGE samples at a time, from the bare ones PAGE_PAD either side (as far as three
## passes of FAIR_STEPS reach).
const PAGE := 64
const PAGE_PAD := 9
## A junction's arm starts its plain road at least this far (m) past where its kerbs clear the arms either side, and at
## most MOUTH_MOST from the node (and never past half the edge).
const FILLET := 3.0
const MOUTH_MOST := 30.0
## A three-armed junction whose straightest pair of arms is within this much (radians) of straight on is a tee;
## otherwise it's a fork.
const TEE_STRAIGHT := deg_to_rad(35.0)
## The crown of the road (m): its middle is this much higher than its edges, as the single-line road's.
const CROWN := 0.04
## The grid locate and ground_at look a point up in (m a side), within each 512 m block.
const GRID := 32.0

var region: RealRegion
## height(x, z) -> float: the bare ground in the region frame (T5's terrain, asked by position and nothing else).
var height: Callable
## ready(area: Rect2) -> bool: whether the ground under `area` is final (RealTerrain.ready). Heights worked out where it
## isn't are used but not kept, so the net never holds on to a coarse guess. None: always final.
var ready: Callable
## 12 hex of the block builder's version and the region's hash.
var version_hash := ""

var _lock := Mutex.new()
var _edges_by_block := {}   # Vector2i -> PackedInt32Array: the edges whose line's box (with GROUND_REACH) meets it
var _nodes_by_block := {}   # Vector2i -> PackedInt32Array
var _buildings_by_block := {}   # Vector2i -> Array of rows
var _cum := {}              # edge -> PackedFloat32Array: distance along its line at each point
var _fair := {}             # Vector2i(edge, page) -> PackedFloat32Array: its heights smoothed (_fair_page)
var _node_y := {}           # node -> float
var _junction := {}         # node -> Dictionary ({} for a plain join)
var _ring_of := {}          # edge -> PackedInt32Array: the ring of nodes it's part of, or empty
var _grids := {}            # Vector2i block -> {Vector2i cell -> PackedInt32Array of edges}


## How far round a road the land is shaped by it (m past the centre line, at the widest).
static func ground_reach() -> float:
	return 4.0 + VERGE + BANK_MAX


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


## The distance along edge `edge`'s line at each of its points.
func _cum_of(edge: int) -> PackedFloat32Array:
	_lock.lock()
	var c = _cum.get(edge)
	_lock.unlock()
	if c != null:
		return c
	var line := region.edge_line[edge]
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
	return region.edge_len[edge]


## The point `s` m along edge `edge` from its a node (clamped to its ends).
func point_at(edge: int, s: float) -> Vector2:
	var line := region.edge_line[edge]
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


## The bare heights along edge `edge`, smoothed, for its samples in page `page` (PAGE of them): three passes of a moving
## average FAIR_STEPS long, worked out from the bare heights PAGE_PAD samples either side, so a page is the same as the
## whole edge done at once and only needs the ground near it. Kept once the ground there is final.
func _fair_page(edge: int, page: int) -> PackedFloat32Array:
	var key := Vector2i(edge, page)
	_lock.lock()
	var f = _fair.get(key)
	_lock.unlock()
	if f != null:
		return f
	var n := samples_of(edge)
	var len := length_of(edge)
	var k0 := page * PAGE
	var k1 := mini(n, k0 + PAGE)
	# (past its ends the bare heights run on straight out of it, so it's smoothed through a junction, not up to it)
	var lo := k0 - PAGE_PAD
	var hi := k1 + PAGE_PAD
	var sp := len / float(n - 1)
	var h := PackedFloat32Array()
	h.resize(hi - lo)
	var box := Rect2()
	for k in range(lo, hi):
		var p: Vector2
		if k < 0:
			p = point_at(edge, 0.0) + (point_at(edge, 0.0) - point_at(edge, minf(2.0, len))).normalized() * (-k * sp)
		elif k >= n:
			p = point_at(edge, len) + (point_at(edge, len) - point_at(edge, maxf(len - 2.0, 0.0))).normalized() * ((k - n + 1) * sp)
		else:
			p = point_at(edge, sp * k)
		box = Rect2(p, Vector2.ZERO) if k == lo else box.expand(p)
		h[k - lo] = float(height.call(p.x, p.y))
	var half := FAIR_STEPS / 2
	for _pass in 3:
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
		h = out
	var res := h.slice(k0 - lo, k1 - lo)
	if not ready.is_valid() or bool(ready.call(box.grow(STEP))):
		_lock.lock()
		_fair[key] = res
		_lock.unlock()
	return res


## The smoothed bare height of edge `edge`'s sample `k`.
func _fair_at(edge: int, k: int) -> float:
	return _fair_page(edge, k / PAGE)[k % PAGE]


## The height of the road at node `node`, which every road meeting there shares: the mean of their smoothed heights at
## that end.
func node_y(node: int) -> float:
	_lock.lock()
	var y = _node_y.get(node)
	_lock.unlock()
	if y != null:
		return y
	var sum := 0.0
	var count := 0
	for ei in region.adjacent[node]:
		if region.edge_a[ei] == node:
			sum += _fair_at(ei, 0)
			count += 1
		if region.edge_b[ei] == node:
			sum += _fair_at(ei, samples_of(ei) - 1)
			count += 1
	var at := region.node_pos[node]
	var out := sum / float(count) if count > 0 else float(height.call(at.x, at.y))
	if _final(at, PAGE_PAD * STEP + STEP * 2.0):
		_lock.lock()
		_node_y[node] = out
		_lock.unlock()
	return out


## The road's height at edge `edge`'s sample `k`: smoothed, and eased over EASE m at each end onto its node's height.
func _profile_at(edge: int, k: int) -> float:
	var n := samples_of(edge)
	if k <= 0:
		return node_y(region.edge_a[edge])
	if k >= n - 1:
		return node_y(region.edge_b[edge])
	var len := length_of(edge)
	var ease := minf(EASE, len * 0.5)
	var s := len * float(k) / float(n - 1)
	var y := _fair_at(edge, k)
	if s < ease:
		y += (node_y(region.edge_a[edge]) - _fair_at(edge, 0)) * (1.0 - smoothstep(0.0, ease, s))
	if len - s < ease:
		y += (node_y(region.edge_b[edge]) - _fair_at(edge, n - 1)) * (1.0 - smoothstep(0.0, ease, len - s))
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
	var island := maxf(0.0, radius - ring_w * 0.5 - 0.5)
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
	for a in arms:
		var p: Vector3 = a["mouth"]
		var ei := int(a["edge"])
		var s := float(a["mouth_s"]) if bool(a["_from_a"]) else length_of(ei) - float(a["mouth_s"])
		var out_head := heading_at(ei, s) + (0.0 if bool(a["_from_a"]) else PI)
		var right := Vector2(cos(out_head), sin(out_head))
		var half := float(a["width"]) * 0.5
		var left_c := Vector2(p.x, p.z) - right * half
		var right_c := Vector2(p.x, p.z) + right * half
		outline.append(left_c)
		outline.append(right_c)
		radius = maxf(radius, maxf(left_c.distance_to(centre), right_c.distance_to(centre)))
	if ring:
		radius = maxf(radius, float(j["ring_r"]) + float(j["ring_w"]) * 0.5)
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
	j["radius"] = maxf(radius, 0.5)
	j["outline"] = outline


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

## The edges filed under each GRID square of block `key` (any whose line comes within ground_reach of the square).
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
		var line := region.edge_line[ei]
		var seen := {}
		for k in range(1, line.size()):
			var box := Rect2(line[k - 1], Vector2.ZERO).expand(line[k]).grow(pad)
			var c0 := Vector2i(floori((box.position.x - o.x) / GRID), floori((box.position.y - o.y) / GRID))
			var c1 := Vector2i(floori((box.end.x - o.x) / GRID), floori((box.end.y - o.y) / GRID))
			for cz in range(maxi(c0.y, 0), mini(c1.y, cells - 1) + 1):
				for cx in range(maxi(c0.x, 0), mini(c1.x, cells - 1) + 1):
					var c := Vector2i(cx, cz)
					if seen.has(c):
						continue
					seen[c] = true
					var list: PackedInt32Array = out.get(c, PackedInt32Array())
					list.append(ei)
					out[c] = list
	_lock.lock()
	_grids[key] = out
	_lock.unlock()
	return out


## The edges filed near (x, z).
func _near(x: float, z: float) -> PackedInt32Array:
	var key := RoadBlock.key_of(x, z)
	var o := Vector2(key) * RoadBlock.SIZE
	return _grid_of(key).get(Vector2i(floori((x - o.x) / GRID), floori((z - o.y) / GRID)), PackedInt32Array())


## The nearest point of edge `edge`'s line to `p`: [distance along the line, signed distance right of it (a to b),
## distance from it].
func _project(edge: int, p: Vector2) -> Array:
	var line := region.edge_line[edge]
	var cum := _cum_of(edge)
	var best_d := INF
	var best_s := 0.0
	var best_lat := 0.0
	for k in range(1, line.size()):
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
	var cands := _near(x, z)
	if hint >= 0 and hint < region.edge_count() and not cands.has(hint):
		cands = cands.duplicate()
		cands.append(hint)
	for ei in cands:
		var pr := _project(ei, p)
		var off := float(pr[2]) - width_of(ei) * 0.5
		if off > REACH:
			continue
		# Inside a carriageway, the one whose centre line is nearest; else the nearest edge of one.
		var key := maxf(off, 0.0) * 1000.0 + float(pr[2])
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
	var on := absf(lat) <= w * 0.5
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


## The radius about a junction's middle that is all its surface (m): a roundabout's ring out to its outer edge.
static func _inner(j: Dictionary) -> float:
	if j["kind"] in ["roundabout", "mini"]:
		return float(j["ring_r"]) + float(j["ring_w"]) * 0.5
	return 0.0


## The land's height at (x, z) with the roads cut in, from the bare ground `bare` there: see road-block.md.
func ground_at(x: float, z: float, bare: float) -> float:
	if is_nan(bare):
		return bare
	var p := Vector2(x, z)
	var most := 0.0
	var sum_w := 0.0
	var sum_y := 0.0
	for ei in _near(x, z):
		var pr := _project(ei, p)
		var off := float(pr[2]) - width_of(ei) * 0.5 - VERGE
		if off > BANK_MAX:
			continue
		var y := road_y(ei, float(pr[0])) - UNDER
		var t := 1.0
		if off > 0.0:
			var bank := clampf(absf(bare - y) * BANK_SLOPE, BANK_MIN, BANK_MAX)
			t = 1.0 - smoothstep(0.0, bank, off)
		if t <= 0.0:
			continue
		most = maxf(most, t)
		sum_w += t
		sum_y += t * y
	if sum_w <= 0.0:
		return bare
	return lerpf(bare, sum_y / sum_w, most)


## Whether any road shapes the land in `rect` (region frame).
func roads_near(rect: Rect2) -> bool:
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
