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
	await _test_engine_and_effects()
	print("Models")
	_test_models()
	print("The shed")
	_test_shed_rules()
	_test_garage_life()
	_test_equipment_and_chains()
	print("Round 5: scratch builds, engines, clocks, yard kit")
	_test_round5_shed()
	_test_round5_models()
	await _test_round5_riding()
	print("Sound and radio")
	_test_sounds()
	_test_mp3_decoder()
	await _test_radio_stream()
	print("Co-op addresses")
	_test_addresses()
	print("World")
	await _test_world()
	print("Game session")
	await _test_session()


const SLICK := {"front_tyre": "race_slick", "rear_tyre": "race_slick"}
const MX := {"fork": "long_travel_mx", "shock": "mono_shock_mx", "front_wheel": "spoked_21", "rear_wheel": "spoked_18",
	"front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx"}


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func _test_catalogue() -> void:
	check(PartsDB.KINDS.size() == 27 and PartsDB.parts.size() >= 170, "catalogue has 27 kinds of part (%d parts)" % PartsDB.parts.size())
	for k in PartsDB.KINDS:
		check(PartsDB.by_kind[k].size() >= 5, "%s has at least five variants (%d)" % [k, PartsDB.by_kind[k].size()])
	var no_colour := []
	for id in PartsDB.parts:
		if not PartsDB.parts[id].has("color"):
			no_colour.append(id)
	check(no_colour.is_empty(), "every part has a colour %s" % str(no_colour))
	check(PartsDB.SLOTS.size() == 33, "a bike has 33 slots, 7 of them on the engine")
	var b := BikeBuild.new()
	check(b.bike_mass > 120.0 and b.bike_mass < 230.0, "default bike mass is plausible (%.0f kg)" % b.bike_mass)
	check(b.hp() > 40.0 and b.hp() < 120.0, "default bike power is plausible (%.0f hp)" % b.hp())
	check(b.notes.is_empty(), "the default bike's parts suit each other %s" % str(b.notes))
	var top := b.top_speed_estimate() * 3.6
	check(top > 120.0 and top < 260.0, "default top speed estimate is plausible (%.0f km/h)" % top)
	check(absf(b.front_radius - 0.3) < 0.03 and absf(b.rear_radius - 0.31) < 0.03,
		"17\" wheels with road tyres make a 0.3 m wheel (%.3f / %.3f)" % [b.front_radius, b.rear_radius])
	var bad := PartsDB.sanitize_build({"engine": "nope", "frame": "long_travel_mx"})
	check(bad["engine"] == PartsDB.DEFAULT_BUILD["engine"] and bad["frame"] == PartsDB.DEFAULT_BUILD["frame"],
		"unknown or wrong-kind parts fall back to defaults")
	var curve := b.dyno_curve()
	check(curve.size() > 10 and curve[0]["torque"] > 0.0, "dyno curve has data")
	# Condition matters.
	var rusty := BikeBuild.new({}, {"engine": {"rust": 0.8, "dirt": 0.9, "wear": 0.8}})
	check(rusty.hp() < b.hp() * 0.85, "a worn, rusty engine makes less power (%.0f vs %.0f hp)" % [rusty.hp(), b.hp()])
	var clogged := BikeBuild.new({"air_filter": "pod_filters"}, {"air_filter": {"dirt": 1.0}})
	var clean := BikeBuild.new({"air_filter": "pod_filters"})
	check(clogged.peak_torque < clean.peak_torque * 0.85, "a clogged pod filter chokes the engine")
	var plugs := BikeBuild.new({}, {"spark_plugs": {"wear": 1.0}})
	check(plugs.peak_torque < b.peak_torque * 0.85 and plugs.notes.size() == 1, "worn spark plugs misfire")
	var tired := BikeBuild.new({}, {"front_pads": {"wear": 1.0, "rust": 1.0}, "front_disc": {"wear": 1.0}})
	check(tired.front_brake_torque < b.front_brake_torque * 0.8, "worn pads and discs stop less well")
	var race_brakes := BikeBuild.new({"front_disc": "floating_330_race", "front_caliper": "six_piston_race",
		"front_pads": "carbon_race", "front_master": "race_radial"})
	check(race_brakes.front_brake_torque > b.front_brake_torque * 1.5, "race brake parts bite much harder (%.0f vs %.0f Nm)" % [
		race_brakes.front_brake_torque, b.front_brake_torque])
	var faster := BikeBuild.new({"exhaust": "titanium_race", "air_filter": "velocity_stacks", "head": "big_valve_ported",
		"fuel": "flat_slide_carbs"})
	check(faster.hp() > b.hp() * 1.1, "tuned head, carbs, stacks and exhaust add power (%.0f hp)" % faster.hp())
	# Engine parts have to suit each other.
	var starved := BikeBuild.new({"engine": "four_1000", "fuel": "single_carb", "cooling": "twin_radiators"})
	var fed := BikeBuild.new({"engine": "four_1000", "fuel": "throttle_bodies", "cooling": "twin_radiators"})
	check(starved.hp() < fed.hp() * 0.9 and str(starved.notes).contains("starved"), "one carb can't feed a 1000 cc four")
	var hot := BikeBuild.new({"engine": "four_1000", "head": "race_high_comp", "fuel": "race_injection", "cooling": "air_fins"})
	var cool := BikeBuild.new({"engine": "four_1000", "head": "race_high_comp", "fuel": "race_injection", "cooling": "race_radiator"})
	check(hot.hp() < cool.hp() and str(hot.notes).contains("hot"), "a race head needs a radiator, not fins")
	# Chassis parts.
	check(BikeBuild.new({"handlebars": "mx_tall"}).steer_rate > BikeBuild.new({"handlebars": "clip_ons"}).steer_rate,
		"wide bars steer quicker than clip-ons")
	check(BikeBuild.new({"tank": "touring_23"}).bike_mass > BikeBuild.new({"tank": "peanut_9"}).bike_mass + 5.0,
		"a big tank carries more fuel weight")
	check(b.front_rebound > b.front_bump and b.rear_rebound > b.rear_bump, "suspension has separate bump and rebound damping")
	check(BikeBuild.new({"dashboard": "analog_speedo"}).dash_features == ["speed"]
		and BikeBuild.new({"dashboard": "race_logger"}).dash_features.has("shift_light"), "the dashboard decides what the speedo shows")
	check(PartsDB.dependents("engine").has("exhaust") and PartsDB.dependents("engine").has("final_drive")
		and not PartsDB.dependents("engine").has("head"), "exhaust and chain come off before the engine; its head goes with it")
	check(PartsDB.dependents("front_wheel").has("front_tyre") and PartsDB.dependents("front_disc").has("front_caliper")
		and PartsDB.dependents("front_caliper").has("front_pads"), "tyres, discs, calipers and pads come off in order")
	check(PartsDB.dependents("head").has("spark_plugs") and PartsDB.dependents("fuel").has("air_filter"),
		"plugs and carbs come off the head, the filter off the carbs")


## Every part can be drawn on its own and on a bike.
func _test_models() -> void:
	var bad := []
	for id in PartsDB.parts:
		var d := BikeModel.part_display(id, {"rust": 0.5, "dirt": 0.5, "wear": 0.2, "color": Color(0.2, 0.4, 0.9)})
		var size: Vector3 = d.get_meta("size")
		if size.length() < 0.02:
			bad.append(id)
		d.free()
	check(bad.is_empty(), "every part has a model of its own %s" % str(bad))
	var count := 0
	for k in ["engine", "head", "fuel", "air_filter", "cooling", "handlebars", "dashboard", "tank", "saddle", "fork"]:
		for id in PartsDB.by_kind[k]:
			var m := BikeModel.new()
			m.build_from(BikeBuild.new({PartsDB.slots_for_kind(k)[0]: id}))
			m.build_pickers({"bike": 1})
			count += m.get_child_count()
			m.free()
	check(count > 0, "whole bikes build with every engine and body variant")


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
		_merge(SLICK, {"frame": "alu_twin_spar", "engine": "single_450", "gearbox": "six_close", "final_drive": "tall_15_42"}),
		_merge(MX, {"engine": "single_450"}),
		_merge(MX, {"frame": "alu_twin_spar", "engine": "twin_700", "gearbox": "six_close"}),
		{"engine": "vtwin_900", "fork": "girder_vintage", "handlebars": "ape_hangers", "front_wheel": "wire_19_chrome",
			"front_tyre": "vintage_ribbed", "rear_tyre": "vintage_ribbed", "cooling": "air_fins", "head": "two_valve_stock"},
	]
	for c in combos:
		var r := await ride(c, 9.0, func(b, t):
			b.throttle = 0.8
			b.lean_input = 0.5 if t > 5.0 else 0.0)
		var full := PartsDB.sanitize_build(c)
		var name := "%s/%s/%s/%s" % [full["frame"], full["fork"], full["rear_tyre"], full["engine"]]
		check(not r["crashed"] and r["max_speed"] > 15.0, "%s rides and turns (%.0f m/s)" % [name, r["max_speed"]])
		await _done(r)
	var dirt_drive := func(b, t):
		b.throttle = 0.7
		b.lean_input = 0.4 if t > 4.0 else 0.0
	var dirt := await ride(MX, 8.0, dirt_drive, "dirt")
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
	var colours := {}
	for id in Shed.items:
		colours[Shed.items[id]["color"]] = true
	check(colours.size() > 8, "parts come in their own colours (%d different)" % colours.size())
	check(Shed.missing_slots(barn).size() == 5, "the barn find arrives stripped, its engine out (%s)" % str(Shed.missing_slots(barn)))
	var stand_spot: String = Shed.stand_spots()[0]
	var block := Shed.item_at_spot(stand_spot)
	check(Shed.is_engine(block) and Shed.engine_missing(block) == ["air_filter", "spark_plugs"],
		"its engine is on the stand, missing plugs and air filter (%s)" % str(Shed.engine_missing(block) if block else []))
	check(Shed.is_complete(faithful) and not Shed.is_complete(barn), "complete bikes are rideable, stripped ones aren't")
	check(Shed.check(me, {"a": "remove", "bike": ranger, "slot": "engine"}) != "", "a bolted engine can't be pulled out")
	Shed.request({"a": "unbolt", "bike": ranger, "slot": "engine"})
	check(Shed.check(me, {"a": "remove", "bike": ranger, "slot": "engine"}).contains("first"),
		"the engine can't come out with the exhaust and chain on")
	check(Shed.check(me, {"a": "unbolt", "bike": ranger, "slot": "spark_plugs"}) == "", "plugs can be serviced in the frame")
	Shed.request({"a": "unbolt", "bike": ranger, "slot": "head"})
	check(Shed.check(me, {"a": "remove", "bike": ranger, "slot": "head"}).contains("engine stand"),
		"the cylinder head needs the engine on the stand")
	Shed.request({"a": "bolt", "bike": ranger, "slot": "head"})
	Shed.request({"a": "unbolt", "bike": ranger, "slot": "exhaust"})
	Shed.request({"a": "remove", "bike": ranger, "slot": "exhaust"})
	var pipe := Shed.held_by(me)
	check(pipe != 0 and Shed.item_on(ranger, "exhaust") == 0, "an unbolted exhaust comes off into your hands")
	check(Shed.check(me, {"a": "take", "spot": "bench_0"}) != "", "you can't carry two parts at once")
	check(Shed.check(me, {"a": "mount", "bike": ranger}) != "", "a bike with no exhaust can't be ridden")
	var washer := _spot_on("washer")
	var repair := _spot_on("repair")
	check(washer != "" and repair != "", "the shed starts with a parts washer and a repair bench (%s, %s)" % [washer, repair])
	Shed.request({"a": "place", "spot": washer})
	var dirt_before: float = Shed.items[pipe]["dirt"]
	Shed._process(2.0)
	check(Shed.items[pipe]["dirt"] < dirt_before, "the parts washer cleans what's in it")
	check(Shed.check(me, {"a": "repair", "item": pipe}) != "", "repairs need the repair bench")
	check(Shed.check(me, {"a": "paint", "item": pipe, "color": 3}).contains("rust"), "rusty parts can't be painted")
	Shed.request({"a": "take", "spot": washer})
	Shed.request({"a": "place", "spot": repair})
	Shed.request({"a": "repair", "item": pipe})
	check(Shed.items[pipe]["rust"] == 0.0 and Shed.items[pipe]["wear"] == 0.0, "the repair bench restores rust and wear")
	Shed.request({"a": "paint", "item": pipe, "color": 3, "finish": "chrome"})
	check(Shed.items[pipe]["color"] == Shed.PAINTS[3] and Shed.items[pipe]["finish"] == "chrome",
		"the spray can paints a restored part in the chosen colour and finish")
	check(Shed.check(me, {"a": "paint", "item": pipe, "color": 3, "finish": "chrome"}).contains("already"),
		"spraying the same paint again is refused")
	check(Shed.condition_text(Shed.items[pipe]).contains("Chrome green"), "the info panel names the finish")
	for f in Shed.FINISHES:
		var mat_model := BikeModel.part_display("stock_muffler", {"rust": 0.0, "dirt": 0.0, "wear": 0.0,
			"color": Shed.PAINTS[0], "finish": f})
		mat_model.free()
	var chrome := StandardMaterial3D.new()
	BikeModel._apply_finish(chrome, Shed.PAINTS[0], "chrome")
	var matte := StandardMaterial3D.new()
	BikeModel._apply_finish(matte, Shed.PAINTS[0], "matte")
	check(chrome.metallic > 0.9 and chrome.roughness < 0.15 and matte.roughness > 0.8, "chrome is a mirror and matte is flat")
	Shed.request({"a": "clean", "item": pipe})
	Shed.request({"a": "take", "spot": repair})
	Shed.request({"a": "install", "bike": ranger, "slot": "frame"})
	check(Shed.item_on(ranger, "exhaust") == pipe and not Shed.is_bolted(ranger, "exhaust"), "a part goes back on loose")
	Shed.request({"a": "bolt", "bike": ranger, "slot": "exhaust"})
	Shed.request({"a": "bolt", "bike": ranger, "slot": "engine"})
	check(Shed.is_complete(ranger), "bolting everything up makes the bike rideable")
	var now := Shed.build_of(ranger).summary()
	var was: Dictionary = Shed.bikes[ranger]["delivered"]
	check(now["health"] > was["health"], "restoring a part raises the bike's condition (%.0f%% vs %.0f%%)" % [now["health"] * 100, was["health"] * 100])

	# Building up the barn find's engine on the stand with parts from the computer.
	check(Shed.check(me, {"a": "order_part", "part": "spark_plugs"}) != "", "you can only order real parts")
	var plugs := _order("iridium_plugs")
	var box_at: Transform3D = Shed.items[plugs]["ref"]
	check(Shed.items[plugs]["boxed"] and Shed.items[plugs]["at"] == "floor" and box_at.origin.z > Workshop.CENTER.z + Workshop.HALF.y,
		"an ordered part arrives boxed, outside the roller door")
	Shed.request({"a": "take", "item": plugs})
	check(Shed.check(me, {"a": "install", "engine": block, "slot": "head"}).contains("Unpack"), "a part has to be unpacked before it fits")
	Shed.request({"a": "drop", "xf": box_at})
	Shed.request({"a": "unpack", "item": plugs})
	check(not Shed.items[plugs]["boxed"] and Shed.items[plugs]["wear"] == 0.0, "unpacking the box leaves a brand new part")
	var filter := _order("cotton_gauze")
	Shed.request({"a": "unpack", "item": filter})
	Shed.request({"a": "take", "item": filter})
	check(Shed.check(me, {"a": "install", "engine": block, "slot": "head"}) == "", "the air filter fits the engine on the stand")
	check(Shed.check(me, {"a": "install", "bike": barn, "slot": "frame"}).contains("engine first"),
		"engine parts need an engine in the bike")
	Shed.request({"a": "install", "engine": block, "slot": "head"})
	check(Shed.engine_item(block, "air_filter") != 0, "the air filter goes on the carbs")
	Shed.request({"a": "take", "item": plugs})
	Shed.request({"a": "install", "engine": block, "slot": "head"})
	for slot in ["air_filter", "spark_plugs"]:
		Shed.request({"a": "bolt", "engine": block, "slot": slot})
	check(Shed.engine_missing(block).is_empty() and Shed.engine_bolted(block, "spark_plugs"), "the engine is complete on the stand")
	Shed.request({"a": "unbolt", "engine": block, "slot": "spark_plugs"})
	Shed.request({"a": "remove", "engine": block, "slot": "spark_plugs"})
	check(Shed.held_by(me) == plugs, "parts come off the engine on the stand")
	Shed.request({"a": "install", "engine": block, "slot": "spark_plugs"})
	Shed.request({"a": "bolt", "engine": block, "slot": "spark_plugs"})
	Shed.request({"a": "take", "spot": stand_spot})
	check(Shed.held_by(me) == block and Shed.engine_item(block, "head") != 0, "the engine comes off the stand with its parts")
	Shed.request({"a": "install", "bike": barn, "slot": "frame"})
	check(Shed.item_on(barn, "engine") == block and Shed.item_on(barn, "spark_plugs") == plugs, "the built engine goes into the frame")
	Shed.request({"a": "bolt", "bike": barn, "slot": "engine"})
	# The bench has the exhaust, chain, sprockets and front tyre; the sprockets go on before the chain.
	for spot in ["bench_0", "bench_2", "bench_1", "bench_3"]:
		var item := Shed.item_at_spot(spot)
		var k: String = Shed.items[item]["kind"]
		Shed.request({"a": "take", "spot": spot})
		Shed.request({"a": "install", "bike": barn, "slot": "rear_tyre" if k == "tyre" else "frame", "crouched": true})
	check(Shed.item_on(barn, "front_tyre") != 0 and Shed.item_on(barn, "rear_tyre") != 0, "a tyre fills whichever wheel is bare")
	for slot in Shed.loose_slots(barn):
		Shed.request({"a": "bolt", "bike": barn, "slot": slot, "crouched": true})
	check(Shed.is_complete(barn), "the barn find is rebuilt and ready to ride (%s)" % str(Shed.missing_slots(barn) + Shed.loose_slots(barn)))

	# Mounting order on the chassis.
	var pads := _order("carbon_race")
	Shed.request({"a": "unpack", "item": pads})
	Shed.request({"a": "take", "item": pads})
	check(Shed.check(me, {"a": "install", "bike": barn, "slot": "front_pads"}).contains("already"), "a full bike has no room for more pads")
	Shed.request({"a": "unbolt", "bike": barn, "slot": "front_pads"})
	check(Shed.install_slot({"bike": barn, "slot": "front_caliper"}, Shed.held_by(me)).get("error", "") != "", "pads need their old ones out first")
	Shed.request({"a": "bin"})
	check(Shed.held_by(me) == 0, "the scrap bin takes parts")
	# Equipment: a second engine stand and a shelving unit, pushed into place.
	Shed.request({"a": "order_furniture", "kind": "stand"})
	Shed.request({"a": "order_furniture", "kind": "shelf"})
	check(Shed.stand_spots().size() == 2, "a second engine stand can be ordered")
	var shelf := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "shelf":
			shelf = id
	check(shelf != 0 and Shed.furniture_spots(shelf).size() == 12, "a shelving unit adds twelve places to put things")
	Shed.request({"a": "grab", "furniture": shelf})
	check(Shed.moving(me) == shelf and Shed.check(me, {"a": "mount", "bike": faithful}) != "", "you push one thing at a time and can't ride off with it")
	var wall := Transform3D(Basis(), Workshop.CENTER + Vector3(-2.0, 0.0, 4.6))
	Shed.request({"a": "release", "furniture": shelf, "xf": wall})
	check(Shed.moving(me) == 0 and Shed.furniture[shelf]["xf"] == wall, "letting go leaves it where you pushed it")
	var stock := _order("flat_bar")
	Shed.request({"a": "take", "item": stock})
	Shed.request({"a": "place", "spot": "shelf_%d_3" % shelf})
	check(Shed.items[stock]["boxed"] and Shed.items[stock]["ref"] == "shelf_%d_3" % shelf, "boxed stock goes on the shelves")
	check(Shed.spot_transform("shelf_%d_3" % shelf).origin.distance_to(wall.origin) < 2.0, "shelf places move with the shelf")
	Shed.request({"a": "label", "furniture": shelf, "text": "Handlebars"})
	check(Shed.furniture_name(Shed.furniture[shelf]) == "Shelving unit: Handlebars", "shelves take a label")
	check(Shed.check(me, {"a": "place", "spot": "stand_%d" % shelf}) != "", "a shelf isn't an engine stand")
	for i in 12:
		Shed.request({"a": "order_part", "part": "flat_bar"})
	check(Shed.check(me, {"a": "order_part", "part": "flat_bar"}).contains("full"), "you can't order with the delivery area full")
	# The brush scrubs a whole cluster of parts.
	var dirty: Array = []
	for id in Shed.items:
		if Shed.items[id]["at"] == "bike" and Shed.items[id]["dirt"] > 0.1:
			dirty.append(id)
	Shed.request({"a": "clean_many", "items": dirty.slice(0, 3)})
	check(dirty.slice(0, 3).all(func(id): return Shed.items[id]["dirt"] == 0.0), "the brush cleans several parts at once")
	var before := Shed.bikes.size()
	Shed.request({"a": "order"})
	check(Shed.bikes.size() == before + 1, "ordering a project bike delivers one to the free bay")
	check(Shed.check(me, {"a": "order"}) != "", "you can't order when every bay is full")
	Shed.stop()


func _test_equipment_and_chains() -> void:
	Shed.start_new("Tester", 11)
	var me := Shed.me()
	# The shop sells every kind of equipment, with compact versions for a tight shed.
	for k in Equipment.KINDS:
		check(Equipment.by_kind(k).size() >= 2, "the parts computer sells %s (%d models)" % [Equipment.KIND_NAMES[k].to_lower(), Equipment.by_kind(k).size()])
	for k in ["washer", "repair", "bench", "shelf"]:
		check(Equipment.by_kind(k).any(func(m): return Equipment.get_model(m).get("compact", false)), "there's a compact %s" % Equipment.KIND_NAMES[k].to_lower())
	check(Equipment.places("shelf_standard") == 12 and Equipment.places("shelf_racking") == 20, "shelves hold more: 12 on a standard unit, 20 on racking")
	for model in Equipment.MODELS:
		check(Equipment.spec_line(model) != "", "%s has a spec line" % model)
	# Order a compact washer, a big repair machine, a poster, a seat and a TV.
	var ordered := {}
	for model in ["washer_compact", "repair_workshop", "poster_cafe", "seat_sofa", "tv_55", "bench_compact"]:
		Shed.request({"a": "order_furniture", "model": model})
		for id in Shed.furniture:
			if Shed.furniture[id]["model"] == model:
				ordered[model] = id
	check(ordered.size() == 6, "equipment orders arrive outside (%s)" % str(ordered.keys()))
	check(Shed.check(me, {"a": "order_furniture", "model": "rocket_ship"}) != "", "you can only order real equipment")
	var machine: int = ordered["repair_workshop"]
	check(Shed.furniture_spots(machine).size() == 4 and Shed.spot_role(Shed.furniture_spots(machine)[0]) == "repair",
		"the machine shop bench has four repair places")
	# Restore several parts at once on the repair machine.
	var rusty := []
	for part in ["stock_muffler", "flat_bar", "cafe_15"]:
		var id := Shed._new_item(part, 0.7, 0.3, 0.5)
		Shed._move(id, "spot", Shed.furniture_spots(machine)[rusty.size()])
		rusty.append(id)
	var batch := Shed.repair_batch(Shed.furniture_spots(machine)[0])
	check(batch.size() == 3, "the grinder works on every part on the machine (%d)" % batch.size())
	check(Shed.repair_time(batch) < 3.0 * Shed.repair_time([rusty[0]]) * 0.6, "doing three at once is much quicker than one by one")
	Shed.request({"a": "repair_many", "items": batch})
	check(rusty.all(func(id): return Shed.items[id]["rust"] == 0.0 and Shed.items[id]["wear"] == 0.0), "all three parts come off restored")
	check(Shed.check(me, {"a": "repair_many", "items": batch}).contains("top condition"), "nothing left to restore")
	# A parts washer with two places cleans both.
	var washer := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "washer_standard":
			washer = id
	var grubby := []
	for n in 2:
		var id := Shed._new_item("paper_oil", 0.0, 0.8, 0.0)
		Shed._move(id, "spot", Shed.furniture_spots(washer)[n])
		grubby.append(id)
	Shed._process(1.0)
	check(grubby.all(func(id): return Shed.items[id]["dirt"] < 0.8), "the parts washer cleans both parts in it")
	# A poster hangs on the wall where you let go.
	var poster: int = ordered["poster_cafe"]
	Shed.request({"a": "grab", "furniture": poster})
	var on_wall := Transform3D(Basis(Vector3.UP, PI), Workshop.CENTER + Vector3(0.0, 2.0, Workshop.HALF.y - 0.01))
	Shed.request({"a": "release", "furniture": poster, "xf": on_wall})
	check(Shed.furniture[poster]["xf"] == on_wall and Equipment.is_wall("poster_cafe"), "posters hang on the wall")
	check(EquipmentView.sit_point("seat_sofa", 2).x > EquipmentView.sit_point("seat_sofa", 0).x, "a sofa seats several")

	# Chains: they stretch and dry out as you ride, and you tighten and lube them.
	var faithful := _bike_named("Old Faithful")
	var chain := Shed.item_on(faithful, "chain")
	check(chain != 0 and Shed.items[chain].has("slack") and Shed.items[chain].has("lube"), "bikes have a chain with slack and lube")
	Shed.items[chain]["slack"] = 30.0
	Shed.items[chain]["lube"] = 1.0
	var fresh := Shed.build_of(faithful)
	Shed.crew[me]["riding"] = faithful
	Shed._wear_from_ride(faithful, {"km": 5.0, "dirt_km": 3.0})
	Shed.crew[me]["riding"] = 0
	check(float(Shed.items[chain]["slack"]) > 30.0 and float(Shed.items[chain]["lube"]) < 1.0,
		"riding stretches the chain and wears the lube off (%.1f mm, %.0f%%)" % [Shed.items[chain]["slack"], Shed.items[chain]["lube"] * 100.0])
	Shed.items[chain]["slack"] = 70.0
	Shed.items[chain]["lube"] = 0.0
	var neglected := Shed.build_of(faithful)
	check(neglected.drivetrain_efficiency < fresh.drivetrain_efficiency * 0.95 and str(neglected.notes).contains("slack")
		and str(neglected.notes).contains("dry"), "a slack, dry chain wastes power and the bay screen says so (%s)" % str(neglected.notes))
	check(Shed.check(me, {"a": "adjust_chain", "bike": faithful}).contains("Crouch"), "you crouch to get at the chain adjusters")
	Shed.request({"a": "adjust_chain", "bike": faithful, "crouched": true})
	check(is_equal_approx(float(Shed.items[chain]["slack"]), Shed.CHAIN_SLACK_SET), "the wrench sets the chain tension right")
	check(Shed.check(me, {"a": "adjust_chain", "bike": faithful, "crouched": true}).contains("spot on"), "no need to adjust a good chain")
	check(Shed.check(me, {"a": "lube", "item": chain, "crouched": true}).contains("chain lube"), "lubing needs a can of chain lube")
	var can := Shed._new_item("wax_lube", 0.0, 0.0, 0.0)
	Shed._move(can, "held", me)
	Shed.request({"a": "lube", "item": chain, "crouched": true})
	check(float(Shed.items[chain]["lube"]) == 1.0 and float(Shed.items[can]["fluid"]["litres"]) < 0.4, "the can lubes the chain and gets lighter")
	check(Shed.build_of(faithful).drivetrain_efficiency > neglected.drivetrain_efficiency, "a tight, lubed chain gives the power back")
	check(Shed.condition_text(Shed.items[chain]).contains("Chain slack 30 mm"), "the info panel shows chain slack and lube")
	Shed._erase_item(can)
	check(PartsDB.dependents("final_drive").has("chain"), "the chain comes off before the sprockets")

	# More wheels, and parts that save weight.
	check(PartsDB.by_kind["wheel"].size() >= 15, "there are %d wheels" % PartsDB.by_kind["wheel"].size())
	var sizes := {}
	for w in PartsDB.by_kind["wheel"]:
		sizes[float(PartsDB.get_part(w)["diameter"])] = true
		var display := BikeModel.part_display(w, {"rust": 0.0, "dirt": 0.0, "wear": 0.0, "color": PartsDB.default_color(w), "finish": ""})
		display.free()
	check(sizes.size() >= 5, "wheels come in %d sizes" % sizes.size())
	var light := 0
	for id in PartsDB.parts:
		if PartsDB.is_lightweight(id):
			light += 1
	check(light >= 12, "%d lightweight parts to choose from" % light)
	var stock := BikeBuild.new()
	var diet := BikeBuild.new({"tank": "carbon_sport_16", "exhaust": "carbon_slip_on", "saddle": "carbon_race_seat",
		"handlebars": "alloy_clip_ons", "front_wheel": "forged_17_mag", "rear_wheel": "forged_17_mag", "chain": "light_428"})
	check(diet.bike_mass < stock.bike_mass - 10.0 and diet.power_to_weight() > stock.power_to_weight(),
		"lightweight parts cut %.0f kg and raise power to weight" % (stock.bike_mass - diet.bike_mass))
	check(PartsDB.spec_line("carbon_sport_16").contains("Lightweight"), "the parts computer flags lightweight parts")
	Shed.stop()


## The first place on the first piece of equipment of a kind ("washer", "repair"...).
func _spot_on(kind: String) -> String:
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == kind:
			return Shed.furniture_spots(id)[0]
	return ""


## Orders a part and returns its box, waiting outside.
func _order(part: String) -> int:
	Shed.request({"a": "order_part", "part": part})
	var newest := 0
	for id in Shed.items:
		if Shed.items[id]["part"] == part and Shed.items[id].get("boxed", false):
			newest = maxi(newest, id)
	return newest


## Riding round 3: stands, headlights, fluids, wheeling bikes, the wash bay and units.
func _test_garage_life() -> void:
	Shed.start_new("Tester", 11)
	var me := Shed.me()
	var barn := _bike_named("Barn Find")
	var faithful := _bike_named("Old Faithful")
	# Optional parts.
	check(PartsDB.by_kind["side_stand"].size() >= 5 and PartsDB.by_kind["centre_stand"].size() >= 5
		and PartsDB.by_kind["headlight"].size() >= 5, "side stands, centre stands and headlights come in five or more variants")
	check(Shed.item_on(faithful, "side_stand") != 0 and Shed.item_on(faithful, "headlight") != 0 and Shed.item_on(faithful, "centre_stand") == 0,
		"a stock bike has a side stand and a headlight but no centre stand")
	check(PartsDB.dependents("fork").has("headlight") and PartsDB.dependents("frame").has("side_stand"), "the headlight hangs off the fork, the stands off the frame")
	check(BikeBuild.new({"headlight": "led_projector"}).headlight_lumens > BikeBuild.new({"headlight": "round_7"}).headlight_lumens,
		"an LED projector is brighter than a halogen lamp")
	check(not Shed.missing_slots(faithful).has("centre_stand"), "a bike rides without the optional parts")
	check(Shed.check(me, {"a": "unbolt", "bike": faithful, "slot": "side_stand"}).contains("Crouch")
		and Shed.check(me, {"a": "unbolt", "bike": faithful, "slot": "side_stand", "crouched": true}) == "",
		"low parts need you to crouch down to reach them")
	# Fluids.
	var tank: int = Shed.item_on(barn, "tank")
	var fuel: Dictionary = Shed.items[tank]["fluid"]
	check(fuel["litres"] < 8.0 and fuel["age"] > 0.4, "the barn find has a little stale petrol in it (%.1f L, age %.2f)" % [fuel["litres"], fuel["age"]])
	check(Shed.fluid_text(Shed.items[tank]).contains("stale"), "the info panel says the petrol is stale")
	Shed.request({"a": "order_part", "part": "empty_jerry_can"})
	var empty := _newest("empty_jerry_can")
	check(empty != 0 and not Shed.items[empty]["boxed"] and Shed.items[empty]["fluid"]["litres"] == 0.0, "an empty jerry can arrives unboxed and empty")
	Shed.request({"a": "take", "item": empty})
	Shed.request({"a": "drain", "item": tank})
	check(Shed.items[tank]["fluid"]["litres"] == 0.0 and Shed.items[empty]["fluid"]["litres"] > 0.0, "draining the tank fills the empty can")
	check(Shed.check(me, {"a": "pour", "item": Shed.item_on(barn, "front_master")}).contains("brake fluid"), "petrol doesn't go in the brakes")
	Shed.request({"a": "tip"})
	check(Shed.items[empty]["fluid"]["litres"] == 0.0, "the scrap bin takes old fluid")
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER)})
	Shed.request({"a": "order_part", "part": "super_98"})
	var petrol := _newest("super_98")
	Shed.request({"a": "take", "item": petrol})
	Shed.request({"a": "pour", "item": tank})
	check(absf(Shed.items[tank]["fluid"]["litres"] - 5.0) < 0.01 and Shed.items[tank]["fluid"]["type"] == "super_98"
		and Shed.items[tank]["fluid"]["age"] == 0.0, "pouring a can of super fills the tank with fresh fuel")
	check(Shed.items[petrol]["fluid"]["litres"] == 0.0 and Shed.check(me, {"a": "pour", "item": tank}).contains("empty"), "the can is empty afterwards")
	Shed.request({"a": "bin"})
	# Oil: draining needs a pan, crouching, and an engine; low oil hurts.
	var ranger := _bike_named("Rusty Ranger")
	var block: int = Shed.item_on(ranger, "engine")
	var full_hp := BikeBuild.new({"engine": "single_450"}).hp()
	Shed.request({"a": "order_part", "part": "drain_pan"})
	var pan := _newest("drain_pan")
	Shed.request({"a": "take", "item": pan})
	check(Shed.check(me, {"a": "drain", "item": block}).contains("Crouch"), "you crouch to get at the drain plug")
	Shed.request({"a": "drain", "item": block, "crouched": true})
	check(Shed.items[block]["fluid"]["litres"] == 0.0, "the old oil drains into the pan")
	var dry := Shed.build_of(ranger)
	check(str(dry.notes).contains("No oil") and dry.hp() < full_hp, "an engine with no oil is flagged and down on power")
	var wear_before := float(Shed.items[block]["wear"])
	Shed.bikes[ranger]["rider"] = me
	Shed.crew[me]["riding"] = ranger
	Shed.request({"a": "ride", "km": 1.0, "dirt_km": 1.0, "fuel": 0.3})
	check(Shed.items[block]["wear"] > wear_before + 0.01, "riding with no oil wears the engine out fast")
	var tyre: int = Shed.item_on(ranger, "rear_tyre")
	var dash: int = Shed.item_on(ranger, "dashboard")
	Shed.items[tyre]["dirt"] = 0.0
	Shed.items[dash]["dirt"] = 0.0
	Shed.request({"a": "ride", "km": 1.0, "dirt_km": 1.0, "fuel": 0.3})
	check(Shed.items[tyre]["dirt"] > 0.2 and Shed.items[dash]["dirt"] < Shed.items[tyre]["dirt"] * 0.5,
		"riding the dirt plasters the tyres and barely touches the clocks (%.2f / %.2f)" % [Shed.items[tyre]["dirt"], Shed.items[dash]["dirt"]])
	Shed.bikes[ranger]["rider"] = 0
	Shed.crew[me]["riding"] = 0
	Shed.request({"a": "tip"})
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER)})
	Shed.request({"a": "order_part", "part": "synthetic_5w40"})
	var oil := _newest("synthetic_5w40")
	Shed.request({"a": "take", "item": oil})
	Shed.request({"a": "pour", "item": block})
	var cap := PartsDB.fluid_capacity("single_450")
	check(absf(Shed.items[block]["fluid"]["litres"] - minf(cap, 4.0)) < 0.01 and Shed.build_of(ranger).oil_age == 0.0,
		"fresh synthetic oil goes in (%.1f of %.1f L)" % [Shed.items[block]["fluid"]["litres"], cap])
	Shed.request({"a": "bin"})
	# Brakes need fluid.
	var good := BikeBuild.new()
	var dry_brakes := BikeBuild.new({}, {"front_master": {"fluid": {"type": "dot4", "litres": 0.05, "age": 0.0}}})
	check(dry_brakes.front_brake_torque < good.front_brake_torque * 0.6 and str(dry_brakes.notes).contains("spongy"),
		"low brake fluid makes a spongy front brake")
	# Petrol and economy.
	var econ := good.cruise_economy()
	check(econ > 12.0 and econ < 40.0, "the default bike does a plausible %.1f km per litre at 90 km/h" % econ)
	var stale := BikeBuild.new({}, {"tank": {"fluid": {"type": "unleaded_95", "litres": 5.0, "age": 1.0}}})
	check(stale.hp() < good.hp() * 0.9, "stale petrol saps power")
	check(BikeBuild.new({}, {"tank": {"fluid": {"type": "race_fuel", "litres": 5.0, "age": 0.0}}}).hp() > good.hp(), "race fuel adds power")
	check(BikeBuild.new({"engine": "four_1000"}).cruise_economy() < BikeBuild.new({"engine": "single_250"}).cruise_economy(),
		"a big four drinks more than a small single")
	# Wheeling a bike about and its stands.
	check(Shed.check(me, {"a": "grab_bike", "bike": barn}).contains("wheels"), "a bike without tyres can't be wheeled")
	Shed.request({"a": "grab_bike", "bike": faithful})
	check(Shed.pushing_bike(me) == faithful and Shed.check(me, {"a": "mount", "bike": faithful}) != "", "you take hold of a bike to wheel it")
	var yard := Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 9.0))
	Shed.request({"a": "release_bike", "bike": faithful, "xf": yard})
	check(Shed.bikes[faithful]["stand"] == "side" and Shed.bikes[faithful]["xf"] == yard, "let go, it rests on its side stand")
	Shed.request({"a": "set_stand", "bike": faithful, "stand": "centre"})
	check(Shed.bikes[faithful]["stand"] == "side", "no centre stand fitted, so it stays on the side stand")
	# Take the side stand off: let go of it now and it falls over.
	Shed.request({"a": "unbolt", "bike": faithful, "slot": "side_stand", "crouched": true})
	Shed.request({"a": "remove", "bike": faithful, "slot": "side_stand", "crouched": true})
	var side := Shed.held_by(me)
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER)})
	Shed.request({"a": "grab_bike", "bike": faithful})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": yard})
	check(Shed.bikes[faithful]["stand"] == "down", "a bike with no stand falls over when you let go")
	Shed.request({"a": "order_part", "part": "lever_centre"})
	var centre := _newest("lever_centre")
	Shed.request({"a": "unpack", "item": centre})
	Shed.request({"a": "take", "item": centre})
	Shed.request({"a": "install", "bike": faithful, "slot": "centre_stand", "crouched": true})
	Shed.request({"a": "bolt", "bike": faithful, "slot": "centre_stand", "crouched": true})
	Shed.request({"a": "set_stand", "bike": faithful, "stand": "centre"})
	check(Shed.bikes[faithful]["stand"] == "centre", "a fitted centre stand holds the bike up")
	Shed.request({"a": "take", "item": side})
	Shed.request({"a": "install", "bike": faithful, "slot": "side_stand", "crouched": true})
	Shed.request({"a": "bolt", "bike": faithful, "slot": "side_stand", "crouched": true})
	# Back into its bay: it goes onto the paddock stand.
	var bay_xf: Transform3D = Workshop.bay_transform(Shed.bikes[faithful]["bay"])
	Shed.request({"a": "grab_bike", "bike": faithful})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": bay_xf.translated(Vector3(0.4, 0.0, 0.3))})
	check(Shed.on_paddock(faithful) and Shed.bikes[faithful]["xf"].origin.distance_to(bay_xf.origin) < 0.01,
		"let go in a bay and it snaps onto the paddock stand")
	# The wash bay.
	var muddy: Array = []
	for slot in ["front_tyre", "rear_tyre", "fork"]:
		var id := Shed.item_on(faithful, slot)
		Shed.items[id]["dirt"] = 0.8
		muddy.append(id)
	check(Shed.check(me, {"a": "wash", "items": muddy, "at": Workshop.CENTER}).contains("hose"), "the hose only reaches around the wash bay")
	for i in 5:
		Shed.request({"a": "wash", "items": muddy, "at": Workshop.WASH_CENTER})
	check(muddy.all(func(id): return Shed.items[id]["dirt"] < 0.5), "the pressure washer blasts the muck off")
	# Units.
	Settings.units = "imperial"
	var mph := Units.speed_value(100.0 / 3.6)
	var lb := Units.mass(100.0)
	var mpg := Units.economy(20.0)
	Settings.units = "metric"
	check(mph == 62 and lb == "220 lb" and mpg == "56 mpg" and Units.economy(20.0) == "5.0 L/100 km" and Units.kmh(100.0) == "100 km/h",
		"units switch between metric and imperial (%d mph, %s, %s)" % [mph, lb, mpg])
	Shed.stop()


func _newest(part: String) -> int:
	var newest := 0
	for id in Shed.items:
		if Shed.items[id]["part"] == part:
			newest = maxi(newest, id)
	return newest


## The engine needs starting, burns petrol and stalls when it runs dry; smoke, dust and the headlight.
func _test_engine_and_effects() -> void:
	var r := await ride({}, 0.5, func(b, _t): b.engine_on = false; b.throttle = 1.0)
	var bike: Bike = r["bike"]
	check(bike.speed < 0.2 and not bike.effects.smoke_emitting(), "with the engine off there's no drive and no smoke")
	check(bike.start_engine() == "", "the starter cranks")
	for i in 120:
		await get_tree().physics_frame
	check(bike.engine_on and bike.effects.smoke_emitting() and bike.effects.light_on(), "it fires: exhaust smoke and the headlight come on")
	bike.fuel_litres = 0.002
	bike.throttle = 1.0
	for i in 240:
		await get_tree().physics_frame
	check(not bike.engine_on and bike.fuel_litres == 0.0 and bike.fuel_used > 0.0, "running out of petrol stalls the engine")
	check(bike.start_engine().contains("petrol"), "it won't start with an empty tank")
	await _done(r)
	var d := await ride({"front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx"}, 4.0, func(b, _t): b.throttle = 0.6, "dirt")
	check(d["bike"].effects.dust_emitting(), "riding on dirt kicks up dust")
	await _done(d)


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0


func _test_sounds() -> void:
	var ok := true
	for sound in ["ratchet", "scrub", "grinder", "spray", "washer", "static", "clink", "clunk", "pickup", "step", "scrap", "switch"]:
		var wav := Sfx.stream(sound)
		var loud := 0
		for i in range(0, wav.data.size() - 1, 64):
			loud = maxi(loud, absi(wav.data.decode_s16(i)))
		if wav.data.size() < 1000 or loud < 2000 or loud > 32767:
			ok = false
			print("    quiet or broken sound: ", sound, " peak ", loud)
	check(ok, "every shed sound is made and audible")
	check(AudioServer.get_bus_index("SFX") != -1 and AudioServer.get_bus_index("Radio") != -1, "sound effects and radio have their own volume")
	Shed.start_new("Tester", 7)
	check(not Shed.radio["on"] and Shed.stations.size() >= 5, "the radio starts off with %d stations to pick from" % Shed.stations.size())
	Shed.request({"a": "radio", "on": true, "station": 2})
	check(Shed.radio["on"] and Shed.radio["station"] == 2, "anyone can switch the radio on and pick a station")
	check(Shed._snapshot()["radio"]["station"] == 2, "the radio's state goes to everyone with the shed")
	check(Shed.check(Shed.me(), {"a": "radio", "station": 99}) != "", "there's no station 99")
	Shed.stop()


## A live stream arrives in odd-sized pieces; decoding it run by run must join up seamlessly.
## (A sine this loud steps about 0.03 per sample; a bad join jumps 0.15 or more.)
func _test_mp3_decoder() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/sine_440_mp3.bin")
	var dec := Mp3StreamDecoder.new()
	var out := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pos := 0
	while pos < bytes.size():
		var n := rng.randi_range(300, 5000)
		dec.feed(bytes.slice(pos, pos + n))
		pos += n
		out.append_array(dec.decode(10))
	var worst := 0.0
	for i in range(3000, out.size()):
		worst = maxf(worst, absf(out[i].x - out[i - 1].x))
	check(out.size() > AudioServer.get_mix_rate() * 3.0, "the stream decodes to audio (%.1f s)" % (out.size() / AudioServer.get_mix_rate()))
	check(worst < 0.06, "the joins between decoded runs are seamless (biggest step %.3f)" % worst)


## Runs a tiny radio station on this machine: it redirects once, then streams the test tone
## with a song title in the metadata, the way Icecast and Shoutcast servers do.
func _test_radio_stream() -> void:
	var server := TCPServer.new()
	var port := 0
	for p in range(18750, 18800):
		if server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	var holder := Node3D.new()
	add_child(holder)
	var speaker := AudioStreamPlayer3D.new()
	holder.add_child(speaker)
	var radio := RadioStream.new()
	radio.player = speaker
	holder.add_child(radio)
	radio.tune("http://127.0.0.1:%d/start" % port)
	var audio := FileAccess.get_file_as_bytes("res://tests/fixtures/sine_440_mp3.bin")
	var metaint := 4000
	var conns: Array[StreamPeerTCP] = []
	var sent := {}
	for frame in 600:
		await get_tree().process_frame
		while server.is_connection_available():
			conns.append(server.take_connection())
		for c in conns:
			c.poll()
			if not sent.has(c):
				if c.get_available_bytes() == 0:
					continue
				var req := c.get_utf8_string(c.get_available_bytes())
				if req.begins_with("GET /start"):
					c.put_data(("HTTP/1.0 302 Found\r\nLocation: http://127.0.0.1:%d/live\r\n\r\n" % port).to_utf8_buffer())
					sent[c] = -1
				else:
					c.put_data(("ICY 200 OK\r\nicy-name: Test FM\r\nicy-metaint: %d\r\n\r\n" % metaint).to_utf8_buffer())
					sent[c] = 0
			elif sent[c] >= 0 and sent[c] < audio.size():
				var at: int = sent[c]
				var piece := audio.slice(at, at + metaint)
				c.put_data(piece)
				sent[c] = at + piece.size()
				if piece.size() == metaint:
					var meta := "StreamTitle='Test Artist - Test Song';".to_utf8_buffer()
					var blocks := ceili(meta.size() / 16.0)
					meta.resize(blocks * 16)
					var lead := PackedByteArray([blocks])
					lead.append_array(meta)
					c.put_data(lead)
		if radio.is_live() and radio.title != "":
			break
	check(radio.is_live(), "the radio follows a redirect, buffers the stream and plays it (%s)" % radio.status)
	check(radio.title == "Test Artist - Test Song", "the radio reads the song title from the stream (%s)" % radio.title)
	radio.stop()
	check(not speaker.playing, "switching off stops the sound")
	server.stop()
	holder.queue_free()
	await get_tree().process_frame


## Stands the walker beside a bike slot and points the crosshair at it.
func _aim_at(main: Node, bike_id: int, slot: String) -> void:
	var model: BikeModel = main.workshop.bike_model(bike_id)
	var aim: Vector3 = model.global_transform * model.slot_bounds(slot).get_center()
	var stand: Vector3 = aim + Vector3(1.4, 0.0, 0.0)
	stand.y = 0.0
	main.walker.place(Transform3D(Basis(), stand))
	main.walker.rotation.y = PI * 0.5
	var eye: Vector3 = stand + Vector3.UP * Walker.EYE
	main.walker._look(0.0, -atan2(eye.y - aim.y, Vector2(eye.x - aim.x, eye.z - aim.z).length()))
	for i in 5:
		await get_tree().physics_frame


## Holds the work button until the current job is done.
func _hold_act(main: Node) -> void:
	Input.action_press("act")
	for i in 240:
		await get_tree().physics_frame
		if main.walker.progress == 0.0 and i > 10:
			break
	Input.action_release("act")
	await get_tree().physics_frame


## Sends a real press and release of an action through the viewport, as a key would.
func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		get_viewport().push_input(ev)


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
	# A TV on the back wall, to watch the ride on later.
	Shed.request({"a": "order_furniture", "model": "tv_55"})
	var tv_id := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "tv":
			tv_id = id
	Shed.request({"a": "grab", "furniture": tv_id})
	Shed.request({"a": "release", "furniture": tv_id, "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(1.6, 3.4, -Workshop.HALF.y + 0.02))})
	# Look at the Rusty Ranger's exhaust from beside it and unbolt it with the wrench.
	var ranger := _bike_named("Rusty Ranger")
	var view: Node3D = main.workshop.bike_views[ranger]
	var model: BikeModel = main.workshop.bike_model(ranger)
	var aim: Vector3 = model.global_transform * (model.exhaust_tip() + Vector3(0.0, -0.04, -0.2))
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
	# Put a part down on the open floor, then pick it back up off the floor.
	main.walker.set_tool("hands")
	var plugs := _order("iridium_plugs")
	# Walk out to the box by the door and press F on it to unpack it.
	var box_at: Vector3 = Shed.items[plugs]["ref"].origin
	main.walker.place(Transform3D(Basis(), box_at + Vector3(0.0, 0.0, 1.0)))
	main.walker.rotation.y = 0.0
	main.walker._pitch = 0.0
	main.walker._look(0.0, -atan2(Walker.EYE - 0.1, 1.0))
	for i in 5:
		await get_tree().physics_frame
	check(main.walker.target.get("item", 0) == plugs, "the crosshair finds the delivery box outside (%s)" % str(main.walker.target))
	_press("interact")
	await get_tree().physics_frame
	check(not Shed.items[plugs]["boxed"], "F on a delivery box unpacks it")
	Shed.request({"a": "take", "item": plugs})
	main.walker.place(Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 1.0)))
	main.walker._look(0.0, -0.9)
	for i in 5:
		await get_tree().physics_frame
	check(main.walker.plan.get("action", {}).get("a", "") == "drop", "holding a part and looking at the floor offers to put it down (%s)" % str(main.walker.plan))
	await _hold_act(main)
	check(Shed.items[plugs]["at"] == "floor" and Shed.held_by(Shed.me()) == 0, "the part is put down on the floor")
	check(main.workshop._floor_nodes.has(plugs), "the floor part is drawn where it was put down")
	for i in 5:
		await get_tree().physics_frame
	check(main.walker.target.get("item", 0) == plugs, "the crosshair finds the part on the floor (%s)" % str(main.walker.target))
	await _hold_act(main)
	check(Shed.held_by(Shed.me()) == plugs, "the part is picked back up off the floor")
	# Build the stripped engine on the stand back up: aim at the block and fit the plugs.
	var block: int = Shed.item_at_spot(Shed.stand_spots()[0])
	var stand_at: Vector3 = Shed.spot_transform(Shed.stand_spots()[0]).origin
	main.walker.place(Transform3D(Basis(), Vector3(stand_at.x - 1.4, 0.0, stand_at.z)))
	main.walker.rotation.y = -PI * 0.5
	main.walker._pitch = 0.0
	main.walker._look(0.0, -atan2(Walker.EYE - stand_at.y - 0.1, 1.4))
	for i in 5:
		await get_tree().physics_frame
	check(main.walker.plan.get("action", {}).get("a", "") == "install", "holding plugs at the engine on the stand offers to fit them (%s)" % str(main.walker.plan))
	await _hold_act(main)
	check(Shed.engine_item(block, "spark_plugs") == plugs, "the plugs go back on the engine on the stand")
	# F on the stand grabs it; walk it backwards across the floor and let go.
	var stand_id: int = Shed.furniture_of_spot(Shed.stand_spots()[0])["id"]
	var stand_from: Vector3 = Shed.furniture[stand_id]["xf"].origin
	_press("interact")
	await get_tree().physics_frame
	check(Shed.moving(Shed.me()) == stand_id, "F on the engine stand takes hold of it")
	Input.action_press("move_back")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_back")
	_press("interact")
	await get_tree().physics_frame
	var moved: float = Shed.furniture[stand_id]["xf"].origin.distance_to(stand_from)
	check(Shed.moving(Shed.me()) == 0 and moved > 0.8, "the stand rolls with you and stays where you let go (%.1f m)" % moved)
	check(Shed.spot_transform(Shed.stand_spots()[0]).origin.distance_to(stand_from) > 0.8, "the engine travels on the stand")
	main.walker.place(Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 1.0)))
	main.walker._pitch = 0.0
	main.walker._look(0.0, 0.0)
	# Aim at it and press a real F, so the press can't also reach the get-off handler.
	var faithful := _bike_named("Old Faithful")
	await _aim_at(main, faithful, "tank")
	check(int(main.walker.target.get("bike", 0)) == faithful, "the crosshair finds Old Faithful (%s)" % str(main.walker.target))
	_press("interact")
	for i in 3:
		await get_tree().physics_frame
	check(main.bike != null and main.riding_id == faithful, "F on a finished bike gets you on it")
	_press("interact")
	await get_tree().physics_frame
	check(main.bike != null, "a second F straight away doesn't throw you off")
	check(not main.workshop.bike_views.has(faithful), "the parked copy disappears while you ride")
	check(not main.bike.engine_on, "you get on with the engine off")
	var fuel_at_start: float = Shed.items[Shed.item_on(faithful, "tank")]["fluid"]["litres"]
	Input.action_press("throttle", 0.5)
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("throttle")
	check(main.bike.speed < 0.2, "with the engine off the throttle does nothing")
	_press("ignition")
	for i in 120:
		await get_tree().physics_frame
	check(main.bike.engine_on and main.bike.rpm > 500.0, "I starts the engine (%.0f rpm)" % main.bike.rpm)
	_press("camera")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rider_eye: Vector3 = main.bike.model.global_transform * main.bike.model.eye_transform().origin
	check(main.camera.mode == ChaseCamera.Mode.HELMET and main.camera.global_position.distance_to(rider_eye) < 0.05
		and not main.camera.get_cull_mask_value(BikeModel.HELMET_LAYER), "C switches to first person, from the rider's eyes inside the helmet")
	# The forearms reaching down to the bars, just above the gloves (low clip-ons sit under the view, as they do).
	var grips: Vector3 = main.camera.to_local(main.bike.model.global_transform * (main.bike.model._head + main.bike.model._grip_l + Vector3(0.0, 0.12, 0.1)))
	var dash: Vector3 = main.camera.to_local(main.bike.model.global_transform * (main.bike.model._head + Vector3(0.0, 0.1, -0.06)))
	check(main.camera.is_position_in_frustum(main.camera.to_global(grips)) and main.camera.is_position_in_frustum(main.camera.to_global(dash)),
		"the first-person view shows the rider's arms on the bars and the clocks (arms %s, dash %s)" % [grips, dash])
	check(main._dash != null and main._dash.text.contains(Units.speed_unit()), "the clocks show speed and fuel (%s)" % main._dash.text.replace("\n", " / "))
	_press("camera")
	await get_tree().physics_frame
	Input.action_press("throttle", 0.35)
	for i in 600:
		await get_tree().physics_frame
		if main.bike.global_position.z > Workshop.CENTER.z + Workshop.HALF.y + 4.0:
			break
	Input.action_release("throttle")
	check(not main.bike.is_crashed and main.bike.global_position.z > Workshop.CENTER.z + Workshop.HALF.y + 4.0,
		"the bike rides out through the roller door (z %.1f)" % main.bike.global_position.z)
	await get_tree().process_frame
	var screens: Array = main.workshop.tvs()
	check(screens.size() == 1 and screens[0].is_live() and main.workshop.tv_feed != null, "the shed TV shows the ride live")
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
	check(Shed.bikes[faithful]["stand"] == "side", "getting off puts it on its side stand")
	check(Shed.items[Shed.item_on(faithful, "tank")]["fluid"]["litres"] < fuel_at_start, "the ride used some petrol")
	# Crouch down, then stand back up.
	_press("crouch")
	for i in 40:
		await get_tree().physics_frame
	check(main.walker.crouched and main.walker.camera.position.y < 1.0, "C crouches you down (eye at %.2f m)" % main.walker.camera.position.y)
	_press("crouch")
	for i in 40:
		await get_tree().physics_frame
	check(not main.walker.crouched and main.walker.camera.position.y > 1.5, "C again stands you up")
	# Hold F on the parked bike to take hold of it, wheel it backwards, and let go.
	await _aim_at(main, faithful, "tank")
	var parked_at: Vector3 = Shed.bikes[faithful]["xf"].origin
	var down := InputEventAction.new()
	down.action = "interact"
	down.pressed = true
	get_viewport().push_input(down)
	for i in 60:
		await get_tree().physics_frame
	var up := InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().physics_frame
	check(Shed.pushing_bike(Shed.me()) == faithful and main.bike == null, "holding F on a bike takes hold of it instead of getting on")
	Input.action_press("move_back")
	for i in 90:
		await get_tree().physics_frame
	Input.action_release("move_back")
	_press("interact")
	await get_tree().physics_frame
	var wheeled: float = Shed.bikes[faithful]["xf"].origin.distance_to(parked_at)
	check(Shed.pushing_bike(Shed.me()) == 0 and wheeled > 1.0 and Shed.bikes[faithful]["stand"] == "side",
		"you can pull it backwards, and let go it goes back on its stand (%.1f m)" % wheeled)
	# Into the wash bay with it, and blast the mud off with the pressure washer.
	Shed.request({"a": "grab_bike", "bike": faithful})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": Transform3D(Basis(), Workshop.WASH_CENTER)})
	for washed in ["front_tyre", "front_wheel", "fork"]:
		Shed.items[Shed.item_on(faithful, washed)]["dirt"] = 0.9
	Shed.changed.emit()
	await get_tree().physics_frame
	await _aim_at(main, faithful, "front_tyre")
	main.walker.set_tool("lance")
	await get_tree().physics_frame
	check(main.walker.plan.get("action", {}).get("a", "") == "wash" and main.walker.plan["blocked"] == "",
		"the pressure washer is ready in the wash bay (%s / %s)" % [str(main.walker.plan.get("blocked", main.walker.plan)), str(main.walker.target)])
	Input.action_press("act")
	for i in 180:
		await get_tree().physics_frame
	Input.action_release("act")
	var tyre_dirt: float = Shed.items[Shed.item_on(faithful, "front_tyre")]["dirt"]
	check(tyre_dirt < 0.5, "holding the trigger keeps the jet going and washes the tyre (%.2f dirt left)" % tyre_dirt)
	main.walker.set_tool("hands")
	await get_tree().physics_frame
	check(main.workshop.tvs().size() == 1 and not main.workshop.tvs()[0].is_live(), "with nobody riding, the TV goes back to the crew board")
	await _session_equipment(main, faithful)
	await _session_round5(main)
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## Equipment in the real shed: every model draws, posters hang on walls, seats sit you down,
## the grinder does a whole machine at once and the wrench sets chain tension.
func _session_equipment(main: Node, faithful: int) -> void:
	var w: Walker = main.walker
	var row := 0
	for model in Equipment.MODELS:
		var kind := Equipment.kind_of(model)
		var at := Workshop.CENTER + Vector3(-20.0 + (row % 8) * 3.0, 0.0, 30.0 + (row / 8) * 3.0)
		Shed._new_furniture(kind, Transform3D(Basis(), at), model)
		row += 1
	Shed.changed.emit()
	await get_tree().process_frame
	var drawn := 0
	for id in main.workshop.furniture_nodes:
		if main.workshop.furniture_nodes[id] is EquipmentView:
			drawn += 1
	check(drawn == Shed.furniture.size() and drawn >= Equipment.MODELS.size(), "every model of equipment is drawn in the world (%d)" % drawn)
	# Carry a poster and hang it on the side wall.
	var poster := 0
	var sofa := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "poster_mx":
			poster = id
		if Shed.furniture[id]["model"] == "seat_sofa":
			sofa = id
	Shed.request({"a": "grab", "furniture": poster})
	w.place(Transform3D(Basis(Vector3.UP, PI * 0.5), Workshop.CENTER + Vector3(-Workshop.HALF.x + 1.5, 0.0, 1.0)))
	for i in 4:
		await get_tree().physics_frame
	check(w._on_wall, "holding a poster up to the wall offers to hang it")
	_press("interact")
	await get_tree().physics_frame
	var hung: Transform3D = Shed.furniture[poster]["xf"]
	check(Shed.moving(Shed.me()) == 0 and absf(hung.origin.x - (Workshop.CENTER.x - Workshop.HALF.x)) < 0.1 and hung.origin.y > 1.0,
		"F hangs it flat on the wall (%s)" % str(hung.origin))
	# Sit on the sofa, then walk off it.
	Shed.request({"a": "grab", "furniture": sofa})
	Shed.request({"a": "release", "furniture": sofa, "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 2.0))})
	await get_tree().physics_frame
	w.sit(sofa)
	for i in 3:
		await get_tree().physics_frame
	check(w.seat == sofa and w.camera.global_position.y < Walker.EYE, "you can sit on the sofa (eye at %.2f m)" % w.camera.global_position.y)
	Input.action_press("move_forward")
	for i in 3:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(w.seat == 0, "walking gets you up again")
	# Two rusty parts on the repair bench: the grinder does both.
	var bench_spots: Array = []
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "repair_standard" and bench_spots.is_empty():
			bench_spots = Shed.furniture_spots(id)
	var rusty := []
	for n in 2:
		var part := Shed._new_item("stock_muffler", 0.6, 0.2, 0.4)
		Shed._move(part, "spot", bench_spots[n])
		rusty.append(part)
	Shed.changed.emit()
	await get_tree().process_frame
	var spot_at: Vector3 = Shed.spot_transform(bench_spots[0]).origin + Vector3.UP * 0.15
	w.place(Transform3D(Basis(), spot_at + Vector3(0.0, -spot_at.y, -1.2)))
	w.set_tool("repair")
	await _aim_point(w, spot_at)
	check(w.plan.get("action", {}).get("a", "") == "repair_many" and w.plan["action"]["items"].size() == 2,
		"the grinder offers to restore both parts on the bench (%s)" % str(w.plan.get("verb", w.target)))
	Input.action_press("act")
	for i in 1200:
		await get_tree().physics_frame
		if rusty.all(func(id): return Shed.items[id]["rust"] == 0.0):
			break
	Input.action_release("act")
	check(rusty.all(func(id): return Shed.items[id]["rust"] == 0.0), "holding the grinder restores both")
	# The wrench's second button sets the chain tension, crouched by the bike.
	var chain := Shed.item_on(faithful, "chain")
	Shed.items[chain]["slack"] = 60.0
	w.set_tool("wrench")
	w.set_crouched(true)
	var model: BikeModel = main.workshop.bike_model(faithful)
	var aim: Vector3 = model.global_transform * model.slot_bounds("chain").get_center()
	var side: Vector3 = model.global_transform.basis.x
	var feet := aim - Vector3(side.x, 0.0, side.z).normalized() * 1.0
	feet.y = 0.0
	w.place(Transform3D(Basis(), feet))
	await _aim_point(w, aim)
	check(w.alt_plan.get("action", {}).get("a", "") == "adjust_chain" and w.alt_plan["blocked"] == "",
		"crouched with the wrench at the chain, the second button adjusts it (%s / %s)" % [str(w.alt_plan.get("blocked", "")), str(w.target)])
	w.set_crouched(false)
	w.set_tool("hands")


## Building a bike from a bare frame, the yard kit, and the new engines in the catalogue.
func _test_round5_shed() -> void:
	Shed.start_new("Tester", 5)
	var me := Shed.me()
	# A frame set up on the empty fourth bay becomes a new bike to build on.
	Shed.request({"a": "order_part", "part": "steel_cradle"})
	var frame := 0
	for id in Shed.items:
		if Shed.items[id]["part"] == "steel_cradle" and Shed.items[id]["at"] == "floor":
			frame = id
	Shed.request({"a": "unpack", "item": frame})
	Shed.request({"a": "take", "item": frame})
	check(Shed.check(me, {"a": "start_build", "bay": 0}).contains("already"), "a frame can't go on a bay that has a bike in it")
	var bay := Shed.free_bay(Workshop.BAY_COUNT)
	check(bay == 3 and Shed.bay_at(Workshop.bay_transform(bay).origin) == bay, "bay 4 is the empty one")
	var before := Shed.bikes.size()
	Shed.request({"a": "start_build", "bay": bay})
	var scratch := 0
	for id in Shed.bikes:
		if Shed.item_on(id, "frame") == frame:
			scratch = id
	check(Shed.bikes.size() == before + 1 and scratch != 0 and Shed.held_by(me) == 0,
		"setting the frame on the empty bay's stand starts a bike from scratch")
	check(str(Shed.bikes[scratch]["name"]) == "Scratch build 1" and Shed.missing_slots(scratch).has("fork")
		and Shed.on_paddock(scratch), "it's just a frame on the paddock stand, waiting for parts")
	# Now parts go on it like any bike.
	Shed.request({"a": "order_part", "part": "classic_conventional"})
	var fork := 0
	for id in Shed.items:
		if Shed.items[id]["part"] == "classic_conventional" and Shed.items[id]["at"] == "floor":
			fork = id
	Shed.request({"a": "unpack", "item": fork})
	Shed.request({"a": "take", "item": fork})
	Shed.request({"a": "install", "bike": scratch, "slot": "fork"})
	check(Shed.item_on(scratch, "fork") == fork, "the forks bolt onto the bare frame (%s)" % Shed.check(me, {"a": "install", "bike": scratch, "slot": "fork"}))
	check(Shed.build_of(scratch).hp() > 0.0 and not Shed.build_of(scratch).summary().is_empty(), "the bay screens can show its numbers")
	# Strip it back to nothing and the bay is free again.
	Shed.request({"a": "unbolt", "bike": scratch, "slot": "fork"})
	Shed.request({"a": "remove", "bike": scratch, "slot": "fork"})
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER)})
	Shed.request({"a": "unbolt", "bike": scratch, "slot": "frame"})
	Shed.request({"a": "remove", "bike": scratch, "slot": "frame"})
	check(not Shed.bikes.has(scratch) and Shed.held_by(me) == frame and Shed.bay_is_free(bay),
		"taking the frame off the stand clears the bay")

	# The yard comes with a jump line, a slalom and things to jump, and more can be ordered.
	var yard := {}
	for id in Shed.furniture:
		if Equipment.is_yard(str(Shed.furniture[id]["model"])):
			yard[Equipment.kind_of(str(Shed.furniture[id]["model"]))] = true
	check(yard.size() == 4, "the yard has ramps, things to jump, walls and markers (%s)" % str(yard.keys()))
	for k in Equipment.YARD_KINDS:
		check(Equipment.by_kind(k).size() >= 4, "the parts computer sells %s (%d)" % [Equipment.KIND_NAMES[k].to_lower(), Equipment.by_kind(k).size()])
	for model in ["ramp_small", "ramp_medium", "ramp_large", "ramp_landing", "cone", "post", "flag_red", "wall_concrete", "fence_wood", "barrels", "car_wreck"]:
		check(Equipment.get_model(model).size() > 0, "%s is in the catalogue" % model)
	var n := Shed.furniture.size()
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER)})
	Shed.request({"a": "order_furniture", "model": "ramp_large"})
	var ordered: Dictionary = Shed.furniture[Shed.furniture.keys().max()]
	var at: Vector3 = ordered["xf"].origin
	check(Shed.furniture.size() == n + 1 and ordered["model"] == "ramp_large" and at.z > 104.0 and absf(at.x) < 65.0,
		"an ordered ramp is left in the yard past the drag strip (%s)" % str(at))
	check(Shed.check(me, {"a": "grab", "furniture": ordered["id"]}) == "", "you can take hold of it to move it")

	# Six engine layouts in ten sizes each.
	for layout in ["boxer", "twin", "parallel", "vtwin", "2stroke", "inline"]:
		var sizes := 0
		for cc in [50, 125, 350, 500, 600, 750, 800, 1000, 1100, 1200]:
			var p := PartsDB.get_part("%s_%d" % [layout, cc])
			if not p.is_empty() and p["layout"] == layout and int(p["displacement"]) == cc:
				sizes += 1
		check(sizes == 10, "%s engines come in all ten sizes (%d)" % [layout, sizes])
	var small := BikeBuild.new({"engine": "parallel_125"})
	var big := BikeBuild.new({"engine": "parallel_1200"})
	check(big.hp() > small.hp() * 5.0 and small.redline > big.redline, "a 125 is gutless and revvy next to a 1200 (%.0f vs %.0f hp)" % [small.hp(), big.hp()])
	check(BikeBuild.new({"engine": "2stroke_125"}).hp() > BikeBuild.new({"engine": "twin_125"}).hp(), "a two-stroke makes more power per cc")


func _test_round5_models() -> void:
	# The clocks face the rider, and dial clocks have needles that move.
	for dash in ["analog_speedo", "twin_clocks", "lcd_basic", "tft_colour", "race_logger"]:
		var m := BikeModel.new()
		add_child(m)
		m.build_from(BikeBuild.new({"dashboard": dash}))
		var label := m.dash_readout()
		var facing: Vector3 = label.global_transform.basis.z
		check(facing.z > 0.3 and facing.y > 0.3, "the %s readout faces back up at the rider (%s)" % [dash, str(facing)])
		if dash in ["analog_speedo", "twin_clocks"]:
			check(m.has_dials(), "%s has needles" % dash)
			var n0: Basis = m._needles[0]["node"].basis
			m.set_gauges(0.8, 0.8)
			check(not m._needles[0]["node"].basis.is_equal_approx(n0), "the %s needle swings with speed" % dash)
		m.queue_free()
	# Tanks sit behind the bars and the saddle behind the tank; the eye is in the helmet.
	for frame in ["steel_cradle", "steel_backbone", "alu_twin_spar"]:
		for tank in PartsDB.by_kind["tank"]:
			var m := BikeModel.new()
			add_child(m)
			m.build_from(BikeBuild.new({"frame": frame, "tank": tank, "handlebars": "clip_ons"}))
			var t := m.slot_bounds("tank")
			var bars := m.slot_bounds("handlebars")
			var seat := m.slot_bounds("saddle")
			check(t.position.z > m._head.z + 0.04 and t.end.z < seat.position.z + 0.12,
				"%s on a %s sits between the bars and the seat (%.2f..%.2f, head %.2f, seat %.2f)" % [tank, frame, t.position.z, t.end.z, m._head.z, seat.position.z])
			m.queue_free()
	var m := BikeModel.new()
	add_child(m)
	m.build_from(BikeBuild.new({}))
	var eye := m.eye_transform().origin
	check(eye.y > m._head.y + 0.4 and eye.z > m._head.z, "the first-person eye is up in the rider's helmet (%.2f m above the bars)" % (eye.y - m._head.y))
	m.queue_free()
	# Every engine layout draws, from 50 cc to 1200.
	for layout in ["boxer", "twin", "parallel", "vtwin", "2stroke", "inline"]:
		var sizes := []
		for cc in [50, 1200]:
			var em := BikeModel.new()
			add_child(em)
			em.build_from(BikeBuild.new({"engine": "%s_%d" % [layout, cc]}))
			sizes.append(em.slot_bounds("engine").size.length())
			em.queue_free()
		check(sizes[1] > sizes[0] * 1.2, "a 1200 cc %s is drawn bigger than a 50 (%.2f vs %.2f)" % [layout, sizes[1], sizes[0]])
	var boxer := BikeModel.new()
	add_child(boxer)
	boxer.build_from(BikeBuild.new({"engine": "boxer_1000"}))
	check(boxer.slot_bounds("engine").size.x > 0.5, "a boxer's cylinders stick out either side (%.2f m wide)" % boxer.slot_bounds("engine").size.x)
	boxer.queue_free()
	var audio := EngineAudio.new()
	for case in [["vtwin", 2], ["parallel", 2], ["inline", 4], ["2stroke", 1]]:
		audio.layout = case[0]
		audio.cylinders = case[1]
		check(audio.firing_angles().size() == case[1], "a %s fires %d times a cycle" % case)
	audio.layout = "vtwin"
	var v: Array = audio.firing_angles()
	check(absf(v[1] - 0.5) > 0.03, "a V-twin's beat is uneven")
	audio.free()


func _test_round5_riding() -> void:
	# Hold a wheelie: weight back and the throttle pinned; the rider keeps it at the balance angle.
	var pitches := []
	var r := await ride({"engine": "four_1000"}, 9.0, func(b, t):
		b.body_shift = -1.0 if t > 1.0 else 0.0
		b.throttle = 0.35 if t < 1.0 else 1.0
		if t > 3.0 and not b.wheels[0]["contact"]:
			pitches.append(rad_to_deg(b.pitch_angle)))
	check(not r["crashed"] and r["front_lifted"], "a big four lifts the front under power and doesn't loop out")
	check(pitches.size() > 120, "the wheelie can be held for a good while (%.1f s)" % (pitches.size() / float(Engine.physics_ticks_per_second)))
	if not pitches.is_empty():
		check(pitches.max() < 60.0, "it stays short of the balance point (max %.0f deg)" % pitches.max())
	await _done(r)
	# A stoppie: hard on the front brake from speed lifts the back without throwing you over the bars.
	var stoppie := [false]
	r = await ride({"engine": "four_1000", "front_caliper": "four_piston_radial", "front_pads": "sintered"}, 9.0, func(b, t):
		if t < 5.0:
			b.throttle = 0.8
		else:
			b.throttle = 0.0
			b.front_brake = 1.0
			b.body_shift = 1.0
			if not b.wheels[1]["contact"] and b.wheels[0]["contact"]:
				stoppie[0] = true)
	check(not r["crashed"], "stamping on the front brake doesn't throw you over the bars")
	check(absf(r["bike"].speed) < 2.0, "and still stops the bike")
	await _done(r)
	# Skids: lock the back wheel at speed and it screeches and leaves a black line.
	var marks_before := SkidMarks.shared(get_tree()).count()
	var screeched := [false]
	r = await ride({}, 9.0, func(b, t):
		if t < 6.0:
			b.throttle = 1.0
		else:
			b.throttle = 0.0
			b.rear_brake = 1.0
			if b.effects.screeching():
				screeched[0] = true)
	check(screeched[0], "locking the back wheel screeches")
	check(SkidMarks.shared(get_tree()).count() > marks_before, "and lays a skid mark (%d strips)" % SkidMarks.shared(get_tree()).count())
	await _done(r)
	# Gear changes: the revs fall to the new gear over the shift instead of jumping, and the
	# engine note drops while the clutch is in.
	var during := []
	r = await ride({}, 4.0, func(b, t):
		b.auto_shift = false
		b.throttle = 1.0
		if absf(t - 3.0) < 0.001:
			b.shift_up()
		if t > 3.0 and t < 3.0 + b.build.shift_time:
			during.append([b.rpm, b.sound_load()]))
	if during.size() > 2:
		check(during[0][0] > during[-1][0] and during[1][1] < 0.5, "shifting up drops the revs smoothly and the note softens (%.0f -> %.0f rpm)" % [during[0][0], during[-1][0]])
	else:
		check(false, "the shift was recorded")
	await _done(r)
	# In the air the revs steer the pitch: gas lifts the nose, closing it drops the nose.
	for gas in [1.0, 0.0]:
		var root := Node3D.new()
		add_child(root)
		var bike := Bike.new()
		bike.setup(BikeBuild.new({}))
		root.add_child(bike)
		bike.place(Vector3(0.0, 200.0, 0.0), 0.0)
		bike.throttle = gas
		for i in 30:
			await get_tree().physics_frame
		var rate := bike.angular_velocity.dot(bike.global_transform.basis.x)
		check(rate > 0.3 if gas > 0.5 else rate < -0.3, "in the air, %s (%.2f rad/s)" % ["gas rotates the bike backwards" if gas > 0.5 else "shutting the throttle drops the nose", rate])
		root.queue_free()
		await get_tree().physics_frame


## In the real shed: set a frame up on the empty bay by aiming at it, spray a part by sweeping
## over it, and ride a bike up a yard ramp.
func _session_round5(main: Node) -> void:
	var w: Walker = main.walker
	w.set_tool("hands")
	# A frame carried to the empty bay.
	var frame := Shed._new_item("steel_backbone", 0.0, 0.0, 0.0)
	Shed._move(frame, "held", Shed.me())
	Shed.changed.emit()
	var bay := Shed.free_bay(Workshop.BAY_COUNT)
	var stand := Workshop.bay_transform(bay).origin
	w.place(Transform3D(Basis(), stand + Vector3(0.0, 0.0, 1.8)))
	await _aim_point(w, stand + Vector3(0.0, 0.0, 0.5))
	check(w.plan.get("action", {}).get("a", "") == "start_build" and w.plan["blocked"] == "",
		"holding a frame over an empty bay offers to set it up on the stand (%s)" % str(w.plan.get("verb", w.target)))
	await _hold_act(main)
	var built := false
	for id in Shed.bikes:
		if Shed.item_on(id, "frame") == frame:
			built = true
	check(built, "and doing it starts a new bike there")
	# Spray a muffler on the floor: holding still covers one patch; sweeping covers it all.
	var pipe := Shed._new_item("stock_muffler", 0.0, 0.0, 0.0)
	Shed._move(pipe, "floor", Transform3D(Basis(Vector3.UP, 0.4), Workshop.CENTER + Vector3(-3.0, 0.0, 12.0)))
	Shed.changed.emit()
	await get_tree().process_frame
	var frame_info: Dictionary = main.workshop.item_frame(pipe)
	check(not frame_info.is_empty(), "the part on the bench has a shape to spray")
	var box: AABB = frame_info["box"]
	var xf: Transform3D = frame_info["xf"]
	var centre: Vector3 = xf * box.get_center()
	w.place(Transform3D(Basis(), Vector3(centre.x, 0.0, centre.z) + (Workshop.CENTER - Vector3(centre.x, 0.0, centre.z)).normalized() * 1.0))
	w.set_tool("spray")
	w.spray_color = 4
	await _aim_point(w, centre)
	check(w.plan.get("coverage", false) and w.plan["blocked"] == "", "the spray can wants sweeping over the part (%s %s)" % [str(w.plan.get("verb", "")), str(w.plan.get("blocked", ""))])
	Input.action_press("act")
	for i in 90:
		await get_tree().physics_frame
	check(w.coverage > 0.0 and w.coverage < Walker.COVER_DONE and Shed.items[pipe]["color"] != Shed.PAINTS[4],
		"spraying one spot only covers part of it (%.0f%%)" % (w.coverage * 100.0))
	# Work over it like a painter: steady horizontal passes across it, a hand's width apart.
	var cam: Camera3D = w.camera
	var rect := Rect2(cam.unproject_position(xf * box.position), Vector2.ZERO)
	for c in 8:
		rect = rect.expand(cam.unproject_position(xf * box.get_endpoint(c)))
	var dist: float = cam.global_position.distance_to(centre)
	var px_per_m: float = get_viewport().get_visible_rect().size.y / (2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5))
	var rows := maxi(2, ceili(rect.size.y / (0.12 * px_per_m)))
	var path: Array[Vector3] = []
	for r in rows:
		var y := rect.position.y + (r + 0.5) * rect.size.y / rows
		var frames := maxi(30, ceili(rect.size.x / px_per_m * 120.0))
		for k in frames:
			var f := float(k) / (frames - 1)
			var x := lerpf(rect.position.x, rect.end.x, f if r % 2 == 0 else 1.0 - f)
			path.append(cam.project_position(Vector2(x, y), dist))
	for p in path:
		var d: Vector3 = p - w.camera.global_position
		w.rotation.y = atan2(-d.x, -d.z)
		w._pitch = 0.0
		w._look(0.0, atan2(d.y, Vector2(d.x, d.z).length()))
		await get_tree().physics_frame
		if Shed.items[pipe]["color"] == Shed.PAINTS[4]:
			break
	Input.action_release("act")
	await get_tree().physics_frame
	check(Shed.items[pipe]["color"] == Shed.PAINTS[4] and Shed.items[pipe].has("paint_quality"),
		"sweeping the can over all of it finishes the paint job (quality %.0f%%)" % (float(Shed.items[pipe].get("paint_quality", 0.0)) * 100.0))
	check(Shed.condition_text(Shed.items[pipe]).contains("Paint job"), "the info panel says how good the paint job is")
	w.set_tool("hands")
	# The yard: a bike ridden at a ramp goes up it.
	var ramp := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "ramp_large":
			ramp = id
			break
	var rxf: Transform3D = Shed.furniture[ramp]["xf"]
	var top := rxf * Vector3(0.0, 3.0, -1.8)
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 4.0, 1)
	var hit: Dictionary = w.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and (hit["position"] as Vector3).y > 1.0 and str((hit["collider"] as Object).get_meta("surface", "")) == "tarmac",
		"the big ramp is solid near its lip (%.2f m up)" % ((hit["position"] as Vector3).y if hit else -1.0))
	var cone := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "cone":
			cone = id
			break
	var cxf: Transform3D = Shed.furniture[cone]["xf"]
	q = PhysicsRayQueryParameters3D.create(cxf.origin + Vector3.UP * 2.0, cxf.origin + Vector3.DOWN * 0.5, 1)
	hit = w.get_world_3d().direct_space_state.intersect_ray(q)
	check(hit.is_empty() or (hit["position"] as Vector3).y < 0.05, "cones don't stop a bike: you ride through them")


## Turns the walker where it stands to look straight at a point, once its eye height has settled.
func _aim_point(w: Walker, at: Vector3) -> void:
	for i in 30:
		await get_tree().physics_frame
	var eye: Vector3 = w.camera.global_position
	var d := at - eye
	w.rotation.y = atan2(-d.x, -d.z)
	w._pitch = 0.0
	w._look(0.0, atan2(d.y, Vector2(d.x, d.z).length()))
	for i in 3:
		await get_tree().physics_frame


func _test_addresses() -> void:
	var cases := {
		"81.159.199.56": ["81.159.199.56", Net.PORT],
		" 81.159.199.56:24680 ": ["81.159.199.56", 24680],
		"81.159.199.56:3000": ["81.159.199.56", 3000],
		"udp://81.159.199.56:24681/": ["81.159.199.56", 24681],
		"myshed.example.com:24680": ["myshed.example.com", 24680],
		"2a00:23c5::1": ["2a00:23c5::1", Net.PORT],
		"[2a00:23c5::1]:24682": ["2a00:23c5::1", 24682],
		"81.159.199.56:port": ["81.159.199.56", Net.PORT],
	}
	for text in cases:
		var got := Net.parse_address(text)
		check(got["host"] == cases[text][0] and got["port"] == cases[text][1],
			"the join box reads '%s' as %s port %d (%s)" % [text, cases[text][0], cases[text][1], str(got)])
	check(Net._is_private("192.168.1.64") and Net._is_private("10.0.0.2") and Net._is_private("172.20.1.1")
		and Net._is_private("100.72.1.1") and not Net._is_private("81.159.199.56") and not Net._is_private("172.32.0.1"),
		"home-network and carrier-shared addresses aren't offered as the internet address")
	Net.internet_status = "closed"
	var text := Net.join_instructions()
	check(text.contains("forward UDP port %d" % Net.PORT), "when the router won't open the port, the menu says how to forward it")
	Net.internet_status = "open"
	Net.external_ip = "81.159.199.56"
	check(Net.join_instructions().contains("81.159.199.56"), "when the router opens the port, the menu shows the internet address")
	Net.internet_status = ""
	Net.external_ip = ""


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
