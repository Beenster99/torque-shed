class_name AdventureWorld
extends Node3D
## The world of an adventure ride: the route (AdventureRoute, the same on every player's game
## from the planned road and its seed), streamed in as chunks (AdventureChunk) a few kilometres ahead of you and
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
## A crash this far past the road's edge (m) is off it: you're picked up back on the road.
const OFF_ROAD := 1.0
const MAX_TASKS := 2
## How long a frame spends putting a built chunk into the world (ms): a piece at a time (see
## AdventureChunk.step), at least one a frame, more while they fit in this.
const COMMIT_BUDGET_MS := 2.0
## Marks a network snapshot carrying its sender's origin (see tag_state).
const NET_TAG := -77777.0
## The sea's colour on a coastal ride (the far ground there: see _follow_horizon).
const SEA_COLOR := Color(0.09, 0.27, 0.36)

## Emitted after the origin moves: everything placed in the local frame moves by -delta.
signal origin_shifted(delta: Vector3)
## Emitted when a way picked at a fork has been taken in (see apply_picks_soon).
signal picks_taken

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
## The real hills and mountains beyond the land, on a real road (see RealRidges), or null.
var ridges: RealRidges
## The land beyond the road's own chunks, on a real road (see RealLand), or null.
var land: RealLand
var _box := _Results.new()
var _tasks := {}         # chunk -> WorkerThreadPool task id
var _ready_data := {}    # chunk -> built data waiting to be committed
var _committing := {}    # the chunk going into the world a piece at a time (AdventureChunk.begin), or {}
var _hints := {}         # who -> the knot they were last found near
var _own_s := 0.0
var _path_job: _PathJob   # a fork's way being put together on a worker thread (apply_picks_soon)
var _later_picks := {}    # picks that came in meanwhile


## What the worker threads hand back, guarded by its mutex (not the node, which may go first).
class _Results extends RefCounted:
	var mutex := Mutex.new()
	var done := {}


## The path for some picks at the forks, put together on a worker thread: `path` is a copy of
## the route assembled for `picks` (see AdventureRoute.path_copy).
class _PathJob extends RefCounted:
	var picks := {}
	var path: AdventureRoute
	var task := -1

	func run() -> void:
		path._assemble_path()


func _ready() -> void:
	current = self
	process_physics_priority = -100   # shift before the bike's physics in the same tick


func _exit_tree() -> void:
	for c in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[c])
	_tasks.clear()
	if _path_job != null:
		WorkerThreadPool.wait_for_task_completion(_path_job.task)
		_path_job = null
	_stop_committing()
	if current == self:
		current = null


## Lays out the ride along the real road `pack` (planned from the crew's pins, see AdventurePlans) and puts its start
## at ANCHOR: the first `km` of it (all of it for 0), its stops laid out by `seed`.
func setup(pack: RealPack, seed := 1, km := 0.0) -> void:
	name = "Adventure"
	var t0 := Time.get_ticks_usec()
	route = AdventureRoute.new()
	route.plan_real(pack, seed, km if km > 0.0 else pack.max_km())
	stats["plan_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	origin = -ANCHOR
	site_builders = {
		"fuel": func(site, xf, _info): return AdventureProps.fuel_station(site, xf, route.surface_at_s(float(site["s"]))),
		"start": func(_site, xf, info): return AdventureProps.banner("START", xf, float(info["width"]), Color(0.1, 0.35, 0.7)),
		"finish": func(_site, xf, info): return AdventureProps.banner("DESTINATION", xf, float(info["width"]), Color(0.75, 0.2, 0.1)),
		"fork": func(site, xf, _info): return AdventureForks.signpost(site, xf, route),
		AdventureJunctions.KIND: func(site, xf, _info): return AdventureJunctions.build(route, site, xf),
		"limit": func(site, xf, _info): return AdventureProps.limit_sign(float(site["kmh"]), route.real != null and route.real.region == "uk", xf),
	}
	AdventureStops.register(self)
	_make_horizon()
	ridges = RealRidges.new()
	ridges.setup(self, route.real.terrain)
	add_child(ridges)
	ridges.follow(ANCHOR.x + origin.x, ANCHOR.z + origin.z)
	land = RealLand.new()
	land.setup(self, route)
	add_child(land)
	land.follow(ANCHOR.x + origin.x, ANCHOR.z + origin.z)


## Takes the ways picked at the forks ({fork: way}, see AdventureForks): the road from each newly
## decided fork on is rebuilt along its way, and anything already built or building past it is
## dropped (normally nothing: the road isn't built past a fork until it's decided). True when
## anything changed.
func apply_picks(picks: Dictionary) -> bool:
	var keys := picks.keys()
	keys.sort()
	var changed := false
	for f in keys:
		var fi := int(f)
		var w := int(picks[f])
		if fi < 0 or fi >= route.forks.size() or (route.decided.has(fi) and int(route.choices.get(fi, 0)) == w):
			continue
		_drop_from(route.fork_s(fi))
		route.choose(fi, w)
		changed = true
	return changed


## apply_picks without the hitch, for the crew's picks as they come in on the ride: a way off
## the main road has its path put together on a worker thread, and taken in (the chunks past
## its fork dropped) once that's done and no chunk is building, a few frames later; picks_taken
## says when. True when it's started on a pick it didn't have.
func apply_picks_soon(picks: Dictionary) -> bool:
	if _path_job != null:
		_later_picks = picks   # the one under way first, then these
		return false
	var fresh := {}
	for f in picks:
		var fi := int(f)
		if fi < 0 or fi >= route.forks.size() or (route.decided.has(fi) and int(route.choices.get(fi, 0)) == int(picks[f])):
			continue
		fresh[fi] = int(picks[f])
	if fresh.is_empty():
		return false
	var same := fresh.keys().all(func(f): return int(route.choices.get(f, 0)) == int(fresh[f]))
	if same or not threaded:
		# The way the path already runs (the main road): nothing to put together.
		if apply_picks(fresh):
			picks_taken.emit()
		return true
	if land != null:
		land.hold = true   # (the land's workers read the road: none are started till it's swapped)
	_path_job = _PathJob.new()
	_path_job.picks = fresh
	_path_job.path = route.path_copy(fresh)
	_path_job.task = WorkerThreadPool.add_task(_path_job.run, false, "Adventure fork")
	return true


## Takes in the path a pick's job put together, once it's done and nothing's building on the
## route: drops what was built past its forks (normally nothing) and swaps the new path in.
func _take_path() -> void:
	if not WorkerThreadPool.is_task_completed(_path_job.task) or not _tasks.is_empty() or (land != null and land.working()):
		return
	WorkerThreadPool.wait_for_task_completion(_path_job.task)
	var job := _path_job
	_path_job = null
	var keys := job.picks.keys()
	keys.sort()
	_drop_from(route.fork_s(int(keys[0])))
	route.take_path(job.path, job.picks)
	if land != null:
		land.hold = false
	picks_taken.emit()
	var later := _later_picks
	_later_picks = {}
	if not later.is_empty():
		apply_picks_soon(later)


## Lets the worker threads finish (they read the route, which is about to change) and drops every
## chunk from `s` on, built, waiting or building.
func _drop_from(s: float) -> void:
	if land != null:
		land.reset()   # (its workers read the route too, and the land past a fork is about to be another way's)
	for c in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[c])
	_tasks.clear()
	_box.mutex.lock()
	_box.done.clear()
	_box.mutex.unlock()
	var c0 := AdventureRoute.chunk_of(s)
	if not _committing.is_empty() and int(_committing["c"]) >= c0:
		_stop_committing()
	for c in _ready_data.keys():
		if c >= c0:
			_ready_data.erase(c)
	for c in chunks.keys():
		if c >= c0:
			chunks[c].queue_free()
			chunks.erase(c)


## The last chunk that may be built: the one ending at the first undecided fork (or the road's end).
func last_buildable_chunk() -> int:
	var end := route.stream_end()
	var last := route.chunk_count() - 1
	return last if end == INF else mini(last, AdventureRoute.chunk_of(end) - 1)


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


## Where a bike that came to rest at local `p` off the road is put back on it: the nearest point
## along it, on the left half and facing on towards the destination. null when `p` is on the
## road (or nowhere near it), so it's picked up where it lies.
func back_on_road(p: Vector3):
	var hit := locate_local(p, "respawn")
	if hit.is_empty():
		return null
	var s := float(hit["s"])
	if absf(float(hit["lat"])) <= route.width_at_s(s) * 0.5 + OFF_ROAD and p.y > route.height_at_s(s) - 5.0:
		return null
	s = clampf(s, 2.0, minf(route.total, route.stream_end()) - 20.0)
	return transform_at(s, -route.width_at_s(s) * 0.25)


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
	var pad := AdventureStops.pad_surface(route, s, float(hit["lat"]))
	if pad != "":
		return pad
	var xz := route_xz(p)
	var arm := AdventureJunctions.arm_surface(route, int(hit["i"]), xz[0], xz[1])
	if arm != "":
		return arm
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
	if ridges != null:
		ridges.place()
	if land != null:
		land.place()
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
	var c_hi := mini(last_buildable_chunk(), AdventureRoute.chunk_of(own + AHEAD))
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
	if not _committing.is_empty() and not keep.has(int(_committing["c"])):
		_stop_committing()
	if _path_job != null:
		_take_path()
	var commits := _commit_some(want)
	for c in want:
		if chunks.has(c) or _tasks.has(c) or _ready_data.has(c) or int(_committing.get("c", -1)) == c:
			continue
		if not threaded:
			if commits == 0:
				var data := AdventureChunk.build(route, c)
				_note_build(data)
				_commit(data)
				commits += 1
			break
		if _tasks.size() >= MAX_TASKS or _path_job != null:
			break   # (none started while a fork's new way is being put together: see _take_path)
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


## This frame's share of putting built chunks into the world, nearest wanted first: pieces of
## one (AdventureChunk.step) while they fit in COMMIT_BUDGET_MS, at least one. How many chunks
## went in whole.
func _commit_some(want: Array) -> int:
	var t0 := Time.get_ticks_usec()
	var done := 0
	while true:
		if _committing.is_empty():
			for c in want:
				if _ready_data.has(c) and not chunks.has(c):
					_committing = AdventureChunk.begin(_ready_data[c], self)
					_committing["us"] = 0
					_ready_data.erase(c)
					break
			if _committing.is_empty():
				break
		var s0 := Time.get_ticks_usec()
		var whole := AdventureChunk.step(_committing)
		_committing["us"] = int(_committing["us"]) + Time.get_ticks_usec() - s0
		if whole:
			stats["commits"] += 1
			stats["commit_ms_total"] += int(_committing["us"]) / 1000.0
			_committing = {}
			done += 1
		if Time.get_ticks_usec() - t0 >= COMMIT_BUDGET_MS * 1000.0:
			break
	if Time.get_ticks_usec() > t0 + 50:
		stats["commit_ms_max"] = maxf(float(stats["commit_ms_max"]), (Time.get_ticks_usec() - t0) / 1000.0)
	return done


## Gives up on the chunk being put into the world (not wanted any more, or past a fork).
func _stop_committing() -> void:
	if _committing.is_empty():
		return
	var node: Node3D = _committing["node"]
	if is_instance_valid(node) and node.get_parent() == null:
		node.free()
	_committing = {}


## Builds and commits every chunk from `s0` to `s1` metres at once (the start, behind a fade).
func preload_range(s0: float, s1: float) -> void:
	for c in range(maxi(0, AdventureRoute.chunk_of(s0)), mini(last_buildable_chunk(), AdventureRoute.chunk_of(s1)) + 1):
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
	return "plan %.1f ms; chunk build %.1f ms avg, %.1f max (worker thread, %d built); commit %.2f ms a chunk avg, %.2f max in a frame (main thread); origin shift %.2f ms max (%d); worst frame of streaming %.2f ms" % [
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
	var m := horizon.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.roughness = 1.0
		horizon.material_override = m
	if route.sea:
		# By the sea the far ground is the sea itself, at its own level: the land runs down into it.
		horizon.position = Vector3(p.x, AdventureTheme.SEA_Y, p.z)
		m.albedo_color = SEA_COLOR
		m.roughness = 0.12
		m.metallic_specular = 0.8
		return
	horizon.position = Vector3(p.x, route.base[i] - 70.0, p.z)
	var surf := route.surface_at_s(s)
	var col: Color = route.look["land"][surf]
	m.albedo_color = col.darkened(0.2)


## Keeps the far ground under you as you ride (a few times a second is plenty).
func follow(p: Vector3) -> void:
	if ridges != null:
		ridges.follow(p.x + origin.x, p.z + origin.z)
	if land != null:
		land.follow(p.x + origin.x, p.z + origin.z)
	if horizon and Vector2(horizon.position.x - p.x, horizon.position.z - p.z).length() > 200.0:
		_follow_horizon(p)
