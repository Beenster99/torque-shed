class_name RoadStreamer
extends Node3D
## The road network round each rider on the network ride (Esc > Debug > "Road network (test)": AdventureWorld.network):
## the road blocks (RoadBlock) within REACH of any rider, laid out on worker threads and put into the world one a
## frame, freed once every rider is past KEEP, and laid out again where the ground under them sharpens (the terrain's
## ground_arrived). A block is only laid out once the ground round it is final (RoadNet.ready), so every machine lays
## out the same one. Its node sits at the block's corner in AdventureWorld's local frame (moved with the floating
## origin: place).

## Blocks whose middle is within REACH of a rider are wanted; kept until every rider is KEEP away (m).
const REACH := 1100.0
const KEEP := 1500.0
const MAX_TASKS := 2
## How far round a block the ground must be final before it's laid out (m): the farthest a road's height reaches.
const READY_PAD := 128.0

var world: AdventureWorld
var net: RoadNet
var blocks := {}         # Vector2i -> Node3D in the world
var stats := {"built": 0, "build_ms_max": 0.0, "commit_ms_max": 0.0}
var _tasks := {}         # Vector2i -> WorkerThreadPool task id
var _done := {}          # Vector2i -> RoadBlock, laid out by a worker (read under the lock)
var _waiting := {}       # Vector2i -> RoadBlock, laid out and waiting its turn to go in
var _lock := Mutex.new()
var _stale := {}         # Vector2i -> true: laid out on ground that has since sharpened (lay out again)


func setup(w: AdventureWorld, n: RoadNet) -> void:
	name = "RoadNetwork"
	world = w
	net = n
	var terrain = w.route.real.terrain if w.route != null and w.route.real != null else null
	if terrain != null and terrain.has_signal("ground_arrived"):
		terrain.connect("ground_arrived", _on_ground_arrived)


func _exit_tree() -> void:
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()


## The region-frame (x, z) of each rider (the world's focus points).
func riders() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var spots: Array = world.focus.call() if world.focus.is_valid() else []
	for p: Vector3 in spots:
		out.append(Vector2(p.x + world.origin.x, p.z + world.origin.z))
	return out


## The blocks wanted round `at`, nearest the first rider first.
static func wanted(at: Array[Vector2], reach := REACH) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for p in at:
		var k0 := RoadBlock.key_of(p.x - reach, p.y - reach)
		var k1 := RoadBlock.key_of(p.x + reach, p.y + reach)
		for bz in range(k0.y, k1.y + 1):
			for bx in range(k0.x, k1.x + 1):
				var k := Vector2i(bx, bz)
				if seen.has(k) or _centre(k).distance_to(p) > reach:
					continue
				seen[k] = true
				out.append(k)
	if not at.is_empty():
		var first := at[0]
		out.sort_custom(func(a, b): return _centre(a).distance_squared_to(first) < _centre(b).distance_squared_to(first))
	return out


static func _centre(k: Vector2i) -> Vector2:
	return (Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE


## Whether block `k`'s ground is in, final, to lay it out on.
func can_build(k: Vector2i) -> bool:
	var area := Rect2(Vector2(k) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(READY_PAD)
	if net.ready.is_valid():
		return bool(net.ready.call(area))
	var c := _centre(k)
	return not is_nan(float(net.height.call(c.x, c.y)))


func _process(_delta: float) -> void:
	if net == null:
		return
	stream(riders())


## One frame's streaming round riders `at`: frees the blocks every rider is past, puts one laid out block in, and starts
## laying out the next wanted ones.
func stream(at: Array[Vector2]) -> void:
	if at.is_empty():
		return
	for k: Vector2i in blocks.keys():
		if at.all(func(p): return _centre(k).distance_to(p) > KEEP):
			blocks[k].queue_free()
			blocks.erase(k)
	var want := wanted(at)
	_lock.lock()
	for k in _done.keys():
		if WorkerThreadPool.is_task_completed(_tasks[k]):
			if not (_done[k] as RoadBlock).stale:
				_waiting[k] = _done[k]
			_done.erase(k)
			WorkerThreadPool.wait_for_task_completion(_tasks[k])
			_tasks.erase(k)
	_lock.unlock()
	# One a frame, nearest first; any no longer wanted (or laid out on ground that has since sharpened) dropped.
	for k in _waiting.keys():
		if not want.has(k) and not blocks.has(k):
			_waiting.erase(k)
	for k in want:
		if _waiting.has(k):
			var b: RoadBlock = _waiting[k]
			_waiting.erase(k)
			commit(b)
			break
	for k in want:
		if _tasks.size() >= MAX_TASKS:
			break
		if (blocks.has(k) and not _stale.has(k)) or _tasks.has(k) or _waiting.has(k) or not can_build(k):
			continue
		_tasks[k] = WorkerThreadPool.add_task(_work.bind(k), false, "Road block")


func _work(k: Vector2i) -> void:
	var b := net.block(k)
	_lock.lock()
	_done[k] = b
	_lock.unlock()


## Lays out every wanted block round `at` here and now, and puts it in (the start, behind a fade).
func preload_round(at: Array[Vector2], reach := 600.0) -> void:
	for k in wanted(at, reach):
		if not blocks.has(k) and can_build(k):
			commit(net.block(k))


## Whether a block with its collision is in under region-frame (x, z).
func has_ground(x: float, z: float) -> bool:
	return blocks.has(RoadBlock.key_of(x, z))


func _on_ground_arrived(area: Rect2, _level := 0) -> void:
	_lock.lock()
	for k: Vector2i in blocks.keys() + _waiting.keys() + _tasks.keys():
		if Rect2(Vector2(k) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(READY_PAD).intersects(area):
			_stale[k] = true
			_waiting.erase(k)
			if _done.has(k):
				(_done[k] as RoadBlock).stale = true
	_lock.unlock()


## Puts laid out block `b` into the world (in place of the one there before, if any).
func commit(b: RoadBlock) -> Node3D:
	var t0 := Time.get_ticks_usec()
	stats["built"] += 1
	stats["build_ms_max"] = maxf(float(stats["build_ms_max"]), b.ms)
	_stale.erase(b.key)
	if blocks.has(b.key):
		blocks[b.key].queue_free()
	var node := Node3D.new()
	node.name = "Block_%d_%d" % [b.key.x, b.key.y]
	node.set_meta("key", b.key)
	node.set_meta("hash", b.hash)
	var deck: Dictionary = b.arrays["deck"]
	for surf: String in deck:
		var g: Dictionary = deck[surf]
		var mi := MeshInstance3D.new()
		mi.name = "Deck_" + surf
		mi.mesh = grid_mesh(g)
		mi.material_override = AdventureSurface.road_material(surf)
		node.add_child(mi)
	for part: String in ["verge", "island"]:
		var a: Dictionary = b.arrays[part]
		if not (a["v"] as PackedVector3Array).is_empty():
			var mi := MeshInstance3D.new()
			mi.name = part.capitalize()
			mi.mesh = AdventureProps.to_mesh(a)
			node.add_child(mi)
	var lines: Dictionary = b.arrays["lines"]
	if not (lines["v"] as PackedVector3Array).is_empty():
		var lmi := MeshInstance3D.new()
		lmi.name = "Lines"
		lmi.mesh = AdventureProps.to_mesh(lines)
		lmi.material_override = AdventureSurface.line_material()
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lmi)
	if b.arrays.has("buildings") and not (b.arrays["buildings"]["v"] as PackedVector3Array).is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Buildings"
		bmi.mesh = AdventureProps.to_mesh(b.arrays["buildings"])
		node.add_child(bmi)
	for surf: String in b.arrays["faces"]:
		var body := StaticBody3D.new()
		body.name = "Body_" + surf
		body.collision_layer = 1
		body.set_meta("surface", surf)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(b.arrays["faces"][surf])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		node.add_child(body)
	blocks[b.key] = node
	_place(node)
	add_child(node)
	stats["commit_ms_max"] = maxf(float(stats["commit_ms_max"]), (Time.get_ticks_usec() - t0) / 1000.0)
	return node


## An ArrayMesh of RoadBlock grid arrays.
static func grid_mesh(g: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if (g["v"] as PackedVector3Array).is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g["v"]
	arr[Mesh.ARRAY_NORMAL] = g["n"]
	arr[Mesh.ARRAY_TEX_UV] = g["uv"]
	arr[Mesh.ARRAY_COLOR] = g["c"]
	arr[Mesh.ARRAY_INDEX] = g["i"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Puts every block at its corner in the world's local frame (after the origin moves).
func place() -> void:
	for k in blocks:
		_place(blocks[k])


func _place(node: Node3D) -> void:
	var k: Vector2i = node.get_meta("key")
	node.position = Vector3(k.x * RoadBlock.SIZE - world.origin.x, 0.0, k.y * RoadBlock.SIZE - world.origin.z)
