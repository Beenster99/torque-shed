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
## How often the land's grain repeats a metre on the network (AdventureSurface.land_material's noise): near its 0.12,
## and a whole number of times across a block, so a block's edge shows no seam.
const NET_GRAIN := 0.125
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
## On the road network a near cell the roads cut into is drawn this many times finer each way (8 m cells in 2 m ones),
## where its land strays more than REFINE_OFF (m) from the flat between its corners (RealLand._refine).
const FINE := 4
const REFINE_OFF := 0.12
## How far the edges of a block hang down at least (m), so two blocks at different levels show no crack between them.
const SKIRT_MIN := 4.0
## On the road network the skirts are as deep as the land and this block's edge part, looked at every EDGE_LOOK (m), and
## as the land parts from a straight line between points EDGE_KNOT apart (the far level's cells, where every level's
## edge meets the land).
const EDGE_LOOK := 8.0
const EDGE_KNOT := 64.0
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
## The banks (_bank): stone and shingle up to BANK_HIGH (m) over the water (an embankment's riprap, a beach of pebbles),
## damp and darker to BANK_DAMP, and out from the water while its nearness (RealTerrain.water_at) is under BANK_REACH.
const BANK_COLOUR := Color(0.6, 0.57, 0.5)
const BANK_HIGH := 2.2
const BANK_DAMP := 0.6
const BANK_REACH := 0.3
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
var _pieces := StreamPieces.new()   # the near blocks' ground going in a piece at a time
var _water_material: StandardMaterial3D
var _at := Vector2(INF, INF)
var _epoch := 0        # changes when the roads do (set_roads): older work is thrown away
var _touch := {}       # Vector2i -> true for the blocks the road is near (worked out once a road, see _near_road)
var _touch_done := false
var _redo := {}        # Vector2i -> true: its ground came in while it was being laid out, so it's laid out again
var _was := Vector3(INF, INF, 0.0)   # where the rider was (x, z) and when (s), for its way (follow_riders)
var _way := Vector2.ZERO
## The road network in network mode (set_roads), else null: anything with roads_near(rect: Rect2) -> bool and
## ground_at(x, z, bare) -> float (RoadNet, interfaces/road-block.md). Read by the workers.
var roads: Object = null
## No new blocks are started while this is set (the roads are about to change under them: see set_roads), and those
## being laid out stop where they are (the swap lays every block out again: reset), so the roads can be swapped
## without waiting on any. Read by the workers.
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
	# (seen from both sides: wherever the eye might slip through a crack, under the land's edge or between two levels,
	# it meets the land's underside, not the sky beyond)
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
		JobPool.drop(_tasks[key]["id"])
	_tasks.clear()
	_pieces.clear()


## Everything is laid out again (the roads changed under it: see set_roads).
func reset() -> void:
	_epoch += 1
	for key in _tasks:
		JobPool.drop(_tasks[key]["id"])
	_tasks.clear()
	_lock.lock()
	_done.clear()
	_lock.unlock()
	_queue.clear()
	_pieces.clear()
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
				var bare: bool = not _blocks.has(key) or _blocks[key]["mi"] == null
				want.append({"key": key, "lod": lod, "d": d, "bare": bare})
	# Land where there's none yet first, nearest first, then the rest re-levelled: a block waiting behind the near ones'
	# finer levels is a hole through to the sky (the skyline under it is pushed well down near the road).
	want.sort_custom(func(a, b): return bool(a["bare"]) and not bool(b["bare"]) if bool(a["bare"]) != bool(b["bare"]) else float(a["d"]) < float(b["d"]))
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
	# (on the network the land beside the roads is this land, so it has the planned road's land's grain: its noise,
	# NET_GRAIN a metre so it tiles across a block exactly)
	var land := AdventureSurface.land_material()
	_material.albedo_texture = land.albedo_texture if net != null else null
	_material.uv1_triplanar = net != null
	_material.uv1_scale = Vector3.ONE * NET_GRAIN if net != null else Vector3.ONE
	_material.roughness = land.roughness if net != null else 1.0
	hold = false


## Whether a near block's land (with all its collision) is laid out under route-frame (x, z).
func holds(x: float, z: float) -> bool:
	var key := Vector2i(floori(x / BLOCK), floori(z / BLOCK))
	return _blocks.has(key) and _blocks[key]["mi"] != null and (_blocks[key]["mi"] as Node).has_node("Ground") \
		and not _pieces.has(_blocks[key]["mi"])


## Whether the road is within ROAD_NEAR of the middle of block `key`. The blocks it's near are marked in one go along
## the road (a point every 64 m), the first time it's asked: asking the road for each block in reach on its own was a
## hitch of tens of ms when they were all asked at once (at the start).
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
	var pt := Perf.t0()
	_process_body(_delta)
	Perf.add("land_stream", pt)


func _process_body(_delta: float) -> void:
	_pieces.pump()
	if not _pieces.waiting.is_empty() and _at.x != INF:
		# (the block you're on is solid at once, if you've reached it before its pieces were all in)
		var on := Vector2i(floori(_at.x / BLOCK), floori(_at.y / BLOCK))
		if _blocks.has(on) and is_instance_valid(_blocks[on]["mi"]):
			_pieces.flush(_blocks[on]["mi"])
	while not hold and _tasks.size() < AT_ONCE and not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var key: Vector2i = item["key"]
		var lod: int = item["lod"]
		if _tasks.has(key):
			continue
		var epoch := _epoch
		_tasks[key] = {"lod": lod, "id": JobPool.add(func():
			var arrays = _block_arrays(key, lod)
			var water = _water_arrays(key, lod) if arrays != null else null
			var shape = _ground_shapes(arrays) if arrays != null and lod == 0 else null
			_lock.lock()
			if epoch == _epoch:
				_done[key] = {"lod": lod, "arrays": arrays, "water": water, "shape": shape}
			_lock.unlock(), float(item["d"]))}
	if _tasks.is_empty():
		return
	var put := 0
	for key: Vector2i in _tasks.keys():
		if put >= PUT_PER_FRAME or not JobPool.done(_tasks[key]["id"]):
			continue
		JobPool.wait(_tasks[key]["id"])
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
			# Its ground solid a piece at a time over the next frames, unless it's ground that was solid already being
			# laid again, or you're on it or nearly.
			var at_once := (old != null and int(_blocks[key]["lod"]) == 0) \
				or Rect2(Vector2(key) * BLOCK, Vector2.ONE * BLOCK).grow(64.0).has_point(_at)
			var shapes: Array = got["shape"] if got.get("shape") != null else []
			for i in shapes.size():
				var body := StaticBody3D.new()
				body.name = "Ground" if i == 0 else "Ground_%d" % i
				body.collision_layer = 1
				body.set_meta("surface", "grass")
				var cs := CollisionShape3D.new()
				cs.shape = shapes[i]
				body.add_child(cs)
				if at_once:
					mi.add_child(body)
				else:
					_pieces.add(mi, body)
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
static func _ground_shapes(arrays: Array) -> Array[ConcavePolygonShape3D]:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		# (not the skirts: a skirt's triangles stand on end, two of their corners one over the other)
		if _apart(a, b) and _apart(b, c) and _apart(a, c):
			faces.append_array([a, b, c])
	# (in pieces that go in a few a frame: see StreamPieces)
	return StreamPieces.shapes(StreamPieces.split(faces, BLOCK))


## Whether `a` and `b` aren't one over the other.
static func _apart(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) > 0.01 or absf(a.z - b.z) > 0.01


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


## Any height in `grid` (`m` a side) that isn't a number (the ground not in there yet, or no road height for it) made
## its nearest neighbour's along the row, or the column, so no vertex is ever lost and leaves a hole: the block is laid
## again once the ground comes.
static func _fill_gaps(grid: PackedFloat32Array, m: int) -> PackedFloat32Array:
	var any := false
	for g in grid.size():
		if not is_finite(grid[g]):
			any = true
			break
	if not any:
		return grid
	for pass_dir in 2:
		for line in m:
			var last := NAN
			for step in 2:
				for t in m:
					var u := t if step == 0 else m - 1 - t
					var g := line * m + u if pass_dir == 0 else u * m + line
					if is_finite(grid[g]):
						last = grid[g]
					elif not is_nan(last):
						grid[g] = last
	for g in grid.size():
		if not is_finite(grid[g]):
			grid[g] = 0.0   # (none in the whole block: flat rather than a hole, till the ground comes)
	return grid


## The vertex index of fine point (I, J) of a block `n` vertices a side: a cell's corner is the block's own vertex.
static func _fine_vert(fine: Dictionary, I: int, J: int, n: int) -> int:
	if I % FINE == 0 and J % FINE == 0:
		return (J / FINE) * n + I / FINE
	return fine[Vector2i(I, J)]


## The cells of a near block on the road network that the roads cut into or bank, drawn finer (FINE times, each way):
## where the land part-way along a cell's sides or at its middle (net.ground_at) strays more than REFINE_OFF from the
## straight line or the plane between its corners. The cell either side of the block's edge is looked at too, so the
## finer points along a side shared with a block next door are the same in both. Adds the finer cells' vertices (their
## heights the land's own, but along a side shared with a cell that isn't finer, on the straight line between its
## corners, so there's no crack) to `verts` (and `norms`, `cols`), indexed in `fine`; returns the finer cells
## {Vector2i(i, j): true} inside the block.
func _refine(ox: float, oz: float, cells: int, sp: float, grid: PackedFloat32Array, bares: PackedFloat32Array, m: int,
		net: Object, memo: Dictionary, fine: Dictionary,
		verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, knot: PackedInt32Array,
		lats: PackedFloat32Array, n: int, water := {}) -> Dictionary:
	var fs := sp / FINE
	var land := {}   # Vector2i fine point -> the land's height there (ground_at), as it's asked for
	var land_at := func(I: int, J: int) -> float:
		var key := Vector2i(I, J)
		if land.has(key):
			return land[key]
		var x := ox + I * fs
		var z := oz + J * fs
		# (the bare ground between the cell's corners, as they have it: the height tiles are coarser than a cell)
		var ci := clampi(floori(float(I) / FINE), -1, cells)
		var cj := clampi(floori(float(J) / FINE), -1, cells)
		var tx := float(I - ci * FINE) / FINE
		var tz := float(J - cj * FINE) / FINE
		var g := (cj + 1) * m + (ci + 1)
		var bare := lerpf(lerpf(bares[g], bares[g + 1], tx), lerpf(bares[g + m], bares[g + m + 1], tx), tz)
		var y := NAN if is_nan(bare) else float(net.call("ground_at", x, z, bare, memo))
		land[key] = y
		return y
	# (a corner's height, I and J multiples of FINE, -FINE to (cells + 1) * FINE)
	var corner := func(I: int, J: int) -> float:
		return grid[(J / FINE + 1) * m + (I / FINE + 1)]
	var wants := {}
	for cj in range(-1, cells + 1):
		if hold:
			return {}
		for ci in range(-1, cells + 1):
			var I := ci * FINE
			var J := cj * FINE
			# (a road's cut and bank is wider than a cell, so one the roads shape has a corner they shape)
			var g := (cj + 1) * m + (ci + 1)
			if absf(grid[g] - bares[g]) < 0.01 and absf(grid[g + 1] - bares[g + 1]) < 0.01 and absf(grid[g + m] - bares[g + m]) < 0.01 \
					and absf(grid[g + m + 1] - bares[g + m + 1]) < 0.01:
				continue
			var h00: float = corner.call(I, J)
			var h10: float = corner.call(I + FINE, J)
			var h01: float = corner.call(I, J + FINE)
			var h11: float = corner.call(I + FINE, J + FINE)
			var half := FINE / 2
			var off := 0.0
			for look: Array in [[half, 0, (h00 + h10) * 0.5], [0, half, (h00 + h01) * 0.5], [FINE, half, (h10 + h11) * 0.5],
					[half, FINE, (h01 + h11) * 0.5], [half, half, (h00 + h11) * 0.5]]:
				var y: float = land_at.call(I + int(look[0]), J + int(look[1]))
				if not is_nan(y):
					off = maxf(off, absf(y - float(look[2])))
			if off > REFINE_OFF:
				wants[Vector2i(ci, cj)] = true
	var out := {}
	for c: Vector2i in wants:
		if c.x >= 0 and c.y >= 0 and c.x < cells and c.y < cells:
			out[c] = true
	# The finer cells' vertices: on a side shared with a cell that isn't finer, on the line between that side's corners.
	var added := PackedInt32Array()
	for c: Vector2i in out:
		for fj in FINE + 1:
			for fi in FINE + 1:
				if (fi == 0 or fi == FINE) and (fj == 0 or fj == FINE):
					continue
				var I := c.x * FINE + fi
				var J := c.y * FINE + fj
				var key := Vector2i(I, J)
				if fine.has(key):
					continue
				var y := NAN
				var other := c
				if fi == 0:
					other = c + Vector2i(-1, 0)
				elif fi == FINE:
					other = c + Vector2i(1, 0)
				elif fj == 0:
					other = c + Vector2i(0, -1)
				elif fj == FINE:
					other = c + Vector2i(0, 1)
				if other == c or wants.has(other):
					y = land_at.call(I, J)
				if is_nan(y):
					var t := float(fj if (fi == 0 or fi == FINE) else fi) / FINE
					if fi == 0 or fi == FINE:
						y = lerpf(corner.call(I, c.y * FINE), corner.call(I, c.y * FINE + FINE), t)
					elif fj == 0 or fj == FINE:
						y = lerpf(corner.call(c.x * FINE, J), corner.call(c.x * FINE + FINE, J), t)
					else:
						y = lerpf(lerpf(corner.call(c.x * FINE, c.y * FINE), corner.call(c.x * FINE + FINE, c.y * FINE), float(fi) / FINE),
							lerpf(corner.call(c.x * FINE, c.y * FINE + FINE), corner.call(c.x * FINE + FINE, c.y * FINE + FINE), float(fi) / FINE),
							float(fj) / FINE)
				fine[key] = verts.size()
				added.append(verts.size())
				verts.append(Vector3(I * fs, y, J * fs))
				norms.append(Vector3.UP)
				var g := (c.y + 1) * m + (c.x + 1)
				cols.append(Color.BLACK)
				knot.append(knot[g])   # (each finer vertex's road and lat, for its colour: its cell's corner's)
				lats.append(lats[g])
	# Their normals from the points either side (the land's own, or the block's vertices'), and their colours.
	var y_at := func(I: int, J: int) -> float:
		if I % FINE == 0 and J % FINE == 0 and I >= -FINE and J >= -FINE:
			return corner.call(I, J)
		var key := Vector2i(I, J)
		if fine.has(key):
			return verts[fine[key]].y
		var y: float = land_at.call(I, J)
		return y
	var base := knot.size() - added.size()
	for q in added.size():
		var vi := added[q]
		var p := verts[vi]
		var I := roundi(p.x / fs)
		var J := roundi(p.z / fs)
		var dx: float = y_at.call(I - 1, J) - y_at.call(I + 1, J)
		var dz: float = y_at.call(I, J - 1) - y_at.call(I, J + 1)
		var nm := Vector3(dx if is_finite(dx) else 0.0, 2.0 * fs, dz if is_finite(dz) else 0.0).normalized()
		norms[vi] = nm
		cols[vi] = _colour(knot[base + q], lats[base + q], ox + p.x, oz + p.z, p.y, nm, true, water)
	return out


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
	var memo := {}   # (this worker's own copy of the roads it asks after: RoadNet.ground_at)
	# (the water's tiles round the block, where it's drawn: by_water and the banks' colours ask them at every vertex)
	var water := terrain.water_view(Rect2(ox, oz, BLOCK - 1.0, BLOCK - 1.0)) if lod < WATER_LODS else {}
	# (the far level lies past where the road blocks are drawn, RoadStreamer.REACH: the roads don't cut it)
	var cut := net != null and lod < 2 and bool(net.call("roads_near", Rect2(ox - sp, oz - sp, BLOCK + sp * 2.0, BLOCK + sp * 2.0)))
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
	var bares := PackedFloat32Array()
	bares.resize(m * m)
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
			elif lod < WATER_LODS and i > 0 and j > 0 and i < m - 1 and j < m - 1:
				bare = by_water(x, z, bare, water)   # (the block's own: not the border round it, for the normals)
			bares[g] = bare
			if net != null:
				grid[g] = float(net.call("ground_at", x, z, bare, memo)) if cut else bare
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
	grid = _fill_gaps(grid, m)
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
			cols[j * n + i] = _colour(knot[g], lats[g], ox + i * sp, oz + j * sp, h, norms[j * n + i], lod < WATER_LODS, water)
	# On the road network, a near cell the roads cut or bank into is drawn FINE times finer (_refine), so the land
	# follows the cuttings and banks as closely as the planned road's own land does.
	var fine := {}   # Vector2i(fine x, fine z) in the block -> vertex index, for the finer cells' vertices
	var refined := {}   # Vector2i cell -> true
	if net != null and cut and lod == 0:
		refined = _refine(ox, oz, cells, sp, grid, bares, m, net, memo, fine, verts, norms, cols, knot, lats, n, water)
	# Cells wholly under the chunks' own land are left out.
	var idx := PackedInt32Array()
	var any := false
	for j in cells:
		for i in cells:
			var a := (j + 1) * m + (i + 1)
			if sp <= 16.0 and dist[a] < STRIP_OUT and dist[a + 1] < STRIP_OUT and dist[a + m] < STRIP_OUT and dist[a + m + 1] < STRIP_OUT:
				continue
			any = true
			if refined.has(Vector2i(i, j)):
				for fj in FINE:
					for fi in FINE:
						var I := i * FINE + fi
						var J := j * FINE + fj
						var v00 := _fine_vert(fine, I, J, n)
						var v10 := _fine_vert(fine, I + 1, J, n)
						var v01 := _fine_vert(fine, I, J + 1, n)
						var v11 := _fine_vert(fine, I + 1, J + 1, n)
						idx.append_array([v00, v10, v11, v00, v11, v01])
				continue
			var v := j * n + i
			idx.append_array([v, v + 1, v + n + 1, v, v + n + 1, v + n])
	if not any:
		return null
	# Skirts round the edge: as deep as the edge's mesh and the real ground ever part along it (the neighbour at another
	# level, or the ridge, may be anywhere in between), and more. Every vertex along the edge has its skirt (the finer
	# cells' too).
	for e in 4:
		var drop := SKIRT_MIN + _edge_gap(ox, oz, e, cells, sp, verts, n, memo if cut else null)
		var along := PackedInt32Array()
		for t in cells * FINE + 1:
			var I := t if e < 2 else (0 if e == 2 else cells * FINE)
			var J := t if e >= 2 else (0 if e == 0 else cells * FINE)
			if t % FINE == 0:
				along.append(_fine_vert(fine, I, J, n))
			elif fine.has(Vector2i(I, J)):
				along.append(fine[Vector2i(I, J)])
		var base := verts.size()
		for src in along:
			verts.append(verts[src] + Vector3.DOWN * drop)
			norms.append(norms[src])
			cols.append(cols[src])
		for t in along.size() - 1:
			var s0 := along[t]
			var s1 := along[t + 1]
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
## its middle is (or the land there is let down under it beside it: RealTerrain.water_shore), and one either side of it
## too, at the water's level (RealTerrain.water_level): the banks rise through it, so the shore follows the land rather
## than the cells' squares.
func _water_arrays(key: Vector2i, lod: int) -> Variant:
	if lod >= WATER_LODS:
		return null
	var cells: int = CELLS[lod]
	var sp := BLOCK / cells
	var ox := key.x * BLOCK
	var oz := key.y * BLOCK
	var water := terrain.water_view(Rect2(ox, oz, BLOCK - 1.0, BLOCK - 1.0))
	# Each cell's middle, a cell's border round the block: water there.
	var m := cells + 2
	var wet := PackedByteArray()
	wet.resize(m * m)
	var any := false
	for j in m:
		if hold:
			return null
		for i in m:
			var cx := ox + (i - 0.5) * sp
			var cz := oz + (j - 0.5) * sp
			if terrain.cover(cx, cz) != RealPack.WATER:
				# (or land let down under the water beside it, RealTerrain.water_shore, in the block: not the border
				# round it, which would ask after the next block's water too)
				if i == 0 or j == 0 or i == m - 1 or j == m - 1:
					continue
				var w := terrain.water_at(cx, cz, water)
				if is_nan(w.x) or w.y <= 0.0:
					continue
				var hs := terrain.height(cx, cz)
				if is_nan(hs) or RealTerrain.shore_of(w, hs) >= w.x:
					continue
			elif is_nan(terrain.height(cx, cz)):
				continue
			wet[j * m + i] = 1
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
	# Each corner of the cells: the water's level there (RealTerrain.water_level: flat across a river, easing down along
	# it, the same in every block), where it's a corner of a cell with water, or a cell round those (a corner on the
	# shore, a little lower), so the water is one level surface, no steps.
	var n := cells + 1
	var corner := PackedFloat32Array()
	corner.resize(n * n)
	for vj in n:
		for vi in n:
			var h := INF
			for reach: int in [1, 2]:
				var wet_by := false
				for cj in range(vj + 1 - reach, vj + 1 + reach):
					for ci in range(vi + 1 - reach, vi + 1 + reach):
						if ci >= 0 and cj >= 0 and ci < m and cj < m and wet[cj * m + ci] == 1:
							wet_by = true
				if wet_by:
					var lv := terrain.water_level(ox + vi * sp, oz + vj * sp, water)
					if not is_nan(lv):
						h = lv - (WATER_SHORE if reach == 2 else 0.0)   # (on the shore: dipping into the bank)
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
## lowest of them a point either way; on the network ride no higher than the land with the roads cut in), over the
## trough the land has along it (AdventureRoute.ground_at). Each segment is
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
			if roads != null:
				# (down with the land where a road's bank has cut it, never standing over it)
				ha = minf(ha, float(roads.call("ground_at", a.x, a.y, ha)))
				hb = minf(hb, float(roads.call("ground_at", b.x, b.y, hb)))
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
	if roads != null:
		return _on_net(x, z)
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


## _on_road for the road network: whether (x, z) is on a road, its verge, or the land held level with it past the verge
## (RoadNet.LAND_PAD, where water would stand over the cut land), unless it's under a bridge.
func _on_net(x: float, z: float) -> bool:
	var on: Dictionary = roads.call("locate", x, z)
	if on.is_empty():
		return false
	var off := absf(float(on["lat"])) - float(on["width"]) * 0.5
	return off <= RoadNet.VERGE + RoadNet.LAND_PAD and float(roads.call("bridge_at", int(on["edge"]), float(on["s"]))) < 0.5


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


## The ground at (x, z) where the water is drawn (the near and middle levels: WATER_LODS), from the ground there
## (AdventureRoute.ground_at, `bare`): under a river or a lake its bed under the water's level (RealTerrain.water_bed),
## not under the map's heights there, which run up its banks and wander; beside it, land the map has level with the
## water let down just under it (RealTerrain.water_shore). Any thread.
func by_water(x: float, z: float, bare: float, water := {}) -> float:
	if terrain.cover(x, z) == RealPack.WATER:
		# (ground_at has the bed WATER_DEPTH under the map's height there)
		return terrain.water_bed(x, z, bare + AdventureRoute.WATER_DEPTH, AdventureRoute.WATER_DEPTH, water)
	return terrain.water_shore(x, z, bare, water)


## Land colour `col` at (x, z), height y, on a river's or lake's bank: stone and shingle up from the water, darker where
## it's damp just over it, out to BANK_HIGH above the water and as far from it as the water's nearness
## (RealTerrain.water_at) reaches; under the water the same (the bed shows where a bank stands in it).
func _bank(col: Color, x: float, z: float, y: float, water := {}) -> Color:
	var w := terrain.water_at(x, z, water)
	if w.y <= 0.0 or is_nan(w.x):
		return col
	var up := y - w.x
	var k := smoothstep(BANK_REACH * 0.4, BANK_REACH, w.y) * (1.0 - smoothstep(BANK_HIGH * 0.5, BANK_HIGH, up))
	if k <= 0.0:
		return col
	var bank := BANK_COLOUR.lerp(col, 0.15).darkened(0.25 * (1.0 - smoothstep(0.0, BANK_DAMP, up)))
	return col.lerp(bank, k)


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
## edge `e` (0 north, 1 south, 2 west, 3 east): the crack a neighbour at another level could show. With `memo` (a block
## the roads cut, RoadNet.ground_at's), the cut land's too (_net_edge_gap).
func _edge_gap(ox: float, oz: float, e: int, cells: int, sp: float, verts: PackedVector3Array, n: int, memo = null) -> float:
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
	if roads != null and memo != null:
		gap = maxf(gap, _net_edge_gap(ox, oz, e, cells, sp, verts, n, memo))
	return gap


## _edge_gap on the road network, where the land is cut and banked for the roads at the near levels: how far this block's
## edge `e` and a neighbour's at any level can part along it. Both are the same land (ground_at) at the points they
## share, every EDGE_KNOT (the coarsest level's cell), and straight or nearly so between: so the most this edge strays
## from the land, or the land from a straight line between those points, every EDGE_LOOK along it.
func _net_edge_gap(ox: float, oz: float, e: int, cells: int, sp: float, verts: PackedVector3Array, n: int, memo := {}) -> float:
	var looks := int(BLOCK / EDGE_LOOK)
	var land := PackedFloat32Array()
	land.resize(looks + 1)
	for k in looks + 1:
		var t := k * EDGE_LOOK
		var x := ox + (t if e < 2 else (0.0 if e == 2 else BLOCK))
		var z := oz + (t if e >= 2 else (0.0 if e == 0 else BLOCK))
		var bare := route.ground_at(x, z)
		land[k] = NAN if is_nan(bare) else float(roads.call("ground_at", x, z, bare, memo))
	var gap := 0.0
	var per := int(EDGE_KNOT / EDGE_LOOK)
	for k in looks + 1:
		if is_nan(land[k]):
			continue
		# This edge there (between its own vertices), and the coarsest neighbour's (between the shared points).
		var f := k * EDGE_LOOK / sp
		var i0 := mini(int(f), cells - 1)
		var mine := lerpf(verts[_edge_vert(e, i0, n)].y, verts[_edge_vert(e, i0 + 1, n)].y, f - i0)
		var k0 := (k / per) * per
		var k1 := mini(k0 + per, looks)
		var theirs := land[k]
		if not is_nan(land[k0]) and not is_nan(land[k1]) and k1 > k0:
			theirs = lerpf(land[k0], land[k1], float(k - k0) / float(k1 - k0))
		gap = maxf(gap, maxf(absf(land[k] - mine), absf(theirs - mine)))
	return gap


## The vertex index of point `t` along edge `e` of a block `n` vertices a side (see _edge_gap's order).
static func _edge_vert(e: int, t: int, n: int) -> int:
	match e:
		0: return t
		1: return (n - 1) * n + t
		2: return t * n
	return t * n + n - 1


## The ground's colour: what the road's own land is there (its surface's, patched, tinted by what covers it), so the two
## meet without a line; rock where the ground itself is steep (by its normal: far from the road, how far it has risen
## from the road means nothing), and a beach by the sea. Under water it's the bed's, where the water is drawn (`wet`), and
## the water's own blue where it isn't (the far level).
func _colour(i: int, lat: float, x: float, z: float, y: float, normal: Vector3, wet := true, water := {}) -> Color:
	var col := AdventureChunk._land_color(route, i, 3, lat, x, z, y, NET_SATELLITE if roads != null else 1.0)
	if not wet and terrain.cover(x, z) == RealPack.WATER:
		return col.lerp(FAR_WATER, 0.85)
	if route.cover_at(x, z) == "":
		col = col.lerp(route.look.get("woods", RealRidges.WOODS), 0.5)   # past the baked cover: about what the place is mostly (its climate's woods)
	col = col.lerp(Color(0.45, 0.43, 0.4), smoothstep(0.32, 0.62, 1.0 - normal.y) * 0.7)
	if wet:
		col = _bank(col, x, z, y, water)
	if route.sea and y < AdventureTheme.SEA_Y + 5.0:
		col = col.lerp(AdventureChunk.BEACH, 1.0 - smoothstep(AdventureTheme.SEA_Y + 2.0, AdventureTheme.SEA_Y + 5.0, y))
		if y < AdventureTheme.SEA_Y - 0.2:
			col = AdventureChunk.BEACH.darkened(0.3)
	return col
