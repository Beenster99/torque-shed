class_name SceneryStreamer
extends Node3D
## The things worth stopping for round each rider on the network ride (Ride Anywhere v2, phase D: interfaces/scenery.md):
## the region's features (RealRegion.features, from tools/feature_bake.py) placed by 512 m block as the road blocks are
## (RoadStreamer), each as its kind's model from the kit library (data/scenery_kits.json, by the place's regional kit).
## A block is laid out on a worker once the ground round it is final (RoadNet.ready), put in one a frame, freed once
## every rider is past KEEP, and laid out again where the ground sharpens.
##
## Scenery stands beside and above the road, never in it: nothing here changes a road, the land under one or what a
## bike can touch (no collision at all), and a thing the map puts on a carriageway or its verge is stood just off it
## (lay_out). Everything is instanced: one MultiMesh a block for each model, drawn while the camera is within its
## kind's reach.
##
## Round 0 has one model, "standin": a post at every point, coloured by the round that will model it, as the proof
## the pipeline works, drawn only while show_standins is on (Esc > Debug; the tests): an ordinary ride shows nothing
## until a round models a kind. A round adds its models to MODELS (or a script of its own under scripts/scenery/) and its kinds'
## rows to the kit library; the streaming, the filing and the rules stay here.

## Part of the builder hash (AdventureCrew.builds): bump it when what a block lays out changes.
const VERSION := 1
const KITS := "res://data/scenery_kits.json"
## Blocks whose middle is within REACH of a rider are wanted; kept until every rider is KEEP away (m).
const REACH := 2000.0
const KEEP := 2400.0
const MAX_TASKS := 1
## How far round a block the ground must be final before it's laid out (m), as the road blocks' (RoadStreamer).
const READY_PAD := 128.0
## A block with this many points or more keeps its own copy of the roads it asks after (lay_out).
const MEMO_FROM := 32
## How far past a road's verge a thing the map puts on the road is stood (m).
const CLEAR := 1.5
## The stand-in post's colour by the round that will model its kind (phase D plan).
const ROUND_COLOURS := {"D1": Color(0.95, 0.3, 0.2), "D2": Color(0.35, 0.35, 0.4), "D3": Color(0.2, 0.55, 0.95),
	"D4": Color(0.95, 0.95, 0.95), "D5": Color(0.4, 0.8, 0.25), "D6": Color(0.75, 0.55, 0.25),
	"D7": Color(0.1, 0.85, 0.85), "D8": Color(0.95, 0.85, 0.15), "D9": Color(0.75, 0.3, 0.8)}
## The models a kit row can name.
const MODELS := ["standin"]
## Whether the stand-in posts are drawn (Esc > Debug's scenery markers; off for an ordinary ride). It changes only what
## this machine draws: never a road, the land or the crew's hashes.
static var show_standins := false
## The stand-in post: this tall and this thick (m), with a cap to see it by.
const POST_H := 3.0
const POST_W := 0.25

var world: AdventureWorld
var net: RoadNet
var region: RealRegion
var blocks := {}         # Vector2i -> Node3D in the world
var stats := {"built": 0, "items": 0, "moved": 0, "skipped": 0, "build_ms_max": 0.0}
var _filed := {}         # Vector2i -> PackedInt32Array: the points in the block (indices into region.features.points)
var _tasks := {}         # Vector2i -> JobPool job id
var _done := {}          # Vector2i -> Dictionary (lay_out's), read under the lock
var _stale := {}
var _lock := Mutex.new()

static var _kits := {}
static var _kits_lock := Mutex.new()
static var _meshes := {}


func setup(w: AdventureWorld, n: RoadNet) -> void:
	name = "Scenery"
	world = w
	net = n
	region = n.region
	_filed = file_points(region.features.get("points", []))
	var terrain = w.route.real.terrain if w.route != null and w.route.real != null else null
	if terrain != null and terrain.has_signal("ground_arrived"):
		terrain.connect("ground_arrived", _on_ground_arrived)
	w.origin_shifted.connect(func(_d): place())


func _exit_tree() -> void:
	for k in _tasks:
		JobPool.drop(_tasks[k])
	_tasks.clear()


## The points of `points` (RealRegion.features' rows) filed by the road block they stand in.
static func file_points(points: Array) -> Dictionary:
	var out := {}
	for i in points.size():
		var row: Array = points[i]
		var k := RoadBlock.key_of(float(row[1]), float(row[2]))
		var list: PackedInt32Array = out.get(k, PackedInt32Array())
		list.append(i)
		out[k] = list   # (a packed array is a copy: put back)
	return out


# ---------------------------------------------------------------------------- the kit library

## The kit library's row for `kind` in regional kit `region_id` ("" for none): its default with that region's laid
## over it. {} for a kind the library hasn't got (nothing is placed for it).
static func kit(kind: String, region_id := "") -> Dictionary:
	var kinds: Dictionary = kits().get("kinds", {})
	var k: Dictionary = kinds.get(kind, {})
	if k.is_empty():
		return {}
	var out: Dictionary = (k.get("default", {}) as Dictionary).duplicate()
	out["round"] = str(k.get("round", ""))
	if region_id != "":
		out.merge(((k.get("regions", {}) as Dictionary).get(region_id, {}) as Dictionary), true)
	return out


## Whether any kind's kit names a model of its own (not the stand-in): until a round adds one, an ordinary ride has
## nothing to place.
static func models_beyond_standin() -> bool:
	for k: Dictionary in (kits().get("kinds", {}) as Dictionary).values():
		if str((k.get("default", {}) as Dictionary).get("model", "standin")) != "standin":
			return true
		for r: Dictionary in (k.get("regions", {}) as Dictionary).values():
			if str(r.get("model", "standin")) != "standin":
				return true
	return false


## The kit library as read (once).
static func kits() -> Dictionary:
	_kits_lock.lock()
	if _kits.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string(KITS)) if FileAccess.file_exists(KITS) else null
		_kits = v if v is Dictionary else {"kinds": {}}
	var out := _kits
	_kits_lock.unlock()
	return out


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds: {key, items: {"model|round": [Transform3D in the block's frame (its corner)]}, reach:
## {"model|round": m}, moved, skipped, ms}. Every point in it as its kind's model, stood on the land (RoadNet.ground_at),
## pushed off any carriageway and verge it's on (or left out where it can't be: inside a junction). Safe on a worker.
static func lay_out(n: RoadNet, filed: Dictionary, key: Vector2i) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var out := {"key": key, "items": {}, "reach": {}, "moved": 0, "skipped": 0}
	var points: Array = n.region.features.get("points", [])
	var o := Vector3(key.x * RoadBlock.SIZE, 0.0, key.y * RoadBlock.SIZE)
	var many: PackedInt32Array = filed.get(key, PackedInt32Array())
	# (a busy block keeps its own copy of the roads it asks after, out of the lock the other workers wait on: worth it
	# from a few dozen points, RoadNet.ground_at)
	var memo = {} if many.size() >= MEMO_FROM else null
	var kits_of := {}   # "kind|region" -> its kit row, looked up once a block
	for i in many:
		var row: Array = points[i]
		var kind := str(row[0])
		var region_id := str(RegionKit.at_frame(n.region.frame_lat, n.region.frame_lon, float(row[1]), float(row[2])).get("region", ""))
		var slot_key := kind + "|" + region_id
		if not kits_of.has(slot_key):
			kits_of[slot_key] = kit(kind, region_id)
		var k: Dictionary = kits_of[slot_key]
		var model := str(k.get("model", ""))
		if model not in MODELS or (model == "standin" and not show_standins):
			continue
		var p := off_road(n, Vector2(float(row[1]), float(row[2])))
		if is_nan(p.x):
			out["skipped"] += 1
			continue
		if p != Vector2(float(row[1]), float(row[2])):
			out["moved"] += 1
		var bare := float(n.height.call(p.x, p.y))
		if is_nan(bare):
			out["skipped"] += 1
			continue
		var y := n.ground_at(p.x, p.y, bare, memo) - 0.1
		var turn := deg_to_rad(float(row[5])) if row[5] != null else 0.0
		# (a heading is clockwise from north; a yaw about +y is anticlockwise from -z)
		var xf := Transform3D(Basis(Vector3.UP, -turn), Vector3(p.x, y, p.y) - o)
		var slot := "%s|%s" % [model, str(k.get("round", ""))]
		if not (out["items"] as Dictionary).has(slot):
			out["items"][slot] = []
			out["reach"][slot] = 0.0
		(out["items"][slot] as Array).append(xf)
		out["reach"][slot] = maxf(float(out["reach"][slot]), float(k.get("reach", 1500.0)))
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## Where a thing the map puts at `p` (region x, z) stands: there, or just past the verge of a road it's on (CLEAR
## out, the side it's on); NAN where it can't be stood clear of every road (inside a junction).
static func off_road(n: RoadNet, p: Vector2) -> Vector2:
	if n._near(p.x, p.y).is_empty():
		return p
	for _attempt in 2:
		var on := n.locate(p.x, p.y, -1, false)
		if on.is_empty():
			return p
		if int(on["node"]) >= 0:
			return Vector2(NAN, NAN)
		var clear := float(on["width"]) * 0.5 + RoadNet.VERGE + CLEAR
		var lat := float(on["lat"])
		if absf(lat) >= clear:
			return p
		var e := int(on["edge"])
		var s := float(on["s"])
		var c := n.point_at(e, s)
		var along := n.point_at(e, minf(s + 1.0, n.length_of(e))) - n.point_at(e, maxf(s - 1.0, 0.0))
		if along.length() < 1e-4:
			return Vector2(NAN, NAN)
		var right := Vector2(-along.y, along.x).normalized()
		p = c + right * (clear + 0.05) * (1.0 if lat >= 0.0 else -1.0)
	var last := n.locate(p.x, p.y, -1, false)
	if not last.is_empty() and (int(last["node"]) >= 0 or absf(float(last["lat"])) < float(last["width"]) * 0.5 + RoadNet.VERGE):
		return Vector2(NAN, NAN)
	return p


# ---------------------------------------------------------------------------- streaming

## The region-frame (x, z) of each rider.
func riders() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var spots: Array = world.focus.call() if world.focus.is_valid() else []
	for p: Vector3 in spots:
		out.append(Vector2(p.x + world.origin.x, p.z + world.origin.z))
	return out


## Whether block `k`'s ground is final, to stand things on.
func can_build(k: Vector2i) -> bool:
	var area := Rect2(Vector2(k) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(READY_PAD)
	if net.ready.is_valid():
		return bool(net.ready.call(area))
	var c := (Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
	return not is_nan(float(net.height.call(c.x, c.y)))


func _process(_delta: float) -> void:
	if net == null or _filed.is_empty() or not (show_standins or models_beyond_standin()):
		return
	stream(riders())


## One frame's streaming round riders `at`: frees the blocks every rider is past, puts one laid out block in, and starts
## laying out the next wanted one (only blocks that have something in them).
func stream(at: Array[Vector2]) -> void:
	if at.is_empty():
		return
	for k: Vector2i in blocks.keys():
		var c := (Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
		if at.all(func(p): return c.distance_to(p) > KEEP):
			blocks[k].queue_free()
			blocks.erase(k)
	var want := RoadStreamer.wanted(at, REACH).filter(func(k): return _filed.has(k))
	var ready_one: Dictionary = {}
	_lock.lock()
	for k in _done.keys():
		if JobPool.done(_tasks[k]):
			JobPool.wait(_tasks[k])
			_tasks.erase(k)
			if ready_one.is_empty() and want.has(k):
				ready_one = _done[k]
				_done.erase(k)
			elif not want.has(k):
				_done.erase(k)
	_lock.unlock()
	if not ready_one.is_empty():
		commit(ready_one)
	for k in want:
		if _tasks.size() >= MAX_TASKS:
			break
		if (blocks.has(k) and not _stale.has(k)) or _tasks.has(k) or _done.has(k) or not can_build(k):
			continue
		_stale.erase(k)
		# (ranked with the road blocks by distance: a block of scenery is a fraction of a millisecond)
		_tasks[k] = JobPool.add(_work.bind(k), ((Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE).distance_to(at[0]))


func _work(k: Vector2i) -> void:
	var b := lay_out(net, _filed, k)
	_lock.lock()
	_done[k] = b
	_lock.unlock()


func _on_ground_arrived(area: Rect2, _level := 0) -> void:
	for k: Vector2i in blocks.keys():
		if Rect2(Vector2(k) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(READY_PAD).intersects(area):
			_stale[k] = true


## Puts laid out block `b` (lay_out's) into the world, in place of the one there before.
func commit(b: Dictionary) -> Node3D:
	var key: Vector2i = b["key"]
	stats["built"] += 1
	stats["moved"] += int(b["moved"])
	stats["skipped"] += int(b["skipped"])
	stats["build_ms_max"] = maxf(float(stats["build_ms_max"]), float(b["ms"]))
	if blocks.has(key):
		blocks[key].queue_free()
	var node := Node3D.new()
	node.name = "Scenery_%d_%d" % [key.x, key.y]
	node.set_meta("key", key)
	for slot: String in b["items"]:
		var list: Array = b["items"][slot]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = model_mesh(slot.get_slice("|", 0), slot.get_slice("|", 1))
		multi.instance_count = list.size()
		for i in list.size():
			multi.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = slot.replace("|", "_")
		mmi.multimesh = multi
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		AdventureChunk._range(mmi, float(b["reach"][slot]))
		node.add_child(mmi)
		stats["items"] += list.size()
	blocks[key] = node
	_place(node)
	add_child(node)
	return node


## The mesh of `model` for a kind of round `round` (the stand-in's colour is its round's).
static func model_mesh(model: String, round: String) -> Mesh:
	var key := "%s|%s" % [model, round]
	if _meshes.has(key):
		return _meshes[key]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(POST_W, POST_H, POST_W)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROUND_COLOURS.get(round, Color(0.9, 0.9, 0.9))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.35
	mesh.material = mat
	# (the box stood on the ground: its middle half its height up)
	var arrays := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += POST_H * 0.5
	arrays[Mesh.ARRAY_VERTEX] = v
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mat)
	_meshes[key] = out
	return out


## Puts every block at its corner in the world's local frame (after the origin moves).
func place() -> void:
	for k in blocks:
		_place(blocks[k])


func _place(node: Node3D) -> void:
	var k: Vector2i = node.get_meta("key")
	node.position = Vector3(k.x * RoadBlock.SIZE - world.origin.x, 0.0, k.y * RoadBlock.SIZE - world.origin.z)
