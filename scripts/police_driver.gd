class_name PoliceDriver
extends Node3D
## Who moves the police cars along an adventure's road (see AdventurePolice), behind a small
## interface so the police themselves never care: the police say what each car should do this
## tick (a speed to make, how hard it may speed up and brake, and which part of the road to be on)
## and the driver moves it there and draws it. This one drives them itself, a kinematic follower
## along the road the way TrafficStream drives its own vehicles. Once the traffic has a stream on
## the adventure's road, a driver that spawns a "police" slot in that stream and takes the slot
## over (scripted control) and hands it back can stand in for this one by overriding the same
## handful of functions (add, remove, has, state, steer, body, traffic, step).
##
## Positions are distance along the road (s) and a lane: metres to the left of the centre line
## as the car faces (it's a left-hand road: about LANE x half the width is its own lane, minus
## that the other side's for overtaking, past the edge a lay-by), so a car is the same on every
## machine and never minds the floating origin moving.
##
## Host-driven in co-op like the traffic: the host's police steer the cars, and pack() / unpack()
## (in AdventurePolice) carry them to the crew, whose drivers move them on between updates.

## How far into its own half of the road a car keeps (a share of the half width).
const LANE := 0.45
## How quickly a car moves across the road (m/s), changing lanes or pulling over.
const LANE_RATE := 2.2
## The traffic's grip in the bends (sideways m/s^2) a police driver will use, and how far ahead
## it looks for them (rechecked every BEND_EVERY seconds).
const GRIP := 4.5
const BEND_STEP := 8.0
const BEND_EVERY := 0.25

## s -> {pos, fwd, hw} (see TrafficStream.sample): where the road is, in the local frame.
var sample: Callable
## Whether this machine steers them (the host, or a solo game); a client only moves them on
## between the host's updates.
var host := true
## id -> {s, dir, v, lane, want, accel, brake, lane_want, bend, bend_t, body, last_v, slowing,
## target?, lane_target?}.
var cars := {}
var _stream: Node = null       # a TrafficStream on the same road, when there is one
var _stream_t := 0.0
var _blockers: Array = []      # what we put in that stream's blockers last tick


# ---------------------------------------------------------------------------- the interface

## Puts car `id` on the road `s` metres along, facing `dir` (+1 the way s grows, -1 back),
## going `v` m/s, `lane` metres left of the centre line (NAN: its own lane).
func add(id: int, s: float, dir: int, v: float, lane := NAN) -> void:
	if cars.has(id):
		return
	var car := TrafficVehicle.new()
	car.setup("police", id)
	car.name = "Police%d" % id
	add_child(car)
	var at := lane if not is_nan(lane) else own_lane(s)
	cars[id] = {"s": s, "dir": dir, "v": v, "lane": at, "want": v, "accel": 2.0, "brake": 3.0, "lane_want": at,
		"bend": INF, "bend_t": 0.0, "body": car, "last_v": v, "slowing": 0.0}


func remove(id: int) -> void:
	if not cars.has(id):
		return
	(cars[id]["body"] as Node).queue_free()
	cars.erase(id)


func has(id: int) -> bool:
	return cars.has(id)


## Where car `id` is: {s, dir, v, lane}, or {} when there's no such car.
func state(id: int) -> Dictionary:
	if not cars.has(id):
		return {}
	var c: Dictionary = cars[id]
	return {"s": float(c["s"]), "dir": int(c["dir"]), "v": float(c["v"]), "lane": float(c["lane"])}


## What car `id` should do this tick: make `want` m/s (no faster than the bends ahead allow),
## speeding up at `accel` and braking at `brake` m/s^2, heading for `lane`; `dir` turns it round
## (only when it's all but stopped: it brakes for that first).
func steer(id: int, want: float, accel: float, brake: float, lane: float, dir := 0) -> void:
	if not cars.has(id):
		return
	var c: Dictionary = cars[id]
	if dir != 0 and dir != int(c["dir"]):
		if float(c["v"]) > 1.5:
			want = 0.0
		else:
			c["dir"] = dir
			c["v"] = 0.0
			c["bend_t"] = 0.0
	c["want"] = want
	c["accel"] = accel
	c["brake"] = brake
	c["lane_want"] = lane


## The car's model, for its lamps and siren.
func body(id: int) -> TrafficVehicle:
	return cars[id]["body"] if cars.has(id) else null


## The other vehicles on the road, for overtaking: [{s, dir, v, half}] (none without a stream).
func traffic() -> Array:
	var out := []
	var st := _find_stream()
	if st == null:
		return out
	for d in st.get("vehicles"):
		out.append({"s": float(d["s"]), "dir": int(d["dir"]), "v": float(d["v"]),
			"half": float(VehicleModel.SPECS[d["kind"]]["len"]) * 0.5})
	return out


## The lane (m left of the centre line) a car keeps to on its own side at `s`.
func own_lane(s: float) -> float:
	return half_width(s) * LANE


func half_width(s: float) -> float:
	return float(sample.call(s)["hw"]) if sample.is_valid() else 3.0


# ---------------------------------------------------------------------------- driving

## Moves every car on `delta` seconds and draws them (the police call it each physics tick).
func step(delta: float) -> void:
	_share_blockers()
	if not sample.is_valid():
		return
	for id in cars:
		var c: Dictionary = cars[id]
		if host:
			_drive(c, delta)
		else:
			c["s"] = float(c["s"]) + int(c["dir"]) * float(c["v"]) * delta
			if c.has("target"):
				var err := float(c["target"]) - float(c["s"])
				c["s"] = float(c["s"]) + err * (1.0 - exp(-4.0 * delta)) if absf(err) < 40.0 else float(c["target"])
				c["target"] = float(c["target"]) + int(c["dir"]) * float(c["v"]) * delta
			if c.has("lane_target"):
				c["lane"] = move_toward(float(c["lane"]), float(c["lane_target"]), LANE_RATE * 1.5 * delta)
	_draw(delta)


func _drive(c: Dictionary, delta: float) -> void:
	var s := float(c["s"])
	var dir := int(c["dir"])
	var v := float(c["v"])
	c["bend_t"] = float(c["bend_t"]) - delta
	if float(c["bend_t"]) <= 0.0:
		# The bends ahead, as far as it needs to stop in.
		c["bend_t"] = BEND_EVERY
		var brake := maxf(float(c["brake"]), 3.0)
		var best := INF
		var look := maxf(40.0, v * v / (2.0 * brake) + 20.0)
		var dist := 0.0
		while dist <= look:
			var k := absf(curvature(s + dir * dist))
			var bend := sqrt(GRIP / maxf(k, 0.0004))
			best = minf(best, sqrt(bend * bend + 2.0 * brake * maxf(dist - v * BEND_EVERY, 0.0)))
			dist += BEND_STEP
		c["bend"] = best
	var want := minf(float(c["want"]), float(c["bend"]))
	v = move_toward(v, want, (float(c["brake"]) if want < v else float(c["accel"])) * delta)
	c["v"] = v
	c["s"] = s + dir * v * delta
	c["lane"] = move_toward(float(c["lane"]), float(c["lane_want"]), LANE_RATE * delta)


## The road's bend at `s`: 1/m, + bending right going the way s grows (as TrafficStream's).
func curvature(s: float) -> float:
	var a: Vector3 = sample.call(s - 2.0)["fwd"]
	var b: Vector3 = sample.call(s + 2.0)["fwd"]
	return Vector2(a.x, a.z).cross(Vector2(b.x, b.z)) / 4.0


## Where car `c` is in the local frame, facing its way: its transform on the road.
func transform_of(c: Dictionary) -> Transform3D:
	var car: TrafficVehicle = c["body"]
	var s := float(c["s"])
	var dir := int(c["dir"])
	var at: Dictionary = sample.call(s)
	var f: Vector3 = (at["fwd"] as Vector3) * dir
	var left := Vector3(f.z, 0.0, -f.x).normalized()
	var pos: Vector3 = (at["pos"] as Vector3) + left * float(c["lane"])
	var ahead: Vector3 = sample.call(s + dir * car.length * 0.5)["pos"]
	var behind: Vector3 = sample.call(s - dir * car.length * 0.5)["pos"]
	var pitch := atan2(ahead.y - behind.y, maxf(car.length, 1.0))
	var yaw := atan2(-f.x, -f.z)
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos)


func _draw(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for id in cars:
		var c: Dictionary = cars[id]
		var car: TrafficVehicle = c["body"]
		var xf := transform_of(c)
		var v := float(c["v"])
		var dv := (float(c["last_v"]) - v) / maxf(delta, 0.001)
		c["last_v"] = v
		c["slowing"] = 0.4 if dv > 0.8 or v < 0.3 else maxf(float(c["slowing"]) - delta, 0.0)
		var axles: Array = VehicleModel.SPECS["police"]["axles"]
		var drift := (float(c["lane_want"]) - float(c["lane"])) if host else (float(c.get("lane_target", c["lane"])) - float(c["lane"]))
		var steer_a := atan((float(axles[1]) - float(axles[0])) * curvature(float(c["s"])) * int(c["dir"])) \
			- clampf(drift, -1.0, 1.0) * 0.08 * clampf(v / 10.0, 0.0, 1.0)
		var cam_at := cam.global_position if cam else xf.origin + Vector3(0.0, 0.0, 1.0e5)
		car.drive(xf, v, clampf(steer_a, -0.6, 0.6), float(c["slowing"]) > 0.0, 0, delta, cam_at)


# ---------------------------------------------------------------------------- the traffic

## The TrafficStream on the same road (a sibling under the adventure's world), looked for now
## and then; null when there's none.
func _find_stream() -> Node:
	if _stream != null and not is_instance_valid(_stream):
		_stream = null
	_stream_t -= get_physics_process_delta_time()
	if _stream == null and _stream_t <= 0.0 and get_parent() != null:
		_stream_t = 1.0
		for n in get_parent().find_children("*", "TrafficStream", true, false):
			_stream = n
			break
	return _stream


## Keeps the police cars in the stream's blockers, so the traffic slows behind them as it
## would behind anything else in its lane.
func _share_blockers() -> void:
	var st := _find_stream()
	if st == null:
		return
	var list: Array = st.get("blockers")
	for b in _blockers:
		list.erase(b)
	_blockers.clear()
	for id in cars:
		var c: Dictionary = cars[id]
		if float(c["lane"]) > 0.0 and float(c["lane"]) < half_width(float(c["s"])) + 0.5:
			var b := [float(c["s"]), int(c["dir"]), float(VehicleModel.SPECS["police"]["len"]) * 0.5]
			_blockers.append(b)
			list.append(b)
