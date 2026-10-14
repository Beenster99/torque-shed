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
	print("Round 6: horns, ECU, luggage, shop, booth, burnouts")
	_test_round6_parts()
	_test_round6_shed()
	await _test_round6_riding()
	print("Round 7: lights, suspension, landings, tyre widths, paint shop")
	_test_round7_parts()
	await _test_round7_riding()
	print("Sound and radio")
	_test_sounds()
	_test_mp3_decoder()
	await _test_radio_stream()
	print("Co-op addresses")
	_test_addresses()
	print("World")
	await _test_world()
	print("Day and night, tyre smoke")
	await _test_daylight()
	await _test_tyre_smoke()
	print("Game session")
	await _test_session()
	print("Tool models, posters and the water jet")
	await _test_tool_art()
	print("Saving and loading")
	await _test_save_load()
	print("Whiteboard")
	await _test_whiteboard()
	print("Tuning room and dyno")
	await _test_tuning()
	print("XP, levels, tool upgrades and skills")
	_test_progress()
	print("Bike lights, tyres and the tyre changer")
	await _test_bike_lights()
	await _test_tyre_changer()
	await _test_changer_save_load()


const SLICK := {"front_tyre": "race_slick", "rear_tyre": "race_slick"}
const MX := {"fork": "long_travel_mx", "shock": "mono_shock_mx", "front_wheel": "spoked_21", "rear_wheel": "spoked_18",
	"front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx"}


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func _test_catalogue() -> void:
	check(PartsDB.KINDS.size() == 32 and PartsDB.parts.size() >= 170, "catalogue has 32 kinds of part (%d parts)" % PartsDB.parts.size())
	for k in PartsDB.KINDS:
		check(PartsDB.by_kind[k].size() >= 5, "%s has at least five variants (%d)" % [k, PartsDB.by_kind[k].size()])
	var no_colour := []
	for id in PartsDB.parts:
		if not PartsDB.parts[id].has("color"):
			no_colour.append(id)
	check(no_colour.is_empty(), "every part has a colour %s" % str(no_colour))
	check(PartsDB.SLOTS.size() == 38, "a bike has 38 slots, 7 of them on the engine")
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
	for spot in ["bench_0", "bench_2", "bench_1"]:
		Shed.request({"a": "take", "spot": spot})
		Shed.request({"a": "install", "bike": barn, "slot": "frame", "crouched": true})
	# The front tyre goes on at the tyre changer: the front wheel has to come off first.
	var new_tyre := Shed.item_at_spot("bench_3")
	Shed.request({"a": "take", "spot": "bench_3"})
	check(Shed.check(me, {"a": "install", "bike": barn, "slot": "front_wheel"}).contains("tyre changer"),
		"a tyre can't be fitted to a wheel on the bike")
	Shed.request({"a": "place", "spot": "bench_3"})
	var brake := _wheel_to_changer(barn, "front")
	Shed.request({"a": "take", "spot": "bench_3"})
	Shed.request({"a": "tyre_fit", "spot": Shed.changer_spot(), "quality": 0.9})
	_wheel_from_changer(barn, "front", brake)
	check(Shed.item_on(barn, "front_tyre") == new_tyre and Shed.item_on(barn, "rear_tyre") != 0
		and Shed.is_bolted(barn, "front_tyre"), "the front wheel goes back in with its new tyre seated")
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
		if Equipment.FIXED_KINDS.has(k):
			continue   # built into the shed, not sold
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
	# Look at the Rusty Ranger's tank from beside it and unbolt it with the wrench.
	var ranger := _bike_named("Rusty Ranger")
	await _aim_at(main, ranger, "tank")
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
	r = await ride({"engine": "four_1000", "front_caliper": "four_piston_radial", "front_pads": "sintered"}, 10.0, func(b, t):
		if t < 5.0:
			b.throttle = 0.8
		else:
			b.throttle = 0.0
			b.front_brake = 1.0
			b.body_shift = 1.0
			if not b.wheels[1]["contact"] and b.wheels[0]["contact"]:
				stoppie[0] = true)
	check(not r["crashed"], "stamping on the front brake doesn't throw you over the bars")
	check(absf(r["bike"].speed) < 2.0, "and still stops the bike (%.1f m/s)" % r["bike"].speed)
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


func _test_round6_parts() -> void:
	for k in ["horn", "ecu", "panniers", "top_box", "fog_lights"]:
		check(PartsDB.by_kind[k].size() >= (10 if k == "horn" else 5), "the shop has %d %s" % [PartsDB.by_kind[k].size(), k])
		for id in PartsDB.by_kind[k]:
			if PartsDB.spec_line(id) == "":
				check(false, "%s has a spec line" % id)
	# Old bikes, saved before these parts existed, come with the stock horn and none of the extras.
	var old := BikeBuild.new({"engine": "twin_700"})
	check(old.parts["horn"] == "disc_horn" and old.parts["ecu"] == "none" and old.parts["panniers"] == "none",
		"a bike from before gets a stock horn and no ECU or luggage")
	check(not old.horn_tones.is_empty() and old.ecu_features.is_empty() and old.fog_lumens == 0.0, "so it can hoot but has no rider aids or fog lights")
	var loaded := BikeBuild.new({"engine": "twin_700", "panniers": "aluminium_boxes", "top_box": "top_box_45", "fog_lights": "rally_lamps",
		"ecu": "race_ecu", "horn": "musical_horn"})
	check(loaded.cda > old.cda and loaded.bike_mass > old.bike_mass and loaded.luggage_litres > 100.0,
		"luggage adds drag, weight and %d litres of space" % roundi(loaded.luggage_litres))
	check(loaded.fog_lumens > 1000.0 and loaded.has_aid("traction") and loaded.has_aid("abs") and loaded.has_aid("anti_wheelie"),
		"fog lamps light up and the race ECU brings traction control, ABS and anti-wheelie")
	check(loaded.peak_torque > old.peak_torque and loaded.redline > old.redline, "and a sharper map")
	check(loaded.horn_tones.size() == 5 and loaded.horn_style == "melody", "the musical horn has its five trumpets")
	# Every new part draws on the bike.
	var model := BikeModel.new()
	add_child(model)
	model.build_from(loaded)
	for slot in ["horn", "ecu", "panniers", "top_box", "fog_lights"]:
		check(model.slot_bounds(slot).size.length() > 0.02, "the %s is drawn on the bike" % slot)
	check(model.fog_positions().size() == 2, "rally lamps sit either side of the fork")
	model.queue_free()
	# The shop: three aisles and a search box.
	check(PartsComputer.section_of("eq:ramp") == "outdoors" and PartsComputer.section_of("eq:seat") == "shed"
		and PartsComputer.section_of("horn") == "bike" and PartsComputer.section_of("petrol") == "bike", "the shop is split into shed, bike and outdoors")
	var horns := PartsComputer.search("horn")
	check(horns.size() >= 10, "searching 'horn' finds every horn (%d)" % horns.size())
	var vtwins := PartsComputer.search("v-twin 1200")
	check(vtwins.size() >= 1 and str(vtwins[0]["id"]) == "vtwin_1200", "searching by words finds the 1200 V-twin")
	check(PartsComputer.search("zzzz nothing").is_empty(), "a search for nothing finds nothing")
	var pc := PartsComputer.new()
	add_child(pc)
	pc._search.text = "sofa"
	pc._refresh_list()
	check(pc._kind == "eq:seat", "picking a search result shows its aisle and kind")
	pc.queue_free()
	# Fluid containers show how full they are.
	var full := BikeModel.fluid_display("semi_10w40", 1.0)
	var half := BikeModel.fluid_display("semi_10w40", 0.5)
	check(full.get_child_count() > 3 and half.get_child_count() > 3, "a bottle has the liquid inside it, at its level")
	full.free()
	half.free()
	check(Stopwatch.format(62.37) == "1:02.37" and Stopwatch.format(9.5) == "9.50", "the stopwatch reads minutes, seconds and hundredths")
	var sw := Stopwatch.new()
	sw.start_stop()
	sw.lap_or_reset()
	sw.start_stop()
	check(not sw.running and sw.laps.size() == 1 and sw.showing(), "it starts, laps and stops")
	sw.lap_or_reset()
	check(not sw.showing(), "and resets to zero")


func _test_round6_shed() -> void:
	Shed.start_new("Tester", 6)
	var me := Shed.me()
	var bike: int = Shed.bikes.keys()[0]
	Shed.request({"a": "rename_bike", "bike": bike, "name": "  The Beast  "})
	check(str(Shed.bikes[bike]["name"]) == "The Beast", "bikes can be named")
	check(Shed.check(me, {"a": "rename_bike", "bike": bike, "name": "   "}) != "", "but not with nothing")
	Shed.request({"a": "door", "open": false})
	Shed.request({"a": "lights", "on": false})
	check(not Shed.door_open and not Shed.lights_on, "the roller door comes down and the lights go off")
	check(Shed._snapshot()["door"] == false and Shed._snapshot()["lights"] == false, "and everyone in the shed sees it")
	Shed.request({"a": "door", "open": true})
	Shed.request({"a": "lights", "on": true})
	# A ping goes out to everyone with what it was.
	var got := []
	var on_ping := func(peer, d): got.append([peer, d])
	Shed.pinged.connect(on_ping)
	Shed.request({"a": "ping", "at": Vector3(1, 2, 3), "what": "Front brake caliper", "item": 0})
	Shed.pinged.disconnect(on_ping)
	check(got.size() == 1 and got[0][1]["what"] == "Front brake caliper" and got[0][1]["name"] == "Tester", "a ping is sent round with who and what")
	# The paint booth: built into the paint shop, parts hang on its hooks and the spray gun only
	# works there.
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	check(booth != 0 and Shed.furniture_spots(booth).size() == 6, "the shed has a built-in paint booth with six hooks")
	check(Shed.furniture[booth]["xf"] == Workshop.BOOTH_XF, "in the paint shop lean-to")
	check(Shed.check(me, {"a": "grab", "furniture": booth}) != "", "it can't be moved")
	check(Shed.check(me, {"a": "order_furniture", "model": "booth_compact"}) != "", "and booths aren't sold")
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0)
	Shed.items[tank]["at"] = "floor"
	Shed.items[tank]["ref"] = Transform3D(Basis(), Workshop.CENTER)
	var paint := {"a": "paint", "item": tank, "color": 3, "finish": "gloss", "gun": true, "quality": 0.8}
	check(Shed.check(me, paint).contains("booth"), "the spray gun needs the part hung in the booth")
	Shed.request({"a": "take", "item": tank})
	var hook: String = Shed.furniture_spots(booth)[0]
	Shed.request({"a": "place", "spot": hook})
	check(Shed.item_at_spot(hook) == tank and Shed.spot_role(hook) == "booth", "the tank hangs on a hook")
	check(Shed.check(me, paint) == "", "and can be sprayed there")
	Shed.request(paint)
	check(float(Shed.items[tank]["paint_quality"]) > 0.8, "the booth gives a cleaner finish than the gun alone (%.2f)" % float(Shed.items[tank]["paint_quality"]))


func _test_round6_riding() -> void:
	# Burnout: front brake on, throttle pinned, standing still. The back tyre spins and smokes.
	var spun := [0.0, 0.0]
	var r := await ride({"engine": "twin_700"}, 4.0, func(b, t):
		b.front_brake = 1.0
		b.throttle = 1.0 if t > 0.5 else 0.0
		if t > 2.0:
			spun[0] = maxf(spun[0], b.wheels[1]["omega"] * b.build.rear_radius - absf(b.speed))
			spun[1] = maxf(spun[1], b.burnout))
	var bike: Bike = r["bike"]
	check(not r["crashed"] and absf(bike.speed) < 1.5, "a burnout holds the bike on the spot (%.1f m/s)" % bike.speed)
	check(spun[0] > 6.0 and spun[1] > 0.5, "while the back tyre spins up (%.1f m/s faster than the bike, burnout %.2f)" % spun)
	check(bike.wheels[1]["slip"] > Bike.SKID_SLIP, "and it squeals and marks the road")
	await _done(r)
	# The front brake slows the wheel hard but never locks it.
	var worst := [1.0]
	r = await ride({}, 9.0, func(b, t):
		if t < 6.0:
			b.throttle = 1.0
		else:
			b.throttle = 0.0
			b.front_brake = 1.0
			if b.speed > 4.0 and b.wheels[0]["contact"]:
				worst[0] = minf(worst[0], b.wheels[0]["omega"] * b.build.front_radius / b.speed))
	check(worst[0] > 0.8, "the front wheel keeps turning under full front brake (%.0f%% of road speed at worst)" % (worst[0] * 100.0))
	check(absf(r["bike"].speed) < 3.0, "and still pulls the bike up (%.1f m/s)" % r["bike"].speed)
	await _done(r)
	# Paddling backwards: stopped, hold the front brake and the rider walks it back.
	r = await ride({}, 4.0, func(b, t):
		b.front_brake = 1.0 if t > 0.3 else 0.0
		b.lean_input = 0.6 if t > 2.0 else 0.0)
	bike = r["bike"]
	check(bike.paddling and bike.speed < -0.5, "holding the front brake at a standstill paddles it backwards (%.1f m/s)" % bike.speed)
	check(not r["crashed"] and absf(rad_to_deg(bike.steer)) > 5.0, "steering with the bars as it goes")
	await _done(r)
	# Anti-wheelie: weight back and full gas on a big four with the race ECU keeps the front down.
	var pitch := [0.0]
	r = await ride({"engine": "four_1000", "ecu": "race_ecu"}, 7.0, func(b, t):
		b.body_shift = -1.0
		b.throttle = 1.0 if t > 0.5 else 0.0
		pitch[0] = maxf(pitch[0], rad_to_deg(b.pitch_angle)))
	check(not r["crashed"] and pitch[0] < 15.0, "the ECU's anti-wheelie keeps it near level (%.0f deg)" % pitch[0])
	await _done(r)
	# The horn sounds while held, and goes out to the other players.
	r = await ride({"horn": "air_horn"}, 0.5, func(b, _t): b.horn = true)
	bike = r["bike"]
	check(bike.horn_audio.pressed and bike.horn_audio.has_horn(), "the horn sounds while the button's held")
	var st := bike.get_net_state()
	check(st.size() >= 24 and st[21] > 0.5, "and the other players hear it")
	await _done(r)
	# Engine notes: a little 50 and a big 1200 are synthesised differently.
	var small := EngineAudio.new()
	small.displacement = 50.0
	var big := EngineAudio.new()
	big.displacement = 1200.0
	add_child(small)
	add_child(big)
	await get_tree().process_frame
	check(is_instance_valid(small) and is_instance_valid(big), "engine notes run for any size of engine")
	small.queue_free()
	big.queue_free()


func _test_tool_art() -> void:
	for which in ["wrench", "brush", "repair", "spray", "lance", "gun", "stopwatch"]:
		var t := ToolModels.make(which, Color(0.2, 0.5, 0.9))
		add_child(t)
		var meshes := t.find_children("*", "MeshInstance3D", true, false)
		var shadowless := true
		for mi: MeshInstance3D in meshes:
			shadowless = shadowless and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		check(meshes.size() >= 8 and shadowless, "%s model builds from %d shadowless meshes" % [which, meshes.size()])
		t.queue_free()
	check(Walker.make_tool_mesh("hands").get_child_count() == 0, "bare hands draw nothing")
	var lance := ToolModels.make("lance")
	check(lance.has_meta("nozzle") and (lance.get_meta("nozzle") as Vector3).is_equal_approx(Vector3(0, 0, -0.6)), "lance nozzle sits where the jet goes")
	var gun := ToolModels.make("gun")
	check(gun.has_meta("nozzle") and (gun.get_meta("nozzle") as Vector3).distance_to(Vector3(0, 0.02, -0.12)) < 0.01, "paint gun nozzle at the front")
	var watch := ToolModels.make("stopwatch")
	ToolModels.set_hand_seconds(watch, 15.0)
	var hand := watch.get_node_or_null("Hand") as Node3D
	check(hand != null and is_equal_approx(hand.rotation.z, -PI * 0.5), "stopwatch hand turns to quarter past")
	lance.free()
	gun.free()
	watch.free()
	var jet := Walker.make_jet()
	add_child(jet)
	jet.emitting = true
	for i in 3:   # the mist and core follow on the jet's next _process
		await get_tree().process_frame
	var mist := jet.get_node_or_null("Mist") as CPUParticles3D
	check(jet is WaterSpray and mist != null and mist.emitting and (jet.get_node("Core") as Node3D).visible, "water jet emits with its mist and core")
	jet.queue_free()
	for model in Equipment.MODELS:
		if Equipment.kind_of(model) != "poster":
			continue
		var size: Vector3 = Equipment.get_model(model)["size"]
		var art := PosterArt.make(model, size)
		var quad := art.mesh as QuadMesh
		check(quad != null and quad.size.is_equal_approx(Vector2(size.x, size.y)) and absf(art.position.z) <= 0.003
			and art.material_override != null, "%s poster is one flat sheet on the wall" % model)
		art.free()


## Time of day: the sun sets, darkness rises, the moon and yard lamps take over, the clock
## settings persist, and a client follows the host's clock.
func _test_daylight() -> void:
	var saved := [Settings.day_night_cycle, Settings.day_length, Settings.time_of_day]
	Settings.day_night_cycle = false
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var dl := Daylight.new()
	add_child(dl)
	dl.setup(env, sun)
	check(Daylight.current == dl and get_tree().get_first_node_in_group("daylight") == dl, "the daylight node is findable")
	var lamp := OmniLight3D.new()
	lamp.set_meta("night_energy", 3.0)
	lamp.add_to_group(Daylight.NIGHT_LIGHTS)
	add_child(lamp)
	dl.set_time(12.0)
	var noon_dark := World.darkness()
	check(is_equal_approx(World.time_of_day(), 12.0) and noon_dark < 0.05, "noon is bright (darkness %.2f)" % noon_dark)
	check(sun.visible and sun.light_energy > 1.0 and not lamp.visible, "the sun is up at noon and lamps are off")
	check(sun.global_transform.basis.z.y > 0.5, "the noon sun shines down from high in the sky")
	dl.set_time(0.0)
	check(World.darkness() > 0.95 and World.darkness() > noon_dark, "midnight is dark (darkness %.2f)" % World.darkness())
	check(not sun.visible and dl._moon.visible and dl._moon.light_energy > 0.05, "at midnight the moon lights the yard")
	check(lamp.visible and is_equal_approx(lamp.light_energy, 3.0), "lamps in the night_lights group switch on at night")
	dl.set_time(18.0)
	check(sun.light_color.b < 0.6 and World.darkness() > 0.05 and World.darkness() < 0.7, "dusk is warm and half dark (%.2f)" % World.darkness())
	check(Daylight.sun_direction(6.0).x > 0.9 and Daylight.sun_direction(18.0).x < -0.9, "the sun rises in the east and sets in the west")
	check(Daylight.clock_text(18.75) == "18:45" and Daylight.clock_text(24.0) == "00:00", "the clock reads hours and minutes")
	# The cycle runs at the chosen day length.
	Settings.day_night_cycle = true
	Settings.day_length = 10
	dl.set_time(10.0)
	for i in 120:
		await get_tree().process_frame
	var ran := dl.hours - 10.0
	check(ran > 0.03 and ran < 0.05, "a 10 minute day moves the clock 0.04 h a second (%.3f h)" % ran)
	check(absf(Settings.time_of_day - dl.hours) < 0.001, "the settings follow the clock so it carries on next time")
	# Persisted like the other settings.
	Settings.day_length = 40
	Settings.time_of_day = 21.5
	Settings.save_settings()
	Settings.day_length = 20
	Settings.time_of_day = 3.0
	Settings.load_settings()
	check(Settings.day_length == 40 and is_equal_approx(Settings.time_of_day, 21.5) and Settings.day_night_cycle,
		"day/night settings persist")
	# Solo, a message from a "host" is ignored.
	Settings.day_night_cycle = false
	dl.set_time(8.0)
	Net.time_received.emit(20.0, 0.0)
	check(is_equal_approx(dl.hours, 8.0), "solo, the local clock rules")
	Settings.day_night_cycle = saved[0]
	Settings.day_length = saved[1]
	Settings.time_of_day = saved[2]
	Settings.save_settings()
	lamp.queue_free()
	dl.queue_free()
	sun.queue_free()
	await get_tree().process_frame
	check(Daylight.current == null and is_equal_approx(World.time_of_day(), 12.0), "with no world it reads noon")


func _test_tyre_smoke() -> void:
	var fx := BikeEffects.new()
	add_child(fx)
	fx.setup(Vector3(0.2, 0.4, 0.9), Vector3(0.0, -0.3, 0.7), Vector3(0.0, 0.9, -0.8), 900.0)
	check(not fx.tyre_smoke_emitting(), "no tyre smoke to start with")
	for i in 10:
		fx.set_tyre_smoke(1.0, Vector3(0.0, -0.3, 0.7))
		await get_tree().process_frame
	check(fx.tyre_smoke_emitting(), "a burnout makes tyre smoke")
	for i in 10:
		fx.set_tyre_smoke(0.0, Vector3(0.0, -0.3, 0.7))
		await get_tree().process_frame
	check(not fx.tyre_smoke_emitting(), "the smoke stops when the tyre grips again")
	var tex := BikeEffects.puff_texture()
	check(tex.get_width() == BikeEffects.PUFF_FRAME * 2, "smoke puffs come from a shared atlas texture")
	var fx2 := BikeEffects.new()
	add_child(fx2)
	fx2.set_tyre_smoke(0.5, Vector3.ZERO)
	check(BikeEffects.puff_texture() == tex, "the atlas is made once")
	fx.queue_free()
	fx2.queue_free()
	await get_tree().process_frame


func _test_round7_riding() -> void:
	# A jump landing: dropped from 2.5 m at speed, the suspension soaks it up instead of bouncing.
	var log := {"dropped": false, "flying": false, "landed": false, "max_up": 0.0, "impact": 0.0, "air_after": 0, "max_comp": 0.0}
	var r := await ride({}, 6.0, func(b, t):
		b.throttle = 0.3
		if t >= 2.0 and not log["dropped"]:
			log["dropped"] = true
			b.global_position.y += 2.5
		if log["dropped"]:
			var both: bool = b.wheels[0]["contact"] and b.wheels[1]["contact"]
			var any: bool = b.wheels[0]["contact"] or b.wheels[1]["contact"]
			if not log["flying"]:
				log["flying"] = not any
			elif not log["landed"] and any:
				log["landed"] = true
				log["impact"] = -b.linear_velocity.y
			elif log["landed"]:
				log["max_up"] = maxf(log["max_up"], b.linear_velocity.y)
				log["max_comp"] = maxf(log["max_comp"], maxf(b.wheels[0]["compression"] / b.wheels[0]["travel"], b.wheels[1]["compression"] / b.wheels[1]["travel"]))
				if not any:
					log["air_after"] += 1)
	print("    landing: impact %.1f m/s, rebound %.2f m/s, %d frames airborne after, max travel used %.0f%%" % [log["impact"], log["max_up"], log["air_after"], log["max_comp"] * 100.0])
	check(not r["crashed"] and log["landed"], "a bike dropped from 2.5 m lands on its wheels")
	check(log["max_comp"] > 0.6, "and uses most of its suspension travel (%.0f%%)" % (log["max_comp"] * 100.0))
	check(log["max_up"] < 0.25 * log["impact"], "without bouncing back up (%.2f m/s up after a %.1f m/s landing)" % [log["max_up"], log["impact"]])
	check(log["air_after"] < 6, "and the wheels stay on the ground (%d frames in the air after landing)" % log["air_after"])
	await _done(r)


func _test_round7_parts() -> void:
	check(PartsDB.by_kind["tyre"].size() >= 30, "tyres come in lots of widths (%d)" % PartsDB.by_kind["tyre"].size())
	var widths := {}
	for id in PartsDB.by_kind["tyre"]:
		widths[int(PartsDB.parts[id]["width"])] = true
	check(widths.size() >= 10, "from narrow to fat (%d widths)" % widths.size())
	for id in PartsDB.by_kind["wheel"]:
		check(PartsDB.parts[id].has("rim_width"), "the %s has a rim width" % id)
	var narrow := BikeBuild.new({"rear_tyre": "sport_road_120"})
	var fat := BikeBuild.new({"rear_tyre": "sport_road_200"})
	check(fat.grip_rear["tarmac"] > narrow.grip_rear["tarmac"], "a fatter rear tyre grips tarmac better (%.3f vs %.3f)" % [fat.grip_rear["tarmac"], narrow.grip_rear["tarmac"]])
	check(fat.rear_radius > narrow.rear_radius, "and is taller")
	var mx_narrow := BikeBuild.new({"rear_tyre": "knobbly_mx_90", "rear_wheel": "spoked_18"})
	var mx_wide := BikeBuild.new({"rear_tyre": "knobbly_mx_140", "rear_wheel": "spoked_18"})
	check(mx_narrow.grip_rear["dirt"] > mx_wide.grip_rear["dirt"], "a narrow knobbly digs into dirt better")
	var wrong := BikeBuild.new({"rear_wheel": "spoked_21", "rear_tyre": "sport_road_200"})
	check(wrong.notes.any(func(n): return n.contains("too wide")), "a fat tyre on a skinny rim is flagged")
	check(BikeBuild.new().notes.all(func(n): return not n.contains("rim")), "the stock bike's tyres suit its rims")
	for b in Shed.bikes:
		var notes: Array = Shed.build_of(b).notes
		check(notes.all(func(n): return not n.contains("rim")), "%s's tyres suit its rims" % Shed.bikes[b]["name"])
	var quick := BikeBuild.new({"front_tyre": "sport_road_120"})
	check(quick.steer_rate > BikeBuild.new({"front_tyre": "sport_road_200"}).steer_rate, "a narrow front turns in quicker")


## The shed is saved and comes back as it was: parts, names, paint, furniture, the clock, where
## you stood and a bike left out on the road. Uses its own slot so a real save is never touched.
func _test_save_load() -> void:
	var kept := [Settings.time_of_day, Settings.day_night_cycle, Settings.day_length]
	SaveGame.slot_override = "test_save_load"
	var slot := SaveGame.active_slot()
	SaveGame.delete_slot(slot)
	# Types and int keys survive the file.
	var sample := {"version": SaveGame.VERSION, "shed": {"items": {7: {"ref": Transform3D(Basis(Vector3.UP, 0.5), Vector3(1, 2, 3)),
		"color": Color(0.1, 0.2, 0.3)}}, "next": 8}}
	check(SaveGame.write(slot, sample) == OK, "a save file is written")
	var back := SaveGame.read(slot)
	check(back.get("shed", {}).get("items", {}).has(7) and back["shed"]["items"][7]["ref"] is Transform3D
		and back["shed"]["items"][7]["ref"].origin == Vector3(1, 2, 3) and back["shed"]["items"][7]["color"] == Color(0.1, 0.2, 0.3),
		"transforms, colours and int keys come back from the file")
	check(not FileAccess.file_exists(SaveGame.path_of(slot) + ".tmp"), "the temp file is swapped in")
	SaveGame.delete_slot(slot)
	check(not SaveGame.can_continue(), "with no save there's nothing to continue")

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	check(Shed.bikes.size() == 3 and main.walker != null, "with no save a new shed opens")
	# Ride Old Faithful out onto the road loop and leave it there.
	var faithful := _bike_named("Old Faithful")
	Shed.request({"a": "mount", "bike": faithful})
	await get_tree().physics_frame
	check(main.bike != null, "you get on Old Faithful")
	var road: Transform3D = main.world.road_transform(0.3)
	main.bike.place(road.origin, road.basis.get_euler().y)
	for i in 90:
		await get_tree().physics_frame
	main._get_off()
	await get_tree().physics_frame
	var parked: Transform3D = Shed.bikes[faithful]["xf"]
	check(main.bike == null and parked.origin.distance_to(road.origin) < 3.0, "Old Faithful is left out on the road")
	# Change some things.
	var ranger := _bike_named("Rusty Ranger")
	Shed.request({"a": "rename_bike", "bike": ranger, "name": "Saved Ranger"})
	var tank := Shed.item_on(ranger, "tank")
	Shed.items[tank]["color"] = Shed.PAINTS[3]
	Shed.items[tank]["finish"] = "chrome"
	var plugs := _order("iridium_plugs")
	var plug_xf := Transform3D(Basis(Vector3.UP, 1.0), Workshop.CENTER + Vector3(0.7, 0.0, 1.3))
	Shed.items[plugs]["ref"] = plug_xf
	var washer := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "washer":
			washer = id
	var washer_xf := Transform3D(Basis(Vector3.UP, 0.3), Workshop.CENTER + Vector3(-2.0, 0.0, 0.5))
	Shed.request({"a": "grab", "furniture": washer})
	Shed.request({"a": "release", "furniture": washer, "xf": washer_xf})
	Shed.request({"a": "door", "open": false})
	Shed.crew[Shed.me()]["fitted"] = 7
	var bench := Shed.item_at_spot("bench_0")
	Shed.request({"a": "take", "spot": "bench_0"})
	Daylight.current.set_time(21.5)
	var stand_at := Transform3D(Basis(Vector3.UP, 0.8), Workshop.CENTER + Vector3(1.0, 0.0, -1.0))
	main.walker.place(stand_at)
	var next_id: int = Shed._next_id
	check(main.saver.save_now(), "the host saves the shed")
	check(FileAccess.file_exists(SaveGame.path_of(slot)) and SaveGame.last_saved > 0 and SaveGame.status_text().begins_with("Saved"),
		"the save file is there and the Esc menu says it just saved (%s)" % SaveGame.status_text())
	main._leave()
	check(SaveGame.can_continue() and SaveGame.describe(SaveGame.read(slot)).begins_with("3 bikes, 21:30"),
		"the title menu offers to continue it (%s)" % SaveGame.describe(SaveGame.read(slot)))
	# A fresh shed in between, then continue the saved one.
	Shed.start_new("Someone else", 99)
	Daylight.current.set_time(8.0)
	check(_bike_named("Saved Ranger") == 0, "a new shed forgets the changes")
	Shed.stop()
	main._start_session()
	await get_tree().physics_frame
	check(_bike_named("Saved Ranger") == ranger, "the renamed bike comes back")
	check(Shed.items[tank]["color"] == Shed.PAINTS[3] and Shed.items[tank]["finish"] == "chrome", "its tank keeps its new paint")
	check(Shed.items.has(plugs) and Shed.items[plugs]["at"] == "floor" and Shed.items[plugs]["ref"] == plug_xf,
		"a part put down on the floor is where it was left")
	check(Shed.furniture[washer]["xf"] == washer_xf and Shed.furniture[washer]["mover"] == 0, "moved furniture stays moved")
	check(Shed.bikes[faithful]["xf"].origin.distance_to(parked.origin) < 0.01 and Shed.bikes[faithful]["stand"] == "side",
		"the bike left on the road is still there on its stand")
	check(not Shed.door_open, "the roller door is still down")
	check(absf(Daylight.time_of_day() - 21.5) < 0.05, "the clock carries on from 21:30 (%s)" % Daylight.clock_text(Daylight.time_of_day()))
	check(main.walker.global_position.distance_to(stand_at.origin) < 0.3 and absf(wrapf(main.walker.yaw() - 0.8, -PI, PI)) < 0.01,
		"you're back where you stood, facing the same way")
	check(Shed.held_by(Shed.me()) == 0 and Shed.items[bench]["at"] == "spot", "nobody holds anything after loading")
	check(Shed.crew.size() == 1 and Shed.crew.has(Shed.me()) and int(Shed.crew[Shed.me()]["fitted"]) == 7,
		"the crew is who's here, with their numbers kept")
	check(Shed._next_id >= next_id, "new ids carry on past the saved ones")
	Shed.request({"a": "order_part", "part": "copper_plugs"})
	var newest := 0
	for id in Shed.items:
		newest = maxi(newest, id)
	check(newest >= next_id and Shed.items[newest]["part"] == "copper_plugs", "a part ordered after loading gets a fresh id")
	# Saved while riding: you're back on the bike, out where you were.
	Shed.request({"a": "mount", "bike": faithful})
	await get_tree().physics_frame
	var far: Transform3D = main.world.road_transform(0.6)
	main.bike.place(far.origin, far.basis.get_euler().y)
	for i in 60:
		await get_tree().physics_frame
	var ride_at: Vector3 = main.bike.global_position
	main._leave()
	var ridden: Dictionary = SaveGame.read(slot)
	check(ridden["shed"]["bikes"][faithful]["xf"].origin.distance_to(ride_at) < 2.0
		and int(ridden["players"][Settings.player_name]["riding"]) == faithful,
		"a save while riding keeps the bike where it is and who was on it")
	main._start_session()
	await get_tree().physics_frame
	check(Shed.riding(Shed.me()) == faithful and main.bike != null and main.bike.global_position.distance_to(ride_at) < 2.5,
		"loading puts you back on the bike out on the road")
	main._leave()
	# A damaged save falls back to a new shed.
	SaveGame.delete_slot(slot)
	var f := FileAccess.open(SaveGame.path_of(slot), FileAccess.WRITE)
	f.store_string("{ \"version\": 1, \"shed\": { not a shed")
	f.close()
	main._start_session()
	check(Shed.bikes.size() == 3 and _bike_named("Saved Ranger") == 0 and main.in_session, "a damaged save opens a new shed instead")
	check(FileAccess.file_exists(SaveGame.path_of(slot) + ".broken"), "the damaged file is kept to one side")
	main._leave()
	# A damaged newest save with a good one behind it uses the good one.
	main._start_session()
	main.saver.save_now()
	main.saver.save_now()
	f = FileAccess.open(SaveGame.path_of(slot), FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	check(SaveGame.read(slot).has("shed"), "a damaged save falls back to the one before it")
	main._leave()
	SaveGame.delete_slot(slot)
	main.menu.new_shed = false
	main._start_session()
	check(Shed.bikes.size() == 3, "a missing save opens a new shed")
	main._leave()
	main.queue_free()
	await get_tree().process_frame
	SaveGame.delete_slot(slot)
	SaveGame.slot_override = ""
	SaveGame.last_saved = 0
	Settings.time_of_day = kept[0]
	Settings.day_night_cycle = kept[1]
	Settings.day_length = kept[2]


func _test_whiteboard() -> void:
	Shed.start_new("Tester", 9)
	var me := Shed.me()
	check(Shed.board.has("marks") and Shed.board["marks"].is_empty(), "the whiteboard starts clean")
	# A blue line drawn in two goes, as it goes out while you draw, then finished.
	var line := PackedVector2Array()
	for i in 11:
		line.append(Vector2(100.0 + i * 20.0, 100.0))
	Shed.board_request({"a": "board_draw", "id": 101, "c": 1, "w": 6.0, "from": 0, "pts": line.slice(0, 5)})
	var marks: Array = Shed.board["marks"]
	check(marks.size() == 1 and marks[0]["by"] == "Tester" and int(marks[0]["peer"]) == me, "a stroke goes into the shed state with its author")
	Shed.board_request({"a": "board_draw", "id": 101, "c": 1, "w": 6.0, "from": 5, "pts": line.slice(5)})
	check((marks[0]["pts"] as PackedVector2Array).size() == 11, "more of the stroke adds on to it (%d points)" % (marks[0]["pts"] as PackedVector2Array).size())
	Shed.board_request({"a": "board_draw", "id": 101, "c": 1, "w": 6.0, "from": 0, "pts": BoardData.simplify(line), "done": true})
	check((marks[0]["pts"] as PackedVector2Array).size() == 2, "the finished straight line is simplified to its two ends")
	check(BoardData.ink_at(Shed.board, Vector2(210, 101)) == 1 and BoardData.ink_at(Shed.board, Vector2(210, 140)) == -1,
		"the line is blue ink along where it was drawn")
	# Rub all of it out and it's gone from the board, eraser and all.
	Shed.board_request({"a": "board_draw", "id": 102, "c": BoardData.ERASER, "from": 0, "done": true,
		"pts": PackedVector2Array([Vector2(80, 100), Vector2(330, 100)])})
	check(BoardData.ink_at(Shed.board, Vector2(210, 100)) == -1, "the eraser rubs the ink out")
	check(Shed.board["marks"].is_empty(), "a mark rubbed out completely is dropped, with the eraser that rubbed it")
	# Rub out half of a line: the rest stays.
	Shed.board_request({"a": "board_draw", "id": 103, "c": 2, "w": 11.0, "from": 0, "done": true,
		"pts": PackedVector2Array([Vector2(100, 300), Vector2(500, 300)])})
	Shed.board_request({"a": "board_draw", "id": 104, "c": BoardData.ERASER, "from": 0, "done": true,
		"pts": PackedVector2Array([Vector2(90, 300), Vector2(260, 300)])})
	check(BoardData.ink_at(Shed.board, Vector2(150, 300)) == -1 and BoardData.ink_at(Shed.board, Vector2(400, 300)) == 2,
		"rubbing out half a line leaves the other half")
	check(Shed.board["marks"].size() == 2, "a half rubbed out line and its eraser stay")
	# Typed text, for lists.
	Shed.board_request({"a": "board_text", "id": 105, "c": 3, "s": 38, "at": Vector2(600, 80), "text": "  1. Fit the new chain  "})
	var text: Dictionary = Shed.board["marks"][-1]
	check(text.get("text", "") == "1. Fit the new chain" and text["by"] == "Tester" and text["at"] == Vector2(600, 80),
		"a line of text is stored where it was put, by who wrote it")
	check(BoardData.ink_at(Shed.board, Vector2(620, 100)) == 3, "the text shows in its colour")
	Shed.board_request({"a": "board_text", "id": 106, "c": 0, "at": Vector2(600, 80), "text": "   "})
	check(BoardData.find(Shed.board, 106) < 0, "blank text isn't put up")
	# Somebody else's marks: they can't add to yours, and undo only takes back your own.
	Shed._apply(77, {"a": "board_draw", "id": 105, "c": 0, "w": 3.0, "from": 0, "pts": PackedVector2Array([Vector2(1, 1)])})
	Shed._apply(77, {"a": "board_draw", "id": 201, "c": 4, "w": 3.0, "from": 0, "done": true,
		"pts": PackedVector2Array([Vector2(700, 500), Vector2(800, 520)])})
	check(BoardData.find(Shed.board, 201) >= 0 and Shed.board["marks"][-1]["by"] == "Someone", "another player's stroke goes up as theirs")
	check(not Shed.board["marks"][BoardData.find(Shed.board, 105)].has("pts"), "nobody can draw onto someone else's mark")
	Shed.board_request({"a": "board_undo"})
	check(BoardData.find(Shed.board, 105) < 0 and BoardData.find(Shed.board, 201) >= 0, "undo takes back your own last mark, not theirs")
	# The board goes out whole in the snapshot that players joining (and saves) get, but not in
	# the regular syncs.
	var snap: Dictionary = bytes_to_var(var_to_bytes(Shed._snapshot()))
	check(not Shed._snapshot(false).has("board"), "the regular syncs leave the board out")
	var count: int = Shed.board["marks"].size()
	Shed._sync(Shed._snapshot(false))
	check(Shed.board["marks"].size() == count, "a regular sync keeps the board as it is")
	Shed.board = BoardData.empty()
	Shed._sync(snap)
	check(Shed.board["marks"].size() == count and BoardData.ink_at(Shed.board, Vector2(400, 300)) == 2,
		"the snapshot round trip brings every mark back (%d)" % Shed.board["marks"].size())
	# Bad requests are ignored or tidied up.
	Shed.board_request({"a": "board_draw", "id": 300, "c": 0, "pts": PackedVector2Array()})
	Shed.board_request({"a": "board_draw", "id": 0, "c": 0, "pts": PackedVector2Array([Vector2(5, 5)])})
	check(BoardData.find(Shed.board, 300) < 0 and Shed.board["marks"].size() == count, "empty or unnamed strokes are ignored")
	Shed.board_request({"a": "board_draw", "id": 301, "c": 99, "w": 999.0, "from": 0, "pts": PackedVector2Array([Vector2(-50, 9000)])})
	var odd: Dictionary = Shed.board["marks"][-1]
	check(int(odd["c"]) < BoardData.COLORS.size() and float(odd["w"]) <= 40.0 and (odd["pts"] as PackedVector2Array)[0] == Vector2(0, 600),
		"colours, widths and points are kept on the board")
	# It can't fill up for ever: the oldest marks go first.
	for i in BoardData.MAX_MARKS + 20:
		Shed.board_request({"a": "board_draw", "id": 1000 + i, "c": i % 6, "w": 3.0, "from": 0, "done": true,
			"pts": PackedVector2Array([Vector2(i % 1200, 50), Vector2(i % 1200, 60)])})
	check(Shed.board["marks"].size() <= BoardData.MAX_MARKS and BoardData.find(Shed.board, 1000 + BoardData.MAX_MARKS + 19) >= 0,
		"a full board drops its oldest marks (%d)" % Shed.board["marks"].size())
	# Clean the whole board.
	Shed.board_request({"a": "board_clear"})
	check(Shed.board["marks"].is_empty(), "wiping the board cleans it all off")
	# On the wall in the real game: walk up to it, look at it and draw with the mouse.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var board: Whiteboard = get_tree().get_first_node_in_group("whiteboard")
	check(board != null, "the whiteboard hangs in the shed")
	var face: Vector3 = board.global_position
	w.place(Transform3D(Basis(), Vector3(face.x, 0.0, face.z - 1.4)))
	w.rotation.y = PI
	w._pitch = 0.0
	w._look(0.0, -atan2(Walker.EYE - face.y, 1.4))
	for i in 5:
		await get_tree().physics_frame
	check(w.target.get("kind", "") == "board", "the crosshair finds the whiteboard (%s)" % str(w.target))
	check(w.info.begins_with("Whiteboard") and w.plan.is_empty(), "the side panel says how to use it")
	check(board.aim(w).distance_to(BoardData.PX * 0.5) < 30.0, "looking at the middle aims at the middle of the board (%s)" % str(board.aim(w)))
	_press("tool_3")
	_press("tool_next")
	await get_tree().process_frame
	check(board.pen == 2 and board.width == 2, "number keys pick the colour and scroll the thickness (%s)" % board.pen_text())
	check(w.tool == "hands", "the number keys don't change tool at the board")
	Input.action_press("act")
	for i in 30:
		w._look(0.01, 0.002)
		await get_tree().process_frame
	Input.action_release("act")
	await get_tree().process_frame
	marks = Shed.board["marks"]
	check(marks.size() == 1 and int(marks[0]["c"]) == 2 and (marks[0]["pts"] as PackedVector2Array).size() >= 2,
		"holding the mouse at the board draws a red line where you look (%d marks)" % marks.size())
	await get_tree().process_frame
	check(board._nodes.size() == 1 and board._nodes.values()[0] is Line2D, "the line is drawn on the board")
	_press("board_undo")
	await get_tree().process_frame
	await get_tree().process_frame
	check(Shed.board["marks"].is_empty() and board._nodes.is_empty(), "Z takes it back off")
	_press("board_text")
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.label_dialog.visible, "T opens a box to type in")
	main.label_dialog._edit.text = "Order brake pads"
	main.label_dialog._save()
	main.label_dialog._edit.text = "Bleed the brakes"
	main.label_dialog._save()
	main.label_dialog._save()
	var texts: Array = Shed.board["marks"].filter(func(m): return m.has("text"))
	check(texts.size() == 2 and texts[1]["at"].y > texts[0]["at"].y and not main.label_dialog.visible,
		"Enter puts each line up under the last, and an empty line closes the box")
	for i in 3:
		await get_tree().physics_frame
	Input.action_press("board_wipe")
	for i in 400:
		await get_tree().process_frame
		if Shed.board["marks"].is_empty():
			break
	Input.action_release("board_wipe")
	check(Shed.board["marks"].is_empty(), "holding X wipes the whole board")
	main._end_session()
	main.queue_free()
	await get_tree().process_frame

func _test_tuning() -> void:
	Shed.start_new("Tester", 7)
	var me := Shed.me()
	var faithful := _bike_named("Old Faithful")   # USD fork and sport shock (3-way), close-ratio cassette box, no ECU
	var ranger := _bike_named("Rusty Ranger")     # enduro fork: preload and rebound only
	var barn := _bike_named("Barn Find")          # classic fork: no adjusters
	var stock := BikeBuild.new()
	check(BikeBuild.new({}, {}, {}).hp() == stock.hp() and BikeBuild.new({}, {}, {}).rolling == BikeBuild.ROLLING,
		"an untouched tune leaves the bike stock")

	# Settings live in the Shed: the engine's on the bike, the rest on the part they belong to.
	Shed.request({"a": "tune", "bike": faithful, "key": "map", "value": 0.6})
	Shed.request({"a": "tune", "bike": faithful, "key": "psi_r", "value": 2.0})
	Shed.request({"a": "tune", "bike": faithful, "key": "sprocket_r", "value": 50})
	var rear_tyre := Shed.item_on(faithful, "rear_tyre")
	check(is_equal_approx(float(Shed.bikes[faithful]["tune"]["map"]), 0.25),
		"with no ECU the fuel map only moves a little (asked 0.6, got %.2f)" % float(Shed.bikes[faithful]["tune"]["map"]))
	check(is_equal_approx(float(Shed.items[rear_tyre]["tune"]["pressure"]), 2.0), "tyre pressure is kept on the tyre")
	var copy: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	Shed._sync(copy)
	var t := Shed.tune_of(faithful)
	check(is_equal_approx(float(t.get("map", 0.0)), 0.25) and is_equal_approx(float(t.get("psi_r", 0.0)), 2.0)
		and is_equal_approx(float(t.get("sprocket_r", 0.0)), 50.0), "the tune survives the snapshot (save and co-op sync) %s" % str(t))
	check(BikeBuild.new({"ecu": "race_ecu"}).tune_range("map").y > BikeBuild.new({"ecu": "stock_ecu"}).tune_range("map").y
		and BikeBuild.new({"ecu": "remap_ecu"}).tune_range("limiter").y > 0.0 and stock.tune_range("limiter").y == 0.0,
		"a remap or race ECU opens up the map and the rev limiter")

	# Gearing: a bigger rear sprocket is shorter.
	var short := Shed.build_of(faithful)
	Shed.request({"a": "tune", "bike": faithful, "key": "sprocket_r", "reset": true})
	var tall := Shed.build_of(faithful)
	check(short.final_drive > tall.final_drive and float(short.gear_speeds()[-1]) < float(tall.gear_speeds()[-1])
		and absf(short.top_speed_estimate() - tall.top_speed_estimate()) > 0.1,
		"a 50-tooth rear sprocket gears it down (%.0f vs %.0f km/h in top at the limiter, top speed %.0f vs %.0f)" % [
		short.gear_speeds()[-1], tall.gear_speeds()[-1], short.top_speed_estimate() * 3.6, tall.top_speed_estimate() * 3.6])
	var wide := BikeBuild.new({"gearbox": "six_close"}, {}, {"spread": 1.0})
	var close := BikeBuild.new({"gearbox": "six_close"})
	check(float(wide.gear_ratios[0]) > float(close.gear_ratios[0]) and is_equal_approx(float(wide.gear_ratios[-1]), float(close.gear_ratios[-1])),
		"a cassette gearbox can be respaced about top gear")
	check(Shed.check(me, {"a": "tune", "bike": ranger, "key": "spread", "value": 0.5}).contains("cassette"),
		"an ordinary gearbox can't be respaced")

	# Fuel map and ignition.
	var rich := BikeBuild.new({"ecu": "race_ecu"}, {}, {"map": 0.4})
	var lean := BikeBuild.new({"ecu": "race_ecu"}, {}, {"map": -0.8})
	var base := BikeBuild.new({"ecu": "race_ecu"})
	var low := base.peak_torque_rpm * 0.6
	check(rich.engine_torque(low) > base.engine_torque(low) * 1.01 and rich.hp() > base.hp(),
		"a richer map fattens the curve (%.1f vs %.1f Nm low down)" % [rich.engine_torque(low), base.engine_torque(low)])
	check(lean.cruise_economy() > base.cruise_economy() and lean.hp() < base.hp() and lean.engine_stress > 1.5
		and rich.cruise_economy() < base.cruise_economy(), "lean saves petrol but costs power and works the engine harder")
	var pinking := BikeBuild.new({"ecu": "race_ecu"}, {}, {"ignition": 1.0})
	var race_fuel := BikeBuild.new({"ecu": "race_ecu"}, {"tank": {"fluid": {"type": "race_fuel", "litres": 5.0, "age": 0.0}}}, {"ignition": 1.0})
	check(str(pinking.notes).contains("Pinking") and not str(race_fuel.notes).contains("Pinking")
		and pinking.engine_stress > race_fuel.engine_stress, "full advance pinks on 95 but not on race fuel")
	var revvy := BikeBuild.new({"ecu": "race_ecu"}, {}, {"limiter": 800.0})
	check(is_equal_approx(revvy.redline, base.redline + 800.0) and float(revvy.gear_speeds()[0]) > float(base.gear_speeds()[0]),
		"raising the limiter lets each gear run on")

	# Tyre pressures.
	var soft := BikeBuild.new({}, {}, {"psi_f": 1.4, "psi_r": 1.4})
	var hard := BikeBuild.new({}, {}, {"psi_f": 3.2, "psi_r": 3.2})
	check(float(soft.grip_front["tarmac"]) < float(stock.grip_front["tarmac"]) and float(hard.grip_rear["tarmac"]) < float(stock.grip_rear["tarmac"])
		and soft.rolling > stock.rolling and float(soft.tyre_wear["rear"]) > 1.5,
		"tyres off their best pressure grip less; soft ones drag and wear (%.3f vs %.3f grip)" % [soft.grip_front["tarmac"], stock.grip_front["tarmac"]])
	var mx := {"front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx"}
	check(float(BikeBuild.new(mx, {}, {"psi_r": 0.85}).grip_rear["dirt"]) > float(BikeBuild.new(mx).grip_rear["dirt"]),
		"a knobbly a touch soft finds more grip in the dirt")

	# Suspension clickers, only where the parts have them.
	check(Shed.check(me, {"a": "tune", "bike": barn, "key": "f_preload", "value": 0.5}).contains("no preload adjuster"),
		"a fork with no adjusters can't be changed")
	check(Shed.check(me, {"a": "tune", "bike": ranger, "key": "f_bump", "value": 0.5}).contains("no bump adjuster")
		and Shed.check(me, {"a": "tune", "bike": ranger, "key": "f_rebound", "value": 0.5}) == "",
		"a 2-way fork adjusts rebound but not compression")
	check(BikeBuild.new({"fork": "classic_conventional"}, {}, {"f_preload": 1.0}).front_spring == BikeBuild.new({"fork": "classic_conventional"}).front_spring,
		"a setting the part can't take is ignored")
	var before := Shed.build_of(faithful)
	Shed.request({"a": "tune", "bike": faithful, "key": "f_bump", "value": 0.5})
	Shed.request({"a": "tune", "bike": faithful, "key": "r_preload", "value": 1.0})
	var after := Shed.build_of(faithful)
	check(after.front_bump > before.front_bump * 1.1 and after.rear_spring > before.rear_spring * 1.1
		and Shed.items[Shed.item_on(faithful, "fork")]["tune"].has("bump"), "clicking the USD fork and shock firms them up")

	# Chain tension from the desk is the chain's own slack.
	Shed.request({"a": "tune", "bike": faithful, "key": "chain", "value": 26})
	check(is_equal_approx(float(Shed.items[Shed.item_on(faithful, "chain")]["slack"]), 26.0) and is_equal_approx(Shed.build_of(faithful).chain_slack, 26.0),
		"the desk sets the chain slack")

	# Lightening parts.
	var frame := Shed.item_on(faithful, "frame")
	var heavy := Shed.build_of(faithful).bike_mass
	var wear := float(Shed.items[frame]["wear"])
	Shed.request({"a": "lighten", "item": frame})
	var saved := heavy - Shed.build_of(faithful).bike_mass
	check(Shed.items[frame].get("lightened", false) and saved > 0.5 and float(Shed.items[frame]["wear"]) > wear,
		"a drilled and trimmed frame weighs less (%.1f kg saved) but gives up some condition" % saved)
	check(Shed.check(me, {"a": "lighten", "item": frame}).contains("already"), "a part is only lightened once")
	var carbon := Shed._new_item("carbon_monocoque", 0.0, 0.0, 0.0)
	check(Shed.check(me, {"a": "lighten", "item": carbon}).contains("light as it goes"), "lightweight parts can't be trimmed further")
	Shed._erase_item(carbon)

	# Riding wears tyres faster at the wrong pressure.
	var tyre := Shed.item_on(faithful, "front_tyre")
	Shed.items[tyre]["wear"] = 0.0
	Shed._wear_from_ride(faithful, {"km": 5.0})
	var right := float(Shed.items[tyre]["wear"])
	Shed.request({"a": "tune", "bike": faithful, "key": "psi_f", "value": 1.2})
	Shed.items[tyre]["wear"] = 0.0
	Shed._wear_from_ride(faithful, {"km": 5.0})
	check(float(Shed.items[tyre]["wear"]) > right * 1.5 and right > 0.0, "a soft tyre wears faster")
	Shed.request({"a": "tune", "bike": faithful, "key": "psi_f", "reset": true})

	# The dyno: wheel it on and it's strapped down; then run it.
	check(Shed.check(me, {"a": "dyno_run", "bike": faithful}).contains("onto the dyno"), "only a bike on the dyno can be run")
	Shed.request({"a": "grab_bike", "bike": faithful})
	var near := DynoRoom.rig_transform().translated(Vector3(0.3, 0.0, 0.5))
	Shed.request({"a": "move_bike", "bike": faithful, "xf": near})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": near})
	check(Shed.on_dyno(faithful) and Shed.dyno_bike() == faithful and Shed.bikes[faithful]["stand"] == ""
		and (Shed.bikes[faithful]["xf"] as Transform3D).is_equal_approx(DynoRoom.rig_transform()),
		"let go near the drum, the bike snaps onto the rig and is strapped down")
	Shed.request({"a": "dyno_run", "bike": faithful})
	var runs: Array = Shed.bikes[faithful].get("dyno", {}).get("runs", [])
	check(runs.size() == 1, "a dyno run is stored on the bike")
	check(Shed.check(me, {"a": "dyno_run", "bike": faithful}).contains("mid-run"), "one run at a time")
	var run: Dictionary = runs[0] if not runs.is_empty() else {}
	var b := Shed.build_of(faithful)
	if not run.is_empty():
		var rpms: Array = run["rpm"]
		var ascending := true
		var positive := true
		for i in range(1, rpms.size()):
			ascending = ascending and float(rpms[i]) > float(rpms[i - 1])
			positive = positive and float(run["hp"][i]) > 0.0 and float(run["nm"][i]) > 0.0
		check(ascending and positive and rpms.size() == run["hp"].size() and is_equal_approx(float(rpms[-1]), roundf(b.redline)),
			"the sweep runs from low revs to the limiter")
		check(float(run["peak_nm_rpm"]) < float(run["peak_hp_rpm"]), "peak torque comes before peak power (%d < %d rpm)" % [
			run["peak_nm_rpm"], run["peak_hp_rpm"]])
		var wheel_hp := b.hp() * b.drivetrain_efficiency
		check(absf(float(run["peak_hp"]) - wheel_hp) < wheel_hp * 0.02 and absf(float(run["top_kmh"]) - b.top_speed_estimate() * 3.6) < 0.5
			and run["gears"].size() == b.gear_count(), "the dyno's numbers match the build (%.1f vs %.1f hp at the wheel)" % [run["peak_hp"], wheel_hp])
		check(float(run["zero_100"]) > 2.0 and float(run["zero_100"]) < 15.0, "a 0-100 estimate (%.2f s)" % run["zero_100"])
	# Change something and run again: the last run stays to compare against.
	Shed._dyno_busy_until = 0
	Shed.request({"a": "tune", "bike": faithful, "key": "map", "value": -0.25})
	Shed.request({"a": "dyno_run", "bike": faithful})
	runs = Shed.bikes[faithful]["dyno"]["runs"]
	check(runs.size() == 2 and int(runs[0]["n"]) == 1 and int(runs[1]["n"]) == 2 and float(runs[1]["peak_hp"]) < float(runs[0]["peak_hp"]),
		"the previous run is kept as a ghost to compare (%.1f -> %.1f hp)" % [runs[0]["peak_hp"], runs[-1]["peak_hp"]])
	Shed._dyno_busy_until = 0
	Shed.request({"a": "dyno_run", "bike": faithful})
	check(Shed.bikes[faithful]["dyno"]["runs"].size() == 2 and int(Shed.bikes[faithful]["dyno"]["n"]) == 3, "only the last two runs are kept")
	check(Shed.check(me, {"a": "set_stand", "bike": faithful, "stand": "side"}).contains("dyno"), "it stays strapped down until you wheel it off")
	# The run plays back the same everywhere: through the gears, then a sweep to the limiter.
	var peak_rpm := 0.0
	var last_p := -1.0
	var monotonic := true
	var tt := 0.0
	while tt < DynoRoom.run_time(b):
		var st := DynoRoom.sweep_state(b, tt)
		peak_rpm = maxf(peak_rpm, float(st["rpm"]))
		monotonic = monotonic and float(st["progress"]) >= last_p
		last_p = float(st["progress"])
		tt += 0.05
	check(monotonic and peak_rpm >= b.redline * 0.99 and DynoRoom.run_time(b) > 6.0 and DynoRoom.run_time(b) < 14.0,
		"a run revs through the gears to the limiter in %.1f s" % DynoRoom.run_time(b))

	# The desk and its graph.
	var desk := TuningComputer.new()
	add_child(desk)
	var tune_before := Shed.tune_of(faithful)
	desk.open()
	await get_tree().process_frame
	desk._process(1.0)
	check(desk.bike_id == faithful and desk.tunable_bikes()[0] == faithful, "the desk picks the bike on the dyno")
	check(Shed.tune_of(faithful) == tune_before, "opening the desk doesn't change the tune %s" % str(Shed.tune_of(faithful)))
	(desk._rows["psi_r"]["slider"] as HSlider).value = 2.2
	desk._flush()
	check(is_equal_approx(float(Shed.tune_of(faithful).get("psi_r", 0.0)), 2.2), "moving a slider tunes the bike through the Shed")
	desk._select(barn)
	check(not (desk._rows["f_preload"]["slider"] as HSlider).editable, "sliders are locked where the part has no adjuster")
	check(TuningComputer.value_text("map", 0.2, b).begins_with("Rich") and TuningComputer.value_text("psi_f", 2.0, b).contains("bar"),
		"the desk reads settings in plain words")
	desk.close_computer()
	desk.queue_free()
	var graph := DynoGraph.new()
	graph.size = Vector2(1280, 720)
	add_child(graph)
	graph.show_runs("DYNO", Shed.bikes[faithful]["dyno"]["runs"], 0.5, {"rpm": 6000.0, "gear": 5})
	await get_tree().process_frame
	graph.show_runs("DYNO", Shed.bikes[faithful]["dyno"]["runs"], 1.0)
	await get_tree().process_frame
	check(graph.runs.size() == 2, "the dyno graph draws the last two runs")
	graph.queue_free()
	Shed.stop()


## XP, levels, tool upgrades and skills (Progress), with a throwaway profile file.
func _test_progress() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_unit_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Tester", 5)
	Progress.select("Tester")
	var me := Shed.me()
	var xp := func() -> int: return int(Progress.profile["xp"])
	check(xp.call() == 0 and Progress.level() == 1, "a new character starts at level 1 with no XP")
	# The table, ranked the way it should be.
	for key in ["bin", "recycle_plastic", "recycle_metal", "tyre_fit", "tyre_remove", "sell_bike", "sell_part", "money_milestone"]:
		check(Progress.XP.has(key), "the XP table has %s" % key)
	var v := func(k: String) -> int: return int(Progress.XP[k]["xp"])
	check(v.call("bin") < v.call("recycle_plastic") and v.call("recycle_plastic") < v.call("recycle_metal"),
		"binning < recycling < recycling metal")
	check(v.call("carry") <= v.call("bolt") and v.call("bolt") < v.call("brush") and v.call("brush") < v.call("repair")
		and v.call("repair") <= v.call("paint") and v.call("paint") < v.call("build_complete") and v.call("build_complete") < v.call("max_health"),
		"moving < wrenching < cleaning < repairing <= spraying < a build < max health")
	# The level curve.
	check(Progress.xp_for_level(1) == 0 and Progress.xp_for_level(2) == 75 and Progress.level_for_xp(74) == 1
		and Progress.level_for_xp(75) == 2, "level 2 at 75 XP")
	var rising := true
	for l in range(2, Progress.MAX_LEVEL):
		rising = rising and Progress.xp_for_level(l + 1) - Progress.xp_for_level(l) > Progress.xp_for_level(l) - Progress.xp_for_level(l - 1)
	check(rising and Progress.level_for_xp(100000000) == Progress.MAX_LEVEL, "each level takes more than the last, up to level 50")
	# Awards and the repeat cut.
	Progress.award(me, "brush", 1.0, "item:1")
	check(xp.call() == 6, "cleaning a part pays 6 XP (%d)" % xp.call())
	Progress.award(me, "brush", 1.0, "item:1")
	Progress.award(me, "brush", 1.0, "item:1")
	check(xp.call() == 6 + 3 + 2, "cleaning the same part again straight away pays less and less (%d)" % xp.call())
	Progress.award(me, "unbolt", 1.0, "item:7")
	Progress.award(me, "bolt", 1.0, "item:7")
	Progress.award(me, "unbolt", 1.0, "item:7")
	check(xp.call() == 11 + 2 + 1 + 1, "bolting and unbolting the same bolt over and over soon stops paying (%d)" % xp.call())
	var before: int = xp.call()
	Progress.award(me, "no_such_job")
	check(xp.call() == before, "an unknown XP key is ignored")
	var faithful := _bike_named("Old Faithful")
	Progress.award(me, "build_complete", 1.0, "bike:%d" % faithful)
	Progress.award(me, "build_complete", 1.0, "bike:%d" % faithful)
	check(xp.call() == before + 150 + 50 and Progress.level() == 2, "a finished build pays 150 once per bike, and its goal 50 (%d)" % xp.call())
	# Work in the shed pays through the Shed's actions.
	before = xp.call()
	Shed.request({"a": "unbolt", "bike": faithful, "slot": "exhaust"})
	check(xp.call() == before + 2, "unbolting a part in the shed pays wrench XP")
	# Max health: everything on a tired project bike made like new, the last part cleaned.
	var ids := []
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(faithful, slot)
		if id != 0:
			ids.append(id)
			for k in ["rust", "dirt", "wear"]:
				Shed.items[id][k] = 0.0
	Shed.items[ids[3]]["dirt"] = 0.6
	Shed.request({"a": "bolt", "bike": faithful, "slot": "exhaust"})
	before = xp.call()
	Shed.request({"a": "clean", "item": ids[3]})
	check(xp.call() >= before + 300, "bringing a project bike to max health pays 300 (%d)" % (xp.call() - before))
	# Riding XP: worked out on the bike, paid by the host.
	var events := []
	var ride := RideXP.new(faithful)
	ride.sink = func(a, m, d): events.append([a, m, d])
	ride.landed(1.2, true)
	ride.wheelie_done(25.0)
	ride.sprint_done(4.5)
	check(events.size() == 3 and events[0][0] == "jump" and float(events[0][1]) > 2.0 and events[1][0] == "wheelie"
		and events[2][0] == "sprint", "jumps, wheelies and 0-100 runs make riding XP %s" % str(events))
	check(Progress.record("air") >= 1.2 and Progress.profile["goals"].has("jump1"), "a 1.2 s jump is a personal best and reaches a goal")
	before = xp.call()
	Progress.rider_event("jump", 2.0)
	check(xp.call() == before + 24, "riding XP goes through the host's award (%d)" % (xp.call() - before))
	# Spend points: a tool stage really changes the work and the spray.
	Progress.profile["xp"] = Progress.xp_for_level(10)
	var w := Walker.new()
	w.tool = "wrench"
	var p := {"action": {"a": "bolt", "bike": faithful, "slot": "exhaust"}, "time": 1.6}
	w._scale_time(p)
	check(is_equal_approx(float(p["time"]), 1.6), "a stock wrench takes the stock time")
	check(Progress.upgrade_tool("wrench") == "" and Progress.upgrade_tool("wrench") == "" and Progress.tool_stage(me, "wrench") == 2,
		"tool points buy wrench stages")
	p["time"] = 1.6
	w._scale_time(p)
	check(float(p["time"]) < 1.3, "an upgraded wrench bolts up quicker (%.2f s)" % float(p["time"]))
	var radius := Progress.spread_mult(me, "spray")
	Progress.upgrade_tool("spray")
	check(Progress.spread_mult(me, "spray") > radius and Progress.cover_rate_mult(me, "spray") > 1.0, "an upgraded spray can sprays wider and faster")
	check(Progress.upgrade_tool("brush") == "" and Progress.upgrade_tool("brush") == "" and Progress.upgrade_tool("brush") == ""
		and Progress.upgrade_tool("brush").contains("level"),
		"higher stages need higher levels")
	w.free()
	# A gold-trimmed tool looks it.
	var gold := false
	var model := ToolModels.make("wrench", Color.RED, 5)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		gold = gold or (m != null and m.albedo_color.r > 0.9 and m.albedo_color.b < 0.4 and m.metallic > 0.9)
	model.free()
	check(gold, "a stage 5 tool has gold trim")
	# Skills.
	check(Progress.buy_skill("master_builder").contains("first"), "deep skills need the ones before them")
	var points := Progress.skill_points()
	check(Progress.buy_skill("salvager").contains("first") and Progress.buy_skill("quick_hands") == "" and Progress.buy_skill("salvager") == ""
		and Progress.skill_points() == points - 2, "skills cost a point a rank, after their prerequisite")
	before = xp.call()
	Progress.award(me, "recycle_metal")
	check(xp.call() == before + 6, "Salvager gets more XP from recycling (%d)" % (xp.call() - before))
	var plain := Progress.time_mult(me, "hands", {"a": "install"})
	Progress.buy_skill("quick_hands")
	check(Progress.time_mult(me, "hands", {"a": "install"}) < plain, "Quick Hands fits parts quicker")
	Progress.buy_skill("featherweight")
	var frame := Shed.item_on(faithful, "frame")
	Shed.request({"a": "lighten", "item": frame})
	check(BikeBuild.lighten_cut(str(Shed.items[frame]["part"]), float(Shed.items[frame].get("lighten_extra", 0.0)))
		> BikeBuild.lighten_cut(str(Shed.items[frame]["part"])), "Featherweight takes more weight off when lightening")
	var bike := Bike.new()
	bike.assist = 0.3
	var steady := bike._steadiness()
	bike.skills = {"balance": 2}
	check(bike._steadiness() > steady, "Balance steadies the rider on one wheel")
	bike.free()
	Progress.respec()
	check(Progress.skill_rank(me, "quick_hands") == 0 and Progress.skill_points() == Progress.level() - 1, "a respec hands every skill point back")
	# The character is kept on disk, by name.
	Progress.buy_skill("torque_feel")
	var saved: Dictionary = Progress.profile.duplicate(true)
	check(Progress.save_profile(), "the profile saves")
	Progress.profile["xp"] = 0
	Progress.profile["tools"] = {}
	Progress.select("Somebody else")
	check(int(Progress.profile["xp"]) == 0, "another name has its own character")
	Progress.select("Tester")
	check(int(Progress.profile["xp"]) == int(saved["xp"]) and Progress.tool_stage(me, "wrench") == 2
		and Progress.skill_rank(me, "torque_feel") == 1 and Progress.record("air") >= 1.2, "the character loads back as it was saved")
	var s := Progress.summary(me)
	check(s.has_all(["name", "level", "xp", "xp_level_start", "xp_next", "tool_points", "skill_points", "goals"])
		and s["goals"].size() == Progress.GOALS.size() and s["level"] == 10, "summary() gives the TVs everything")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


## Takes a bike's wheel off (the brake parts mounted on it come off first and are put down on the
## floor) and puts it, tyre and all, on the tyre changer. Returns [[slot, item]] of the brake parts.
func _wheel_to_changer(bike_id: int, side: String) -> Array:
	var off := []
	for part in ["pads", "caliper", "disc"]:
		var slot: String = side + "_" + part
		var id := Shed.item_on(bike_id, slot)
		if id == 0:
			continue
		Shed.request({"a": "unbolt", "bike": bike_id, "slot": slot})
		Shed.request({"a": "remove", "bike": bike_id, "slot": slot})
		Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(-1.0 + off.size() * 0.4, 0.0, 1.5))})
		off.append([slot, id])
	Shed.request({"a": "unbolt", "bike": bike_id, "slot": side + "_wheel"})
	Shed.request({"a": "remove", "bike": bike_id, "slot": side + "_wheel"})
	Shed.request({"a": "place", "spot": Shed.changer_spot()})
	return off


## Lifts the wheel off the tyre changer, puts it back in the bike and refits its brake parts.
func _wheel_from_changer(bike_id: int, side: String, brake: Array) -> void:
	Shed.request({"a": "take", "spot": Shed.changer_spot()})
	Shed.request({"a": "install", "bike": bike_id, "slot": side + "_wheel"})
	Shed.request({"a": "bolt", "bike": bike_id, "slot": side + "_wheel"})
	for i in range(brake.size() - 1, -1, -1):
		Shed.request({"a": "take", "item": int(brake[i][1])})
		Shed.request({"a": "install", "bike": bike_id, "slot": str(brake[i][0])})
		Shed.request({"a": "bolt", "bike": bike_id, "slot": str(brake[i][0])})


## Lights run off the ignition: a parked or switched-off bike is dark, lenses and all, ridden or
## another player's; the beam is grainy and dusty, with motes drifting in it at night.
func _test_bike_lights() -> void:
	var parked := BikeModel.new()
	add_child(parked)
	parked.build_from(BikeBuild.new({"fog_lights": "rally_lamps", "headlight": "led_projector"}))
	check(not parked.lights_lit(), "a parked bike's headlight, tail light, fog lamps and clocks are dark")
	parked.set_lights(true, false)
	check(parked.lights_lit(), "with the ignition on the tail light and clocks glow")
	parked.queue_free()
	var r := await ride({"fog_lights": "rally_lamps"}, 0.3, func(b, _t): b.engine_on = false)
	var bike: Bike = r["bike"]
	check(not bike.model.lights_lit() and not bike.effects.light_on() and bike._fog.all(func(l): return not l.visible),
		"engine off: no beam, no fog lamps, every lens dark")
	bike.engine_on = true
	for i in 3:
		await get_tree().physics_frame
	check(bike.model.lights_lit() and bike.effects.light_on() and bike._fog.all(func(l): return l.visible), "engine running: the lights come on")
	bike.beam = 0
	for i in 3:
		await get_tree().physics_frame
	check(not bike.effects.light_on() and bike.model.lights_lit(), "L switches the headlight off; the tail light stays on")
	bike.beam = 2
	bike.engine_on = false
	for i in 3:
		await get_tree().physics_frame
	check(not bike.effects.light_on() and not bike.model.lights_lit(), "switching the engine off puts every light out, even on high beam")
	# At night the beam fills with dust motes; by day there are none.
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var dl := Daylight.new()
	add_child(dl)
	var cycle := Settings.day_night_cycle
	Settings.day_night_cycle = false
	dl.setup(env, sun)
	dl.set_time(0.0)
	bike.engine_on = true
	bike.beam = 1
	for i in 3:
		await get_tree().physics_frame
	var cone := bike.effects._cone.material_override as ShaderMaterial
	check(bike.effects.motes_showing() and cone.get_shader_parameter("haze") is Texture2D,
		"at night dust motes drift in the beam and the shaft is grainy haze, not a smooth gradient")
	dl.set_time(12.0)
	for i in 3:
		await get_tree().physics_frame
	check(bike.effects.light_on() and not bike.effects.motes_showing(), "in daylight the motes fade out")
	Settings.day_night_cycle = cycle
	dl.queue_free()
	sun.queue_free()
	await _done(r)
	# Another player's bike follows their ignition.
	var rb := RemoteBike.new()
	add_child(rb)
	rb.setup("Other", BikeBuild.new(), Color(0.2, 0.4, 0.9))
	var st := PackedFloat32Array()
	st.resize(25)
	st[6] = 1.0
	st[24] = 1.0
	rb.push_state(st)
	for i in 3:
		await get_tree().physics_frame
	check(not rb.model.lights_lit() and not rb._effects.light_on(), "another player's parked, switched-off bike is dark")
	st[19] = 1.0
	rb.push_state(st)
	for i in 3:
		await get_tree().physics_frame
	check(rb.model.lights_lit() and rb._effects.light_on(), "and lights up when they start it")
	rb.queue_free()
	await get_tree().process_frame


## Tyres and rims: drawn to their real sizes, only fitted to rims they suit, and changed on the
## tyre changer with a little skill game.
func _test_tyre_changer() -> void:
	# Drawn to size: a 180/55 is 180 mm wide and 99 mm tall on its rim.
	var b := BikeBuild.new({"rear_tyre": "sport_road", "rear_wheel": "cast_17"})
	var model := BikeModel.new()
	add_child(model)
	model.build_from(b)
	var tyre_box := model.slot_bounds("rear_tyre")
	check(absf(tyre_box.size.x - 0.18) < 0.006 and absf(tyre_box.size.y - 2.0 * (b.rear_rim_radius + 0.18 * 0.55)) < 0.01,
		"a 180/55 tyre is drawn 180 mm wide and to its profile (%.3f x %.3f m)" % [tyre_box.size.x, tyre_box.size.y])
	check(is_equal_approx(b.front_tyre_width, 0.12) and BikeModel.rim_width_of(PartsDB.get_part("cast_17")) < 0.18,
		"the front tyre is its own width, and the rim is narrower than the tyre on it")
	model.queue_free()
	# Which tyres go on which rims.
	check(PartsDB.tyre_fit("sport_road", "cast_17") == 0 and PartsDB.tyre_fit("sport_road_200", "spoked_21") == 1
		and PartsDB.tyre_fit("knobbly_mx_80", "cast_17") != 0 and PartsDB.tyre_fit("sport_road_120", "cast_19_six") == 2,
		"a tyre fits only a rim of its width range and diameter")
	check(PartsDB.spec_line("cast_17").contains("140-180 mm") and PartsDB.spec_line("cast_17").contains("17\""),
		"a wheel's info says which tyres it takes (%s)" % PartsDB.spec_line("cast_17"))
	check(PartsDB.spec_line("knobbly_mx_80").contains("21\" rims"), "a tyre's info says which rims it fits (%s)" % PartsDB.spec_line("knobbly_mx_80"))
	for w in PartsDB.by_kind["wheel"]:
		check(not PartsDB.tyres_for(w).is_empty(), "the %s has tyres to fit it (%d)" % [w, PartsDB.tyres_for(w).size()])
	# The skill game: following the marker seats the bead; leaving the lever still doesn't.
	var good := TyreGame.new()
	while not good.done():
		good.cursor = good.marker()
		good.step(1.0 / 60.0)
	var lazy := TyreGame.new()
	while not lazy.done():
		lazy.step(1.0 / 60.0)
	check(good.quality() > 0.95 and lazy.quality() < 0.3, "following the marker round seats the bead (%.2f, left alone %.2f)" % [good.quality(), lazy.quality()])

	Shed.start_new("Tester", 5)
	var me := Shed.me()
	var spot := Shed.changer_spot()
	var changer := Shed.furniture_of_spot(spot)
	check(spot != "" and Equipment.FIXED_KINDS.has(str(changer["kind"])) and Shed.check(me, {"a": "grab", "furniture": int(changer["id"])}) != "",
		"the shed has a built-in tyre changer")
	var at: Vector3 = (changer["xf"] as Transform3D).origin
	check(at.distance_to(Workshop.CENTER) < 8.0 and absf(at.x - (Workshop.CENTER.x - Workshop.HALF.x)) < 0.6
		and at.distance_to(Whiteboard.MOUNT) > 1.6 and at.z > Workshop.spot_transform("bench_3").origin.z,
		"it stands against the west wall past the workbench, clear of the whiteboard")
	for bay in Workshop.BAY_COUNT:
		check(Workshop.bay_transform(bay).origin.distance_to(at) > 3.0, "it's clear of bay %d" % (bay + 1))
	var faithful := _bike_named("Old Faithful")
	# On the bike, tyres can't be changed.
	var tyre := _order("sport_road_120")
	Shed.request({"a": "unpack", "item": tyre})
	Shed.request({"a": "take", "item": tyre})
	check(Shed.check(me, {"a": "install", "bike": faithful, "slot": "rear_tyre"}).contains("tyre changer"),
		"a tyre can't be fitted with the wheel on the bike")
	check(Shed.check(me, {"a": "remove", "bike": faithful, "slot": "rear_tyre"}).contains("tyre changer")
		and Shed.check(me, {"a": "unbolt", "bike": faithful, "slot": "rear_tyre"}).contains("tyre changer"),
		"nor taken off: take the wheel off and use the tyre changer")
	check(Shed.check(me, {"a": "place", "spot": spot}).contains("wheel"), "only a wheel goes on the changer")
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(0.5, 0.0, 2.0))})
	# The wheel comes off with its tyre on and goes on the changer.
	var old_tyre := Shed.item_on(faithful, "front_tyre")
	var wheel := Shed.item_on(faithful, "front_wheel")
	var brake := _wheel_to_changer(faithful, "front")
	check(Shed.item_at_spot(spot) == wheel and Shed.tyre_on_wheel(wheel) == old_tyre and Shed.items[old_tyre]["at"] == "wheel"
		and Shed.item_on(faithful, "front_tyre") == 0, "the wheel comes off with its tyre and sits on the changer")
	var shown := BikeModel.item_display(wheel)
	check((shown.get_meta("model") as BikeModel).is_fitted("front_tyre"), "the wheel is drawn with its tyre on")
	shown.free()
	# Lever the old tyre off, then try a tyre that's wrong for the rim.
	# (XP goes through /root/Progress: a stand-in records it if the game's isn't loaded.)
	var prog := get_node_or_null("/root/Progress")
	var mock: Node = null
	if prog == null:
		var s := GDScript.new()
		s.source_code = "extends Node\nvar got := []\nfunc award(peer, key, mult := 1.0) -> void:\n\tgot.append([peer, key, mult])\n"
		s.reload()
		mock = Node.new()
		mock.set_script(s)
		mock.name = "Progress"
		get_tree().root.add_child(mock)
	Shed.request({"a": "tyre_remove", "spot": spot})
	check(Shed.held_by(me) == old_tyre and Shed.tyre_on_wheel(wheel) == 0, "the old tyre is levered off into your hands")
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(1.0, 0.0, 2.0))})
	var skinny := _order("knobbly_mx_80")
	Shed.request({"a": "unpack", "item": skinny})
	Shed.request({"a": "take", "item": skinny})
	var why := Shed.check(me, {"a": "tyre_fit", "spot": spot, "quality": 1.0})
	check(why.contains("too narrow") and why.contains("110-130"), "a tyre that doesn't suit the rim can't be fitted (%s)" % why)
	Shed.request({"a": "tyre_fit", "spot": spot, "quality": 1.0})
	check(Shed.tyre_on_wheel(wheel) == 0 and Shed.held_by(me) == skinny, "so it stays in your hands")
	Shed.request({"a": "bin"})
	# Fit the new tyre with a sloppy bead: XP for the job, and the build feels it.
	Shed.request({"a": "take", "item": tyre})
	Shed.request({"a": "tyre_fit", "spot": spot, "quality": 0.3})
	check(Shed.tyre_on_wheel(wheel) == tyre and is_equal_approx(float(Shed.items[tyre]["bead"]), 0.3),
		"the new tyre goes on, its bead seated as well as it was worked on")
	check(Shed.condition_text(Shed.items[tyre]).contains("badly seated"), "the part info says the bead is badly seated")
	_wheel_from_changer(faithful, "front", brake)
	check(Shed.item_on(faithful, "front_wheel") == wheel and Shed.item_on(faithful, "front_tyre") == tyre and Shed.is_complete(faithful),
		"the wheel goes back in with its new tyre and the bike is whole again (%s)" % str(Shed.missing_slots(faithful) + Shed.loose_slots(faithful)))
	var sloppy := Shed.build_of(faithful)
	check(sloppy.notes.any(func(n): return n.contains("bead")), "the bay screen flags the badly seated bead")
	var grip_sloppy: float = sloppy.grip_front["tarmac"]
	Shed.crew[me]["riding"] = faithful
	Shed.request({"a": "ride", "km": 4.0})
	Shed.crew[me]["riding"] = 0
	check(float(Shed.items[tyre].get("tune", {}).get("pressure", 9.0)) < Shed.build_of(faithful).tune_default("psi_f") - 0.03,
		"a badly seated bead slowly lets the tyre down")
	Shed.items[tyre]["bead"] = 1.0
	check(Shed.build_of(faithful).grip_front["tarmac"] > grip_sloppy, "a well seated bead grips better")
	if mock:
		var got: Array = mock.get("got")
		check(got.size() == 2 and got[0][1] == "tyre_remove" and got[1][1] == "tyre_fit" and is_equal_approx(float(got[1][2]), 0.3)
			and int(got[1][0]) == me, "XP goes to whoever changed the tyre, scaled by how well (%s)" % str(got))
		mock.queue_free()
	# Binning a wheel with a tyre on it bins both.
	var spare := _order("cast_17_front")
	Shed.request({"a": "unpack", "item": spare})
	Shed.request({"a": "take", "item": spare})
	Shed.request({"a": "place", "spot": spot})
	Shed.request({"a": "take", "item": old_tyre})
	Shed.request({"a": "tyre_fit", "spot": spot, "quality": 1.0})
	Shed.request({"a": "take", "spot": spot})
	Shed.request({"a": "bin"})
	check(not Shed.items.has(spare) and not Shed.items.has(old_tyre), "a wheel binned with its tyre on takes the tyre with it")
	# New project bikes always wear tyres that suit their rims.
	for i in 12:
		var id := Shed._random_bike(3)
		var parts: Dictionary = Shed.bikes[id]["original"]
		check(PartsDB.tyre_fit(parts["front_tyre"], parts["front_wheel"]) == 0 and PartsDB.tyre_fit(parts["rear_tyre"], parts["rear_wheel"]) == 0,
			"a delivered bike's tyres suit its rims (%s on %s, %s on %s)" % [parts["front_tyre"], parts["front_wheel"], parts["rear_tyre"], parts["rear_wheel"]])
		Shed.bikes.erase(id)
	Shed.stop()


## A wheel left on the tyre changer, with its tyre on, is saved and comes back; a shed saved
## before the changer was built in gets one.
func _test_changer_save_load() -> void:
	SaveGame.slot_override = "test_changer"
	var slot := SaveGame.active_slot()
	SaveGame.delete_slot(slot)
	Shed.start_new("Tester", 3)
	var spot := Shed.changer_spot()
	var wheel := _order("spoked_21")
	Shed.request({"a": "unpack", "item": wheel})
	Shed.request({"a": "take", "item": wheel})
	Shed.request({"a": "place", "spot": spot})
	var tyre := _order("knobbly_mx_90")
	Shed.request({"a": "unpack", "item": tyre})
	Shed.request({"a": "take", "item": tyre})
	Shed.request({"a": "tyre_fit", "spot": spot, "quality": 0.72})
	check(Shed.tyre_on_wheel(wheel) == tyre, "a tyre is fitted on the changer")
	check(SaveGame.write(slot, {"version": SaveGame.VERSION, "shed": Shed._snapshot().duplicate(true)}) == OK, "the shed is saved")
	Shed.start_new("Tester", 4)
	check(Shed.item_at_spot(spot) != wheel, "a new shed has an empty changer")
	Shed.load_state(SaveGame.read(slot)["shed"], "Tester")
	check(Shed.item_at_spot(spot) == wheel and Shed.tyre_on_wheel(wheel) == tyre and Shed.items[tyre]["at"] == "wheel"
		and is_equal_approx(float(Shed.items[tyre]["bead"]), 0.72), "the wheel on the changer and its tyre come back from the save")
	var changers := Shed.furniture.values().filter(func(f): return f["kind"] == "changer")
	check(changers.size() == 1, "loading doesn't add a second changer")
	# An old save with no tyre changer in it.
	var old: Dictionary = Shed._snapshot().duplicate(true)
	for id in old["furniture"].keys():
		if old["furniture"][id]["kind"] == "changer":
			old["furniture"].erase(id)
	old["items"].erase(wheel)
	old["items"].erase(tyre)
	Shed.load_state(old, "Tester")
	check(Shed.changer_spot() != "", "a shed saved before the tyre changer gets one")
	SaveGame.delete_slot(slot)
	SaveGame.slot_override = ""
	Shed.stop()
