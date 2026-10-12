extends Node
## Headless test suite. Run with:
##   godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn
## Prints a line per check and exits with code 1 if anything failed.

var failures := 0
var checks := 0
var verbose := OS.get_cmdline_user_args().has("--verbose")


func _ready() -> void:
	await get_tree().process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			# Run a single test method, e.g. --only=_test_acceleration
			await call(a.trim_prefix("--only="))
			print("\n%d checks, %d failed" % [checks, failures])
			get_tree().quit(1 if failures > 0 else 0)
			return
	await _run_all()
	print("\n%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  PASS  ", what)
	else:
		failures += 1
		print("  FAIL  ", what)


func _run_all() -> void:
	print("Parts and builds")
	_test_catalogue()
	print("Bike physics")
	await _test_settle()
	await _test_acceleration()
	await _test_turning()
	await _test_braking()
	await _test_low_speed()
	await _test_all_builds_ride()
	await _test_crash_and_respawn()
	await _test_sim_mode()
	print("The shed")
	_test_shed_rules()
	print("World")
	await _test_world()
	print("Game session")
	await _test_session()


func _test_catalogue() -> void:
	check(PartsDB.parts.size() == 50, "catalogue has 50 parts (got %d)" % PartsDB.parts.size())
	for slot in PartsDB.SLOTS:
		check(PartsDB.by_slot[slot].size() >= 5, "slot %s has at least five variants" % slot)
	var b := BikeBuild.new()
	check(b.bike_mass > 120.0 and b.bike_mass < 230.0, "default bike mass is plausible (%.0f kg)" % b.bike_mass)
	check(b.hp() > 40.0 and b.hp() < 120.0, "default bike power is plausible (%.0f hp)" % b.hp())
	var top := b.top_speed_estimate() * 3.6
	check(top > 120.0 and top < 260.0, "default top speed estimate is plausible (%.0f km/h)" % top)
	var bad := PartsDB.sanitize_build({"engine": "nope", "frame": "long_travel_mx"})
	check(bad["engine"] == PartsDB.DEFAULT_BUILD["engine"] and bad["frame"] == PartsDB.DEFAULT_BUILD["frame"],
		"unknown or wrong-slot parts fall back to defaults")
	var curve := b.dyno_curve()
	check(curve.size() > 10 and curve[0]["torque"] > 0.0, "dyno curve has data")
	# Condition matters.
	var rusty := BikeBuild.new({}, {"engine": {"rust": 0.8, "dirt": 0.9, "wear": 0.8}})
	check(rusty.hp() < b.hp() * 0.85, "a worn, rusty engine makes less power (%.0f vs %.0f hp)" % [rusty.hp(), b.hp()])
	var clogged := BikeBuild.new({"intake": "pod_filters"}, {"intake": {"dirt": 1.0}})
	var clean := BikeBuild.new({"intake": "pod_filters"})
	check(clogged.peak_torque < clean.peak_torque * 0.85, "a clogged pod filter chokes the engine")
	var tired := BikeBuild.new({}, {"brakes": {"wear": 1.0, "rust": 1.0}})
	check(tired.front_brake_torque < b.front_brake_torque * 0.75, "worn brakes stop less well")
	var faster := BikeBuild.new({"exhaust": "titanium_race", "intake": "race_carbs"})
	check(faster.hp() > b.hp() * 1.1, "race intake and exhaust add power (%.0f hp)" % faster.hp())
	check(PartsDB.dependents("engine").has("intake") and PartsDB.dependents("engine").has("exhaust"),
		"intake and exhaust must come off before the engine")
	check(PartsDB.dependents("wheels").has("brakes"), "brakes must come off before the wheels")


## Spawns a bike on flat ground, runs `seconds` of physics calling `drive(bike, t)` each step,
## and returns the bike plus a few measurements. The caller frees the returned "root".
func ride(build: Dictionary, seconds: float, drive: Callable, surf := "tarmac") -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.add_child(TestGround.new(4000.0, surf))
	var bike := Bike.new()
	bike.setup(BikeBuild.new(build))
	root.add_child(bike)
	bike.place(Vector3.ZERO, 0.0)
	bike.auto_shift = true
	bike.assist = 0.5
	var result := {"root": root, "bike": bike, "max_speed": 0.0, "max_lean": 0.0, "crashed": false,
		"start_yaw": 0.0, "front_lifted": false}
	var steps := int(seconds * Engine.physics_ticks_per_second)
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in steps:
		drive.call(bike, i * dt)
		await get_tree().physics_frame
		result["max_speed"] = maxf(result["max_speed"], bike.speed)
		result["max_lean"] = maxf(result["max_lean"], absf(bike.lean_angle))
		if bike.is_crashed:
			result["crashed"] = true
		if not bike.wheels[0]["contact"] and bike.wheels[1]["contact"] and bike.speed > 2.0:
			result["front_lifted"] = true
		if verbose and i % 60 == 0:
			print("    t=%.1f v=%.1f lean=%.1f steer=%.1f gear=%d rpm=%.0f comp=%.3f/%.3f slip=%.2f/%.2f pitch=%.1f" % [
				i * dt, bike.speed, rad_to_deg(bike.lean_angle), rad_to_deg(bike.steer), bike.gear, bike.rpm,
				bike.wheels[0]["compression"], bike.wheels[1]["compression"], bike.wheels[0]["slip"], bike.wheels[1]["slip"],
				rad_to_deg(bike.pitch_angle)])
	return result


func _heading(bike: Bike) -> float:
	var f := -bike.global_transform.basis.z
	return atan2(-f.x, -f.z)


func _done(r: Dictionary) -> void:
	r["root"].queue_free()
	await get_tree().physics_frame


func _test_settle() -> void:
	var r := await ride({}, 3.0, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	check(not r["crashed"], "bike stands still without crashing")
	check(bike.wheels[0]["contact"] and bike.wheels[1]["contact"], "both wheels touch the ground at rest")
	var sag_f: float = bike.wheels[0]["compression"] / bike.build.front_travel
	var sag_r: float = bike.wheels[1]["compression"] / bike.build.rear_travel
	check(sag_f > 0.1 and sag_f < 0.7 and sag_r > 0.1 and sag_r < 0.7,
		"suspension sags a sensible amount (front %.0f%%, rear %.0f%%)" % [sag_f * 100, sag_r * 100])
	check(absf(bike.lean_angle) < deg_to_rad(6.0), "bike stays upright at rest (%.1f deg)" % rad_to_deg(bike.lean_angle))
	await _done(r)


func _test_acceleration() -> void:
	var r := await ride({}, 12.0, func(b, _t): b.throttle = 1.0)
	var bike: Bike = r["bike"]
	check(not r["crashed"], "full-throttle run does not crash")
	check(r["max_speed"] > 30.0, "accelerates past 30 m/s in 12 s (%.1f m/s)" % r["max_speed"])
	check(bike.gear >= 3, "auto-shift moves up the gears (gear %d)" % bike.gear)
	check(absf(_heading(bike)) < deg_to_rad(10.0), "runs straight under power (%.1f deg off)" % rad_to_deg(_heading(bike)))
	await _done(r)


func _test_turning() -> void:
	for dir in [1.0, -1.0]:
		var yaw0 := [0.0]
		var r := await ride({}, 10.0, func(b, t):
			b.throttle = 0.45 if t < 4.0 else 0.3
			b.lean_input = 0.0 if t < 4.0 else 0.7 * dir
			if absf(t - 4.0) < 0.001:
				yaw0[0] = _heading(b))
		var bike: Bike = r["bike"]
		var turned := wrapf(_heading(bike) - yaw0[0], -PI, PI)
		var side := "right" if dir > 0 else "left"
		check(not r["crashed"], "leaning %s does not crash" % side)
		check(r["max_lean"] > deg_to_rad(15.0), "leans into the %s turn (max %.0f deg)" % [side, rad_to_deg(r["max_lean"])])
		# Turning right is a negative yaw in Godot's convention.
		check(turned * -dir > deg_to_rad(60.0), "turns %s (%.0f deg)" % [side, rad_to_deg(turned)])
		await _done(r)


func _test_braking() -> void:
	var stop_speed := [0.0]
	var r := await ride({}, 14.0, func(b, t):
		if t < 7.0:
			b.throttle = 1.0
		else:
			if stop_speed[0] == 0.0:
				stop_speed[0] = b.speed
			b.throttle = 0.0
			b.front_brake = 0.8
			b.rear_brake = 0.6)
	var bike: Bike = r["bike"]
	check(not r["crashed"], "hard braking does not crash")
	check(absf(bike.speed) < 1.5, "brakes from %.0f m/s to a stop (now %.1f m/s)" % [stop_speed[0], bike.speed])
	await _done(r)


func _test_low_speed() -> void:
	var r := await ride({}, 8.0, func(b, t):
		b.throttle = 0.12
		b.lean_input = sin(t * 1.5) * 0.8)
	check(not r["crashed"], "slow weaving at walking pace does not crash (max speed %.1f m/s)" % r["max_speed"])
	await _done(r)


func _test_all_builds_ride() -> void:
	var combos := [
		{"frame": "alu_twin_spar", "wheels": "slick_17", "engine": "single_450", "gearbox": "six_close", "final_drive": "tall_15_42"},
		{"fork": "long_travel_mx", "shock": "mono_shock_mx", "wheels": "knobbly_21_18", "engine": "single_450"},
		{"frame": "alu_twin_spar", "fork": "long_travel_mx", "shock": "mono_shock_mx", "wheels": "knobbly_21_18", "engine": "twin_700", "gearbox": "six_close"},
	]
	for c in combos:
		var r := await ride(c, 9.0, func(b, t):
			b.throttle = 0.8
			b.lean_input = 0.5 if t > 5.0 else 0.0)
		var name := "%s/%s/%s" % [PartsDB.sanitize_build(c)["frame"], PartsDB.sanitize_build(c)["wheels"], PartsDB.sanitize_build(c)["engine"]]
		check(not r["crashed"] and r["max_speed"] > 15.0, "%s rides and turns (%.0f m/s)" % [name, r["max_speed"]])
		await _done(r)
	var dirt_drive := func(b, t):
		b.throttle = 0.7
		b.lean_input = 0.4 if t > 4.0 else 0.0
	var dirt := await ride({"fork": "long_travel_mx", "shock": "mono_shock_mx", "wheels": "knobbly_21_18"}, 8.0, dirt_drive, "dirt")
	check(not dirt["crashed"], "knobbly tyres ride and turn on dirt")
	await _done(dirt)


func _test_crash_and_respawn() -> void:
	var r := await ride({}, 2.0, func(b, t):
		if t > 0.5 and not b.is_crashed:
			b.crash())
	var bike: Bike = r["bike"]
	check(bike.is_crashed, "crash puts the bike into the crashed state")
	bike.respawn()
	for i in 120:
		await get_tree().physics_frame
	check(not bike.is_crashed and absf(bike.lean_angle) < deg_to_rad(8.0), "respawn puts the bike back upright")
	await _done(r)


func _test_sim_mode() -> void:
	var r := await ride({}, 9.0, func(b, t):
		b.assist = 0.0
		b.throttle = 0.45 if t < 4.0 else 0.3
		b.lean_input = 0.0 if t < 4.0 else 0.6)
	check(not r["crashed"] and r["max_lean"] > deg_to_rad(15.0), "full-sim mode (no assist) still leans and turns")
	await _done(r)


func _test_shed_rules() -> void:
	Shed.start_new("Tester", 7)
	var me := Shed.me()
	check(Shed.bikes.size() == 3, "the shed opens with three project bikes")
	var ranger := _bike_named("Rusty Ranger")
	var barn := _bike_named("Barn Find")
	var faithful := _bike_named("Old Faithful")
	check(Shed.missing_slots(barn).size() == 3, "the barn find arrives with parts on the bench")
	check(Shed.is_complete(faithful) and not Shed.is_complete(barn), "complete bikes are rideable, stripped ones aren't")
	check(Shed.check(me, {"a": "remove", "bike": ranger, "slot": "engine"}) != "", "a bolted engine can't be pulled out")
	Shed.request({"a": "unbolt", "bike": ranger, "slot": "engine"})
	check(Shed.check(me, {"a": "remove", "bike": ranger, "slot": "engine"}).contains("first"),
		"the engine can't come out with the intake and exhaust on")
	Shed.request({"a": "unbolt", "bike": ranger, "slot": "exhaust"})
	Shed.request({"a": "remove", "bike": ranger, "slot": "exhaust"})
	var pipe := Shed.held_by(me)
	check(pipe != 0 and Shed.item_on(ranger, "exhaust") == 0, "an unbolted exhaust comes off into your hands")
	check(Shed.check(me, {"a": "shelf_take", "part": "slip_on"}) != "", "you can't carry two parts at once")
	check(Shed.check(me, {"a": "mount", "bike": ranger}) != "", "a bike with no exhaust can't be ridden")
	Shed.request({"a": "place", "spot": "washer"})
	var dirt_before: float = Shed.items[pipe]["dirt"]
	Shed._process(2.0)
	check(Shed.items[pipe]["dirt"] < dirt_before, "the parts washer cleans what's in it")
	check(Shed.check(me, {"a": "repair", "item": pipe}) != "", "repairs need the repair bench")
	Shed.request({"a": "take", "spot": "washer"})
	Shed.request({"a": "place", "spot": "repair"})
	Shed.request({"a": "repair", "item": pipe})
	check(Shed.items[pipe]["rust"] == 0.0 and Shed.items[pipe]["wear"] == 0.0, "the repair bench restores rust and wear")
	Shed.request({"a": "clean", "item": pipe})
	Shed.request({"a": "take", "spot": "repair"})
	Shed.request({"a": "install", "bike": ranger})
	check(Shed.item_on(ranger, "exhaust") == pipe and not Shed.is_bolted(ranger, "exhaust"), "a part goes back on loose")
	Shed.request({"a": "bolt", "bike": ranger, "slot": "exhaust"})
	Shed.request({"a": "bolt", "bike": ranger, "slot": "engine"})
	check(Shed.is_complete(ranger), "bolting everything up makes the bike rideable")
	var now := Shed.build_of(ranger).summary()
	var was: Dictionary = Shed.bikes[ranger]["delivered"]
	check(now["health"] > was["health"], "restoring a part raises the bike's condition (%.0f%% vs %.0f%%)" % [now["health"] * 100, was["health"] * 100])
	# Fitting a new part from the shelf, with the right mounting order.
	Shed.request({"a": "shelf_take", "part": "twin_disc_sport"})
	check(Shed.check(me, {"a": "install", "bike": barn}).contains("wheels"), "brakes need the wheels on first")
	Shed.request({"a": "bin"})
	check(Shed.held_by(me) == 0, "the scrap bin takes parts")
	var before := Shed.bikes.size()
	Shed.request({"a": "order"})
	check(Shed.bikes.size() == before + 1, "ordering a project bike delivers one to the free bay")
	check(Shed.check(me, {"a": "order"}) != "", "you can't order when every bay is full")
	Shed.stop()


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0


func _test_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	check(main.walker != null and main.in_session, "a solo session puts you in the shed on foot")
	check(main.workshop.bike_views.size() == 3, "the three project bikes are parked in their bays")
	var start: Vector3 = main.walker.global_position
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(main.walker.global_position.distance_to(start) > 1.0, "WASD walks you around (%.1f m)" % main.walker.global_position.distance_to(start))
	# Look at the Rusty Ranger's exhaust from beside it and unbolt it with the wrench.
	var ranger := _bike_named("Rusty Ranger")
	var view: Node3D = main.workshop.bike_views[ranger]
	var model: BikeModel = view.get_child(0)
	var aim: Vector3 = model.global_transform * model.slot_bounds("exhaust").get_center()
	var stand: Vector3 = aim + Vector3(1.4, 0.0, 0.0)
	stand.y = 0.0
	main.walker.place(Transform3D(Basis(), stand))
	main.walker.rotation.y = PI * 0.5
	var eye: Vector3 = stand + Vector3.UP * Walker.EYE
	main.walker._look(0.0, -atan2(eye.y - aim.y, Vector2(eye.x - aim.x, eye.z - aim.z).length()))
	for i in 5:
		await get_tree().physics_frame
	check(main.walker.target.get("kind", "") == "part", "the crosshair finds the bike's parts (%s)" % str(main.walker.target))
	var slot: String = main.walker.target.get("slot", "")
	main.walker.set_tool("wrench")
	Input.action_press("act")
	for i in 300:
		await get_tree().physics_frame
		if slot != "" and not Shed.is_bolted(ranger, slot):
			break
	Input.action_release("act")
	check(slot != "" and not Shed.is_bolted(ranger, slot), "holding the wrench on a part unbolts it (%s)" % slot)
	# Ride the finished sport bike out of the roller door.
	var faithful := _bike_named("Old Faithful")
	main._try_mount(faithful)
	await get_tree().physics_frame
	check(main.bike != null and main.riding_id == faithful, "F on a finished bike gets you on it")
	check(not main.workshop.bike_views.has(faithful), "the parked copy disappears while you ride")
	for i in 120:
		await get_tree().physics_frame
	Input.action_press("throttle", 0.35)
	for i in 600:
		await get_tree().physics_frame
		if main.bike.global_position.z > Workshop.CENTER.z + Workshop.HALF.y + 4.0:
			break
	Input.action_release("throttle")
	check(not main.bike.is_crashed and main.bike.global_position.z > Workshop.CENTER.z + Workshop.HALF.y + 4.0,
		"the bike rides out through the roller door (z %.1f)" % main.bike.global_position.z)
	Input.action_press("front_brake")
	Input.action_press("rear_brake")
	for i in 600:
		await get_tree().physics_frame
		if absf(main.bike.speed) < 0.5:
			break
	Input.action_release("front_brake")
	Input.action_release("rear_brake")
	main._get_off()
	await get_tree().physics_frame
	check(main.bike == null and Shed.bikes[faithful]["rider"] == 0, "F when stopped gets you off")
	check(main.workshop.bike_views.has(faithful), "the bike stays parked where you left it")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_world() -> void:
	var t0 := Time.get_ticks_msec()
	var world := World.new()
	add_child(world)
	world.generate(1234)
	var gen_ms := Time.get_ticks_msec() - t0
	check(world.road_length() > 800.0 and world.road_length() < 1400.0, "riding loop is about 1 km (%.0f m)" % world.road_length())
	check(gen_ms < 20000, "map generates in reasonable time (%d ms)" % gen_ms)
	var bike := Bike.new()
	bike.setup(BikeBuild.new())
	world.add_child(bike)
	var spawn: Transform3D = world.spawn_point(0)
	bike.place(spawn.origin, spawn.basis.get_euler().y)
	for i in 360:
		bike.throttle = 0.5
		await get_tree().physics_frame
	check(not bike.is_crashed and bike.speed > 5.0, "bike rides in the Build Yard (%.1f m/s)" % bike.speed)
	# Drop a bike onto the road loop and check it lands on the road surface.
	var road_t: Transform3D = world.road_transform(0.3)
	bike.place(road_t.origin, road_t.basis.get_euler().y)
	var surfaces := {}
	for i in 240:
		bike.throttle = 0.3
		await get_tree().physics_frame
		if i % 30 == 29:
			surfaces[bike.surface] = surfaces.get(bike.surface, 0) + 1
	check(not bike.is_crashed and surfaces.get("tarmac", 0) >= 3, "bike rides on the tarmac loop (%s)" % str(surfaces))
	road_t = world.road_transform(0.75)
	bike.place(road_t.origin, road_t.basis.get_euler().y)
	for i in 60:
		await get_tree().physics_frame
	check(bike.surface == "dirt", "the far side of the loop is dirt (on %s)" % bike.surface)
	world.queue_free()
	await get_tree().physics_frame
