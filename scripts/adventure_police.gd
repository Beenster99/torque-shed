class_name AdventurePolice
extends Node3D
## The police out on an adventure's road (Simon's point 5): now and then a police car (an estate
## in battenberg livery with a light bar, see VehicleModel "police") turns up in the traffic,
## one every 15-25 km, coming towards you or going your way, and sometimes parked up in a lay-by
## with an officer and a speed gun beside it.
##
## The rule: you can pass the police, but not much faster than they're going. Pass or meet a
## police car more than THRESHOLD (30 mph) faster than it's going, or go by a parked one more
## than 30 mph over the limit (60 mph on the open road, 30 through a village), and it lights up
## (blue lamps flashing by day and night, its siren wailing, pitch bent as it closes and falls
## away) and comes after you: hard on the throttle, following the road, round the traffic when
## the other side's clear. Let it get within CATCH_DIST of you for CATCH_TIME, or stop, and
## you're pulled over: your throttle's cut and you brake to a stop, an officer walks up from the
## car, says a few words, and you're fined from your OWN money (Progress, not the garage's):
## £100-£600, by how far over you were and how many times you've been done that day. Can't pay it
## all? You pay what you have and the rest goes on your licence as penalty points (kept in your
## profile's stats, "licence_points"): no debts. Outrun it (more than LOSE_DIST ahead for
## LOSE_TIME) and it gives up.
##
## Each rider is judged on their own: a car chases one rider, the one who broke the rule, and
## only that rider is pulled over and fined. The host runs the police (where every rider is along
## the road, how fast they go, the cars' driving and decisions) and sends the cars a few times a
## second (pack / unpack: lights, siren and the stop all ride along); the fines go through the
## shed's state (Shed.adventure["police"]), each paid on the fined player's own machine from
## their own purse.
##
## The cars are moved by a PoliceDriver, behind a small interface, so the traffic's stream can
## drive them instead later (see PoliceDriver).

## The rule: this much faster (m/s; 30 mph) than the car's going, or over the limit past a parked one.
const THRESHOLD := 13.4
## How near (m along the road) a rider has to be for the police to judge their speed.
const RADAR := 90.0
## Caught: within CATCH_DIST of the car's nose for CATCH_TIME seconds, or stopped within STOP_CATCH.
const CATCH_DIST := 15.0
const CATCH_TIME := 3.0
const STOP_CATCH := 40.0
## Lost: more than LOSE_DIST ahead for LOSE_TIME seconds.
const LOSE_DIST := 600.0
const LOSE_TIME := 20.0
## A chasing car's top speed (m/s, 130 mph) and how hard it speeds up and brakes; where it sits
## behind its rider once it's caught up.
const CHASE_TOP := 58.0
const CHASE_ACCEL := 5.5
const CHASE_BRAKE := 7.5
const FOLLOW := 9.0
## The speed limits: the open road, and through a village (within VILLAGE_REACH of its middle).
const OPEN_LIMIT := 26.8
const VILLAGE_LIMIT := 13.4
const VILLAGE_REACH := 220.0
## How often police turn up (m between them; the first a little sooner), and the share of them
## parked up in a lay-by with a speed gun.
const FIRST := [8000.0, 16000.0]
const EVERY := [15000.0, 25000.0]
const TRAP_SHARE := 0.4
## A patrol's pace (a share of the limit).
const PACE := [0.82, 0.95]
## A car turns up this far ahead of the leading rider, and goes when it's this far from everyone.
const SPAWN_AHEAD := 650.0
const DESPAWN := 1300.0
## How far into a lay-by a parked car sits (m past the road's edge).
const PARKED_OUT := 3.2
## The stop: the officer's walking pace, how long the words take, and how long a rider just let
## go is left alone by that car.
const WALK_SPEED := 1.4
const TALK_TIME := 7.0
const LET_OFF := 40.0
## The fines (£), and the points on your licence for what you couldn't pay.
const FINE_MIN := 100
const FINE_MAX := 600
const POINTS := 3
const MPH := 2.23694
## How often the host sends the cars to the crew (s).
const SEND_EVERY := 0.1
const MODES: Array[String] = ["patrol", "parked", "chase", "stop"]
const PACKED := 15              # numbers per car in pack()
const STAGES: Array[String] = ["", "pull", "walk", "talk", "back"]
## What the officer says, by how fast you were going.
const LINES: Array[String] = [
	"Morning. Do you know what speed you were doing back there? %d mph. That's a fine, I'm afraid.",
	"%d mph past a police car. Brave. Licence, please.",
	"I clocked you at %d mph. Not the place for it. You'll be paying for that.",
	"%d mph on this road? We had to work to catch you. Fine's coming your way.",
]

var trip: Node                 # the AdventureTrip (its main, for the HUD and your bike)
var world: AdventureWorld
var driver: PoliceDriver
## Whether this machine runs the police (the host, or solo).
var host := true
## Where the police turn up along the route: [{s, dir, trap, pace, used, site_s?, side?}].
var plan: Array = []
## id -> {id, mode, target, excess (mph over the rule's reference), near_t, lost_t, stage,
## stage_t, stop_s, let_off {peer: seconds left}, pace, trap}.
var cars := {}
## Instead of finding the riders (tests): () -> [{peer, s, v}], v along the road (+ the way s grows).
var rider_source := Callable()
## Every rider's place: peer -> {s, v}.
var riders := {}
## What was said on this machine (tests), newest last; and things that happened (host).
var messages: Array[String] = []
var events: Array = []
var _next_id := 1
var _send_t := 0.0
var _spawn_t := 0.0
var _fine_t := 0.0
var _paying := {}               # fine ids being paid here
var _track := {}                # peer -> {s, t} for working out speeds
var _sirens := {}               # car id -> PoliceSiren
var _officers := {}             # car id -> StaffFigure
var _clock := 0.0
var _limits := {}               # int(s / 25) -> the limit there
var _mirror_view: SubViewport   # the mirror, while you're being chased (see _mirror)
var _mirror_cam: Camera3D
var _mirror_box: Control


func _ready() -> void:
	name = "Police"
	host = Shed.is_authority()
	if driver == null:
		driver = PoliceDriver.new()
		driver.name = "PoliceDriver"
		add_child(driver)
	driver.host = host
	if world and not driver.sample.is_valid():
		driver.sample = road_sample
	if world and plan.is_empty():
		plan = plan_for(world.route)
	if not Net.police_received.is_connected(unpack):
		Net.police_received.connect(unpack)


func _exit_tree() -> void:
	if Net.police_received.is_connected(unpack):
		Net.police_received.disconnect(unpack)


## The road for the driver: s -> {pos, fwd, hw} in the local frame (see TrafficStream.sample).
func road_sample(s: float) -> Dictionary:
	var xf := world.transform_at(s)
	return {"pos": xf.origin, "fwd": -xf.basis.z, "hw": world.route.width_at_s(s) * 0.5}


# ---------------------------------------------------------------------------- planning and rules

## Where the police turn up along `route`, the same on every machine for its seed: one every
## EVERY metres (the first within FIRST), each going one way or the other at a pace of its own,
## and TRAP_SHARE of them parked in a lay-by (the nearest one, found when the riders get near).
static func plan_for(route: AdventureRoute) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = route.seed_value * 7919 + 1013
	var out := []
	var end := maxf(route.length, route.total) - 1000.0
	var s := rng.randf_range(FIRST[0], FIRST[1])
	while s < end:
		out.append({"s": s, "dir": 1 if rng.randf() < 0.5 else -1, "trap": rng.randf() < TRAP_SHARE,
			"pace": rng.randf_range(PACE[0], PACE[1]), "used": false})
		s += rng.randf_range(EVERY[0], EVERY[1])
	return out


## The speed limit at `s` (m/s), remembered by the 25 m.
func limit_here(s: float) -> float:
	var k := int(s / 25.0)
	if not _limits.has(k):
		if _limits.size() > 400:
			_limits.clear()
		_limits[k] = limit_at(world.route, k * 25.0 + 12.5)
	return _limits[k]


## The speed limit at `s` (m/s): 30 mph through a village, else 60.
static func limit_at(route: AdventureRoute, s: float) -> float:
	for kind in ["village", AdventureStops.ROW]:
		for st in route.sites_of(kind):
			if absf(float(st["s"]) - s) < VILLAGE_REACH:
				return VILLAGE_LIMIT
	return OPEN_LIMIT


## How far (m/s) a rider at `speed` is past what the rule allows passing a car going `police_v`
## (parked: past `limit`): over 0 and they're chased. The rule itself: THRESHOLD faster.
static func over_rule(speed: float, police_v: float, parked: bool, limit: float) -> float:
	var ref := limit if parked else absf(police_v)
	return absf(speed) - ref - THRESHOLD


## The fine (£) for going `over_mph` faster than the rule's reference (the car's speed, or the
## limit past a parked one: 30 or more, or they'd not have been chased), the `offence`th time
## that day: £100 at 30 over, £10 more a mph, half as much again for each time before; rounded
## to £10 and kept within £100-£600.
static func fine_amount(over_mph: float, offence: int) -> int:
	var base := 100.0 + maxf(0.0, over_mph - 30.0) * 10.0
	var f := base * (1.0 + 0.5 * maxi(0, offence - 1))
	return clampi(roundi(f / 10.0) * 10, FINE_MIN, FINE_MAX)


## The police's part of the adventure's state: {next, fines [{id, peer, amount, mph, day, n,
## paid (-1 till paid), points}], count {peer: [day, n]}}.
static func state() -> Dictionary:
	var p = Shed.adventure.get("police", {})
	return p if p is Dictionary else {}


static func fines_of(peer: int) -> Array:
	return (state().get("fines", []) as Array).filter(func(f): return int(f["peer"]) == peer)


## How many times `peer` has been done today (the shed's money day).
static func offences_today(peer: int) -> int:
	var c = (state().get("count", {}) as Dictionary).get(peer, [])
	return int(c[1]) if c is Array and c.size() == 2 and int(c[0]) == _day() else 0


static func _day() -> int:
	var bank = Shed.get("bank")
	return int(bank.get("day", 0)) if bank is Dictionary else 0


## Shed actions: adventure_police_fine {peer, mph, car} (the host, once its officer has had his
## say) and adventure_police_paid {id, paid, points} (the fined player, once it's paid).
static func check(peer: int, action: Dictionary) -> String:
	if not Adventure.active():
		return "There's no adventure on."
	match str(action.get("a", "")):
		"adventure_police_fine":
			if Net.is_online() and peer != 1:
				return "Only the police fine people."
		"adventure_police_paid":
			for f in state().get("fines", []):
				if int(f["id"]) == int(action.get("id", 0)):
					return "" if int(f["peer"]) == peer and int(f["paid"]) < 0 else "That fine's not yours to pay."
			return "There's no such fine."
	return ""


static func apply(_peer: int, action: Dictionary) -> String:
	var p := state().duplicate(true)
	if not p.has("fines"):
		p = {"next": 1, "fines": [], "count": {}}
	match str(action.get("a", "")):
		"adventure_police_fine":
			var who := int(action.get("peer", 0))
			var day := _day()
			var c = (p["count"] as Dictionary).get(who, [])
			var n := (int(c[1]) if c is Array and c.size() == 2 and int(c[0]) == day else 0) + 1
			p["count"][who] = [day, n]
			var mph := float(action.get("mph", 30.0))
			var id := int(p["next"])
			p["next"] = id + 1
			(p["fines"] as Array).append({"id": id, "peer": who, "amount": fine_amount(mph, n), "mph": roundi(mph),
				"day": day, "n": n, "paid": -1, "points": 0})
			while (p["fines"] as Array).size() > 24:
				(p["fines"] as Array).pop_front()
		"adventure_police_paid":
			for f in p["fines"]:
				if int(f["id"]) == int(action.get("id", 0)):
					f["paid"] = maxi(0, int(action.get("paid", 0)))
					f["points"] = maxi(0, int(action.get("points", 0)))
	Shed.adventure["police"] = p
	return ""


# ---------------------------------------------------------------------------- each tick

func _physics_process(delta: float) -> void:
	if world == null or world.route == null:
		return
	var pt := Perf.t0()
	tick(delta)
	Perf.add("police", pt)


## Everything for `delta` seconds: where the riders are, the host's police deciding and driving,
## the cars moved, their lamps, sirens and officers, and any fine of yours paid.
func tick(delta: float) -> void:
	_clock += delta
	_track_riders(delta)
	if host:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = 0.5
			_spawn_and_despawn()
		for id in cars.keys():
			_think(cars[id], delta)
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = SEND_EVERY
			if Net.is_online():
				Net.send_police(pack())
	driver.step(delta)
	_show(delta)
	_mirror()
	_fine_t -= delta
	if _fine_t <= 0.0:
		_fine_t = 0.25
		pay_fines()


## Every rider's distance along the road and speed along it (+ the way s grows): yours and the
## crew's from where they are, their speed their bike's own (as it reports it: network jitter
## isn't speed), or on foot from how they move (smoothed, and a jump down the road isn't speed).
func _track_riders(delta: float) -> void:
	if rider_source.is_valid():
		riders.clear()
		for r in rider_source.call():
			riders[int(r["peer"])] = {"s": float(r["s"]), "v": float(r["v"])}
		return
	var spots := {}     # peer -> [where, velocity or null]
	if trip and trip.get("main"):
		var main = trip.main
		if main.bike:
			spots[Shed.me()] = [main.bike.global_position, main.bike.linear_velocity]
		elif main.walker:
			spots[Shed.me()] = [main.walker.global_position, null]
		for peer in main.remotes:
			var rp = main.remotes[peer]
			if is_instance_valid(rp):
				spots[int(peer)] = [rp.world_position(), rp.bike.current_velocity() if rp.bike else null]
	for peer in riders.keys():
		if not spots.has(peer):
			riders.erase(peer)
			_track.erase(peer)
	for peer in spots:
		var s := world.distance_of(spots[peer][0], "police_%d" % peer)
		if s < 0.0:
			continue
		var tr: Dictionary = _track.get(peer, {"s": s, "v": 0.0})
		var ds := s - float(tr["s"])
		var v := float(tr["v"])
		if spots[peer][1] is Vector3:
			v = (spots[peer][1] as Vector3).dot(-world.transform_at(s).basis.z)
		elif absf(ds) < 90.0 and delta > 0.0:
			v = lerpf(v, ds / delta, 1.0 - exp(-delta / 0.35))
		else:
			v = 0.0
		_track[peer] = {"s": s, "v": v}
		riders[peer] = {"s": s, "v": v}


## Host: brings in the police planned near the riders and lets go of those left far behind.
func _spawn_and_despawn() -> void:
	if riders.is_empty():
		return
	var lead := -INF
	var trail := INF
	for p in riders:
		lead = maxf(lead, float(riders[p]["s"]))
		trail = minf(trail, float(riders[p]["s"]))
	var road_end := minf(world.route.length, world.route.stream_end()) - 60.0
	for e in plan:
		if e["used"]:
			continue
		if float(e["s"]) < trail - 200.0:
			e["used"] = true   # behind everyone already (an adventure carried on past it)
			continue
		if e["trap"] and not e.has("site_s") and float(e["s"]) - lead < 5000.0:
			_find_layby(e, lead)
		var at := float(e.get("site_s", e["s"]))
		if at - lead < SPAWN_AHEAD and at < road_end:
			e["used"] = true
			spawn(at, int(e["dir"]), e["trap"] and e.has("site_s"), float(e["pace"]), int(e.get("side", 0)))
	for id in cars.keys():
		var b: Dictionary = cars[id]
		var st := driver.state(id)
		var far := INF
		for p in riders:
			far = minf(far, absf(float(riders[p]["s"]) - float(st["s"])))
		var off_road := float(st["s"]) < 5.0 or float(st["s"]) > road_end
		if (b["mode"] in ["patrol", "parked"] and far > DESPAWN) or off_road:
			remove(id)


## A trap planned near `e`: the nearest lay-by (or rest area, or viewpoint) ahead within 4 km,
## else it's a patrol after all.
func _find_layby(e: Dictionary, lead: float) -> void:
	var best := {}
	for kind in ["layby", "rest_area", "viewpoint"]:
		for st in world.route.sites_of(kind):
			if float(st["s"]) > lead + SPAWN_AHEAD * 0.5 and absf(float(st["s"]) - float(e["s"])) < 4000.0:
				if best.is_empty() or absf(float(st["s"]) - float(e["s"])) < absf(float(best["s"]) - float(e["s"])):
					best = st
	if best.is_empty():
		e["trap"] = false
	else:
		e["site_s"] = float(best["s"])
		e["side"] = int(best["side"])


## Host: a police car `s` metres along: driving `dir` at `pace` x the limit, or parked in the
## lay-by on `side` (-1 left of the way s grows, +1 right), facing the way that side's traffic
## goes. Returns its id.
func spawn(s: float, dir: int, parked := false, pace := 0.9, side := -1) -> int:
	var id := _next_id
	_next_id += 1
	var lane := NAN
	var v := pace * limit_here(s)
	if parked:
		dir = 1 if side <= 0 else -1
		lane = world.route.width_at_s(s) * 0.5 + PARKED_OUT
		v = 0.0
	driver.add(id, s, dir, v, lane)
	cars[id] = {"id": id, "mode": "parked" if parked else "patrol", "target": 0, "excess": 0.0, "near_t": 0.0, "lost_t": 0.0,
		"stage": "", "stage_t": 0.0, "stop_s": 0.0, "let_off": {}, "pace": pace, "trap": parked, "speed": 0.0}
	events.append(["spawn", id, "parked" if parked else "patrol"])
	return id


func remove(id: int) -> void:
	driver.remove(id)
	cars.erase(id)
	if _officers.has(id):
		(_officers[id] as Node).queue_free()
		_officers.erase(id)
	_sirens.erase(id)


## Host: one car's decisions for `delta` seconds.
func _think(b: Dictionary, delta: float) -> void:
	var id := int(b["id"])
	var st := driver.state(id)
	if st.is_empty():
		return
	for p in (b["let_off"] as Dictionary).keys():
		b["let_off"][p] = float(b["let_off"][p]) - delta
		if float(b["let_off"][p]) <= 0.0:
			b["let_off"].erase(p)
	var s := float(st["s"])
	var dir := int(st["dir"])
	var lane := driver.own_lane(s)
	var limit := limit_here(s)
	match str(b["mode"]):
		"patrol", "parked":
			var parked: bool = b["mode"] == "parked"
			if parked:
				driver.steer(id, 0.0, 2.0, 4.0, float(st["lane"]))
			else:
				driver.steer(id, float(b["pace"]) * limit, 2.0, 3.0, lane)
			var keys := riders.keys()
			keys.sort()
			for p in keys:
				var r: Dictionary = riders[p]
				if b["let_off"].has(p) or absf(float(r["s"]) - s) > RADAR:
					continue
				var over := over_rule(float(r["v"]), float(st["v"]), parked, limit)
				if over > 0.0:
					_start_chase(b, int(p), (over + THRESHOLD) * MPH, absf(float(r["v"])) * MPH)
					break
		"chase":
			if not riders.has(int(b["target"])):
				_give_up(b)
				return
			_chase(b, st, riders[int(b["target"])], delta)
		"stop":
			if not riders.has(int(b["target"])):
				_release(b)
				return
			_stop(b, st, riders[int(b["target"])], delta)


func _start_chase(b: Dictionary, peer: int, over_mph: float, mph: float) -> void:
	b["mode"] = "chase"
	b["target"] = peer
	b["excess"] = over_mph
	b["speed"] = mph
	b["near_t"] = 0.0
	b["lost_t"] = 0.0
	events.append(["chase", int(b["id"]), peer, roundi(over_mph)])
	_announce(b, "patrol", 0)


## Chasing rider `r`: turned to face them, flat out till close, then sat FOLLOW behind; round
## slower traffic when the other side's clear, behind it when not. Caught or lost as it goes.
func _chase(b: Dictionary, st: Dictionary, r: Dictionary, delta: float) -> void:
	var id := int(b["id"])
	var s := float(st["s"])
	var dir := int(st["dir"])
	var rs := float(r["s"])
	# Facing the way they're going (turning round if it has to); them stopped, towards them.
	var want_dir := dir
	if absf(float(r["v"])) > 2.0:
		want_dir = 1 if float(r["v"]) > 0.0 else -1
	elif absf(rs - s) > 5.0:
		want_dir = 1 if rs > s else -1
	var gap := (rs - s) * dir
	var rv := float(r["v"]) * dir
	var want := CHASE_TOP if gap > 150.0 else clampf(rv + clampf((gap - FOLLOW) * 0.6, -12.0, 30.0), 0.0, CHASE_TOP)
	if gap < 0.0 and rv > 2.0:
		want = clampf(rv - 6.0, 0.0, CHASE_TOP)   # still coming up behind: let them by, then go
	var lane := driver.own_lane(s)
	var lane_to := lane
	# Traffic in our lane between us and them: round it if the other side's clear, else behind it.
	var others := driver.traffic()
	for o in others:
		var ahead := (float(o["s"]) - s) * dir
		if int(o["dir"]) != dir or ahead < -12.0 or ahead > 55.0 or ahead > gap or float(o["v"]) > want - 2.0:
			continue
		var clear := true
		for q in others:
			var q_ahead := (float(q["s"]) - s) * dir
			if int(q["dir"]) == -dir and q_ahead > -10.0 and q_ahead < 260.0:
				clear = false
		if clear:
			lane_to = -lane
		elif ahead > 0.0:
			want = minf(want, float(o["v"]) + maxf(0.0, ahead - float(o["half"]) - 6.0) * 0.4)
	driver.steer(id, want, CHASE_ACCEL, CHASE_BRAKE, lane_to, want_dir)
	# Caught: close behind them a while, or they've stopped with us on them.
	if gap > 0.0 and gap < CATCH_DIST:
		b["near_t"] = float(b["near_t"]) + delta
	else:
		b["near_t"] = maxf(0.0, float(b["near_t"]) - delta * 0.5)
	if float(b["near_t"]) >= CATCH_TIME or (absf(float(r["v"])) < 2.0 and absf(rs - s) < STOP_CATCH):
		_caught(b)
		return
	# Lost: well out ahead for long enough.
	if absf(rs - s) > LOSE_DIST:
		b["lost_t"] = float(b["lost_t"]) + delta
		if float(b["lost_t"]) >= LOSE_TIME:
			_give_up(b)
	else:
		b["lost_t"] = 0.0


func _caught(b: Dictionary) -> void:
	b["mode"] = "stop"
	b["stage"] = "pull"
	b["stage_t"] = 0.0
	events.append(["caught", int(b["id"]), int(b["target"])])
	_announce(b, "chase", int(b["target"]))


func _give_up(b: Dictionary) -> void:
	var was := int(b["target"])
	b["mode"] = "patrol"
	b["target"] = 0
	b["let_off"][was] = LET_OFF
	events.append(["gave_up", int(b["id"]), was])
	_announce(b, "chase", was)


## Lets the rider go after a stop: back on patrol, leaving them be a while.
func _release(b: Dictionary) -> void:
	var was := int(b["target"])
	b["mode"] = "patrol"
	b["stage"] = ""
	b["target"] = 0
	b["let_off"][was] = LET_OFF
	events.append(["released", int(b["id"]), was])
	_announce(b, "stop", was)


## The stop: pulled in behind the rider as they brake to a halt (their throttle's cut, see
## holding), then the officer walks up, has his say (and the fine goes out), walks back, and
## they're let go.
func _stop(b: Dictionary, st: Dictionary, r: Dictionary, delta: float) -> void:
	var id := int(b["id"])
	var s := float(st["s"])
	var dir := int(st["dir"])
	var gap := (float(r["s"]) - s) * dir
	b["stage_t"] = float(b["stage_t"]) + delta
	var verge := driver.own_lane(s) + 0.7
	match str(b["stage"]):
		"pull":
			var rv := float(r["v"]) * dir
			# Up behind them, creeping the last few metres, and stopped FOLLOW back.
			var close := clampf((gap - FOLLOW) * 0.8, -6.0, 8.0)
			if gap > FOLLOW + 1.0:
				close = maxf(close, 1.5)
			# Gone past them as they stopped: round and back to them.
			var back := 0
			if gap < -25.0 and absf(float(r["v"])) < 2.0:
				back = -dir
				close = 6.0
			driver.steer(id, clampf(rv + close, 0.0, CHASE_TOP), CHASE_ACCEL, CHASE_BRAKE, verge, back)
			var there := gap < FOLLOW + 2.5 or float(b["stage_t"]) > 25.0
			if there and absf(float(r["v"])) < 0.6 and float(st["v"]) < 0.6 and float(b["stage_t"]) > 1.0:
				b["stage"] = "walk"
				b["stage_t"] = 0.0
				b["stop_s"] = float(r["s"])
			elif float(b["stage_t"]) > 40.0 and absf(gap) > LOSE_DIST:
				_give_up(b)
		"walk":
			driver.steer(id, 0.0, 1.0, CHASE_BRAKE, float(st["lane"]))
			if float(b["stage_t"]) >= walk_time(b, s):
				b["stage"] = "talk"
				b["stage_t"] = 0.0
				Shed.request({"a": "adventure_police_fine", "peer": int(b["target"]), "mph": float(b["excess"]), "car": id})
				events.append(["fined", id, int(b["target"])])
		"talk":
			driver.steer(id, 0.0, 1.0, CHASE_BRAKE, float(st["lane"]))
			if float(b["stage_t"]) >= TALK_TIME:
				b["stage"] = "back"
				b["stage_t"] = 0.0
		"back":
			driver.steer(id, 0.0, 1.0, CHASE_BRAKE, float(st["lane"]))
			if float(b["stage_t"]) >= walk_time(b, s):
				_release(b)


## How long the officer takes to walk from the car to the rider stopped at stop_s.
static func walk_time(b: Dictionary, car_s: float) -> float:
	return maxf(1.0, absf(float(b["stop_s"]) - car_s) - 2.5) / WALK_SPEED


## Whether `peer`'s bike is being pulled over (or held at the stop) by the police: their
## throttle's cut and they brake (see Main), till the officer's said his piece.
func holding(peer := -1) -> bool:
	var who := Shed.me() if peer < 0 else peer
	for id in cars:
		var b: Dictionary = cars[id]
		if b["mode"] == "stop" and int(b["target"]) == who and str(b["stage"]) in ["pull", "walk", "talk"]:
			return true
	return false


## Whether `peer` is being chased now.
func chasing(peer := -1) -> bool:
	var who := Shed.me() if peer < 0 else peer
	for id in cars:
		if cars[id]["mode"] == "chase" and int(cars[id]["target"]) == who:
			return true
	return false


# ---------------------------------------------------------------------------- what's said

## Something changed for car `b` (it was `old_mode`, after `old_target`): tells whoever it's
## about, and the crew.
func _announce(b: Dictionary, old_mode: String, old_target: int) -> void:
	var me := Shed.me()
	var mode := str(b["mode"])
	var target := int(b["target"])
	if mode == "chase" and old_mode != "chase":
		if target == me:
			var why := "%d mph over the limit past their speed trap" % roundi(float(b["excess"])) if b["trap"] \
				else "%d mph faster than them" % roundi(float(b["excess"]))
			_say("POLICE! Blue lights behind you: you went by %s (30's the most). Stop, or try to lose them." % why, true)
		else:
			_say("The police are after %s!" % _name(target), false)
	elif mode == "stop" and old_mode == "chase":
		if target == me:
			_say("Pulled over: the police have caught you. Pull in and stop.", true)
		else:
			_say("The police have pulled %s over." % _name(target), false)
	elif mode == "patrol" and old_mode == "chase" and old_target == me:
		_say("You've lost the police: they've given up the chase.", false)


func _say(text: String, bad: bool) -> void:
	messages.append(text)
	if messages.size() > 20:
		messages.pop_front()
	if trip and trip.get("main") and trip.main.hud:
		trip.main.hud.flash(text, 5.0, bad)


static func _name(peer: int) -> String:
	return str(Shed.crew.get(peer, {}).get("name", "a rider"))


## The officer's words, from car `id`, to the rider it caught (b["speed"]: how fast they went, mph).
static func line_for(id: int, b: Dictionary) -> String:
	return LINES[id % LINES.size()] % roundi(float(b.get("speed", 0.0)))


## Pays any fine of yours not yet paid, from your own money: all of it if you've got it, else
## what you have, and the rest as points on your licence. Tells you, and the host it's paid.
func pay_fines() -> void:
	var me := Shed.me()
	for f in fines_of(me):
		if int(f["paid"]) >= 0 or _paying.has(int(f["id"])):
			continue
		_paying[int(f["id"])] = true
		var amount := int(f["amount"])
		var have := Progress.money()
		var paid := mini(amount, have)
		var points := 0
		if paid > 0:
			Progress.spend(paid, "Police fine (%d mph)" % int(f["mph"]))
		var what := "Fined £%d for speeding, %d mph too fast%s" % [amount, int(f["mph"]), "" if int(f["n"]) <= 1 else " (the %s today)" % _nth(int(f["n"]))]
		var text := "%s: paid from your own money." % what
		if paid < amount:
			points = POINTS * (2 if amount - paid > 300 else 1)
			add_points(points)
			text = "%s: you only had £%d, so the rest goes on your licence as %d penalty points (%d now)." % [what, paid, points, licence_points()]
		_say(text, true)
		Shed.request({"a": "adventure_police_paid", "id": int(f["id"]), "paid": paid, "points": points})


static func _nth(n: int) -> String:
	return {2: "second time", 3: "third time"}.get(n, "%dth time" % n)


## The penalty points on your licence (kept with your character, see Progress).
static func licence_points() -> int:
	var stats = Progress.profile.get("stats", {})
	return int(stats.get("licence_points", 0)) if stats is Dictionary else 0


static func add_points(n: int) -> void:
	if Progress.profile.is_empty():
		return
	if not (Progress.profile.get("stats") is Dictionary):
		Progress.profile["stats"] = {}
	Progress.profile["stats"]["licence_points"] = licence_points() + n
	Progress._touch()


# ---------------------------------------------------------------------------- how they look

## Every machine: each car's blue lamps and siren, and its officer (beside a parked car with his
## speed gun, or walking up to whoever's been stopped and having a word).
func _show(delta: float) -> void:
	for id in cars:
		var b: Dictionary = cars[id]
		var body := driver.body(id)
		if body == null:
			continue
		var st := driver.state(id)
		var mode := str(b["mode"])
		var lit := mode == "chase" or (mode == "stop" and str(b["stage"]) != "back")
		body.set_blues(blues_at(_clock + id * 0.37) if lit else Vector2.ZERO)
		var wail := mode == "chase" or (mode == "stop" and str(b["stage"]) == "pull")
		if wail and not _sirens.has(id):
			var siren := PoliceSiren.new()
			siren.name = "Siren"
			siren.position = Vector3(0.0, 1.6, -0.6)
			body.add_child(siren)
			_sirens[id] = siren
		if _sirens.has(id):
			var siren: PoliceSiren = _sirens[id]
			siren.on = wail
			var gap := INF
			if riders.has(int(b["target"])):
				gap = absf(float(riders[int(b["target"])]["s"]) - float(st["s"]))
			siren.yelp = gap < 70.0
			siren.velocity = -body.global_transform.basis.z * float(st["v"])
		_officer(b, st, delta)


## While the police are after you (or stopping you), a rear-view mirror at the top of the
## screen: a small second view back down the road from your bike, flipped as a mirror is, so
## you can see the blue lights coming. Drawn only then (a second camera costs a frame's time).
func _mirror() -> void:
	var main = trip.main if trip and trip.get("main") else null
	var bike: Node3D = main.bike if main else null
	var want := bike != null and (chasing() or holding())
	if not want:
		if _mirror_box and _mirror_box.visible:
			_mirror_box.visible = false
			_mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _mirror_view == null:
		var layer := CanvasLayer.new()
		layer.layer = 4
		add_child(layer)
		_mirror_box = PanelContainer.new()
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color(0.02, 0.02, 0.02)
		frame.set_corner_radius_all(14)
		frame.set_content_margin_all(5)
		_mirror_box.add_theme_stylebox_override("panel", frame)
		_mirror_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mirror_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_mirror_box.position = Vector2(-215.0, 40.0)
		layer.add_child(_mirror_box)
		var holder := SubViewportContainer.new()
		holder.stretch = true
		holder.custom_minimum_size = Vector2(420.0, 120.0)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mirror_box.add_child(holder)
		_mirror_view = SubViewport.new()
		_mirror_view.size = Vector2i(420, 120)
		holder.add_child(_mirror_view)
		_mirror_cam = Camera3D.new()
		_mirror_cam.fov = 38.0
		_mirror_cam.far = 900.0
		_mirror_view.add_child(_mirror_cam)
		# Flipped left to right, as a mirror shows it.
		holder.scale = Vector2(-1.0, 1.0)
		holder.pivot_offset = Vector2(210.0, 60.0)
	_mirror_box.visible = true
	_mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var b := bike.global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	# The right-hand mirror, out on its stalk ahead of the rider: their shoulder at its inner edge.
	var right := fwd.cross(Vector3.UP)
	var eye := bike.global_position + Vector3.UP * 1.15 + fwd * 0.55 + right * 0.68
	_mirror_cam.global_transform = Transform3D(Basis.looking_at(-fwd + right * 0.06 + Vector3.DOWN * 0.03, Vector3.UP), eye)
	_mirror_cam.make_current()


## The blue lamps at time `t`: the left and right banks flashing in turn, each a double flash.
static func blues_at(t: float) -> Vector2:
	var x := fmod(t, 0.8) / 0.8
	var flash := func(u: float) -> float: return TrafficVehicle.BLUE_ON if (u < 0.12 or (u > 0.2 and u < 0.32)) else 0.0
	return Vector2(flash.call(x * 2.0) if x < 0.5 else 0.0, flash.call(x * 2.0 - 1.0) if x >= 0.5 else 0.0)


func _officer(b: Dictionary, st: Dictionary, delta: float) -> void:
	var id := int(b["id"])
	var mode := str(b["mode"])
	var stage := str(b["stage"])
	var shown := mode == "parked" or (mode == "stop" and stage in ["walk", "talk", "back"])
	if not shown:
		if _officers.has(id):
			(_officers[id] as Node).queue_free()
			_officers.erase(id)
		return
	var fig: StaffFigure = _officers.get(id)
	if fig == null:
		fig = StaffFigure.new()
		add_child(fig)
		fig.build({"id": 9000 + id, "name": "PC %d" % (1200 + id * 7), "role": "police",
			"look": {"top": Color(0.85, 0.9, 0.1), "legs": Color(0.05, 0.05, 0.07), "skin": Color(0.85, 0.66, 0.52),
				"hair": Color(0.15, 0.1, 0.05), "hat": true, "tall": 1.05}})
		fig.body.collision_layer = 0   # nothing to bump into or look at
		if mode == "parked":
			var gun := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.08, 0.12, 0.26)
			gun.mesh = box
			gun.position = Vector3(0.0, 0.0, -0.12)
			fig.hand.add_child(gun)
		_officers[id] = fig
	var s := float(st["s"])
	var dir := int(st["dir"])
	var side_lane := float(st["lane"]) + 1.3
	var at_s := s
	var face := -dir   # parked: looking back down the road at what's coming
	var walking := false
	var anim := ""
	var said := ""
	if mode == "parked":
		at_s = s - dir * 1.2
		anim = "spray"
	else:
		var to_s := float(b["stop_s"]) - dir * 0.9
		var from_s := s + dir * 1.0
		var f := clampf(float(b["stage_t"]) / walk_time(b, s), 0.0, 1.0)
		match stage:
			"walk":
				at_s = lerpf(from_s, to_s, f)
				face = dir
				walking = f < 1.0
			"talk":
				at_s = to_s
				face = 0
				anim = "talk"
				said = line_for(id, b)
			"back":
				at_s = lerpf(to_s, from_s, f)
				face = -dir
				walking = f < 1.0
	var xf := world.transform_at(at_s, -side_lane * dir)
	var road_fwd := -xf.basis.z
	var look := road_fwd * face if face != 0 else Vector3(road_fwd.z, 0.0, -road_fwd.x) * -dir   # talk: towards the road
	fig.global_transform = Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), xf.origin)
	fig.set_said(said)
	fig.animate(delta, walking, false, false, anim, false)


# ---------------------------------------------------------------------------- the crew

## For the network: per car [id, s, dir, v, lane, lane_want, mode, target (its high 16 bits),
## stage, stage_t, stop_s, excess, speed, trap, target (its low 16 bits)]: a peer id is too big to
## go whole in a float.
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in cars:
		var b: Dictionary = cars[id]
		var c: Dictionary = driver.cars.get(id, {})
		if c.is_empty():
			continue
		out.append_array([float(id), float(c["s"]), float(c["dir"]), float(c["v"]), float(c["lane"]), float(c["lane_want"]),
			float(MODES.find(b["mode"])), float(int(b["target"]) >> 16), float(STAGES.find(b["stage"])), float(b["stage_t"]),
			float(b["stop_s"]), float(b["excess"]), float(b["speed"]), 1.0 if b["trap"] else 0.0, float(int(b["target"]) & 0xFFFF)])
	return out


## Client: the host's cars (new ones put on the road, gone ones taken off), and anything that
## changed for you said.
func unpack(state_in: PackedFloat32Array) -> void:
	if host or world == null:
		return
	var seen := {}
	for k in range(0, state_in.size() - (PACKED - 1), PACKED):
		var id := int(state_in[k])
		var mi := int(state_in[k + 6])
		var si := int(state_in[k + 8])
		if mi < 0 or mi >= MODES.size() or si < 0 or si >= STAGES.size():
			continue
		seen[id] = true
		if not driver.has(id):
			driver.add(id, state_in[k + 1], int(state_in[k + 2]), state_in[k + 3], state_in[k + 4])
			cars[id] = {"id": id, "mode": MODES[mi], "target": 0, "excess": 0.0, "near_t": 0.0, "lost_t": 0.0, "stage": "",
				"stage_t": 0.0, "stop_s": 0.0, "let_off": {}, "pace": 1.0, "trap": MODES[mi] == "parked", "speed": 0.0}
		var c: Dictionary = driver.cars[id]
		c["dir"] = int(state_in[k + 2])
		c["v"] = state_in[k + 3]
		c["target"] = state_in[k + 1]
		c["lane_target"] = state_in[k + 4]
		c["lane_want"] = state_in[k + 5]
		var b: Dictionary = cars[id]
		var old_mode := str(b["mode"])
		var old_target := int(b["target"])
		b["mode"] = MODES[mi]
		b["target"] = (int(state_in[k + 7]) << 16) | int(state_in[k + 14])
		b["stage"] = STAGES[si]
		b["stage_t"] = state_in[k + 9]
		b["stop_s"] = state_in[k + 10]
		b["excess"] = state_in[k + 11]
		b["speed"] = state_in[k + 12]
		b["trap"] = state_in[k + 13] > 0.5
		if old_mode != b["mode"] or old_target != int(b["target"]):
			_announce(b, old_mode, old_target)
	for id in cars.keys():
		if not seen.has(id):
			remove(id)
