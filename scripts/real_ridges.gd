class_name RealRidges
extends Node3D
## The skyline of a real road: the real hills and mountains beyond the land mesh (which runs 1 km out), drawn from
## the pack's ridge level (RealTerrain.ridge_tile: 128 m samples, baked pushed down near the road so the land hides
## it there). A block of BLOCK samples square is a mesh of its own, made when it comes within RANGE of the rider
## and dropped once it is DROP away; they sit in the route's frame, so they move with the world's origin
## (AdventureWorld.shift_origin_to calls place()).

const BLOCK := 32
## How many blocks are laid out at once.
const AT_ONCE := 2
const RANGE := 14000.0
const DROP := 17000.0
## Past this the ridge's own height (m) is rock and, on a snowy road, the snow line takes over.
const ROCK_FROM := 600.0
const ROCK_TO := 1400.0
## Within this of the road (m) the ridge lies LAND_UNDER below the real height, easing back up to it over the next
## LAND_EASE: RealLand's blocks (the garage map's way of drawing the land) are above it there, and the two never fight.
const LAND_REACH := 5400.0
const LAND_EASE := 700.0
const LAND_UNDER := 30.0
## A live ridge level (RealTerrain.ridge_lowered false) is pushed down here as the baker pushes a baked one down
## (tools/route_bake.py ridge_tile): LOWER metres within LOWER_NEAR of the road, easing back up by LOWER_FAR.
const LOWER := 90.0
const LOWER_NEAR := 700.0
const LOWER_FAR := 1000.0
const WOODS := Color(0.09, 0.22, 0.1)
const ROCK := Color(0.46, 0.44, 0.4)
const SNOW := Color(0.92, 0.93, 0.96)

var world: AdventureWorld
var terrain: RealTerrain
var _blocks := {}   # Vector2i -> MeshInstance3D (null where the pack has no ridge there: not asked again)
var _tasks := {}    # Vector2i -> worker task id while its mesh is laid out
var _queue: Array[Vector2i] = []   # blocks to make, nearest first, a few at a time (they must not crowd out the road's chunks)
var _done := {}     # Vector2i -> the arrays it made (or null), waiting for the main thread
var _lock := Mutex.new()
var _material: StandardMaterial3D
var _land := Color(0.3, 0.4, 0.22)
var _snow_line := INF
var _at := Vector2(INF, INF)
## The road every 16th knot, for easing the ridge down under the land blocks (RealLand) along it.
var _road := PackedVector2Array()
var _stale := {}    # Vector2i -> the block made before its tiles came in, shown till the new one replaces it


func setup(w: AdventureWorld, t: RealTerrain) -> void:
	name = "RealRidges"
	world = w
	terrain = t
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true   # (as the land's: RealLand)
	_material.roughness = 1.0
	if w.route != null:
		_land = (w.route.look["land"]["tarmac"] as Color).lerp(w.route.look.get("woods", WOODS), 0.55)
		_snow_line = w.route.snow_line
		for k in range(0, w.route.px.size(), 16):
			_road.append(Vector2(w.route.px[k], w.route.pz[k]))
	if t != null and not t.ground_arrived.is_connected(_on_ground):
		t.ground_arrived.connect(_on_ground)


## New ridge-level tiles came in over `area` (RealTerrain.ground_arrived): the skyline there is made again (the old
## blocks stay till the new are in), and any block that had nothing there is asked again.
func _on_ground(area: Rect2, level: int) -> void:
	if level != 2:
		return
	var size := BLOCK * terrain.ridge_spacing()
	var any := false
	for key: Vector2i in _blocks.keys():
		if Rect2(key.x * size, key.y * size, size, size).intersects(area):
			_stale[key] = _blocks[key]
			_blocks.erase(key)
			any = true
	if any:
		_at = Vector2(INF, INF)


func _exit_tree() -> void:
	for key in _tasks:
		JobPool.drop(_tasks[key])
	_tasks.clear()


## Starts the blocks within RANGE of route-frame (x, z) (laid out on worker threads, put in by _process) and drops
## those past DROP.
func follow(x: float, z: float) -> void:
	if terrain == null or terrain.levels.is_empty() or Vector2(x, z).distance_to(_at) < 400.0:
		return
	_at = Vector2(x, z)
	var size := BLOCK * terrain.ridge_spacing()
	var b0 := Vector2i(floori((x - RANGE) / size), floori((z - RANGE) / size))
	var b1 := Vector2i(floori((x + RANGE) / size), floori((z + RANGE) / size))
	for bz in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var key := Vector2i(bx, bz)
			var mid := Vector2((bx + 0.5) * size, (bz + 0.5) * size)
			if _blocks.has(key) or _tasks.has(key) or mid.distance_to(_at) > RANGE + size * 0.7:
				continue
			if not _queue.has(key):
				_queue.append(key)
	_queue = _queue.filter(func(k): return Vector2((k.x + 0.5) * size, (k.y + 0.5) * size).distance_to(_at) <= RANGE + size * 0.7)
	_queue.sort_custom(func(a, b): return Vector2((a.x + 0.5) * size, (a.y + 0.5) * size).distance_squared_to(_at) \
		< Vector2((b.x + 0.5) * size, (b.y + 0.5) * size).distance_squared_to(_at))
	for key: Vector2i in _blocks.keys():
		var mid := Vector2((key.x + 0.5) * size, (key.y + 0.5) * size)
		if mid.distance_to(_at) > DROP + size * 0.7:
			var mi: MeshInstance3D = _blocks[key]
			if mi != null:
				mi.queue_free()
			_blocks.erase(key)
	for key: Vector2i in _stale.keys():
		if not _queue.has(key) and not _tasks.has(key):
			if _stale[key] != null:
				(_stale[key] as Node).queue_free()
			_stale.erase(key)


func _process(_delta: float) -> void:
	while _tasks.size() < AT_ONCE and not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		_tasks[key] = JobPool.add(func():
			var arrays = _block_arrays(key)
			_lock.lock()
			_done[key] = arrays
			_lock.unlock(), RANGE)   # (after the near land and roads)
	if _tasks.is_empty():
		return
	var put := 0
	for key: Vector2i in _tasks.keys():
		if put >= 2 or not JobPool.done(_tasks[key]):
			continue
		JobPool.wait(_tasks[key])
		_tasks.erase(key)
		_lock.lock()
		var arrays = _done.get(key)
		_done.erase(key)
		_lock.unlock()
		var mi: MeshInstance3D = null
		if arrays != null:
			mi = _make_mesh(key, arrays)
			add_child(mi)
			_place(key, mi)
			put += 1
		var old = _stale.get(key)
		_stale.erase(key)
		if old != null:
			(old as Node).queue_free()
		_blocks[key] = mi


## Puts every block where the world's origin has it (after a shift).
func place() -> void:
	for key: Vector2i in _blocks:
		if _blocks[key] != null:
			_place(key, _blocks[key])
	for key: Vector2i in _stale:
		if _stale[key] != null:
			_place(key, _stale[key])


func block_count() -> int:
	return _blocks.values().filter(func(b): return b != null).size()


## Whether any block is still waiting or being laid out.
func busy() -> bool:
	return not _tasks.is_empty() or not _queue.is_empty()


func _place(key: Vector2i, mi: MeshInstance3D) -> void:
	var size := BLOCK * terrain.ridge_spacing()
	mi.position = Vector3(key.x * size - world.origin.x, 0.0, key.y * size - world.origin.z)


## The mesh arrays of block `key` (BLOCK x BLOCK cells), or null where there is no ridge land in it. Any thread.
func _block_arrays(key: Vector2i) -> Variant:
	var sp := terrain.ridge_spacing()
	var per := terrain.ridge_cells()
	var n := BLOCK + 1
	var m := n + 2   # (a sample's border either side, for the normals)
	var tiles := {}
	var grid := PackedFloat32Array()
	grid.resize(m * m)
	var any := false
	for j in m:
		for i in m:
			var ix := key.x * BLOCK + i - 1
			var iz := key.y * BLOCK + j - 1
			var tk := Vector2i(floori(float(ix) / per), floori(float(iz) / per))
			if not tiles.has(tk):
				tiles[tk] = terrain.ridge_tile(tk)
			var t: PackedFloat32Array = tiles[tk]
			var h := NAN if t.is_empty() else t[posmod(iz, per) * per + posmod(ix, per)]
			grid[j * m + i] = h
			any = any or (not is_nan(h) and i > 0 and j > 0 and i < m - 1 and j < m - 1)
	if not any:
		return null
	if not terrain.ridge_lowered():
		_lower_near_road(key, grid, m, sp)
	# The stretch of road that could be within reach of this block.
	var size := BLOCK * sp
	var near_road := PackedVector2Array()
	var lo := Vector2(key.x * size - LAND_REACH - LAND_EASE, key.y * size - LAND_REACH - LAND_EASE)
	var hi := Vector2((key.x + 1) * size + LAND_REACH + LAND_EASE, (key.y + 1) * size + LAND_REACH + LAND_EASE)
	for p in _road:
		if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y:
			near_road.append(p)
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
			if is_nan(h):
				h = -50.0
			var hl := grid[g - 1]
			var hr := grid[g + 1]
			var hu := grid[g - m]
			var hd := grid[g + m]
			hl = h if is_nan(hl) else hl
			hr = h if is_nan(hr) else hr
			hu = h if is_nan(hu) else hu
			hd = h if is_nan(hd) else hd
			verts[j * n + i] = Vector3(i * sp, h, j * sp)
			norms[j * n + i] = Vector3(hl - hr, 2.0 * sp, hu - hd).normalized()
			cols[j * n + i] = _colour(h)
	var idx := PackedInt32Array()
	for j in BLOCK:
		for i in BLOCK:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## Pushes the samples of block `key`'s grid (`m` x `m`, a sample's border round the block) down near the road.
func _lower_near_road(key: Vector2i, grid: PackedFloat32Array, m: int, sp: float) -> void:
	var x0 := (key.x * BLOCK - 1) * sp
	var z0 := (key.y * BLOCK - 1) * sp
	var span := (m - 1) * sp
	var near := PackedVector2Array()
	for p in _road:
		if p.x >= x0 - LOWER_FAR and p.x <= x0 + span + LOWER_FAR and p.y >= z0 - LOWER_FAR and p.y <= z0 + span + LOWER_FAR:
			near.append(p)
	if near.is_empty():
		return
	for j in m:
		for i in m:
			var g := j * m + i
			if is_nan(grid[g]):
				continue
			var at := Vector2(x0 + i * sp, z0 + j * sp)
			var d := INF
			for p in near:
				d = minf(d, at.distance_squared_to(p))
			grid[g] -= LOWER * (1.0 - smoothstep(LOWER_NEAR, LOWER_FAR, sqrt(d)))


func _make_mesh(key: Vector2i, arrays: Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Ridge_%d_%d" % [key.x, key.y]
	return mi


func _colour(h: float) -> Color:
	var col := _land.lerp(ROCK, smoothstep(ROCK_FROM, ROCK_TO, h))
	if h > _snow_line:
		col = col.lerp(SNOW, smoothstep(_snow_line, _snow_line + 250.0, h))
	return col
