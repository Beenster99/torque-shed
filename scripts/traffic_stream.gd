class_name TrafficStream
extends Node3D
## Cars, vans, lorries and coaches (TrafficVehicle) along any one road, for a road that isn't the
## riding map's network (the adventure's road, say): give it `sample`, a function from metres
## along the road to where the road is there, and keep `focus_s` at where the riders are along
## it, and it keeps traffic going both ways round them, more of it where the road says it's
## built up. Like the town's traffic (RoadTraffic) none of it is simulated: each keeps to its
## lane (left-hand road) at a pace of its own (a share of the road's limit, lorries and coaches
## slower), slows for the bends ahead, and hangs back a gap behind whatever's ahead in its lane,
## the stream's own vehicles and anything in `blockers`. Solid for a bike to hit (group
## "road_traffic", see RoadTraffic._on_bike_hit).
##
##   var stream := TrafficStream.new()
##   stream.sample = func(s: float) -> Dictionary: return {"pos": ..., "fwd": ..., "hw": 3.5, "busy": 0.0}
##   add_child(stream)
##   stream.focus_s = rider_s   # each frame
##
## `sample(s)` returns {pos (Vector3, the centre line on the surface, in global space), fwd
## (Vector3, unit, the way s grows), hw (half the road's width, m), and optionally busy (0 open
## road .. 1 town) and limit (m/s, else from busy)}. The road may only exist round the focus
## (a streamed road): nothing is asked for further than `reach` from it.
##
## Host-driven in co-op like RoadTraffic: the host runs it, and pack() / unpack() carry it to
## the crew (a few numbers per vehicle; the looks come from seeds).

## Most vehicles at once, and how many round the riders on the open road and in town.
const MAX_VEHICLES := 12
const OPEN_COUNT := 5
const TOWN_COUNT := 11
## The limits (m/s) out of town and in it, when the road doesn't give its own.
const OPEN_LIMIT := 22.0
const TOWN_LIMIT := 13.0
## Vehicles turn up between these distances along the road from the focus, and go past DESPAWN.
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

## s -> {pos, fwd, hw, busy?, limit?} (see above).
var sample: Callable
## Where the riders are along the road (m).
var focus_s := 0.0
## How far either way of the focus the road may be asked about.
var reach := 700.0
## Other things in the lanes to keep a gap behind: [[s, dir (+1, -1, or 0 for both lanes), half length], ...].
var blockers: Array = []
## Whether this machine runs it (the host, or a solo game); a client only moves them on between unpacks.
var host := true
## Each: {s, dir, v, pace, kind, seed, ind, body (TrafficVehicle), bend (allowed speed for the
## bends ahead), bend_t (when to look again), slowing, last_v}.
var vehicles: Array = []
var rng := RandomNumberGenerator.new()
var _spawn_timer := 0.0
var _seq := 0


func _ready() -> void:
	if rng.seed == 0:
		rng.randomize()


func _physics_process(delta: float) -> void:
	if not sample.is_valid():
		return
	var pt := Perf.t0()
	step(delta)
	Perf.add("traffic", pt)


## Moves everything on `delta` seconds (and, on the host, brings new ones and lets far ones go).
func step(delta: float) -> void:
	if host:
		for i in range(vehicles.size() - 1, -1, -1):
			if absf(float(vehicles[i]["s"]) - focus_s) > DESPAWN:
				_remove(i)
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_EVERY
			if vehicles.size() < wanted():
				spawn_one()
	for d in vehicles:
		if host:
			_drive(d, delta)
		else:
			d["s"] = float(d["s"]) + int(d["dir"]) * float(d["v"]) * delta
			if d.has("target"):
				var err := float(d["target"]) - float(d["s"])
				d["s"] = float(d["s"]) + err * (1.0 - exp(-4.0 * delta))
				d["target"] = float(d["target"]) + int(d["dir"]) * float(d["v"]) * delta
	_draw(delta)


## How many should be out round the focus, by how built up the road is there.
func wanted() -> int:
	var at: Dictionary = sample.call(focus_s)
	return mini(MAX_VEHICLES, roundi(lerpf(OPEN_COUNT, TOWN_COUNT, float(at.get("busy", 0.0)))))


func _limit(at: Dictionary) -> float:
	return float(at["limit"]) if at.has("limit") else lerpf(OPEN_LIMIT, TOWN_LIMIT, float(at.get("busy", 0.0)))


## A new vehicle out of sight along the road, either way, not too close to another. Returns it,
## or {} when it's full or the spot it tried was taken.
func spawn_one(near := SPAWN_NEAR, far := SPAWN_FAR) -> Dictionary:
	if vehicles.size() >= MAX_VEHICLES:
		return {}
	var s := focus_s + rng.randf_range(near, minf(far, reach)) * (1.0 if rng.randf() < 0.5 else -1.0)
	var dir := 1 if rng.randf() < 0.5 else -1
	for o in vehicles:
		if int(o["dir"]) == dir and absf(float(o["s"]) - s) < 30.0 + float(VehicleModel.SPECS[o["kind"]]["len"]):
			return {}
	var at: Dictionary = sample.call(s)
	var kind := TrafficVehicle.pick_kind(rng, float(at.get("busy", 0.0)) > 0.5)
	_seq += 1
	var pace := TrafficVehicle.pick_pace(rng, kind)
	var d := {"s": s, "dir": dir, "v": pace * _limit(at) * 0.9, "pace": pace, "kind": kind, "seed": rng.randi() % 100000, "ind": 0}
	_add(d)
	return d


func _add(d: Dictionary) -> void:
	var car := TrafficVehicle.new()
	car.setup(str(d["kind"]), int(d["seed"]))
	add_child(car)
	d["body"] = car
	d["bend"] = INF
	d["bend_t"] = 0.0
	d["slowing"] = 0.0
	d["last_v"] = float(d["v"])
	vehicles.append(d)


func _remove(i: int) -> void:
	(vehicles[i]["body"] as Node).queue_free()
	vehicles.remove_at(i)


## Everything off the road.
func clear() -> void:
	for i in range(vehicles.size() - 1, -1, -1):
		_remove(i)


## The road's bend at `s`: 1/m, + bending right going the way s grows.
func curvature(s: float) -> float:
	var a: Vector3 = sample.call(s - 2.0)["fwd"]
	var b: Vector3 = sample.call(s + 2.0)["fwd"]
	return Vector2(a.x, a.z).cross(Vector2(b.x, b.z)) / 4.0


func _drive(d: Dictionary, delta: float) -> void:
	var tr: Dictionary = TrafficVehicle.TRAITS[d["kind"]]
	var s := float(d["s"])
	var dir := int(d["dir"])
	var v := float(d["v"])
	var brake := float(tr["brake"])
	d["bend_t"] = float(d["bend_t"]) - delta
	if float(d["bend_t"]) <= 0.0:
		# The bends ahead, as far as it needs to stop in (rechecked now and then).
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
	var allow := minf(float(d["bend"]), float(d["pace"]) * _limit(sample.call(s)))
	var half := float(VehicleModel.SPECS[d["kind"]]["len"]) * 0.5
	for o in vehicles:
		if o != d and int(o["dir"]) == dir:
			_follow(d, float(o["s"]), float(VehicleModel.SPECS[o["kind"]]["len"]) * 0.5, half)
	for b in blockers:
		if int(b[1]) == 0 or int(b[1]) == dir:
			_follow(d, float(b[0]), float(b[2]), half)
	allow = minf(allow, float(d.get("hold", INF)))
	d.erase("hold")
	v = move_toward(v, allow, (brake * 1.6 if allow < v else float(tr["accel"])) * delta)
	d["v"] = v
	d["s"] = s + dir * v * delta


func _follow(d: Dictionary, other_s: float, other_half: float, half: float) -> void:
	var along := (other_s - float(d["s"])) * int(d["dir"])
	var clear := along - half - other_half
	if along > 0.0 and clear < 50.0:
		d["hold"] = minf(float(d.get("hold", INF)), maxf(0.0, (clear - GAP) / HEADWAY))


func _draw(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for d in vehicles:
		var car: TrafficVehicle = d["body"]
		var s := float(d["s"])
		var dir := int(d["dir"])
		var at: Dictionary = sample.call(s)
		var f: Vector3 = (at["fwd"] as Vector3) * dir
		var left := Vector3(f.z, 0.0, -f.x).normalized()
		var hw := float(at["hw"])
		var lane := minf(maxf(hw * LANE, car.half_width + 0.2), hw - car.half_width - 0.1)
		var pos: Vector3 = (at["pos"] as Vector3) + left * lane
		var ahead: Vector3 = sample.call(s + dir * car.length * 0.5)["pos"]
		var behind: Vector3 = sample.call(s - dir * car.length * 0.5)["pos"]
		var pitch := atan2(ahead.y - behind.y, maxf(car.length, 1.0))
		var yaw := atan2(-f.x, -f.z)
		var v := float(d["v"])
		var dv := (float(d["last_v"]) - v) / maxf(delta, 0.001)
		d["last_v"] = v
		d["slowing"] = 0.4 if dv > 0.8 or v < 0.3 else maxf(float(d["slowing"]) - delta, 0.0)
		var axles: Array = VehicleModel.SPECS[d["kind"]]["axles"]
		var steer := clampf(atan((float(axles[1]) - float(axles[0])) * curvature(s) * dir), -0.6, 0.6)
		var cam_at := cam.global_position if cam else pos + Vector3(0.0, 0.0, 1.0e5)
		car.drive(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos), v, steer,
			float(d["slowing"]) > 0.0, int(d["ind"]), delta, cam_at)


# ---------------------------------------------------------------------------- the crew

## For the network: [s, dir, v, seed, kind (its place in VehicleModel.KINDS)] for each vehicle.
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in vehicles:
		out.append_array([float(d["s"]), float(d["dir"]), float(d["v"]), float(d["seed"]), float(VehicleModel.KINDS.find(d["kind"]))])
	return out


## Client: the host's vehicles (matched by seed; new ones built, gone ones removed).
func unpack(state: PackedFloat32Array) -> void:
	var seen := {}
	for b in range(0, state.size() - 4, 5):
		var seed_value := int(state[b + 3])
		var ki := int(state[b + 4])
		if ki < 0 or ki >= VehicleModel.KINDS.size():
			continue
		seen[seed_value] = true
		var found := {}
		for d in vehicles:
			if int(d["seed"]) == seed_value:
				found = d
		if found.is_empty():
			_add({"s": state[b], "dir": int(state[b + 1]), "v": state[b + 2], "pace": 1.0, "kind": VehicleModel.KINDS[ki],
				"seed": seed_value, "ind": 0, "target": state[b]})
		else:
			found["dir"] = int(state[b + 1])
			found["v"] = state[b + 2]
			found["target"] = state[b]
			if absf(float(found["s"]) - state[b]) > 25.0:
				found["s"] = state[b]
	for i in range(vehicles.size() - 1, -1, -1):
		if not seen.has(int(vehicles[i]["seed"])):
			_remove(i)
