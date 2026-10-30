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
## A kind's model is a kit row's "model", "SCRIPT:MODEL": res://scripts/scenery/SCRIPT.gd, a round's own script of
## static functions the streamer calls (docs/scenery.md):
##   lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary   on a worker: rows is {points, lines, areas},
##       each [[feature row, kit], ...] of the rows in the block whose kit names the script; returns {items: {MODEL:
##       [Transform3D in the block's frame (its corner)]}, dress (optional, anything), moved, skipped (optional counts)}
##   mesh(model: String) -> Mesh                                            the mesh each of MODEL's MultiMeshes draws
##   dress(node: Node3D, data) -> void                                      optional, on the main thread once the block
##       is in: what isn't instanced (wires, lamps, moving parts)
## so a round adds its script and its kit rows and never edits this file. Round 0's model is "standin:post"
## (scripts/scenery/standin.gd): a post at every point, coloured by the round that will model it, drawn only while
## show_standins is on (Esc > Debug; the tests): an ordinary ride shows nothing until a round models a kind.

## Part of the builder hash (AdventureCrew.builds): bump it when what a block lays out changes.
const VERSION := 1
const KITS := "res://data/scenery_kits.json"
const SCRIPTS := "res://scripts/scenery/%s.gd"
## Blocks whose middle is within REACH of a rider are wanted; kept until every rider is KEEP away (m).
const REACH := 2000.0
const KEEP := 2400.0
## A block holding a kind whose kit reach is past REACH (a wind farm, a pylon line, a mast) is wanted out to that reach
## (FAR_MOST at most), laid out on whatever ground is known there (unknown ground counts as sea level for a kit with
## "sea": true, else it's left out) and laid out again once it's within REACH and its ground is final. Both scale with
## Settings.gfx_draw_distance, as the roads' do.
const FAR_MOST := 8000.0
const MAX_TASKS := 1
## How far a rider moves before the wanted blocks are picked again (m).
const MOVE_AGAIN := 24.0
## How often the wanted blocks are gone over for one to lay out while none needs it (ms).
const SCAN_MS := 250
## How far round a block the ground must be final before it's laid out (m), as the road blocks' (RoadStreamer).
const READY_PAD := 128.0
## How far past a road's verge a thing the map puts on the road is stood (m).
const CLEAR := 1.5
## A line or area is filed in at most this many blocks a side of its box (a power line across a whole cell is in
## every block it crosses; a country's border only where it is near).
const FILE_MOST := 64
## Whether the stand-ins are drawn (Esc > Debug's scenery markers; off for an ordinary ride). It changes only what this
## machine draws: never a road, the land or the crew's hashes.
static var show_standins := false

var world: AdventureWorld
var net: RoadNet
var region: RealRegion
var blocks := {}         # Vector2i -> Node3D in the world
var stats := {"built": 0, "items": 0, "moved": 0, "skipped": 0, "build_ms_max": 0.0}
var _filed := {}         # Vector2i -> {points, lines, areas: PackedInt32Array}: what is in the block (file_features)
var _far := {}           # Vector2i -> m: the blocks holding a kind whose reach is past REACH, and the farthest
var _coarse := {}        # Vector2i -> true: blocks laid out before their ground was final (laid out again once it is)
var _tasks := {}         # Vector2i -> JobPool job id
var _want: Array = []    # the blocks wanted (nearest first) and which of them are near, as _choose last picked them
var _want_near := {}
var _want_at: Array[Vector2] = []   # where the riders were then, and the draw distance
var _want_scale := 0.0
var _scan_at := 0        # (msec) when the wanted blocks are next gone over for one to start laying out
var _done := {}          # Vector2i -> Dictionary (lay_out's), read under the lock
var _stale := {}
var _lock := Mutex.new()

static var _kits := {}
static var _kits_lock := Mutex.new()
static var _meshes := {}
static var _scripts := {}   # SCRIPT -> its Script (loaded once: load_scripts)


func setup(w: AdventureWorld, n: RoadNet) -> void:
	name = "Scenery"
	world = w
	net = n
	region = n.region
	load_scripts()
	_filed = file_features(region.features)
	_far = far_blocks(region.features, _filed)
	var terrain = w.route.real.terrain if w.route != null and w.route.real != null else null
	if terrain != null and terrain.has_signal("ground_arrived"):
		terrain.connect("ground_arrived", _on_ground_arrived)
	w.origin_shifted.connect(func(_d): place())


func _exit_tree() -> void:
	for k in _tasks:
		JobPool.drop(_tasks[k])
	_tasks.clear()


## What of `features` (RealRegion.features) is in each road block: {key: {"points", "lines", "areas":
## PackedInt32Array of indices}}. A point is in the block it stands in; a line or an area in every block its points'
## box touches (FILE_MOST a side at most), each model placing only what is in its block (in_block).
static func file_features(features: Dictionary) -> Dictionary:
	var out := {}
	var points: Array = features.get("points", [])
	for i in points.size():
		var row: Array = points[i]
		_file(out, RoadBlock.key_of(float(row[1]), float(row[2])), "points", i)
	for part: String in ["lines", "areas"]:
		var rows: Array = features.get(part, [])
		for i in rows.size():
			var pts: PackedVector2Array = rows[i][1]
			if pts.is_empty():
				continue
			var box := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				box = box.expand(p)
			var k0 := RoadBlock.key_of(box.position.x, box.position.y)
			var k1 := RoadBlock.key_of(box.end.x, box.end.y)
			if k1.x - k0.x > FILE_MOST or k1.y - k0.y > FILE_MOST:
				k0 = Vector2i(k0.x, k0.y)
				k1 = Vector2i(mini(k1.x, k0.x + FILE_MOST), mini(k1.y, k0.y + FILE_MOST))
			for bz in range(k0.y, k1.y + 1):
				for bx in range(k0.x, k1.x + 1):
					_file(out, Vector2i(bx, bz), part, i)
	return out


static func _file(out: Dictionary, k: Vector2i, part: String, i: int) -> void:
	if not out.has(k):
		out[k] = {"points": PackedInt32Array(), "lines": PackedInt32Array(), "areas": PackedInt32Array()}
	var list: PackedInt32Array = out[k][part]
	list.append(i)
	out[k][part] = list   # (a packed array is a copy: put back)


## The blocks of `filed` (file_features') holding a kind whose kit reach (in its default or any region's row) is past
## REACH: {key: the farthest such reach, FAR_MOST at most}.
static func far_blocks(features: Dictionary, filed: Dictionary) -> Dictionary:
	var by_kind := {}
	for kind: String in (kits().get("kinds", {}) as Dictionary):
		var r := kind_reach(kind)
		if r > REACH:
			by_kind[kind] = minf(r, FAR_MOST)
	var out := {}
	if by_kind.is_empty():
		return out
	for k: Vector2i in filed:
		for part: String in ["points", "lines", "areas"]:
			var rows: Array = features.get(part, [])
			for i in (filed[k] as Dictionary).get(part, PackedInt32Array()):
				var m := float(by_kind.get(str(rows[i][0]), 0.0))
				if m > float(out.get(k, 0.0)):
					out[k] = m
	return out


## The farthest reach `kind` is drawn to in any region (m).
static func kind_reach(kind: String) -> float:
	var k: Dictionary = (kits().get("kinds", {}) as Dictionary).get(kind, {})
	var out := float((k.get("default", {}) as Dictionary).get("reach", 0.0))
	for r: Dictionary in (k.get("regions", {}) as Dictionary).values():
		out = maxf(out, float(r.get("reach", out)))
	return out


## Whether region-frame point `p` is in block `key` (a model places a line's or area's things only in their own block).
static func in_block(key: Vector2i, p: Vector2) -> bool:
	return RoadBlock.key_of(p.x, p.y) == key


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
	for m in models():
		if not m.begins_with("standin:"):
			return true
	return false


## Every model the kit library names ("SCRIPT:MODEL"), in its default or any region's row.
static func models() -> Array[String]:
	var out: Array[String] = []
	for k: Dictionary in (kits().get("kinds", {}) as Dictionary).values():
		var rows: Array = [k.get("default", {})] + (k.get("regions", {}) as Dictionary).values()
		for r: Dictionary in rows:
			var m := str(r.get("model", ""))
			if m != "" and not out.has(m):
				out.append(m)
	return out


## Loads the scripts the kit library's models name (once, on the main thread, before any block is laid out).
static func load_scripts() -> void:
	for m in models():
		script_of(m)


## Each model script's own VERSION (0 for one without), "SCRIPT:VERSION,..." in name order: part of the builder hash
## (AdventureCrew.builds), so a round bumps its script's VERSION when its lay_out changes what a block holds.
static func script_versions() -> String:
	var names := {}
	for m in models():
		names[m.get_slice(":", 0)] = true
	var out := PackedStringArray()
	for n: String in names.keys():
		var s := script_of(n + ":")
		var v = s.get_script_constant_map().get("VERSION", 0) if s != null else -1
		out.append("%s:%s" % [n, str(v)])
	out.sort()
	return ",".join(out)


## The script of model "SCRIPT:MODEL" (loaded the first time), or null when there's no such script.
static func script_of(model: String) -> Script:
	var name := model.get_slice(":", 0)
	_kits_lock.lock()
	var have = _scripts.get(name)
	if have == null and not _scripts.has(name):
		var path := SCRIPTS % name
		have = load(path) if ResourceLoader.exists(path) else null
		if have == null:
			push_warning("Scenery: no model script %s (kit model %s)" % [path, model])
		_scripts[name] = have
	_kits_lock.unlock()
	return have


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

## What block `key` holds: {key, items: {"SCRIPT:MODEL": [Transform3D in the block's frame (its corner)]}, reach:
## {"SCRIPT:MODEL": m (the farthest of its rows' kits)}, dress: {SCRIPT: its lay_out's dress}, moved, skipped, ms}. Each
## row in the block goes to the script its kit's model names (the stand-ins only while show_standins is on). Safe on a
## worker.
static func lay_out(n: RoadNet, filed: Dictionary, key: Vector2i) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var out := {"key": key, "items": {}, "reach": {}, "dress": {}, "moved": 0, "skipped": 0}
	var here: Dictionary = filed.get(key, {})
	var by_script := {}   # SCRIPT -> {points, lines, areas: [[row, kit], ...]}
	var reach := {}       # "SCRIPT:MODEL" -> m
	var kits_of := {}     # "kind|region" -> its kit row, looked up once a block
	for part: String in ["points", "lines", "areas"]:
		var rows: Array = n.region.features.get(part, [])
		for i in here.get(part, PackedInt32Array()):
			var row: Array = rows[i]
			var at: Vector2 = Vector2(float(row[1]), float(row[2])) if part == "points" else (row[1] as PackedVector2Array)[0]
			var region_id := str(RegionKit.at_frame(n.region.frame_lat, n.region.frame_lon, at.x, at.y).get("region", ""))
			var kk := str(row[0]) + "|" + region_id
			if not kits_of.has(kk):
				kits_of[kk] = kit(str(row[0]), region_id)
			var k: Dictionary = kits_of[kk]
			var model := str(k.get("model", ""))
			if model == "" or (model.begins_with("standin:") and not show_standins):
				continue
			var script := model.get_slice(":", 0)
			if not by_script.has(script):
				by_script[script] = {"points": [], "lines": [], "areas": []}
			(by_script[script][part] as Array).append([row, k])
			reach[model] = maxf(float(reach.get(model, 0.0)), float(k.get("reach", 1500.0)))
	for script: String in by_script:
		var s := script_of(script + ":")
		if s == null:
			continue
		var got: Dictionary = s.call("lay_out", n, key, by_script[script])
		var farthest := 0.0   # (a model the script names that no kit row does is drawn to its rows' farthest reach)
		for m: String in reach:
			if m.begins_with(script + ":"):
				farthest = maxf(farthest, float(reach[m]))
		for m: String in got.get("items", {}):
			var full := script + ":" + m
			out["items"][full] = got["items"][m]
			out["reach"][full] = float(reach.get(full, farthest))
		if got.has("dress"):
			out["dress"][script] = got["dress"]
		out["moved"] += int(got.get("moved", 0))
		out["skipped"] += int(got.get("skipped", 0))
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## Where a thing the map puts at `p` (region x, z) stands on the land, off any road (off_road), in the region frame: y
## just under the land's (RoadNet.ground_at, `memo` a block's own: pass {} once a block). NAN where it can't stand
## (inside a junction, or no ground known there yet: at sea level instead when `sea`, for a thing that may stand
## offshore or far off, as a kit's "sea" says).
static func stand(n: RoadNet, p: Vector2, memo = null, sea := false) -> Vector3:
	var q := off_road(n, p)
	if is_nan(q.x):
		return Vector3(NAN, NAN, NAN)
	var bare := float(n.height.call(q.x, q.y))
	if is_nan(bare):
		return Vector3(q.x, 0.0, q.y) if sea else Vector3(NAN, NAN, NAN)
	return Vector3(q.x, n.ground_at(q.x, q.y, bare, memo) - 0.1, q.y)


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
	var pt := Perf.t0()
	_process_body(_delta)
	Perf.add("scenery_stream", pt)


func _process_body(_delta: float) -> void:
	if net == null or _filed.is_empty() or not (show_standins or models_beyond_standin()):
		return
	stream(riders())


## One frame's streaming round riders `at`: frees the blocks every rider is past, puts one laid out block in, and starts
## laying out the next wanted one (only blocks that have something in them).
func stream(at: Array[Vector2]) -> void:
	if at.is_empty():
		return
	# Which blocks are wanted is worked out again once a rider has moved MOVE_AGAIN on (or the draw distance changed):
	# going over every far block each frame was a millisecond and a half a frame.
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	if _want_at.size() != at.size() or scale != _want_scale or range(at.size()).any(func(i): return at[i].distance_to(_want_at[i]) > MOVE_AGAIN):
		_want_at = at.duplicate()
		_want_scale = scale
		_choose(at, scale)
		_scan_at = 0
	var want := _want
	var near := _want_near
	var now := Time.get_ticks_msec()
	var ready_one: Dictionary = {}
	_lock.lock()
	for k in _done.keys():
		if JobPool.done(_tasks[k]):
			JobPool.wait(_tasks[k])
			_tasks.erase(k)
			_scan_at = 0
			if ready_one.is_empty() and want.has(k):
				ready_one = _done[k]
				_done.erase(k)
			elif not want.has(k):
				_done.erase(k)
	_lock.unlock()
	if not ready_one.is_empty():
		commit(ready_one)
	# (gone over when a worker's free, and then only every SCAN_MS while there's nothing to start)
	if _tasks.size() >= MAX_TASKS or now < _scan_at:
		return
	_scan_at = now + SCAN_MS
	for k in want:
		if _tasks.size() >= MAX_TASKS:
			_scan_at = 0
			break
		var coarse := not near.has(k) or not can_build(k)
		if coarse and not _far.has(k):
			continue
		var redo := _stale.has(k) or (_coarse.has(k) and not coarse)
		if (blocks.has(k) and not redo) or _tasks.has(k) or _done.has(k):
			continue
		_stale.erase(k)
		if coarse:
			_coarse[k] = true
		else:
			_coarse.erase(k)
		# (ranked with the road blocks by distance: a block of scenery is a fraction of a millisecond)
		_tasks[k] = JobPool.add(_work.bind(k), ((Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE).distance_to(at[0]))


## Frees the blocks every rider is past, and picks the blocks wanted round riders `at` (_want, nearest first, and which
## of them are near: _want_near).
func _choose(at: Array[Vector2], scale: float) -> void:
	for k: Vector2i in blocks.keys():
		var c := (Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
		var keep := maxf(KEEP, (float(_far.get(k, 0.0)) * scale) + KEEP - REACH)
		if at.all(func(p): return c.distance_to(p) > keep):
			blocks[k].queue_free()
			blocks.erase(k)
			_coarse.erase(k)
	var want := RoadStreamer.wanted(at, REACH).filter(func(k): return _filed.has(k))
	var near := {}
	for k in want:
		near[k] = true
	for k: Vector2i in _far:
		if near.has(k):
			continue
		var c := (Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
		var r := float(_far[k]) * scale
		if at.any(func(p): return c.distance_to(p) <= r):
			want.append(k)
	_want = want
	_want_near = near


func _work(k: Vector2i) -> void:
	var b := lay_out(net, _filed, k)
	_lock.lock()
	_done[k] = b
	_lock.unlock()


func _on_ground_arrived(area: Rect2, _level := 0) -> void:
	_scan_at = 0
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
		multi.mesh = model_mesh(slot)
		multi.instance_count = list.size()
		for i in list.size():
			multi.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = slot.replace(":", "_")
		mmi.multimesh = multi
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		AdventureChunk._range(mmi, float(b["reach"][slot]) * clampf(Settings.gfx_draw_distance, 0.5, 2.0))
		node.add_child(mmi)
		stats["items"] += list.size()
	blocks[key] = node
	_place(node)
	add_child(node)
	for script: String in b.get("dress", {}):
		var s := script_of(script + ":")
		if s != null and s.has_method("dress"):
			s.call("dress", node, b["dress"][script])
	return node


## The mesh model "SCRIPT:MODEL" is drawn with (its script's mesh, made once).
static func model_mesh(model: String) -> Mesh:
	_kits_lock.lock()
	var have = _meshes.get(model)
	_kits_lock.unlock()
	if have != null:
		return have
	var s := script_of(model)
	var mesh: Mesh = s.call("mesh", model.substr(model.find(":") + 1)) if s != null else null
	if mesh == null:
		mesh = BoxMesh.new()
	_kits_lock.lock()
	_meshes[model] = mesh
	_kits_lock.unlock()
	return mesh


## Puts every block at its corner in the world's local frame (after the origin moves).
func place() -> void:
	for k in blocks:
		_place(blocks[k])


func _place(node: Node3D) -> void:
	var k: Vector2i = node.get_meta("key")
	node.position = Vector3(k.x * RoadBlock.SIZE - world.origin.x, 0.0, k.y * RoadBlock.SIZE - world.origin.z)
