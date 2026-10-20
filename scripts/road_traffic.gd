class_name RoadTraffic
extends Node3D
## Other traffic out on the riding map's roads, now and then: bikers on bikes of every style,
## cars (hatchbacks, saloons, estates, vans, pickups) and lorries (box lorries, flatbeds,
## tippers), never more than MAX_RIDERS of them at once. They ride the tarmac roads in their
## own lane (it's a left-hand road) at a sensible pace of their own (cars a bit slower than the
## bikers on the bends, lorries slower again), slowing for the bends and junctions (bikes lean
## into the bends), turning off at junctions, turning round at a dead end, and braking for
## anyone stopped or slower in the lane ahead. They're solid: ride into one and you crash, as
## you would into anything else.
##
## Now and then a few bikers come together, a group of two to five spread out along the road
## in a loose stagger (a little to either side of the lane, 8 to 25 m apart) at much the same
## pace: the one in front eases off if the others fall behind, the one at the back catches up,
## and they all make the same choice at a junction, so they stay together.
##
## Cars and lorries keep to the tarmac roads wide enough for them (half width CAR_MIN_HW);
## dirt tracks are for bikes only. Nothing here depends on which roads there are, so it works
## the same on the hand-laid map and on a real-world route (WorldLayout.pack), where the roads
## are many short ones: it uses only each road's kind, width and joins.
##
## They keep off the Build Yard (the test area, with the shed, the sales office and the cafe
## and its car park) and the stretch of the loop that runs across it: roads near the yard are
## marked out of bounds, and anyone heading that way turns off at the junction before it.
## They appear out of everyone's sight (SPAWN_NEAR from every player) but near enough to
## someone to be met (SPAWN_FAR), and go when they're far from everyone (DESPAWN).
##
## Host-driven: the host (or a solo game) drives them and sends where each is to the crew a few
## times a second (see pack); everyone else drives them on along their road between updates. A
## vehicle is only its road, how far along it, which way, its speed and a look seed, so that's
## all that's sent; every machine draws the same one from the seed. What it is (bike, car or
## lorry), its look and which side of its lane a biker keeps all come from the seed too (the
## last digit says which kind: see kind_of), so the numbers sent are the same as ever.

const MAX_RIDERS := 12
## No more than this many of them can be bikes (they're the dear ones to draw).
const MAX_BIKES := 7
const SEND_EVERY := 0.2
const SPAWN_EVERY := 5.0
const SPAWN_CHANCE := 0.5
## When a bike is the next to appear, the chance it comes with a group instead of on its own.
const GROUP_CHANCE := 0.3
## A group is this many riders, spaced this far apart (m) along the road.
const GROUP_MIN := 2
const GROUP_MAX := 5
const GROUP_GAP_MIN := 8.0
const GROUP_GAP_MAX := 25.0
## A group's front rider eases off when the nearest behind is further than this (m), and the
## one at the back catches up when the nearest ahead is.
const GROUP_LOOSE := 40.0
const GROUP_CLOSE := 30.0
## Cars and lorries use only the tarmac roads at least this wide (half width, m) and this long.
const CAR_MIN_HW := 3.0
const CAR_MIN_LENGTH := 100.0
## The chance the next to appear is a car, or a lorry (otherwise a bike).
const CAR_SHARE := 0.38
const TRUCK_SHARE := 0.12
const SPAWN_NEAR := 220.0
const SPAWN_FAR := 520.0
const DESPAWN := 700.0
## The Build Yard, and how far round it the roads are out of bounds.
const KEEP_OUT := Rect2(-65.0, 55.0, 130.0, 90.0)
const KEEP_OUT_MARGIN := 25.0
## How each kind drives: how hard it corners (sideways m/s^2), brakes and pulls away (m/s^2),
## its range of cruising pace (m/s), the pace it takes a junction it turns off at (m/s), the
## pace it takes past any junction (0 for no slowing), the gap it keeps behind what's ahead (m)
## and how far left of the middle of the road it keeps (as a share of the road's half width).
const STATS := {
	"bike": {"grip": 3.0, "brake": 3.0, "accel": 2.0, "lo": 12.5, "hi": 20.0, "turn": 6.0, "pass": 0.0, "gap": 7.0, "lane": 0.45},
	"car": {"grip": 2.4, "brake": 3.0, "accel": 1.8, "lo": 11.0, "hi": 17.0, "turn": 5.5, "pass": 9.0, "gap": 7.5, "lane": 0.45},
	"truck": {"grip": 1.8, "brake": 2.2, "accel": 1.0, "lo": 8.0, "hi": 12.5, "turn": 4.5, "pass": 6.5, "gap": 11.0, "lane": 0.52},
}
## The pace they take a dead end they turn round in (m/s).
const ROUND_SPEED := 2.5
## How far a biker keeps to one side or other of their lane's middle (m), by their seed.
const STAGGER := 0.3
## The chance a vehicle turns off at a junction they could go on through.
const TURN_CHANCE := 0.4
## Drawn only within this of the camera.
const DRAW_RANGE := 450.0
## Hitting one faster than this (m/s) throws you off.
const CRASH_SPEED := 4.0
## How far ahead (m) they watch for anything in their lane.
const LOOK_AHEAD := 80.0

var main: Node
var world: World
## The chance a new biker comes with a group (see GROUP_CHANCE), and the share of new vehicles
## that are cars and lorries: set them to change the mix.
var group_chance := GROUP_CHANCE
var car_share := CAR_SHARE
var truck_share := TRUCK_SHARE
## Each slot: {} when free, else {road, s, dir (+1 along the road, -1 against it), v, seed,
## cruise, turn ({} or {at, road, s, dir}: the junction it's turning off at), round (s of
## the dead end or out-of-bounds stretch it's turning round before, or -1), decided (the
## junction it last made its mind up about, Vector2i(road, sample)), group (0, or the number of
## the group of bikers it's riding with, on the host)}.
var riders: Array = []
var _views: Array = []       # per slot: {} or {body, lean, kind, model, sound, seed, pos, yaw, off, roll, spin, road, ...}
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 2.0
var _send_timer := 0.0
var _groups := 0             # groups handed out
## Per road: the curvature at each sample (1/m, + bending right going along it), which samples
## are out of bounds, and the junctions on it (sample -> [[road, s, dir], ...]).
var _k: Array = []
var _blocked: Array = []
var _junctions: Array = []
var _tarmac: Array[int] = []
## The tarmac roads cars and lorries may use.
var _car_roads: Array[int] = []
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
	_car_roads.clear()
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
			if float(r["hw"]) >= CAR_MIN_HW and float(r["length"]) >= CAR_MIN_LENGTH:
				_car_roads.append(ri)
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


# ---------------------------------------------------------------------------- the kinds

## What a look seed makes: "bike" (0 to 5 as its last digit), "car" (6 to 8) or "truck" (9).
static func kind_of(seed_value: int) -> String:
	var m := posmod(seed_value, 10)
	return "bike" if m < 6 else ("car" if m < 9 else "truck")


## Which side of its lane a biker keeps, from its seed (m, + towards the left verge): they
## alternate a little in a group, which picks its seeds to match. Cars and lorries keep the middle.
static func lane_shift(seed_value: int) -> float:
	if kind_of(seed_value) != "bike":
		return 0.0
	return STAGGER if (seed_value / 10) % 2 == 0 else -STAGGER


## Whether road `ri` is one this kind may drive: any tarmac road for a bike, the wider ones for
## the rest (never a dirt track).
func _usable(ri: int, kind: String) -> bool:
	if not _tarmac.has(ri):
		return false
	return kind == "bike" or float(_road(ri)["hw"]) >= CAR_MIN_HW


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
				spawn_next()
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


## Everything on the road a vehicle might have to stop for: yours, the crew's and everyone
## else's bikes, cars and lorries (but not `skip_slot`), each as [position, way it's heading
## (Vector3.ZERO when that's not known), speed (m/s), road (-1 when not one of ours), how far
## along it, and which way along it].
func _obstacles(skip_slot: int) -> Array:
	var out := []
	var mine = main.get("bike")
	if mine != null and is_instance_valid(mine):
		var f := Vector3.ZERO
		var v := 0.0
		if mine is Bike:
			f = -(mine as Bike).global_transform.basis.z
			f.y = 0.0
			f = f.normalized()
			v = (mine as Bike).linear_velocity.length()
		out.append([(mine as Node3D).global_position, f, v, -1, 0.0, 0])
	for rp in (main.get("remotes") as Dictionary).values():
		if is_instance_valid(rp) and is_instance_valid(rp.get("bike")):
			out.append([(rp.bike as Node3D).global_position, Vector3.ZERO, 0.0, -1, 0.0, 0])
	for slot in MAX_RIDERS:
		if slot != skip_slot and not riders[slot].is_empty():
			var o: Dictionary = riders[slot]
			out.append([_rider_point(o), _heading(o), float(o["v"]), int(o["road"]), float(o["s"]), int(o["dir"])])
	return out


## The way a vehicle is heading (unit, flat).
func _heading(d: Dictionary) -> Vector3:
	var f := road_dir(int(d["road"]), float(d["s"])) * int(d["dir"])
	return Vector3(f.x, 0.0, f.y)


func _nearest_person(p: Vector3, people: Array[Vector3]) -> float:
	var best := INF
	for q in people:
		best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best


## Host: the next thing to appear, chosen by the mix: a bike (perhaps with a group), a car or
## a lorry. Returns how many appeared.
func spawn_next() -> int:
	var kind := _pick_kind()
	if kind == "bike" and _rng.randf() < group_chance:
		var n := spawn_group()
		if n > 0:
			return n
	return 1 if spawn_one(SPAWN_NEAR, SPAWN_FAR, kind) >= 0 else 0


func _pick_kind() -> String:
	var roll := _rng.randf()
	var kind := "bike"
	if roll < truck_share:
		kind = "truck"
	elif roll < truck_share + car_share:
		kind = "car"
	if (kind != "bike" and _car_roads.is_empty()) or (kind == "bike" and count_kind("bike") >= MAX_BIKES):
		kind = "car" if not _car_roads.is_empty() else "bike"
	return kind


## How many of the vehicles on the road are `kind` ("bike", "car" or "truck").
func count_kind(kind: String) -> int:
	var c := 0
	for d in riders:
		if not d.is_empty() and kind_of(int(d["seed"])) == kind:
			c += 1
	return c


func _free_slots() -> Array[int]:
	var out: Array[int] = []
	for i in MAX_RIDERS:
		if (riders[i] as Dictionary).is_empty():
			out.append(i)
	return out


## A look seed for a `kind` of vehicle; a bike's says which side of its lane it keeps with
## `side` 0 or 1 (or at random for -1).
func _seed_for(kind: String, side := -1) -> int:
	var base := _rng.randi() % 100000
	if side >= 0:
		base = base - base % 2 + side
	var code := _rng.randi() % 6 if kind == "bike" else (6 + _rng.randi() % 3 if kind == "car" else 9)
	return base * 10 + code


## Host: somewhere out of sight but not too far from someone for a `kind` of vehicle to go,
## with `behind` metres of road clear behind it, heading away from the yard: {road, s, dir},
## or {} when nowhere suits.
func _find_spot(kind: String, near: float, far: float, behind := 0.0) -> Dictionary:
	if not _ready_roads:
		setup_roads()
	var roads := _tarmac if kind == "bike" else _car_roads
	if not _ready_roads or roads.is_empty():
		return {}
	var people := _people()
	if people.is_empty():
		return {}
	var others := _obstacles(-1)
	for attempt in 60:
		var ri: int = roads[_rng.randi() % roads.size()]
		var r := _road(ri)
		var n := (r["xz"] as PackedVector2Array).size()
		var i := _rng.randi() % n
		if attempt % 2 == 1:
			# Half the tries look for a road at a random spot the right distance from someone, as on
			# a map of many roads spread far apart picking one at random rarely lands near anybody.
			var c := people[_rng.randi() % people.size()]
			var a := _rng.randf() * TAU
			var reach := _rng.randf_range(near, far)
			var hit := world.roads.nearest(c.x + cos(a) * reach, c.z + sin(a) * reach, 60.0, "tarmac")
			if hit.is_empty() or not roads.has(int(hit["road"])):
				continue
			ri = int(hit["road"])
			r = _road(ri)
			n = (r["xz"] as PackedVector2Array).size()
			i = int(hit["i"]) % n
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
		if behind > 0.0 and not r["closed"]:
			var back := s - dir * behind
			if back < 4.0 or back > float(r["length"]) - 4.0:
				continue
		var crowded := false
		for o in others:
			if (o[0] as Vector3).distance_to(p) < 16.0:
				crowded = true
				break
		if not crowded:
			return {"road": ri, "s": s, "dir": dir}
	return {}


## Host: a new vehicle somewhere out of sight but not too far from someone, heading away from
## the yard: a `kind` of "bike", "car" or "truck" (by the mix when left out). Returns its slot,
## or -1 when there's no room or nowhere suits.
func spawn_one(near := SPAWN_NEAR, far := SPAWN_FAR, kind := "") -> int:
	var free := _free_slots()
	if free.is_empty():
		return -1
	if kind == "":
		kind = _pick_kind()
	if kind == "bike" and count_kind("bike") >= MAX_BIKES:
		return -1
	var spot := _find_spot(kind, near, far)
	if spot.is_empty():
		return -1
	var st: Dictionary = STATS[kind]
	var hw := float(_road(int(spot["road"]))["hw"])
	var cruise := _rng.randf_range(float(st["lo"]), float(st["hi"])) * (0.85 if hw < 3.4 else 1.0)
	_place(free[0], kind, int(spot["road"]), float(spot["s"]), int(spot["dir"]), _seed_for(kind), cruise, 0)
	return free[0]


## Host: a group of bikers (`count` of them, or two to five at random) together on one road in
## a loose stagger. Returns how many appeared, or 0 when there isn't room or nowhere suits.
func spawn_group(near := SPAWN_NEAR, far := SPAWN_FAR, count := 0) -> int:
	var free := _free_slots()
	var room := mini(free.size(), MAX_BIKES - count_kind("bike"))
	var n := mini(count if count > 0 else _rng.randi_range(GROUP_MIN, GROUP_MAX), room)
	if n < GROUP_MIN:
		return 0
	var gaps: Array[float] = []
	var span := 0.0
	for j in n - 1:
		gaps.append(_rng.randf_range(GROUP_GAP_MIN, GROUP_GAP_MAX))
		span += gaps[j]
	var spot := _find_spot("bike", near, far, span + 6.0)
	if spot.is_empty():
		return 0
	var ri := int(spot["road"])
	var dir := int(spot["dir"])
	var r := _road(ri)
	var st: Dictionary = STATS["bike"]
	# They all go at much the same pace.
	var pace := _rng.randf_range(float(st["lo"]), float(st["hi"])) * (0.85 if float(r["hw"]) < 3.4 else 1.0)
	_groups += 1
	var placed := 0
	var cum := 0.0
	for j in n:
		if j > 0:
			cum += gaps[j - 1]
		var s := float(spot["s"]) - dir * cum
		if not r["closed"] and (s < 2.0 or s > float(r["length"]) - 2.0):
			break
		s = _wrap_s(ri, s)
		if (_blocked[ri] as PackedByteArray)[_i(ri, s)]:
			break
		_place(free[j], "bike", ri, s, dir, _seed_for("bike", j % 2), pace * _rng.randf_range(0.96, 1.04), _groups)
		placed += 1
	if placed < GROUP_MIN:
		for j in placed:
			riders[free[j]] = {}
		return 0
	return placed


func _place(slot: int, kind: String, ri: int, s: float, dir: int, look_seed: int, cruise: float, group: int) -> void:
	riders[slot] = {"road": ri, "s": s, "dir": dir, "v": cruise * 0.8, "seed": look_seed, "cruise": cruise,
		"turn": {}, "round": -1.0, "group": group}


## A random number generator for a choice a whole group makes the same way: the same for
## every member (and different for each `salt`), so they stay together.
func _group_rng(d: Dictionary, salt: int) -> RandomNumberGenerator:
	if int(d.get("group", 0)) == 0:
		return _rng
	var g := RandomNumberGenerator.new()
	g.seed = int(d["group"]) * 100003 + salt
	return g


## How fast a group's rider may go to stay with the others: its own cruise, less when the
## nearest behind is far back, more when the nearest ahead is far ahead.
func _group_pace(slot: int, d: Dictionary, here: Vector3, fwd: Vector3) -> float:
	var cruise := float(d["cruise"])
	var group := int(d.get("group", 0))
	if group == 0:
		return cruise
	var behind := INF
	var ahead := INF
	for o in MAX_RIDERS:
		var od: Dictionary = riders[o]
		if o == slot or od.is_empty() or int(od.get("group", 0)) != group:
			continue
		var off := _rider_point(od) - here
		var dist := Vector2(off.x, off.z).length()
		if off.dot(fwd) < 0.0:
			behind = minf(behind, dist)
		else:
			ahead = minf(ahead, dist)
	if behind < 150.0 and behind > GROUP_LOOSE:
		return cruise * maxf(0.5, 1.0 - (behind - GROUP_LOOSE) / 60.0)
	if ahead < 150.0 and ahead > GROUP_CLOSE:
		return cruise * 1.1
	return cruise


## Host: drives one vehicle on along its road for `delta` seconds.
func _drive(slot: int, d: Dictionary, delta: float) -> void:
	var ri := int(d["road"])
	var r := _road(ri)
	var dir := int(d["dir"])
	var v := float(d["v"])
	var kind := kind_of(int(d["seed"]))
	var st: Dictionary = STATS[kind]
	var grip := float(st["grip"])
	var brake := float(st["brake"])
	var step := _step(ri)
	var n := (r["xz"] as PackedVector2Array).size()
	var length := float(r["length"])
	var people := _people()
	var here := _rider_point(d)
	if _nearest_person(here, people) > DESPAWN:
		riders[slot] = {}
		return
	var fwd := _heading(d)
	# The pace it can take now: its own cruise (kept to the group's), the bends ahead, the
	# junctions, the one it's turning off at, a dead end or the edge of the yard it turns round before.
	var allow := _group_pace(slot, d, here, fwd)
	var pass_speed := float(st["pass"])
	var turn_speed := float(st["turn"])
	var reach := maxf(40.0, v * v / (2.0 * brake) + 15.0)
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
			if _end_join(ri, dir, kind).is_empty():
				if float(d["round"]) < 0.0:
					d["round"] = 0.0 if dir < 0 else length
			else:
				# The end of the road, where it joins another: slow to turn onto it.
				allow = minf(allow, sqrt(turn_speed * turn_speed + 2.0 * brake * maxf(dist - step, 0.0)))
			break
		var bend := sqrt(grip / maxf(absf(kk[j]), 0.0005))
		allow = minf(allow, sqrt(bend * bend + 2.0 * brake * dist))
		if blocked[j]:
			if float(d["round"]) < 0.0 and (d["turn"] as Dictionary).is_empty():
				d["round"] = _wrap_s(ri, float(d["s"]) + dir * maxf(dist - 6.0, 0.0))
			break
		if k > 0 and at.has(j):
			if pass_speed > 0.0:
				# Cars and lorries take it steadily: someone may pull out.
				allow = minf(allow, sqrt(pass_speed * pass_speed + 2.0 * brake * dist))
			if (d["turn"] as Dictionary).is_empty() and float(d["round"]) < 0.0 \
					and d.get("decided", Vector2i(-1, -1)) != Vector2i(ri, j):
				d["decided"] = Vector2i(ri, j)   # made up its mind about this one: don't ask again
				_choose_turn(d, ri, j, dir, kind)
	if not (d["turn"] as Dictionary).is_empty():
		var gap := absf(_ahead(ri, float(d["s"]), float(d["turn"]["at"]), dir))
		allow = minf(allow, sqrt(turn_speed * turn_speed + 2.0 * brake * gap))
	if float(d["round"]) >= 0.0:
		var gap := maxf(_ahead(ri, float(d["s"]), float(d["round"]), dir), 0.0)
		allow = minf(allow, sqrt(ROUND_SPEED * ROUND_SPEED + 2.0 * brake * gap))
		if gap < 1.0:
			# Round in the road and back the way it came.
			d["dir"] = -dir
			d["round"] = -1.0
			d["v"] = minf(v, ROUND_SPEED)
			return
	# Something in the lane ahead: hang back behind it, at its pace if it's moving the same way.
	var keep_gap := float(st["gap"])
	if int(d.get("group", 0)) != 0:
		keep_gap = maxf(keep_gap, GROUP_GAP_MIN)   # a group's bikers don't tail-gate each other
	for o in _obstacles(slot):
		var off: Vector3 = o[0] - here
		var along := off.dot(fwd)
		var f: Vector3 = o[1]
		if int(o[3]) == ri and int(o[5]) == dir:
			# Another on this road going the same way: it's in the lane, however it bends.
			along = _ahead(ri, float(d["s"]), float(o[4]), dir)
		elif int(o[3]) == ri and int(o[5]) != dir and o[3] >= 0:
			continue   # in the other lane
		elif along <= 0.0 or (off - fwd * along).length() >= 1.9 or absf(off.y) >= 3.0:
			continue
		if along <= 0.0 or along >= LOOK_AHEAD:
			continue
		var same_way := f != Vector3.ZERO and f.dot(fwd) > 0.3
		if not same_way and f != Vector3.ZERO and float(o[2]) > 1.0:
			continue   # coming the other way in its own lane
		var lead_v := minf(float(o[2]), float(d["cruise"])) if same_way else 0.0
		allow = minf(allow, lead_v * clampf((along - keep_gap * 0.5) / (keep_gap * 0.5), 0.0, 1.0)
			+ sqrt(2.0 * brake * maxf(along - keep_gap, 0.0)))
	v = move_toward(v, allow, (brake * 1.6 if allow < v else float(st["accel"])) * delta)
	# A kink it couldn't see coming (just round a junction onto a new road): scrub off what it
	# must so it never corners harder than a rider would.
	var k_now := absf(kk[i0])
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
		var join := _end_join(ri, dir, kind)
		if join.is_empty():
			d["s"] = clampf(s, 0.0, length)
			d["dir"] = -dir
			return
		# On to the road this one leaves from or joins, whichever way doesn't head into the yard.
		var pr := int(join["road"])
		var ps := float(join["i"]) * _step(pr)
		var pd := 1 if _group_rng(d, pr).randf() < 0.5 else -1
		if _heads_into_yard(pr, ps, pd):
			pd = -pd
		d["road"] = pr
		d["s"] = ps
		d["dir"] = pd
		return
	d["s"] = _wrap_s(ri, s)


## The join at the end of road `ri` it's driving towards ({road, i}), or {} for a dead end (or
## when the road it joins is no use to a `kind` of vehicle).
func _end_join(ri: int, dir: int, kind := "bike") -> Dictionary:
	var j: Dictionary = _road(ri)["end_join" if dir > 0 else "start_join"]
	return j if not j.is_empty() and _usable(int(j["road"]), kind) else {}


## How far ahead (in the way it's going) `to` is from `from` along road `ri`, in metres.
func _ahead(ri: int, from: float, to: float, dir: int) -> float:
	var gap := (to - from) * dir
	if _road(ri)["closed"]:
		gap = wrapf(gap, -float(_road(ri)["length"]) * 0.5, float(_road(ri)["length"]) * 0.5)
	return gap


## At the junction at sample `j` of road `ri`: go on, or turn off onto one of the roads there
## (always, when going on heads into the yard). A group's riders choose alike.
func _choose_turn(d: Dictionary, ri: int, j: int, dir: int, kind := "bike") -> void:
	var options := []
	for e in _junctions[ri][j]:
		var branch := int(e[0])
		if _usable(branch, kind) and not _heads_into_yard(branch, float(e[1]), int(e[2])):
			options.append(e)
	var on := not _heads_into_yard(ri, float(j) * _step(ri), dir)
	var rng := _group_rng(d, ri * 7919 + j)
	if options.is_empty() or (on and rng.randf() > TURN_CHANCE):
		return
	var e: Array = options[rng.randi() % options.size()]
	d["turn"] = {"at": float(j) * _step(ri), "road": int(e[0]), "s": float(e[1]), "dir": int(e[2])}


## Client: drives each vehicle on along its road between the host's updates.
func _coast(d: Dictionary, delta: float) -> void:
	var ri := int(d["road"])
	d["s"] = _wrap_s(ri, float(d["s"]) + int(d["dir"]) * float(d["v"]) * delta)
	if d.has("target"):
		# Ease towards where the host says it is.
		var err := _ahead(ri, float(d["s"]), float(d["target"]), 1)
		d["s"] = _wrap_s(ri, float(d["s"]) + err * (1.0 - exp(-4.0 * delta)))
		d["target"] = _wrap_s(ri, float(d["target"]) + int(d["dir"]) * float(d["v"]) * delta)


# ---------------------------------------------------------------------------- the crew

## The vehicles for the network: [count, then road, s, dir, v, seed for each slot (road -1 when free)].
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array([float(MAX_RIDERS)])
	for d in riders:
		if d.is_empty():
			out.append_array([-1.0, 0.0, 0.0, 0.0, 0.0])
		else:
			out.append_array([float(d["road"]), float(d["s"]), float(d["dir"]), float(d["v"]), float(d["seed"])])
	return out


## Client: the host's vehicles.
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
				"cruise": state[b + 3], "turn": {}, "round": -1.0, "target": state[b + 1], "group": 0}
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

## Where a vehicle is on the road: in its lane, on the surface.
func _rider_point(d: Dictionary) -> Vector3:
	var ri := int(d["road"])
	var look_seed := int(d.get("seed", 0))
	var f := road_dir(ri, float(d["s"])) * int(d["dir"])
	var left := Vector3(f.y, 0.0, -f.x)
	var lane := float((STATS[kind_of(look_seed)] as Dictionary)["lane"])
	return road_point(ri, float(d["s"])) + left * (float(_road(ri)["hw"]) * lane + lane_shift(look_seed))


## A rider's bike as it looks from its seed: a bike of a style, in a colour, its rider in
## their own jacket. The same on every machine. (A car's or lorry's look is TrafficVehicle.look.)
static func look_of(seed_value: int) -> Dictionary:
	var kind := kind_of(seed_value)
	if kind != "bike":
		return TrafficVehicle.look(kind, seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var style: String = PartsDB.STYLES[rng.randi() % PartsDB.STYLES.size()]
	var parts := PartsDB.sanitize_build(Contracts.style_build(style))
	var jackets := [Color(0.07, 0.07, 0.08), Color(0.35, 0.2, 0.12), Color(0.6, 0.08, 0.06), Color(0.12, 0.2, 0.45),
		Color(0.85, 0.85, 0.82), Color(0.2, 0.3, 0.15)]
	return {"kind": "bike", "style": style, "parts": parts, "paint": Shed.PAINTS[rng.randi() % Shed.PAINTS.size()],
		"jacket": jackets[rng.randi() % jackets.size()]}


func _make_view(slot: int, d: Dictionary) -> Dictionary:
	var look := look_of(int(d["seed"]))
	var kind := str(look["kind"])
	var body := AnimatableBody3D.new()
	body.name = "Traffic%d" % slot
	body.sync_to_physics = false
	body.collision_layer = 2       # with the bikes, so yours runs into it
	body.collision_mask = 0
	body.add_to_group("road_traffic")
	add_child(body)
	var shape := BoxShape3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var lean := Node3D.new()
	body.add_child(lean)
	var view := {"body": body, "lean": lean, "kind": kind, "model": null, "sound": null, "seed": int(d["seed"]), "build": null,
		"wheels": [], "radius": 0.3, "pos": _rider_point(d), "yaw": _yaw(d), "off": Vector3.ZERO, "roll": 0.0, "spin": 0.0,
		"road": int(d["road"]), "dir": int(d["dir"])}
	if kind != "bike":
		var built := TrafficVehicle.build(look)
		var size: Vector3 = built["size"]
		shape.size = Vector3(size.x, size.y, size.z + 0.1)
		cs.position = Vector3(0.0, size.y * 0.5, 0.0)
		lean.add_child(built["root"])
		view["model"] = built["root"]
		view["wheels"] = built["wheels"]
		view["radius"] = float(built["radius"])
		return view
	var build := BikeBuild.new(look["parts"])
	shape.size = Vector3(0.7, 1.55, build.wheelbase + 0.45)
	cs.position = Vector3(0.0, 0.8, 0.0)
	var model := BikeModel.new()
	model.rider_color = look["jacket"]
	model.position.y = build.rear_radius
	lean.add_child(model)
	model.build_from(build, look["paint"])
	model.set_lights(true, true)
	if DisplayServer.get_name() != "headless":
		var sound := EngineSound.new()
		sound.volume_db = -6.0
		body.add_child(sound)
		sound.setup(build, model)
		sound.set_distant_filter(true)
		sound.running = true
		view["sound"] = sound
	view["model"] = model
	view["build"] = build
	return view


func _yaw(d: Dictionary) -> float:
	var f := road_dir(int(d["road"]), float(d["s"])) * int(d["dir"])
	return atan2(-f.x, -f.y)


## How brightly the vehicles' lamps burn: at dusk and in the dark, and a little in heavy rain.
func _lamp_level() -> float:
	var level := 0.0
	if Daylight.current != null:
		level = Daylight.current.lamps
	if Weather.current != null:
		level = maxf(level, clampf((Weather.rain_level() - 0.2) * 1.5, 0.0, 0.8))
	return level


func _update_views(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	TrafficVehicle.set_lamps(_lamp_level())
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
		var dir := int(d["dir"])
		var near := cam == null or cam.global_position.distance_to(pos) < DRAW_RANGE
		(view["model"] as Node3D).visible = near
		var ahead := road_point(ri, float(d["s"]) + dir * 2.0)
		var behind := road_point(ri, float(d["s"]) - dir * 2.0)
		var pitch := atan2(ahead.y - behind.y, 4.0)   # pitched with the road's slope
		var body: AnimatableBody3D = view["body"]
		body.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos)
		if str(view["kind"]) != "bike":
			view["spin"] = float(view["spin"]) + v * delta / float(view["radius"])
			if near:
				for w in view["wheels"]:
					(w as Node3D).rotation.x = -float(view["spin"])
			continue
		# Leaning into the bend just ahead, atan(v^2 k / g).
		var k := float((_k[ri] as PackedFloat32Array)[_i(ri, float(d["s"]) + dir * maxf(v * 0.3, 1.0))]) * dir
		var want := clampf(atan(v * v * k / Bike.G), -0.7, 0.7)
		var roll := lerpf(float(view["roll"]), want, 1.0 - exp(-4.0 * delta))
		view["roll"] = roll
		(view["lean"] as Node3D).basis = Basis(Vector3.FORWARD, roll)   # + leans right
		var build: BikeBuild = view["build"]
		view["spin"] = float(view["spin"]) + v * delta / maxf(build.rear_radius, 0.2)
		var model: BikeModel = view["model"]
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
