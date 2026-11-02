class_name TrafficStream
extends Node3D
## Cars, vans, lorries and coaches (TrafficVehicle) along any one road, for a road that isn't the
## riding map's network (the adventure's road, say): give it `sample`, a function from metres
## along the road to where the road is there, and keep `focus_s` (or `foci`, one for each group
## of riders) at where the riders are along it, and it keeps traffic going both ways round them,
## more of it where the road says it's built up. Like the town's traffic (RoadTraffic) none of it
## is simulated: each keeps to its lane (on the side of the road the country drives on, see
## keep_left) at a pace of its own (a share of the
## road's limit, lorries and coaches slower), slows for the bends ahead, crawls up steep hills
## when it's heavy (TrafficVehicle.TRAITS "power"), and hangs back a gap behind whatever's ahead
## in its lane, the stream's own vehicles and anything in `blockers`. Service buses pull in at
## `bus_stops` for a while. Solid for a bike to hit (group "road_traffic", see
## RoadTraffic._on_bike_hit), and the nearest few are heard (TrafficSounds).
##
##   var stream := TrafficStream.new()
##   stream.sample = func(s: float) -> Dictionary: return {"pos": ..., "fwd": ..., "hw": 3.5, "busy": 0.0}
##   add_child(stream)
##   stream.focus_s = rider_s   # each frame
##
## `sample(s)` returns {pos (Vector3, the centre line on the surface, in global space), fwd
## (Vector3, unit, the way s grows), hw (half the road's width, m), and optionally busy (0 open
## road .. 1 town), limit (m/s, else from busy) and grade (rise per metre the way s grows)}. The
## road may only exist round the focus (a streamed road): nothing is asked for further than
## `reach` from it, nor outside s_min..s_max.
##
## Scripted drivers: spawn_at() puts a given kind in at s going dir and returns its
## id; slot(id) reads where it is; take(id) hands back its live entry, which the stream then
## leaves alone (no driving, no despawning) while the taker writes its s, v, dir, lat (m right of
## the centre line, NAN for its lane), ind (-1 left, 0, 1 right) and aux (a small whole number
## sent to the crew as it is, e.g. lights and siren) each tick; release(id) gives it back to the
## stream to drive on from there; remove_id(id) takes it off the road.
##
## Junctions (`junctions`, see there): traffic stops at the lights while they're against it (a red,
## or an amber it can stop for: `signal_state`), slows round a roundabout's island and gives way
## at its line to anything already going round, and now and then turns off down a side road
## (indicating, a right turn waiting for what's coming) and drives off along it out of sight; and
## others come out of the side roads (`arm_at` says where they run), waiting at the mouth for the
## side road's green, a clear circle or a gap in the lanes they cross.
##
## Host-driven in co-op like RoadTraffic: the host runs it, and pack() / unpack() carry it to
## the crew (a few numbers per vehicle; the looks come from seeds).

## Most vehicles at once (spawn_at may go a couple over), and how many round each group of
## riders on the open road and in town.
const MAX_VEHICLES := 12
const OPEN_COUNT := 5
const TOWN_COUNT := 11
## The limits (m/s) out of town and in it, when the road doesn't give its own.
const OPEN_LIMIT := 22.0
const TOWN_LIMIT := 13.0
## Vehicles turn up between these distances along the road from the focus, and go past DESPAWN
## (the defaults of spawn_near, spawn_far and despawn).
const SPAWN_NEAR := 260.0
const SPAWN_FAR := 520.0
const DESPAWN := 650.0
const SPAWN_EVERY := 1.2
## The least bumper-to-bumper gap (m), and the time gap at speed (s), and how far ahead each
## looks for bends (it rechecks every BEND_EVERY seconds).
const GAP := 3.0
const HEADWAY := 1.3
## How hard a driver brakes for someone stood in the road ahead (m/s^2): seen in time to stop short of them.
const STOP_BRAKE := 3.0
const BEND_STEP := 6.0
const BEND_EVERY := 0.3
const LANE := 0.45
## A hill's pull on a climbing vehicle: its power (W/kg) over g x grade + this (rolling and air).
const CLIMB_DRAG := 0.12
## Service buses: the share of coaches that are, how long they stand at a stop (s), and how far
## ahead they start pulling in (m).
const BUS_SHARE := 0.65
const BUS_DWELL := [10.0, 18.0]
const BUS_PULL_IN := 70.0
## Now and then a supercar comes past on the open road, going well over the limit: the chance a
## vehicle turning up out of town is one (never more than one out at a time).
const SUPERCAR_CHANCE := 0.035
## The gaps (a ferry's water, see gaps): how far ahead one's looked for (m), how near one a vehicle stood waiting at it
## is let go once nobody's looking (m), and how far either side of one nothing turns up (m).
const GAP_LOOK := 200.0
const GAP_WAIT := 40.0
const GAP_CLEAR := 30.0
## Numbers sent for each vehicle (see pack).
const PACKED := 7
## Junctions: the share of drivers that turn off at one with a side road they can take (more in
## a village), the speed they take the turn at and the bend's length off the lane onto the side
## road (m), how fast they go along it, round a roundabout, and how often one comes out of a side
## road (s) when there's room for it. An out-of-sight side road's end is this far from the
## camera, or behind it.
const TURN_ODDS := 0.14
const TURN_ODDS_VILLAGE := 0.3
const TURN_SPEED := 4.5
const TURN_LEN := 10.0
const ARM_LIMIT := 9.0
const ROUND_SPEED := 7.5
const SIDE_EVERY := 3.0
const UNSEEN := 140.0
## A vehicle on a side road is sent with its lat past this (see pack).
const ARM_CODE := 10000.0

## s -> {pos, fwd, hw, busy?, limit?, grade?} (see above).
var sample: Callable
## Optional s -> the road's bend there (1/m, + bending right the way s grows); else worked out
## from two samples.
var curve: Callable
## Where the riders are along the road (m), or several groups' places in `foci` (when set).
var focus_s := 0.0
var foci: Array = []
## How far either way of the focus the road may be asked about, and the road's ends.
var reach := 700.0
var s_min := -INF
var s_max := INF
## Where they turn up and go (m from the nearest focus).
var spawn_near := SPAWN_NEAR
var spawn_far := SPAWN_FAR
var despawn := DESPAWN
## Turning up more where the road's busy (a town) than on the open road either side of it.
var weigh_busy := false
## Other things in the lanes to keep a gap behind: [[s, dir (+1, -1, or 0 for both lanes), half length], ...].
var blockers: Array = []
## Where service buses pull in: [{s (the shelter), dir (the way the buses that stop go)}, ...].
var bus_stops: Array = []
## Optional s -> whether the road drives on the left there (Britain, Ireland, Japan, India...);
## else it does everywhere, as the town's roads.
var keep_left: Callable
## Optional s -> Vector2(the way a one-way road goes there: 1 the way s grows, -1 against it, 0 both ways; and where
## the other way's traffic is instead, m right of the centre line: the other carriageway of a dual carriageway or
## motorway, NAN where there's none to see, as on a slip road). Where it's one way, the traffic going the other
## way keeps to the other carriageway, or isn't there at all.
var one_way: Callable
## Whether this machine runs it (the host, or a solo game); a client only moves them on between unpacks.
var host := true
## Stretches of the road that aren't road ([[s from, s to], ...]: a ferry's crossing, its water between the terminals).
## Nothing turns up on one or drives onto it: traffic coming to one stops short at the terminal, as if waiting for the
## boat, and is gone once nobody's looking.
var gaps: Array = []
## The junctions along it, in order of s: [{s (the middle), stop (m before the middle where traffic
## stops or gives way), lights (bool), village (bool: in or by one), ro and rc (a roundabout's
## outer and going-round radii; absent for none), arms: [{side (+1 right of the way s grows), len,
## w}]}, ...]; the same list on every machine (a vehicle on a side road is sent by its place in
## it). `signal_state(junction)` gives its lights, Vector2i(main road, side road) as
## AdventureJunctions.RED / RED_AMBER_ON / GREEN / AMBER_ON; `arm_at(junction, arm, t)` where a
## side road is `t` m out from its mouth, {pos (global, on its surface), fwd (unit, out along it)}.
var junctions: Array = []
var signal_state: Callable
var arm_at: Callable
## Each: {s, dir, v, pace, kind, seed (also its id), ind, aux, lat (NAN in its lane), bus,
## kerb (pulled in to the kerb), body (TrafficVehicle), bend (allowed speed for the bends ahead),
## bend_t (when to look again), climb (allowed speed up the hill), slowing, last_v, scripted,
## dwell (seconds left at a bus stop), served (the stop it last stood at); and at the junctions
## turn ([junction, arm, right] it's turning off at), seen (the last junction it decided at),
## and on a side road arm (its junction's index), k (which arm), t (m out along it: negative on
## the bend off the main road), out (going away from the main road), go (pulling out), parked
## (stood at the side road's end, gone once no one sees)}. On a side road `dir` is the way it
## goes on the main road, its s is worked from t (see _arm_s).
var vehicles: Array = []
var rng := RandomNumberGenerator.new()
## The engine sounds of the nearest few.
var sounds: TrafficSounds
var _spawn_timer := 0.0
var _seq := 0
var _side_timer := 0.0
var _near_j: Array = []   # the junctions within reach of the riders (indices into junctions)
var _near_t := 0.0


func _ready() -> void:
	if rng.seed == 0:
		rng.randomize()
	sounds = TrafficSounds.new()
	sounds.name = "Sounds"
	add_child(sounds)


func _physics_process(delta: float) -> void:
	if not sample.is_valid():
		return
	var pt := Perf.t0()
	step(delta)
	Perf.add("traffic", pt)


## Where the riders are: `foci`, or just focus_s.
func spots() -> Array:
	return foci if not foci.is_empty() else [focus_s]


## Which side of its way traffic keeps to at `s`: -1 its left, 1 its right (see keep_left).
func keep(s: float) -> int:
	return 1 if keep_left.is_valid() and not bool(keep_left.call(s)) else -1


## The road's one way at `s` (one_way): Vector2(its way, the other carriageway's offset), Vector2(0, NAN) both ways.
func ways(s: float) -> Vector2:
	return one_way.call(s) if one_way.is_valid() else Vector2(0.0, NAN)


## Whether going `dir` at `s` is against a one-way road with no other carriageway for it to be on.
func wrong_way(s: float, dir: int) -> bool:
	var w := ways(s)
	return w.x != 0.0 and int(w.x) != dir and is_nan(w.y)


## Whether `s` is on one of the gaps (a ferry's water), or within `margin` m of one.
func in_gap(s: float, margin := 0.0) -> bool:
	for g: Array in gaps:
		if s > float(g[0]) - margin and s < float(g[1]) + margin:
			return true
	return false


## How far (m) from `s` going `dir` to the start of the next gap ahead (INF for none within GAP_LOOK).
func gap_ahead(s: float, dir: int) -> float:
	var best := INF
	for g: Array in gaps:
		var edge := float(g[0]) if dir > 0 else float(g[1])
		var along := (edge - s) * dir
		if along >= -1.0 and along < minf(best, GAP_LOOK):
			best = maxf(along, 0.0)
	return best


## How far `s` is from the nearest focus.
func from_focus(s: float) -> float:
	var best := INF
	for f in spots():
		best = minf(best, absf(float(f) - s))
	return best


## Moves everything on `delta` seconds (and, on the host, brings new ones and lets far ones go).
func step(delta: float, draw := true) -> void:
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.5
		var jt := Perf.t0()
		_find_junctions()
		Perf.add("traffic_junctions", jt)
	var st := Perf.t0()
	if host:
		for i in range(vehicles.size() - 1, -1, -1):
			var d: Dictionary = vehicles[i]
			if d.get("scripted", false):
				continue
			var s := float(d["s"])
			if from_focus(s) > despawn or s < s_min or s > s_max or (d.get("parked", false) and unseen(_place_arm(d)[0])) \
					or in_gap(s) or (not d.has("arm") and float(d["v"]) < 0.5 and gap_ahead(s, int(d["dir"])) < GAP_WAIT \
					and unseen(sample.call(s)["pos"])):
				_remove(i)
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_EVERY
			if vehicles.size() < wanted():
				spawn_one()
		_side_timer -= delta
		if _side_timer <= 0.0:
			_side_timer = SIDE_EVERY
			if vehicles.size() < wanted():
				spawn_side()
	Perf.add("traffic_spawn", st)
	for d in vehicles:
		if host:
			if not d.get("scripted", false):
				if d.has("arm"):
					_drive_arm(d, delta)
				else:
					_drive(d, delta)
		elif d.has("arm"):
			var way := 1.0 if d["out"] else -1.0
			d["t"] = float(d["t"]) + way * float(d["v"]) * delta
			if d.has("target"):
				d["t"] = float(d["t"]) + (float(d["target"]) - float(d["t"])) * (1.0 - exp(-4.0 * delta))
				d["target"] = float(d["target"]) + way * float(d["v"]) * delta
			d["s"] = _arm_s(d)
		else:
			d["s"] = float(d["s"]) + int(d["dir"]) * float(d["v"]) * delta
			if d.has("target"):
				var err := float(d["target"]) - float(d["s"])
				d["s"] = float(d["s"]) + err * (1.0 - exp(-4.0 * delta))
				d["target"] = float(d["target"]) + int(d["dir"]) * float(d["v"]) * delta
	if host:
		# (one come to where its road is one way against it, with no other carriageway: it's gone before it's drawn)
		for i in range(vehicles.size() - 1, -1, -1):
			var d: Dictionary = vehicles[i]
			if not d.get("scripted", false) and not d.has("arm") and wrong_way(float(d["s"]), int(d["dir"])):
				_remove(i)
	if draw:
		draw_all(delta)


## Puts every vehicle where it's got to (step does it, unless the caller does it once a drawn frame instead).
func draw_all(delta: float) -> void:
	var dt := Perf.t0()
	_draw(delta)
	Perf.add("traffic_draw", dt)


## How many should be out round the riders, by how built up the road is round each group (a
## few hundred metres either way, so a town's traffic is there as you come into it).
func wanted() -> int:
	var total := 0
	for f in spots():
		var busy := 0.0
		for k in 5:
			var s := clampf(float(f) + (k - 2) * 150.0, s_min, s_max)
			busy = maxf(busy, float(sample.call(s).get("busy", 0.0)))
			if not weigh_busy:
				break
		total += roundi(lerpf(OPEN_COUNT, TOWN_COUNT, busy))
	return mini(MAX_VEHICLES, total)


func _limit(at: Dictionary) -> float:
	return float(at["limit"]) if at.has("limit") else lerpf(OPEN_LIMIT, TOWN_LIMIT, float(at.get("busy", 0.0)))


## A new vehicle out of sight along the road, either way, not too close to another. Returns it,
## or {} when it's full or the spot it tried was taken (or, weighing busy roads, passed over).
func spawn_one(near := spawn_near, far := spawn_far) -> Dictionary:
	if vehicles.size() >= MAX_VEHICLES:
		return {}
	var at_focus: Array = spots()
	var f := float(at_focus[rng.randi() % at_focus.size()])
	var s := f + rng.randf_range(near, minf(far, reach)) * (1.0 if rng.randf() < 0.5 else -1.0)
	if s < s_min or s > s_max or from_focus(s) < near - 0.01 or in_gap(s, GAP_CLEAR):
		return {}
	var dir := 1 if rng.randf() < 0.5 else -1
	if wrong_way(s, dir) or wrong_way(lerpf(s, f, 0.5), dir):
		dir = -dir   # (none coming the wrong way down a slip road)
	if wrong_way(s, dir) or not clear_at(s, dir, 30.0):
		return {}
	var at: Dictionary = sample.call(s)
	var busy := float(at.get("busy", 0.0))
	if weigh_busy and rng.randf() > 0.3 + 0.7 * busy:
		return {}
	var kind := TrafficVehicle.pick_kind(rng, busy > 0.5)
	var hw := float(at.get("hw", 3.5))
	if hw < 2.0 and kind in ["lorry", "coach"]:
		kind = "van"   # nothing that big down a single-track lane
	if busy < 0.3 and hw >= 2.5 and rng.randf() < SUPERCAR_CHANCE and not vehicles.any(func(o): return str(o["kind"]) == "supercar"):
		kind = "supercar"
	var pace := TrafficVehicle.pick_pace(rng, kind)
	var d := {"s": s, "dir": dir, "v": pace * _limit(at) * 0.9, "pace": pace, "kind": kind, "seed": _new_seed(), "ind": 0}
	d["bus"] = kind == "coach" and rng.randf() < BUS_SHARE
	_add(d)
	return d


## Whether nothing in lane `dir` is within `gap` (plus their lengths) of `s`.
func clear_at(s: float, dir: int, gap: float) -> bool:
	for o in vehicles:
		if int(o["dir"]) == dir and not o.has("arm") and absf(float(o["s"]) - s) < gap + TrafficVehicle.spec_of(str(o["kind"]))["len"]:
			return false
	return true


## A look seed no vehicle out now has (it's also how a vehicle is known: its id).
func _new_seed() -> int:
	while true:
		var seed_value := rng.randi() % 100000
		if find(seed_value).is_empty():
			return seed_value
	return 0


func _add(d: Dictionary) -> void:
	var car := TrafficVehicle.new()
	car.setup(str(d["kind"]), int(d["seed"]))
	add_child(car)
	d["body"] = car
	d["bend"] = INF
	d["bend_t"] = 0.0
	d["climb"] = INF
	d["slowing"] = 0.0
	d["last_v"] = float(d["v"])
	if not d.has("aux"):
		d["aux"] = 0
	if not d.has("lat"):
		d["lat"] = NAN
	d["kerb_f"] = 1.0 if d.get("kerb", false) else 0.0
	vehicles.append(d)


func _remove(i: int) -> void:
	(vehicles[i]["body"] as Node).queue_free()
	vehicles.remove_at(i)


## Everything off the road.
func clear() -> void:
	for i in range(vehicles.size() - 1, -1, -1):
		_remove(i)


# ---------------------------------------------------------------------------- scripted drivers

## Puts a `kind` (any of VehicleModel.KINDS) on the road at `s` going `dir` (+1 the way s grows,
## -1 back) at `v` m/s (negative: at its own pace's share of the limit there). Its id, or -1 if
## the road's full (MAX_VEHICLES + 2) or it's off the road's ends. Host only. `extra` is merged
## into its entry (bus, dwell, kerb, aux...).
func spawn_at(kind: String, s: float, dir: int, v := -1.0, extra := {}) -> int:
	if not host or vehicles.size() >= MAX_VEHICLES + 2 or s < s_min or s > s_max or not VehicleModel.SPECS.has(kind):
		return -1
	var at: Dictionary = sample.call(s)
	var pace := TrafficVehicle.pick_pace(rng, kind)
	var d := {"s": s, "dir": 1 if dir >= 0 else -1, "v": v if v >= 0.0 else pace * _limit(at) * 0.9, "pace": pace, "kind": kind,
		"seed": _new_seed(), "ind": 0, "bus": false}
	d.merge(extra, true)
	_add(d)
	return int(d["seed"])


## The live entry of vehicle `id` ({} if it's gone).
func find(id: int) -> Dictionary:
	for d in vehicles:
		if int(d["seed"]) == id:
			return d
	return {}


## Where vehicle `id` is: {id, kind, s, v, dir, lat (m right of the centre line), pos (global),
## fwd (unit, the way it's facing), scripted}, or {} if it's gone.
func slot(id: int) -> Dictionary:
	var d := find(id)
	if d.is_empty():
		return {}
	var where := _place_arm(d) if d.has("arm") else _place(d)
	return {"id": id, "kind": d["kind"], "s": float(d["s"]), "v": float(d["v"]), "dir": int(d["dir"]), "lat": float(where[2]),
		"pos": where[0], "fwd": where[1], "scripted": bool(d.get("scripted", false))}


## Every vehicle's id.
func ids() -> Array:
	return vehicles.map(func(d): return int(d["seed"]))


## Takes vehicle `id` over: the stream stops driving and despawning it, and the caller moves it
## by writing the returned entry's s, v, dir, lat, ind and aux. {} if it's gone.
func take(id: int) -> Dictionary:
	var d := find(id)
	if d.has("arm"):
		return {}   # off down a side road: not one to take over
	if not d.is_empty():
		d["scripted"] = true
		d.erase("dwell")
	return d


## Hands vehicle `id` back to the stream, which drives it on from where it is, in its own lane.
func release(id: int) -> void:
	var d := find(id)
	if d.is_empty():
		return
	d["scripted"] = false
	d["lat"] = NAN
	d["ind"] = 0
	d["bend_t"] = 0.0


## Takes vehicle `id` off the road.
func remove_id(id: int) -> void:
	for i in vehicles.size():
		if int(vehicles[i]["seed"]) == id:
			_remove(i)
			return


# ---------------------------------------------------------------------------- driving

## The road's bend at `s`: 1/m, + bending right going the way s grows.
func curvature(s: float) -> float:
	if curve.is_valid():
		return float(curve.call(s))
	var a: Vector3 = sample.call(s - 2.0)["fwd"]
	var b: Vector3 = sample.call(s + 2.0)["fwd"]
	return Vector2(a.x, a.z).cross(Vector2(b.x, b.z)) / 4.0


func _drive(d: Dictionary, delta: float) -> void:
	var tr := TrafficVehicle.traits_of(str(d["kind"]))
	var s := float(d["s"])
	var dir := int(d["dir"])
	var v := float(d["v"])
	var brake := float(tr["brake"])
	var at: Dictionary = sample.call(s)
	d["bend_t"] = float(d["bend_t"]) - delta
	if float(d["bend_t"]) <= 0.0:
		# The bends ahead, as far as it needs to stop in (rechecked now and then), and the hill.
		d["bend_t"] = BEND_EVERY
		var best := INF
		var look := maxf(40.0, v * v / (2.0 * brake) + 15.0)
		var dist := 0.0
		while dist <= look:
			var k := absf(curvature(s + dir * dist))
			var bend := sqrt(float(tr["grip"]) / maxf(k, 0.0005))
			best = minf(best, sqrt(bend * bend + 2.0 * brake * maxf(dist - v * BEND_EVERY, 0.0)))
			dist += BEND_STEP
		d["bend"] = best
		var grade := float(at["grade"]) if at.has("grade") else \
			((sample.call(s + 4.0)["pos"] as Vector3).y - (at["pos"] as Vector3).y) / 4.0
		grade *= dir
		d["climb"] = float(tr.get("power", 60.0)) / (9.81 * maxf(grade, 0.0) + CLIMB_DRAG)
		if grade < -0.05 and float(tr.get("power", 60.0)) < 20.0:
			# Down a steep hill a lorry or coach holds back in a low gear.
			d["climb"] = minf(float(d["climb"]), lerpf(16.0, 8.0, clampf((-grade - 0.05) / 0.07, 0.0, 1.0)))
	var allow := minf(minf(float(d["bend"]), float(d["climb"])), float(d["pace"]) * _limit(at))
	var half := TrafficVehicle.half_length_of(str(d["kind"]))
	allow = minf(allow, _junction_ahead(d, half, brake))
	allow = minf(allow, _stop_for(gap_ahead(s, dir) - half - 2.0, brake))
	for o in vehicles:
		if o != d and int(o["dir"]) == dir and _in_lane(o, float(at["hw"])):
			_follow(d, float(o["s"]), TrafficVehicle.half_length_of(str(o["kind"])), half)
	for b in blockers:
		if int(b[1]) == 0 or int(b[1]) == dir:
			_follow(d, float(b[0]), float(b[2]), half, true)
	allow = minf(allow, float(d.get("hold", INF)))
	d.erase("hold")
	if d.has("dwell"):
		allow = minf(allow, _stand(d, delta))
	else:
		if int(d["ind"]) > 0 and v > 6.0 and not d.has("turn"):
			d["ind"] = 0   # pulled out and away
		if d.get("bus", false):
			allow = minf(allow, _bus(d, half, brake))
	v = move_toward(v, allow, (brake * 1.6 if allow < v else float(tr["accel"])) * delta)
	d["v"] = v
	d["s"] = s + dir * v * delta
	if d.has("turn") and (float(d["s"]) - _turn_from(d)) * dir >= 0.0:
		# Onto the bend off the lane, down the side road.
		var turn: Array = d["turn"]
		d.erase("turn")
		d["arm"] = int(turn[0])
		d["k"] = int(turn[1])
		d["t"] = -TURN_LEN
		d["out"] = true
		d["s"] = _arm_s(d)


## Stood at the kerb (a bus at its stop, a parked car about to pull out) for its `dwell`
## seconds, indicating out for the last few, then away. Returns the speed it's allowed now.
func _stand(d: Dictionary, delta: float) -> float:
	d["dwell"] = float(d["dwell"]) - delta
	d["kerb"] = true
	d["ind"] = -keep(float(d["s"])) if float(d["dwell"]) < 2.5 else 0   # out from the kerb
	if float(d["dwell"]) > 0.0:
		return 0.0
	d.erase("dwell")
	d["kerb"] = false
	return INF


## A service bus: pulling in at the next stop in its way (indicating, to the kerb), where it
## stands a while (see _stand). Returns the speed it's allowed now.
func _bus(d: Dictionary, half: float, brake: float) -> float:
	var dir := int(d["dir"])
	var best := INF
	var stop_at := INF
	for st in bus_stops:
		if int(st["dir"]) != dir or absf(float(st["s"]) - float(d.get("served", -INF))) < 1.0:
			continue
		# Its door (just behind the front) by the shelter.
		var centre := float(st["s"]) + dir * (2.5 - half)
		var along := (centre - float(d["s"])) * dir
		if along > -2.0 and along < best:
			best = along
			stop_at = float(st["s"])
	if best > BUS_PULL_IN * 2.0:
		return INF
	if best < BUS_PULL_IN:
		d["ind"] = keep(float(d["s"]))   # in to the kerb
		d["kerb"] = true
	if best < 0.8 and float(d["v"]) < 0.6:
		d["dwell"] = rng.randf_range(BUS_DWELL[0], BUS_DWELL[1])
		d["served"] = stop_at
		return 0.0
	return sqrt(2.0 * brake * 0.6 * maxf(best, 0.0)) + 0.3


## Whether vehicle `o` is in its own lane: a scripted one put over on the other side (overtaking)
## or off the road (a police car in a lay-by) isn't in anyone's way there.
func _in_lane(o: Dictionary, hw: float) -> bool:
	if o.has("arm"):
		# Off the main road, but for the first half of the bend off it or the last onto it.
		return float(o["t"]) < -TURN_LEN * 0.5
	var lat := float(o.get("lat", NAN))
	return is_nan(lat) or (lat * int(o["dir"]) * keep(float(o["s"])) > 0.0 and absf(lat) < hw + 0.5)


## Holds vehicle `d` back behind something at `other_s` ahead of it in its lane: a vehicle (kept a headway behind it),
## or someone in the road (`standing`: seen from far enough off to stop short of them at STOP_BRAKE).
func _follow(d: Dictionary, other_s: float, other_half: float, half: float, standing := false) -> void:
	var along := (other_s - float(d["s"])) * int(d["dir"])
	var clear := along - half - other_half
	var v := float(d["v"])
	var reach := maxf(50.0, v * v / (2.0 * STOP_BRAKE) + GAP + 10.0) if standing else 50.0
	if along > 0.0 and clear < reach:
		var hold := maxf(0.0, (clear - GAP) / HEADWAY)
		if standing:
			hold = minf(hold, sqrt(2.0 * STOP_BRAKE * maxf(0.0, clear - GAP)))
		d["hold"] = minf(float(d.get("hold", INF)), hold)


# ---------------------------------------------------------------------------- junctions

## The junctions within reach of the riders now (rechecked twice a second).
func _find_junctions() -> void:
	_near_j = []
	for j in junctions.size():
		if from_focus(float(junctions[j]["s"])) < reach + 100.0:
			_near_j.append(j)


## The speed vehicle `d` (on the main road) is allowed for the junctions ahead: held at a red (or
## an amber it can stop for), slowed round a roundabout and waiting at its line while something's
## going round, and slowing for the turn when it's turning off (deciding whether it will as it
## comes up to each one).
func _junction_ahead(d: Dictionary, half: float, brake: float) -> float:
	var allow := INF
	var s := float(d["s"])
	var dir := int(d["dir"])
	var v := float(d["v"])
	for j in _near_j:
		var jn: Dictionary = junctions[j]
		var along := (float(jn["s"]) - s) * dir
		if along < -2.0 or along > 160.0:
			continue
		if along > 2.0 and along < 120.0 and int(d.get("seen", -1)) != j:
			d["seen"] = j
			_decide_turn(d, j)
		var to_line := along - float(jn["stop"]) - half   # its front to the stop line
		if jn.get("lights", false) and to_line > -0.5 and signal_state.is_valid():
			var light := int(signal_state.call(jn).x)
			# Amber: stop if it comfortably can, else go on through.
			if light == AdventureJunctions.RED or light == AdventureJunctions.RED_AMBER_ON \
					or (light == AdventureJunctions.AMBER_ON and to_line > v * v / (2.0 * brake * 0.7)):
				allow = minf(allow, _stop_for(to_line, brake))
		if jn.has("ro"):
			allow = minf(allow, sqrt(ROUND_SPEED * ROUND_SPEED + 2.0 * brake * 0.5 * maxf(along - float(jn["ro"]), 0.0)))
			if to_line > -0.5 and to_line < 30.0 and not _circle_clear(jn, d):
				allow = minf(allow, _stop_for(to_line, brake))
		if d.has("turn") and int(d["turn"][0]) == j:
			var to_turn := (_turn_from(d) - s) * dir
			allow = minf(allow, sqrt(TURN_SPEED * TURN_SPEED + 2.0 * brake * 0.5 * maxf(to_turn, 0.0)))
			if to_turn < 70.0:
				d["ind"] = int(jn["arms"][int(d["turn"][1])]["side"]) * dir   # 1 right, -1 left
			# Turning across the other lane (right where they drive on the left), so it waits for a gap in what's coming.
			if d["turn"][2] and not _lanes_clear(jn, [-dir], d):
				allow = minf(allow, _stop_for(to_turn, brake))
	return allow


## The speed from which it stops in `dist` m (gently).
static func _stop_for(dist: float, brake: float) -> float:
	return sqrt(2.0 * brake * 0.6 * maxf(dist - 0.5, 0.0))


## Whether vehicle `d` turns off at junction `j`, and down which side road: on its kerb side (its
## left where they drive on the left) whichever it is, on the other across the other lane (not at a
## roundabout: round the island it only takes the first exit). Nothing big, no bus and no supercar (it's only passing through) goes down a side road.
func _decide_turn(d: Dictionary, j: int) -> void:
	var jn: Dictionary = junctions[j]
	if d.get("bus", false) or str(d["kind"]) in ["lorry", "coach", "police", "supercar"] or d.has("dwell"):
		return
	if rng.randf() > (TURN_ODDS_VILLAGE if jn.get("village", false) else TURN_ODDS):
		return
	var dir := int(d["dir"])
	var kerb := keep(float(jn["s"])) * dir   # the arm side on its kerb's side
	var can := []
	for k in (jn["arms"] as Array).size():
		var side := int(jn["arms"][k]["side"])
		if side == kerb or (side == -kerb and not jn.has("ro")):
			can.append([j, k, side == -kerb])
	if not can.is_empty():
		d["turn"] = can[rng.randi() % can.size()]


## How far from junction `jn`'s middle along the main road the bend off it (before the middle)
## or onto it (past it) starts.
static func _bend_reach(jn: Dictionary) -> float:
	return float(jn["stop"]) + 1.5


func _turn_from(d: Dictionary) -> float:
	var jn: Dictionary = junctions[int(d["turn"][0])]
	return float(jn["s"]) - int(d["dir"]) * _bend_reach(jn)


## Whether nothing's going round roundabout `jn` but `d` itself: no vehicle past its own line and
## not yet out (nor on the bend off it or onto it), nor a rider in it.
func _circle_clear(jn: Dictionary, d: Dictionary) -> bool:
	var js := float(jn["s"])
	var ro := float(jn["ro"])
	var line := float(jn["stop"])
	for o in vehicles:
		if o == d:
			continue
		var ds := float(o["s"]) - js
		if o.has("arm"):
			if float(o["t"]) < 0.0 and absf(ds) < ro:
				return false
			continue
		var before := -ds * int(o["dir"])   # how far short of the middle it is
		if before < line - 0.3 and before > -ro:
			return false
	for b in blockers:
		if absf(float(b[0]) - js) < ro:
			return false
	return true


## Whether the main road's lanes `dirs` are clear enough to cross or pull into at junction `jn`:
## nothing in them coming up to it within a few seconds (nor just past, still across the mouth),
## nor a rider near it.
func _lanes_clear(jn: Dictionary, dirs: Array, d: Dictionary) -> bool:
	var js := float(jn["s"])
	for o in vehicles:
		if o == d or o.has("arm") or not int(o["dir"]) in dirs or not _in_lane(o, 3.0):
			continue
		var coming := (js - float(o["s"])) * int(o["dir"])
		if coming > -TrafficVehicle.half_length_of(str(o["kind"])) - 4.0 and coming < maxf(35.0, float(o["v"]) * 5.0):
			return false
	for b in blockers:
		if absf(float(b[0]) - js) < 45.0:
			return false
	return true


## Whether vehicle `d`, waiting at its side road's mouth, may pull out: at the lights on the side
## road's green, at a roundabout into a clear circle, else into a gap in the lanes it crosses.
func _may_join(d: Dictionary) -> bool:
	var jn: Dictionary = junctions[int(d["arm"])]
	if jn.get("lights", false) and signal_state.is_valid():
		return int(signal_state.call(jn).y) == AdventureJunctions.GREEN
	if jn.has("ro"):
		return _circle_clear(jn, d)
	var dir := int(d["dir"])
	var side := int(jn["arms"][int(d["k"])]["side"])
	return _lanes_clear(jn, [dir] if side == keep(float(jn["s"])) * dir else [dir, -dir], d)


## A vehicle on a side road: off along it and out of sight (stopping at its end, parked there
## till no one sees), or coming in to the mouth, waiting there, then the bend onto the main
## road, where it drives on as any other.
func _drive_arm(d: Dictionary, delta: float) -> void:
	var tr := TrafficVehicle.traits_of(str(d["kind"]))
	var brake := float(tr["brake"])
	var j := int(d["arm"])
	var jn: Dictionary = junctions[j]
	var arm: Dictionary = jn["arms"][int(d["k"])]
	var t := float(d["t"])
	var v := float(d["v"])
	var out: bool = d["out"]
	var allow := ARM_LIMIT if t >= 0.0 else TURN_SPEED + 1.5
	var half := TrafficVehicle.half_length_of(str(d["kind"]))
	if out:
		var end := float(arm["len"]) - 4.0
		allow = minf(allow, _stop_for(end - t + 0.5, brake))
		if t > 4.0:
			d["ind"] = 0
		if end - t < 1.0 and v < 0.3:
			d["parked"] = true
	elif not d.get("go", false):
		allow = minf(allow, _stop_for(t + 0.1, brake))
		d["ind"] = -1 if int(arm["side"]) == -int(d["dir"]) else 1
		if t < 1.5 and v < 1.0 and _may_join(d):
			d["go"] = true
	# Behind whatever's ahead of it along the same side road, going the same way.
	for o in vehicles:
		if o == d or not o.has("arm") or int(o["arm"]) != int(d["arm"]) or int(o["k"]) != int(d["k"]) or o["out"] != out:
			continue
		var ahead := (float(o["t"]) - t) * (1.0 if out else -1.0)
		var clear := ahead - half - TrafficVehicle.half_length_of(str(o["kind"]))
		if ahead > 0.0 and clear < 40.0:
			allow = minf(allow, maxf(0.0, (clear - GAP) / HEADWAY))
	v = move_toward(v, allow, (brake * 1.6 if allow < v else float(tr["accel"])) * delta)
	d["v"] = v
	t += (1.0 if out else -1.0) * v * delta
	d["t"] = t
	d["s"] = _arm_s(d)
	if not out and t <= -TURN_LEN:
		# Onto the main road: on in its lane from here.
		for key in ["arm", "k", "t", "out", "go"]:
			d.erase(key)
		d["s"] = float(jn["s"]) + int(d["dir"]) * _bend_reach(jn)
		d["ind"] = 0
		d["seen"] = j
		d["bend_t"] = 0.0


## Where along the main road a vehicle on a side road counts as being: the junction's middle, or
## along the bend between it and the lane.
func _arm_s(d: Dictionary) -> float:
	var jn: Dictionary = junctions[int(d["arm"])]
	var js := float(jn["s"])
	var t := float(d["t"])
	if t >= 0.0:
		return js
	var lane_s := js + (-1.0 if d["out"] else 1.0) * int(d["dir"]) * _bend_reach(jn)
	return lerpf(js, lane_s, clampf(-t / TURN_LEN, 0.0, 1.0))


## Where a vehicle on a side road is: [pos, fwd, lat] as _place (lat NAN). Along the side road on
## its kerb side, or on the bend, a curve from its lane on the main road to the mouth.
func _place_arm(d: Dictionary) -> Array:
	var jn: Dictionary = junctions[int(d["arm"])]
	var k := int(d["k"])
	var arm: Dictionary = jn["arms"][k]
	var out: bool = d["out"]
	var t := float(d["t"])
	var off := clampf(float(arm["w"]) * 0.25, 0.9, 1.4)
	var a: Dictionary = arm_at.call(jn, k, maxf(t, 0.0))
	var fwd: Vector3 = a["fwd"]
	var travel := fwd if out else -fwd
	var mouth: Vector3 = (a["pos"] as Vector3) + Vector3(-travel.z, 0.0, travel.x).normalized() * off * keep(float(jn["s"]))
	if t >= 0.0:
		return [mouth, travel, NAN]
	var js := float(jn["s"])
	var dir := int(d["dir"])
	var lane_s := js + (-1.0 if out else 1.0) * dir * _bend_reach(jn)
	var lane: Array = _place({"s": lane_s, "dir": dir, "kind": d["kind"]})
	var p0: Vector3 = lane[0]
	var u := clampf(1.0 + t / TURN_LEN, 0.0, 1.0)   # 0 in the lane, 1 at the mouth
	# A curve that leaves the lane along it and meets the side road along it (from the lane towards the mouth: on the
	# way out the way it's driven, on the way in backwards), so the vehicle never snaps round at either end.
	var along_lane: Vector3 = (lane[1] as Vector3) * (1.0 if out else -1.0)
	var reach := p0.distance_to(mouth) * 0.4
	var c1 := p0 + along_lane * reach
	var c2 := mouth - fwd * reach
	var v := 1.0 - u
	var pos := p0 * v * v * v + c1 * 3.0 * v * v * u + c2 * 3.0 * v * u * u + mouth * u * u * u
	var tangent := (c1 - p0) * 3.0 * v * v + (c2 - c1) * 6.0 * v * u + (mouth - c2) * 3.0 * u * u
	tangent.y = 0.0
	if tangent.length() < 0.01:
		tangent = travel
	tangent = tangent.normalized()
	return [pos, tangent if out else -tangent, NAN]


## Whether `pos` is out of everyone's sight: well away from the camera, or behind it (always, with
## no camera).
func unseen(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	if cam == null:
		return true
	var to := pos - cam.global_position
	return to.length() > UNSEEN or to.normalized().dot(-cam.global_basis.z) < 0.1


## A vehicle coming out of a side road near the riders: turning up at the far end of one whose
## end no one can see, heading in to the main road to turn onto its near side (left where they
## drive on the left; off a roundabout's, round it), or now and then the other way, across. Returns it, or {}.
func spawn_side() -> Dictionary:
	if vehicles.size() >= MAX_VEHICLES or not arm_at.is_valid():
		return {}
	var can := []
	for j in _near_j:
		var jn: Dictionary = junctions[j]
		if from_focus(float(jn["s"])) > spawn_far:
			continue
		for k in (jn["arms"] as Array).size():
			var end := float(jn["arms"][k]["len"]) - 4.0
			var busy := false
			for o in vehicles:
				if o.has("arm") and int(o["arm"]) == j and int(o["k"]) == k and float(o["t"]) > end - 25.0:
					busy = true
			if not busy and unseen((arm_at.call(jn, k, end) as Dictionary)["pos"]):
				can.append([j, k, end])
	if can.is_empty():
		return {}
	var pick: Array = can[rng.randi() % can.size()]
	var jn: Dictionary = junctions[int(pick[0])]
	var arm: Dictionary = jn["arms"][int(pick[1])]
	var side := int(arm["side"])
	var near := side * keep(float(jn["s"]))   # the way along the main road with the arm on its kerb side
	var dir := near if jn.has("ro") or rng.randf() < 0.6 else -near
	var kind := TrafficVehicle.pick_kind(rng, jn.get("village", false))
	if kind in ["lorry", "coach"] or (float(arm["w"]) < 4.0 and kind == "van"):
		kind = "hatchback"
	var pace := TrafficVehicle.pick_pace(rng, kind)
	var d := {"s": float(jn["s"]), "dir": dir, "v": ARM_LIMIT * 0.8, "pace": pace, "kind": kind, "seed": _new_seed(), "ind": 0,
		"bus": false, "arm": int(pick[0]), "k": int(pick[1]), "t": float(pick[2]), "out": false}
	_add(d)
	return d


# ---------------------------------------------------------------------------- drawing

## Where a vehicle is: [pos (global, its middle on the road), fwd (the way it faces), lat (m right
## of the centre line)]. In its lane (its kerb side, keep), wheels off the middle line and inside
## the road's edge, or at the kerb at a bus stop, or where a scripted driver put it.
func _place(d: Dictionary, at := {}) -> Array:
	var s := float(d["s"])
	var dir := int(d["dir"])
	if at.is_empty():
		at = sample.call(s)
	var fwd: Vector3 = at["fwd"]
	var right := Vector3(-fwd.z, 0.0, fwd.x).normalized()
	var hw := float(at["hw"])
	var spec := TrafficVehicle.spec_of(str(d["kind"]))
	var half_w := float(spec["w"])
	var lat := float(d.get("lat", NAN))
	var lane := minf(maxf(hw * LANE, half_w + 0.2), maxf(hw - half_w - 0.1, half_w + 0.1))
	if is_nan(lat):
		var kerb := maxf(hw - half_w - 0.1, lane)
		lat = keep(s) * dir * lerpf(lane, kerb, float(d.get("kerb_f", 0.0)))
		# (the other way along a dual carriageway: in its lane on the other carriageway)
		var w := ways(s)
		if w.x != 0.0 and int(w.x) != dir and not is_nan(w.y):
			lat += w.y
	var heading := fwd * dir
	for j in _near_j:
		var jn: Dictionary = junctions[j]
		if jn.has("rc") and absf(s - float(jn["s"])) < float(jn["rc"]) + 9.0:
			# Round the island on its kerb side, then back into the lane.
			var ds := s - float(jn["s"])
			var side := signf(lat) if absf(lat) > 0.3 else float(keep(s) * dir)
			lat += side * (AdventureJunctions.swing(jn, ds, lane, side) - lane)
			var slope := AdventureJunctions.swing(jn, ds + 0.5, lane, side) - AdventureJunctions.swing(jn, ds - 0.5, lane, side)
			heading = (fwd * dir + right * side * slope * dir).normalized()
	return [(at["pos"] as Vector3) + right * lat, heading, lat]


func _draw(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for d in vehicles:
		var car: TrafficVehicle = d["body"]
		var s := float(d["s"])
		var dir := int(d["dir"])
		d["kerb_f"] = move_toward(float(d.get("kerb_f", 0.0)), 1.0 if d.get("kerb", false) else 0.0, delta * 0.6)
		var at: Dictionary = sample.call(s)
		var on_arm: bool = d.has("arm")
		var where := _place_arm(d) if on_arm else _place(d, at)
		var pos: Vector3 = where[0]
		var f: Vector3 = where[1]
		var pitch := 0.0
		if on_arm:
			var probe: Dictionary = d.duplicate()
			probe["t"] = float(d["t"]) + (1.0 if d["out"] else -1.0) * 1.5
			var ahead_at: Vector3 = _place_arm(probe)[0]
			pitch = atan2(ahead_at.y - pos.y, 1.5)
		elif at.has("grade"):
			pitch = atan(float(at["grade"]) * dir)
		else:
			var ahead: Vector3 = sample.call(s + dir * car.length * 0.5)["pos"]
			var behind: Vector3 = sample.call(s - dir * car.length * 0.5)["pos"]
			pitch = atan2(ahead.y - behind.y, maxf(car.length, 1.0))
		var yaw := atan2(-f.x, -f.z)
		var v := float(d["v"])
		var dv := (float(d["last_v"]) - v) / maxf(delta, 0.001)
		d["last_v"] = v
		d["slowing"] = 0.4 if dv > 0.8 or v < 0.3 else maxf(float(d["slowing"]) - delta, 0.0)
		var axles: Array = TrafficVehicle.spec_of(str(d["kind"]))["axles"]
		var steer := 0.0 if on_arm else clampf(atan((float(axles[1]) - float(axles[0])) * curvature(s) * dir), -0.6, 0.6)
		var cam_at := cam.global_position if cam else pos + Vector3(0.0, 0.0, 1.0e5)
		car.drive(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos), v, steer,
			float(d["slowing"]) > 0.0, int(d["ind"]), delta, cam_at)
		car.aux = int(d.get("aux", 0))


# ---------------------------------------------------------------------------- the crew

## For the network: [s, dir, v, seed, kind (its place in VehicleModel.KINDS), flags (indicator + 1,
## + 4 at the kerb, + 8 x aux), lat (-999 in its lane)] for each vehicle; on a side road, its t
## for s and for lat ARM_CODE + (junction x 8 + arm) x 2 + (1 going out).
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in vehicles:
		var flags := int(d.get("ind", 0)) + 1 + (4 if d.get("kerb", false) else 0) + 8 * int(d.get("aux", 0))
		var lat := float(d.get("lat", NAN))
		var s := float(d["s"])
		if d.has("arm"):
			s = float(d["t"])
			lat = ARM_CODE + (int(d["arm"]) * 8 + int(d["k"])) * 2 + (1 if d["out"] else 0)
		out.append_array([s, float(d["dir"]), float(d["v"]), float(d["seed"]), float(VehicleModel.KINDS.find(d["kind"])),
			float(flags), -999.0 if is_nan(lat) else lat])
	return out


## Client: the host's vehicles (matched by seed; new ones built, gone ones removed), from a snapshot that came `late`
## seconds later than the quickest lately (each is aimed at where it has driven on to since).
func unpack(state: PackedFloat32Array, late := 0.0) -> void:
	var seen := {}
	for b in range(0, state.size() - PACKED + 1, PACKED):
		var seed_value := int(state[b + 3])
		var ki := int(state[b + 4])
		if ki < 0 or ki >= VehicleModel.KINDS.size():
			continue
		seen[seed_value] = true
		var flags := int(state[b + 5])
		var lat := NAN if state[b + 6] < -998.0 else state[b + 6]
		var arm := {}
		if lat > ARM_CODE - 0.5:
			var code := int(round(lat - ARM_CODE))
			if code >> 4 >= junctions.size() or (code >> 1) & 7 >= (junctions[code >> 4]["arms"] as Array).size():
				continue   # (a junction we don't have: the road changed under it)
			arm = {"arm": code >> 4, "k": (code >> 1) & 7, "out": code & 1 == 1, "t": state[b]}
			lat = NAN
		# Where it has driven on to since (its s, or its t on a side road: growing going out).
		var way := (1.0 if arm["out"] else -1.0) if not arm.is_empty() else state[b + 1]
		var on := state[b] + way * state[b + 2] * late
		var found := find(seed_value)
		if found.is_empty() or str(found["kind"]) != VehicleModel.KINDS[ki]:
			if not found.is_empty():
				remove_id(seed_value)
			found = {"s": state[b], "dir": int(state[b + 1]), "v": state[b + 2], "pace": 1.0, "kind": VehicleModel.KINDS[ki],
				"seed": seed_value, "ind": 0, "target": state[b], "kerb": flags & 4 != 0}
			found.merge(arm, true)
			_add(found)
		elif not arm.is_empty():
			# On a side road: its t is what moves (s follows from it).
			var was_on := found.has("arm") and int(found["arm"]) == int(arm["arm"]) and int(found["k"]) == int(arm["k"])
			found["dir"] = int(state[b + 1])
			found["v"] = state[b + 2]
			found["arm"] = arm["arm"]
			found["k"] = arm["k"]
			found["out"] = arm["out"]
			found["target"] = on
			if not was_on or absf(float(found["t"]) - on) > 25.0:
				found["t"] = on
		else:
			if found.has("arm"):
				for key in ["arm", "k", "t", "out"]:
					found.erase(key)
				found["s"] = state[b]
			found["dir"] = int(state[b + 1])
			found["v"] = state[b + 2]
			found["target"] = on
			if absf(float(found["s"]) - on) > 25.0:
				found["s"] = on
		found["ind"] = (flags & 3) - 1
		found["kerb"] = flags & 4 != 0
		found["aux"] = flags >> 3
		found["lat"] = lat
		if found.has("arm"):
			found["s"] = _arm_s(found)
	for i in range(vehicles.size() - 1, -1, -1):
		if not seen.has(int(vehicles[i]["seed"])):
			_remove(i)
