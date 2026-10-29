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
## The far ground's flat sheet lies this far (m) under the planned road and the ground round you.
const HORIZON_DROP := 70.0
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
## Inside a tunnel the sky is shut out this far from a portal (m), easing in from the mouth.
const SHELTER_IN := 30.0

## Emitted after the origin moves: everything placed in the local frame moves by -delta.
signal origin_shifted(delta: Vector3)

static var current: AdventureWorld
## The network ride (Ride Anywhere v2), on by default: a ride set up while it's on streams the road blocks of its whole
## region round each rider (RoadStreamer) instead of the planned road's chunks, and the planned road is only advice
## (found only within NETWORK_ADVICE of it). The host's choice is the crew's (Shed.adventure "network"). Off (Esc >
## Debug, for now) is the single planned road, kept as the fallback.
static var network := true
## On the network ride the planned road answers locate_local only this close to it (m), so riding off it is riding on.
const NETWORK_ADVICE := 60.0

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
## The road network round each rider on the network ride (see network), or null.
var roads: RoadStreamer
## The region the network ride is on: the plan's (Shed.adventure), unless set before setup (the tests).
var roads_region: RealRegion
## The planned ride's places (its stops, fuel, start and destination) beside the network's roads, or null (NetSites).
var net_sites: NetSites
## The scenery round the riders on the network ride (SceneryStreamer); null on the single road.
var scenery: SceneryStreamer
var _net_y := {}         # route knot -> the network road's height there (network_y)
var _net_y_hint := -1
var _box := _Results.new()
var _tasks := {}         # chunk -> WorkerThreadPool task id
var _ready_data := {}    # chunk -> built data waiting to be committed
var _committing := {}    # the chunk going into the world a piece at a time (AdventureChunk.begin), or {}
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
	_stop_committing()
	NetNav.forget(self)
	if current == self:
		current = null
		Daylight.shelter = 0.0


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
		AdventureJunctions.KIND: func(site, xf, _info): return AdventureJunctions.build(route, site, xf),
		"limit": func(site, xf, _info): return AdventureProps.limit_sign(float(site["kmh"]), route.real != null and route.real.region == "uk", xf),
	}
	AdventureStops.register(self)
	_make_horizon()
	ridges = RealRidges.new()
	ridges.setup(self, route.real.terrain)
	add_child(ridges)
	ridges.follow(ANCHOR.x + origin.x, ANCHOR.z + origin.z)
	var on_network := network and _start_network()
	RealLand.roam = on_network   # (riders may ride the land off the roads on the network ride)
	land = RealLand.new()
	land.setup(self, route)
	if on_network:
		land.set_roads(roads.net)   # (the land everywhere round the riders, the roads cut into it)
	add_child(land)
	land.follow(ANCHOR.x + origin.x, ANCHOR.z + origin.z)


## Starts the road network round the riders (the network ride): false when the ride's region isn't known.
func _start_network() -> bool:
	if roads_region == null:
		var plan = Shed.adventure.get("plan", {})
		var id := str((plan as Dictionary).get("region", "")) if plan is Dictionary else ""
		roads_region = RealRegion.get_region(id) if id != "" else null
	if roads_region == null:
		push_warning("Network ride: the ride's region isn't known; riding the planned road.")
		return false
	var t: RealTerrain = route.real.terrain
	var net := RoadNet.new(roads_region, t.height, Callable(t, "ready") if t.has_method("ready") else Callable())
	net.dress = {"terrain": t, "look": route.look}
	roads = RoadStreamer.new()
	roads.setup(self, net)
	add_child(roads)
	net_sites = NetSites.new()
	net_sites.setup(self)   # (before any block is laid out: the stops' flat ground is in them)
	add_child(net_sites)
	scenery = SceneryStreamer.new()
	scenery.setup(self, net)   # (beside the roads, never in them: phase D's things worth stopping for)
	add_child(scenery)
	return true


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
	if roads != null and not hit.is_empty() and absf(float(hit["lat"])) > NETWORK_ADVICE:
		return {}
	if who != "" and not hit.is_empty():
		_hints[who] = int(hit["i"])
	return hit


## How far local `p` is under a tunnel's roof: 0 out under the sky, 1 well inside (easing in over SHELTER_IN from each
## portal), for the daylight, the rain and your eyes.
func shelter_local(p: Vector3) -> float:
	if route == null or route.bore.is_empty():
		return 0.0
	var hit := locate_local(p, "shelter")
	if hit.is_empty():
		return 0.0
	var i := int(hit["i"])
	var span := route.tunnel_span(i)
	if span.x < 0:
		return 0.0
	var s := float(hit["s"])
	if absf(float(hit["lat"])) > route.width[i] * 0.5 + AdventureTunnels.SIDE + 1.0 \
			or p.y > route.height_at_s(s) + AdventureTunnels.WALL + AdventureTunnels.ARCH + 1.0:
		return 0.0
	return smoothstep(0.0, SHELTER_IN, minf(s - span.x * AdventureRoute.STEP, span.y * AdventureRoute.STEP - s))


## shelter_local at global `pos` in the current adventure (0 when there's none).
static func shelter_at(pos: Vector3) -> float:
	if current == null or current.route == null or not current.is_inside_tree():
		return 0.0
	return current.shelter_local(current.to_local(pos))


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
	if roads != null:
		var on := roads.net.locate(xz[0], xz[1])
		if not on.is_empty() and bool(on["on_road"]):
			y = float(on["y"])   # (the network's road, which the planned line only follows)
	return Transform3D(Basis(Vector3.UP, -h), to_local_pos(xz[0], y, xz[1]))


## Where a rider in grid slot `slot` wakes on the network ride, having slept at `bed` ([x, z, heading], the region's
## frame: AdventureNeeds.resume_at): on the road nearest it, on the left half, facing on along the route (or the way the
## bed faced, away from it), staggered a bike length back by slot. null when no road is near.
func net_wake_xf(bed: Array, slot: int):
	if roads == null or bed.size() != 3:
		return null
	var net := roads.net
	var on := net.locate(float(bed[0]), float(bed[1]))
	if on.is_empty():
		return null
	var e := int(on["edge"])
	# Facing on along the route where it's near (the beds are at its stops), else the way the bed faced.
	var face := float(bed[2])
	var hit := route.locate(float(bed[0]), float(bed[1]))
	if not hit.is_empty() and absf(float(hit["lat"])) < NETWORK_ADVICE * 2.0:
		face = route.heading_at_s(float(hit["s"]))
	var dir := 1.0 if absf(angle_difference(net.heading_at(e, float(on["s"])), face)) < PI * 0.5 else -1.0
	var len := net.length_of(e)
	var s := clampf(float(on["s"]) - dir * 4.0 * slot, minf(5.0, len * 0.5), maxf(len - 5.0, len * 0.5))
	var h := net.heading_at(e, s) + (0.0 if dir > 0.0 else PI)
	var p := net.point_at(e, s) + Vector2(cos(h), sin(h)) * (-net.width_of(e) * 0.25)
	var y := net.road_y(e, s)
	if is_nan(y):
		return null
	return Transform3D(Basis(Vector3.UP, -h), to_local_pos(p.x, y + RoadNet.CROWN, p.y))


## The network's road height under the planned road's knot `i` (the network ride: the planned line only follows the
## network's roads, whose heights are their own), or NaN off the network or where it isn't laid out yet. Kept until the
## ground under the roads sharpens (RoadStreamer.heights_changed).
func network_y(i: int) -> float:
	if roads == null:
		return NAN
	if _net_y.has(i):
		return _net_y[i]
	var on := roads.net.locate(route.px[i], route.pz[i], _net_y_hint)
	if on.is_empty() or not bool(on["on_road"]):
		return NAN
	_net_y_hint = int(on["edge"])
	var y := roads.net.road_y(int(on["edge"]), float(on["s"])) if int(on["node"]) < 0 else float(on["y"]) - RoadNet.CROWN
	if roads.can_build(RoadBlock.key_of(route.px[i], route.pz[i])):
		_net_y[i] = y   # (only once the ground there is final: before that it's a guess)
	return y


## Forgets the network heights under the planned road (network_y): the ground under them has sharpened.
func forget_network_y() -> void:
	_net_y.clear()


## The heading Bike.place wants for facing along the road at `s`.
func heading_at(s: float) -> float:
	return -route.heading_at_s(s)


## Which side of the road they keep to where local `p` is: -1 the left (as at home, and wherever the
## country isn't known), 1 the right (its country's facts, RegionKit).
func keep_at(p: Vector3) -> int:
	if route == null or route.real == null or route.real.terrain == null:
		return -1
	var xz := route_xz(p)
	var t: RealTerrain = route.real.terrain
	var f: Dictionary = RegionKit.at_frame(t.lat0, t.lon0, xz[0], xz[1]).get("facts", {})
	return 1 if str(f.get("drive", "left")) == "right" else -1


## Where a bike that came to rest at local `p` off the road is put back on it: the nearest point
## along it, on the half the country drives on and facing on towards the destination. null when `p` is on the
## road (or nowhere near it), so it's picked up where it lies.
func back_on_road(p: Vector3):
	if roads != null:
		return _back_on_network(p)
	var hit := locate_local(p, "respawn")
	if hit.is_empty():
		return null
	var s := float(hit["s"])
	if absf(float(hit["lat"])) <= route.width_at_s(s) * 0.5 + OFF_ROAD and p.y > route.height_at_s(s) - 5.0:
		return null
	s = clampf(s, 2.0, route.total - 20.0)
	return transform_at(s, keep_at(p) * route.width_at_s(s) * 0.25)


## back_on_road on the network ride: the nearest road's half the country drives on, facing along it (a to b).
func _back_on_network(p: Vector3):
	var xz := route_xz(p)
	var hit := roads.net.locate(xz[0], xz[1])
	if hit.is_empty():
		return null
	if bool(hit["on_road"]) or (absf(float(hit["lat"])) <= float(hit["width"]) * 0.5 + OFF_ROAD and p.y > float(hit["y"]) - 5.0):
		return null
	var ei := int(hit["edge"])
	var s := float(hit["s"])
	var h := float(hit["heading"])
	var at := roads.net.point_at(ei, s) + Vector2(cos(h), sin(h)) * (keep_at(p) * float(hit["width"]) * 0.25)
	return Transform3D(Basis(Vector3.UP, -h), to_local_pos(at.x, roads.net.road_y(ei, s) + RoadNet.CROWN, at.y))


## Where player `slot` starts: two by two behind the start banner, on the half of the road the
## country drives on.
func start_xf(slot: int) -> Transform3D:
	var s := 36.0 - 5.0 * float(slot / 2)
	var w := route.width_at_s(maxf(s, 0.0))
	var lat := keep_at(transform_at(maxf(s, 2.0), 0.0).origin) * w * 0.25 + (0.7 if slot % 2 == 1 else -0.7)
	return transform_at(maxf(s, 2.0), lat)


## The surface at local `p`: the road's, or the land's beside it (see AdventureSurface).
func surface_local(p: Vector3) -> String:
	if roads != null:
		var xz := route_xz(p)
		var on := roads.net.locate(xz[0], xz[1])
		return roads.net.region.surface_of(int(on["edge"])) if not on.is_empty() and bool(on["on_road"]) else "grass"
	var hit := locate_local(p, "surface")
	if hit.is_empty():
		return "grass"
	var s: float = hit["s"]
	var surf := route.surface_at_s(s)
	if absf(float(hit["lat"])) <= AdventureJunctions.edge_at_s(route, s) + 0.1:
		return surf   # (right up to the edge as its mesh is drawn: a side road starts there)
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
	if roads != null:
		roads.place()
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

func _process(delta: float) -> void:
	if route == null:
		return
	var pt := Perf.t0()
	var t0 := Time.get_ticks_usec()
	if roads == null:
		stream()   # (the network ride's blocks stream themselves: RoadStreamer)
	stats["stream_ms_max"] = maxf(float(stats["stream_ms_max"]), (Time.get_ticks_usec() - t0) / 1000.0)
	# The tunnel roof over the camera, eased so the light doesn't snap at a portal.
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var cover := shelter_local(to_local(cam.global_position)) if cam else 0.0
	Daylight.shelter = move_toward(Daylight.shelter, cover, delta * 2.5)
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
	# What the workers have finished (only those whose task has returned: waiting on one that's written its chunk but not
	# yet got back from the call was a hitch of tens of ms when the machine was busy).
	_box.mutex.lock()
	var finished := {}
	for c in _box.done.keys():
		if not _tasks.has(c) or WorkerThreadPool.is_task_completed(_tasks[c]):
			finished[c] = _box.done[c]
			_box.done.erase(c)
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


## Gives up on the chunk being put into the world (not wanted any more).
func _stop_committing() -> void:
	if _committing.is_empty():
		return
	var node: Node3D = _committing["node"]
	if is_instance_valid(node) and node.get_parent() == null:
		node.free()
	_committing = {}


## Builds and commits every chunk from `s0` to `s1` metres at once (the start, behind a fade).
func preload_range(s0: float, s1: float) -> void:
	if roads != null:
		var at: Array[Vector2] = []
		for s in [s0, (s0 + s1) * 0.5, s1]:
			var xz := route.xz_at(clampf(s, 0.0, route.total), 0.0)
			at.append(Vector2(xz[0], xz[1]))
		roads.preload_round(at, 300.0)
		return
	for c in range(maxi(0, AdventureRoute.chunk_of(s0)), mini(route.chunk_count() - 1, AdventureRoute.chunk_of(s1)) + 1):
		if not chunks.has(c):
			var data := AdventureChunk.build(route, c)
			_note_build(data)
			_commit(data)


## As preload_range, letting the frames go on while it's done (for a loading screen): `report` is told (done, out of)
## as it goes.
func preload_range_async(s0: float, s1: float, report := Callable()) -> void:
	if roads != null:
		var at: Array[Vector2] = []
		for s in [s0, (s0 + s1) * 0.5, s1]:
			var xz := route.xz_at(clampf(s, 0.0, route.total), 0.0)
			at.append(Vector2(xz[0], xz[1]))
		await roads.preload_round_async(at, 300.0, report)
		return
	var c0 := maxi(0, AdventureRoute.chunk_of(s0))
	var c1 := mini(route.chunk_count() - 1, AdventureRoute.chunk_of(s1))
	for c in range(c0, c1 + 1):
		if report.is_valid():
			report.call(c - c0, c1 - c0 + 1)
		await get_tree().process_frame
		if not chunks.has(c):
			var data := AdventureChunk.build(route, c)
			_note_build(data)
			_commit(data)
	if report.is_valid():
		report.call(c1 - c0 + 1, c1 - c0 + 1)


## Whether the chunk under `s` is in the world (its collision there to ride on).
func has_ground(s: float) -> bool:
	if roads != null:
		var xz := route.xz_at(clampf(s, 0.0, route.total), 0.0)
		return roads.has_ground(xz[0], xz[1])
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
	# (well under the planned road there, and under the ground you're on: on the network you may be far below it, down
	# in a valley, and the far ground's flat sheet would hang over you)
	var y := route.base[i] - HORIZON_DROP
	var g := route.ground_at(p.x + origin.x, p.z + origin.z)
	if not is_nan(g):
		y = minf(y, g - HORIZON_DROP)
	horizon.position = Vector3(p.x, y, p.z)
	var surf := route.surface_at_s(s)
	var col: Color = route.look["land"][surf]
	m.albedo_color = col.darkened(0.2)


## Keeps the far ground under you as you ride (a few times a second is plenty).
func follow(p: Vector3) -> void:
	if ridges != null:
		ridges.follow(p.x + origin.x, p.z + origin.z)
	if land != null:
		land.follow(p.x + origin.x, p.z + origin.z)
	if horizon and (Vector2(horizon.position.x - p.x, horizon.position.z - p.z).length() > 200.0 \
			or p.y < horizon.position.y + HORIZON_DROP * 0.5):
		_follow_horizon(p)
