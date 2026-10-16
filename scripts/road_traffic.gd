class_name RoadTraffic
extends Node3D
## Other bikers out on the riding map's roads, now and then: a few riders (never more than
## MAX_RIDERS) on bikes of every style, riding the tarmac roads in their own lane (it's a
## left-hand road) at a sensible pace of their own, slowing for the bends and leaning into
## them, slowing to turn off at junctions, turning round at a dead end, and braking for
## anyone stopped or slower in the lane ahead. They're solid: ride into one and you crash, as
## you would into anything else.
##
## They keep off the Build Yard (the test area, with the shed, the sales office and the cafe
## and its car park) and the stretch of the loop that runs across it: roads near the yard are
## marked out of bounds, and a rider heading that way turns off at the junction before it.
## They appear out of everyone's sight (SPAWN_NEAR from every player) but near enough to
## someone to be met (SPAWN_FAR), and go when they're far from everyone (DESPAWN).
##
## Host-driven: the host (or a solo game) rides them and sends where each is to the crew a few
## times a second (see pack); everyone else rides them on along their road between updates. A
## rider is only its road, how far along it, which way, its speed and a look seed, so that's
## all that's sent; every machine draws the same rider from the seed.

const MAX_RIDERS := 4
const SEND_EVERY := 0.2
const SPAWN_EVERY := 5.0
const SPAWN_CHANCE := 0.5
const SPAWN_NEAR := 220.0
const SPAWN_FAR := 520.0
const DESPAWN := 700.0
## The Build Yard, and how far round it the roads are out of bounds.
const KEEP_OUT := Rect2(-65.0, 55.0, 130.0, 90.0)
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
## Hitting one faster than this (m/s) throws you off.
const CRASH_SPEED := 4.0

var main: Node
var world: World
## Each slot: {} when free, else {road, s, dir (+1 along the road, -1 against it), v, seed,
## cruise, turn ({} or {at, road, s, dir}: the junction it's turning off at), round (s of
## the dead end or out-of-bounds stretch it's turning round before, or -1), decided (the
## junction it last made its mind up about, Vector2i(road, sample))}.
var riders: Array = []
var _views: Array = []       # per slot: {} or {body, lean, model, sound, seed, pos, yaw, off, roll, spin, road}
var _rng := RandomNumberGenerator.new()
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
	for slot in MAX_RIDERS:
		var d: Dictionary = riders[slot]
		if d.is_empty():
			continue
		if host:
			_drive(slot, d, delta)
		else:
			_coast(d, delta)
	if host:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_EVERY
			if _rng.randf() < SPAWN_CHANCE:
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
			and not b.is_crashed:
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


## The bikes on the road: yours, the crew's and the other riders'.
func _bikes(skip_slot: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if main.get("bike") != null:
		out.append((main.bike as Node3D).global_position)
	for rp in (main.get("remotes") as Dictionary).values():
		if is_instance_valid(rp) and is_instance_valid(rp.get("bike")):
			out.append((rp.bike as Node3D).global_position)
	for slot in MAX_RIDERS:
		if slot != skip_slot and not riders[slot].is_empty():
			out.append(_rider_point(riders[slot]))
	return out


func _nearest_person(p: Vector3, people: Array[Vector3]) -> float:
	var best := INF
	for q in people:
		best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best


## Host: a new rider somewhere out of sight but not too far from someone, riding away from
## the yard. Returns its slot, or -1 when there's no room or nowhere suits.
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
		var dir := 1 if _rng.randf() < 0.5 else -1
		if _heads_into_yard(ri, s, dir):
			dir = -dir
			if _heads_into_yard(ri, s, dir):
				continue
		_seq += 1
		var look := _rng.randi() % 100000
		var cruise := _rng.randf_range(12.5, 20.0) * (0.85 if float(r["hw"]) < 3.4 else 1.0)
		riders[slot] = {"road": ri, "s": s, "dir": dir, "v": cruise * 0.8, "seed": look, "cruise": cruise,
			"turn": {}, "round": -1.0}
		return slot
	return -1


## Host: rides one rider on along its road for `delta` seconds.
func _drive(slot: int, d: Dictionary, delta: float) -> void:
	var ri := int(d["road"])
	var r := _road(ri)
	var dir := int(d["dir"])
	var v := float(d["v"])
	var step := _step(ri)
	var n := (r["xz"] as PackedVector2Array).size()
	var length := float(r["length"])
	var people := _people()
	var here := _rider_point(d)
	if _nearest_person(here, people) > DESPAWN:
		riders[slot] = {}
		return
	# The pace it can take now: its own cruise, the bends ahead, the junction it's turning
	# off at, a dead end or the edge of the yard it turns round before.
	var allow := float(d["cruise"])
	var reach := maxf(40.0, v * v / (2.0 * BRAKE) + 15.0)
	var i0 := _i(ri, float(d["s"]))
	var blocked: PackedByteArray = _blocked[ri]
	var at: Dictionary = _junctions[ri]
	var kk: PackedFloat32Array = _k[ri]
	var steps := int(reach / step) + 1
	for k in range(0, steps):
		var j := i0 + k * dir
		var dist := k * step
		if r["closed"]:
			j = posmod(j, n)
		elif j < 0 or j >= n:
			if _end_join(ri, dir).is_empty():
				if float(d["round"]) < 0.0:
					d["round"] = 0.0 if dir < 0 else length
			else:
				# The end of the road, where it joins another: slow to turn onto it.
				allow = minf(allow, sqrt(TURN_SPEED * TURN_SPEED + 2.0 * BRAKE * maxf(dist - step, 0.0)))
			break
		var bend := sqrt(GRIP / maxf(absf(kk[j]), 0.0005))
		allow = minf(allow, sqrt(bend * bend + 2.0 * BRAKE * dist))
		if blocked[j]:
			if float(d["round"]) < 0.0 and (d["turn"] as Dictionary).is_empty():
				d["round"] = _wrap_s(ri, float(d["s"]) + dir * maxf(dist - 6.0, 0.0))
			break
		if k > 0 and at.has(j) and (d["turn"] as Dictionary).is_empty() and float(d["round"]) < 0.0 \
				and d.get("decided", Vector2i(-1, -1)) != Vector2i(ri, j):
			d["decided"] = Vector2i(ri, j)   # made up its mind about this one: don't ask again
			_choose_turn(d, ri, j, dir)
	if not (d["turn"] as Dictionary).is_empty():
		var gap := absf(_ahead(ri, float(d["s"]), float(d["turn"]["at"]), dir))
		allow = minf(allow, sqrt(TURN_SPEED * TURN_SPEED + 2.0 * BRAKE * gap))
	if float(d["round"]) >= 0.0:
		var gap := maxf(_ahead(ri, float(d["s"]), float(d["round"]), dir), 0.0)
		allow = minf(allow, sqrt(ROUND_SPEED * ROUND_SPEED + 2.0 * BRAKE * gap))
		if gap < 1.0:
			# Round in the road and back the way it came.
			d["dir"] = -dir
			d["round"] = -1.0
			d["v"] = minf(v, ROUND_SPEED)
			return
	# Something in the lane ahead: hang back behind it.
	var fwd2 := road_dir(ri, float(d["s"])) * dir
	var fwd := Vector3(fwd2.x, 0.0, fwd2.y)
	for o in _bikes(slot):
		var off := o - here
		var along := off.dot(fwd)
		if along > 0.0 and along < 40.0 and (off - fwd * along).length() < 2.4 and absf(off.y) < 3.0:
			allow = minf(allow, maxf(0.0, (along - 7.0) * 0.8))
	v = move_toward(v, allow, (BRAKE * 1.6 if allow < v else ACCEL) * delta)
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
		d["road"] = pr
		d["s"] = ps
		d["dir"] = pd
		return
	d["s"] = _wrap_s(ri, s)


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

## The riders for the network: [count, then road, s, dir, v, seed for each slot (road -1 when free)].
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array([float(MAX_RIDERS)])
	for d in riders:
		if d.is_empty():
			out.append_array([-1.0, 0.0, 0.0, 0.0, 0.0])
		else:
			out.append_array([float(d["road"]), float(d["s"]), float(d["dir"]), float(d["v"]), float(d["seed"])])
	return out


## Client: the host's riders.
func unpack(state: PackedFloat32Array) -> void:
	if Net.is_host() or state.size() < 1 or not _ready_roads:
		return
	var count := mini(int(state[0]), MAX_RIDERS)
	for slot in count:
		var b := 1 + slot * 5
		if state.size() < b + 5:
			return
		var ri := int(state[b])
		if ri < 0 or ri >= world.roads.roads.size():
			riders[slot] = {}
			continue
		var d: Dictionary = riders[slot]
		var fresh := d.is_empty() or int(d["seed"]) != int(state[b + 4]) or int(d["road"]) != ri
		if fresh or absf(_ahead(ri, float(d["s"]), state[b + 1], 1)) > 25.0:
			riders[slot] = {"road": ri, "s": state[b + 1], "dir": int(state[b + 2]), "v": state[b + 3], "seed": int(state[b + 4]),
				"cruise": state[b + 3], "turn": {}, "round": -1.0, "target": state[b + 1]}
		else:
			d["dir"] = int(state[b + 2])
			d["v"] = state[b + 3]
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

## Where a rider is on the road: in their lane, on the surface.
func _rider_point(d: Dictionary) -> Vector3:
	var ri := int(d["road"])
	var f := road_dir(ri, float(d["s"])) * int(d["dir"])
	var left := Vector3(f.y, 0.0, -f.x)
	return road_point(ri, float(d["s"])) + left * float(_road(ri)["hw"]) * LANE


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
	var look := look_of(int(d["seed"]))
	var build := BikeBuild.new(look["parts"])
	var body := AnimatableBody3D.new()
	body.name = "TrafficRider%d" % slot
	body.sync_to_physics = false
	body.collision_layer = 2       # with the bikes, so yours runs into it
	body.collision_mask = 0
	body.add_to_group("road_traffic")
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.55, build.wheelbase + 0.45)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(cs)
	var lean := Node3D.new()
	body.add_child(lean)
	var model := BikeModel.new()
	model.rider_color = look["jacket"]
	model.position.y = build.rear_radius
	lean.add_child(model)
	model.build_from(build, look["paint"])
	model.set_lights(true, true)
	var sound: EngineSound = null
	if DisplayServer.get_name() != "headless":
		sound = EngineSound.new()
		sound.volume_db = -6.0
		body.add_child(sound)
		sound.setup(build, model)
		sound.set_distant_filter(true)
		sound.running = true
	var p := _rider_point(d)
	return {"body": body, "lean": lean, "model": model, "sound": sound, "seed": int(d["seed"]), "build": build,
		"pos": p, "yaw": _yaw(d), "off": Vector3.ZERO, "roll": 0.0, "spin": 0.0, "road": int(d["road"]), "dir": int(d["dir"])}


func _yaw(d: Dictionary) -> float:
	var f := road_dir(int(d["road"]), float(d["s"])) * int(d["dir"])
	return atan2(-f.x, -f.y)


func _update_views(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for slot in MAX_RIDERS:
		var d: Dictionary = riders[slot]
		var view: Dictionary = _views[slot]
		if not view.is_empty() and (d.is_empty() or int(view["seed"]) != int(d["seed"])):
			(view["body"] as Node).queue_free()
			_views[slot] = {}
			view = {}
		if d.is_empty():
			continue
		if view.is_empty():
			view = _make_view(slot, d)
			_views[slot] = view
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
		# Leaning into the bend just ahead, atan(v^2 k / g); pitched with the road's slope.
		var k := float((_k[ri] as PackedFloat32Array)[_i(ri, float(d["s"]) + int(d["dir"]) * maxf(v * 0.3, 1.0))]) * int(d["dir"])
		var want := clampf(atan(v * v * k / Bike.G), -0.7, 0.7)
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
		var model: BikeModel = view["model"]
		var near := cam == null or cam.global_position.distance_to(pos) < DRAW_RANGE
		model.visible = near
		if near:
			var steer := clampf(-atan(build.wheelbase * k) * 0.8, -0.5, 0.5)
			model.update_pose_from(steer, float(view["spin"]), float(view["spin"]), 0.0, 0.0, 0.0, clampf(roll / 0.6, -1.0, 1.0) * 0.6)
		var sound: EngineSound = view["sound"]
		if sound:
			sound.speed = v
			sound.gear = clampi(1 + int(v / 4.5), 1, 5)
			sound.throttle = 0.35
			sound.rpm = lerpf(build.idle_rpm, build.redline * 0.55, clampf(fmod(v, 4.5) / 4.5 * 0.7 + 0.2, 0.0, 1.0)) \
				if v > 0.5 else build.idle_rpm
