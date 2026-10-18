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


# ---------------------------------------------------------------------------- on site (shed state)

## Out in the country, away from the yard, so a bike standing by the trailer isn't delivered.
const SITE := Transform3D(Basis(Vector3.UP, 0.4), Vector3(320.0, 0.0, -240.0))


func _seconds(s: float) -> void:
	for i in int(s * 120.0):
		await t.get_tree().process_frame


## A new shed with the recovery rig bought and parked out at SITE.
func _shed_with_rig() -> void:
	Shed.start_new("Recovery tester", 4242)
	Shed.garage_money = 60000
	Shed.request({"a": "recovery_grant"})
	_park_at(SITE)


func _park_at(xf: Transform3D) -> void:
	Recovery.car()["xf"] = xf
	Recovery.car()["trailer_xf"] = Recovery.trailer_park(xf)


## A recovery job taken on (the newest), its bike rolling or not, uncovered.
func _job(kind: String, rolls: bool) -> Dictionary:
	var oid := Recovery.spawn(kind)
	Recovery.offers()[oid]["rolls"] = rolls
	Shed.request({"a": "recovery_accept", "offer": oid})
	var best := {}
	for jid in Recovery.jobs():
		if best.is_empty() or int(jid) > int(best["id"]):
			best = Recovery.jobs()[jid]
	best["tarp"] = false
	return best


## Stands a bike at the foot of the ramp (`dx` across), facing up it (or away when `back`).
func _to_ramp(bike: int, dx := 0.0, back := false) -> void:
	var b := Basis(Vector3.UP, PI) if back else Basis()
	Shed.bikes[bike]["xf"] = Recovery.trailer_xf() * Transform3D(b, Vector3(dx, 0.0, Trailer.start_z() + 0.2))
	Shed.bikes[bike]["stand"] = "side"


## A rolling bike: lower the ramp, winch it up the ramp, strap it, and let it down again; a
## second goes in the other channel and there's no room for a third.
func test_winch() -> void:
	_shed_with_rig()
	var me := Shed.me()
	check(Recovery.owned() and Shed.check(me, {"a": "recovery_enter"}) == "", "with the rig bought the truck can be got into")
	var job := _job("barn", true)
	var bike := int(job["bike"])
	check(Recovery.job_of(bike) == job and str(job["state"]) == "collect", "accepting a job puts its bike out at the site")
	check(Shed.check(me, {"a": "mount", "bike": bike}) != "", "a recovery bike can't be ridden home")
	_to_ramp(bike)
	check(Shed.check(me, {"a": "recovery_winch", "bike": bike}).contains("ramp"), "the winch wants the ramp down first")
	Shed.request({"a": "recovery_ramp", "down": true})
	check(bool(Recovery.car()["ramp"]) and Shed.check(me, {"a": "recovery_enter"}) != "", "the ramp goes down, and you can't drive off with it down")
	Shed.bikes[bike]["stand"] = "down"
	check(Shed.check(me, {"a": "recovery_winch", "bike": bike}).contains("Stand it up"), "a bike lying down has to be stood up")
	_to_ramp(bike, 0.0, true)
	check(Shed.check(me, {"a": "recovery_winch", "bike": bike}).contains("face"), "it has to face up the ramp")
	Shed.bikes[bike]["xf"] = Recovery.trailer_xf() * Transform3D(Basis(), Vector3(0.0, 0.0, Trailer.start_z() + 6.0))
	check(Shed.check(me, {"a": "recovery_winch", "bike": bike}).contains("foot of the ramp"), "and stand at the foot of it")
	_to_ramp(bike, 0.4)
	check(Shed.check(me, {"a": "recovery_winch", "bike": bike}) == "", "stood at the foot of the ramp, it can be winched")
	Shed.request({"a": "recovery_winch", "bike": bike})
	check(Recovery.is_loaded(bike) and int(Recovery.car()["winch"]) == bike, "the winch starts pulling")
	check(Shed.check(me, {"a": "grab_bike", "bike": bike}) != "", "nobody can wheel it off while it's on the winch")
	await _seconds(2.0)
	var s := float(Recovery.loads()[bike]["s"])
	check(s > 0.6 and s < 1.6 and not Recovery.on_bed(bike), "two seconds in it's part way up the ramp (%.2f m)" % s)
	await _seconds(10.0)
	var at := Recovery.trailer_xf().affine_inverse() * (Shed.bikes[bike]["xf"] as Transform3D).origin
	check(Recovery.on_bed(bike) and int(Recovery.car()["winch"]) == 0, "the winch stops with it on the bed")
	check(absf(at.y - Trailer.BED_Y) < 0.02 and absf(at.z - Trailer.SLOT_Z) < 0.05 and absf(at.x - Trailer.SLOTS_X[1]) < 0.01,
		"standing on the bed in the right-hand channel (%.2f, %.2f, %.2f)" % [at.x, at.y, at.z])
	check(not Recovery.secure(bike), "it isn't secure until it's strapped")
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 0})
	check(Recovery.straps_on(bike) == 1 and not Recovery.secure(bike), "one strap tight isn't enough")
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 1})
	check(Recovery.secure(bike), "the front pair hold it")
	check(Shed.check(me, {"a": "recovery_unload", "bike": bike}).contains("straps"), "it can't be let down with its straps on")
	var job2 := _job("crash", true)
	var bike2 := int(job2["bike"])
	_to_ramp(bike2, -0.4)
	Shed.bikes[bike2]["stand"] = "side"
	Shed.request({"a": "recovery_winch", "bike": bike2})
	await _seconds(11.0)
	check(Recovery.on_bed(bike2) and int(Recovery.loads()[bike2]["slot"]) == 0, "a second bike goes up beside it")
	check(Shed.check(me, {"a": "recovery_accept", "offer": Recovery.spawn("barn")}).contains("already"),
		"two to fetch at once is the most it takes on")
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 0, "on": false})
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 1, "on": false})
	Shed.request({"a": "recovery_unload", "bike": bike})
	await _seconds(11.0)
	check(not Recovery.is_loaded(bike) and str(Shed.bikes[bike]["stand"]) != "", "let down the ramp, it stands behind the trailer")
	check(str(job["state"]) == "collect", "out in the country that isn't a delivery")
	Shed.stop()


## A bike that won't roll can't be wheeled or winched; it goes on the dolly tray, up the ramp
## on that, home, and down again in the yard, where the call-out is paid.
func test_dolly() -> void:
	_shed_with_rig()
	var me := Shed.me()
	var job := _job("barn", false)
	var bike := int(job["bike"])
	var beside := Recovery.trailer_xf() * Transform3D(Basis(), Vector3(6.0, 0.0, 2.0))
	# On the ground there (a session earlier in the run leaves the map's terrain loaded).
	beside.origin.y = Recovery.ground_y(beside.origin.x, beside.origin.z)
	Shed.bikes[bike]["xf"] = beside
	Shed.bikes[bike]["stand"] = "side"
	check(Recovery.seized(bike) and Shed.check(me, {"a": "grab_bike", "bike": bike}).contains("seized"),
		"a barn find with seized brakes can't be wheeled about")
	Shed.request({"a": "recovery_ramp", "down": true})
	_to_ramp(bike)
	check(Shed.check(me, {"a": "recovery_winch", "bike": bike}).contains("dolly"), "or winched: it needs the dolly")
	Shed.bikes[bike]["xf"] = beside
	Shed.request({"a": "recovery_dolly_off", "bike": bike})
	var dxf: Transform3D = Recovery.dolly()["xf"]
	check(str(Recovery.dolly()["at"]) == "ground" and dxf.origin.distance_to(beside.origin) < 1.5,
		"the dolly tray comes off the side rail and goes down beside the bike")
	check(Shed.check(me, {"a": "recovery_dolly_stow"}) == "", "it could go back on the rail")
	Shed.request({"a": "recovery_dolly_load", "bike": bike})
	check(Recovery.on_dolly(bike) and not Recovery.seized(bike) and Shed.check(me, {"a": "grab_bike", "bike": bike}) == "",
		"up on the dolly it can be pushed")
	_to_ramp(bike)
	Shed.bikes[bike]["stand"] = ""
	Shed.request({"a": "recovery_winch", "bike": bike})
	check(Recovery.is_loaded(bike) and str(Recovery.dolly()["at"]) == "load", "the dolly goes up the ramp under it")
	await _seconds(9.6)
	check(not Recovery.on_bed(bike), "pushing it up on the dolly is slower than winching a rolling bike")
	await _seconds(4.0)
	check(Recovery.on_bed(bike), "but it gets there")
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 0})
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 1})
	Shed.request({"a": "recovery_ramp", "down": false})
	Shed.request({"a": "recovery_enter"})
	check(Recovery.driver() == me, "into the cab")
	var money0 := Shed.garage_money
	Shed.request({"a": "recovery_exit", "xf": Recovery.PARK, "trailer_xf": Recovery.trailer_park(Recovery.PARK)})
	var at := (Shed.bikes[bike]["xf"] as Transform3D).origin
	check(Recovery.driver() == 0 and at.distance_to(Recovery.trailer_park(Recovery.PARK).origin) < 2.0,
		"driven home, the bike on the trailer comes with it")
	await _seconds(0.5)
	check(str(job["state"]) == "collect", "still on the trailer in the yard isn't delivered yet")
	Shed.request({"a": "recovery_ramp", "down": true})
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 0, "on": false})
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 1, "on": false})
	Shed.request({"a": "recovery_unload", "bike": bike})
	await _seconds(14.0)
	check(not Recovery.is_loaded(bike) and str(Recovery.dolly()["at"]) == "bike", "let down the ramp in the yard, still on its dolly")
	check(str(job["state"]) == "delivered" and Shed.garage_money == money0 + int(job["fee"]),
		"that's a delivery: the call-out fee is paid (%s)" % Recovery.money(int(job["fee"])))
	Shed.request({"a": "recovery_dolly_unload"})
	check(str(Recovery.dolly()["at"]) == "ground" and int(Recovery.dolly()["bike"]) == 0, "off the dolly")
	Shed.request({"a": "recovery_dolly_stow"})
	check(str(Recovery.dolly()["at"]) == "trailer", "and the dolly goes back on its rail")
	Shed.stop()


## Loads on the moving trailer: hard braking throws an unstrapped bike into the chock and over
## the side; a strapped one stays put; a gentle stop only rolls a loose one forward. A bike
## that comes off lands on its side, scuffed.
func test_straps() -> void:
	var r := _rig(true)
	var car: Car = r["car"]
	var tr: Trailer = r["trailer"]
	await _ticks(240)
	var fell := {}
	tr.load_fell.connect(func(id, _side, _v): fell[id] = true)
	tr.load_sim = {101: {"z": 0.0, "v": 0.0, "straps": 0, "secure": false}, 102: {"z": 0.0, "v": 0.0, "straps": 2, "secure": true}}
	await _drive(car, 6.0, func(c, _t): c.throttle = 0.9)
	check(not fell.has(101) and float(tr.load_sim[101]["z"]) > 0.1, "pulling away a loose bike rolls back to the tailgate (%.2f m)" % float(tr.load_sim.get(101, {}).get("z", -9.0)))
	await _drive(car, 5.0, func(c, _t):
		c.throttle = 0.0
		c.brake = 1.0 if absf(c.speed) > 0.3 else 0.0)
	check(fell.has(101), "braking hard throws the unstrapped bike into the chock and off the side")
	check(not fell.has(102) and absf(float(tr.load_sim[102]["z"])) < 0.001, "the strapped bike doesn't move")
	await _drive(car, 6.0, func(c, _t):
		c.brake = 0.0
		c.throttle = 0.9 if c.speed < 12.0 else 0.0)
	tr.load_sim[104] = {"z": 0.0, "v": 0.0, "straps": 0, "secure": false}
	await _drive(car, 12.0, func(c, _t):
		c.throttle = 0.0
		c.brake = 0.3 if absf(c.speed) > 0.3 else 0.0)
	check(not fell.has(104) and float(tr.load_sim.get(104, {}).get("z", 9.0)) < -0.05,
		"a gentle stop only rolls a loose bike forwards against the chock (%.2f m)" % float(tr.load_sim.get(104, {}).get("z", 9.0)))
	r["root"].queue_free()
	await _ticks(2)
	# The shed's side of a fall.
	_shed_with_rig()
	var job := _job("barn", true)
	var bike := int(job["bike"])
	Shed.request({"a": "recovery_ramp", "down": true})
	_to_ramp(bike)
	Shed.request({"a": "recovery_winch", "bike": bike})
	await _seconds(11.0)
	Shed.request({"a": "recovery_ramp", "down": false})
	Shed.request({"a": "recovery_enter"})
	var drop := Recovery.trailer_xf() * Transform3D(Basis(), Vector3(2.0, 0.0, 0.0))
	Shed.request({"a": "recovery_fall", "bike": bike, "xf": drop})
	var scuffed := 0
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike, slot)
		if id != 0 and bool(Shed.items[id].get("scuff", false)):
			scuffed += 1
	check(not Recovery.is_loaded(bike) and str(Shed.bikes[bike]["stand"]) == "down", "a bike that comes off lies on its side on the road")
	check(scuffed > 0 and (Shed.bikes[bike]["xf"] as Transform3D).origin.distance_to(drop.origin) < 0.01, "where it fell, scuffed (%d parts)" % scuffed)
	Shed.request({"a": "recovery_exit"})
	Shed.stop()


# ---------------------------------------------------------------------------- back in the yard

## A job's bike let down in the yard (beside the parked trailer): delivered, call-out paid.
func _deliver(job: Dictionary) -> void:
	var bike := int(job["bike"])
	Shed.bikes[bike]["xf"] = Recovery.trailer_xf() * Transform3D(Basis(), Vector3(0.0, 0.0, Trailer.start_z() + 1.0))
	Shed.bikes[bike]["stand"] = "side"
	Recovery.process(0.01)


## The assessment of a crashed bike, then each of the three choices: buy it, break it for parts,
## or repair it for the insurer, who won't collect it till it's up to their spec.
func test_assess() -> void:
	_shed_with_rig()
	_park_at(Recovery.PARK)
	var me := Shed.me()
	var job := _job("crash", true)
	var bike := int(job["bike"])
	check(Shed.check(me, {"a": "recovery_buy", "job": int(job["id"])}).contains("yard"), "it can't be bought before it's brought in")
	var m0 := Shed.garage_money
	_deliver(job)
	check(str(job["state"]) == "delivered" and Shed.garage_money == m0 + int(job["fee"]), "stood in the yard it's delivered and the call-out paid")
	check(Shed.check(me, {"a": "mount", "bike": bike}).contains("Assess"), "it can't be ridden off before it's assessed")
	var a := Recovery.assess(bike, job)
	var bad: Array = a["rows"].filter(func(r): return str(r["fix"]) != "ok")
	check(a["rows"].size() > 10 and bad.size() >= 3, "every part is looked over and the crash damage found (%d of %d need work)" % [bad.size(), a["rows"].size()])
	check(int(a["repair"]) > 0 and int(a["repair"]) == bad.reduce(func(acc, r): return acc + int(r["cost"]), 0),
		"the repair estimate is what those parts cost to put right (%s)" % Recovery.money(int(a["repair"])))
	check(int(a["salvage"]) < int(a["buy"]) and int(a["insurer"]) > int(a["repair"]),
		"breaking it costs less than buying it, and the insurer pays more than the parts (%s, %s, %s)" % [
			Recovery.money(int(a["buy"])), Recovery.money(int(a["salvage"])), Recovery.money(int(a["insurer"]))])
	# Buy it.
	var m1 := Shed.garage_money
	Shed.request({"a": "recovery_buy", "job": int(job["id"])})
	check(Shed.garage_money == m1 - int(a["buy"]) and not Recovery.jobs().has(int(job["id"])) and Shed.bikes.has(bike),
		"bought: the owner's paid and it's the garage's bike")
	check(Shed.check(me, {"a": "mount", "bike": bike}) == "" or not Shed.check(me, {"a": "mount", "bike": bike}).contains("Assess"),
		"and it's no longer held up by the job")
	check(str(Recovery._st()["done"][0]["outcome"]).begins_with("Bought"), "the job's in the done list")
	# Break one for parts.
	var job2 := _job("barn", true)
	var bike2 := int(job2["bike"])
	_deliver(job2)
	var parts_on := 0
	for slot in PartsDB.BIKE_SLOTS:
		if Shed.item_on(bike2, slot) != 0 and slot != "frame":
			parts_on += 1
	var items0 := Shed.items.size()
	var a2 := Recovery.assess(bike2, job2)
	var m2 := Shed.garage_money
	Shed.request({"a": "recovery_salvage", "job": int(job2["id"])})
	check(not Shed.bikes.has(bike2) and not Recovery.jobs().has(int(job2["id"])), "broken for parts: the bike's gone")
	check(Shed.items.size() == items0 - 1 and Shed.garage_money < m2 and Shed.garage_money > m2 - int(a2["salvage"]),
		"its %d parts are spares now, the frame scrapped for a little back (%s paid)" % [parts_on, Recovery.money(int(a2["salvage"]))])
	# Do the work for the insurer.
	var job3 := _job("crash", true)
	var bike3 := int(job3["bike"])
	_deliver(job3)
	Shed.request({"a": "recovery_insurer", "job": int(job3["id"])})
	check(str(job3["state"]) == "insurer" and not (job3["spec"] as Array).is_empty() and int(job3["pay"]) > 0,
		"for the insurer: the damaged parts are listed and the pay agreed (%s)" % Recovery.money(int(job3["pay"])))
	var why := Shed.check(me, {"a": "recovery_collect", "job": int(job3["id"])})
	check(why.contains("spec"), "they won't collect it as it is (%s)" % why)
	for slot in job3["spec"]:
		var id := Shed.item_on(bike3, str(slot))
		if id != 0:
			for k in ["wear", "rust", "dirt"]:
				Shed.items[id][k] = 0.0
			Shed.items[id]["scuff"] = false
	why = Shed.check(me, {"a": "recovery_collect", "job": int(job3["id"])})
	check(why == "", "put right, it's up to spec (%s)" % why)
	var m3 := Shed.garage_money
	Shed.request({"a": "recovery_collect", "job": int(job3["id"])})
	check(not Shed.bikes.has(bike3) and Shed.garage_money == m3 + int(job3["pay"]), "the insurer collects it and pays")
	check(Recovery._st()["done"].size() == 3, "all three in the done list")
	Shed.stop()


## Saved and loaded: the rig, the jobs, what's on the trailer with its straps, the dolly and the
## offers all come back; nobody's in the cab and a bike halfway up the winch finishes going up.
## A save from before the rig loads with none.
func test_save() -> void:
	_shed_with_rig()
	var job := _job("barn", true)
	var bike := int(job["bike"])
	Shed.request({"a": "recovery_ramp", "down": true})
	_to_ramp(bike)
	Shed.request({"a": "recovery_winch", "bike": bike})
	await _seconds(11.0)
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 0})
	Shed.request({"a": "recovery_strap", "bike": bike, "point": 1})
	var job2 := _job("crash", true)
	var bike2 := int(job2["bike"])
	_to_ramp(bike2, -0.4)
	Shed.request({"a": "recovery_winch", "bike": bike2})
	await _seconds(1.0)
	Shed.request({"a": "recovery_dolly_off"})
	Recovery.spawn("barn")
	Recovery.car()["driver"] = Shed.me()
	var car_xf := Recovery.car()["xf"] as Transform3D
	var offers := Recovery.offers().size()
	var state: Dictionary = Shed._snapshot().duplicate(true)
	SaveGame.write("test_recovery_save", {"version": SaveGame.VERSION, "shed": state})
	var back := SaveGame.read("test_recovery_save")
	SaveGame.delete_slot("test_recovery_save")
	Shed.start_new("Someone else", 7)
	check(not Recovery.owned() and Recovery.jobs().is_empty(), "a new shed has no rig")
	Shed.load_state(back["shed"], "Tester")
	check(Recovery.owned() and Recovery.jobs().size() == 2 and Recovery.offers().size() == offers, "the rig, its jobs and offers come back")
	check((Recovery.car()["xf"] as Transform3D).is_equal_approx(car_xf) and bool(Recovery.car()["ramp"]), "the truck where it was left, ramp down")
	check(Recovery.on_bed(bike) and Recovery.secure(bike), "the strapped bike still on the bed, strapped")
	check(Recovery.on_bed(bike2) and int(Recovery.car()["winch"]) == 0, "the one on the winch finished going up")
	check(Recovery.driver() == 0, "nobody's in the cab")
	check(str(Recovery.dolly()["at"]) == "ground", "the dolly tray where it was put down")
	check(Recovery.job_of(bike) == Recovery.jobs()[int(job["id"])], "the bikes still know their jobs")
	var old := Shed._snapshot().duplicate(true)
	old.erase("recovery")
	Shed.load_state(old, "Tester")
	check(Recovery.jobs().is_empty() and Recovery.loads().is_empty() and str(Recovery.dolly()["at"]) == "trailer",
		"a save from before the recovery rig loads with no jobs out")
	Shed.stop()


# ---------------------------------------------------------------------------- on foot

## The game with a session started, the rig bought and parked in the yard.
func _main_with_rig() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.garage_money = 60000
	Shed.request({"a": "recovery_grant"})
	await _ticks(10)
	return main


## Holds `action` down for `seconds`, or until `until` says stop.
func _hold(action: String, seconds: float, until := Callable()) -> void:
	Input.action_press(action)
	for i in int(seconds * Engine.physics_ticks_per_second):
		await t.get_tree().physics_frame
		if until.is_valid() and until.call():
			break
	Input.action_release(action)


## A real Space bar press (or release), through the viewport as the keyboard sends it.
func _space(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.keycode = KEY_SPACE
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Walking onto the trailer: with the ramp down you walk up it onto the bed and about on it
## (the front board stops you walking off onto the drawbar); with it up there's no ramp to walk
## up. While someone drives off you're put down beside it, not carried away on the bed.
func test_walk_on() -> void:
	var main := await _main_with_rig()
	var rv: RecoveryView = main.recovery
	var tr := rv.trailer
	var w: Walker = main.walker
	check(tr != null and not tr.ramp_walkable(), "the rig is parked in the yard with its ramp up")
	var behind := tr.global_transform * Transform3D(Basis(), Vector3(0.0, 0.0, Trailer.ramp_foot_z() + 1.2))
	w.place(behind)
	await _ticks(20)
	var local := func() -> Vector3: return tr.global_transform.affine_inverse() * w.global_position
	await _hold("move_forward", 2.0)
	check((local.call() as Vector3).y < 0.2 and (local.call() as Vector3).z > Trailer.BED_REAR,
		"with the ramp up you can't get up on the bed (%s)" % str(local.call()))
	Shed.request({"a": "recovery_ramp", "down": true})
	await _seconds(1.2)
	check(tr.ramp_walkable(), "lowered, the ramp can be walked on")
	w.place(behind)
	await _ticks(20)
	await _hold("move_forward", 3.0, func(): return (local.call() as Vector3).z < -0.4)
	await _ticks(30)
	var l: Vector3 = local.call()
	check(w.is_on_floor() and absf(l.y - Trailer.BED_Y) < 0.06 and l.z < Trailer.BED_REAR and tr.carries(w.global_position),
		"you walk up the ramp onto the bed (stood %.2f m up, %.2f m along)" % [l.y, l.z])
	await _hold("move_left", 0.25)
	await _hold("move_right", 0.5)
	await _ticks(30)
	l = local.call()
	check(w.is_on_floor() and absf(l.y - Trailer.BED_Y) < 0.06, "and walk about on it (%.2f m up, %.2f m across)" % [l.y, l.x])
	await _hold("move_forward", 1.5)
	await _ticks(20)
	l = local.call()
	check(l.z > Trailer.BED_FRONT and absf(l.y - Trailer.BED_Y) < 0.06, "the front board keeps you on the bed (%.2f m along)" % l.z)
	# Someone else drives off: you're stepped off the side.
	Recovery.car()["driver"] = 999
	await t.get_tree().process_frame
	await _ticks(10)
	l = local.call()
	check(not tr.carries(w.global_position) and absf(l.x) > Trailer.BED_HALF_W and l.y < 0.2,
		"when it's driven off you're put down beside it, not carried on the bed (%s)" % str(l))
	Recovery.car()["driver"] = 0
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()


## Space jumps on foot: a hop of about 0.45 m that lands again. Jumping about the shed, at
## the walls and the benches, gets you nowhere walking wouldn't (no standing on anything high,
## nothing through a wall). In the truck Space is still the handbrake, and doesn't jump.
func test_jump() -> void:
	var main := await _main_with_rig()
	var w: Walker = main.walker
	w.place(Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 0.5)))
	await _ticks(40)
	var y0 := w.global_position.y
	var top := y0
	_space(true)
	_space(false)
	var landed := -1
	for i in 150:
		await t.get_tree().physics_frame
		top = maxf(top, w.global_position.y)
		if i > 10 and w.is_on_floor() and landed < 0:
			landed = i
	check(top - y0 > 0.38 and top - y0 < 0.52, "Space jumps about 0.45 m (%.2f m)" % (top - y0))
	check(landed > 0 and absf(w.global_position.y - y0) < 0.03 and not w.jumping,
		"and you land again (after %.2f s)" % (landed / float(Engine.physics_ticks_per_second)))
	w.set_crouched(true)
	await _ticks(5)
	_space(true)
	_space(false)
	top = y0
	for i in 40:
		await t.get_tree().physics_frame
		top = maxf(top, w.global_position.y)
	check(top - y0 < 0.05, "crouched, you don't jump")
	w.set_crouched(false)
	await _ticks(5)
	# Run every way across the shed from the middle, jumping all the way: into the walls, the
	# benches, the bikes, out of the doors. A ray at waist height from each tick's spot to the
	# next would catch going through a wall.
	var worst := 0.0
	var through := []
	var space := w.get_world_3d().direct_space_state
	for k in 16:
		var yaw := TAU * k / 16.0
		w.place(Transform3D(Basis(Vector3.UP, yaw), Workshop.CENTER + Vector3(0.0, 0.0, 0.5)))
		await _ticks(30)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var was := w.global_position
		for i in 360:
			if i % 20 == 0:
				w._jump_wanted = true
			await t.get_tree().physics_frame
			var now := w.global_position
			if w.is_on_floor():
				worst = maxf(worst, now.y - y0)
			var q := PhysicsRayQueryParameters3D.create(was + Vector3.UP * 0.9, now + Vector3.UP * 0.9, 1)
			q.exclude = [w.get_rid()]
			if not space.intersect_ray(q).is_empty() and through.size() < 3:
				through.append("%d deg at %s" % [roundi(rad_to_deg(yaw)), str(now)])
			was = now
		Input.action_release("move_forward")
		Input.action_release("sprint")
		await _ticks(60)
	check(worst < 0.5, "jumping about the shed you never land on anything higher than a step (%.2f m)" % worst)
	check(through.is_empty(), "and it never takes you through a wall %s" % str(through))
	# In the truck: Space is the handbrake, and you don't jump.
	Shed.request({"a": "recovery_enter"})
	await _ticks(10)
	var rv: RecoveryView = main.recovery
	check(rv.driving, "into the truck")
	var at := w.global_position
	_space(true)
	await _ticks(10)
	check(rv.car.handbrake > 0.9 and w.global_position.distance_to(at) < 0.01, "in the truck Space is the handbrake (%.1f), and doesn't jump" % rv.car.handbrake)
	_space(false)
	await _ticks(10)
	check(rv.car.handbrake < 0.1, "and lets it off")
	rv.stop_driving()
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()


## The truck's model: a handful of meshes (the fixed body merged by material), glass you can see
## out of, the lamps lit only with the engine running (the reversing lamps in reverse), and the
## steering wheel turning with the front wheels. The trailer's fixed parts are merged too.
func test_model() -> void:
	var car := Car.new()
	# The front doors and the openings they leave only draw while one stands open (hidden, shut).
	var meshes := car.model.find_children("*", "MeshInstance3D", true, false).filter(func(mi): return not str(mi.get_parent().name).begins_with("Door"))
	var body: MeshInstance3D = car.model.get_node("Body")
	var mats := []
	for s in body.mesh.get_surface_count():
		mats.append(body.mesh.surface_get_material(s))
	var glass := mats.any(func(mt): return mt is StandardMaterial3D and (mt as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	check(meshes.size() <= 14 and body.mesh.get_surface_count() <= 30, "the truck is a handful of meshes (%d, the body %d surfaces)" % [meshes.size(), body.mesh.get_surface_count()])
	check(glass and body.get_aabb().size.y > 1.4 and body.get_aabb().end.y > 1.75 and body.get_aabb().size.z > 5.3, "with see-through glass, full size (%s)" % str(body.get_aabb().size))
	car.engine_on = false
	car._update_model(0.0)
	check(car._lamp_mat.emission_energy_multiplier == 0.0 and car._brake_mat.emission_energy_multiplier == 0.0 and not (car._head_lights[0] as Light3D).visible,
		"parked with the engine off its lights are off")
	car.engine_on = true
	car.gear = 1
	car._update_model(0.0)
	check(car._lamp_mat.emission_energy_multiplier > 1.0 and car._brake_mat.emission_energy_multiplier > 0.0
		and car._reverse_mat.emission_energy_multiplier == 0.0 and (car._head_lights[0] as Light3D).visible, "running, the head and tail lights are on")
	car.gear = -1
	car.steer = 0.3
	car._update_model(0.0)
	check(car._reverse_mat.emission_energy_multiplier > 0.0, "in reverse the reversing lamps light")
	check(absf(car._steering_wheel.rotation.y + 0.3 * Car.STEER_RATIO) < 0.01, "the steering wheel turns with the front wheels")
	car.free()
	var tr := Trailer.new()
	var tm := tr.model.find_children("*", "MeshInstance3D", false, false)
	check(tm.size() <= 3 and tr.model.get_node_or_null("Merged") != null, "the trailer's fixed parts are one mesh (%d left)" % tm.size())
	tr.free()


## A real press and release of an action through the viewport, as a key would send it.
func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		t.get_viewport().push_input(ev)


## Simon's 17 October round: the truck starts, reverses and lights up like the bikes. You get in
## with the engine off and start it on I (the starter turning it over first); L works the
## headlamps through off, dipped and main beam, real lights on the road; Q at a standstill puts
## the automatic in reverse, where W backs it up and the reversing lamps light, and E is drive
## again; the dash in the corner shows the gear; and the crew see the lamps, the brake lamps and
## the starter through the network snapshot.
func test_controls() -> void:
	var main := await _main_with_rig()
	var rv: RecoveryView = main.recovery
	Settings.auto_shift = true
	Shed.request({"a": "recovery_enter"})
	await _ticks(10)
	var car := rv.car
	check(rv.driving and not car.engine_on and main.hud.car == car, "you get in with the engine off, and the HUD shows the truck's dash")
	Input.action_press("throttle")
	await _ticks(60)
	Input.action_release("throttle")
	check(absf(car.speed) < 0.2, "with the engine off the throttle does nothing (%.2f m/s)" % car.speed)
	_press("ignition")
	await _ticks(20)
	check(car.is_starting() and not car.engine_on and rv.audio.cranking, "I turns it over on the starter (the starter sound plays)")
	await _ticks(Engine.physics_ticks_per_second * 1)
	check(car.engine_on and car.rpm > Car.IDLE_RPM * 0.8, "then it catches and idles (%.0f rpm)" % car.rpm)
	# The headlamps.
	var hl := car._head_lights[0] as SpotLight3D
	check(car.beam == 1 and hl.visible, "the headlamps come on dipped with the engine, as a bike's do")
	var dipped := hl.spot_range
	_press("headlight")
	await _ticks(2)
	check(car.beam == 2 and hl.visible and hl.spot_range > dipped * 1.5 and hl.rotation.x > deg_to_rad(-3.0),
		"L: main beam, reaching further up the road (%.0f m, dipped %.0f m)" % [hl.spot_range, dipped])
	_press("headlight")
	await _ticks(2)
	check(car.beam == 0 and not hl.visible, "L again: off")
	_press("headlight")
	await _ticks(2)
	check(car.beam == 1 and hl.visible and hl.light_projector != null, "and round to dipped, a soft-edged pool like the bikes'")
	# Reverse on the lever.
	_press("shift_down")
	await _ticks(2)
	check(car.gear == -1 and car.reverse_selected and not car.pedals_swapped(), "Q at a standstill: reverse")
	check(car._reverse_mat.emission_energy_multiplier > 0.0, "the reversing lamps light")
	Input.action_press("throttle")
	await _ticks(Engine.physics_ticks_per_second * 2)
	check(car.gear == -1 and car.speed < -0.8, "W backs it up, staying in reverse (%.1f m/s)" % car.speed)
	Input.action_release("throttle")
	Input.action_press("front_brake")
	await _ticks(10)
	check(car.braking and car._brake_mat.emission_energy_multiplier > 2.0, "S brakes it, the brake lamps bright")
	# What the crew see: another truck shown from this one's snapshot.
	var other := Car.new()
	t.add_child(other)
	other.freeze = true
	other.set_net_state(car.get_net_state())
	other._update_model(0.0)
	check(other.gear == -1 and other.braking and other.beam == 1 and (other._head_lights[0] as SpotLight3D).visible
		and other._reverse_mat.emission_energy_multiplier > 0.0 and other._brake_mat.emission_energy_multiplier > 2.0,
		"the crew see the reverse, brake and headlamps")
	await _ticks(Engine.physics_ticks_per_second * 2)
	Input.action_release("front_brake")
	_press("shift_up")
	await _ticks(2)
	check(car.gear == 1 and not car.reverse_selected, "E: back in drive")
	# Holding the brake at a standstill still finds reverse, the brake pedal backing it up.
	Input.action_press("front_brake")
	await _ticks(Engine.physics_ticks_per_second * 1)
	check(car.gear == -1 and car.pedals_swapped(), "holding S at a standstill finds reverse too")
	Input.action_release("front_brake")
	# Engine off on the key; the crew hear the starter when it's turned over again.
	_press("ignition")
	await _ticks(5)
	check(not car.engine_on and not hl.visible, "I again: engine off, and the lamps go out")
	car.start_engine()
	other.set_net_state(car.get_net_state())
	check(other.is_starting() and not other.engine_on, "the crew's copy knows the starter is turning")
	other.queue_free()
	rv.stop_driving()
	check(main.hud.car == null, "out of the truck, the dash goes")
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()


## The horn players in the scene still sounding one of `sound`'s recordings, but `skip`.
func _horns_playing(sound: String, skip: Node = null) -> Array:
	var takes := Sfx.recordings(sound)
	return t.get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(
		func(p): return p != skip and p.playing and takes.has(p.stream))


## Simon's 17 October (21:18) round: the truck's horn kept playing, stuck where he'd honked it.
## It fired a one-off sound into the scene, and a disc horn's takes are set to loop once a bike
## with one has been ridden, so it never finished. Now the horn is on the truck: it sounds while
## held, moves with the truck, stops when you let go, get out or the truck goes, and the crew
## hear it the same way through the snapshot.
func test_horn() -> void:
	var main := await _main_with_rig()
	var rv: RecoveryView = main.recovery
	# A ride on a bike with a disc horn first, as in the game: its takes now loop.
	var bike_horn := HornAudio.new()
	bike_horn.sound = "horn_disc"
	bike_horn.tones = [400.0]
	t.add_child(bike_horn)
	await t.get_tree().process_frame
	check(bike_horn.is_recorded() and (Sfx.recordings("horn_disc")[0] as AudioStreamOggVorbis).loop, "a disc horn's takes loop after a ride")
	Shed.request({"a": "recovery_enter"})
	await _ticks(10)
	var car := rv.car
	var horn: HornAudio = car.get("horn_audio")
	check(horn != null and horn.get_parent() == car and horn.is_recorded(), "the truck has its own horn, on the truck")
	car.start_engine()
	await _ticks(Engine.physics_ticks_per_second * 1)
	Input.action_press("horn")
	await _ticks(12)
	var honked_at := car.global_position
	check(car.horn and horn != null and horn.pressed and horn.playing, "held, the horn sounds")
	check(rv.net_state()[-1] > 0.5 and rv.net_state().size() == 2 + Car.NET_SIZE + Trailer.NET_SIZE, "and the crew's snapshot says so")
	Input.action_press("throttle")
	await _ticks(Engine.physics_ticks_per_second * 2)
	Input.action_release("throttle")
	var moved := car.global_position.distance_to(honked_at)
	check(horn != null and horn.playing and moved > 2.0 and horn.global_position.distance_to(car.global_position) < 3.5,
		"it goes with the truck (%.1f m from where it was honked)" % moved)
	Input.action_release("horn")
	await _ticks(40)
	check(not car.horn and (horn == null or not horn.playing), "let go, it stops")
	check(_horns_playing("horn_disc", bike_horn).is_empty(), "and nothing's left sounding where it was honked (%d)" % _horns_playing("horn_disc", bike_horn).size())
	check(rv.net_state()[-1] < 0.5, "and the crew are told")
	# Out of the truck with the horn held.
	Input.action_press("horn")
	await _ticks(12)
	check(horn != null and horn.playing, "honking again")
	rv.stop_driving()
	await _ticks(40)
	check(_horns_playing("horn_disc", bike_horn).is_empty(), "getting out stops it")
	Input.action_release("horn")
	# The crew's copy: the driver's snapshots, horn on, then off, then stopped coming.
	var snap := PackedFloat32Array([2.0])
	snap.append_array(car.get_net_state())
	snap.append_array(rv.trailer.get_net_state())
	snap.append(1.0)
	var peer := 99
	rv._remote[peer] = [{"t": Time.get_ticks_msec() / 1000.0, "s": snap}]
	rv._follow_remote(peer)
	car._process(0.0)
	check(car.horn and horn != null and horn.pressed, "the crew hear the driver's horn while it's held")
	var off := snap.duplicate()
	off[-1] = 0.0
	rv._remote[peer] = [{"t": Time.get_ticks_msec() / 1000.0, "s": off}]
	rv._follow_remote(peer)
	car._process(0.0)
	check(not car.horn and horn != null and not horn.pressed, "and it stops when they let go")
	rv._remote[peer] = [{"t": Time.get_ticks_msec() / 1000.0 - 1.0, "s": snap}]
	rv._follow_remote(peer)
	check(not car.horn, "or when their snapshots stop coming")
	rv._remote[peer] = [{"t": Time.get_ticks_msec() / 1000.0, "s": snap.slice(0, snap.size() - 1)}]
	rv._follow_remote(peer)
	check(not car.horn and car.global_position.is_finite(), "an older build's snapshot (no horn) still reads")
	rv._remote.erase(peer)
	# Honking when the truck goes away.
	Shed.request({"a": "recovery_enter"})
	await _ticks(10)
	Input.action_press("horn")
	await _ticks(12)
	check(rv.driving and _horns_playing("horn_disc", bike_horn).size() >= 1, "honking again at the wheel")
	rv._free_rig()
	await _ticks(5)
	Input.action_release("horn")
	check(_horns_playing("horn_disc", bike_horn).is_empty(), "the truck going takes its horn with it")
	# A crew member's bike: its horn sounds while their snapshot says held, and stops if the
	# snapshots stop coming (it used to sound on for good after a dropped connection).
	var rb := RemoteBike.new()
	t.add_child(rb)
	rb.setup("Crew", BikeBuild.new({"engine": "twin_700", "horn": "disc_horn"}), Color.RED)
	var bs := PackedFloat32Array()
	bs.resize(25)
	bs[6] = 1.0
	bs[21] = 1.0
	rb.push_state(bs)
	await _ticks(2)
	check(rb._horn.pressed, "a crew member's bike horn sounds while they hold it")
	var since := Time.get_ticks_msec()   # snapshots are timed on the clock, not the game's ticks
	while Time.get_ticks_msec() - since < 800:
		await _ticks(1)
	check(not rb._horn.pressed, "and stops if their snapshots stop coming")
	rb.queue_free()
	bike_horn.queue_free()
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()


## Simon's 18 October (16:08) round: a ratchet sound stayed in space like the horns did. The
## winch and strap ratchets fired the work loop (whose take loops) as a one-off where you pressed
## it, so it never finished; the cab door played the shed's roller door loop. One-shots now never
## loop, ride on what made them, and go once played (or after a few seconds whatever happens).
func test_oneshot_sounds() -> void:
	var main := await _main_with_rig()
	var rv: RecoveryView = main.recovery
	var takes := Sfx.sounds("ratchet")
	var loops := func(s) -> bool:
		return (s is AudioStreamOggVorbis and s.loop) or (s is AudioStreamWAV and s.loop_mode != AudioStreamWAV.LOOP_DISABLED)
	check(takes.any(loops), "the ratchet work loop's takes loop (as the spanner's sound needs)")
	var before := Sfx.oneshots_alive()
	var p := Sfx.play_on("ratchet", rv.trailer, Trailer.WINCH, -6.0, RecoveryView.RATCHET_SECONDS)
	check(p != null and p.get_parent() == rv.trailer and not loops.call(p.stream)
		and p.global_position.distance_to(rv.trailer.global_transform * Trailer.WINCH) < 0.01,
		"a turn of the winch's ratchet plays once, from the winch on the trailer")
	check(takes.any(loops), "and the spanner's own loop still loops")
	Shed.request({"a": "recovery_enter"})
	await _ticks(10)
	var door := rv.car.get_children().filter(func(c): return c is AudioStreamPlayer3D and c.is_in_group(Sfx.ONESHOT_GROUP))
	check(door.size() >= 1, "getting in, the door shuts on the truck itself (%d)" % door.size())
	Sfx.play_at("ratchet", Vector3(4.0, 1.0, 4.0), -6.0)
	Sfx.play_ui("wash_ding", -5.0)
	check(Sfx.oneshots_alive() >= before + 3, "the one-shots are sounding (%d)" % Sfx.oneshots_alive())
	await _ticks(Engine.physics_ticks_per_second * 3)
	var stuck := t.get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(
		func(q): return q.playing and takes.has(q.stream))
	check(stuck.is_empty(), "nothing's left ratcheting where it was pressed (%d)" % stuck.size())
	await _ticks(Engine.physics_ticks_per_second * 7)
	check(Sfx.oneshots_alive() <= before, "and every one-shot's gone by itself (%d left)" % Sfx.oneshots_alive())
	rv.stop_driving()
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()


## A slope of `deg` degrees running down towards +z, with the truck on it facing uphill (-z) and
## its trailer hitched on behind when `trailer`, stopped.
func _slope_rig(deg: float, trailer := false) -> Dictionary:
	var root := Node3D.new()
	t.add_child(root)
	var ground := TestGround.new(4000.0, "tarmac")
	ground.rotation.x = deg_to_rad(deg)   # +z end lower: facing -z is uphill
	root.add_child(ground)
	var car := Car.new()
	root.add_child(car)
	var up := Basis(Vector3.RIGHT, deg_to_rad(deg))
	car.place(Transform3D(up, Vector3.ZERO))
	var out := {"root": root, "car": car}
	if trailer:
		var tr := Trailer.new()
		root.add_child(tr)
		tr.hitch_to(car)
		out["trailer"] = tr
	return out


## Simon's 18 October (16:08) round: a handbrake for the truck. Pulled up (J, or the pad's D-pad
## left) it stays on, holding the back wheels, on a slope too and with the trailer behind; let off
## (or never put on) a stopped truck rolls back down the hill. It's on the dash, and it's left as
## it was for whoever gets in next.
func test_handbrake() -> void:
	for with_trailer in [false, true]:
		var r := _slope_rig(7.0, with_trailer)
		var car: Car = r["car"]
		car.engine_on = false
		car.parking_brake = true
		await _ticks(Engine.physics_ticks_per_second * 1)
		var held_at := car.global_position
		await _ticks(Engine.physics_ticks_per_second * 4)
		var crept := car.global_position.distance_to(held_at)
		check(crept < 0.05, "%s on a 7 degree hill the handbrake holds it (%.2f m in 4 s)" % ["With the trailer," if with_trailer else "Parked", crept])
		car.parking_brake = false
		await _ticks(Engine.physics_ticks_per_second * 4)
		var rolled := car.global_position.distance_to(held_at)
		check(rolled > 1.5 and car.speed < -0.3, "let off, it rolls back down (%.1f m, %.1f m/s)" % [rolled, car.speed])
		(r["root"] as Node).queue_free()
		await _ticks(2)
	# At the wheel.
	var main := await _main_with_rig()
	var rv: RecoveryView = main.recovery
	Shed.request({"a": "recovery_enter"})
	await _ticks(10)
	check(rv.driving and not rv.car.parking_brake, "getting in a truck that was left without it, the handbrake's off")
	var ev := InputEventAction.new()
	ev.action = "handbrake"
	ev.pressed = true
	check(rv.drive_input(ev) and rv.car.parking_brake, "the handbrake key pulls it up")
	check(InputMap.action_get_events("handbrake").any(func(e): return e is InputEventJoypadButton), "and there's a pad button for it")
	rv.car.start_engine()
	await _ticks(Engine.physics_ticks_per_second * 1)
	main.hud.queue_redraw()
	rv.car._update_model(0.0)
	check(rv.car._park_lamp_mat.emission_energy_multiplier > 1.0, "its red lamp's lit on the dash")
	Input.action_press("throttle")
	await _ticks(Engine.physics_ticks_per_second * 2)
	Input.action_release("throttle")
	check(absf(rv.car.speed) < 1.0 and absf(float(rv.car.wheels[2]["omega"])) < 1.0, "with it on, the back wheels stay put on the throttle (%.1f m/s)" % rv.car.speed)
	await _ticks(Engine.physics_ticks_per_second * 1)
	rv.stop_driving()
	await _ticks(5)
	check(bool(Recovery.car()["handbrake"]), "got out, the truck's left with its handbrake on")
	Shed.request({"a": "recovery_enter"})
	await _ticks(10)
	check(rv.car.parking_brake, "and it's still on for whoever gets in next")
	check(rv.drive_input(ev) and not rv.car.parking_brake, "pressed again it's let off")
	rv.car.start_engine()
	await _ticks(Engine.physics_ticks_per_second * 1)
	Input.action_press("throttle")
	await _ticks(Engine.physics_ticks_per_second * 2)
	Input.action_release("throttle")
	check(rv.car.speed > 1.0, "and it pulls away (%.1f m/s)" % rv.car.speed)
	rv.stop_driving()
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()


## Simon's 18 October (16:08) round: passenger doors. A second player can get in the passenger
## seat by its own door (on the left: it's right-hand drive), sits there looking out, and gets out
## the same side. The doors swing open and shut as anyone gets in or out, on everyone's screen
## (it's the shed's seats changing), and the crew are drawn sat in the cab.
func test_passenger() -> void:
	var main := await _main_with_rig()
	var rv: RecoveryView = main.recovery
	var w: Walker = main.walker
	var car := rv.car
	check(car._doors.size() == 2 and not (car._doors[0] as Node3D).visible, "the truck has two front doors, shut")
	check(rv.use_text({"use": {"what": "ride"}}).contains("passenger seat"), "the passenger door says you can get in there")
	rv.use({"use": {"what": "ride"}})
	await _ticks(3)
	check(Recovery.passenger() == Shed.me() and rv.riding_along, "F at the passenger door: you're in the passenger seat")
	var cam: Camera3D = rv._pass_cam
	check(cam != null and cam.current and cam.get_parent() == car and cam.position.distance_to(Car.PASSENGER_EYE) < 0.01,
		"looking out from the passenger's seat, on the left")
	check(w.process_mode == Node.PROCESS_MODE_DISABLED and not w.visible, "the walker's put away meanwhile")
	await _ticks(20)
	check(float(car.door_open[0]) > 0.5 and (car._doors[0] as Node3D).visible and float(car.door_open[1]) == 0.0,
		"the passenger door swings open as you get in (%.2f), the driver's stays shut" % float(car.door_open[0]))
	await _ticks(Engine.physics_ticks_per_second * 3)
	check(float(car.door_open[0]) == 0.0 and not (car._doors[0] as Node3D).visible, "and shuts behind you")
	check(main._net_state() == PackedFloat32Array([3.0]), "the crew are told you're sat in the truck")
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(-200.0, 0.0)
	rv.passenger_input(ev)
	check(cam.rotation.y > 0.3, "the mouse turns your head to look about (%.2f)" % cam.rotation.y)
	check(Shed.check(Shed.me(), {"a": "recovery_enter"}) != "", "you can't drive from the passenger seat")
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	rv.passenger_input(press)
	await _ticks(3)
	var local := car.global_transform.affine_inverse() * w.global_position
	check(Recovery.passenger() == 0 and not rv.riding_along and w.visible and w.camera.current and local.x < -1.0,
		"F gets you out, stood by the passenger door (%.1f m to the left)" % -local.x)
	await _ticks(10)
	check(float(car.door_open[0]) > 0.3, "the door swings open as you get out too")
	# The crew's view: a player getting in the passenger seat, and one at the wheel.
	var peer := 99
	Recovery.car()["passenger"] = peer
	await _ticks(3)
	var sat: Array = car.get_children().filter(func(c): return c.has_meta("peer") and int(c.get_meta("peer")) == peer)
	check(sat.size() == 1 and (sat[0] as Node3D).position.x < 0.0, "the crew see them sat in the passenger seat")
	check(float(car.door_open[0]) > 0.0, "and the door swing as they get in")
	var parked := car.global_position
	Recovery.car()["passenger"] = 0
	await _ticks(3)
	sat = car.get_children().filter(func(c): return c.has_meta("peer") and int(c.get_meta("peer")) == peer and not c.is_queued_for_deletion())
	check(sat.is_empty() and car.global_position.distance_to(parked) < 0.01, "and gone again once they're out")
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()


## Simon's 18 October (16:08) round: a sort of radar in the truck for the jobs. In the cab a round
## radar shows the truck in the middle facing up, a blip for each bike still to collect and one
## for the garage (out of range, on the rim), and under it the next place to go, how far, and an
## arrow pointing at it.
func test_radar() -> void:
	var main := await _main_with_rig()
	var rv: RecoveryView = main.recovery
	Shed.request({"a": "recovery_start", "kind": "barn"})
	await _ticks(3)
	var list := TruckRadar.targets()
	var jobs := list.filter(func(x): return str(x["kind"]) == "job")
	var home := list.filter(func(x): return str(x["kind"]) == "home")
	check(jobs.size() >= 1 and home.size() == 1, "the radar has the job to collect and the garage on it (%d jobs)" % jobs.size())
	var ahead := TruckRadar.blip(Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, -450.0))
	var right := TruckRadar.blip(Vector3.ZERO, Vector3.FORWARD, Vector3(300.0, 0.0, 0.0))
	var far := TruckRadar.blip(Vector3.ZERO, Vector3.RIGHT, Vector3(0.0, 0.0, -5000.0))
	check(absf(ahead.x) < 0.01 and absf(ahead.y + TruckRadar.RADIUS * 0.5) < 0.1 and right.x > 10.0 and absf(right.y) < 0.01,
		"something ahead shows straight up the screen, something to the right to the right (%s, %s)" % [ahead, right])
	check(absf(far.length() - TruckRadar.RADIUS) < 0.01 and far.x < -10.0, "and a long way off it sits on the rim, turned with the truck (%s)" % far)
	check(not rv.radar.visible, "on foot there's no radar")
	Shed.request({"a": "recovery_enter"})
	await _ticks(5)
	check(rv.radar.visible, "in the cab it's up")
	rv.radar.queue_redraw()
	await t.get_tree().process_frame
	rv.stop_driving()
	await _ticks(3)
	check(not rv.radar.visible, "and out of the truck it's gone")
	main.queue_free()
	await t.get_tree().process_frame
	Shed.stop()
