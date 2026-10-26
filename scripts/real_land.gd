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
## Where the heights come from is the RealTerrain's alone: it follows the riders (RealTerrain.follow_riders, driven
## from here), and where its tiles come in later (ground_arrived) the blocks there are laid out again. The near blocks
## carry collision of their own, so a bike that leaves the road is held up by the land wherever the riders go.

## Network mode (set_roads: T6's RoadNet, behind the Esc > Debug toggle): there are no road chunks, so the land is
## drawn everywhere, the strip beside the road too, and wherever a road is near (roads.roads_near) its height is the
## net's, the roads cut and banked into it (roads.ground_at); the road blocks sit just above it. Blocks within NET_NEAR
## of the rider are at the near level, so their 8 m cells follow the cuttings.
const NET_NEAR := 1100.0
## In network mode the land is coloured as the land well away from a road is (the satellite's ground showing through:
## PlaceLook.ground_share), wherever it is: the roads' own verges are the road blocks'.
const NET_COLOUR_LAT := 60.0
## And the satellite's ground takes only this share of what it would there: the land round a rider is near it, where the
## place's own grass, crops and woods colour it, the satellite's only shading them.
const NET_SATELLITE := 0.5

## The riders may leave the road and ride the land (the Esc > Debug network toggle sets it): AdventureTrip doesn't put
## a bike back on the road while a near block holds it up.
static var roam := false

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
## A ribbon of a beck is at least this wide (m), the width the land's trough along it shows (AdventureRoute.ground_at).
const STREAM_MIN_W := 4.0
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
var _redo := {}        # Vector2i -> true: its ground came in while it was being laid out, so it's laid out again
var _was := Vector3(INF, INF, 0.0)   # where the rider was (x, z) and when (s), for its way (follow_riders)
var _way := Vector2.ZERO
## The road network in network mode (set_roads), else null: anything with roads_near(rect: Rect2) -> bool and
## ground_at(x, z, bare) -> float (RoadNet, interfaces/road-block.md). Read by the workers.
var roads: Object = null
## No new blocks are started while this is set (a fork's way is being put together, and the road is about to change
## under them: see AdventureWorld.apply_picks_soon), and those being laid out stop where they are (the swap lays every
## block out again: reset), so the road can be swapped without waiting on any. Read by the workers.
var hold := false


func setup(w: AdventureWorld, r: AdventureRoute) -> void:
	name = "RealLand"
	world = w
	route = r
	terrain = r.real.terrain
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true   # (the colours are the look's, as the chunks' land is: AdventureSurface.land_material)
	_material.roughness = 1.0
	_water_material = water_material()
	if terrain != null and not terrain.ground_arrived.is_connected(_on_ground):
		terrain.ground_arrived.connect(_on_ground)


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
	_redo.clear()
	_at = Vector2(INF, INF)


## Keeps the blocks round route-frame (x, z): lays out the ones that come in range (on worker threads, put in by
## _process), re-levels those that change, and drops those past the far range.
func follow(x: float, z: float) -> void:
	if terrain != null and terrain.live:
		terrain.follow_riders(riders(x, z))
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
			if lod > 0 and (_near_road(key) if roads == null else d <= NET_NEAR):
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


## The crew for the terrain (RealTerrain.follow_riders): you at route-frame (x, z) going your way, then everyone else the
## world follows (its focus) where they are.
func riders(x: float, z: float) -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var moved := Vector2(x - _was.x, z - _was.y)
	if not is_finite(_was.x) or moved.length() > 400.0:
		_was = Vector3(x, z, now)
		_way = Vector2.ZERO
	elif moved.length() >= 16.0 and now > _was.z:
		_way = moved / (now - _was.z)
		_was = Vector3(x, z, now)
	var out: Array = [Vector4(x, z, _way.x, _way.y)]
	if world != null and world.focus.is_valid():
		var spots: Array = world.focus.call()
		for k in range(1, spots.size()):
			var p: Vector3 = spots[k]
			out.append(Vector4(p.x + world.origin.x, p.z + world.origin.z, 0.0, 0.0))
	return out


## New tiles came in over `area` (RealTerrain.ground_arrived): the blocks there are laid out again (the old ones stay
## till the new are in).
func _on_ground(area: Rect2, _level: int) -> void:
	var b0 := Vector2i(floori(area.position.x / BLOCK), floori(area.position.y / BLOCK))
	var b1 := Vector2i(floori(area.end.x / BLOCK), floori(area.end.y / BLOCK))
	var any := false
	for key: Vector2i in _blocks:
		if key.x >= b0.x and key.x <= b1.x and key.y >= b0.y and key.y <= b1.y:
			_blocks[key]["lod"] = -1
			any = true
	for key: Vector2i in _tasks:
		if key.x >= b0.x and key.x <= b1.x and key.y >= b0.y and key.y <= b1.y:
			_redo[key] = true
			any = true
	if any:
		_at = Vector2(INF, INF)


## Draws the land for the road network `net` (network mode, see roads), or for the planned road again (null): every
## block is laid out again.
func set_roads(net: Object) -> void:
	hold = true
	reset()
	roads = net
	hold = false


## Whether a near block's land (with its collision) is laid out under route-frame (x, z).
func holds(x: float, z: float) -> bool:
	var key := Vector2i(floori(x / BLOCK), floori(z / BLOCK))
	return _blocks.has(key) and _blocks[key]["mi"] != null and (_blocks[key]["mi"] as Node).has_node("Ground")


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
			var shape = _ground_shape(arrays) if arrays != null and lod == 0 else null
			_lock.lock()
			if epoch == _epoch:
				_done[key] = {"lod": lod, "arrays": arrays, "water": water, "shape": shape}
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
			if got.get("shape") != null:
				var body := StaticBody3D.new()
				body.name = "Ground"
				body.collision_layer = 1
				body.set_meta("surface", "grass")
				var cs := CollisionShape3D.new()
				cs.shape = got["shape"]
				body.add_child(cs)
				mi.add_child(body)
			add_child(mi)
			_place(key, mi)
			put += 1
		if old != null:
			old.queue_free()
		_blocks[key] = {"lod": -1 if _redo.has(key) else int(got["lod"]), "mi": mi}
		if _redo.erase(key):
			_at = Vector2(INF, INF)


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

## The collision of a near block's land: its ground's triangles (not the skirts), as the mesh has them. Any thread.
static func _ground_shape(arrays: Array) -> ConcavePolygonShape3D:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var grid := CELLS[0] + 1
	var faces := PackedVector3Array()
	for t in range(0, idx.size(), 3):
		if idx[t] < grid * grid and idx[t + 1] < grid * grid and idx[t + 2] < grid * grid:
			faces.append_array([verts[idx[t]], verts[idx[t + 1]], verts[idx[t + 2]]])
	if faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


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
	var net: Object = roads
	var cut := net != null and bool(net.call("roads_near", Rect2(ox - sp, oz - sp, BLOCK + sp * 2.0, BLOCK + sp * 2.0)))
	for k in range(0, route.px.size(), 4):
		if net == null and route.px[k] >= lo.x and route.px[k] <= hi.x and route.pz[k] >= lo.y and route.pz[k] <= hi.y:
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
		if hold:
			return null   # (the road's being swapped: what's laid out now is thrown away, see hold)
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
			if net != null:
				grid[g] = float(net.call("ground_at", x, z, bare)) if cut else bare
				lats[g] = NET_COLOUR_LAT
			elif d >= BAND_FAR:
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
		if hold:
			return null
		for i in m:
			var cx := ox + (i - 0.5) * sp
			var cz := oz + (j - 0.5) * sp
			if terrain.cover(cx, cz) != RealPack.WATER:
				continue
			var h := terrain.height(cx, cz)
			if not is_nan(h):
				wet[j * m + i] = 1
				level[j * m + i] = h
				any = true
	var streams := lod == 0 and not route.real.streams.is_empty()
	if not any and not streams:
		return null
	var near := PackedInt32Array()
	for k in range(0, route.px.size() if roads == null else 0, 4):
		if route.px[k] >= ox - WATER_ROAD - sp and route.px[k] <= ox + BLOCK + WATER_ROAD + sp \
				and route.pz[k] >= oz - WATER_ROAD - sp and route.pz[k] <= oz + BLOCK + WATER_ROAD + sp:
			near.append(k)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	if streams:
		_stream_ribbons(ox, oz, near, verts, idx)
	if hold:
		return null
	if not any:
		return _water_mesh(verts, idx)
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
	for j in cells:
		for i in cells:
			var dry := true
			for dj in 3:
				for di in 3:
					if wet[(j + dj) * m + (i + di)] == 1:
						dry = false
			if dry:
				continue
			# (off the road, unless it's crossing on a bridge: the water runs on under the deck)
			if _on_road(near, ox + (i + 0.5) * sp, oz + (j + 0.5) * sp, WATER_ROAD + sp * 0.5):
				continue
			var c := [corner[j * n + i], corner[j * n + i + 1], corner[(j + 1) * n + i + 1], corner[(j + 1) * n + i]]
			if c.has(INF):
				continue
			var v := verts.size()
			verts.append_array([Vector3(i * sp, c[0], j * sp), Vector3((i + 1) * sp, c[1], j * sp),
				Vector3((i + 1) * sp, c[2], (j + 1) * sp), Vector3(i * sp, c[3], (j + 1) * sp)])
			idx.append_array([v, v + 1, v + 2, v, v + 2, v + 3])
	return _water_mesh(verts, idx)


## The rivers and streams (RealPack.streams) of the block at (ox, oz) into `verts` and `idx`: a ribbon of water down each,
## its own width or STREAM_MIN_W if narrower, on the water at each point (the real heights there, never up a bank: the
## lowest of them a point either way), over the trough the land has along it (AdventureRoute.ground_at). Each segment is
## the block's that its middle is in; none on the road (`near`: its knots by the block) but under a bridge, nor where the
## land cover has the water already.
func _stream_ribbons(ox: float, oz: float, near: PackedInt32Array, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var box := Rect2(ox, oz, BLOCK, BLOCK)
	for line: Array in route.real.streams:
		if hold:
			return
		var pts: PackedVector2Array = line[1]
		var half: float = maxf(RealPack.STREAM_HALF[clampi(int(line[0]), 0, 2)], STREAM_MIN_W * 0.5)
		var mine := PackedInt32Array()
		for k in pts.size() - 1:
			if box.has_point((pts[k] + pts[k + 1]) * 0.5):
				mine.append(k)
		if mine.is_empty():
			continue
		var raw := PackedFloat32Array()
		raw.resize(pts.size())
		for k in pts.size():
			raw[k] = terrain.height(pts[k].x, pts[k].y)
		for k in mine:
			var a := pts[k]
			var b := pts[k + 1]
			var mid := (a + b) * 0.5
			if terrain.cover(mid.x, mid.y) == RealPack.WATER:
				continue   # (a river mapped as water too: it's drawn as that)
			if _on_road(near, mid.x, mid.y, WATER_ROAD):
				continue
			var ha := _lowest(raw, k)
			var hb := _lowest(raw, k + 1)
			if is_nan(ha) or is_nan(hb):
				continue
			var along := (b - a).normalized()
			var side := Vector2(-along.y, along.x) * half
			# (a little past each end, so the next segment's ribbon overlaps it at a bend)
			var a2 := a - along * half
			var b2 := b + along * half
			var v := verts.size()
			verts.append_array([Vector3(a2.x - side.x - ox, ha, a2.y - side.y - oz), Vector3(a2.x + side.x - ox, ha, a2.y + side.y - oz),
				Vector3(b2.x + side.x - ox, hb, b2.y + side.y - oz), Vector3(b2.x - side.x - ox, hb, b2.y - side.y - oz)])
			idx.append_array([v, v + 1, v + 2, v, v + 2, v + 3, v, v + 2, v + 1, v, v + 3, v + 2])


## Whether (x, z) is within `reach` of the road (`near`: every fourth of its knots by the block) where it isn't on a bridge:
## no water's drawn there (it would lie over the road, or a bank of it). The deck is the nearest knot's, not the nearest
## of every fourth (at a bridge's end that may be on the deck while the road there isn't).
func _on_road(near: PackedInt32Array, x: float, z: float, reach: float) -> bool:
	if near.is_empty():
		return false
	var nr := _nearest_of(route, near, x, z)
	var k := int(nr[1])
	if float(nr[0]) >= reach or k < 0:
		return false
	var best := INF
	for i in range(maxi(0, k - 4), mini(route.px.size(), k + 5)):
		var d := Vector2(route.px[i] - x, route.pz[i] - z).length_squared()
		if d < best:
			best = d
			k = i
	return not near_deck(route, k)


## Whether knot `i` of `r` is on a bridge or just at its end (a deck eases in over its first and last knots).
static func near_deck(r: AdventureRoute, i: int) -> bool:
	for j in range(maxi(0, i - 2), mini(r.deck.size(), i + 3)):
		if r.deck[j] > 0.0:
			return true
	return false


## The lowest of `h` at k and the points either side of it (NAN when there's no height there).
static func _lowest(h: PackedFloat32Array, k: int) -> float:
	var out := h[k]
	for j: int in [k - 1, k + 1]:
		if j >= 0 and j < h.size() and not is_nan(h[j]) and (is_nan(out) or h[j] < out):
			out = h[j]
	return out


## Water arrays from `verts` and `idx`, or null when there are none.
static func _water_mesh(verts: PackedVector3Array, idx: PackedInt32Array) -> Variant:
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
	var col := AdventureChunk._land_color(route, i, 3, lat, x, z, y, NET_SATELLITE if roads != null else 1.0)
	if not wet and terrain.cover(x, z) == RealPack.WATER:
		return col.lerp(FAR_WATER, 0.85)
	if route.cover_at(x, z) == "":
		col = col.lerp(route.look.get("woods", RealRidges.WOODS), 0.5)   # past the baked cover: about what the place is mostly (its climate's woods)
	col = col.lerp(Color(0.45, 0.43, 0.4), smoothstep(0.32, 0.62, 1.0 - normal.y) * 0.7)
	if route.sea and y < AdventureTheme.SEA_Y + 5.0:
		col = col.lerp(AdventureChunk.BEACH, 1.0 - smoothstep(AdventureTheme.SEA_Y + 2.0, AdventureTheme.SEA_Y + 5.0, y))
		if y < AdventureTheme.SEA_Y - 0.2:
			col = AdventureChunk.BEACH.darkened(0.3)
	return col
