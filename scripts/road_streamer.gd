class_name RoadStreamer
extends Node3D
## The road network round each rider on the network ride (the default: AdventureWorld.network):
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
## A block's trees are drawn while the camera is this close to any of them (m).
const TREES_REACH := 900.0
## A block's trees, posts and buildings go in as TILES x TILES squares of their own, not one each for the whole block:
## the camera's view and each of the sun's shadow splits then only draw the squares they reach, not every tree and
## house of a 512 m block that one corner of it is in (the shadows' many times over).
const TILES := 2

var world: AdventureWorld
var net: RoadNet
var blocks := {}         # Vector2i -> Node3D in the world
var stats := {"built": 0, "build_ms_max": 0.0, "commit_ms_max": 0.0}
var _tasks := {}         # Vector2i -> JobPool job id
var _done := {}          # Vector2i -> RoadBlock, laid out by a worker (read under the lock)
var _waiting := {}       # Vector2i -> RoadBlock, laid out and waiting its turn to go in
var _lock := Mutex.new()
var _stale := {}         # Vector2i -> true: laid out on ground that has since sharpened (lay out again)
var _pieces := StreamPieces.new()   # the blocks' road going solid a piece at a time


func setup(w: AdventureWorld, n: RoadNet) -> void:
	name = "RoadNetwork"
	world = w
	net = n
	var terrain = w.route.real.terrain if w.route != null and w.route.real != null else null
	if terrain != null and terrain.has_signal("ground_arrived"):
		terrain.connect("ground_arrived", _on_ground_arrived)


func _exit_tree() -> void:
	for k in _tasks:
		JobPool.drop(_tasks[k])
	_tasks.clear()
	_pieces.clear()


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
	var pt := Perf.t0()
	_process_body(_delta)
	Perf.add("road_stream", pt)


func _process_body(_delta: float) -> void:
	_pieces.pump()
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
		if JobPool.done(_tasks[k]):
			if not (_done[k] as RoadBlock).stale:
				_waiting[k] = _done[k]
			_done.erase(k)
			JobPool.wait(_tasks[k])
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
		_tasks[k] = JobPool.add(_work.bind(k), _centre(k).distance_to(at[0]))


func _work(k: Vector2i) -> void:
	var b := _laid(k)
	_lock.lock()
	_done[k] = b
	_lock.unlock()


## Block `k` laid out, with its collision shapes made too (any thread), in pieces (StreamPieces): made in commit, on
## the main thread, and taken in by the physics as one, a block's shapes were a hitch of their own as it came in.
func _laid(k: Vector2i) -> RoadBlock:
	var b := net.block(k)
	var shapes := {}
	for surf: String in b.arrays["faces"]:
		shapes[surf] = StreamPieces.shapes(StreamPieces.split(b.arrays["faces"][surf], RoadBlock.SIZE))
	b.set_meta("shapes", shapes)
	if b.arrays.has("buildings"):
		b.set_meta("building_tiles", tile_soup(b.arrays["buildings"]))
	b.set_meta("tree_tiles", tile_lists(b.trees))
	b.set_meta("roadside_tiles", tile_lists(b.roadside))
	return b


## Which of a block's TILES x TILES squares block-local point `p` is in (0 .. TILES² - 1).
static func tile_of(p: Vector3) -> int:
	var n := RoadBlock.SIZE / TILES
	return clampi(int(p.z / n), 0, TILES - 1) * TILES + clampi(int(p.x / n), 0, TILES - 1)


## Triangle soup `a` ({v, n, c}, block-local) cut into the squares its triangles' middles are in: one soup a square.
static func tile_soup(a: Dictionary) -> Array:
	var out := []
	for i in TILES * TILES:
		out.append(AdventureProps.new_arrays())
	var v: PackedVector3Array = a["v"]
	var nrm: PackedVector3Array = a["n"]
	var col: PackedColorArray = a["c"]
	for t in range(0, v.size() - 2, 3):
		var o: Dictionary = out[tile_of((v[t] + v[t + 1] + v[t + 2]) / 3.0)]
		o["v"].append_array([v[t], v[t + 1], v[t + 2]])
		o["n"].append_array([nrm[t], nrm[t + 1], nrm[t + 2]])
		o["c"].append_array([col[t], col[t + 1], col[t + 2]])
	return out


## {kind: [transforms]} cut into the squares each stands in: {kind: [[transforms] a square]}.
static func tile_lists(by_kind: Dictionary) -> Dictionary:
	var out := {}
	for kind in by_kind:
		var tiles := []
		for i in TILES * TILES:
			tiles.append([])
		for xf: Transform3D in by_kind[kind]:
			tiles[tile_of(xf.origin)].append(xf)
		out[kind] = tiles
	return out


## Lays out every wanted block round `at` here and now (on every core at once), and puts it in (the start, behind a
## fade).
func preload_round(at: Array[Vector2], reach := 600.0) -> void:
	var keys: Array[Vector2i] = []
	for k in wanted(at, reach):
		if not blocks.has(k) and can_build(k):
			keys.append(k)
	if keys.is_empty():
		return
	var laid: Array[RoadBlock] = []
	laid.resize(keys.size())
	# (ahead of all else on the workers, and this thread lends a hand: no more threads at work than there are cores)
	var ids: Array[int] = []
	for i in keys.size():
		ids.append(JobPool.add(func(): laid[i] = _laid(keys[i]), -INF))
	for id in ids:
		JobPool.wait(id)
	for b in laid:
		commit(b, true)


## As preload_round, without holding the game up while it's done (so a loading screen can show how it's getting on):
## the blocks are laid out on every core while `report` is told (done, out of) each frame, then put in a few a frame.
## The streaming round the riders waits meanwhile.
func preload_round_async(at: Array[Vector2], reach := 600.0, report := Callable()) -> void:
	var keys: Array[Vector2i] = []
	for k in wanted(at, reach):
		if not blocks.has(k) and can_build(k):
			keys.append(k)
	if keys.is_empty():
		return
	var was := is_processing()
	set_process(false)
	var laid: Array[RoadBlock] = []
	laid.resize(keys.size())
	var group := WorkerThreadPool.add_group_task(func(i: int): laid[i] = _laid(keys[i]), keys.size(), -1, true,
		"Road blocks round the start")
	while not WorkerThreadPool.is_group_task_completed(group):
		if report.is_valid():
			report.call(WorkerThreadPool.get_group_processed_element_count(group), keys.size())
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(group)
	for i in laid.size():
		commit(laid[i], true)
		if i % 4 == 3 and i + 1 < laid.size():
			await get_tree().process_frame
	if report.is_valid():
		report.call(keys.size(), keys.size())
	set_process(was)


## Whether a block with its collision is in under region-frame (x, z).
func has_ground(x: float, z: float) -> bool:
	var k := RoadBlock.key_of(x, z)
	return blocks.has(k) and not _pieces.has(blocks[k])


func _on_ground_arrived(area: Rect2, _level := 0) -> void:
	net.forget_guesses()
	if world != null:
		world.forget_network_y.call_deferred()
	_lock.lock()
	for k: Vector2i in blocks.keys() + _waiting.keys() + _tasks.keys():
		if Rect2(Vector2(k) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(READY_PAD).intersects(area):
			_stale[k] = true
			_waiting.erase(k)
			if _done.has(k):
				(_done[k] as RoadBlock).stale = true
	_lock.unlock()


## Puts laid out block `b` into the world (in place of the one there before, if any), solid `at_once` or a piece at a
## time.
func commit(b: RoadBlock, at_once := false) -> Node3D:
	var t0 := Time.get_ticks_usec()
	stats["built"] += 1
	stats["build_ms_max"] = maxf(float(stats["build_ms_max"]), b.ms)
	_stale.erase(b.key)
	# (in place of one a rider may be on, or with a rider on it or nearly: solid at once)
	var area := Rect2(Vector2(b.key) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(64.0)
	var solid_now := blocks.has(b.key) or (is_inside_tree() and riders().any(func(p): return area.has_point(p)))
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
			if part == "verge":
				mi.material_override = AdventureSurface.land_material()   # (grained as the land beside it is, as the planned road's verge)
			node.add_child(mi)
	var bridge: Dictionary = b.arrays.get("bridge", {})
	if not bridge.is_empty() and not (bridge["v"] as PackedVector3Array).is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Bridges"
		bmi.mesh = AdventureProps.to_mesh(bridge)
		bmi.material_override = AdventureChunk._bridge_material()
		node.add_child(bmi)
	var lines: Dictionary = b.arrays["lines"]
	if not (lines["v"] as PackedVector3Array).is_empty():
		var lmi := MeshInstance3D.new()
		lmi.name = "Lines"
		lmi.mesh = AdventureProps.to_mesh(lines)
		lmi.material_override = AdventureSurface.line_material()
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lmi)
	if b.arrays.has("buildings") and not (b.arrays["buildings"]["v"] as PackedVector3Array).is_empty():
		var tiles: Array = b.get_meta("building_tiles") if b.has_meta("building_tiles") else tile_soup(b.arrays["buildings"])
		for i in tiles.size():
			if (tiles[i]["v"] as PackedVector3Array).is_empty():
				continue
			var make := func() -> Node:
				var bmi := MeshInstance3D.new()
				bmi.name = "Buildings_%d" % i
				bmi.mesh = AdventureProps.to_mesh(tiles[i])
				bmi.material_override = WindowLights.material()   # (their windows lit after dark)
				return bmi
			# (a town's houses are made into meshes a square a frame, over the frames after: see StreamPieces)
			_put(node, make, at_once or solid_now)
	for l: Dictionary in b.arrays.get("labels", []):
		var label := Label3D.new()
		label.text = str(l["text"])
		label.font_size = int(l["font"])
		label.pixel_size = float(l["pixel"])
		label.modulate = l["col"]
		label.outline_size = 0
		label.double_sided = false
		label.transform = l["xf"]
		label.visibility_range_end = float(l["reach"])
		node.add_child(label)
	var tree_tiles: Dictionary = b.get_meta("tree_tiles") if b.has_meta("tree_tiles") else tile_lists(b.trees)
	for kind: String in tree_tiles:
		for i in TILES * TILES:
			var list: Array = tree_tiles[kind][i]
			if list.is_empty():
				continue
			var mmi := _multi(AdventureProps.mesh(kind), list, "Trees_%s_%d" % [kind, i])
			if kind in AdventureChunk.BUSHES:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# (a square's trees go as one: drawn while any of it is within reach)
			AdventureChunk._range(mmi, TREES_REACH)
			node.add_child(mmi)
	# The posts by the road (RoadBlock._roadside), and the fences' rails, walls and hedges: as the trees, drawn while
	# any of the square is within reach.
	var roadside_tiles: Dictionary = b.get_meta("roadside_tiles") if b.has_meta("roadside_tiles") else tile_lists(b.roadside)
	for kind: String in roadside_tiles:
		var mesh := RegionKit.post_mesh(kind.trim_prefix("kit_post_")) if kind.begins_with("kit_post_") else AdventureProps.mesh(kind)
		for i in TILES * TILES:
			var list: Array = roadside_tiles[kind][i]
			if list.is_empty():
				continue
			var mmi := _multi(mesh, list, "Roadside_%s_%d" % [kind, i])
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			AdventureChunk._range(mmi, TREES_REACH)
			node.add_child(mmi)
	var walls: Dictionary = b.arrays.get("walls", {})
	if not walls.is_empty() and not (walls["v"] as PackedVector3Array).is_empty():
		var wmi := MeshInstance3D.new()
		wmi.name = "Walls"
		wmi.mesh = AdventureProps.to_mesh(walls)
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		AdventureChunk._range(wmi, TREES_REACH)
		node.add_child(wmi)
	for s: Dictionary in b.arrays.get("signals", []):
		_put(node, _signals.bind(s), at_once or solid_now)
	# Its road solid a piece at a time over the next frames (see StreamPieces), unless it's in place of one a rider
	# may be on, or it's the start's (behind the fade).
	var shapes: Dictionary = b.get_meta("shapes", {})
	for surf: String in b.arrays["faces"]:
		var pieces: Array = shapes[surf] if shapes.has(surf) else \
			StreamPieces.shapes(StreamPieces.split(b.arrays["faces"][surf], RoadBlock.SIZE))
		for i in pieces.size():
			var body := StaticBody3D.new()
			body.name = "Body_%s_%d" % [surf, i]
			body.collision_layer = 1
			body.set_meta("surface", surf)
			var cs := CollisionShape3D.new()
			cs.shape = pieces[i]
			body.add_child(cs)
			if at_once or solid_now:
				node.add_child(body)
			else:
				_pieces.add(node, body)   # (made already: the shapes were made on the worker)
	blocks[b.key] = node
	_place(node)
	add_child(node)
	stats["commit_ms_max"] = maxf(float(stats["commit_ms_max"]), (Time.get_ticks_usec() - t0) / 1000.0)
	return node


## The traffic lights at a crossroads in town (RoadBlock._signals), as the planned road's are, from signals entry `s`.
static func _signals(s: Dictionary) -> Node:
	var sig := AdventureJunctions.Signals.new()
	sig.name = "Signals_%d" % int(s["node"])
	sig.site = {"green": s["green"], "phase": s["phase"]}
	var poles := AdventureProps.new_arrays()
	var sbody := StaticBody3D.new()
	sbody.collision_layer = 1
	for h: Array in s["heads"]:
		AdventureJunctions._head(sig, poles, sbody, h[0], str(h[1]))
	var pmi := MeshInstance3D.new()
	pmi.mesh = AdventureProps.to_mesh(poles)
	sig.add_child(pmi)
	sig.add_child(sbody)
	return sig


## Puts `make`'s node (made now or when its turn comes) into block `node`: `now`, or over the next frames (StreamPieces).
func _put(node: Node, make: Callable, now: bool) -> void:
	if now:
		node.add_child(make.call())
	else:
		_pieces.add(node, make)


## A MultiMeshInstance3D named `name` of `mesh` at each of `list`'s transforms.
static func _multi(mesh: Mesh, list: Array, name: String) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = list.size()
	for k in list.size():
		multi.set_instance_transform(k, list[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = multi
	return mmi


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
