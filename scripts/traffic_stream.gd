class_name TrafficStream
extends Node3D
## Cars, vans, lorries and coaches (TrafficVehicle) along any one road, for a road that isn't the
## riding map's network (the adventure's road, say): give it `sample`, a function from metres
## along the road to where the road is there, and keep `focus_s` (or `foci`, one for each group
## of riders) at where the riders are along it, and it keeps traffic going both ways round them,
## more of it where the road says it's built up. Like the town's traffic (RoadTraffic) none of it
## is simulated: each keeps to its lane (left-hand road) at a pace of its own (a share of the
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
## Scripted drivers (the police): spawn_at() puts a given kind in at s going dir and returns its
## id; slot(id) reads where it is; take(id) hands back its live entry, which the stream then
## leaves alone (no driving, no despawning) while the taker writes its s, v, dir, lat (m right of
## the centre line, NAN for its lane), ind (-1 left, 0, 1 right) and aux (a small whole number
## sent to the crew as it is, e.g. lights and siren) each tick; release(id) gives it back to the
## stream to drive on from there; remove_id(id) takes it off the road.
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
## Numbers sent for each vehicle (see pack).
const PACKED := 7

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
## Whether this machine runs it (the host, or a solo game); a client only moves them on between unpacks.
var host := true
## Each: {s, dir, v, pace, kind, seed (also its id), ind, aux, lat (NAN in its lane), bus,
## kerb (pulled in to the kerb), body (TrafficVehicle), bend (allowed speed for the bends ahead),
## bend_t (when to look again), climb (allowed speed up the hill), slowing, last_v, scripted,
## dwell (seconds left at a bus stop), served (the stop it last stood at)}.
var vehicles: Array = []
var rng := RandomNumberGenerator.new()
## The engine sounds of the nearest few.
var sounds: TrafficSounds
var _spawn_timer := 0.0
var _seq := 0


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


## How far `s` is from the nearest focus.
func from_focus(s: float) -> float:
	var best := INF
	for f in spots():
		best = minf(best, absf(float(f) - s))
	return best


## Moves everything on `delta` seconds (and, on the host, brings new ones and lets far ones go).
func step(delta: float) -> void:
	if host:
		for i in range(vehicles.size() - 1, -1, -1):
			var d: Dictionary = vehicles[i]
			if d.get("scripted", false):
				continue
			var s := float(d["s"])
			if from_focus(s) > despawn or s < s_min or s > s_max:
				_remove(i)
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_EVERY
			if vehicles.size() < wanted():
				spawn_one()
	for d in vehicles:
		if host:
			if not d.get("scripted", false):
				_drive(d, delta)
		else:
			d["s"] = float(d["s"]) + int(d["dir"]) * float(d["v"]) * delta
			if d.has("target"):
				var err := float(d["target"]) - float(d["s"])
				d["s"] = float(d["s"]) + err * (1.0 - exp(-4.0 * delta))
				d["target"] = float(d["target"]) + int(d["dir"]) * float(d["v"]) * delta
	_draw(delta)


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
	if s < s_min or s > s_max or from_focus(s) < near - 0.01:
		return {}
	var dir := 1 if rng.randf() < 0.5 else -1
	if not clear_at(s, dir, 30.0):
		return {}
	var at: Dictionary = sample.call(s)
	var busy := float(at.get("busy", 0.0))
	if weigh_busy and rng.randf() > 0.3 + 0.7 * busy:
		return {}
	var kind := TrafficVehicle.pick_kind(rng, busy > 0.5)
	var hw := float(at.get("hw", 3.5))
	if hw < 2.0 and kind in ["lorry", "coach"]:
		kind = "van"   # nothing that big down a single-track lane
	var pace := TrafficVehicle.pick_pace(rng, kind)
	var d := {"s": s, "dir": dir, "v": pace * _limit(at) * 0.9, "pace": pace, "kind": kind, "seed": _new_seed(), "ind": 0}
	d["bus"] = kind == "coach" and rng.randf() < BUS_SHARE
	_add(d)
	return d


## Whether nothing in lane `dir` is within `gap` (plus their lengths) of `s`.
func clear_at(s: float, dir: int, gap: float) -> bool:
	for o in vehicles:
		if int(o["dir"]) == dir and absf(float(o["s"]) - s) < gap + TrafficVehicle.spec_of(str(o["kind"]))["len"]:
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
	var where := _place(d)
	return {"id": id, "kind": d["kind"], "s": float(d["s"]), "v": float(d["v"]), "dir": int(d["dir"]), "lat": float(where[2]),
		"pos": where[0], "fwd": where[1], "scripted": bool(d.get("scripted", false))}


## Every vehicle's id.
func ids() -> Array:
	return vehicles.map(func(d): return int(d["seed"]))


## Takes vehicle `id` over: the stream stops driving and despawning it, and the caller moves it
## by writing the returned entry's s, v, dir, lat, ind and aux. {} if it's gone.
func take(id: int) -> Dictionary:
	var d := find(id)
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
	var allow := minf(minf(float(d["bend"]), float(d["climb"])), float(d["pace"]) * _limit(at))
	var half := TrafficVehicle.half_length_of(str(d["kind"]))
	for o in vehicles:
		if o != d and int(o["dir"]) == dir:
			_follow(d, float(o["s"]), TrafficVehicle.half_length_of(str(o["kind"])), half)
	for b in blockers:
		if int(b[1]) == 0 or int(b[1]) == dir:
			_follow(d, float(b[0]), float(b[2]), half)
	allow = minf(allow, float(d.get("hold", INF)))
	d.erase("hold")
	if d.has("dwell"):
		allow = minf(allow, _stand(d, delta))
	else:
		if int(d["ind"]) > 0 and v > 6.0:
			d["ind"] = 0   # pulled out and away
		if d.get("bus", false):
			allow = minf(allow, _bus(d, half, brake))
	v = move_toward(v, allow, (brake * 1.6 if allow < v else float(tr["accel"])) * delta)
	d["v"] = v
	d["s"] = s + dir * v * delta


## Stood at the kerb (a bus at its stop, a parked car about to pull out) for its `dwell`
## seconds, indicating out for the last few, then away. Returns the speed it's allowed now.
func _stand(d: Dictionary, delta: float) -> float:
	d["dwell"] = float(d["dwell"]) - delta
	d["kerb"] = true
	d["ind"] = 1 if float(d["dwell"]) < 2.5 else 0
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
		d["ind"] = -1
		d["kerb"] = true
	if best < 0.8 and float(d["v"]) < 0.6:
		d["dwell"] = rng.randf_range(BUS_DWELL[0], BUS_DWELL[1])
		d["served"] = stop_at
		return 0.0
	return sqrt(2.0 * brake * 0.6 * maxf(best, 0.0)) + 0.3


func _follow(d: Dictionary, other_s: float, other_half: float, half: float) -> void:
	var along := (other_s - float(d["s"])) * int(d["dir"])
	var clear := along - half - other_half
	if along > 0.0 and clear < 50.0:
		d["hold"] = minf(float(d.get("hold", INF)), maxf(0.0, (clear - GAP) / HEADWAY))


# ---------------------------------------------------------------------------- drawing

## Where a vehicle is: [pos (global, its middle on the road), fwd (the way it faces), lat (m right
## of the centre line)]. In its lane (the left of its way), wheels off the middle line and inside
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
	if is_nan(lat):
		var lane := minf(maxf(hw * LANE, half_w + 0.2), maxf(hw - half_w - 0.1, half_w + 0.1))
		var kerb := maxf(hw - half_w - 0.1, lane)
		lat = -dir * lerpf(lane, kerb, float(d.get("kerb_f", 0.0)))
	return [(at["pos"] as Vector3) + right * lat, fwd * dir, lat]


func _draw(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for d in vehicles:
		var car: TrafficVehicle = d["body"]
		var s := float(d["s"])
		var dir := int(d["dir"])
		d["kerb_f"] = move_toward(float(d.get("kerb_f", 0.0)), 1.0 if d.get("kerb", false) else 0.0, delta * 0.6)
		var where := _place(d)
		var pos: Vector3 = where[0]
		var f: Vector3 = where[1]
		var ahead: Vector3 = sample.call(s + dir * car.length * 0.5)["pos"]
		var behind: Vector3 = sample.call(s - dir * car.length * 0.5)["pos"]
		var pitch := atan2(ahead.y - behind.y, maxf(car.length, 1.0))
		var yaw := atan2(-f.x, -f.z)
		var v := float(d["v"])
		var dv := (float(d["last_v"]) - v) / maxf(delta, 0.001)
		d["last_v"] = v
		d["slowing"] = 0.4 if dv > 0.8 or v < 0.3 else maxf(float(d["slowing"]) - delta, 0.0)
		var axles: Array = TrafficVehicle.spec_of(str(d["kind"]))["axles"]
		var steer := clampf(atan((float(axles[1]) - float(axles[0])) * curvature(s) * dir), -0.6, 0.6)
		var cam_at := cam.global_position if cam else pos + Vector3(0.0, 0.0, 1.0e5)
		car.drive(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos), v, steer,
			float(d["slowing"]) > 0.0, int(d["ind"]), delta, cam_at)
		car.aux = int(d.get("aux", 0))


# ---------------------------------------------------------------------------- the crew

## For the network: [s, dir, v, seed, kind (its place in VehicleModel.KINDS), flags (indicator + 1,
## + 4 at the kerb, + 8 x aux), lat (-999 in its lane)] for each vehicle.
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in vehicles:
		var flags := int(d.get("ind", 0)) + 1 + (4 if d.get("kerb", false) else 0) + 8 * int(d.get("aux", 0))
		var lat := float(d.get("lat", NAN))
		out.append_array([float(d["s"]), float(d["dir"]), float(d["v"]), float(d["seed"]), float(VehicleModel.KINDS.find(d["kind"])),
			float(flags), -999.0 if is_nan(lat) else lat])
	return out


## Client: the host's vehicles (matched by seed; new ones built, gone ones removed).
func unpack(state: PackedFloat32Array) -> void:
	var seen := {}
	for b in range(0, state.size() - PACKED + 1, PACKED):
		var seed_value := int(state[b + 3])
		var ki := int(state[b + 4])
		if ki < 0 or ki >= VehicleModel.KINDS.size():
			continue
		seen[seed_value] = true
		var flags := int(state[b + 5])
		var lat := NAN if state[b + 6] < -998.0 else state[b + 6]
		var found := find(seed_value)
		if found.is_empty() or str(found["kind"]) != VehicleModel.KINDS[ki]:
			if not found.is_empty():
				remove_id(seed_value)
			found = {"s": state[b], "dir": int(state[b + 1]), "v": state[b + 2], "pace": 1.0, "kind": VehicleModel.KINDS[ki],
				"seed": seed_value, "ind": 0, "target": state[b], "kerb": flags & 4 != 0}
			_add(found)
		else:
			found["dir"] = int(state[b + 1])
			found["v"] = state[b + 2]
			found["target"] = state[b]
			if absf(float(found["s"]) - state[b]) > 25.0:
				found["s"] = state[b]
		found["ind"] = (flags & 3) - 1
		found["kerb"] = flags & 4 != 0
		found["aux"] = flags >> 3
		found["lat"] = lat
	for i in range(vehicles.size() - 1, -1, -1):
		if not seen.has(int(vehicles[i]["seed"])):
			_remove(i)
