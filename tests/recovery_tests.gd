extends RefCounted
## The recovery truck, trailer and recovery contracts' checks, run from tests/run_tests.gd
## (its _test_recovery_* functions hand over to these), so they live together.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


## A flat test ground with the truck on it (and its trailer hitched on when `trailer`).
func _rig(trailer := false) -> Dictionary:
	var root := Node3D.new()
	t.add_child(root)
	root.add_child(TestGround.new(4000.0, "tarmac"))
	var car := Car.new()
	root.add_child(car)
	car.place(Transform3D())
	var out := {"root": root, "car": car}
	if trailer:
		var tr := Trailer.new()
		root.add_child(tr)
		tr.hitch_to(car)
		out["trailer"] = tr
	return out


func _drive(car: Car, seconds: float, drive: Callable) -> Dictionary:
	var stats := {"max_speed": 0.0, "max_roll": 0.0}
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in int(seconds * Engine.physics_ticks_per_second):
		drive.call(car, i * dt)
		await t.get_tree().physics_frame
		stats["max_speed"] = maxf(stats["max_speed"], car.speed)
		stats["max_roll"] = maxf(stats["max_roll"], absf(car.global_basis.x.y))
	return stats


func _heading(n: Node3D) -> float:
	var f := -n.global_basis.z
	return atan2(-f.x, -f.z)


## The truck sits on its springs, pulls away through the gears, turns, brakes to a stop with
## ABS, reverses, and the handbrake locks the back wheels.
func test_car() -> void:
	var r := _rig()
	var car: Car = r["car"]
	await _ticks(240)
	var all_down := car.wheels.all(func(w): return w["contact"])
	var sag: float = float(car.wheels[0]["compression"]) / Car.TRAVEL
	check(all_down and sag > 0.2 and sag < 0.8 and absf(car.speed) < 0.05,
		"the truck settles on its four wheels (front sag %d%%, %.2f m/s)" % [roundi(sag * 100.0), car.speed])
	var gears := {}
	var s := await _drive(car, 12.0, func(c, _t):
		c.throttle = 1.0
		gears[c.gear] = true)
	check(car.speed > 22.0 and car.speed < 40.0, "flat out for 12 s it reaches %.0f km/h" % (car.speed * 3.6))
	check(gears.size() >= 3 and car.gear >= 3, "the automatic changes up through the gears (%s, in %d now)" % [str(gears.keys()), car.gear])
	check(car.rpm < Car.REDLINE * 1.03 and car.rpm > Car.IDLE_RPM, "the revs stay under the red line (%.0f rpm)" % car.rpm)
	var tread: float = car.wheels[2]["kappa"]
	check(absf(tread) < 0.15, "the back tyres grip on tarmac (slip ratio %.2f)" % tread)
	var h0 := _heading(car)
	s = await _drive(car, 3.0, func(c, _t):
		c.throttle = 0.3
		c.steer_input = 1.0)
	var turned := wrapf(h0 - _heading(car), -PI, PI)
	check(turned > 0.3, "steering right turns it right (%.0f degrees in 3 s)" % rad_to_deg(turned))
	check(s["max_roll"] < 0.2, "it leans on its springs in the turn but stays on its wheels (%.2f)" % s["max_roll"])
	var from_v := car.speed
	var stop_at := car.global_position
	var locked := [false]
	var stopped := [-1.0]
	s = await _drive(car, 6.0, func(c, tt):
		c.throttle = 0.0
		c.steer_input = 0.0
		c.brake = 1.0 if stopped[0] < 0.0 else 0.0
		if c.speed > 3.0 and absf(float(c.wheels[0]["omega"])) < 0.5:
			locked[0] = true
		if stopped[0] < 0.0 and absf(c.speed) < 0.3:
			stopped[0] = tt)
	var dist := car.global_position.distance_to(stop_at)
	check(stopped[0] > 0.0 and stopped[0] < 5.0, "the brakes stop it from %.0f km/h in %.1f s (%.0f m)" % [from_v * 3.6, stopped[0], dist])
	check(not locked[0], "ABS keeps the front wheels turning under full braking")
	check(dist > 5.0 and dist < 60.0, "in a believable distance for its speed (%.1f m)" % dist)
	# Hold the brake when stopped: reverse. Then back up.
	await _drive(car, 1.0, func(c, _t): c.brake = 1.0)
	check(car.gear == -1, "holding the brake at a standstill puts the automatic in reverse")
	await _drive(car, 3.0, func(c, _t): c.brake = 1.0 if c.gear < 0 else 0.0)
	check(car.speed < -1.0 and car.speed > -9.0, "and it backs up on the brake pedal (%.1f m/s)" % car.speed)
	await _drive(car, 3.0, func(c, _t):
		c.brake = 0.0
		c.throttle = 1.0)
	check(car.gear >= 1 and car.speed > 0.5, "the throttle stops it and pulls away forwards again (gear %d)" % car.gear)
	await _drive(car, 4.0, func(c, _t): c.throttle = 1.0)
	await _drive(car, 0.5, func(c, _t):
		c.throttle = 0.0
		c.handbrake = 1.0)
	check(absf(float(car.wheels[2]["omega"])) < 1.0 and absf(float(car.wheels[0]["omega"])) > 5.0,
		"the handbrake locks the back wheels and leaves the fronts rolling")
	# The manual box.
	await _drive(car, 5.0, func(c, _t):
		c.handbrake = 1.0
		c.brake = 1.0)
	car.handbrake = 0.0
	car.brake = 0.0
	car.auto_shift = false
	car.gear = 1
	await _drive(car, 6.0, func(c, _t): c.throttle = 1.0)
	check(car.gear == 1 and car.rpm > Car.REDLINE * 0.95, "with the manual box it stays in first on the limiter (%.0f rpm)" % car.rpm)
	car.shift_up()
	check(car.gear == 2, "and changes up when told")
	check(Car.engine_torque(1800.0) > Car.engine_torque(900.0) and Car.engine_torque(4500.0) < Car.engine_torque(2500.0),
		"the torque curve peaks in the middle of the revs")
	r["root"].queue_free()
	await _ticks(2)


## The trailer follows the truck on its ball joint: it stays on the tow ball, tracks round a
## corner behind it, comes straight again, stays on its wheels, and slows the truck a little.
func test_trailer() -> void:
	var r := _rig(true)
	var car: Car = r["car"]
	var tr: Trailer = r["trailer"]
	await _ticks(240)
	var gap := tr.global_transform * Trailer.COUPLER - car.hitch_point()
	check(gap.length() < 0.08 and tr.wheels.all(func(w): return w["contact"]),
		"the trailer sits on its wheels with its coupler on the tow ball (%.3f m)" % gap.length())
	var most_gap := [0.0]
	var tilt := [0.0]
	var watch := func(c: Car) -> void:
		most_gap[0] = maxf(most_gap[0], (tr.global_transform * Trailer.COUPLER - c.hitch_point()).length())
		tilt[0] = maxf(tilt[0], absf(tr.global_basis.x.y))
	await _drive(car, 8.0, func(c, _t):
		c.throttle = 0.8
		watch.call(c))
	var v_with := car.speed
	var behind := (tr.global_position - car.global_position).dot(car.global_basis.z)
	check(behind > 4.5 and behind < 7.0 and absf(_heading(tr) - _heading(car)) < 0.05,
		"towed in a straight line it runs straight behind (%.1f m back)" % behind)
	var h0 := _heading(car)
	await _drive(car, 4.0, func(c, _t):
		c.throttle = 0.35
		c.steer_input = -0.8
		watch.call(c))
	var car_turn := wrapf(_heading(car) - h0, -PI, PI)
	var tr_turn := wrapf(_heading(tr) - h0, -PI, PI)
	check(car_turn > 0.5 and tr_turn > 0.25 and tr_turn < car_turn, "round a left-hander the trailer follows the truck round (truck %d deg, trailer %d deg)" % [
		roundi(rad_to_deg(car_turn)), roundi(rad_to_deg(tr_turn))])
	await _drive(car, 5.0, func(c, _t):
		c.throttle = 0.4
		c.steer_input = 0.0
		watch.call(c))
	var angle := absf(wrapf(_heading(tr) - _heading(car), -PI, PI))
	check(angle < 0.08, "and lines up behind again once it's straight (%.1f deg)" % rad_to_deg(angle))
	check(most_gap[0] < 0.15 and tilt[0] < 0.2, "it never leaves the ball (%.2f m) or leans over (%.2f)" % [most_gap[0], tilt[0]])
	await _drive(car, 6.0, func(c, _t):
		c.throttle = 0.0
		c.brake = 1.0 if absf(c.speed) > 0.3 else 0.0
		watch.call(c))
	check(absf(car.speed) < 0.4 and absf(tr.linear_velocity.length()) < 0.6, "the truck pulls it up to a stop")
	r["root"].queue_free()
	await _ticks(2)
	var solo := _rig()
	var s := await _drive(solo["car"], 8.0, func(c, _t): c.throttle = 0.8)
	check(float(s["max_speed"]) > v_with, "the truck pulls away quicker without it (%.0f vs %.0f km/h in 8 s)" % [float(s["max_speed"]) * 3.6, v_with * 3.6])
	solo["root"].queue_free()
	await _ticks(2)
