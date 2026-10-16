class_name RideTelemetry
extends RefCounted
## A data logger for the ridden bike: speed, lean, steering and bar torque, each tyre's slip,
## load and how much of its grip is in use, the controls, gear and revs, sampled RATE times a
## second for the whole ride. The ride overlay draws the last few seconds live, and the dyno
## desk shows the last ride (RideTelemetry.last). A long ride keeps every other sample once
## it fills up, so the whole ride always fits.

const RATE := 30.0
const MAX_SAMPLES := 36000     # 20 minutes at the full rate before it starts thinning out
## Every channel: [key, label, unit]. Slip angles and lean are in degrees.
const CHANNELS := [
	["t", "Time", "s"], ["speed", "Speed", "km/h"], ["lean", "Lean", "°"], ["steer", "Steering", "°"],
	["bar", "Bar torque", "Nm"], ["trail", "Trail", "mm"], ["wobble", "Steering shake", "°"], ["kappa_f", "Front slip ratio", ""], ["kappa_r", "Rear slip ratio", ""],
	["alpha_f", "Front slip angle", "°"], ["alpha_r", "Rear slip angle", "°"], ["load_f", "Front load", "N"],
	["load_r", "Rear load", "N"], ["grip_f", "Front grip used", ""], ["grip_r", "Rear grip used", ""],
	["throttle", "Throttle", ""], ["brake_f", "Front brake", ""], ["brake_r", "Rear brake", ""],
	["gear", "Gear", ""], ["rpm", "Revs", "rpm"], ["long_g", "Braking / drive", "g"], ["lat_g", "Cornering", "g"],
]

## The ride being recorded now, or the last one; the dyno desk shows it.
static var last: RideTelemetry

var bike_name := ""
var data := {}                 # channel key -> PackedFloat32Array
var interval := 1.0 / RATE     # seconds between kept samples (doubles each time it thins out)
var time := 0.0
var _wait := 0.0
var _last_speed := 0.0


func _init(name := "") -> void:
	bike_name = name
	for c in CHANNELS:
		data[c[0]] = PackedFloat32Array()
	last = self


func size() -> int:
	return (data["t"] as PackedFloat32Array).size()


## Called by the bike every physics step.
func step(bike: Bike, delta: float) -> void:
	time += delta
	_wait -= delta
	if _wait > 0.0:
		return
	var dt := interval - _wait
	_wait += interval
	if _wait < 0.0:
		_wait = interval
	var f: Dictionary = bike.wheels[0]
	var r: Dictionary = bike.wheels[1]
	var yaw_rate := bike.angular_velocity.dot(Vector3.UP)
	var long_g := (bike.speed - _last_speed) / maxf(dt, 1e-3) / Bike.G if size() > 0 else 0.0
	_last_speed = bike.speed
	add({
		"t": time, "speed": absf(bike.speed) * 3.6, "lean": rad_to_deg(bike.lean_angle), "steer": rad_to_deg(bike.steer),
		"bar": bike.bar_torque, "trail": bike.trail_now * 1000.0, "wobble": rad_to_deg(bike.wobble), "kappa_f": f["kappa"], "kappa_r": r["kappa"],
		"alpha_f": rad_to_deg(float(f["alpha"])), "alpha_r": rad_to_deg(float(r["alpha"])),
		"load_f": f["load"], "load_r": r["load"], "grip_f": f["grip_used"], "grip_r": r["grip_used"],
		"throttle": bike.throttle, "brake_f": bike.front_brake, "brake_r": bike.rear_brake,
		"gear": float(bike.gear), "rpm": bike.rpm, "long_g": long_g, "lat_g": -bike.speed * yaw_rate / Bike.G,
	})


## Adds one sample (channel -> value; missing channels read 0).
func add(sample: Dictionary) -> void:
	for c in CHANNELS:
		# Packed arrays are values: take it out of the dictionary (so it isn't copied), add, put it back.
		var a: PackedFloat32Array = data[c[0]]
		data[c[0]] = PackedFloat32Array()
		a.append(float(sample.get(c[0], 0.0)))
		data[c[0]] = a
	if size() >= MAX_SAMPLES:
		_thin()


## Keeps every other sample and halves the rate from here on.
func _thin() -> void:
	for k in data:
		var a: PackedFloat32Array = data[k]
		var out := PackedFloat32Array()
		out.resize(a.size() / 2)
		for i in out.size():
			out[i] = a[i * 2]
		data[k] = out
	interval *= 2.0


## The latest value of a channel.
func latest(key: String) -> float:
	var a: PackedFloat32Array = data.get(key, PackedFloat32Array())
	return a[-1] if not a.is_empty() else 0.0


## Index of the first sample in the last `seconds` of the ride.
func index_since(seconds: float) -> int:
	var t: PackedFloat32Array = data["t"]
	if t.is_empty():
		return 0
	var from := t[-1] - seconds
	var i := t.size() - 1
	while i > 0 and t[i - 1] >= from:
		i -= 1
	return i


## The ride's headline numbers for the dyno desk.
func summary() -> Dictionary:
	var out := {"duration": time, "top_kmh": 0.0, "max_lean": 0.0, "max_brake_g": 0.0, "max_lat_g": 0.0,
		"front_over": 0.0, "rear_over": 0.0, "max_wobble": 0.0}
	if size() == 0:
		return out
	var dt := interval
	for i in size():
		out["top_kmh"] = maxf(out["top_kmh"], data["speed"][i])
		out["max_lean"] = maxf(out["max_lean"], absf(data["lean"][i]))
		out["max_brake_g"] = maxf(out["max_brake_g"], -float(data["long_g"][i]))
		out["max_lat_g"] = maxf(out["max_lat_g"], absf(data["lat_g"][i]))
		out["max_wobble"] = maxf(out["max_wobble"], data["wobble"][i])
		# Seconds spent past the peak of grip: sliding or spinning.
		if data["grip_f"][i] > 1.0:
			out["front_over"] += dt
		if data["grip_r"][i] > 1.0:
			out["rear_over"] += dt
	return out
