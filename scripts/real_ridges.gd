class_name RealRidges
extends Node3D
## The skyline of a real road: the real hills and mountains beyond the land mesh (which runs 1 km out), drawn from
## the pack's ridge level (RealTerrain.ridge_tile: 128 m samples, baked pushed down near the road so the land hides
## it there). A block of BLOCK samples square is a mesh of its own, made when it comes within RANGE of the rider
## and dropped once it is DROP away; they sit in the route's frame, so they move with the world's origin
## (AdventureWorld.shift_origin_to calls place()).

const BLOCK := 32
const RANGE := 14000.0
const DROP := 17000.0
## Past this the ridge's own height (m) is rock and, on a snowy road, the snow line takes over.
const ROCK_FROM := 600.0
const ROCK_TO := 1400.0
const WOODS := Color(0.09, 0.22, 0.1)
const ROCK := Color(0.46, 0.44, 0.4)
const SNOW := Color(0.92, 0.93, 0.96)

var world: AdventureWorld
var terrain: RealTerrain
var _blocks := {}   # Vector2i -> MeshInstance3D
var _material: StandardMaterial3D
var _land := Color(0.3, 0.4, 0.22)
var _snow_line := INF
var _at := Vector2(INF, INF)


func setup(w: AdventureWorld, t: RealTerrain) -> void:
	name = "RealRidges"
	world = w
	terrain = t
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	if w.route != null:
		_land = (w.route.look["land"]["tarmac"] as Color).lerp(WOODS, 0.55)
		_snow_line = w.route.snow_line


## Makes the blocks within RANGE of route-frame (x, z) and drops those past DROP.
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
			if _blocks.has(key) or mid.distance_to(_at) > RANGE + size * 0.7:
				continue
			var mi := _make_block(key)
			_blocks[key] = mi   # (null where the pack has no ridge there: not asked again)
			if mi != null:
				add_child(mi)
				_place(key, mi)
	for key: Vector2i in _blocks.keys():
		var mid := Vector2((key.x + 0.5) * size, (key.y + 0.5) * size)
		if mid.distance_to(_at) > DROP + size * 0.7:
			var mi: MeshInstance3D = _blocks[key]
			if mi != null:
				mi.queue_free()
			_blocks.erase(key)


## Puts every block where the world's origin has it (after a shift).
func place() -> void:
	for key: Vector2i in _blocks:
		if _blocks[key] != null:
			_place(key, _blocks[key])


func block_count() -> int:
	return _blocks.values().filter(func(b): return b != null).size()


func _place(key: Vector2i, mi: MeshInstance3D) -> void:
	var size := BLOCK * terrain.ridge_spacing()
	mi.position = Vector3(key.x * size - world.origin.x, 0.0, key.y * size - world.origin.z)


## The ridge's height at grid sample (ix, iz) over the whole route frame, or NAN.
func _sample(ix: int, iz: int) -> float:
	var per := terrain.ridge_cells()
	var t := terrain.ridge_tile(Vector2i(floori(float(ix) / per), floori(float(iz) / per)))
	if t.is_empty():
		return NAN
	return t[posmod(iz, per) * per + posmod(ix, per)]


## The mesh of block `key` (BLOCK x BLOCK cells), or null where there is no ridge land in it.
func _make_block(key: Vector2i) -> MeshInstance3D:
	var sp := terrain.ridge_spacing()
	var n := BLOCK + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var any := false
	for j in n:
		for i in n:
			var h := _sample(key.x * BLOCK + i, key.y * BLOCK + j)
			heights[j * n + i] = h
			any = any or not is_nan(h)
	if not any:
		return null
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var h := heights[j * n + i]
			if is_nan(h):
				h = -50.0
				heights[j * n + i] = h
			verts[j * n + i] = Vector3(i * sp, h, j * sp)
			var hl := _sample(key.x * BLOCK + i - 1, key.y * BLOCK + j)
			var hr := _sample(key.x * BLOCK + i + 1, key.y * BLOCK + j)
			var hu := _sample(key.x * BLOCK + i, key.y * BLOCK + j - 1)
			var hd := _sample(key.x * BLOCK + i, key.y * BLOCK + j + 1)
			hl = h if is_nan(hl) else hl
			hr = h if is_nan(hr) else hr
			hu = h if is_nan(hu) else hu
			hd = h if is_nan(hd) else hd
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
