class_name RealLand
extends Node3D
## The land of a real road, drawn the way the garage map's is (WorldTerrain): a grid of blocks over the real heights,
## each in a near, a middle or a far level of detail by how far the rider is from it, the road cut into it, so valleys
## open out and hills climb away from the road instead of the road running down a corridor of strips.
##
## The land beside the road itself (out to STRIP_OUT, with its collision) is still the road's own chunks
## (AdventureChunk): this is everything beyond, from there out to FAR_R, where the skyline (RealRidges) takes over.
## Heights are AdventureRoute.land_height (the real heights blended into the road's own near it, so a block meets the
## chunk's land exactly), or the bare real heights away from the road. A block is a mesh of its own, laid out on a
## worker thread when it comes within range and re-laid at another level as the rider nears or leaves it.
##
## Where the heights come from is the RealTerrain's alone, so land streamed from the net later needs nothing here.

## A block is this big (m) on a side: the same as the fine tiles.
const BLOCK := 512.0
## Cells along a block's side at each level (near 8 m, middle 32 m, far 64 m).
const CELLS := [64, 16, 8]
## A block is at the near level within the first distance of the rider, the middle level within the second, the far
## level within the third (block centre to rider, m); a level is kept this much further on (so a block on the line
## doesn't flicker between two).
const RANGES := [560.0, 2100.0, 5200.0]
const HYSTERESIS := 120.0
## The chunks' land runs out this far from the road (AdventureChunk.REAL_LAND_OUT): cells wholly inside it are left out.
const STRIP_OUT := 110.0
## Where the land is eased under the chunks' own, so no edge of one shows over the other (m, from the road).
const UNDER_FROM := 112.0
const UNDER_TO := 126.0
const UNDER_BY := 0.3
## A block this close to the road (its middle, m) is always at the near level, however far off the rider is: the
## coarser levels' cells are too big to meet the chunks' land cleanly.
const ROAD_NEAR := 560.0
## How far the edges of a block hang down at least (m), so two blocks at different levels show no crack between them.
const SKIRT_MIN := 4.0
## Where the road's own blend into the land is worked out exactly: from this far off it (m, from BAND_NEAR the chunks'
## land covers it and the land lies hidden under it) to BAND_FAR, where the ground is the bare real height.
const BAND_NEAR := 96.0
const BAND_FAR := 150.0
## Water (rivers and lakes: RealPack.WATER cover) is drawn on the near and middle levels' blocks, a cell wherever its
## middle is water, at the water's height (the real heights there; the land is its bed, AdventureRoute.ground_at). It's
## kept this far off the road (m, from the nearest of every fourth knot) but where the road is on a bridge.
const WATER_LODS := 2
const WATER_ROAD := 14.0
## How far the water's outer edge dips below the water (m): into the bank, where flat ground would show its cells' squares.
const WATER_SHORE := 0.8
const WATER_COLOUR := Color(0.08, 0.17, 0.22)
## A lake's or river's colour on the far level's land (no water is drawn there).
const FAR_WATER := Color(0.18, 0.34, 0.5)
## How many blocks are laid out at once, and put in the tree a frame.
const AT_ONCE := 3
const PUT_PER_FRAME := 2

var world: AdventureWorld
var route: AdventureRoute
var terrain: RealTerrain
var _blocks := {}      # Vector2i -> {lod, mi}
var _tasks := {}       # Vector2i -> {id, lod}
var _queue: Array = [] # [{key, lod}] to lay out, nearest first
var _done := {}        # Vector2i -> {lod, arrays}
var _lock := Mutex.new()
var _material: StandardMaterial3D
var _water_material: StandardMaterial3D
var _at := Vector2(INF, INF)
var _epoch := 0        # changes when the road does (a way picked at a fork): older work is thrown away
var _touch := {}       # Vector2i -> true for the blocks the road is near (worked out once a road, see _near_road)
var _touch_done := false
## No new blocks are started while this is set (a fork's way is being put together, and the road is about to change
## under them: see AdventureWorld.apply_picks_soon), so the road can be swapped without waiting on any.
var hold := false


func setup(w: AdventureWorld, r: AdventureRoute) -> void:
	name = "RealLand"
	world = w
	route = r
	terrain = r.real.terrain
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_water_material = water_material()


static var _water_mat: StandardMaterial3D


## The water's material: dark and glassy, catching the sky, with ripples on it.
static func water_material() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = WATER_COLOUR
		_water_mat.roughness = 0.06
		_water_mat.metallic = 0.25
		_water_mat.metallic_specular = 1.0
		var ripples := NoiseTexture2D.new()
		ripples.seamless = true
		ripples.as_normal_map = true
		ripples.bump_strength = 1.5
		ripples.noise = FastNoiseLite.new()
		ripples.noise.frequency = 0.05
		_water_mat.normal_enabled = true
		_water_mat.normal_texture = ripples
		_water_mat.normal_scale = 0.35
		_water_mat.uv1_triplanar = true
		_water_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	return _water_mat


func _exit_tree() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
	_tasks.clear()


## Everything is laid out again (the road changed under it: a way was picked at a fork).
func reset() -> void:
	_epoch += 1
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
	_tasks.clear()
	_lock.lock()
	_done.clear()
	_lock.unlock()
	_queue.clear()
	for key: Vector2i in _blocks.keys():
		var mi: MeshInstance3D = _blocks[key]["mi"]
		if mi != null:
			mi.queue_free()
	_blocks.clear()
	_touch.clear()
	_touch_done = false
	_at = Vector2(INF, INF)


## Keeps the blocks round route-frame (x, z): lays out the ones that come in range (on worker threads, put in by
## _process), re-levels those that change, and drops those past the far range.
func follow(x: float, z: float) -> void:
	if Vector2(x, z).distance_to(_at) < 48.0:
		return
	_at = Vector2(x, z)
	var far: float = RANGES[2] + BLOCK
	var b0 := Vector2i(floori((x - far) / BLOCK), floori((z - far) / BLOCK))
	var b1 := Vector2i(floori((x + far) / BLOCK), floori((z + far) / BLOCK))
	var want: Array = []
	for bz in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var key := Vector2i(bx, bz)
			var d := _centre(key).distance_to(_at)
			var have: int = _blocks[key]["lod"] if _blocks.has(key) else -1
			var lod := _lod_for(d, have)
			if lod < 0:
				continue
			if lod > 0 and _near_road(key):
				lod = 0
			if have != lod and not _tasks.has(key):
				want.append({"key": key, "lod": lod, "d": d})
	want.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	_queue = want
	for key: Vector2i in _blocks.keys():
		if _centre(key).distance_to(_at) > RANGES[2] + HYSTERESIS + BLOCK * 0.5:
			var mi: MeshInstance3D = _blocks[key]["mi"]
			if mi != null:
				mi.queue_free()
			_blocks.erase(key)


## Whether the road is within ROAD_NEAR of the middle of block `key`. The blocks it's near are marked in one go along
## the road (a point every 64 m), the first time it's asked: asking the road for each block in reach on its own was a
## hitch of tens of ms when they were all asked at once (at the start, and once a fork's way is taken).
func _near_road(key: Vector2i) -> bool:
	if not _touch_done:
		_touch_done = true
		var reach := ROAD_NEAR + 32.0
		var span := int(ceil(reach / BLOCK)) + 1
		for i in range(0, route.knot_count(), 16):
			var p := Vector2(route.px[i], route.pz[i])
			var b := Vector2i(floori(p.x / BLOCK), floori(p.y / BLOCK))
			for bz in range(b.y - span, b.y + span + 1):
				for bx in range(b.x - span, b.x + span + 1):
					var k := Vector2i(bx, bz)
					if not _touch.has(k) and _centre(k).distance_to(p) < reach:
						_touch[k] = true
	return _touch.has(key)


## The level for a block `d` metres from the rider (-1: none), keeping `have` (-1 for none yet) while it is near enough.
static func _lod_for(d: float, have: int) -> int:
	for lod in 3:
		var r: float = RANGES[lod]
		if d <= r or (have == lod and d <= r + HYSTERESIS):
			return lod
	return -1


static func _centre(key: Vector2i) -> Vector2:
	return Vector2((key.x + 0.5) * BLOCK, (key.y + 0.5) * BLOCK)


func _process(_delta: float) -> void:
	while not hold and _tasks.size() < AT_ONCE and not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var key: Vector2i = item["key"]
		var lod: int = item["lod"]
		if _tasks.has(key):
			continue
		var epoch := _epoch
		_tasks[key] = {"lod": lod, "id": WorkerThreadPool.add_task(func():
			var arrays = _block_arrays(key, lod)
			var water = _water_arrays(key, lod) if arrays != null else null
			_lock.lock()
			if epoch == _epoch:
				_done[key] = {"lod": lod, "arrays": arrays, "water": water}
			_lock.unlock())}
	if _tasks.is_empty():
		return
	var put := 0
	for key: Vector2i in _tasks.keys():
		if put >= PUT_PER_FRAME or not WorkerThreadPool.is_task_completed(_tasks[key]["id"]):
			continue
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
		_tasks.erase(key)
		_lock.lock()
		var got = _done.get(key)
		_done.erase(key)
		_lock.unlock()
		if got == null:
			continue
		var old: MeshInstance3D = _blocks[key]["mi"] if _blocks.has(key) else null
		var mi: MeshInstance3D = null
		if got["arrays"] != null:
			mi = _make_mesh(key, got["arrays"], got.get("water"))
			add_child(mi)
			_place(key, mi)
			put += 1
		if old != null:
			old.queue_free()
		_blocks[key] = {"lod": int(got["lod"]), "mi": mi}


## Puts every block where the world's origin has it (after a shift).
func place() -> void:
	for key: Vector2i in _blocks:
		var mi: MeshInstance3D = _blocks[key]["mi"]
		if mi != null:
			_place(key, mi)


func block_count() -> int:
	return _blocks.values().filter(func(b): return b["mi"] != null).size()


## The level each block that is laid out is at, {lod: count}.
func level_counts() -> Dictionary:
	var out := {}
	for key in _blocks:
		out[_blocks[key]["lod"]] = int(out.get(_blocks[key]["lod"], 0)) + 1
	return out


## Whether any block is still waiting or being laid out.
func busy() -> bool:
	return not _tasks.is_empty() or not _queue.is_empty()


## Whether any block is being laid out on a worker thread right now.
func working() -> bool:
	return not _tasks.is_empty()


func _place(key: Vector2i, mi: MeshInstance3D) -> void:
	mi.position = Vector3(key.x * BLOCK - world.origin.x, 0.0, key.y * BLOCK - world.origin.z)


func _make_mesh(key: Vector2i, arrays: Array, water = null) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	if water != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water)
		mesh.surface_set_material(1, _water_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Land_%d_%d" % [key.x, key.y]
	return mi


# ---------------------------------------------------------------------------- laying a block out

## The knot (and its distance) nearest (x, z) among the knots of `ids` (every few knots of the road): [distance, knot].
static func _nearest_of(route: AdventureRoute, ids: PackedInt32Array, x: float, z: float) -> Array:
	var best := INF
	var at := -1
	for k in ids:
		var dx := route.px[k] - x
		var dz := route.pz[k] - z
		var d := dx * dx + dz * dz
		if d < best:
			best = d
			at = k
	return [sqrt(best), at]


## The land at (x, z) a little off a road whose knot `k` is nearest (to within a few knots): the road's own height blended
## into the real one (AdventureRoute.land_height), as the chunks' land has it. Returns [height, knot, lat].
func _precise(x: float, z: float, k: int) -> Array:
	var best := -1
	var best_d := INF
	for i in range(maxi(0, k - 6), mini(route.px.size(), k + 7)):
		var d := (route.px[i] - x) * (route.px[i] - x) + (route.pz[i] - z) * (route.pz[i] - z)
		if d < best_d:
			best_d = d
			best = i
	var lat := 0.0
	var seg_d := INF
	for i in [best - 1, best]:
		if i < 0 or i >= route.px.size() - 1:
			continue
		var ax := route.px[i]
		var az := route.pz[i]
		var dx := route.px[i + 1] - ax
		var dz := route.pz[i + 1] - az
		var t := clampf(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0.0, 1.0)
		var qx := ax + dx * t
		var qz := az + dz * t
		var d := sqrt((x - qx) * (x - qx) + (z - qz) * (z - qz))
		if d < seg_d:
			seg_d = d
			var h := lerpf(route.hd[i], route.hd[i + 1], t)
			lat = (x - qx) * cos(h) + (z - qz) * sin(h)
	var y := route.land_height(best, lat, x, z)
	if seg_d < UNDER_TO:
		y -= UNDER_BY * (1.0 - smoothstep(UNDER_FROM, UNDER_TO, seg_d))
	return [y, best, lat]


## The mesh arrays of block `key` at level `lod`, or null when it holds no land. Any thread.
func _block_arrays(key: Vector2i, lod: int) -> Variant:
	var cells: int = CELLS[lod]
	var sp := BLOCK / cells
	var n := cells + 1
	var m := n + 2   # a sample's border either side, for the normals
	var ox := key.x * BLOCK
	var oz := key.y * BLOCK
	# The road near the block (every 4th knot), and the knot nearest its middle for the colours where it is far.
	var near := PackedInt32Array()
	var lo := Vector2(ox - BAND_FAR - sp, oz - BAND_FAR - sp)
	var hi := Vector2(ox + BLOCK + BAND_FAR + sp, oz + BLOCK + BAND_FAR + sp)
	for k in range(0, route.px.size(), 4):
		if route.px[k] >= lo.x and route.px[k] <= hi.x and route.pz[k] >= lo.y and route.pz[k] <= hi.y:
			near.append(k)
	var mid := _centre(key)
	var hint := 0
	var best := INF
	for k in range(0, route.px.size(), 8):
		var d := (route.px[k] - mid.x) * (route.px[k] - mid.x) + (route.pz[k] - mid.y) * (route.pz[k] - mid.y)
		if d < best:
			best = d
			hint = k
	var grid := PackedFloat32Array()
	var dist := PackedFloat32Array()
	var knot := PackedInt32Array()
	var lats := PackedFloat32Array()
	grid.resize(m * m)
	dist.resize(m * m)
	knot.resize(m * m)
	lats.resize(m * m)
	for j in m:
		for i in m:
			var x := ox + (i - 1) * sp
			var z := oz + (j - 1) * sp
			var g := j * m + i
			var d := INF
			var k := hint
			if not near.is_empty():
				var nr := _nearest_of(route, near, x, z)
				d = nr[0]
				k = int(nr[1]) if int(nr[1]) >= 0 else hint
			dist[g] = d
			knot[g] = k
			lats[g] = 0.0
			var bare := route.ground_at(x, z)
			if is_nan(bare):
				bare = route.base[k]
			if d >= BAND_FAR:
				grid[g] = bare
			elif d < BAND_NEAR:
				grid[g] = bare - 4.0   # under the chunks' own land
			else:
				var pr := _precise(x, z, k)
				grid[g] = pr[0]
				knot[g] = int(pr[1])
				lats[g] = pr[2]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var g := (j + 1) * m + (i + 1)
			var h := grid[g]
			verts[j * n + i] = Vector3(i * sp, h, j * sp)
			norms[j * n + i] = Vector3(grid[g - 1] - grid[g + 1], 2.0 * sp, grid[g - m] - grid[g + m]).normalized()
			cols[j * n + i] = _colour(knot[g], lats[g], ox + i * sp, oz + j * sp, h, norms[j * n + i], lod < WATER_LODS)
	# Cells wholly under the chunks' own land are left out.
	var idx := PackedInt32Array()
	var any := false
	for j in cells:
		for i in cells:
			var a := (j + 1) * m + (i + 1)
			if sp <= 16.0 and dist[a] < STRIP_OUT and dist[a + 1] < STRIP_OUT and dist[a + m] < STRIP_OUT and dist[a + m + 1] < STRIP_OUT:
				continue
			var v := j * n + i
			idx.append_array([v, v + 1, v + n + 1, v, v + n + 1, v + n])
			any = true
	if not any:
		return null
	# Skirts round the edge: as deep as the edge's mesh and the real ground ever part along it (the neighbour at another
	# level, or the ridge, may be anywhere in between), and more.
	for e in 4:
		var drop := SKIRT_MIN + _edge_gap(ox, oz, e, cells, sp, verts, n)
		var base := verts.size()
		for t in n:
			var src := 0
			match e:
				0: src = t
				1: src = (n - 1) * n + t
				2: src = t * n
				3: src = t * n + n - 1
			verts.append(verts[src] + Vector3.DOWN * drop)
			norms.append(norms[src])
			cols.append(cols[src])
		for t in n - 1:
			var s0 := 0
			var s1 := 0
			match e:
				0:
					s0 = t
					s1 = t + 1
				1:
					s0 = (n - 1) * n + t
					s1 = (n - 1) * n + t + 1
				2:
					s0 = t * n
					s1 = (t + 1) * n
				3:
					s0 = t * n + n - 1
					s1 = (t + 1) * n + n - 1
			idx.append_array([s0, s1, base + t + 1, s0, base + t + 1, base + t])
			idx.append_array([s0, base + t + 1, s1, s0, base + t, base + t + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## The water of block `key` at level `lod` (see WATER_LODS), or null when it has none. Any thread. A cell is water where
## its middle is, and one either side of it too, at the water's height: the banks rise through it, so the shore follows
## the land rather than the cells' squares.
func _water_arrays(key: Vector2i, lod: int) -> Variant:
	if lod >= WATER_LODS:
		return null
	var cells: int = CELLS[lod]
	var sp := BLOCK / cells
	var ox := key.x * BLOCK
	var oz := key.y * BLOCK
	# Each cell's middle, a cell's border round the block: water there, and its height.
	var m := cells + 2
	var wet := PackedByteArray()
	var level := PackedFloat32Array()
	wet.resize(m * m)
	level.resize(m * m)
	var any := false
	for j in m:
		for i in m:
			var cx := ox + (i - 0.5) * sp
			var cz := oz + (j - 0.5) * sp
			var h := terrain.height(cx, cz)
			if not is_nan(h) and terrain.cover(cx, cz) == RealPack.WATER:
				wet[j * m + i] = 1
				level[j * m + i] = h
				any = true
	if not any:
		return null
	var near := PackedInt32Array()
	for k in range(0, route.px.size(), 4):
		if route.px[k] >= ox - WATER_ROAD - sp and route.px[k] <= ox + BLOCK + WATER_ROAD + sp \
				and route.pz[k] >= oz - WATER_ROAD - sp and route.pz[k] <= oz + BLOCK + WATER_ROAD + sp:
			near.append(k)
	# Each corner of the cells: the lowest water among the cells it's a corner of, or failing that among those round them
	# (a corner on the shore, a little lower), so the water slopes down a river as it goes and is one surface, no steps.
	var n := cells + 1
	var corner := PackedFloat32Array()
	corner.resize(n * n)
	for vj in n:
		for vi in n:
			var h := INF
			for reach: int in [1, 2]:
				for cj in range(vj + 1 - reach, vj + 1 + reach):
					for ci in range(vi + 1 - reach, vi + 1 + reach):
						if ci >= 0 and cj >= 0 and ci < m and cj < m and wet[cj * m + ci] == 1:
							h = minf(h, level[cj * m + ci])
				if h != INF:
					if reach == 2:
						h -= WATER_SHORE   # (on the shore: dipping into the bank, so the edge follows the land)
					break
			corner[vj * n + vi] = h
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in cells:
		for i in cells:
			var dry := true
			for dj in 3:
				for di in 3:
					if wet[(j + dj) * m + (i + di)] == 1:
						dry = false
			if dry:
				continue
			if not near.is_empty():
				var nr := _nearest_of(route, near, ox + (i + 0.5) * sp, oz + (j + 0.5) * sp)
				var k := int(nr[1])
				# (off the road, unless it's crossing on a bridge: the water runs on under the deck)
				if float(nr[0]) < WATER_ROAD + sp * 0.5 and k >= 0 and (k >= route.deck.size() or route.deck[k] <= 0.0):
					continue
			var c := [corner[j * n + i], corner[j * n + i + 1], corner[(j + 1) * n + i + 1], corner[(j + 1) * n + i]]
			if c.has(INF):
				continue
			var v := verts.size()
			verts.append_array([Vector3(i * sp, c[0], j * sp), Vector3((i + 1) * sp, c[1], j * sp),
				Vector3((i + 1) * sp, c[2], (j + 1) * sp), Vector3(i * sp, c[3], (j + 1) * sp)])
			idx.append_array([v, v + 1, v + 2, v, v + 2, v + 3])
	if verts.is_empty():
		return null
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## How far (m) the real ground part-way between a block's edge samples lies from the line between them, the most along
## edge `e` (0 north, 1 south, 2 west, 3 east): the crack a neighbour at another level could show.
func _edge_gap(ox: float, oz: float, e: int, cells: int, sp: float, verts: PackedVector3Array, n: int) -> float:
	var gap := 0.0
	for t in cells:
		var a := 0
		var b := 0
		var xa := 0.0
		var za := 0.0
		var xb := 0.0
		var zb := 0.0
		match e:
			0:
				a = t
				b = t + 1
				xa = ox + t * sp
				za = oz
				xb = xa + sp
				zb = oz
			1:
				a = (n - 1) * n + t
				b = a + 1
				xa = ox + t * sp
				za = oz + BLOCK
				xb = xa + sp
				zb = za
			2:
				a = t * n
				b = (t + 1) * n
				xa = ox
				za = oz + t * sp
				xb = ox
				zb = za + sp
			3:
				a = t * n + n - 1
				b = (t + 1) * n + n - 1
				xa = ox + BLOCK
				za = oz + t * sp
				xb = xa
				zb = za + sp
		var mid_h := terrain.height((xa + xb) * 0.5, (za + zb) * 0.5)
		if not is_nan(mid_h):
			gap = maxf(gap, absf(mid_h - (verts[a].y + verts[b].y) * 0.5))
	return gap


## The ground's colour: what the road's own land is there (its surface's, patched, tinted by what covers it), so the two
## meet without a line; rock where the ground itself is steep (by its normal: far from the road, how far it has risen
## from the road means nothing), and a beach by the sea. Under water it's the bed's, where the water is drawn (`wet`), and
## the water's own blue where it isn't (the far level).
func _colour(i: int, lat: float, x: float, z: float, y: float, normal: Vector3, wet := true) -> Color:
	var col := AdventureChunk._land_color(route, i, 3, lat, x, z, y)
	if not wet and terrain.cover(x, z) == RealPack.WATER:
		return col.lerp(FAR_WATER, 0.85)
	if route.cover_at(x, z) == "":
		col = col.lerp(RealRidges.WOODS, 0.5)   # past the baked cover: about what the island is mostly
	col = col.lerp(Color(0.45, 0.43, 0.4), smoothstep(0.32, 0.62, 1.0 - normal.y) * 0.7)
	if route.sea and y < AdventureTheme.SEA_Y + 5.0:
		col = col.lerp(AdventureChunk.BEACH, 1.0 - smoothstep(AdventureTheme.SEA_Y + 2.0, AdventureTheme.SEA_Y + 5.0, y))
		if y < AdventureTheme.SEA_Y - 0.2:
			col = AdventureChunk.BEACH.darkened(0.3)
	return col
