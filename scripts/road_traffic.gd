class_name RoadTraffic
extends Node3D
## The traffic on the riding map's roads: other bikers on bikes of every style, and cars, vans,
## lorries and coaches (TrafficVehicle), never more than MAX_RIDERS at once. Each keeps to its
## own lane (it's a left-hand road) both ways along the tarmac at a pace of its own, a share of
## the road's limit (slower through the town and the villages; lorries and coaches slower
## still), slowing for the bends (riders leaning into them), slowing to turn off at junctions
## with its indicator going, turning round at a dead end, and hanging back a sensible gap behind
## anyone stopped or slower in the lane ahead. There's more of it round the town and the
## villages than out on the open road (see busy). It's all solid: ride into anything and you
## crash, as you would into anything else. None of it is simulated: it's put where it is.
##
## They ride through the town on the High Street past the shed's forecourt, but keep off the
## Build Yard behind it (the test area): roads near the yard are marked out of bounds, and a
## rider heading that way turns off at the junction before it.
## They appear out of everyone's sight (SPAWN_NEAR from every player) but near enough to
## someone to be met (SPAWN_FAR), and go when they're far from everyone (DESPAWN).
##
## Host-driven: the host (or a solo game) rides them and sends where each is to the crew a few
## times a second (see pack); everyone else rides them on along their road between updates. A
## rider is only its road, how far along it, which way, its speed and a look seed, so that's
## all that's sent; every machine draws the same rider from the seed.

const MAX_RIDERS := 14
const SEND_EVERY := 0.2
const SPAWN_EVERY := 1.5
const SPAWN_CHANCE := 0.8
## How many are out round someone in the town (or a village), and round someone out on the open road.
const TOWN_COUNT := 14
const OPEN_COUNT := 6
## The share of them that are bikers, in town and out of it.
const BIKE_SHARE := Vector2(0.2, 0.28)
## The town round the High Street (centre, radius) and how far out from it (and from each
## village) the traffic thins to the open road's.
const TOWN := Vector3(0.0, 93.0, 260.0)
const BUSY_FADE := 160.0
## The limits the drivers keep to (a share of, see TrafficVehicle.pick_pace): in town, open road (m/s).
const TOWN_LIMIT := 12.5
const OPEN_LIMIT := 20.0
## A new one turns up no closer than this (m) to anyone already on the same road.
const SPAWN_GAP := 60.0
## Bumper to bumper, the least gap kept to whoever's ahead in the lane (m), and the time gap
## (s) kept at speed.
const GAP := 3.0
const HEADWAY := 1.2
## How often (s) each looks over the road ahead for bends and junctions.
const SCAN_EVERY := 0.2
const SPAWN_NEAR := 220.0
const SPAWN_FAR := 520.0
const DESPAWN := 700.0
## The Build Yard, and how far round it the roads are out of bounds.
const KEEP_OUT := Rect2(WorldYard.CENTER - WorldYard.HALF, WorldYard.HALF * 2.0)
const KEEP_OUT_MARGIN := 25.0
## How hard they corner (sideways m/s^2), brake and pull away (m/s^2), and the pace they take
## a junction they turn off at, or a dead end they turn round in (m/s).
const GRIP := 3.0
const BRAKE := 3.0
const ACCEL := 2.0
const TURN_SPEED := 6.0
const ROUND_SPEED := 2.5
## How far left of the middle of the road they keep, as a share of its half width.
const LANE := 0.45
## The chance a rider turns off at a junction they could go on through.
const TURN_CHANCE := 0.4
## Drawn only within this of the camera.
const DRAW_RANGE := 450.0
## Further than this (m) a rider's engine isn't heard: its sound players stop.
const SOUND_RANGE := 260.0
## Hitting one faster than this (m/s) throws you off.
const CRASH_SPEED := 4.0
## A biker this close (m) to you when you nod or wave nods back, after NOD_BACK_DELAY seconds.
const NOD_REACH := 45.0
const NOD_BACK_DELAY := 0.5

var main: Node
var world: World
## Each slot: {} when free, else {road, s, dir (+1 along the road, -1 against it), v, seed,
## kind ("bike" or a VehicleModel kind; a bike when missing), cruise (a bike's own pace, m/s),
## pace (a driver's share of the limit), turn ({} or {at, road, s, dir}: the junction it's turning off at), round (s of
## the dead end or out-of-bounds stretch it's turning round before, or -1), decided (the
## junction it last made its mind up about, Vector2i(road, sample))}.
var riders: Array = []
var _views: Array = []       # per slot: {} or {body, lean, model, sound, seed, pos, yaw, off, roll, spin, road}
                             # (a vehicle's: {body (TrafficVehicle), car, seed, pos, yaw, off, road, dir})
var _rng := RandomNumberGenerator.new()
var _spots: Array = []
var _spawn_timer := 2.0
var _send_timer := 0.0
var _seq := 0                # look seeds handed out
## Per road: the curvature at each sample (1/m, + bending right going along it), which samples
## are out of bounds, and the junctions on it (sample -> [[road, s, dir], ...]).
var _k: Array = []
var _blocked: Array = []
var _junctions: Array = []
var _tarmac: Array[int] = []
var _ready_roads := false


func _ready() -> void:
	_rng.randomize()
	for i in MAX_RIDERS:
		riders.append({})
		_views.append({})
	Net.traffic_received.connect(unpack)
	var sounds := TrafficSounds.new()   # the cars', vans', lorries' and coaches' engines (the bikers have their own)
	sounds.name = "VehicleSounds"
	add_child(sounds)


## Works out the bends, the out-of-bounds stretches and the junctions of every tarmac road.
func setup_roads() -> void:
	_ready_roads = false
	if world == null or world.roads == null:
		return
	var roads := world.roads
	_k.clear()
	_blocked.clear()
	_junctions.clear()
	_tarmac.clear()
	var keep := KEEP_OUT.grow(KEEP_OUT_MARGIN)
	for ri in roads.roads.size():
		var r: Dictionary = roads.roads[ri]
		var xz: PackedVector2Array = r["xz"]
		var dir: PackedVector2Array = r["dir"]
		var n := xz.size()
		var closed: bool = r["closed"]
		var step := _step(ri)
		var k := PackedFloat32Array()
		k.resize(n)
		var blocked := PackedByteArray()
		blocked.resize(n)
		for i in n:
			var a := posmod(i - 2, n) if closed else maxi(i - 2, 0)
			var b := (i + 2) % n if closed else mini(i + 2, n - 1)
			var span := step * float(b - a if b >= a else b + n - a)
			k[i] = dir[a].cross(dir[b]) / maxf(span, 0.5) if span > 0.0 else 0.0
			blocked[i] = 1 if keep.has_point(xz[i]) else 0
		_k.append(k)
		_blocked.append(blocked)
		_junctions.append({})
		if r["kind"] == "tarmac":
			_tarmac.append(ri)
	for ri in _tarmac:
		var r: Dictionary = roads.roads[ri]
		for end in ["start_join", "end_join"]:
			var j: Dictionary = r[end]
			if j.is_empty() or not _tarmac.has(int(j["road"])):
				continue
			var entry := [ri, 0.0 if end == "start_join" else float(r["length"]), 1 if end == "start_join" else -1]
			var at: Dictionary = _junctions[int(j["road"])]
			if not at.has(int(j["i"])):
				at[int(j["i"])] = []
			(at[int(j["i"])] as Array).append(entry)
	_ready_roads = true


# ---------------------------------------------------------------------------- the roads

func _road(ri: int) -> Dictionary:
	return world.roads.roads[ri]


## Metres between samples on road `ri`.
func _step(ri: int) -> float:
	var r := _road(ri)
	var n := (r["xz"] as PackedVector2Array).size()
	return float(r["length"]) / float(n if r["closed"] else maxi(n - 1, 1))


## The sample position `s` metres along road `ri` falls at (wrapped round a loop, clamped
## to the ends of an open road).
func _f(ri: int, s: float) -> float:
	var r := _road(ri)
	var n := (r["xz"] as PackedVector2Array).size()
	var f := s / _step(ri)
	return wrapf(f, 0.0, float(n)) if r["closed"] else clampf(f, 0.0, float(n - 1))


func _i(ri: int, s: float) -> int:
	return int(_f(ri, s)) % (_road(ri)["xz"] as PackedVector2Array).size()


## The road's centre line `s` metres along it, on its surface.
func road_point(ri: int, s: float) -> Vector3:
	var r := _road(ri)
	var xz: PackedVector2Array = r["xz"]
	var h: PackedFloat32Array = r["h"]
	var n := xz.size()
	var f := _f(ri, s)
	var i := int(f) % n
	var j := (i + 1) % n if r["closed"] else mini(i + 1, n - 1)
	var u := f - floorf(f)
	var p := xz[i].lerp(xz[j], u)
	return Vector3(p.x, lerpf(h[i], h[j], u), p.y)


## The way along the road at `s` (unit, on the map: x and z).
func road_dir(ri: int, s: float) -> Vector2:
	var dir: PackedVector2Array = _road(ri)["dir"]
	var n := dir.size()
	var f := _f(ri, s)
	var i := int(f) % n
	var j := (i + 1) % n if _road(ri)["closed"] else mini(i + 1, n - 1)
	return dir[i].lerp(dir[j], f - floorf(f)).normalized()


func _wrap_s(ri: int, s: float) -> float:
	var r := _road(ri)
	return wrapf(s, 0.0, float(r["length"])) if r["closed"] else clampf(s, 0.0, float(r["length"]))


## Whether riding road `ri` from `s` in `dir` runs into the out-of-bounds stretch before it
## reaches a junction (or the end of the road, where they can turn round).
func _heads_into_yard(ri: int, s: float, dir: int, reach := 600.0) -> bool:
	var r := _road(ri)
	var n := (r["xz"] as PackedVector2Array).size()
	var blocked: PackedByteArray = _blocked[ri]
	var at: Dictionary = _junctions[ri]
	var i := _i(ri, s)
	var steps := int(reach / _step(ri))
	for k in range(1, steps):
		var j := i + k * dir
		if r["closed"]:
			j = posmod(j, n)
		elif j < 0 or j >= n:
			return false
		if blocked[j]:
			return true
		if at.has(j):
			return false
	return false


# ---------------------------------------------------------------------------- host

func _physics_process(delta: float) -> void:
	var pt := Perf.t0()
	_physics_process_body(delta)
	Perf.add("traffic", pt)


func _physics_process_body(delta: float) -> void:
	if main == null or not main.get("in_session") or world == null:
		if active_count() > 0:
			clear()
		return
	if not _ready_roads:
		setup_roads()
		if not _ready_roads:
			return
	_watch_bike()
	var host := not Net.is_online() or Net.is_host()
	if host:
		_spots = _users(-1)   # where everyone is this tick, for the gaps (see _users)
	for slot in MAX_RIDERS:
		var d: Dictionary = riders[slot]
		if d.is_empty():
			continue
		if host:
			_drive(slot, d, delta)
		else:
			_coast(d, delta)
	_spots = []
	if host:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_EVERY
			if active_count() < wanted() and _rng.randf() < SPAWN_CHANCE:
				spawn_one()
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = SEND_EVERY
			Net.send_traffic(pack())
	_update_views(delta)


## Your bike running into one of them: at more than CRASH_SPEED you come off, as when the
## rider hits anything (see Bike.crash). Its speed is kept from the tick before (on the bike,
## as a meta), as the hit has already stopped it by the time it's reported.
func _watch_bike() -> void:
	for b in get_tree().get_nodes_in_group("ridden_bike"):
		if not b is Bike:
			continue   # the crew's bikes crash on their own machines
		if not b.has_meta("traffic_watch"):
			b.set_meta("traffic_watch", true)
			(b as Bike).body_entered.connect(_on_bike_hit.bind(b))
		b.set_meta("traffic_speed", (b as Bike).linear_velocity.length())


func _on_bike_hit(body: Node, b: Bike) -> void:
	if is_instance_valid(b) and body.is_in_group("road_traffic") and float(b.get_meta("traffic_speed", 0.0)) > CRASH_SPEED \
			and not b.is_crashed and not b.is_ghost():
		b.crash()


## Where everyone in the session is: you, and each of the crew.
func _people() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if main.get("bike") != null:
		out.append((main.bike as Node3D).global_position)
	elif main.get("walker") != null:
		out.append((main.walker as Node3D).global_position)
	for rp in (main.get("remotes") as Dictionary).values():
		if is_instance_valid(rp) and rp.has_method("world_position"):
			out.append(rp.world_position())
	return out


## Everyone on the road but slot `skip_slot`: you, the crew's bikes and the rest of the
## traffic, each [where, half its length, slot or -1, its velocity]. While the host drives them each tick
## it works them out once (_spots) rather than for each of them.
func _users(skip_slot: int) -> Array:
	if not _spots.is_empty():
		return _spots.filter(func(e): return int(e[2]) != skip_slot or skip_slot < 0)
	var out := []
	if main.get("bike") != null:
		out.append([(main.bike as Node3D).global_position, 1.1, -1, (main.bike as RigidBody3D).linear_velocity])
	for rp in (main.get("remotes") as Dictionary).values():
		if is_instance_valid(rp) and is_instance_valid(rp.get("bike")):
			out.append([(rp.bike as Node3D).global_position, 1.1, -1, Vector3.ZERO])
	for slot in MAX_RIDERS:
		if slot != skip_slot and not riders[slot].is_empty():
			var d: Dictionary = riders[slot]
			var f := road_dir(int(d["road"]), float(d["s"])) * int(d["dir"]) * float(d["v"])
			out.append([_rider_point(d), half_length(d), slot, Vector3(f.x, 0.0, f.y)])
	return out


func _nearest_person(p: Vector3, people: Array[Vector3]) -> float:
	var best := INF
	for q in people:
		best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best


## How built up it is round `p`: 1 in the town or a village, fading to 0 out on the open road.
static func busy(p: Vector3) -> float:
	var best := clampf(1.0 - (Vector2(p.x - TOWN.x, p.z - TOWN.y).length() - TOWN.z) / BUSY_FADE, 0.0, 1.0)
	for site in WorldLayout.SITES:
		if site["kind"] != "village":
			continue
		var at: Vector2 = site["at"]
		best = maxf(best, clampf(1.0 - (Vector2(p.x - at.x, p.z - at.y).length() - float(site["r"])) / BUSY_FADE, 0.0, 1.0))
	return best


## How many should be out: more round someone in the town or a village than on the open road.
func wanted() -> int:
	var b := 0.0
	for p in _people():
		b = maxf(b, busy(p))
	return mini(MAX_RIDERS, roundi(lerpf(OPEN_COUNT, TOWN_COUNT, b)))


## The limit the drivers keep to (a share of) at `p` (m/s).
static func limit_at(p: Vector3) -> float:
	return lerpf(OPEN_LIMIT, TOWN_LIMIT, busy(p))


static func kind_of(d: Dictionary) -> String:
	return str(d.get("kind", "bike"))


## How hard it corners (sideways m/s^2), brakes and pulls away (m/s^2): {grip, brake, accel}.
static func traits_of(d: Dictionary) -> Dictionary:
	var k := kind_of(d)
	return TrafficVehicle.TRAITS[k] if TrafficVehicle.TRAITS.has(k) else {"grip": GRIP, "brake": BRAKE, "accel": ACCEL}


## Half its length (m), for the gaps kept to it.
static func half_length(d: Dictionary) -> float:
	var k := kind_of(d)
	return float(VehicleModel.SPECS[k]["len"]) * 0.5 if VehicleModel.SPECS.has(k) else 1.1


## Host: a new rider somewhere out of sight but not too far from someone, riding away from
## the yard, on a bike or driving whatever's usual round there. Returns its slot, or -1 when
## there's no room or nowhere suits.
func spawn_one(near := SPAWN_NEAR, far := SPAWN_FAR) -> int:
	if not _ready_roads:
		setup_roads()
	if not _ready_roads or _tarmac.is_empty():
		return -1
	var slot := -1
	for i in MAX_RIDERS:
		if (riders[i] as Dictionary).is_empty():
			slot = i
			break
	if slot < 0:
		return -1
	var people := _people()
	if people.is_empty():
		return -1
	for attempt in 40:
		var ri: int = _tarmac[_rng.randi() % _tarmac.size()]
		var r := _road(ri)
		var n := (r["xz"] as PackedVector2Array).size()
		var i := _rng.randi() % n
		if (_blocked[ri] as PackedByteArray)[i]:
			continue
		var s := float(i) * _step(ri)
		var p := road_point(ri, s)
		var d := _nearest_person(p, people)
		if d < near or d > far:
			continue
		var crowded := false
		for o in riders:
			if not o.is_empty() and int(o["road"]) == ri and absf(_ahead(ri, s, float(o["s"]), 1)) < SPAWN_GAP:
				crowded = true
		if crowded:
			continue
		var dir := 1 if _rng.randf() < 0.5 else -1
		if _heads_into_yard(ri, s, dir):
			dir = -dir
			if _heads_into_yard(ri, s, dir):
				continue
		_seq += 1
		var look := _rng.randi() % 100000
		var b := busy(p)
		var kind := "bike"
		if _rng.randf() >= lerpf(BIKE_SHARE.y, BIKE_SHARE.x, b):
			kind = TrafficVehicle.pick_kind(_rng, b > 0.5)
		var cruise := _rng.randf_range(12.5, 20.0) * (0.85 if float(r["hw"]) < 3.4 else 1.0)
		var pace := TrafficVehicle.pick_pace(_rng, kind) if kind != "bike" else 1.0
		if kind != "bike":
			cruise = pace * limit_at(p)
		riders[slot] = {"road": ri, "s": s, "dir": dir, "v": cruise * 0.8, "seed": look, "cruise": cruise,
			"pace": pace, "kind": kind, "turn": {}, "round": -1.0}
		return slot
	return -1


## Host: rides one rider on along its road for `delta` seconds.
func _drive(slot: int, d: Dictionary, delta: float) -> void:
	var ri := int(d["road"])
	var r := _road(ri)
	var dir := int(d["dir"])
	var v := float(d["v"])
	var n := (r["xz"] as PackedVector2Array).size()
	var length := float(r["length"])
	var people := _people()
	var here := _rider_point(d)
	if _nearest_person(here, people) > DESPAWN:
		riders[slot] = {}
		return
	var tr := traits_of(d)
	var grip := float(tr["grip"])
	var brake := float(tr["brake"])
	var bike := kind_of(d) == "bike"
	d["ind"] = 0
	# The pace it can take now: its own cruise, the bends ahead, the junction it's turning
	# off at, a dead end or the edge of the yard it turns round before.
	var allow := float(d["cruise"]) if bike else float(d.get("pace", 1.0)) * limit_at(here)
	var i0 := _i(ri, float(d["s"]))
	var kk: PackedFloat32Array = _k[ri]
	# The road ahead is looked over every SCAN_EVERY seconds (and straight away on a new road),
	# allowing for how far it goes before the next look.
	var scan_key := ri * 2 + (1 if dir > 0 else 0)
	d["scan_t"] = float(d.get("scan_t", 0.0)) - delta
	if float(d["scan_t"]) <= 0.0 or int(d.get("scan_key", -1)) != scan_key:
		d["scan_t"] = SCAN_EVERY
		d["scan_key"] = scan_key
		d["scan_allow"] = _scan(d, ri, i0, dir, v, grip, brake)
	allow = minf(allow, float(d["scan_allow"]))
	if not (d["turn"] as Dictionary).is_empty():
		var gap := absf(_ahead(ri, float(d["s"]), float(d["turn"]["at"]), dir))
		allow = minf(allow, sqrt(TURN_SPEED * TURN_SPEED + 2.0 * brake * gap))
		if gap < 60.0:
			# Indicating which way it's turning off.
			var f := road_dir(ri, float(d["turn"]["at"])) * dir
			var to := road_dir(int(d["turn"]["road"]), float(d["turn"]["s"]) + 3.0 * int(d["turn"]["dir"])) * int(d["turn"]["dir"])
			d["ind"] = 1 if f.cross(to) > 0.0 else -1
	if float(d["round"]) >= 0.0:
		var gap := maxf(_ahead(ri, float(d["s"]), float(d["round"]), dir), 0.0)
		allow = minf(allow, sqrt(ROUND_SPEED * ROUND_SPEED + 2.0 * brake * gap))
		if gap < 40.0:
			d["ind"] = 1   # round to the right, across the road
		if gap < 1.0:
			# Round in the road and back the way it came.
			d["dir"] = -dir
			d["round"] = -1.0
			d["v"] = minf(v, ROUND_SPEED)
			return
	# Something in the lane ahead: hang back a gap behind it (bumper to bumper, longer at speed).
	var fwd2 := road_dir(ri, float(d["s"])) * dir
	var fwd := Vector3(fwd2.x, 0.0, fwd2.y)
	# It keeps GAP plus HEADWAY seconds of the other's speed behind it, and never closes faster
	# than it could stop in before the gap runs out if the other stopped dead.
	var mine := half_length(d)
	var look := maxf(45.0, v * v / (2.0 * brake) + GAP + 15.0)
	for o in _users(slot):
		var off: Vector3 = o[0] - here
		var along := off.dot(fwd)
		var other: Dictionary = riders[int(o[2])] if int(o[2]) >= 0 else {}
		if not other.is_empty() and int(other["road"]) == ri:
			# On the same road: by how far along it they are (round the bends too), in this lane only.
			if int(other["dir"]) != dir:
				continue
			along = _ahead(ri, float(d["s"]), float(other["s"]), dir)
			off = fwd * along
		var clear := along - mine - float(o[1])
		if along > 0.0 and clear < look and (off - fwd * along).length() < 2.4 and absf(off.y) < 3.0:
			var vo := maxf((o[3] as Vector3).dot(fwd), 0.0) if other.is_empty() or int(other["road"]) != ri else float(other["v"])
			var want := GAP + HEADWAY * vo
			if clear > want:
				allow = minf(allow, sqrt(vo * vo + 2.0 * brake * (clear - want)))
			else:
				allow = minf(allow, vo * maxf(clear - GAP, 0.0) / maxf(want - GAP, 0.01))
	# Turning off onto a road with someone just there: wait at the junction till it's clear.
	var turning: Dictionary = d["turn"]
	if not turning.is_empty():
		var gap := absf(_ahead(ri, float(d["s"]), float(turning["at"]), dir))
		# (Someone just pulled away along it is always waited for; anyone else not for ever, as
		# two waiting on each other go after a few seconds.)
		var taken := _taken(int(turning["road"]), float(turning["s"]), int(turning["dir"]), slot, gap)
		if gap < 30.0 and (taken == 1 or (taken == 2 and float(d.get("waited", 0.0)) < 4.0)):
			allow = minf(allow, sqrt(2.0 * brake * maxf(gap - 4.0, 0.0)))
			if v < 0.5:
				d["waited"] = float(d.get("waited", 0.0)) + delta
	else:
		d.erase("waited")
	v = move_toward(v, allow, (brake * 1.6 if allow < v else float(tr["accel"])) * delta)
	# A kink it couldn't see coming (just round a junction onto a new road): scrub off what it
	# must so it never corners harder than a rider would.
	var k_now := absf(kk[i0])
	var i1 := i0 + dir   # and the next sample, which this step may ride onto
	if r["closed"]:
		i1 = posmod(i1, n)
	if i1 >= 0 and i1 < n:
		k_now = maxf(k_now, absf(kk[i1]))
	if v * v * k_now > grip * 1.5:
		v = sqrt(grip * 1.5 / k_now)
	d["v"] = v
	var s := float(d["s"]) + dir * v * delta
	# The junction it's turning off at: onto the other road there.
	var turn: Dictionary = d["turn"]
	if not turn.is_empty() and _ahead(ri, float(d["s"]), float(turn["at"]), dir) <= v * delta:
		d["road"] = int(turn["road"])
		d["s"] = float(turn["s"])
		d["dir"] = int(turn["dir"])
		d["turn"] = {}
		return
	if not r["closed"] and (s <= 0.0 or s >= length):
		var join := _end_join(ri, dir)
		if join.is_empty():
			d["s"] = clampf(s, 0.0, length)
			d["dir"] = -dir
			return
		# On to the road this one leaves from or joins, whichever way doesn't head into the yard.
		var pr := int(join["road"])
		var ps := float(join["i"]) * _step(pr)
		var pd := 1 if _rng.randf() < 0.5 else -1
		if _heads_into_yard(pr, ps, pd):
			pd = -pd
		# Someone just there on it: wait at the end of this road till they've pulled away.
		if _taken(pr, ps, pd, slot) == 1:
			d["s"] = clampf(s, 0.0, length)
			d["v"] = 0.0
			return
		d["road"] = pr
		d["s"] = ps
		d["dir"] = pd
		return
	d["s"] = _wrap_s(ri, s)


## Looks along road `ri` ahead from sample `i0`: the bends, the end of the road, a dead end or
## the edge of the yard to turn round before, and the junctions to make its mind up about.
## Returns the pace that lets it take them all, allowing for SCAN_EVERY seconds more road.
func _scan(d: Dictionary, ri: int, i0: int, dir: int, v: float, grip: float, brake: float) -> float:
	var r := _road(ri)
	var n := (r["xz"] as PackedVector2Array).size()
	var step := _step(ri)
	var length := float(r["length"])
	var blocked: PackedByteArray = _blocked[ri]
	var at: Dictionary = _junctions[ri]
	var kk: PackedFloat32Array = _k[ri]
	var allow := INF
	var early := v * SCAN_EVERY
	var reach := maxf(40.0, v * v / (2.0 * brake) + 15.0) + early
	var steps := int(reach / step) + 1
	for k in range(0, steps):
		var j := i0 + k * dir
		var dist := k * step
		var room := maxf(dist - early, 0.0)
		if r["closed"]:
			j = posmod(j, n)
		elif j < 0 or j >= n:
			if _end_join(ri, dir).is_empty():
				if float(d["round"]) < 0.0:
					d["round"] = 0.0 if dir < 0 else length
			else:
				# The end of the road, where it joins another: slow to turn onto it.
				allow = minf(allow, sqrt(TURN_SPEED * TURN_SPEED + 2.0 * brake * maxf(room - step, 0.0)))
			break
		var bend := sqrt(grip / maxf(absf(kk[j]), 0.0005))
		allow = minf(allow, sqrt(bend * bend + 2.0 * brake * room))
		if blocked[j]:
			if float(d["round"]) < 0.0 and (d["turn"] as Dictionary).is_empty():
				d["round"] = _wrap_s(ri, float(d["s"]) + dir * maxf(dist - 6.0, 0.0))
			break
		if k > 0 and at.has(j) and (d["turn"] as Dictionary).is_empty() and float(d["round"]) < 0.0 \
				and d.get("decided", Vector2i(-1, -1)) != Vector2i(ri, j):
			d["decided"] = Vector2i(ri, j)   # made up its mind about this one: don't ask again
			_choose_turn(d, ri, j, dir)
	return allow


## Whether anyone else is on road `ri` near `s`, for someone `gap` short of turning onto it
## there going `dir`: 1 for one just ahead going the same way (or close behind, coming on), or
## turning onto it there too and nearer its junction (it goes first), 2 for anyone else near,
## 0 when it's clear.
func _taken(ri: int, s: float, dir: int, skip_slot: int, gap := INF) -> int:
	var out := 0
	for slot in MAX_RIDERS:
		var o: Dictionary = riders[slot]
		if slot == skip_slot or o.is_empty():
			continue
		var t: Dictionary = o["turn"]
		if not t.is_empty() and int(t["road"]) == ri and absf(float(t["s"]) - s) < 10.0:
			var theirs := absf(_ahead(int(o["road"]), float(o["s"]), float(t["at"]), int(o["dir"])))
			if theirs < gap or (theirs == gap and slot < skip_slot):
				return 1
		if int(o["road"]) != ri:
			continue
		var along := _ahead(ri, s, float(o["s"]), dir)
		# Coming up behind, it's taken for as long as they'd need to stop short of it as well.
		var ov := float(o["v"])
		var behind := 8.0 + half_length(o) + ov * ov / (2.0 * float(traits_of(o)["brake"]))
		if int(o["dir"]) == dir and along > -behind and along < 12.0 + 2.0 * half_length(o):
			return 1
		if absf(along) < 14.0 + half_length(o):
			out = 2
	return out


## The join at the end of road `ri` it's riding towards ({road, i}), or {} for a dead end.
func _end_join(ri: int, dir: int) -> Dictionary:
	var j: Dictionary = _road(ri)["end_join" if dir > 0 else "start_join"]
	return j if not j.is_empty() and _tarmac.has(int(j["road"])) else {}


## How far ahead (in the way it's going) `to` is from `from` along road `ri`, in metres.
func _ahead(ri: int, from: float, to: float, dir: int) -> float:
	var gap := (to - from) * dir
	if _road(ri)["closed"]:
		gap = wrapf(gap, -float(_road(ri)["length"]) * 0.5, float(_road(ri)["length"]) * 0.5)
	return gap


## At the junction at sample `j` of road `ri`: go on, or turn off onto one of the roads there
## (always, when going on heads into the yard).
func _choose_turn(d: Dictionary, ri: int, j: int, dir: int) -> void:
	var options := []
	for e in _junctions[ri][j]:
		var branch := int(e[0])
		if not _heads_into_yard(branch, float(e[1]), int(e[2])):
			options.append(e)
	var on := not _heads_into_yard(ri, float(j) * _step(ri), dir)
	if options.is_empty() or (on and _rng.randf() > TURN_CHANCE):
		return
	var e: Array = options[_rng.randi() % options.size()]
	d["turn"] = {"at": float(j) * _step(ri), "road": int(e[0]), "s": float(e[1]), "dir": int(e[2])}


## Client: rides each rider on along its road between the host's updates.
func _coast(d: Dictionary, delta: float) -> void:
	var ri := int(d["road"])
	d["s"] = _wrap_s(ri, float(d["s"]) + int(d["dir"]) * float(d["v"]) * delta)
	if d.has("target"):
		# Ease towards where the host says it is.
		var err := _ahead(ri, float(d["s"]), float(d["target"]), 1)
		d["s"] = _wrap_s(ri, float(d["s"]) + err * (1.0 - exp(-4.0 * delta)))
		d["target"] = _wrap_s(ri, float(d["target"]) + int(d["dir"]) * float(d["v"]) * delta)


# ---------------------------------------------------------------------------- the crew

## Numbers sent for each slot.
const PACKED := 6


## The traffic for the network: [count, then road, s, dir, v, seed, kind for each slot (road -1
## when free); kind is 4 x (0 for a bike, else 1 + its place in VehicleModel.KINDS) + its
## indicator (0 left, 1 off, 2 right)].
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array([float(MAX_RIDERS)])
	for d in riders:
		if d.is_empty():
			out.append_array([-1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		else:
			var code := (VehicleModel.KINDS.find(kind_of(d)) + 1) * 4 + int(d.get("ind", 0)) + 1
			out.append_array([float(d["road"]), float(d["s"]), float(d["dir"]), float(d["v"]), float(d["seed"]), float(code)])
	return out


## Client: the host's riders.
func unpack(state: PackedFloat32Array) -> void:
	if Net.is_host() or state.size() < 1 or not _ready_roads:
		return
	var count := mini(int(state[0]), MAX_RIDERS)
	for slot in count:
		var b := 1 + slot * PACKED
		if state.size() < b + PACKED:
			return
		var ri := int(state[b])
		if ri < 0 or ri >= world.roads.roads.size():
			riders[slot] = {}
			continue
		var d: Dictionary = riders[slot]
		var code := int(state[b + 5])
		var ki := code / 4 - 1
		var kind: String = VehicleModel.KINDS[ki] if ki >= 0 and ki < VehicleModel.KINDS.size() else "bike"
		var fresh := d.is_empty() or int(d["seed"]) != int(state[b + 4]) or int(d["road"]) != ri or kind_of(d) != kind
		if fresh or absf(_ahead(ri, float(d["s"]), state[b + 1], 1)) > 25.0:
			riders[slot] = {"road": ri, "s": state[b + 1], "dir": int(state[b + 2]), "v": state[b + 3], "seed": int(state[b + 4]),
				"cruise": state[b + 3], "kind": kind, "ind": code % 4 - 1, "turn": {}, "round": -1.0, "target": state[b + 1]}
		else:
			d["dir"] = int(state[b + 2])
			d["v"] = state[b + 3]
			d["ind"] = code % 4 - 1
			d["target"] = state[b + 1]


func active_count() -> int:
	var c := 0
	for d in riders:
		if not d.is_empty():
			c += 1
	return c


## Everyone off the roads (the session's over).
func clear() -> void:
	for slot in MAX_RIDERS:
		riders[slot] = {}
	_update_views(0.0)


# ---------------------------------------------------------------------------- drawing

## Where a rider (or a vehicle's middle) is on the road: in their lane, on the surface. A
## vehicle keeps its wheels off the middle line, and inside the road's edge.
func _rider_point(d: Dictionary) -> Vector3:
	var ri := int(d["road"])
	var f := road_dir(ri, float(d["s"])) * int(d["dir"])
	var left := Vector3(f.y, 0.0, -f.x)
	var hw := float(_road(ri)["hw"])
	var lane := hw * LANE
	var k := kind_of(d)
	if k != "bike":
		var half := float(VehicleModel.SPECS[k]["w"])
		lane = minf(maxf(lane, half + 0.2), hw - half - 0.1)
	return road_point(ri, float(d["s"])) + left * lane


## A rider's bike as it looks from its seed: a bike of a style, in a colour, its rider in
## their own jacket. The same on every machine.
static func look_of(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var style: String = PartsDB.STYLES[rng.randi() % PartsDB.STYLES.size()]
	var parts := PartsDB.sanitize_build(Contracts.style_build(style))
	var jackets := [Color(0.07, 0.07, 0.08), Color(0.35, 0.2, 0.12), Color(0.6, 0.08, 0.06), Color(0.12, 0.2, 0.45),
		Color(0.85, 0.85, 0.82), Color(0.2, 0.3, 0.15)]
	return {"style": style, "parts": parts, "paint": Shed.PAINTS[rng.randi() % Shed.PAINTS.size()],
		"jacket": jackets[rng.randi() % jackets.size()]}


func _make_view(slot: int, d: Dictionary) -> Dictionary:
	if kind_of(d) != "bike":
		var car := TrafficVehicle.new()
		car.name = "TrafficVehicle%d" % slot
		car.setup(kind_of(d), int(d["seed"]))
		add_child(car)
		return {"body": car, "car": true, "kind": kind_of(d), "seed": int(d["seed"]), "pos": _rider_point(d), "yaw": _yaw(d),
			"off": Vector3.ZERO, "road": int(d["road"]), "dir": int(d["dir"]), "v": float(d["v"]), "slowing": 0.0}
	var look := look_of(int(d["seed"]))
	var build := BikeBuild.new(look["parts"])
	var body := AnimatableBody3D.new()
	body.name = "TrafficRider%d" % slot
	body.sync_to_physics = false
	body.collision_layer = 2       # with the bikes, so yours runs into it
	body.collision_mask = 0
	body.add_to_group("road_traffic")
	body.set_meta("traffic_seed", int(d["seed"]))   # its bike can be ordered or copied (see BikeCopyView)
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.55, build.wheelbase + 0.45)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(cs)
	var lean := Node3D.new()
	body.add_child(lean)
	var p := _rider_point(d)
	# The bike and its sound come when it's near enough to see (see _dress_view): most start
	# out of sight, and building one is the heavy part.
	return {"body": body, "lean": lean, "model": null, "sound": null, "seed": int(d["seed"]), "build": build, "look": look,
		"pos": p, "yaw": _yaw(d), "off": Vector3.ZERO, "roll": 0.0, "spin": 0.0, "road": int(d["road"]), "dir": int(d["dir"])}


## Draws a rider's bike and starts its engine sound, the first time it comes in sight.
func _dress_view(view: Dictionary) -> void:
	var look: Dictionary = view["look"]
	var build: BikeBuild = view["build"]
	var model := BikeModel.new()
	model.rider_color = look["jacket"]
	model.baked = true   # far fewer draw calls (see BikeModel._bake_static)
	model.position.y = build.rear_radius
	(view["lean"] as Node3D).add_child(model)
	model.build_from(build, look["paint"])
	model.set_lights(true, true)
	view["model"] = model
	if DisplayServer.get_name() != "headless":
		var sound := EngineSound.new()
		sound.volume_db = -6.0
		(view["body"] as Node3D).add_child(sound)
		sound.setup(build, model)
		sound.set_distant_filter(true)
		sound.running = true
		view["sound"] = sound


func _yaw(d: Dictionary) -> float:
	var f := road_dir(int(d["road"]), float(d["s"])) * int(d["dir"])
	return atan2(-f.x, -f.y)


## You nodded or waved at `at`: the nearest biker within NOD_REACH nods back a moment later
## (on your own screen: it's your nod they answer). Returns the slot that will, or -1.
func nod_back(at: Vector3) -> int:
	var best := -1
	var best_d := NOD_REACH
	for slot in MAX_RIDERS:
		var view: Dictionary = _views[slot]
		if view.is_empty() or view.has("car") or view.get("model") == null:
			continue
		var d := (view["pos"] as Vector3).distance_to(at)
		if d < best_d:
			best_d = d
			best = slot
	if best >= 0:
		var model: BikeModel = _views[best]["model"]
		get_tree().create_timer(NOD_BACK_DELAY).timeout.connect(func():
			if is_instance_valid(model):
				model.gesture("nod"))
	return best


func _update_views(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for slot in MAX_RIDERS:
		var d: Dictionary = riders[slot]
		var view: Dictionary = _views[slot]
		if not view.is_empty() and (d.is_empty() or int(view["seed"]) != int(d["seed"]) or str(view.get("kind", "bike")) != kind_of(d)):
			(view["body"] as Node).queue_free()
			_views[slot] = {}
			view = {}
		if d.is_empty():
			continue
		if view.is_empty():
			view = _make_view(slot, d)
			_views[slot] = view
		if view.has("car"):
			_update_car(view, d, delta, cam)
			continue
		var target := _rider_point(d)
		if int(view["road"]) != int(d["road"]) or int(view["dir"]) != int(d["dir"]):
			# Turned off at a junction or round in the road: ease across from where it was.
			view["off"] = (view["pos"] as Vector3) - target
			view["road"] = int(d["road"])
			view["dir"] = int(d["dir"])
		view["off"] = (view["off"] as Vector3) * exp(-2.0 * delta)
		var pos := target + (view["off"] as Vector3)
		view["pos"] = pos
		var yaw := lerp_angle(float(view["yaw"]), _yaw(d), 1.0 - exp(-5.0 * delta))
		view["yaw"] = yaw
		var ri := int(d["road"])
		var v := float(d["v"])
		# Leaning into the bend just ahead, atan(v^2 k / g), no further than a road rider would
		# (Bike.ROAD_LEAN); pitched with the road's slope.
		var k := float((_k[ri] as PackedFloat32Array)[_i(ri, float(d["s"]) + int(d["dir"]) * maxf(v * 0.3, 1.0))]) * int(d["dir"])
		var want := clampf(atan(v * v * k / Bike.G), -Bike.ROAD_LEAN, Bike.ROAD_LEAN)
		var roll := lerpf(float(view["roll"]), want, 1.0 - exp(-4.0 * delta))
		view["roll"] = roll
		var ahead := road_point(ri, float(d["s"]) + int(d["dir"]) * 2.0)
		var behind := road_point(ri, float(d["s"]) - int(d["dir"]) * 2.0)
		var pitch := atan2(ahead.y - behind.y, 4.0)
		var body: AnimatableBody3D = view["body"]
		body.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos)
		(view["lean"] as Node3D).basis = Basis(Vector3.FORWARD, roll)   # + leans right
		var build: BikeBuild = view["build"]
		view["spin"] = float(view["spin"]) + v * delta / maxf(build.rear_radius, 0.2)
		var dist := 0.0 if cam == null else cam.global_position.distance_to(pos)
		var near := dist < DRAW_RANGE
		if near and view["model"] == null:
			_dress_view(view)
		var model: BikeModel = view["model"]
		if model:
			model.visible = near
		if near:
			var steer := clampf(-atan(build.wheelbase * k) * 0.8, -0.5, 0.5)
			model.update_pose_from(steer, float(view["spin"]), float(view["spin"]), 0.0, 0.0, 0.0, clampf(roll / 0.6, -1.0, 1.0) * 0.6)
		var sound: EngineSound = view["sound"]
		if sound:
			# Too far off to hear: its players stop (they come back as it nears).
			sound.running = dist < SOUND_RANGE
			sound.speed = v
			if sound.running:
				sound.gear = EngineSound.gear_for_speed(sound.gear, v, 4.5, 5)
			sound.throttle = 0.35
			sound.rpm = lerpf(build.idle_rpm, build.redline * 0.55, clampf(fmod(v, 4.5) / 4.5 * 0.7 + 0.2, 0.0, 1.0)) \
				if v > 0.5 else build.idle_rpm


## Puts a vehicle where it is on the road, steering round the bend under it, its brake lamps lit
## as it slows and its indicator going as it's about to turn off.
func _update_car(view: Dictionary, d: Dictionary, delta: float, cam: Camera3D) -> void:
	var target := _rider_point(d)
	if int(view["road"]) != int(d["road"]) or int(view["dir"]) != int(d["dir"]):
		view["off"] = (view["pos"] as Vector3) - target
		view["road"] = int(d["road"])
		view["dir"] = int(d["dir"])
	view["off"] = (view["off"] as Vector3) * exp(-2.0 * delta)
	var pos := target + (view["off"] as Vector3)
	view["pos"] = pos
	var yaw := lerp_angle(float(view["yaw"]), _yaw(d), 1.0 - exp(-5.0 * delta))
	view["yaw"] = yaw
	var ri := int(d["road"])
	var dir := int(d["dir"])
	var v := float(d["v"])
	var car: TrafficVehicle = view["body"]
	var half := car.length * 0.5
	var ahead := road_point(ri, float(d["s"]) + dir * half)
	var behind := road_point(ri, float(d["s"]) - dir * half)
	var pitch := atan2(ahead.y - behind.y, maxf(half * 2.0, 1.0))
	# Slowing harder than coasting does: brake lamps on (kept on a moment, and while stopped).
	var dv := (float(view["v"]) - v) / maxf(delta, 0.001)
	view["v"] = v
	view["slowing"] = 0.4 if dv > 0.8 or v < 0.3 else maxf(float(view["slowing"]) - delta, 0.0)
	var k := float((_k[ri] as PackedFloat32Array)[_i(ri, float(d["s"]) + dir * half)]) * dir
	var axles: Array = VehicleModel.SPECS[car.kind]["axles"]
	var steer := clampf(atan((float(axles[1]) - float(axles[0])) * k), -0.6, 0.6)
	var cam_at := cam.global_position if cam else pos + Vector3(0.0, 0.0, 1.0e5)
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos)
	car.drive(xf, v, steer, float(view["slowing"]) > 0.0, int(d.get("ind", 0)), delta, cam_at)
