class_name AdventureWorld
extends Node3D
## The world of an adventure ride: the route (AdventureRoute, the same on every player's game
## from its seed), streamed in as chunks (AdventureChunk) a few kilometres ahead of you and
## freed behind, built on worker threads and put into the scene one chunk a frame so riding
## never hitches.
##
## Floating origin: the route runs for a hundred kilometres and more, far past where single
## precision floats stay steady, so the world is drawn in a local frame that's moved along as
## you ride. A point of the route frame (doubles, see AdventureRoute) sits at local position
## route - origin; once you're SHIFT_DIST from ANCHOR the origin jumps to keep you near it
## (by whole multiples of SHIFT_SNAP, so the origin is always an exact whole number) and
## origin_shifted tells everyone else to move what they hold by the same amount (the bike, the
## camera, other players: see AdventureTrip). ANCHOR is well off the town's map, so nothing that
## asks "am I in the shed?" by position ever thinks you are while out on the road.
##
## Players' network positions are sent in their own local frame with their origin alongside
## (tag_state); each receiver puts them into its own frame (untag_state), exact to the millimetre
## however far apart the two origins are.

## The local frame's centre: the focus is kept within SHIFT_DIST of it.
const ANCHOR := Vector3(0.0, 0.0, -6000.0)
const SHIFT_DIST := 600.0
const SHIFT_SNAP := 256.0
## The road is kept this far ahead of you and behind (m); behind, also back to anyone within
## REMOTE_BEHIND of you, so a friend a little way back isn't riding on nothing.
const AHEAD := 3200.0
const BEHIND := 600.0
const REMOTE_BEHIND := 1500.0
const MAX_TASKS := 2
const COMMITS_PER_FRAME := 1
## Marks a network snapshot carrying its sender's origin (see tag_state).
const NET_TAG := -77777.0

## Emitted after the origin moves: everything placed in the local frame moves by -delta.
signal origin_shifted(delta: Vector3)

static var current: AdventureWorld

var route: AdventureRoute
## The route frame point at the local frame's zero (whole metres, y always 0): local = route - origin.
var origin := Vector3.ZERO
## chunk index -> its node.
var chunks := {}
## Returns the local positions to keep the road round: [0] yours, then everyone else's.
var focus := Callable()
## kind -> Callable(site, xf, info) -> Node3D: what's built at a site (see AdventureRoute.add_site).
var site_builders := {}
## Off, chunks are built on the main thread instead (one a frame).
var threaded := true
## Timings for the profiler's report (ms): planning, building a chunk (on its thread),
## committing one (main thread), an origin shift (main thread), and the worst frame's streaming.
var stats := {"plan_ms": 0.0, "built": 0, "build_ms_total": 0.0, "build_ms_max": 0.0, "commit_ms_total": 0.0,
	"commit_ms_max": 0.0, "commits": 0, "shift_ms_max": 0.0, "shifts": 0, "stream_ms_max": 0.0, "freed": 0}
var horizon: MeshInstance3D
var _box := _Results.new()
var _tasks := {}         # chunk -> WorkerThreadPool task id
var _ready_data := {}    # chunk -> built data waiting to be committed
var _hints := {}         # who -> the knot they were last found near
var _own_s := 0.0


## What the worker threads hand back, guarded by its mutex (not the node, which may go first).
class _Results extends RefCounted:
	var mutex := Mutex.new()
	var done := {}


func _ready() -> void:
	current = self
	process_physics_priority = -100   # shift before the bike's physics in the same tick


func _exit_tree() -> void:
	for c in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[c])
	_tasks.clear()
	if current == self:
		current = null


## Plans the route for `seed` and `km` and puts its start at ANCHOR.
func setup(seed: int, km: float, theme := "varied") -> void:
	name = "Adventure"
	var t0 := Time.get_ticks_usec()
	route = AdventureRoute.new()
	route.plan(seed, km, theme)
	stats["plan_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	origin = -ANCHOR
	site_builders = {
		"fuel": func(site, xf, _info): return AdventureProps.fuel_station(site, xf, route.surface_at_s(float(site["s"]))),
		"start": func(_site, xf, info): return AdventureProps.banner("START", xf, float(info["width"]), Color(0.1, 0.35, 0.7)),
		"finish": func(_site, xf, info): return AdventureProps.banner("DESTINATION", xf, float(info["width"]), Color(0.75, 0.2, 0.1)),
	}
	_make_horizon()


# ---------------------------------------------------------------------------- frames

## The local position of route-frame (x, y, z).
func to_local_pos(rx: float, ry: float, rz: float) -> Vector3:
	return Vector3(rx - origin.x, ry, rz - origin.z)


## The route frame's x and z of local `p`, as doubles.
func route_xz(p: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([float(p.x) + float(origin.x), float(p.z) + float(origin.z)])


## Where local `p` is along the road: {i, s, lat, d} (see AdventureRoute.locate). `who` keeps a
## hint for the next search, so following someone along is cheap.
func locate_local(p: Vector3, who := "") -> Dictionary:
	var xz := route_xz(p)
	var hit := route.locate(xz[0], xz[1], int(_hints.get(who, -1)) if who != "" else -1)
	if who != "" and not hit.is_empty():
		_hints[who] = int(hit["i"])
	return hit


## How far along the road local `p` is (m), or -1 off it.
func distance_of(p: Vector3, who := "") -> float:
	var hit := locate_local(p, who)
	return float(hit["s"]) if not hit.is_empty() else -1.0


## A local transform on the road `s` metres along and `lat` to the right of the centre line,
## facing along it, on the road's surface.
func transform_at(s: float, lat := 0.0) -> Transform3D:
	var xz := route.xz_at(s, lat)
	var h := route.heading_at_s(s)
	var e := route.width_at_s(s) * 0.5
	var f := clampf(lat / maxf(e, 0.1), -1.0, 1.0)
	var y := route.height_at_s(s) + AdventureChunk.CROWN * (1.0 - f * f)
	return Transform3D(Basis(Vector3.UP, -h), to_local_pos(xz[0], y, xz[1]))


## The heading Bike.place wants for facing along the road at `s`.
func heading_at(s: float) -> float:
	return -route.heading_at_s(s)


## Where player `slot` starts: two by two on the left half of the road behind the start banner.
func start_xf(slot: int) -> Transform3D:
	var s := 36.0 - 5.0 * float(slot / 2)
	var w := route.width_at_s(maxf(s, 0.0))
	var lat := -w * 0.25 + (0.7 if slot % 2 == 1 else -0.7)
	return transform_at(maxf(s, 2.0), lat)


## The surface at local `p`: the road's, or the land's beside it (see AdventureSurface).
func surface_local(p: Vector3) -> String:
	var hit := locate_local(p, "surface")
	if hit.is_empty():
		return "grass"
	var s: float = hit["s"]
	var surf := route.surface_at_s(s)
	if absf(float(hit["lat"])) <= route.width_at_s(s) * 0.5 + 0.1:
		return surf
	for st in route.sites_of("fuel"):
		if absf(float(st["s"]) - s) < 22.0 and signf(float(hit["lat"])) == float(st["side"]) and absf(float(hit["lat"])) < route.width_at_s(s) * 0.5 + 24.0:
			return "tarmac"
	return str(AdventureSurface.LAND.get(surf, "grass"))


## The surface under `pos` in the current adventure, or "tarmac" when there's none (the town's
## own roads carry their surface on their collision, as before).
static func surface_at(pos: Vector3) -> String:
	if current == null or current.route == null:
		return "tarmac"
	return current.surface_local(pos)


# ---------------------------------------------------------------------------- floating origin

func _physics_process(_delta: float) -> void:
	if route == null or not focus.is_valid():
		return
	var spots: Array = focus.call()
	if spots.is_empty():
		return
	var p: Vector3 = spots[0]
	if Vector2(p.x - ANCHOR.x, p.z - ANCHOR.z).length() > SHIFT_DIST:
		shift_origin_to(p)


## Moves the origin so local `p` ends up near ANCHOR: the chunks move, then origin_shifted moves
## the rest. Returns the shift (what was at local q is now at q - delta).
func shift_origin_to(p: Vector3) -> Vector3:
	var t0 := Time.get_ticks_usec()
	var xz := route_xz(p)
	var new_origin := Vector3(snappedf(xz[0], SHIFT_SNAP) - ANCHOR.x, 0.0, snappedf(xz[1], SHIFT_SNAP) - ANCHOR.z)
	var delta := new_origin - origin
	if delta == Vector3.ZERO:
		return delta
	origin = new_origin
	for c in chunks:
		place_chunk(chunks[c])
	_follow_horizon(p - delta)
	origin_shifted.emit(delta)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["shifts"] += 1
	stats["shift_ms_max"] = maxf(float(stats["shift_ms_max"]), ms)
	return delta


## Puts a chunk's node at its anchor in the local frame (and into the world if it isn't yet).
func place_chunk(node: Node3D) -> void:
	node.position = Vector3(float(node.get_meta("ax")) - origin.x, 0.0, float(node.get_meta("az")) - origin.z)
	if node.get_parent() == null:
		add_child(node)
	chunks[int(node.get_meta("c"))] = node


## A network snapshot with our origin on the end, for the receiver to put into its own frame.
func tag_state(state: PackedFloat32Array) -> PackedFloat32Array:
	var out := state.duplicate()
	out.append_array([origin.x, origin.z, NET_TAG])
	return out


## Takes the origin off the end of a tagged snapshot and moves its position into our frame (a
## walker's [0, x, y, z, ...] or a rider's [1, bike, x, y, z, ...]). Untagged ones come back as
## they are.
func untag_state(state: PackedFloat32Array) -> PackedFloat32Array:
	return untag(state, origin)


static func untag(state: PackedFloat32Array, mine: Vector3) -> PackedFloat32Array:
	if state.size() < 4 or state[state.size() - 1] != NET_TAG:
		return state
	var ox := state[state.size() - 3]
	var oz := state[state.size() - 2]
	var out := state.slice(0, state.size() - 3)
	var at := -1
	if out.size() >= 4 and out[0] < 0.5:
		at = 1
	elif out.size() >= 5 and out[0] < 1.5:
		at = 2
	if at > 0:
		# Both origins are whole numbers, so their difference is exact; the positions are small.
		out[at] = float(out[at]) + (float(ox) - float(mine.x))
		out[at + 2] = float(out[at + 2]) + (float(oz) - float(mine.z))
	return out


# ---------------------------------------------------------------------------- streaming

func _process(_delta: float) -> void:
	if route == null:
		return
	var pt := Perf.t0()
	var t0 := Time.get_ticks_usec()
	stream()
	stats["stream_ms_max"] = maxf(float(stats["stream_ms_max"]), (Time.get_ticks_usec() - t0) / 1000.0)
	Perf.add("adventure_stream", pt)


## The chunks wanted now, nearest first (ahead before behind at the same distance).
func wanted_chunks() -> Array:
	var spots: Array = focus.call() if focus.is_valid() else []
	if spots.is_empty():
		return []
	var own := distance_of(spots[0], "own")
	if own < 0.0:
		own = _own_s
	_own_s = own
	var lo := own - BEHIND
	for k in range(1, spots.size()):
		var s := distance_of(spots[k], "remote_%d" % k)
		if s >= 0.0 and s < own and s > own - REMOTE_BEHIND:
			lo = minf(lo, s - BEHIND * 0.5)
	var c_lo := maxi(0, AdventureRoute.chunk_of(lo))
	var c_hi := mini(route.chunk_count() - 1, AdventureRoute.chunk_of(own + AHEAD))
	var c_own := AdventureRoute.chunk_of(own)
	var out := []
	for c in range(c_lo, c_hi + 1):
		out.append(c)
	out.sort_custom(func(a, b): return _priority(a, c_own) < _priority(b, c_own))
	return out


static func _priority(c: int, c_own: int) -> float:
	return float(c - c_own) if c >= c_own else float(c_own - c) * 1.5


## One frame's streaming: frees chunks no longer wanted, commits a finished one, and starts
## building the next wanted ones on worker threads.
func stream() -> void:
	var want := wanted_chunks()
	if want.is_empty():
		return
	var keep := {}
	for c in want:
		keep[c] = true
	for c in chunks.keys():
		if not keep.has(c) and not keep.has(c - 1) and not keep.has(c + 1):
			chunks[c].queue_free()
			chunks.erase(c)
			stats["freed"] += 1
	_box.mutex.lock()
	var finished := _box.done.duplicate()
	_box.done.clear()
	_box.mutex.unlock()
	for c in finished:
		if _tasks.has(c):
			WorkerThreadPool.wait_for_task_completion(_tasks[c])
			_tasks.erase(c)
		_note_build(finished[c])
		if keep.has(c):
			_ready_data[c] = finished[c]
	for c in _ready_data.keys():
		if not keep.has(c):
			_ready_data.erase(c)
	var commits := 0
	for c in want:
		if commits >= COMMITS_PER_FRAME:
			break
		if _ready_data.has(c) and not chunks.has(c):
			_commit(_ready_data[c])
			_ready_data.erase(c)
			commits += 1
	for c in want:
		if chunks.has(c) or _tasks.has(c) or _ready_data.has(c):
			continue
		if not threaded:
			if commits == 0:
				var data := AdventureChunk.build(route, c)
				_note_build(data)
				_commit(data)
				commits += 1
			break
		if _tasks.size() >= MAX_TASKS:
			break
		_tasks[c] = WorkerThreadPool.add_task(_work.bind(route, c, _box), false, "Adventure chunk")


static func _work(r: AdventureRoute, c: int, box: _Results) -> void:
	var data := AdventureChunk.build(r, c)
	box.mutex.lock()
	box.done[c] = data
	box.mutex.unlock()


func _note_build(data: Dictionary) -> void:
	stats["built"] += 1
	stats["build_ms_total"] += float(data["ms"])
	stats["build_ms_max"] = maxf(float(stats["build_ms_max"]), float(data["ms"]))


func _commit(data: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	AdventureChunk.commit(data, self)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["commits"] += 1
	stats["commit_ms_total"] += ms
	stats["commit_ms_max"] = maxf(float(stats["commit_ms_max"]), ms)


## Builds and commits every chunk from `s0` to `s1` metres at once (the start, behind a fade).
func preload_range(s0: float, s1: float) -> void:
	for c in range(maxi(0, AdventureRoute.chunk_of(s0)), mini(route.chunk_count() - 1, AdventureRoute.chunk_of(s1)) + 1):
		if not chunks.has(c):
			var data := AdventureChunk.build(route, c)
			_note_build(data)
			_commit(data)


## Whether the chunk under `s` is in the world (its collision there to ride on).
func has_ground(s: float) -> bool:
	return chunks.has(AdventureRoute.chunk_of(s))


## Timing figures for the report: averages and worst cases in ms.
func timing_text() -> String:
	var built := maxi(1, int(stats["built"]))
	var commits := maxi(1, int(stats["commits"]))
	return "plan %.1f ms; chunk build %.1f ms avg, %.1f max (worker thread, %d built); commit %.2f ms avg, %.2f max (main thread); origin shift %.2f ms max (%d); worst frame of streaming %.2f ms" % [
		stats["plan_ms"], float(stats["build_ms_total"]) / built, stats["build_ms_max"], stats["built"],
		float(stats["commit_ms_total"]) / commits, stats["commit_ms_max"], stats["shift_ms_max"], stats["shifts"], stats["stream_ms_max"]]


# ---------------------------------------------------------------------------- the far ground

## A wide disc of ground far below the road, under everything, so any gap at the skyline shows
## land rather than sky.
func _make_horizon() -> void:
	var a := AdventureProps.new_arrays()
	var segs := 40
	var col := Color(0.3, 0.36, 0.22)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		AdventureProps._tri(a, Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)) * 9000.0, Vector3(cos(a0), 0, sin(a0)) * 9000.0, col)
	horizon = MeshInstance3D.new()
	horizon.name = "FarGround"
	horizon.mesh = AdventureProps.to_mesh(a)
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(horizon)
	_follow_horizon(ANCHOR)


func _follow_horizon(p: Vector3) -> void:
	if horizon == null:
		return
	var s := maxf(_own_s, 0.0)
	var i := clampi(int(s / AdventureRoute.STEP), 0, route.base.size() - 1)
	horizon.position = Vector3(p.x, route.base[i] - 70.0, p.z)
	var surf := route.surface_at_s(s)
	var col: Color = AdventureSurface.LAND_COLOR[surf]
	var m := horizon.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.roughness = 1.0
		horizon.material_override = m
	m.albedo_color = col.darkened(0.2)


## Keeps the far ground under you as you ride (a few times a second is plenty).
func follow(p: Vector3) -> void:
	if horizon and Vector2(horizon.position.x - p.x, horizon.position.z - p.z).length() > 200.0:
		_follow_horizon(p)
