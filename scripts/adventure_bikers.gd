class_name AdventureBikers
extends Node3D
## Other bikers out on an adventure's road (Simon: "add other bikers on the adventures so that we
## can ride together if we wish to"): solo riders and little groups of two to four, both ways, on
## bikes of every style, each at a pace of their own for the road (the traffic's limit there, the
## cruisers and classics a bit under it, the sports bikes a bit over), slowing for the bends and
## leaning into them, stopping at the lights, round the roundabouts' islands, hanging back behind
## the traffic and the crew, and a solo rider now and then going past a slower one when the other
## side's clear. A group rides staggered: the leader by the middle line, the next by the kerb a
## second behind, and so on.
##
## Riding with them: come up behind (or alongside) one going your way and keep its pace for
## JOIN_TIME seconds and it joins the crew for a few minutes: it matches your pace and rides in
## a staggered line with you (behind you if you came up behind it, in front if you went past),
## stopping when you stop. Later it waves and peels off: down a side road at a junction, or it
## rides on when you've stopped a while. Coming the other way, a biker often nods as you pass,
## or lifts their left hand off the bars for a wave.
##
## The nod: nod_back(position) (static) has the bikers near a rider who nods or waves at them
## nod back (or wave): it's for the nod key to call, and runs on whoever's machine nodded.
##
## None of it is simulated, as with the traffic (TrafficStream): each is a distance along the road
## (s), a way (dir), a speed and a place across the road (lat), put where it is every frame, so
## the floating origin never moves it. The bikes come from a pool of POOL built behind the fade
## into the adventure (the same looks on every machine, from the route's seed), so nothing's built
## out on the road. Solid for your bike to hit, as the cars are (see AdventureTraffic._on_bike_hit),
## but not while one's riding with the crew.
##
## Co-op: the host rides them, decides who joins whom and when they part, and sends them on the
## end of the traffic's own snapshot (see pack: AdventureTraffic carries it), so everyone sees the
## same bikers in the same places, joining and peeling off together.

static var current: AdventureBikers

## How many bikes there are (and so most out at once: each takes a good part of a tenth of a
## second to build, all of it behind the fade), and how many round the riders.
const POOL := 6
const WANTED := 4
## One riding the same way as the crew but out of sight this long (s) turns off somewhere
## unseen, so there are new faces along the road.
const LINGER := 150.0
const UNSEEN := 350.0
## How often (s) a new rider or group may turn up, and the odds of a group of 1, 2, 3 or 4.
const SPAWN_EVERY := 6.0
const GROUP_ODDS := [0.5, 0.25, 0.15, 0.1]
## A style's pace (times the road's limit); others ride at the limit, give or take the rider.
const STYLE_PACE := {"classic": 0.92, "bobber": 0.92, "chopper": 0.88, "cruiser": 0.9, "scrambler": 0.95, "mx": 0.9,
	"cafe": 1.03, "sport": 1.08, "race": 1.1, "naked": 1.05}
## How hard they corner (sideways m/s^2, about 22 degrees of lean), brake and pull away (m/s^2),
## and the most they lean (Bike.ROAD_LEAN).
const GRIP := 4.0
const BRAKE := 4.0
const ACCEL := 2.6
const BEND_STEP := 6.0
const BEND_EVERY := 0.3
## The gap kept behind what's ahead in the lane (m, and s at speed), as the traffic's.
const GAP := 3.0
const HEADWAY := 1.2
## Riding staggered: the two tracks either side of the middle of the lane (m), and the gap along
## the road to the rider ahead in the line (m, at least, and s at speed).
const LANE := 0.45
const STAGGER := 0.55
const FORM_GAP := 8.0
const FORM_TIME := 0.75
## Joining: the rider within JOIN_BEHIND behind (or JOIN_BESIDE ahead of) a biker going their
## way, keeping its pace (within JOIN_MATCH m/s) for JOIN_TIME s. It rides along for JOIN_FOR s,
## at least JOIN_MIN before it parts at a stop (the crew stood STOP_PART s), and leaves the crew
## if they get LOSE m from it. A biker that's parted won't join again for COOLDOWN s.
const JOIN_BEHIND := 35.0
const JOIN_BESIDE := 8.0
const JOIN_MATCH := 3.0
const JOIN_TIME := 3.0
const JOIN_FOR := [150.0, 360.0]
const JOIN_MIN := 40.0
const STOP_PART := 8.0
const LOSE := 160.0
const COOLDOWN := 90.0
## Peeling off: down the next side road on its left between these distances ahead (m), with the
## indicator on for the last PEEL_SIGNAL m; with none in GIVE_UP s more, it rides on instead.
const PEEL_LOOK := [60.0, 500.0]
const PEEL_SIGNAL := 90.0
const GIVE_UP := 120.0
## Down a side road: its speed (m/s), as the traffic's (TrafficStream.ARM_LIMIT, TURN_LEN).
const ARM_SPEED := 9.0
const TURN_SPEED := 5.0
## Passing someone: a solo rider held this much under its pace for PASS_WAIT s goes by when the
## other side's clear for PASS_CLEAR m (and no junction within PASS_JUNCTION m), and back in once
## PASS_BY m past.
const PASS_SLOWER := 3.0
const PASS_WAIT := 4.0
const PASS_CLEAR := 260.0
const PASS_JUNCTION := 120.0
const PASS_BY := 15.0
## Greeting the crew: an oncoming biker decides between these distances (m) whether to nod (or,
## WAVE_SHARE of the time, wave) as you pass; a nod at one within NOD_RANGE is nodded back.
const GREET_AT := [20.0, 55.0]
const GREET_ODDS := 0.65
const WAVE_SHARE := 0.35
const NOD_RANGE := 60.0
const NOD_TIME := 1.0
const WAVE_TIME := 2.2
## Gestures as sent: none, a nod, a wave.
const NONE := 0
const NOD := 1
const WAVE := 2
## Drawn within DRAW_RANGE of the camera (times the draw distance setting), heard within SOUND_RANGE.
const DRAW_RANGE := 450.0
const SOUND_RANGE := 220.0
## The numbers sent for each biker (see pack), and the tag after them.
const PACKED := 6
const TAG := -44444.0
## A biker on a side road is sent with its lat past this (as TrafficStream.ARM_CODE).
const ARM_CODE := 10000.0

var traffic: AdventureTraffic
var stream: TrafficStream
var host := true
## The bikers out now. Each: {id (its bike in the pool), s, dir, v, lat, pace (m/s share of the
## limit), lead (the id of the biker it rides behind in its group, or -1), slot (its place in the
## group's line, 0 the leader), rider (the rider whose crew it's riding with, or -1), jslot (its
## place in the crew's line: -1 just behind them, +1 just in front...), jtime (s left with the
## crew), with (s it's been with them), still (s the crew's been stood), match (rider -> s it's
## kept pace with them), cool (s before it'll join again), peel ([junction, arm] it's turning off
## at), ind, gesture, gest_t, greeted (rider -> true), bend, bend_t, pass (overtaking), held,
## and on a side road arm, k, t (as the traffic's: see TrafficStream.vehicles)}.
var bikers: Array = []
## Each bike in the pool: {look, build, body, lean, model, head, arm, sound, used, roll, spin,
## lat, gest, gest_t, joined (as last seen, for the messages), pos}.
var pool: Array = []
var rng := RandomNumberGenerator.new()
## How long the pool took to build (ms).
var pool_ms := 0.0
## Where each rider is: [{s, lat, v (m/s along the road, + the way s grows), lane}...], as
## AdventureTraffic found them this tick (index 0 is you on your machine).
var riders: Array = []
var _spawn_timer := 2.0
var _seq := 0               # bikers put on the road so far (each one's "n")
var _rider_s: Array = []    # each rider's s last tick, for their speed
var _hinted := {}           # bike id -> true once you've been told how to ride with it
var _nod_queue: Array = []  # [seconds to go, bike id, gesture] for nods back


func _ready() -> void:
	name = "Bikers"
	current = self
	if traffic == null:
		traffic = get_parent() as AdventureTraffic
	stream = traffic.stream
	host = traffic.host
	rng.seed = hash([traffic.world.route.seed_value, "adventure_bikers", Time.get_ticks_usec()])
	_build_pool()


func _exit_tree() -> void:
	if current == self:
		current = null


# ---------------------------------------------------------------------------- the pool

## The looks of the pool's bikes: every one a different style, its colour and the rider's jacket,
## from the route's seed (the same on every machine).
static func looks_for(route_seed: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([route_seed, "biker_looks"])
	var styles: Array = PartsDB.STYLES.duplicate()
	for i in range(styles.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var tmp = styles[i]
		styles[i] = styles[j]
		styles[j] = tmp
	var jackets := [Color(0.07, 0.07, 0.08), Color(0.35, 0.2, 0.12), Color(0.6, 0.08, 0.06), Color(0.12, 0.2, 0.45),
		Color(0.85, 0.85, 0.82), Color(0.2, 0.3, 0.15), Color(0.9, 0.45, 0.05)]
	var out := []
	for i in POOL:
		var style: String = styles[i % styles.size()]
		out.append({"style": style, "parts": PartsDB.sanitize_build(Contracts.style_build(style)),
			"paint": Shed.PAINTS[r.randi() % Shed.PAINTS.size()], "jacket": jackets[r.randi() % jackets.size()]})
	return out


## Builds every bike now (behind the fade), hidden till it's out on the road.
func _build_pool() -> void:
	var t0 := Time.get_ticks_usec()
	for look in looks_for(traffic.world.route.seed_value):
		var build := BikeBuild.new(look["parts"])
		var body := AnimatableBody3D.new()
		body.name = "Biker%d" % pool.size()
		body.sync_to_physics = false
		body.collision_layer = 0
		body.collision_mask = 0
		body.add_to_group("road_traffic")
		body.set_meta("mover_radius", 0.9)
		body.visible = false
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
		model.baked = true   # far fewer draw calls (see BikeModel._bake_static)
		model.position.y = build.rear_radius
		lean.add_child(model)
		model.build_from(build, look["paint"])
		model.set_lights(true, true)
		var rig := _rig(model)
		var sound: EngineSound = null
		if DisplayServer.get_name() != "headless":
			sound = EngineSound.new()
			sound.volume_db = -6.0
			body.add_child(sound)
			sound.setup(build, model)
			sound.set_distant_filter(true)
			sound.running = false
		pool.append({"look": look, "build": build, "body": body, "lean": lean, "model": model, "head": rig[0], "arm": rig[1],
			"sound": sound, "used": false, "roll": 0.0, "spin": 0.0, "lat": NAN, "gest": NONE, "gest_t": 0.0, "joined": false,
			"pos": Vector3.ZERO, "yaw": 0.0})
	pool_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The rider's head and left arm on their own pivots (the neck, the left shoulder), so they can
## nod and wave: the pieces BikeModel sat on the bike, moved under them as they are.
static func _rig(model: BikeModel) -> Array:
	var rider: Node3D = model._rider
	# The model has its own head and left-arm pivots now (for your gestures): turn those.
	if model._rider_head and model._arm_left:
		return [model._rider_head, model._arm_left]
	var head := Node3D.new()
	head.name = "Head"
	var arm := Node3D.new()
	arm.name = "ArmL"
	if rider == null:
		return [head, arm]
	var hips := Vector3(0.0, model._seat_y + 0.1, lerpf(model._seat_front.z, model._tail.z, 0.42))
	var shoulders := hips + Vector3(0.0, 0.5, -0.3)
	head.position = shoulders + Vector3(0.0, 0.06, -0.02)
	arm.position = shoulders + Vector3(-0.19, -0.04, 0.0)
	var pieces := rider.get_children()
	rider.add_child(head)
	rider.add_child(arm)
	for n in pieces:
		if not n is MeshInstance3D:
			continue
		var p := (n as Node3D).position
		var to: Node3D = null
		if p.x < -0.1:
			to = arm
		elif p.y > shoulders.y + 0.08:
			to = head
		if to:
			var xf := (n as Node3D).transform
			rider.remove_child(n)
			to.add_child(n)
			(n as Node3D).transform = Transform3D(Basis(), -to.position) * xf
	return [head, arm]


func _free_slot() -> int:
	for i in pool.size():
		if not pool[i]["used"]:
			return i
	return -1


func find(id: int) -> Dictionary:
	for d in bikers:
		if int(d["id"]) == id:
			return d
	return {}


func _take(id: int) -> void:
	var p: Dictionary = pool[id]
	p["used"] = true
	p["roll"] = 0.0
	p["lat"] = NAN
	p["gest"] = NONE
	p["gest_t"] = 0.0
	p["joined"] = false
	p["seen_g"] = NONE
	(p["head"] as Node3D).rotation = Vector3.ZERO
	(p["arm"] as Node3D).rotation = Vector3.ZERO
	(p["body"] as Node3D).visible = true


func _drop(i: int) -> void:
	var id := int(bikers[i]["id"])
	var p: Dictionary = pool[id]
	p["used"] = false
	var body: AnimatableBody3D = p["body"]
	body.visible = false
	body.collision_layer = 0
	if p["sound"]:
		(p["sound"] as EngineSound).running = false
	for d in bikers:
		if int(d.get("lead", -1)) == id:
			d["lead"] = -1   # its group rides on without it
			d["slot"] = 0
	bikers.remove_at(i)


## Every biker off the road.
func clear() -> void:
	for i in range(bikers.size() - 1, -1, -1):
		_drop(i)


## Down a side road on a junction list that's gone (the junctions were listed again): off the road.
func drop_arms() -> void:
	for i in range(bikers.size() - 1, -1, -1):
		if bikers[i].has("arm") or bikers[i].has("peel"):
			_drop(i)


# ---------------------------------------------------------------------------- spawning

## Puts a rider (`size` 1) or a group of them on the road at `s` going `dir`, the leader there and
## the rest behind it in a staggered line, at `v` m/s (negative: their own pace). Host only. Their
## ids, or [] if there aren't enough bikes in the pool or it's off the road's ends.
func spawn_group(s: float, dir: int, size := 1, v := -1.0) -> Array:
	dir = 1 if dir >= 0 else -1
	var free := 0
	for p in pool:
		free += 0 if p["used"] else 1
	if not host or free < size or s < stream.s_min or s > stream.s_max:
		return []
	var at: Dictionary = stream.sample.call(s)
	var limit := float(at.get("limit", TrafficStream.OPEN_LIMIT))
	var ids := []
	var lead := -1
	var pace := 0.0
	for n in size:
		var id := _free_slot()
		var style := str(pool[id]["look"]["style"])
		if n == 0:
			pace = float(STYLE_PACE.get(style, 1.0)) * clampf(1.0 + rng.randfn(0.0, 0.06), 0.88, 1.12)
		var sv := v if v >= 0.0 else pace * limit
		var gap := maxf(FORM_GAP, sv * FORM_TIME)
		_seq += 1
		var d := {"id": id, "n": _seq, "s": s - dir * gap * n, "dir": dir, "v": sv, "lat": NAN, "pace": pace, "lead": lead, "slot": n,
			"rider": -1, "jslot": 0, "match": {}, "cool": 0.0, "ind": 0, "gesture": NONE, "gest_t": 0.0, "greeted": {},
			"bend": INF, "bend_t": 0.0, "held": 0.0}
		d["lat"] = _track_lat(d, at)
		_take(id)
		bikers.append(d)
		ids.append(id)
		if n == 0:
			lead = id
	return ids


## How many should be out: WANTED round the riders, and any riding with the crew on top.
func wanted() -> int:
	var with := 0
	for d in bikers:
		with += 1 if int(d["rider"]) >= 0 else 0
	return mini(POOL, WANTED + with)


## Now and then a rider or a group turns up out of sight along the road, either way.
func _spawn() -> void:
	var spots := stream.spots()
	if spots.is_empty() or bikers.size() >= wanted():
		return
	var roll := rng.randf()
	var size := 1
	for k in GROUP_ODDS.size():
		roll -= float(GROUP_ODDS[k])
		if roll < 0.0:
			size = k + 1
			break
	size = mini(size, wanted() - bikers.size())
	var f := float(spots[rng.randi() % spots.size()])
	var s := f + rng.randf_range(stream.spawn_near, stream.spawn_far) * (1.0 if rng.randf() < 0.5 else -1.0)
	var dir := 1 if rng.randf() < 0.5 else -1
	if s < stream.s_min + 20.0 or s > stream.s_max - 20.0 or stream.from_focus(s) < stream.spawn_near - 0.01:
		return
	if float(stream.sample.call(s).get("hw", 3.5)) < 2.0:
		size = 1   # single file down a single-track lane
	# Not on top of anything in that lane.
	if not stream.clear_at(s, dir, 40.0 + size * 12.0):
		return
	for d in bikers:
		if absf(float(d["s"]) - s) < 80.0:
			return
	spawn_group(s, dir, size)


# ---------------------------------------------------------------------------- each tick

## Moves them all on `delta` s (AdventureTraffic calls it each tick, after finding the riders and
## before the traffic moves); the host rides them, the crew's machines carry them on between the
## host's snapshots. Then they're drawn, and each is put in the traffic's way as a blocker.
func step(delta: float) -> void:
	host = traffic.host
	_find_riders(delta)
	if host:
		for i in range(bikers.size() - 1, -1, -1):
			var d: Dictionary = bikers[i]
			var s := float(d["s"])
			d["age"] = float(d.get("age", 0.0)) + delta
			if int(d["rider"]) < 0 and (stream.from_focus(s) > stream.despawn or s < stream.s_min or s > stream.s_max \
					or (float(d["age"]) > LINGER and stream.from_focus(s) > UNSEEN and int(d["lead"]) < 0 and not _group_near(d)) \
					or (d.has("arm") and float(d["t"]) > _arm_len(d) - 6.0 and stream.unseen(_place_arm(d)[0]))):
				_drop(i)
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_EVERY
			_spawn()
		for d in bikers:
			_ride(d, delta)
	else:
		for d in bikers:
			_carry(d, delta)
	_nods(delta)
	_draw(delta)
	_hint()
	for d in bikers:
		if d.has("arm"):
			continue
		var lane := int(d["dir"]) if float(d["lat"]) * int(d["dir"]) < -0.7 else 0
		stream.blockers.append([float(d["s"]), lane, 1.1])


## Whether any of biker `d`'s group is within UNSEEN of the riders (so it doesn't leave them).
func _group_near(d: Dictionary) -> bool:
	for o in bikers:
		if int(o["lead"]) == int(d["id"]) and stream.from_focus(float(o["s"])) <= UNSEEN:
			return true
	return false


## Each rider's place along the road and their speed along it, from AdventureTraffic's spots.
func _find_riders(delta: float) -> void:
	var spots: Array = traffic.rider_spots
	if _rider_s.size() != spots.size():
		# Someone's come or gone: who's who among the riders may have moved, so those riding with
		# the crew go their own way.
		for d in bikers:
			if int(d.get("rider", -1)) >= 0 and host:
				_part(d, false)
		_rider_s = []
		_rider_s.resize(spots.size())
		_rider_s.fill(NAN)
		riders = []
		for k in spots.size():
			riders.append({"s": NAN, "lat": 0.0, "v": 0.0})
	for k in spots.size():
		var sp: Array = spots[k]
		var r: Dictionary = riders[k]
		if sp.is_empty():
			r["s"] = NAN
			_rider_s[k] = NAN
			continue
		var s := float(sp[0])
		var was := float(_rider_s[k])
		if is_nan(was) or absf(s - was) > 60.0 or delta <= 0.0:
			r["v"] = 0.0
		else:
			r["v"] = lerpf(float(r["v"]), (s - was) / delta, 1.0 - exp(-2.5 * delta))
		_rider_s[k] = s
		r["s"] = s
		r["lat"] = float(sp[1])


## The host: rides one biker on (with a group, the crew, down a side road, or on its own).
func _ride(d: Dictionary, delta: float) -> void:
	d["cool"] = maxf(0.0, float(d["cool"]) - delta)
	_gesture_tick(d, delta)
	if d.has("arm"):
		_ride_arm(d, delta)
		return
	var s := float(d["s"])
	var dir := int(d["dir"])
	var v := float(d["v"])
	var at: Dictionary = stream.sample.call(s)
	# The limit here, or a lower one coming up (into a village).
	var limit := minf(traffic.limit_at(s), traffic.limit_at(s + dir * maxf(30.0, v * 2.5)))
	var allow := minf(_bends(d, delta), _junctions_ahead(d))
	var want_lat := _track_lat(d, at)
	var lead := find(int(d["lead"])) if int(d["lead"]) >= 0 else {}
	if lead.has("arm"):
		lead = {}   # its leader's turning off: it follows on its own to the same turn
	var rider := int(d["rider"])
	if rider >= 0 and (rider >= riders.size() or is_nan(float(riders[rider]["s"]))):
		_part(d, false)
		rider = -1
	if rider >= 0:
		allow = minf(allow, _with_crew(d, delta, limit))
		allow = minf(allow, _traffic_ahead(d, at, delta, true))
		want_lat = _crew_lat(d, at)
	elif not lead.is_empty():
		allow = minf(allow, _in_line(d, lead, limit))
		allow = minf(allow, _traffic_ahead(d, at, delta, true))
		want_lat = _track_lat(d, at)
	else:
		allow = minf(allow, float(d["pace"]) * limit)
		allow = minf(allow, _traffic_ahead(d, at, delta, false))
		want_lat = _pass_lat(d, at, want_lat, delta)
		_try_join(d, delta)
	if d.has("peel"):
		allow = minf(allow, _peel_ahead(d))
	v = move_toward(v, maxf(allow, 0.0), (BRAKE * 1.5 if allow < v else ACCEL) * delta)
	d["v"] = v
	d["s"] = s + dir * v * delta
	d["lat"] = move_toward(float(d["lat"]), want_lat, (1.6 if d.get("pass", false) else 0.8) * delta)
	if d.has("peel") and (float(d["s"]) - _turn_from(d)) * dir >= 0.0:
		var peel: Array = d["peel"]
		d.erase("peel")
		d["arm"] = int(peel[0])
		d["k"] = int(peel[1])
		d["t"] = -TrafficStream.TURN_LEN
		d["out"] = true
		d["s"] = stream._arm_s(_arm_probe(d))
	_greet(d)


## The speed allowed for the bends ahead (looked over every BEND_EVERY s), as the traffic's.
func _bends(d: Dictionary, delta: float) -> float:
	d["bend_t"] = float(d["bend_t"]) - delta
	if float(d["bend_t"]) <= 0.0:
		d["bend_t"] = BEND_EVERY
		var s := float(d["s"])
		var dir := int(d["dir"])
		var v := float(d["v"])
		var best := INF
		var look := maxf(40.0, v * v / (2.0 * BRAKE) + 15.0)
		var dist := 0.0
		while dist <= look:
			var k := absf(stream.curvature(s + dir * dist))
			var bend := sqrt(GRIP / maxf(k, 0.0005))
			best = minf(best, sqrt(bend * bend + 2.0 * BRAKE * maxf(dist - v * BEND_EVERY, 0.0)))
			dist += BEND_STEP
		d["bend"] = best
	return float(d["bend"])


## The lights (stopping for a red, or an amber it can stop for) and the roundabouts (round them
## at the traffic's pace) ahead.
func _junctions_ahead(d: Dictionary) -> float:
	var allow := INF
	var s := float(d["s"])
	var dir := int(d["dir"])
	var v := float(d["v"])
	for j in stream._near_j:
		var jn: Dictionary = stream.junctions[j]
		var along := (float(jn["s"]) - s) * dir
		if along < -2.0 or along > 160.0:
			continue
		var to_line := along - float(jn["stop"]) - 1.0
		if jn.get("lights", false) and to_line > -0.5 and stream.signal_state.is_valid():
			var light := int(stream.signal_state.call(jn).x)
			if light == AdventureJunctions.RED or light == AdventureJunctions.RED_AMBER_ON \
					or (light == AdventureJunctions.AMBER_ON and to_line > v * v / (2.0 * BRAKE * 0.7)):
				allow = minf(allow, TrafficStream._stop_for(to_line, BRAKE))
		if jn.has("ro"):
			allow = minf(allow, sqrt(TrafficStream.ROUND_SPEED * TrafficStream.ROUND_SPEED + 2.0 * BRAKE * 0.5 * maxf(along - float(jn["ro"]), 0.0)))
	return allow


## Hanging back behind what's ahead in its lane: the traffic, and (out on its own) the crew and
## other bikers not in its own group. In a line (its group's or the crew's) only the traffic:
## the line keeps its own gaps. Counts how long it's been held well under its pace (for passing).
func _traffic_ahead(d: Dictionary, at: Dictionary, delta: float, in_line: bool) -> float:
	var s := float(d["s"])
	var dir := int(d["dir"])
	var hold := INF
	var passing: bool = d.get("pass", false)
	var hw := float(at.get("hw", 3.5))
	for o in stream.vehicles:
		if int(o["dir"]) == dir and TrafficStream._in_lane(o, hw) and not passing:
			hold = minf(hold, _gap_speed(s, dir, float(o["s"]), TrafficVehicle.half_length_of(str(o["kind"]))))
	if in_line:
		return hold
	for r in riders:
		if passing or not _rider_lane(r, hw, dir):
			continue
		# Side by side in the lane (on the other track, as riding staggered) isn't in its way.
		var along := (float(r["s"]) - s) * dir
		if along < JOIN_BESIDE + 2.0 and absf(float(r["lat"]) - float(d["lat"])) > 0.55:
			continue
		hold = minf(hold, _gap_speed(s, dir, float(r["s"]), 1.2))
	var group := int(d["id"])
	for o in bikers:
		if o == d or o.has("arm") or int(o["dir"]) != dir or int(o["lead"]) == group:
			continue
		if passing != (float(o["lat"]) * dir > 0.0):
			continue   # in the other lane
		hold = minf(hold, _gap_speed(s, dir, float(o["s"]), 1.1))
	if hold < float(d["pace"]) * traffic.limit_at(s) - PASS_SLOWER:
		d["held"] = float(d["held"]) + delta
	else:
		d["held"] = 0.0
	return hold


## Whether rider `r` is in the way of the lane going `dir` (as AdventureTraffic's blockers: in
## that lane, or astride the middle).
static func _rider_lane(r: Dictionary, hw: float, dir: int) -> bool:
	var lat := float(r["lat"])
	if is_nan(float(r["s"])) or absf(lat) > hw + 0.4:
		return false
	return lat * dir < 0.7


func _gap_speed(s: float, dir: int, other_s: float, other_half: float) -> float:
	var along := (other_s - s) * dir
	var clear := along - 1.1 - other_half
	if along <= 0.0 or clear > 60.0:
		return INF
	return maxf(0.0, (clear - GAP) / HEADWAY)


## A solo rider held up a while goes by on the other side when it's clear a good way ahead, and
## back into its lane once past; the lat it wants.
func _pass_lat(d: Dictionary, at: Dictionary, lane_lat: float, _delta: float) -> float:
	var s := float(d["s"])
	var dir := int(d["dir"])
	var solo := true
	for o in bikers:
		if int(o["lead"]) == int(d["id"]):
			solo = false
	if not d.get("pass", false):
		if solo and float(d["held"]) > PASS_WAIT and float(at.get("hw", 3.5)) >= 2.6 and _other_side_clear(s, dir, PASS_CLEAR):
			d["pass"] = true
			d["pass_from"] = s
		return lane_lat
	# Past everything it was behind (nothing in its own lane within PASS_BY behind to PASS_BY
	# ahead), or something's coming: back in.
	var in_way := false
	for o in stream.vehicles:
		if int(o["dir"]) == dir and not o.has("arm"):
			var along := (float(o["s"]) - s) * dir
			if along > -PASS_BY - TrafficVehicle.half_length_of(str(o["kind"])) and along < 40.0:
				in_way = true
	for r in riders:
		var along := (float(r["s"]) - s) * dir
		if not is_nan(float(r["s"])) and along > -PASS_BY and along < 40.0 and _rider_lane(r, float(at.get("hw", 3.5)), dir):
			in_way = true
	var coming := not _other_side_clear(s, dir, 90.0)
	if (not in_way and (s - float(d["pass_from"])) * dir > PASS_BY) or coming or (s - float(d["pass_from"])) * dir > 600.0:
		d["pass"] = false
		d["held"] = 0.0
		return lane_lat
	var hw := float(at.get("hw", 3.5))
	return dir * _lane_off(hw)


## Whether the other lane is clear for `dist` m ahead of `s` (going `dir`): nothing coming in
## it, and no junction.
func _other_side_clear(s: float, dir: int, dist: float) -> bool:
	for o in stream.vehicles:
		var along := (float(o["s"]) - s) * dir
		if int(o["dir"]) == -dir and along > -10.0 and along < dist + float(o["v"]) * dist / 20.0:
			return false
	for o in bikers:
		var along := (float(o["s"]) - s) * dir
		if int(o["dir"]) == -dir and along > -10.0 and along < dist * 1.5:
			return false
	for r in riders:
		var along := (float(r["s"]) - s) * dir
		if not is_nan(float(r["s"])) and float(r["lat"]) * dir > -0.7 and along > -10.0 and along < dist:
			return false
	for jn in stream.junctions:
		var along := (float(jn["s"]) - s) * dir
		if along > -20.0 and along < PASS_JUNCTION:
			return false
	return true


## In its group's line behind its leader: as fast as keeps it at its place (FORM_GAP or
## FORM_TIME behind the one ahead), no faster than a bit over the limit.
func _in_line(d: Dictionary, lead: Dictionary, limit: float) -> float:
	var dir := int(d["dir"])
	var lv := float(lead["v"])
	var gap := maxf(FORM_GAP, lv * FORM_TIME) * int(d["slot"])
	var target := float(lead["s"]) - dir * gap
	var err := (target - float(d["s"])) * dir
	return clampf(lv + err * 0.5, 0.0, maxf(limit * 1.2, lv + 3.0))


## Riding with the crew: keeping its place in their line (in front of or behind the rider it
## joined), stopping when they stop; and when its time's up, peeling off at the next side road
## (or riding on if there isn't one, or when the crew's stopped a while).
func _with_crew(d: Dictionary, delta: float, limit: float) -> float:
	var r: Dictionary = riders[int(d["rider"])]
	var dir := int(d["dir"])
	var rv := float(r["v"]) * dir
	var gap := maxf(FORM_GAP, absf(rv) * FORM_TIME) * int(d["jslot"])
	var target := float(r["s"]) + dir * gap
	var err := (target - float(d["s"])) * dir
	d["with"] = float(d.get("with", 0.0)) + delta
	d["jtime"] = float(d["jtime"]) - delta
	if absf(err) > LOSE:
		_part(d, false)
		return float(d["pace"]) * limit
	d["still"] = float(d.get("still", 0.0)) + delta if absf(rv) < 0.8 else 0.0
	if float(d["still"]) > STOP_PART and float(d["with"]) > JOIN_MIN:
		_part(d, true)
		return float(d["pace"]) * limit
	if float(d["jtime"]) <= 0.0 and not d.has("peel"):
		if not _find_peel(d) and float(d["jtime"]) < -GIVE_UP:
			_part(d, true)
			return float(d["pace"]) * limit
	# Stood (or stopping) behind them: closing up gently to its place, never past it.
	var v := clampf(maxf(rv, 0.0) + err * 0.45, 0.0, maxf(limit * 1.25, rv + 4.0))
	if err < 0.0:
		v = minf(v, maxf(rv, 0.0) * (1.0 + err * 0.05))
	return maxf(v, 0.0)


## Its place across the road in the crew's line: the other track to the rider it joined, and
## each next one the other way again.
func _crew_lat(d: Dictionary, at: Dictionary) -> float:
	var dir := int(d["dir"])
	var hw := float(at.get("hw", 3.5))
	var lane := _lane_off(hw)
	var stag := minf(STAGGER, maxf(0.0, hw - lane - 0.6))
	var r: Dictionary = riders[int(d["rider"])]
	var theirs := -float(r["lat"]) * dir   # how far left of the middle they are, going our way
	var inner := theirs < lane   # they're on the middle side of the lane: we take the kerb side
	var n := absi(int(d["jslot"]))
	var kerb := inner if n % 2 == 1 else not inner
	return -dir * (lane + (stag if kerb else -stag))


## How far left of the middle line a rider keeps on a road `hw` wide each side.
static func _lane_off(hw: float) -> float:
	return clampf(hw * LANE, 0.6, maxf(0.6, hw - 0.6))


## Its place across the road in its own group's staggered line (a solo rider in the middle of
## its lane): the leader by the middle line, the next by the kerb, and so on.
func _track_lat(d: Dictionary, at: Dictionary) -> float:
	var dir := int(d["dir"])
	var hw := float(at.get("hw", 3.5))
	var lane := _lane_off(hw)
	var grouped := int(d["slot"]) > 0
	for o in bikers:
		if int(o["lead"]) == int(d["id"]):
			grouped = true
	if not grouped:
		return -dir * lane
	var stag := minf(STAGGER, maxf(0.0, hw - lane - 0.6))
	return -dir * (lane + (stag if int(d["slot"]) % 2 == 1 else -stag))


# ---------------------------------------------------------------------------- joining and parting

## A rider keeping pace close behind it (or alongside) going its way: after JOIN_TIME s of it,
## it's riding with them.
func _try_join(d: Dictionary, delta: float) -> void:
	if float(d["cool"]) > 0.0 or d.has("peel"):
		return
	var dir := int(d["dir"])
	var m: Dictionary = d["match"]
	for k in riders.size():
		var r: Dictionary = riders[k]
		if is_nan(float(r["s"])):
			continue
		var along := (float(r["s"]) - float(d["s"])) * dir   # + they're ahead of it
		var rv := float(r["v"]) * dir
		var keeping := along > -JOIN_BEHIND and along < JOIN_BESIDE and rv > 3.0 and absf(rv - float(d["v"])) < JOIN_MATCH \
			and float(r["lat"]) * dir < 1.0
		m[k] = float(m.get(k, 0.0)) + delta if keeping else maxf(0.0, float(m.get(k, 0.0)) - delta * 2.0)
		if float(m[k]) >= JOIN_TIME:
			join(int(d["id"]), k, 1 if along < 0.0 else -1)
			return


## Biker `id` rides with rider `k`'s crew (host): `side` -1 behind them, +1 in front, each at the
## next place along in the line on that side.
func join(id: int, k: int, side: int) -> void:
	var d := find(id)
	if d.is_empty() or d.has("arm"):
		return
	var n := 1
	for o in bikers:
		if int(o["rider"]) == k and signi(int(o["jslot"])) == signi(side):
			n = maxi(n, absi(int(o["jslot"])) + 1)
	d["rider"] = k
	d["jslot"] = n * signi(side)
	d["jtime"] = rng.randf_range(JOIN_FOR[0], JOIN_FOR[1])
	d["with"] = 0.0
	d["still"] = 0.0
	d["match"] = {}
	d["pass"] = false
	if int(d["lead"]) >= 0:
		d["lead"] = -1   # (only a solo rider or a group's leader is joined)
		d["slot"] = 0


## Biker `d` leaves the crew (host): with a wave if `wave`, riding on at its own pace.
func _part(d: Dictionary, wave: bool) -> void:
	var k := int(d["rider"])
	d["rider"] = -1
	d["cool"] = COOLDOWN
	d["ind"] = 0
	if wave:
		_gesture(d, WAVE)
	# The ones behind it in the line close up.
	for o in bikers:
		if int(o["rider"]) == k and signi(int(o["jslot"])) == signi(int(d["jslot"])) and absi(int(o["jslot"])) > absi(int(d["jslot"])):
			o["jslot"] = int(o["jslot"]) - signi(int(o["jslot"]))
	d["jslot"] = 0


## Its time with the crew's up: the next side road on its left within PEEL_LOOK, if there is one.
func _find_peel(d: Dictionary) -> bool:
	var s := float(d["s"])
	var dir := int(d["dir"])
	for j in stream._near_j:
		var jn: Dictionary = stream.junctions[j]
		var along := (float(jn["s"]) - s) * dir
		if along < PEEL_LOOK[0] or along > PEEL_LOOK[1] or jn.has("ro"):
			continue
		for k in (jn["arms"] as Array).size():
			if int(jn["arms"][k]["side"]) == -dir:
				peel_at(d, j, k)
				return true
	return false


## Biker `d` turns off down junction `j`'s side road `k` (on its left): it signals, slows, waves
## to the crew, and turns, and the rest of its own group with it.
func peel_at(d: Dictionary, j: int, k: int) -> void:
	d["peel"] = [j, k]
	for o in bikers:
		if int(o["lead"]) == int(d["id"]) and not o.has("arm"):
			o["peel"] = [j, k]


func _turn_from(d: Dictionary) -> float:
	var jn: Dictionary = stream.junctions[int(d["peel"][0])]
	return float(jn["s"]) - int(d["dir"]) * TrafficStream._bend_reach(jn)


## Slowing for the turn it's peeling off at (and signalling, and a wave as it goes).
func _peel_ahead(d: Dictionary) -> float:
	var to := (_turn_from(d) - float(d["s"])) * int(d["dir"])
	if to < PEEL_SIGNAL:
		d["ind"] = -1
	if to < 40.0 and int(d["rider"]) >= 0:
		_part(d, true)
		d["ind"] = -1
	return sqrt(TURN_SPEED * TURN_SPEED + 2.0 * BRAKE * 0.5 * maxf(to, 0.0))


func _arm_probe(d: Dictionary) -> Dictionary:
	return {"arm": int(d["arm"]), "k": int(d["k"]), "t": float(d["t"]), "out": true, "dir": int(d["dir"]), "kind": "hatchback"}


func _arm_len(d: Dictionary) -> float:
	return float(stream.junctions[int(d["arm"])]["arms"][int(d["k"])]["len"])


func _place_arm(d: Dictionary) -> Array:
	return stream._place_arm(_arm_probe(d))


## Off down a side road and away out of sight (where it goes back in the pool).
func _ride_arm(d: Dictionary, delta: float) -> void:
	var t := float(d["t"])
	var end := _arm_len(d) - 4.0
	var allow := ARM_SPEED if t >= 0.0 else TURN_SPEED + 1.0
	allow = minf(allow, TrafficStream._stop_for(end - t + 0.5, BRAKE))
	if t > 4.0:
		d["ind"] = 0
	var v := move_toward(float(d["v"]), allow, (BRAKE if allow < float(d["v"]) else ACCEL) * delta)
	d["v"] = v
	d["t"] = t + v * delta
	d["s"] = stream._arm_s(_arm_probe(d))


# ---------------------------------------------------------------------------- nods and waves

## An oncoming biker coming up to a rider: once, it decides whether to nod or wave as it passes.
func _greet(d: Dictionary) -> void:
	if int(d["gesture"]) != NONE:
		return
	var dir := int(d["dir"])
	var greeted: Dictionary = d["greeted"]
	for k in riders.size():
		var r: Dictionary = riders[k]
		if is_nan(float(r["s"])) or greeted.has(k):
			continue
		var along := (float(r["s"]) - float(d["s"])) * dir
		if along > GREET_AT[0] and along < GREET_AT[1] and float(r["v"]) * dir < 1.0:
			greeted[k] = true
			if rng.randf() < GREET_ODDS:
				_gesture(d, WAVE if rng.randf() < WAVE_SHARE else NOD)
			return


func _gesture(d: Dictionary, g: int) -> void:
	d["gesture"] = g
	d["gest_t"] = WAVE_TIME if g == WAVE else NOD_TIME


func _gesture_tick(d: Dictionary, delta: float) -> void:
	if int(d["gesture"]) == NONE:
		return
	d["gest_t"] = float(d["gest_t"]) - delta
	if float(d["gest_t"]) <= 0.0:
		d["gesture"] = NONE


## A rider at `from` (local) has nodded (or waved, `wave`): the bikers near them nod back (one
## in three of them waving instead), a moment later. For the nod key to call; it's drawn on this
## machine only (the one whose rider nodded). How many will.
static func nod_back(from: Vector3, wave := false) -> int:
	var me := current
	if me == null or not is_instance_valid(me):
		return 0
	var n := 0
	for d in me.bikers:
		var p: Dictionary = me.pool[int(d["id"])]
		if int(p["gest"]) != NONE or (p["pos"] as Vector3).distance_to(from) > NOD_RANGE:
			continue
		var g := WAVE if me.rng.randf() < (0.6 if wave else 0.33) else NOD
		me._nod_queue.append([me.rng.randf_range(0.3, 0.9), int(d["id"]), g])
		n += 1
	return n


func _nods(delta: float) -> void:
	for i in range(_nod_queue.size() - 1, -1, -1):
		var q: Array = _nod_queue[i]
		q[0] = float(q[0]) - delta
		if float(q[0]) > 0.0:
			continue
		_nod_queue.remove_at(i)
		var p: Dictionary = pool[int(q[1])]
		if p["used"] and int(p["gest"]) == NONE:
			p["gest"] = int(q[2])
			p["gest_t"] = 0.0


## The rider's head and arm for a gesture `t` s into it: a nod down and up, or the left hand up
## off the bars and out for a wave.
func _pose_gesture(p: Dictionary, delta: float) -> void:
	var head: Node3D = p["head"]
	var arm: Node3D = p["arm"]
	var g := int(p["gest"])
	if g == NONE:
		return
	p["gest_t"] = float(p["gest_t"]) + delta
	var t := float(p["gest_t"])
	var length := WAVE_TIME if g == WAVE else NOD_TIME
	if t >= length:
		p["gest"] = NONE
		head.rotation = Vector3.ZERO
		arm.rotation = Vector3.ZERO
		return
	var u := t / length
	if g == NOD:
		head.rotation = Vector3(-0.42 * sin(PI * u), 0.0, 0.0)
	else:
		var up := sin(PI * clampf(u * 1.4, 0.0, 1.0)) if u < 0.72 else lerpf(1.0, 0.0, (u - 0.72) / 0.28)
		up = clampf(up, 0.0, 1.0)
		arm.rotation = Vector3(0.75 * up, 0.0, -0.95 * up + 0.12 * sin(t * 9.0) * up)
		head.rotation = Vector3(0.0, -0.25 * up, 0.0)   # looking across at who they're waving to


# ---------------------------------------------------------------------------- drawing

func _draw(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	for d in bikers:
		var p: Dictionary = pool[int(d["id"])]
		var body: AnimatableBody3D = p["body"]
		var build: BikeBuild = p["build"]
		var v := float(d["v"])
		var dir := int(d["dir"])
		var pos: Vector3
		var fwd: Vector3
		var pitch := 0.0
		var k := 0.0
		if d.has("arm"):
			var where := _place_arm(d)
			pos = where[0]
			fwd = where[1]
			var probe := _arm_probe(d)
			probe["t"] = float(d["t"]) + 2.0
			var ahead: Array = stream._place_arm(probe)
			var turn := Vector2(fwd.x, fwd.z).normalized().cross(Vector2((ahead[1] as Vector3).x, (ahead[1] as Vector3).z).normalized())
			k = turn / 2.0
			pitch = atan2((ahead[0] as Vector3).y - pos.y, 2.0)
			p["lat"] = NAN
		else:
			var s := float(d["s"])
			var at: Dictionary = stream.sample.call(s)
			var f: Vector3 = at["fwd"]
			var right := Vector3(-f.z, 0.0, f.x).normalized()
			var lat := float(d["lat"])
			var was := float(p["lat"])
			var dlat := 0.0 if is_nan(was) else (lat - was) / maxf(delta, 0.001)
			p["lat"] = lat
			var heading := f * dir
			for j in stream._near_j:
				var jn: Dictionary = stream.junctions[j]
				if jn.has("rc") and absf(s - float(jn["s"])) < float(jn["rc"]) + 9.0:
					# Round the island on its left, then back into the lane (as the traffic).
					var ds := s - float(jn["s"])
					var lane := absf(lat)
					var side := signf(lat) if lane > 0.3 else float(-dir)
					lat += side * (AdventureJunctions.swing(jn, ds, lane) - lane)
					var slope := AdventureJunctions.swing(jn, ds + 0.5, lane) - AdventureJunctions.swing(jn, ds - 0.5, lane)
					heading = (f * dir + right * side * slope * dir).normalized()
			pos = (at["pos"] as Vector3) + right * lat
			fwd = (heading + right * clampf(dlat / maxf(v, 2.0), -0.3, 0.3)).normalized()
			pitch = atan(float(at.get("grade", 0.0)) * dir)
			k = stream.curvature(s + dir * maxf(v * 0.3, 1.0)) * dir
		p["pos"] = pos
		var yaw := atan2(-fwd.x, -fwd.z)
		# Leaning into the bend, atan(v^2 k / g), no further than a road rider would.
		var want := clampf(atan(v * v * k / Bike.G), -Bike.ROAD_LEAN, Bike.ROAD_LEAN)
		var roll := lerpf(float(p["roll"]), want, 1.0 - exp(-4.0 * delta))
		p["roll"] = roll
		body.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos)
		(p["lean"] as Node3D).basis = Basis(Vector3.FORWARD, roll)
		p["spin"] = float(p["spin"]) + v * delta / maxf(build.rear_radius, 0.2)
		var dist := 0.0 if cam == null else cam.global_position.distance_to(pos)
		var model: BikeModel = p["model"]
		var near := dist < DRAW_RANGE * scale
		model.visible = near
		# Solid out on the road, but not while it's riding in the crew's line.
		body.collision_layer = 2 if int(d.get("rider", -1)) < 0 and not bool(d.get("joined", false)) else 0
		if near:
			var steer := clampf(-atan(build.wheelbase * k) * 0.8, -0.5, 0.5)
			model.update_pose_from(steer, float(p["spin"]), float(p["spin"]), 0.0, 0.0, 0.0, clampf(roll / 0.6, -1.0, 1.0) * 0.6)
		# The gesture the host decided (or a nod back) starts as it's first seen.
		var g := int(d["gesture"])
		if g != NONE and int(p.get("seen_g", NONE)) == NONE and int(p["gest"]) == NONE:
			p["gest"] = g
			p["gest_t"] = 0.0
		p["seen_g"] = g
		_pose_gesture(p, delta)
		var sound: EngineSound = p["sound"]
		if sound:
			sound.running = dist < SOUND_RANGE
			sound.speed = v
			if sound.running:
				sound.gear = EngineSound.gear_for_speed(sound.gear, v, 4.5, 5)
			sound.throttle = 0.35
			sound.rpm = lerpf(build.idle_rpm, build.redline * 0.55, clampf(fmod(v, 4.5) / 4.5 * 0.7 + 0.2, 0.0, 1.0)) \
				if v > 0.5 else build.idle_rpm
		# Joining and parting, said on every machine as it's seen.
		var joined := int(d.get("rider", -1)) >= 0 or bool(d.get("joined", false))
		if joined != bool(p["joined"]):
			p["joined"] = joined
			var who := "The rider on %s" % _a(PartsDB.style_noun(str(p["look"]["style"])))
			_say("%s joins the crew for a while." % who if joined else ("%s waves and peels off." % who if int(d["gesture"]) == WAVE \
				else "%s goes their own way." % who))


static func _a(noun: String) -> String:
	return ("an " if noun.left(1).to_lower() in ["a", "e", "i", "o", "u"] or noun.begins_with("MX") else "a ") + noun


func _say(text: String) -> void:
	var trip := AdventureTrip.current
	if trip != null and is_instance_valid(trip) and trip.main != null and trip.main.hud != null:
		trip.main.hud.flash(text, 4.0)


## Coming up behind a biker going your way (on your own machine): how to ride with them, once
## for each.
func _hint() -> void:
	if riders.is_empty() or is_nan(float(riders[0]["s"])):
		return
	var r: Dictionary = riders[0]
	for d in bikers:
		var id := int(d["id"])
		if _hinted.has(id) or d.has("arm") or int(d.get("rider", -1)) >= 0 or bool(d.get("joined", false)) or int(d.get("lead", -1)) >= 0:
			continue
		var dir := int(d["dir"])
		var along := (float(r["s"]) - float(d["s"])) * dir
		if along > -45.0 and along < -8.0 and float(r["v"]) * dir > 3.0:
			_hinted[id] = true
			_say("A rider on %s ahead: keep pace behind them for a few seconds to ride along together." % _a(PartsDB.style_noun(str(pool[id]["look"]["style"]))))


# ---------------------------------------------------------------------------- the crew

## For the network, on the end of the traffic's snapshot: [s, dir, v, id, lat, flags] for each
## biker (flags: indicator + 1, + 4 x the gesture, + 16 riding with the crew), then how many and
## TAG. On a side road its t for s and for lat ARM_CODE + (junction x 8 + arm).
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in bikers:
		var flags := int(d["ind"]) + 1 + 4 * int(d["gesture"]) + (16 if int(d["rider"]) >= 0 else 0)
		var s := float(d["s"])
		var lat := float(d["lat"])
		if d.has("arm"):
			s = float(d["t"])
			lat = ARM_CODE + int(d["arm"]) * 8 + int(d["k"])
		out.append_array([s, float(d["dir"]), float(d["v"]), float(d["id"]), lat, float(flags)])
	out.append_array([float(bikers.size()), TAG])
	return out


## The crew: takes the bikers off the end of the host's snapshot (if they're there), and hands
## back the rest of it.
func unpack_tail(state: PackedFloat32Array) -> PackedFloat32Array:
	if state.size() < 2 or state[state.size() - 1] != TAG:
		return state
	var n := int(state[state.size() - 2])
	var from := state.size() - 2 - n * PACKED
	if n < 0 or from < 0:
		return state
	unpack(state.slice(from, state.size() - 2))
	return state.slice(0, from)


func unpack(state: PackedFloat32Array) -> void:
	var seen := {}
	for b in range(0, state.size() - PACKED + 1, PACKED):
		var id := int(state[b + 3])
		if id < 0 or id >= pool.size():
			continue
		seen[id] = true
		var flags := int(state[b + 5])
		var lat := state[b + 4]
		var arm := {}
		if lat > ARM_CODE - 0.5:
			var code := int(round(lat - ARM_CODE))
			lat = 0.0
			if code >> 3 >= stream.junctions.size() or code & 7 >= (stream.junctions[code >> 3]["arms"] as Array).size():
				continue
			arm = {"arm": code >> 3, "k": code & 7, "t": state[b], "out": true}
		var d := find(id)
		if d.is_empty():
			d = {"id": id, "s": state[b], "dir": int(state[b + 1]), "v": state[b + 2], "lat": lat, "target": state[b], "lat_to": lat,
				"lead": -1, "rider": -1, "ind": 0, "gesture": NONE}
			_take(id)
			bikers.append(d)
		if not arm.is_empty():
			var was_on := d.has("arm") and int(d["arm"]) == int(arm["arm"])
			d.merge(arm, true)
			if not was_on or absf(float(d["t"]) - state[b]) > 25.0:
				d["t"] = state[b]
			d["target"] = state[b]
		else:
			if d.has("arm"):
				for key in ["arm", "k", "t", "out"]:
					d.erase(key)
				d["s"] = state[b]
			d["target"] = state[b]
			d["lat_to"] = lat
			if absf(float(d["s"]) - state[b]) > 25.0:
				d["s"] = state[b]
				d["lat"] = lat
		d["dir"] = int(state[b + 1])
		d["v"] = state[b + 2]
		d["ind"] = (flags & 3) - 1
		d["gesture"] = (flags >> 2) & 3
		d["joined"] = flags & 16 != 0
	for i in range(bikers.size() - 1, -1, -1):
		if not seen.has(int(bikers[i]["id"])):
			_drop(i)


## The crew's machines: each biker carried on between the host's snapshots, easing onto them.
func _carry(d: Dictionary, delta: float) -> void:
	var v := float(d["v"])
	if d.has("arm"):
		d["t"] = float(d["t"]) + v * delta
		d["t"] = float(d["t"]) + (float(d["target"]) - float(d["t"])) * (1.0 - exp(-4.0 * delta))
		d["target"] = float(d["target"]) + v * delta
		d["s"] = stream._arm_s(_arm_probe(d))
		return
	var dir := int(d["dir"])
	d["s"] = float(d["s"]) + dir * v * delta
	d["s"] = float(d["s"]) + (float(d["target"]) - float(d["s"])) * (1.0 - exp(-4.0 * delta))
	d["target"] = float(d["target"]) + dir * v * delta
	d["lat"] = lerpf(float(d["lat"]), float(d["lat_to"]), 1.0 - exp(-3.0 * delta))
