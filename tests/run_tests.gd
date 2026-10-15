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
	await _test_walker_spawns()
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
	print("Shop: recycling and TV channels")
	_test_recycling()
	await _test_tv_channels()
	await _test_tv_and_bins_session()
	print("Key bindings, the pad in menus, whiteboard pictures and posters")
	await _test_key_bindings()
	await _test_pad_menus()
	await _test_board_posters()
	await _test_board_images()
	print("Carrying, snapping, free surfaces, the whiteboard and delivery boxes")
	await _test_carry_and_snap()
	_test_free_surfaces()
	await _test_surface_session()
	await _test_whiteboard_moves()
	_test_box_labels()
	print("Side rooms: paint shop, storage room, light switches")
	_test_side_rooms()
	_test_side_rooms_old_save()
	await _test_side_rooms_session()
	print("Dyno room kit and the sandblaster")
	_test_dyno_kit()
	await _test_dyno_room_session()
	await _test_sandblaster()
	print("Geometry mode and blueprints")
	_test_geo_gizmo_math()
	_test_geo_model()
	_test_geo_shed()
	_test_blueprint_build()
	await _test_geometry_session()
	print("Tail units, fairings and mirrors")
	_test_tail_fairing_mirrors_parts()
	_test_tail_fairing_mirrors_shed()
	_test_tail_old_save()
	print("Scrapping kit, turning what you hold, free shelves, turned board pictures and poster sizes")
	_test_scrap()
	await _test_scrap_session()
	await _test_hold_turning()
	_test_shelf_surfaces()
	await _test_shelf_session()
	await _test_board_turning()
	await _test_poster_sizes()
	print("Soft headlight, tyre sounds, debug tab, menu rows and weather")
	await _test_soft_beam()
	await _test_skid_sounds()
	_test_debug_tab()
	await _test_weather()
	await _test_weather_session()
	print("Sandblaster round 2: big cabinet, satin metal, live readout; hooks swing from the rail")
	await _test_blast_cabinet_fits()
	_test_blast_detail_and_satin()
	await _test_blast_live_session()
	await _test_booth_swing_from_rail()
	print("Money: wages, transfers, loans, prices and selling")
	_test_money_pay_and_transfers()
	_test_money_loans()
	_test_money_parts_and_selling()
	print("Contracts: customers, offers, MOT, goals, payouts and saving")
	_test_contract_customers()
	_test_contract_mot()
	_test_contract_goals_and_pay()
	_test_contract_save()
	await _test_contract_session()
	print("Sales office: showroom, reception, kitchen, viewing area, mezzanine office, the bell")
	_test_sales_office_layout()
	_test_sales_office_save()
	await _test_sales_office_session()
	print("Garage upgrades: extension, bays 5 to 7, storage annex, luxury finishes")
	_test_upgrade_catalogue()
	await _test_computer_fits_screen()
	_test_upgrade_buying()
	await _test_upgrade_session()
	print("Rider gear and trinkets from the Shop")
	_test_gear_catalogue()
	_test_gear_buying()
	await _test_gear_seen_by_others()
	await _test_shop_session()
	print("Graphics settings: presets, saving, applying, the driver override, the Graphics tab")
	await _test_graphics_settings()
	print("Lighting: GI, volumetric fog and clouds, shadows, eye adaptation")
	_test_lighting_profile()
	_test_lighting_lamps_and_gi()
	await _test_lighting_clouds()
	await _test_lighting_session()
	print("Engine sound: firing pulses, exhausts, pops, gear shifts")
	_test_engine_firing()
	_test_engine_bank()
	await _test_engine_events()
	await _test_engine_users()
	_test_engine_samples()
	print("Shed sound: variants, impacts by material, footsteps by floor, room acoustics, ambience")
	await _test_shed_sound_variants()
	await _test_shed_sound_session()
	print("Garage upgrade options: colours, effects and styles, preview, changing them later")
	_test_upgrade_options()
	await _test_upgrade_options_session()


const SLICK := {"front_tyre": "race_slick", "rear_tyre": "race_slick"}
const MX := {"fork": "long_travel_mx", "shock": "mono_shock_mx", "front_wheel": "spoked_21", "rear_wheel": "spoked_18",
	"front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx"}


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func _test_catalogue() -> void:
	check(PartsDB.KINDS.size() == 35 and PartsDB.parts.size() >= 170, "catalogue has 35 kinds of part (%d parts)" % PartsDB.parts.size())
	for k in PartsDB.KINDS:
		check(PartsDB.by_kind[k].size() >= 5, "%s has at least five variants (%d)" % [k, PartsDB.by_kind[k].size()])
	var no_colour := []
	for id in PartsDB.parts:
		if not PartsDB.parts[id].has("color"):
			no_colour.append(id)
	check(no_colour.is_empty(), "every part has a colour %s" % str(no_colour))
	check(PartsDB.SLOTS.size() == 41, "a bike has 41 slots, 7 of them on the engine")
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
	for model in ["washer_compact", "repair_workshop", "poster_cafe", "seat_sofa", "tv_128", "bench_compact"]:
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
	for case in [["vtwin", 2], ["parallel", 2], ["inline", 4], ["2stroke", 1]]:
		var fires := EngineSynth.firing_events(EngineSynth.make_spec(case[0], case[1], 600.0))
		check(fires.size() == case[1], "a %s fires %d times a cycle" % case)
	var v: Array = EngineSynth.firing_events(EngineSynth.make_spec("vtwin", 2, 900.0))
	check(absf(float(v[1][0]) / 720.0 - 0.5) > 0.03, "a V-twin's beat is uneven")


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
	check(booth != 0 and Shed.furniture_spots(booth).size() >= 10, "the shed has a built-in paint booth with ten hooks")
	check(Shed.furniture[booth]["xf"] == Workshop.BOOTH_XF, "in the paint shop")
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
	var small := EngineSound.new()
	var big := EngineSound.new()
	add_child(small)
	add_child(big)
	small.setup(BikeBuild.new({"engine": "inline_50"}))
	big.setup(BikeBuild.new({"engine": "inline_1200"}))
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

	# The dyno: wheel it on, strap it down at the four posts, then run it.
	check(Shed.check(me, {"a": "dyno_run", "bike": faithful}).contains("onto the dyno"), "only a bike on the dyno can be run")
	Shed.request({"a": "grab_bike", "bike": faithful})
	var near := DynoRoom.rig_transform().translated(Vector3(0.3, 0.0, 0.5))
	Shed.request({"a": "move_bike", "bike": faithful, "xf": near})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": near})
	check(Shed.on_dyno(faithful) and Shed.dyno_bike() == faithful and Shed.bikes[faithful]["stand"] == ""
		and (Shed.bikes[faithful]["xf"] as Transform3D).is_equal_approx(DynoRoom.rig_transform()),
		"let go near the drum, the bike snaps onto the rig")
	check(not Shed.strapped() and Shed.check(me, {"a": "dyno_run", "bike": faithful}).contains("Strap it down"),
		"it won't run until it's strapped down")
	for i in 4:
		Shed.request({"a": "dyno_strap", "point": i})
	check(Shed.strapped() and Shed.check(me, {"a": "grab_bike", "bike": faithful}).contains("straps"),
		"strapped down at all four posts, and it can't be wheeled off until they're undone")
	Shed.request({"a": "dyno_fan", "on": true})
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
## another player's; at night the beam shows softly in the fog, with a few motes drifting in it.
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
	# The beam is light in the night air (volumetric fog), not a cone you can see the edge of.
	var night_fog := bike.effects.beam_fog()
	check(bike.effects.motes_showing() and night_fog > 0.5 and night_fog <= BikeEffects.BEAM_FOG_LOW + 0.01,
		"at night the beam lights the fog softly (%.2f) with a few motes drifting in it" % night_fog)
	var cone := bike.effects._cone
	check(BikeEffects.volumetric_beams() == (cone == null), "with volumetric fog there's no cone mesh at all; without it, only a stand-in glow")
	if cone:
		check(float((cone.material_override as ShaderMaterial).get_shader_parameter("strength")) <= 0.05,
			"the stand-in glow is faint (%.3f)" % float((cone.material_override as ShaderMaterial).get_shader_parameter("strength")))
	check(env.volumetric_fog_density > Daylight.DAY_FOG, "the night air is a little hazier (%.3f)" % env.volumetric_fog_density)
	bike.beam = 2
	for i in 3:
		await get_tree().physics_frame
	check(bike.effects.beam_fog() > night_fog and bike.effects.beam_fog() <= BikeEffects.BEAM_FOG_HIGH + 0.01,
		"high beam shows a little more in the air, still subtle (%.2f)" % bike.effects.beam_fog())
	bike.beam = 1
	dl.set_time(12.0)
	for i in 3:
		await get_tree().physics_frame
	check(bike.effects.light_on() and not bike.effects.motes_showing() and bike.effects.beam_fog() < 0.01,
		"in daylight the motes fade out and the beam doesn't show in the air")
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


## A stand-in for the XP autoload, when the real one isn't there, that notes every award.
func _xp_stub() -> Node:
	if get_node_or_null("/root/Progress"):
		return null
	var s := GDScript.new()
	s.source_code = "extends Node\nvar calls := []\nfunc award(peer, key, mult = 1.0):\n\tcalls.append([peer, key])\n" + \
		"func summary(peer):\n\treturn {\"name\": \"P%d\" % peer, \"level\": 3, \"xp\": 250, \"xp_level_start\": 200, \"xp_next\": 400," + \
		" \"tool_points\": 1, \"skill_points\": 2, \"goals\": [{\"text\": \"Fit 5 parts\", \"have\": 2, \"need\": 5, \"xp\": 50, \"done\": false}," + \
		" {\"text\": \"Ride 1 km\", \"have\": 1, \"need\": 1, \"xp\": 20, \"done\": true}]}\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.name = "Progress"
	get_tree().root.add_child(n)
	return n


## Takes a fresh part out of its box into your hands.
func _hold_new(part: String) -> int:
	var id := _order(part)
	if PartsDB.is_fluid(part):
		id = _newest(part)    # cans and bottles come unboxed
	Shed.request({"a": "unpack", "item": id})
	Shed.request({"a": "take", "item": id})
	return id


func _test_recycling() -> void:
	Shed.start_new("Tester", 11)
	var me := Shed.me()
	var stub := _xp_stub()
	# Every part is made of something, and that decides its bin.
	var unknown := []
	for id in PartsDB.parts:
		if not PartsDB.MATERIAL_NAMES.has(PartsDB.material(id)):
			unknown.append(id)
	check(unknown.is_empty(), "every part has a known material (%s)" % str(unknown.slice(0, 5)))
	var expect := {"steel_cradle": "metal", "four_1000": "metal", "cast_17": "metal", "floating_310": "metal",
		"carbon_monocoque": "general", "carbon_17": "general", "sport_road": "general", "knobbly_mx": "general",
		"plastic_cases": "plastic", "aluminium_boxes": "metal", "leather_saddlebags": "general", "top_box_30": "plastic",
		"semi_10w40": "plastic", "drain_pan": "plastic", "dot4": "plastic", "empty_jerry_can": "metal", "road_lube": "metal",
		"bulb_horn": "general", "tft_colour": "general"}
	var wrong := []
	for id in expect:
		if PartsDB.bin_for(id) != expect[id]:
			wrong.append("%s -> %s" % [id, PartsDB.bin_for(id)])
	check(wrong.is_empty(), "parts go in the right bins: frames, engines, wheels metal; tyres and carbon general; bottles plastic (%s)" % str(wrong))
	check(PartsDB.material("sport_road") == "rubber" and PartsDB.bin_text("sport_road").contains("general waste"),
		"a tyre is rubber, and its info says general waste (%s)" % PartsDB.bin_text("sport_road"))
	# A tyre is refused by the metal bin, with the reason, and the general bin takes it.
	var tyre := _hold_new("sport_road")
	var why := Shed.check(me, {"a": "bin", "bin": "metal"})
	check(why.contains("rubber") and why.contains("general waste"), "the metal bin refuses a tyre: %s" % why)
	Shed.request({"a": "bin", "bin": "metal"})
	check(Shed.held_by(me) == tyre, "the refused tyre stays in your hands")
	Shed.request({"a": "bin", "bin": "general"})
	check(Shed.held_by(me) == 0 and not Shed.items.has(tyre), "general waste takes the tyre and it's gone")
	# A brake disc is metal: not plastic, yes metal.
	var disc := _hold_new("solid_240")
	why = Shed.check(me, {"a": "bin", "bin": "plastic"})
	check(why.contains("metal recycling"), "the plastic bin refuses a disc: %s" % why)
	Shed.request({"a": "bin", "bin": "metal"})
	check(Shed.held_by(me) == 0 and not Shed.items.has(disc), "the disc is recycled in the metal bin and disappears")
	# A full oil bottle has to be emptied first, at general waste; then the bottle is plastic.
	var oil := _hold_new("semi_10w40")
	check(Shed.check(me, {"a": "bin", "bin": "plastic"}).contains("Empty it first"), "a full bottle can't be recycled")
	check(Shed.check(me, {"a": "tip", "bin": "plastic"}) != "", "old fluid isn't tipped into a recycling bin")
	Shed.request({"a": "tip"})
	Shed.request({"a": "bin", "bin": "plastic"})
	check(not Shed.items.has(oil), "once tipped out, the oil bottle is recycled with the plastic")
	# Boxed parts need unpacking, and an engine needs stripping, before recycling.
	var boxed := _order("wave_270")
	Shed.request({"a": "take", "item": boxed})
	check(Shed.check(me, {"a": "bin", "bin": "metal"}) == "Unpack it first.", "a part still in its box isn't recycled")
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER)})
	var block := Shed.item_at_spot(Shed.stand_spots()[0])
	Shed.request({"a": "take", "spot": Shed.stand_spots()[0]})
	check(Shed.held_by(me) == block and Shed.check(me, {"a": "bin", "bin": "metal"}).contains("Strip the engine"),
		"an engine with parts on it has to be stripped before recycling")
	check(Shed.check(me, {"a": "bin", "bin": "compost"}) != "", "there's no such bin as compost")
	if stub:
		var keys: Array = stub.calls.map(func(c): return c[1])
		check(keys == ["bin", "recycle_metal", "recycle_plastic"] and stub.calls.all(func(c): return c[0] == me),
			"binning and recycling award XP to whoever did it (%s)" % str(stub.calls))
		stub.queue_free()
	Shed.stop()


func _test_tv_channels() -> void:
	# Bought TVs are as big as the screens built into the shed; old models still load.
	var tvs := Equipment.by_kind("tv")
	var small := tvs.filter(func(id): return float(Equipment.get_model(id)["size"].x) < Workshop.BAY_SCREEN_INNER)
	var biggest := 0.0
	for id in tvs:
		biggest = maxf(biggest, float(Equipment.get_model(id)["size"].x))
	check(small.is_empty() and biggest >= Workshop.CREW_SCREEN, "wall TVs are at least as big as the bay screens, up to the crew board (%s)" % str(small))
	check(["tv_32", "tv_43", "tv_55", "tv_65"].all(func(id): return Equipment.kind_of(Equipment.current_id(id)) == "tv"),
		"the old TV models map onto new ones")
	Shed.start_new("Tester", 12)
	var me := Shed.me()
	Shed.request({"a": "order_furniture", "model": "tv_55"})
	var tv := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "tv":
			tv = id
	check(tv != 0 and Shed.furniture[tv]["model"] == "tv_120", "ordering an old TV model gets its new size (%s)" % Shed.furniture.get(tv, {}).get("model", ""))
	var key := "f%d" % tv
	check(Shed.screen_channel(key)["ch"] == "live" and Shed.screen_channel("bay0")["ch"] == "bay" and Shed.screen_channel("crew")["ch"] == "crew",
		"screens start on their home channel")
	Shed.request({"a": "tv_channel", "screen": key, "step": 1})
	check(Shed.screen_channel(key)["ch"] == "crew", "next channel: the crew board")
	Shed.request({"a": "tv_channel", "screen": key, "step": 1})
	check(Shed.screen_channel(key)["ch"] == "xp" and TvChannels.osd_label(key, Shed.screen_channel(key), []) == "CH 3  XP GOALS",
		"then XP goals, CH 3 (%s)" % TvChannels.osd_label(key, Shed.screen_channel(key), []))
	Shed.request({"a": "tv_channel", "screen": key, "step": -1})
	Shed.request({"a": "tv_channel", "screen": key, "step": -1})
	Shed.request({"a": "tv_channel", "screen": key, "step": -1})
	check(Shed.screen_channel(key)["ch"] == "contracts", "back past the first channel wraps round to the last")
	check(Shed.check(me, {"a": "tv_channel", "screen": "f99999", "step": 1}) != "" and Shed.check(me, {"a": "tv_channel", "screen": key, "step": 3}) != "",
		"the host refuses a screen that isn't there or a jump of several channels")
	Shed.request({"a": "tv_channel", "screen": "bay2", "step": 1})
	check(Shed.screen_channel("bay2")["ch"] == "live", "the bay screens change channel too")
	# Two riders out: the live channel has a stop for each.
	var a := _bike_named("Old Faithful")
	var b := _bike_named("Rusty Ranger")
	Shed._add_crew(5, "Pal")
	Shed.bikes[a]["rider"] = me
	Shed.crew[me]["riding"] = a
	Shed.bikes[b]["rider"] = 5
	Shed.crew[5]["riding"] = b
	check(Shed.riders() == [me, 5], "both riders are out (%s)" % str(Shed.riders()))
	Shed.request({"a": "tv_channel", "screen": key, "step": 1})
	check(Shed.screen_channel(key) == {"ch": "live", "rider": me}, "live follows the first rider (%s)" % str(Shed.screen_channel(key)))
	Shed.request({"a": "tv_channel", "screen": key, "step": 1})
	check(Shed.screen_channel(key) == {"ch": "live", "rider": 5} and TvChannels.osd_label(key, Shed.screen_channel(key), Shed.riders()) == "CH 1  LIVE: PAL",
		"then the second rider (%s)" % TvChannels.osd_label(key, Shed.screen_channel(key), Shed.riders()))
	Shed.request({"a": "tv_channel", "screen": key, "step": 1})
	check(Shed.screen_channel(key)["ch"] == "crew", "then on to the crew board")
	Shed.request({"a": "tv_channel", "screen": key, "step": -1})
	check(Shed.screen_channel(key) == {"ch": "live", "rider": 5}, "and back to the last rider")
	# Kept in the save; old TV models and live riders sorted out on load.
	Shed.furniture[tv]["model"] = "tv_43"
	var state: Dictionary = Shed._snapshot().duplicate(true)
	SaveGame.write("test_tv_channels", {"version": SaveGame.VERSION, "shed": state})
	var back := SaveGame.read("test_tv_channels")
	SaveGame.delete_slot("test_tv_channels")
	Shed.start_new("Someone else", 3)
	check(Shed.screens.is_empty(), "a new shed's screens are on their home channels")
	Shed.load_state(back["shed"], "Tester")
	check(Shed.furniture.has(tv) and Shed.furniture[tv]["model"] == "tv_120", "an old 43\" TV loads as the new 120\" one")
	check(Shed.screen_channel(key) == {"ch": "live", "rider": 0} and Shed.screen_channel("bay2")["ch"] == "live",
		"the channels come back from the save (%s)" % str(Shed.screens))
	var old := Shed._snapshot().duplicate(true)
	old.erase("screens")
	Shed.load_state(old, "Tester")
	check(Shed.screens.is_empty(), "a save from before channels loads with every screen on its home channel")
	# The money pages read real numbers; contracts is a list, and the XP page says
	# so when there's no XP system.
	check(not TvChannels.garage_data().has("placeholder") and int(TvChannels.garage_data()["cash"]) == Shed.garage_money
		and not TvChannels.money_data(me).has("placeholder") and TvChannels.contracts_data()["offered"] is Array
		and TvChannels.afford_data(me)["items"].size() > 3 and int(TvChannels.afford_data(me)["items"][0]["price"]) > 0,
		"the money pages have real numbers, and the contracts page a list")
	if get_node_or_null("/root/Progress") == null:
		check(TvChannels.xp_data().get("offline", false), "with no XP system the XP page says it's starting up")
	# Every page draws.
	var dash := Dashboard.new("crew", 2.0)
	add_child(dash)
	var drawn := [0]
	dash._page.draw.connect(func(): drawn[0] += 1)
	dash._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for ch in TvChannels.CHANNELS:
		if ch != "crew":
			dash.show_page(TvChannels.page_kind(ch), TvChannels.page_data(ch))
			await get_tree().process_frame
			await get_tree().process_frame
	var stub := _xp_stub()
	if stub:
		var xp := TvChannels.xp_data()
		check(not xp.get("offline", false) and xp["players"].size() == Shed.crew.size() and xp["me"]["goals"].size() == 2,
			"with the XP system running the page lists everyone's level and your goals")
		dash.show_page("xp", xp)
		await get_tree().process_frame
		await get_tree().process_frame
		stub.queue_free()
	dash.show_osd("CH 2  CREW BOARD")
	check(dash.osd_text() == "CH 2  CREW BOARD", "the channel name flashes up on the screen")
	dash._process(Dashboard.OSD_TIME + 0.1)
	check(dash.osd_text() == "", "and goes again after a moment")
	print("    (pages drawn %d times)" % drawn[0])
	dash.queue_free()
	Shed.stop()


## In the real shed: look at a screen and press R to change its channel; the bins by the door.
func _test_tv_and_bins_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	# The screen over bay 1.
	var screen: Dashboard = main.workshop.screens()["bay0"]
	w.place(Transform3D(Basis(), Vector3(screen.global_position.x, 0.0, screen.global_position.z + 1.6)))
	await _aim_point(w, screen.global_position)
	check(w.target.get("kind", "") == "screen" and w.target.get("screen", "") == "bay0", "you can look at a bay screen (%s)" % str(w.target))
	check(w.info.contains("CH 1  BAY 1") and w.info.contains("next channel"), "the panel says what's on and how to change it")
	_press("alt_act")
	await get_tree().process_frame
	check(Shed.screen_channel("bay0")["ch"] == "live", "R changes the bay screen's channel")
	main.workshop._refresh_dashboards()
	check(screen.osd_text() == "CH 2  LIVE: NOBODY RIDING", "the new channel's name shows on the screen (%s)" % screen.osd_text())
	_press("spray_finish")
	await get_tree().process_frame
	check(Shed.screen_channel("bay0")["ch"] == "bay", "T goes back a channel")
	# A bought TV on the back wall shows the live channel, or a page when nobody's riding.
	Shed.request({"a": "order_furniture", "model": "tv_136"})
	var tv := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "tv":
			tv = id
	Shed.request({"a": "grab", "furniture": tv})
	Shed.request({"a": "release", "furniture": tv, "xf": Transform3D(Basis(Vector3.UP, -PI * 0.5), Workshop.CENTER + Vector3(Workshop.HALF.x - 0.03, 2.6, 2.6))})
	await get_tree().process_frame
	main.workshop._refresh_dashboards()
	var board: Dashboard = main.workshop.screens()["f%d" % tv]
	check(board.kind == "nobody" and not board.is_live(), "with nobody out, the TV's live channel says so")
	w.place(Transform3D(Basis(), Workshop.CENTER + Vector3(Workshop.HALF.x - 2.0, 0.0, 2.6)))
	await _aim_point(w, board.global_position)
	check(w._screen_key() == "f%d" % tv, "you can look at the TV (%s)" % str(w.target))
	_press("alt_act")
	_press("alt_act")
	await get_tree().process_frame
	main.workshop._refresh_dashboards()
	check(board.kind == "xp", "two presses on: the XP page")
	# Hanging a big TV next to a corner slides it clear of the side wall.
	var size: Vector3 = Equipment.get_model("tv_136")["size"]
	w.place(Transform3D(Basis(), Workshop.CENTER + Vector3(Workshop.HALF.x - 1.5, 0.0, Workshop.HALF.y - 0.6)))
	await _aim_point(w, Workshop.CENTER + Vector3(Workshop.HALF.x, 2.2, Workshop.HALF.y - 0.4))
	var hang: Transform3D = w._wall_transform(size)
	check(w._on_wall and hang.origin.z + size.x * 0.5 <= Workshop.CENTER.z + Workshop.HALF.y + 0.03,
		"a big TV hung near a corner doesn't poke through the wall round it (%.2f)" % (hang.origin.z + size.x * 0.5 - Workshop.CENTER.z - Workshop.HALF.y))
	# The three bins by the door.
	var tyre := _hold_new("sport_road")
	var bin_at := Workshop.CENTER + Vector3(Workshop.BINS["plastic"][0], 0.0, Workshop.HALF.y - 1.5)
	w.place(Transform3D(Basis(Vector3.UP, PI), bin_at))
	await _aim_point(w, Workshop.CENTER + Vector3(Workshop.BINS["plastic"][0], 0.8, Workshop.HALF.y - 0.4))
	check(w.target.get("bin", "") == "plastic", "the plastic recycling bin is by the door (%s)" % str(w.target))
	check(w.plan.get("blocked", "").contains("rubber") and w.info.contains("Not in here"), "it won't take a tyre, and says why (%s)" % w.plan.get("blocked", ""))
	await _aim_point(w, Workshop.CENTER + Vector3(Workshop.BINS["general"][0], 0.8, Workshop.HALF.y - 0.4))
	check(w.target.get("bin", "") == "general", "general waste is next to it")
	await _hold_act(main)
	check(not Shed.items.has(tyre), "the tyre goes in general waste")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = true
	return ev


func _test_key_bindings() -> void:
	# Keep the player's own settings file as it was.
	var had := FileAccess.file_exists(Settings.PATH)
	var before := FileAccess.get_file_as_string(Settings.PATH) if had else ""
	Settings.reset_bindings()
	check(Settings.clashes().is_empty(), "the default bindings don't clash %s" % str(Settings.clashes().slice(0, 3)))
	check(Settings.binding_codes("ping").has("mouse:%d" % MOUSE_BUTTON_MIDDLE) and not Settings.binding_codes("spray_finish").has("mouse:%d" % MOUSE_BUTTON_MIDDLE),
		"ping keeps the middle mouse button and the spray finish has moved off it (%s)" % Settings.binding_text("spray_finish", false))
	var listed := Settings.ACTIONS.map(func(a): return a[0])
	var missing := InputMap.get_actions().filter(func(a): return not str(a).begins_with("ui_") and not listed.has(str(a)))
	check(missing.is_empty(), "every action is in the key bindings list %s" % str(missing))
	# Rebind ping's key: saved in the settings file and put back on at the next start.
	Settings.rebind("ping", _key(KEY_J))
	check(Settings.binding_text("ping", false) == "J" and Settings.binding_text("ping", true) == "D-pad right",
		"rebinding ping's key leaves its pad button (%s / %s)" % [Settings.binding_text("ping", false), Settings.binding_text("ping", true)])
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	var saved := Array(cfg.get_value("bindings", "ping", []))
	check(saved.has("key:%d" % KEY_J) and saved.has("joy:%d" % JOY_BUTTON_DPAD_RIGHT) and saved.size() == 2 and not cfg.has_section_key("bindings", "act"),
		"the new binding is saved, and only what changed (%s)" % str(saved))
	InputMap.action_erase_events("ping")
	for e in Settings._defaults["ping"]:
		InputMap.action_add_event("ping", e)
	Settings.load_settings()
	check(_key(KEY_J).is_action_pressed("ping") and not _key(KEY_G).is_action_pressed("ping"), "a saved binding is put back when the game starts")
	# Clashes: the same button doing two things in the same place.
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	Settings.rebind("ping", rmb)
	var clash := Settings.clashes()
	check(clash.any(func(c): return [c["a"], c["b"]].has("ping") and [c["a"], c["b"]].has("alt_act") and c["context"] == "foot"),
		"ping on right mouse clashes with the second work button on foot")
	var tab := KeybindTab.new()
	add_child(tab)
	await get_tree().process_frame
	check(tab.warning().contains("Right mouse") and tab.warning().contains("Ping") and tab.warning().contains("on foot"),
		"the Key bindings tab warns about it (%s)" % tab.warning())
	Settings.rebind("ping", _key(KEY_G))
	Settings.rebind("horn", _key(KEY_N))
	check(Settings.clashes().is_empty(), "a key that names a bike on foot can sound the horn when riding: no clash")
	Settings.rebind("spray_finish", _key(KEY_G))
	check(Settings.clashes().any(func(c): return [c["a"], c["b"]].has("spray_finish") and [c["a"], c["b"]].has("ping")),
		"a spray key clashes with an on-foot one")
	# Click a binding in the tab, then press the key or pad button.
	tab.listen("rename", false)
	get_viewport().push_input(_key(KEY_O))
	check(Settings.binding_text("rename", false) == "O" and tab.listening.is_empty(), "click and press a key: it's bound (%s)" % Settings.binding_text("rename", false))
	tab.listen("rename", true)
	get_viewport().push_input(_key(KEY_P))
	check(not tab.listening.is_empty(), "waiting for a pad button, a key doesn't count")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_STICK
	pad.pressed = true
	get_viewport().push_input(pad)
	check(Settings.binding_text("rename", true) == "L3", "a pad button binds the pad column (%s)" % Settings.binding_text("rename", true))
	tab.listen("rename", false)
	get_viewport().push_input(_key(KEY_ESCAPE))
	check(tab.listening.is_empty() and Settings.binding_text("rename", false) == "O", "Esc cancels")
	Settings.clear_binding("rename", false)
	check(Settings.binding_text("rename", false) == "", "Clear takes a binding off")
	Settings.reset_bindings()
	check(Settings.clashes().is_empty() and Settings.binding_text("rename", false) == "N" and Settings.binding_text("ping", false) == "G / Middle mouse",
		"Reset to defaults puts it all back (%s)" % Settings.binding_text("ping", false))
	tab.queue_free()
	if had:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(before)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	await get_tree().process_frame


## A pad button pressed and let go, through the viewport like a real one.
func _pad(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button as JoyButton
		ev.pressed = pressed
		ev.pressure = 1.0 if pressed else 0.0
		get_viewport().push_input(ev)
	await get_tree().process_frame


func _test_pad_menus() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	for i in 3:
		await get_tree().physics_frame
	var pc: PartsComputer = main.computer
	main._open_computer()
	await get_tree().process_frame
	await get_tree().process_frame
	var focus := get_viewport().gui_get_focus_owner()
	check(focus != null and pc._kinds.is_ancestor_of(focus), "the parts computer opens with the pad's focus on a kind of part (%s)" % str(focus))
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var kind_btn := get_viewport().gui_get_focus_owner()
	check(kind_btn != focus and pc._kinds.is_ancestor_of(kind_btn), "the d-pad moves down the kinds")
	await _pad(JOY_BUTTON_A)
	await get_tree().process_frame
	focus = get_viewport().gui_get_focus_owner()
	check(pc._kind == str(kind_btn.get_meta("kind")) and focus != null and pc._variants.is_ancestor_of(focus),
		"A picks the kind and goes to its parts (%s)" % pc._kind)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	focus = get_viewport().gui_get_focus_owner()
	check(focus != null and pc._part == str(focus.get_meta("part", "")), "moving down the parts shows each one (%s)" % pc._part)
	await _pad(JOY_BUTTON_A)
	check(get_viewport().gui_get_focus_owner() == pc._order, "A on a part goes to the Order button")
	var count := Shed.items.size()
	await _pad(JOY_BUTTON_A)
	check(Shed.items.size() == count + 1, "and A again orders it (%s)" % pc._part)
	await _pad(JOY_BUTTON_B)
	check(pc._variants.is_ancestor_of(get_viewport().gui_get_focus_owner()), "B goes back to the parts")
	await _pad(JOY_BUTTON_B)
	check(pc._kinds.is_ancestor_of(get_viewport().gui_get_focus_owner()), "B again goes back to the kinds")
	var sec := pc._section
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(pc._section != sec and pc._kinds.is_ancestor_of(get_viewport().gui_get_focus_owner()), "RB goes to the next aisle (%s)" % pc._section)
	await _pad(JOY_BUTTON_B)
	await get_tree().process_frame
	check(not pc.visible, "and B once more closes the computer")
	# The dyno desk.
	main._open_tuning()
	await get_tree().process_frame
	check(get_viewport().gui_get_focus_owner() == main.tuning._run, "the dyno desk opens with the focus on Run the dyno")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await get_tree().process_frame
	check(main.tuning._tabs.current_tab == 1 and get_viewport().gui_get_focus_owner() != null, "RB turns the desk's tabs")
	await _pad(JOY_BUTTON_B)
	check(not main.tuning.visible, "B closes the dyno desk")
	# The Esc menu.
	main.menu.show_pause()
	main._capture_mouse(false)
	await get_tree().process_frame
	check(get_viewport().gui_get_focus_owner() == main.menu._resume, "the menu opens on Back to the shed")
	var tab: int = main.menu._tabs.current_tab
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(main.menu._tabs.current_tab != tab, "RB turns the menu's tabs")
	await _pad(JOY_BUTTON_B)
	await get_tree().process_frame
	check(not main.menu.visible, "B goes back to the shed")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	# Back to the keyboard and mouse for the tests after this one.
	Controls.active_device = -1


func _test_board_posters() -> void:
	Shed.start_new("Tester", 12)
	Shed.request({"a": "board_poster", "name": "Nothing"})
	check(Shed.posters.is_empty(), "a clean board can't be made into a poster")
	Shed.board_request({"a": "board_draw", "id": 501, "c": 2, "w": 6.0, "from": 0, "done": true,
		"pts": PackedVector2Array([Vector2(100, 100), Vector2(500, 300)])})
	Shed.board_request({"a": "board_text", "id": 502, "c": 1, "s": 38, "at": Vector2(600, 80), "text": "Bay 3 plan"})
	Shed.request({"a": "board_poster", "name": "  Build plan  "})
	check(Shed.posters.size() == 1, "the board is saved as a poster design")
	var design: int = Shed.posters.keys()[0]
	var p: Dictionary = Shed.posters[design]
	check(p["name"] == "Build plan" and p["by"] == "Tester", "named, and by who made it (%s)" % str(p))
	var marks := Shed.poster_marks(design)
	check(marks.size() == 2 and marks[1].get("text", "") == "Bay 3 plan", "the design keeps the drawing as it was (%d marks)" % marks.size())
	Shed.board_request({"a": "board_clear"})
	check(Shed.poster_marks(design).size() == 2, "wiping the board leaves the poster as it was")
	check(not Equipment.by_kind("poster").has(Equipment.BOARD_POSTER), "the blank whiteboard print isn't sold on its own")
	# The parts computer lists it with the posters, and orders it.
	var pc := PartsComputer.new()
	add_child(pc)
	pc._show_section("shed")
	pc._show_kind("eq:poster")
	var entry: Button = null
	for b in pc._variants.get_children():
		if b is Button and b.get_meta("part", "") == "design:%d" % design:
			entry = b
	check(entry != null and entry.text == "Build plan", "the parts computer's posters list the whiteboard poster")
	pc._pick_part("design:%d" % design)
	check(pc._title.text == "Build plan" and pc._desc.text.contains("Tester"), "with its name and who drew it")
	pc._order.pressed.emit()
	var fid := 0
	for id in Shed.furniture:
		if int(Shed.furniture[id].get("design", 0)) == design:
			fid = id
	check(fid != 0 and Shed.furniture[fid]["model"] == Equipment.BOARD_POSTER and Shed.furniture[fid]["kind"] == "poster",
		"ordering it brings a poster of that drawing")
	Shed.request({"a": "order_furniture", "model": Equipment.BOARD_POSTER, "design": 999999})
	check(Shed.furniture.values().filter(func(f): return f["model"] == Equipment.BOARD_POSTER).size() == 1, "a poster design that doesn't exist can't be ordered")
	pc.queue_free()
	# It hangs in the shed showing the drawing, and it's all kept in the save.
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	Shed.load_state(copy, "Tester")
	await get_tree().process_frame
	await get_tree().process_frame
	check(Shed.posters.size() == 1 and Shed.poster_marks(design).size() == 2 and int(Shed.furniture[fid].get("design", 0)) == design,
		"the poster design and the ordered poster are kept in the save")
	var view: Node = main.workshop.furniture_nodes.get(fid, null)
	var print_node: BoardPrint = view.get_node_or_null("BoardPrint") if view else null
	check(print_node != null and print_node.mark_count() == 2, "the poster in the shed shows the whiteboard drawing")
	# Old saves, made before posters, still open.
	copy.erase("posters")
	copy.erase("blobs")
	Shed.load_state(copy, "Tester")
	check(Shed.posters.is_empty(), "an older save without posters opens with none")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## A made-up picture to put on the board: a colour gradient with noise, so it doesn't pack tiny.
func _test_picture(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(float(x) / w, float(y) / h, rng.randf(), 1.0))
	return img


func _test_board_images() -> void:
	var pic := _test_picture(900, 450)
	var data := Shed.pack_image(pic)
	var back := Image.new()
	check(not data.is_empty() and data.size() <= Shed.MAX_IMAGE_BYTES and back.load_webp_from_buffer(data) == OK,
		"a picture from the PC is packed small (%d bytes)" % data.size())
	check(back.get_width() == BoardData.IMAGE_PX and back.get_height() == BoardData.IMAGE_PX / 2, "and shrunk to 512 px across (%dx%d)" % [back.get_width(), back.get_height()])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var board: Whiteboard = get_tree().get_first_node_in_group("whiteboard")
	var face: Vector3 = board.global_position
	w.place(Transform3D(Basis(), Vector3(face.x, 0.0, face.z - 1.4)))
	w.rotation.y = PI
	w._pitch = 0.0
	w._look(0.0, -atan2(Walker.EYE - face.y, 1.4))
	for i in 5:
		await get_tree().physics_frame
	# Put it up from a file, as the file dialog would.
	var base_snapshot := var_to_bytes(Shed._snapshot()).size()
	var path := "user://test_board_picture.png"
	pic.save_png(path)
	var id := board.add_image_file(path, BoardData.PX * 0.5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(id != 0 and BoardData.find(Shed.board, id) >= 0, "a picture from a file goes up on the board")
	var m: Dictionary = Shed.board["marks"][BoardData.find(Shed.board, id)]
	check(BoardData.bounds(m).has_point(BoardData.PX * 0.5) and (m["sz"] as Vector2).x <= Whiteboard.IMAGE_FIT.x + 0.1,
		"where you're looking, at a sensible size (%s)" % str(m["sz"]))
	check(Shed.image_texture(int(m["img"])) != null and BoardData.ink_at(Shed.board, BoardData.PX * 0.5) == BoardData.IMAGE, "it shows as a picture")
	for i in 2:
		await get_tree().process_frame
	check(board._nodes.get(id) is TextureRect, "drawn on the board")
	check(board.add_image_file("user://no_such_picture.png", BoardData.PX * 0.5) == 0, "a missing file is turned down")
	# Move it with M, size it with the wheel or + and -, put it down with M.
	var at0: Vector2 = m["at"]
	var sz0: Vector2 = m["sz"]
	_press("board_move")
	await get_tree().process_frame
	check(board.carrying == id, "M on a picture takes hold of it")
	for i in 20:
		w._look(0.004, 0.0)
		await get_tree().process_frame
	_press("board_bigger")
	_press("tool_next")
	await get_tree().process_frame
	_press("board_move")
	await get_tree().process_frame
	m = Shed.board["marks"][BoardData.find(Shed.board, id)]
	check(board.carrying == 0 and (m["at"] as Vector2).x != at0.x, "it follows the crosshair and M puts it down (%s -> %s)" % [str(at0), str(m["at"])])
	check((m["sz"] as Vector2).x > sz0.x * 1.25 and absf((m["sz"] as Vector2).aspect() - sz0.aspect()) < 0.01,
		"+ and the wheel make it bigger, keeping its shape (%s)" % str(m["sz"]))
	Shed.board_request({"a": "board_move", "id": id, "at": Vector2(-5000, 9000), "sz": Vector2(99999, 2)})
	m = Shed.board["marks"][BoardData.find(Shed.board, id)]
	check((m["sz"] as Vector2).x <= BoardData.PX.x and (m["sz"] as Vector2).y >= BoardData.IMAGE_MIN and (m["at"] as Vector2).y <= BoardData.PX.y,
		"it can't be moved off the board or sized past it")
	# The bytes go out in chunks small enough to send; a player joining gets the board without them.
	var with_pic := var_to_bytes(Shed._snapshot()).size()
	check(with_pic < base_snapshot + 1000, "the shed snapshot leaves the picture's bytes out (%d bytes more)" % (with_pic - base_snapshot))
	var big := Shed.pack_image(_test_picture(512, 512))
	var n := ceili(big.size() / float(Shed.BLOB_CHUNK))
	check(n >= 2, "a busy picture takes several chunks (%d)" % n)
	var order := range(n)
	order.reverse()
	for k in order.slice(0, n - 1):
		Shed._blob_chunk(777, k, n, big.slice(k * Shed.BLOB_CHUNK, (k + 1) * Shed.BLOB_CHUNK))
	check(not Shed.blobs.has(777), "a picture isn't used till every chunk is in")
	var last: int = order[n - 1]
	Shed._blob_chunk(777, last, n, big.slice(last * Shed.BLOB_CHUNK, (last + 1) * Shed.BLOB_CHUNK))
	check(Shed.blobs.get(777, PackedByteArray()) == big and Shed.image_ok(777), "then it's put back together whole, in any order")
	Shed._blob_chunk(778, 0, 1, PackedByteArray([1, 2, 3]))
	Shed.board_request({"a": "board_image", "id": 9001, "img": 778, "at": Vector2(10, 10), "sz": Vector2(100, 100)})
	check(BoardData.find(Shed.board, 9001) < 0, "something that isn't a picture isn't put up")
	# Undo and the eraser take pictures off like marks.
	var second := board.add_image(_test_picture(64, 64), Vector2(1000, 450))
	check(second != 0 and BoardData.image_count(Shed.board) == 2, "a second picture goes up")
	Shed.board_request({"a": "board_undo"})
	check(BoardData.find(Shed.board, second) < 0 and BoardData.find(Shed.board, id) >= 0, "undo takes the last picture back off")
	var r := BoardData.bounds(Shed.board["marks"][BoardData.find(Shed.board, id)])
	var rub := PackedVector2Array()
	var y := r.position.y
	var row := 0
	while y <= r.end.y + 36.0:
		var xs := [r.position.x - 5.0, r.end.x + 5.0]
		if row % 2 == 1:
			xs.reverse()
		rub.append(Vector2(xs[0], minf(y, r.end.y)))
		rub.append(Vector2(xs[1], minf(y, r.end.y)))
		y += 36.0
		row += 1
	Shed.board_request({"a": "board_draw", "id": 9100, "c": BoardData.ERASER, "from": 0, "done": true, "pts": rub})
	check(BoardData.find(Shed.board, id) < 0, "rubbing all over a picture rubs it out")
	# No more than so many on the board.
	var added := 0
	for i in BoardData.MAX_IMAGES + 2:
		if board.add_image(_test_picture(32, 32), Vector2(80 + i * 60, 80)) != 0:
			added += 1
	check(added == BoardData.MAX_IMAGES and BoardData.image_count(Shed.board) == BoardData.MAX_IMAGES,
		"the board takes %d pictures at most (%d)" % [BoardData.MAX_IMAGES, added])
	# Saved with the shed, and back again.
	var keep: Dictionary = Shed.board["marks"][-1]
	var copy: Dictionary = str_to_var(var_to_str(main.saver.capture()["shed"]))
	check(copy["blobs"].size() == BoardData.MAX_IMAGES, "the save keeps the pictures in use, and not the rest (%d)" % copy["blobs"].size())
	Shed.load_state(copy, "Tester")
	check(BoardData.image_count(Shed.board) == BoardData.MAX_IMAGES and Shed.image_texture(int(keep["img"])) != null,
		"opening the save puts the pictures back on the board")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame



# ---------------------------------------------------------------------------- carrying, snapping, surfaces, whiteboard, boxes

## A loose part made up and put straight into your hands.
func _in_hands(part: String, dirt := 0.0, rust := 0.0) -> int:
	var id := Shed._new_item(part, rust, dirt, rust)
	Shed._move(id, "held", Shed.me())
	return id


## Puts what you're holding down on a surface at the clear place nearest `at`; false if there's no room.
func _set_down_near(key: String, at := Vector2.ZERO) -> bool:
	var held := Shed.held_by(Shed.me())
	var place = Shed.find_room(key, held, at)
	if not (place is Transform3D):
		return false
	Shed.request({"a": "set_down", "top": key, "xf": place})
	return Shed.held_by(Shed.me()) == 0


func _first_furniture(model: String) -> int:
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == model:
			return id
	return 0


func _test_carry_and_snap() -> void:
	# How far out you hold equipment: arm's length plus the wheel, within limits.
	check(Walker.carry_distance(1.0, 0.0) == 1.0 and Walker.carry_distance(1.0, 0.5) == 1.5, "the mouse wheel pushes carried equipment further out")
	check(is_equal_approx(Walker.carry_distance(1.0, 99.0), 1.0 + Walker.CARRY_MAX) and is_equal_approx(Walker.carry_distance(1.0, -99.0), 1.0 + Walker.CARRY_MIN),
		"it stays between %.2f and %.2f m beyond arm's length" % [Walker.CARRY_MIN, Walker.CARRY_MAX])
	check(Placement.snap_yaw(0.3) == 0.0 and is_equal_approx(Placement.snap_yaw(1.4), PI * 0.5) and is_equal_approx(Placement.snap_yaw(-3.0), -PI),
		"snapping squares equipment up in quarter turns")
	# A corner of two walls out of the way of everything, to snap against.
	var corner := Vector3(600.0, 0.0, 600.0)
	var walls := Node3D.new()
	add_child(walls)
	for w in [[corner + Vector3(-0.1, 1.0, 5.0), Vector3(0.2, 2.0, 10.0)], [corner + Vector3(5.0, 1.0, -0.1), Vector3(10.0, 2.0, 0.2)]]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		cs.shape = box
		body.add_child(cs)
		body.position = w[0]
		walls.add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().get_world_3d().direct_space_state
	var size := Vector3(1.2, 1.0, 0.6)
	var none: Array[RID] = []
	var free := Placement.snap(space, Transform3D(Basis(Vector3.UP, 0.2), corner + Vector3(3.0, 0.0, 3.0)), size, none)
	check((free["walls"] as Array).is_empty() and (free["xf"] as Transform3D).origin.is_equal_approx(corner + Vector3(3.0, 0.0, 3.0))
		and is_zero_approx((free["xf"] as Transform3D).basis.get_euler().y), "away from walls it only squares up")
	var by_wall := Placement.snap(space, Transform3D(Basis(Vector3.UP, 0.2), corner + Vector3(0.85, 0.0, 3.0)), size, none)
	var at: Vector3 = (by_wall["xf"] as Transform3D).origin
	check((by_wall["walls"] as Array).size() == 1 and absf(at.x - (corner.x + 0.6 + Placement.GAP)) < 0.005 and absf(at.z - (corner.z + 3.0)) < 0.005,
		"near a wall it slides flush against it (%s)" % str(at - corner))
	var cornered := Placement.snap(space, Transform3D(Basis(Vector3.UP, -0.1), corner + Vector3(0.85, 0.0, 0.5)), size, none)
	at = (cornered["xf"] as Transform3D).origin
	check((cornered["walls"] as Array).size() == 2 and absf(at.x - (corner.x + 0.6 + Placement.GAP)) < 0.005
		and absf(at.z - (corner.z + 0.3 + Placement.GAP)) < 0.005, "near a corner it goes tight into it (%s)" % str(at - corner))
	var turned := Placement.snap(space, Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.2), corner + Vector3(0.6, 0.0, 3.0)), size, none)
	at = (turned["xf"] as Transform3D).origin
	check(absf(at.x - (corner.x + 0.3 + Placement.GAP)) < 0.005, "turned a quarter, its narrow side goes to the wall (%s)" % str(at - corner))
	walls.queue_free()
	# In the shed: carry a stool about, wheel it out, and the tool stays the same.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var kept_snap: bool = Settings.snap_placement
	Settings.snap_placement = true
	Shed.request({"a": "order_furniture", "model": "seat_stool"})
	var stool := _first_furniture("seat_stool")
	var middle := Workshop.CENTER + Vector3(0.0, 0.0, 1.0)
	Shed.furniture[stool]["xf"] = Transform3D(Basis(), middle)
	w.place(Transform3D(Basis(Vector3.UP, 0.3), middle + Vector3(0.0, 0.0, 1.2)))
	Shed.request({"a": "grab", "furniture": stool})
	for i in 3:
		await get_tree().physics_frame
	var near_xf: Transform3D = w._push_transform(stool)
	var flat := (near_xf.origin - w.global_position) * Vector3(1, 0, 1)
	_press("tool_prev")
	_press("tool_prev")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(is_equal_approx(w.carry_reach, 2.0 * Walker.CARRY_STEP) and w.tool == "hands", "two clicks of the wheel push it out, and don't change tool")
	var far_xf: Transform3D = w._push_transform(stool)
	var far := (far_xf.origin - w.global_position) * Vector3(1, 0, 1)
	check(absf(far.length() - flat.length() - 2.0 * Walker.CARRY_STEP) < 0.05, "it's held half a metre further away (%.2f -> %.2f m)" % [flat.length(), far.length()])
	check(is_zero_approx(wrapf(far_xf.basis.get_euler().y, -PI, PI)) and w.snap_text() == "", "in the open it squares up but has no wall to snap to")
	check(w._ghost != null and w._ghost.visible and w.info.contains("Mouse wheel") and w.info.contains("snapping off"),
		"an outline shows where it'll go, and the panel says how to move and snap it (%s)" % w.info)
	for i in 30:
		_press("tool_next")
	await get_tree().physics_frame
	check(is_equal_approx(w.carry_reach, Walker.CARRY_MIN), "pulled in, it stops just short of you")
	_press("alt_act")
	await get_tree().physics_frame
	check(not Settings.snap_placement, "R while carrying turns snapping off")
	var loose: Transform3D = w._push_transform(stool)
	check(absf(wrapf(loose.basis.get_euler().y - 0.3, -PI, PI)) < 0.01, "with snapping off it turns with you freely")
	_press("alt_act")
	await get_tree().physics_frame
	check(Settings.snap_placement, "and back on again")
	_press("interact")
	for i in 3:
		await get_tree().physics_frame
	check(Shed.moving(Shed.me()) == 0 and not w._ghost.visible, "F puts it down and the outline goes")
	Settings.snap_placement = kept_snap
	Settings.save_settings()
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_free_surfaces() -> void:
	Shed.start_new("Tester", 21)
	var me := Shed.me()
	# The shed's repair bench was rated for two parts; now it takes as many as fit on top.
	var machine := _first_furniture("repair_standard")
	var key := "f%d" % machine
	check(Shed.surface(key).get("kind", "") == "repair" and Shed.surface_items(key).is_empty(), "the repair bench has a free top")
	var on := []
	for i in 24:
		_in_hands("stock_muffler" if i % 3 == 0 else "flat_bar", 0.2, 0.6)
		if _set_down_near(key, Vector2(-0.7 + float(i % 6) * 0.28, -0.3 + float(i % 4) * 0.2)):
			on.append(Shed.items.keys().max())
		else:
			Shed._erase_item(Shed.held_by(me))
	check(on.size() > 2, "far more than two parts go on the repair bench (%d)" % on.size())
	var rects := Shed._surface_rects(key)
	var overlaps := 0
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			if (rects[a][1] as Rect2).grow(-Shed.SURFACE_GAP).intersects(rects[b][1]):
				overlaps += 1
	check(overlaps == 0, "none of them overlap")
	var spots := Shed.furniture_spots(machine)
	check(on.all(func(id): return Shed.items[id]["at"] == "spot" and spots.has(Shed.items[id]["ref"]) and Shed.items[id].get("place") is Transform3D),
		"each sits on the machine where it was put down")
	# A part dropped right on another is refused by the host.
	_in_hands("iridium_plugs")
	var taken: Transform3D = Shed.item_place(on[0])
	check(Shed.check(me, {"a": "set_down", "top": key, "xf": taken}).contains("in the way"), "you can't put a part down on top of another")
	var gap = Shed.find_room(key, Shed.held_by(me), Vector2(taken.origin.x, taken.origin.z))
	check(gap == null or Shed.surface_fits(key, Shed.held_by(me), gap) == "", "looking for room next to it finds a real gap, or says it's full")
	Shed._erase_item(Shed.held_by(me))
	# The grinder still does the lot, a little slower with more on than it's rated for.
	var batch := Shed.repair_batch(str(spots[0]))
	check(batch.size() == on.size(), "the grinder works on every part on it (%d)" % batch.size())
	var two := Shed.repair_time(batch.slice(0, 2))
	check(Shed.repair_time(batch) > two * float(batch.size()) / 2.0 * 0.99, "a pile of parts takes longer than the rated two")
	Shed.request({"a": "repair_many", "items": batch})
	check(on.all(func(id): return Shed.items[id]["rust"] == 0.0 and Shed.items[id]["wear"] == 0.0), "every part on it comes off restored")
	# The parts washer cleans everything in it; more than it's rated for and each part goes slower.
	var washer := _first_furniture("washer_standard")
	var wkey := "f%d" % washer
	var dirty := []
	for i in 6:
		_in_hands("paper_oil", 0.9)
		if _set_down_near(wkey, Vector2(-0.5 + i * 0.2, 0.0)):
			dirty.append(Shed.items.keys().max())
	check(dirty.size() == 6, "six oil filters go in a two-part washer")
	Shed._process(1.0)
	var rate := float(Equipment.get_model("washer_standard")["rate"])
	var drop := 0.9 - float(Shed.items[dirty[0]]["dirt"])
	check(dirty.all(func(id): return Shed.items[id]["dirt"] < 0.9), "the washer cleans all six")
	check(absf(drop - rate * 2.0 / 6.0) < 0.01, "six in a washer rated for two go at a third of the speed (%.3f)" % drop)
	# Boxes stay out of the washer, and a frame is too big for a small one.
	var box := _in_hands("paper_oil")
	Shed.items[box]["boxed"] = true
	check(Shed.check(me, {"a": "set_down", "top": wkey, "xf": Transform3D(Basis(), Vector3(0.0, 0.86, 0.0))}) == "Unpack it first.", "boxed parts can't go in the washer")
	Shed._erase_item(box)
	Shed.request({"a": "order_furniture", "model": "washer_compact"})
	var small := "f%d" % _first_furniture("washer_compact")
	var frame := _in_hands("steel_cradle")
	check(Shed.check(me, {"a": "set_down", "top": small, "xf": Transform3D(Basis(), Vector3(0.0, 0.8, 0.0))}).contains("too big"),
		"a frame is too big for the benchtop washer (%s)" % Shed.check(me, {"a": "set_down", "top": small, "xf": Transform3D(Basis(), Vector3(0.0, 0.8, 0.0))}))
	Shed._erase_item(frame)
	# The shed's own workbench takes more than its four old places.
	var bench_had := Shed.surface_items("bench").size()
	var added := 0
	for i in 10:
		_in_hands("iridium_plugs")
		if _set_down_near("bench", Vector2(-0.1, -0.35 + i * 0.08)):
			added += 1
		else:
			Shed._erase_item(Shed.held_by(me))
	check(Shed.surface_items("bench").size() == bench_had + added and added == 10, "the workbench holds %d parts, not just four" % (bench_had + added))
	frame = Shed.surface_items("bench").filter(func(id): return Shed.items[id]["part"] == "iridium_plugs")[0]
	check(Shed.spot_role(str(Shed.items[frame]["ref"])) == "bench" and Shed.spot_transform(str(Shed.items[frame]["ref"])).origin.distance_to(
		Shed.surface("bench")["xf"] * Shed.item_place(frame).origin) < 0.001, "it's drawn where it was put")
	Shed.request({"a": "take", "spot": str(Shed.items[frame]["ref"])})
	check(Shed.held_by(me) == frame and not Shed.items[frame].has("place"), "picked up again it leaves its place")
	Shed._erase_item(frame)
	# An older save: parts in the washer's numbered places still count, get cleaned and are kept clear of.
	var old := Shed._new_item("paper_oil", 0.0, 0.7, 0.0)
	var old_spot := "washer_%d_%d" % [washer, 1]
	for id in Shed.surface_items(wkey):
		Shed._erase_item(id)
	Shed._move(old, "spot", old_spot)
	check(Shed.surface_items(wkey) == [old] and Shed.item_place(old) == Equipment.local_place("washer_standard", 1),
		"a part left in a numbered place is still on the washer, in its old place")
	Shed._process(0.5)
	check(Shed.items[old]["dirt"] < 0.7, "and the washer still cleans it")
	_in_hands("paper_oil")
	var old_at: Transform3D = Shed.item_place(old)
	check(Shed.check(me, {"a": "set_down", "top": wkey, "xf": old_at}).contains("in the way"), "a new part can't go on top of it")
	# What's put down survives the trip to everyone else, and a save.
	var placed: int = Shed.held_by(me)
	check(_set_down_near(wkey, Vector2(-0.4, 0.0)), "a part goes in beside it")
	var place: Transform3D = Shed.items[placed]["place"]
	var snap: Dictionary = bytes_to_var(var_to_bytes(Shed._snapshot()))
	Shed._sync(snap)
	check(Shed.items[placed]["place"] == place and Shed.surface_items(wkey).has(placed), "the place goes out with the shed state")
	var saved: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	Shed.load_state(saved, "Tester")
	check(Shed.items[placed]["place"] == place and Shed.items[placed]["at"] == "spot", "and comes back from a save")
	# Something held when the shed was saved goes back on the workbench, wherever there's room.
	var held := _in_hands("iridium_plugs")
	Shed.load_state(str_to_var(var_to_str(Shed._snapshot())), "Tester")
	check(Shed.items[held]["at"] == "spot" and Shed.surface_of_spot(str(Shed.items[held]["ref"])) == "bench", "a part in your hands goes back on the bench")
	Shed.stop()


func _test_surface_session() -> void:
	# In the game: hold a part, look at the top of the repair bench and put it down there.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var machine := _first_furniture("repair_standard")
	var key := "f%d" % machine
	var mxf: Transform3D = Shed.furniture[machine]["xf"]
	var top := Equipment.work_height("repair_standard")
	var spot_at: Vector3 = mxf * Vector3(-0.3, top, 0.0)
	w.place(Transform3D(Basis(), mxf * Vector3(-0.3, 0.0, 1.3)))
	var count := 0
	for i in 5:
		_in_hands("iridium_plugs")
		Shed.changed.emit()
		await _aim_point(w, spot_at)
		check(w.target.get("kind", "") in ["top", "spot"] and w.plan.get("action", {}).get("a", "") == "set_down" and w.plan["blocked"] == "",
			"looking at the bench top with a part in hand offers to put it down (%s, %s)" % [str(w.target.get("kind", "")), str(w.plan.get("blocked", w.plan))])
		await _hold_act(main)
		if Shed.held_by(Shed.me()) == 0:
			count += 1
	check(count == 5 and Shed.surface_items(key).size() == 5, "five spark plugs go down in the same spot, each beside the last (%d)" % Shed.surface_items(key).size())
	Shed.changed.emit()
	await get_tree().process_frame
	var plug: int = Shed.surface_items(key)[0]
	await _aim_point(w, Shed.spot_transform(str(Shed.items[plug]["ref"])).origin + Vector3.UP * 0.02)
	check(w.target.get("kind", "") == "spot" and w.target_item() != 0, "each part on it can be aimed at (%s)" % str(w.target))
	check(w.plan.get("action", {}).get("a", "") == "take", "and picked up again")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_whiteboard_moves() -> void:
	Shed.start_new("Tester", 31)
	var me := Shed.me()
	var board := Shed.whiteboard_id()
	check(board != 0 and Shed.furniture[board]["xf"].origin == Whiteboard.MOUNT and Equipment.is_wall("whiteboard"),
		"the whiteboard is a wall hanging in its old place on the front wall")
	check(Shed.check(me, {"a": "order_furniture", "model": "whiteboard"}).contains("already"), "there's only the one whiteboard")
	check(not PartsComputer.all_kinds().has("eq:whiteboard"), "it isn't sold")
	check(Shed.check(me, {"a": "grab", "furniture": board}) == "", "it can be taken down")
	# An older save had no whiteboard to move: it stays where it always was.
	var old: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	(old["furniture"] as Dictionary).erase(board)
	Shed.load_state(old, "Tester")
	var again := Shed.whiteboard_id()
	check(again != 0 and Shed.furniture[again]["xf"].origin == Whiteboard.MOUNT, "a save from before keeps it at the old spot")
	Shed.stop()
	# In the game: take it down, hang it on the east wall, and it's still there after a save.
	var kept := [Settings.time_of_day, Settings.day_night_cycle, Settings.day_length]
	SaveGame.slot_override = "test_whiteboard_move"
	SaveGame.delete_slot(SaveGame.active_slot())
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	board = Shed.whiteboard_id()
	var node: Whiteboard = get_tree().get_first_node_in_group("whiteboard")
	check(node != null and node.global_position.distance_to(Whiteboard.MOUNT) < 0.01, "it hangs where it always did")
	Shed.board_request({"a": "board_draw", "id": 501, "c": 2, "w": 6.0, "from": 0, "done": true,
		"pts": PackedVector2Array([Vector2(100, 100), Vector2(400, 120)])})
	w.target = {"kind": "board"}
	check(w._target_furniture() == board, "F at the whiteboard takes hold of it")
	Shed.request({"a": "grab", "furniture": board})
	var east := Transform3D(Basis(Vector3.UP, -PI * 0.5), Workshop.CENTER + Vector3(Workshop.HALF.x - 0.03, 1.6, 2.0))
	Shed.request({"a": "release", "furniture": board, "xf": east})
	await get_tree().process_frame
	node = get_tree().get_first_node_in_group("whiteboard")
	check(node.global_position.distance_to(east.origin) < 0.01, "it hangs on the east wall now")
	check(main.saver.save_now(), "the shed saves")
	main._leave()
	main._start_session()
	await get_tree().physics_frame
	await get_tree().process_frame
	board = Shed.whiteboard_id()
	node = get_tree().get_first_node_in_group("whiteboard")
	check(Shed.furniture[board]["xf"] == east and node != null and node.global_position.distance_to(east.origin) < 0.01,
		"after loading it's still on the east wall")
	check(BoardData.find(Shed.board, 501) >= 0, "with its drawing on it")
	# You can still draw on it where it is.
	w = main.walker
	var face: Vector3 = node.global_position
	w.place(Transform3D(Basis(), Vector3(face.x - 1.4, 0.0, face.z)))
	await _aim_point(w, face)
	check(w.target.get("kind", "") == "board" and node.aim(w).distance_to(BoardData.PX * 0.5) < 40.0, "and draw on it there (%s)" % str(node.aim(w)))
	check(w.info.contains("F: take it down"), "the panel says F takes it down")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	SaveGame.delete_slot(SaveGame.active_slot())
	SaveGame.slot_override = ""
	Settings.time_of_day = kept[0]
	Settings.day_night_cycle = kept[1]
	Settings.day_length = kept[2]


func _test_box_labels() -> void:
	# Each box comes from a made-up delivery firm, always the same one for the same box.
	check(BikeModel.courier_for(42) == BikeModel.courier_for(42) and BikeModel.tracking_for(42) == BikeModel.tracking_for(42),
		"a box's courier and tracking number come from its id, so it always looks the same")
	var seen := {}
	for id in range(1, 41):
		seen[BikeModel.courier_for(id)] = true
	check(seen.size() >= 4, "boxes come from several different couriers (%d)" % seen.size())
	check(BikeModel.tracking_for(1) != BikeModel.tracking_for(2), "each has its own tracking number")
	var long_box := BikeModel.box_display("stock_muffler", 42)
	var size: Vector3 = long_box.get_meta("size")
	var lid: Node3D = long_box.get_node("Label")
	var front: Node3D = long_box.get_node("FrontLabel")
	check(int(long_box.get_meta("courier")) == BikeModel.courier_for(42), "the box shows its courier's label")
	check(lid.position.y > size.y and is_equal_approx(lid.rotation.x, -PI * 0.5), "the lid label lies face up on top")
	check(is_equal_approx(lid.rotation.y, PI * 0.5) == (size.z > size.x * 1.15), "it reads along the box's longer side")
	check(front.position.z > size.z * 0.5 and is_zero_approx(front.rotation.y), "and another faces out the front")
	var texts := []
	for n in lid.get_children():
		if n is Label3D:
			texts.append((n as Label3D).text)
	var firm: Dictionary = BikeModel.COURIERS[BikeModel.courier_for(42)]
	check(texts.has(firm["name"]) and texts.has(PartsDB.part_name("stock_muffler")) and texts.has(BikeModel.tracking_for(42)),
		"the label has the firm's name, what's inside and the tracking number (%s)" % str(texts))
	long_box.free()
	# A delivery outside is drawn with its own courier.
	Shed.start_new("Tester", 41)
	Shed.request({"a": "order_part", "part": "iridium_plugs"})
	var box := 0
	for id in Shed.items:
		if Shed.items[id].get("boxed", false):
			box = id
	var shown := BikeModel.item_display(box)
	check(int(shown.get_meta("courier")) == BikeModel.courier_for(box), "a delivered box carries the label for its own id")
	shown.free()
	Shed.stop()




func _test_side_rooms() -> void:
	var rooms := Workshop.rooms()
	var wash := Rect2(Workshop.WASH_CENTER.x - Workshop.WASH_HALF.x, Workshop.WASH_CENTER.z - Workshop.WASH_HALF.y,
		Workshop.WASH_HALF.x * 2.0, Workshop.WASH_HALF.y * 2.0)
	var names: Array = rooms.keys()
	names.erase("sales_office")   # upstairs in the sales office: inside "sales" by design
	var apart := true
	for i in names.size():
		var a: Rect2 = rooms[names[i]]
		apart = apart and not a.grow(-0.05).intersects(wash)
		for j in range(i + 1, names.size()):
			apart = apart and not a.grow(-0.05).intersects((rooms[names[j]] as Rect2).grow(-0.05))
	check(apart, "the shed, paint shop, storage room, dyno room and wash bay don't overlap")
	check(Workshop.room_at(Workshop.BOOTH_ROOM_CENTER) == "paint" and Workshop.room_at(Workshop.STORE_CENTER) == "storage"
		and Workshop.room_at(Workshop.CENTER) == "shed", "every room knows where it is")
	# Each side door opens off the shed into its room, clear of the bays and the parts computer.
	var doors := Workshop.side_doors()
	for room in ["paint", "storage"]:
		var d: Dictionary = doors[room]
		var side := signf(float(d["x"]) - Workshop.CENTER.x)
		var inside := Vector3(float(d["x"]) - side * 0.5, 0.0, float(d["z"]))
		var beyond := Vector3(float(d["x"]) + side * 0.5, 0.0, float(d["z"]))
		check(Workshop.room_at(inside) == "shed" and Workshop.room_at(beyond) == room, "the %s door leads from the shed into the room" % room)
	check(absf(Workshop.PAINT_DOOR_Z - (Workshop.CENTER.z + 1.9)) > 0.65 + Workshop.SIDE_DOOR_HALF, "the paint shop door is clear of the parts computer")
	# The storage room takes three rows of the biggest shelving, with walking aisles round them.
	var store: Rect2 = rooms["storage"]
	var rack: Vector3 = Equipment.get_model("shelf_racking")["size"]
	var aisle := 1.1
	check(store.size.y >= 3.0 * rack.z + 4.0 * aisle and store.size.x >= 2.0 * rack.x + 2.0 * aisle,
		"the storage room fits three rows of two heavy-duty racks with aisles round them (%.1f x %.1f m)" % [store.size.x, store.size.y])
	# Ten hooks in the paint shop, spaced to walk round every part.
	Shed.start_new("Tester", 12)
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hooks: Array = Shed.furniture_spots(booth)
	check(hooks.size() >= 10 and Shed.furniture[booth]["model"] == Workshop.BOOTH_MODEL, "the paint shop's spray bay has %d hooks" % hooks.size())
	var paint: Rect2 = rooms["paint"]
	var gap := 99.0
	var wall := 99.0
	var bay := Workshop.booth_footprint()
	for i in hooks.size():
		var at: Vector3 = Shed.spot_transform(hooks[i]).origin
		wall = minf(wall, minf(minf(at.x - paint.position.x, paint.end.x - at.x), minf(at.z - paint.position.y, paint.end.y - at.z)))
		check(bay.has_point(Vector2(at.x, at.z)), "hook %d is inside the spray bay" % i)
		for j in range(i + 1, hooks.size()):
			gap = minf(gap, at.distance_to(Shed.spot_transform(hooks[j]).origin))
	check(gap >= 1.2 and wall >= 1.0, "the hooks are %.1f m apart and %.1f m from the walls: room to walk round each part" % [gap, wall])
	check(paint.encloses(bay), "the spray bay fits inside the paint shop")
	check(bay.position.x - paint.position.x >= 2.0, "with a walkway from the door in front of it")
	# Light switches for the side rooms, host-checked and in the snapshot everyone gets.
	var me := Shed.me()
	check(Shed.room_lit("paint") and Shed.room_lit("storage"), "a new shed's side rooms start lit")
	check(Shed.check(me, {"a": "lights", "room": "attic", "on": false}) != "", "there's no switch for a room that isn't there")
	Shed.request({"a": "lights", "room": "paint", "on": false})
	check(not Shed.room_lit("paint") and Shed.room_lit("storage") and Shed.lights_on, "the paint shop switch only turns off the paint shop")
	Shed.request({"a": "lights", "room": "storage", "on": false})
	var snap: Dictionary = Shed._snapshot().duplicate(true)
	check(snap["room_lights"] == {"paint": false, "storage": false}, "the side rooms' lights go out with the shed state")
	Shed.start_new("Tester", 13)
	Shed.load_state(snap, "Tester")
	check(not Shed.room_lit("paint") and not Shed.room_lit("storage"), "and come back from a save as they were left")
	Shed.stop()


## A shed saved before the side rooms: the old six-hook booth and a bought tent with parts on
## their hooks, a shelf where the bigger bay stands now, and no room lights saved.
func _test_side_rooms_old_save() -> void:
	Shed.start_new("Tester", 14)
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	Shed.furniture[booth]["model"] = "booth_pro"
	Shed.furniture[booth]["xf"] = Transform3D(Basis(), Vector3(9.0, 0.0, 64.85))
	var tent := Shed._new_furniture("booth", Transform3D(Basis(), Vector3(9.0, 0.0, 67.0)), "booth_compact")
	var shelf := Shed._new_furniture("shelf", Transform3D(Basis(), Vector3(12.0, 0.0, 65.0)), "shelf_standard")
	var loose: Array = []
	for part in ["solid_240", "sport_road", "solid_240"]:
		loose.append(Shed._new_item(part, 0.0, 0.0, 0.0))
	Shed._move(loose[0], "spot", "booth_%d_2" % booth)
	Shed._move(loose[1], "spot", "booth_%d_5" % booth)
	Shed._move(loose[2], "spot", "booth_%d_0" % tent)
	var old: Dictionary = Shed._snapshot().duplicate(true)
	old.erase("room_lights")
	Shed.start_new("Tester", 15)
	Shed.load_state(old, "Tester")
	var booths := Shed.furniture.values().filter(func(f): return f["kind"] == "booth")
	check(booths.size() == 1 and int(booths[0]["id"]) == booth and booths[0]["model"] == Workshop.BOOTH_MODEL
		and booths[0]["xf"] == Workshop.BOOTH_XF, "an old save's booth becomes the paint shop's ten-hook spray bay")
	check(Shed.items[loose[0]]["ref"] == "booth_%d_2" % booth and Shed.items[loose[1]]["ref"] == "booth_%d_5" % booth,
		"parts on its hooks stay on the same hooks")
	var moved := str(Shed.items[loose[2]]["ref"])
	check(Shed.items[loose[2]]["at"] == "spot" and moved.begins_with("booth_%d_" % booth) and Shed.spot_role(moved) == "booth"
		and Shed.all_spots().has(moved), "a part from a second booth moves onto a free hook (%s)" % moved)
	var spots := {}
	for id in Shed.items:
		if Shed.items[id]["at"] == "spot":
			spots[Shed.items[id]["ref"]] = spots.get(Shed.items[id]["ref"], 0) + 1
	check(spots.values().all(func(v): return v == 1), "no two parts share a place")
	var at: Vector3 = (Shed.furniture[shelf]["xf"] as Transform3D).origin
	check(not Workshop.booth_footprint().has_point(Vector2(at.x, at.z)) and Workshop.room_at(at) == "paint",
		"a shelf standing where the spray bay is now moves to the paint shop walkway")
	check(Shed.room_lit("paint") and Shed.room_lit("storage"), "the side rooms are lit in a save from before their switches")
	Shed.stop()


func _test_side_rooms_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = main.workshop.get_world_3d().direct_space_state
	var ray := func(a: Vector3, b: Vector3) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(a, b, 1)
		return space.intersect_ray(q)
	var doors := Workshop.side_doors()
	for room in ["paint", "storage"]:
		var d: Dictionary = doors[room]
		var x := float(d["x"])
		var z := float(d["z"])
		check(ray.call(Vector3(x - 1.0, 1.2, z), Vector3(x + 1.0, 1.2, z)).is_empty(), "the %s doorway is open" % room)
		check(not ray.call(Vector3(x - 1.0, 1.2, z - 1.4), Vector3(x + 1.0, 1.2, z - 1.4)).is_empty()
			and not ray.call(Vector3(x - 1.0, 2.8, z), Vector3(x + 1.0, 2.8, z)).is_empty(), "with wall either side and over it")
	# The paint shop's old way in from the yard is closed.
	var pc := Workshop.BOOTH_ROOM_CENTER
	var front := pc.z + Workshop.BOOTH_ROOM_HALF.y
	for dx in [-2.5, -1.0, 0.0, 1.0, 2.5]:
		check(not ray.call(Vector3(pc.x + dx, 1.2, front + 1.5), Vector3(pc.x + dx, 1.2, front - 0.5)).is_empty(),
			"the paint shop is closed to the yard (x %+.1f)" % dx)
	# The storage room has a floor to stand shelving on.
	var sc := Workshop.STORE_CENTER
	for p in [Vector2(-3.5, -3.5), Vector2(3.5, -3.5), Vector2(0.0, 0.0), Vector2(-3.5, 3.5)]:
		var hit: Dictionary = ray.call(sc + Vector3(p.x, 2.5, p.y), sc + Vector3(p.x, -1.0, p.y))
		check(not hit.is_empty() and absf((hit["position"] as Vector3).y) < 0.02, "the storage room floor is level (%s)" % str(p))
	# Push a rack into the storage room and leave it there.
	var w: Walker = main.walker
	w.set_tool("hands")
	Shed.request({"a": "order_furniture", "model": "shelf_racking"})
	var rack := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "shelf_racking":
			rack = id
	Shed.request({"a": "grab", "furniture": rack})
	w.place(Transform3D(Basis(Vector3.UP, PI * 0.5), sc + Vector3(1.5, 0.1, -2.0)))
	for i in 10:
		await get_tree().physics_frame
	var xf: Transform3D = w._push_transform(rack)
	check(Workshop.room_at(xf.origin) == "storage" and absf(xf.origin.y) < 0.05, "a rack pushed in the storage room stands on its floor (%s)" % str(xf.origin))
	check(Shed.check(Shed.me(), {"a": "release", "furniture": rack, "xf": xf}) == "", "and can be let go there")
	Shed.request({"a": "release", "furniture": rack, "xf": xf})
	check(Workshop.room_at((Shed.furniture[rack]["xf"] as Transform3D).origin) == "storage", "the rack stays in the storage room")
	# Each side room's switch, and its lights follow it.
	var ws: Workshop = main.workshop
	for room in ["paint", "storage"]:
		var sw: Node3D = ws.get_node("LightRocker_" + room)
		var d: Dictionary = doors[room]
		var side := signf(float(d["x"]) - Workshop.CENTER.x)
		w.place(Transform3D(Basis(), Vector3(sw.global_position.x + side * 1.2, 0.1, sw.global_position.z)))
		await _aim_point(w, sw.global_position)
		check(w.target.get("kind", "") == "lights" and w.target.get("room", "") == room, "the %s light switch is by its door (%s)" % [room, str(w.target)])
		check(w.info.contains("lights"), "and says what it switches")
		Shed.request({"a": "lights", "room": room, "on": false})
		await get_tree().process_frame
		await get_tree().process_frame
		var lamps: Array = ws._room_lights[room]
		check(not lamps.is_empty() and lamps.all(func(l): return not (l as Light3D).visible), "the %s lights go off" % room)
		Shed.request({"a": "lights", "room": room, "on": true})
		await get_tree().process_frame
		await get_tree().process_frame
		check(lamps.all(func(l): return (l as Light3D).visible), "and on again")
	check(ws.get_node_or_null("HexLights") is MultiMeshInstance3D and (ws.get_node("HexLights") as MultiMeshInstance3D).multimesh.instance_count > 60,
		"the paint shop ceiling is a honeycomb of hexagon lights")
	# Screens light only the room in front of them.
	var omni := 0
	for dash in ws.screens().values():
		for child in (dash as Node).get_children():
			if child is OmniLight3D:
				omni += 1
		var spill: SpotLight3D = (dash as Node).get_node_or_null("Spill")
		check(spill != null and (spill.global_basis.z).dot((dash as Node3D).global_basis.z) < -0.99, "a screen's light shines out of its face")
	check(omni == 0, "and none of them glows all round, through the wall behind")
	# Walking into a hanging part sets it swinging, and it soon settles.
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hook: String = Shed.furniture_spots(booth)[3]
	var disc := _hold_new("solid_240")
	check(Shed.check(Shed.me(), {"a": "place", "spot": hook}) == "", "a disc can hang on a hook")
	Shed.request({"a": "place", "spot": hook})
	await get_tree().process_frame
	check(Shed.item_at_spot(hook) == disc, "the disc is on the hook")
	var swing: Swing = ws._spot_nodes[hook].get_parent()
	swing._angle = Vector2.ZERO
	swing._rate = Vector2.ZERO
	var part := swing.part_position()
	var dir := Vector3(0.0, 0.0, 1.0)
	w.place(Transform3D(Basis(), Vector3(part.x, 0.1, part.z) - dir * 1.2))
	await get_tree().physics_frame
	var most := 0.0
	for i in 60:
		w.global_position += dir * 2.4 / 60.0
		await get_tree().physics_frame
		most = maxf(most, swing.angle().length())
	check(most > 0.05, "walking into a part on its hook knocks it swinging (%.2f rad)" % most)
	for i in 600:
		await get_tree().physics_frame
	check(swing.angle().length() < 0.02, "and it settles again after a few seconds (%.3f)" % swing.angle().length())
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## Puts a bike on the dyno rig the way a player does: wheel it there and let go.
func _onto_dyno(bike_id: int) -> void:
	Shed.request({"a": "grab_bike", "bike": bike_id})
	var near := DynoRoom.rig_transform().translated(Vector3(0.2, 0.0, 0.4))
	Shed.request({"a": "move_bike", "bike": bike_id, "xf": near})
	Shed.request({"a": "release_bike", "bike": bike_id, "xf": near})


## The dyno room's kit in the shed state: straps, the extraction hose, the fan and the heat it
## keeps down, exhaust haze, the ear defenders and the room's own lights, all kept with the shed.
func _test_dyno_kit() -> void:
	Shed.start_new("Tester", 21)
	var me := Shed.me()
	var faithful := _bike_named("Old Faithful")
	check(Shed.dyno["hose"] == "hook" and not Shed.dyno["fan"] and Shed.dyno["lights"] and Shed.dyno["headphones"] == 0,
		"a new shed's dyno room: hose on its hook, fan off, lights on, ear defenders hanging up")
	_onto_dyno(faithful)
	check(Shed.dyno_bike() == faithful and Shed.straps_done() == 0, "a bike rolled onto the rig isn't strapped down by itself")
	Shed.request({"a": "dyno_strap", "point": 0})
	Shed.request({"a": "dyno_strap", "point": 3})
	check(Shed.straps_done() == 2 and Shed.check(me, {"a": "dyno_run", "bike": faithful}).contains("2 of the 4"),
		"two straps done: still no run, and it says how many")
	Shed.request({"a": "dyno_strap", "point": 3})
	check(Shed.straps_done() == 1, "the work button at a done-up strap undoes it")
	for i in [1, 2, 3]:
		Shed.request({"a": "dyno_strap", "point": i})
	check(Shed.strapped(), "all four straps done up")
	check(Shed.check(me, {"a": "dyno_strap", "point": 7}) != "", "there are only four strap posts")
	# The extraction hose: off its hook, over the exhaust.
	check(Shed.check(me, {"a": "dyno_hose", "to": "bike"}).contains("hook"), "you need the hose in your hands to fit it")
	Shed.request({"a": "dyno_hose", "to": "held"})
	check(Shed.hose_holder() == me and Shed.check(me, {"a": "take", "spot": "bench_0"}).contains("hose"),
		"carrying the hose, your hands are full")
	var plan := DynoRoom.plan_for({"kind": "part", "bike": faithful, "slot": "tank"}, me)
	check(plan.get("action", {}).get("to", "") == "bike", "carrying the hose, the work button on the bike fits it (%s)" % str(plan))
	Shed.request(plan["action"])
	check(Shed.dyno["hose"] == "bike" and Shed.hose_holder() == 0 and Shed.check(me, {"a": "grab_bike", "bike": faithful}) != "",
		"the hose is on the exhaust, and the bike can't be wheeled off with it on")
	# Heat: a run with the fan on stays cool; with it off the engine heat soaks and fades.
	Shed.request({"a": "dyno_fan", "on": true})
	Shed.dyno["heat"] = 0.0
	Shed._dyno_busy_until = 0
	Shed.request({"a": "dyno_run", "bike": faithful})
	var cool: Dictionary = Shed.bikes[faithful]["dyno"]["runs"][-1]
	check(cool.get("fan", false) and cool.get("hose", false) and float(cool["temp_c"]) < 95.0 and float(Shed.dyno["haze"]) == 0.0,
		"fan on and hose on: a cool run (%d °C) and no fumes in the room" % int(cool.get("temp_c", 0)))
	Shed.request({"a": "dyno_fan", "on": false})
	Shed.dyno["heat"] = 0.0
	Shed._dyno_busy_until = 0
	Shed.request({"a": "dyno_run", "bike": faithful})
	Shed._dyno_busy_until = 0
	Shed.request({"a": "dyno_run", "bike": faithful})
	var hot: Dictionary = Shed.bikes[faithful]["dyno"]["runs"][-1]
	check(float(hot["temp_c"]) > 110.0 and float(hot["peak_hp"]) < float(cool["peak_hp"]) * 0.97,
		"with the fan off it runs hot (%d °C) and down on power (%.1f vs %.1f hp)" % [int(hot["temp_c"]), hot["peak_hp"], cool["peak_hp"]])
	var heat := float(Shed.dyno["heat"])
	Shed.request({"a": "dyno_fan", "on": true})
	Shed._cool_dyno(10.0)
	check(float(Shed.dyno["heat"]) < heat - 0.2, "the fan cools it down between runs (%.2f -> %.2f)" % [heat, Shed.dyno["heat"]])
	# No hose: the room fills with exhaust.
	Shed.request({"a": "dyno_hose", "to": "held"})
	Shed.request({"a": "dyno_hose", "to": "hook"})
	check(Shed.dyno["hose"] == "hook", "the hose comes off the exhaust and back on its hook")
	Shed._dyno_busy_until = 0
	Shed.request({"a": "dyno_run", "bike": faithful})
	check(float(Shed.dyno["haze"]) > 0.4 and not Shed.bikes[faithful]["dyno"]["runs"][-1]["hose"],
		"a run without the extraction hose fills the room with haze (%.2f)" % Shed.dyno["haze"])
	var haze := float(Shed.dyno["haze"])
	Shed._cool_dyno(20.0)
	check(float(Shed.dyno["haze"]) < haze, "the haze clears slowly")
	# Ear defenders and lights.
	Shed.request({"a": "dyno_headphones"})
	check(Shed.wearing_headphones(me), "F at the hook puts the ear defenders on")
	Shed.request({"a": "dyno_lights", "on": false})
	check(not Shed.dyno["lights"] and Shed.lights_on, "the dyno room has its own light switch; the shed's lights stay on")
	# Kept with the shed; nobody is still wearing the ear defenders in a new session.
	var saved: Dictionary = Shed._snapshot().duplicate(true)
	Shed.load_state(saved, "Tester")
	check(not Shed.dyno["lights"] and Shed.dyno["fan"] and Shed.strapped() and Shed.dyno["headphones"] == 0,
		"the dyno room's kit is saved (lights off, fan on, strapped down) and the ear defenders go back on their hook")
	var old: Dictionary = Shed._snapshot().duplicate(true)
	old.erase("dyno")
	Shed.load_state(old, "Tester")
	check(Shed.dyno["hose"] == "hook" and Shed.dyno["lights"] and Shed.straps_done() == 0, "a save from before the dyno kit loads with it all put away")
	# Unstrapped, the bike wheels off and the straps are clear for the next one.
	for i in 4:
		if Shed.dyno["straps"][i]:
			Shed.request({"a": "dyno_strap", "point": i})
	check(Shed.check(me, {"a": "grab_bike", "bike": faithful}) == "", "straps undone, it can be wheeled off")
	Shed.request({"a": "grab_bike", "bike": faithful})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": Workshop.bay_transform(2)})
	check(Shed.dyno_bike() == 0 and Shed.straps_done() == 0, "off the rig and back in its bay")
	# XP for the new jobs.
	for key in ["dyno_strap", "dyno_hose", "sandblast"]:
		check(Progress.XP.has(key), "the XP table has %s" % key)
	check(int(Progress.XP["sandblast"]["xp"]) == int(Progress.XP["repair"]["xp"]), "sandblasting pays like restoring on the grinder")
	# The ear defenders muffle the sound effects.
	Sfx.set_muffled(true)
	check(Sfx.is_muffled(), "with the ear defenders on, sound effects are muffled")
	Sfx.set_muffled(false)
	check(not Sfx.is_muffled(), "and clear again with them off")
	for sound in ["fan", "blast", "ting"]:
		check(Sfx.stream(sound).data.size() > 1000, "the %s sound is made" % sound)
	Shed.stop()


## Walking into the dyno room: the doorway between bays 2 and 3 with full-width bay screens
## either side, no tool chest or tyres, the kit drawn and working through the walker.
func _test_dyno_room_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var ws: Workshop = main.workshop
	var room: DynoRoom = ws.dyno_room
	# The bay screens are all full width again, clear of the doorway and of each other.
	var spans := []
	for bay in Workshop.BAY_COUNT:
		var s: Dashboard = ws._bay_screens[bay]
		spans.append(Vector2(s.global_position.x - s.width * 0.5 - 0.04, s.global_position.x + s.width * 0.5 + 0.04))
	var clear := true
	for i in spans.size():
		clear = clear and spans[i].x >= Workshop.CENTER.x - Workshop.HALF.x
		clear = clear and spans[i].y <= Workshop.CENTER.x + Workshop.HALF.x
		if i > 0:
			clear = clear and spans[i].x > spans[i - 1].y
	var door := DynoRoom.DOOR_HALF + 0.12
	check(ws._bay_screens.all(func(s): return is_equal_approx(s.width, Workshop.BAY_SCREEN_OUTER)), "all four bay screens are full width")
	check(clear and spans[1].y < -door and spans[2].x > door, "they fit either side of the doorway without overlapping (%s)" % str(spans))
	check(DynoRoom.DOOR_HALF * 2.0 >= 1.6, "the doorway is %.1f m wide: room to wheel a bike through" % (DynoRoom.DOOR_HALF * 2.0))
	# Walk through the doorway into the dyno room.
	w.place(Transform3D(Basis(), Vector3(0.0, 0.0, Workshop.CENTER.z - Workshop.HALF.y + 1.2)))
	Input.action_press("move_forward")
	for i in 120:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(w.global_position.z < DynoRoom.CENTER.z + DynoRoom.HALF.y - 0.5, "you can walk through the doorway (z %.1f)" % w.global_position.z)
	# No tool chest or tyre rack along the west wall any more.
	var west := 0
	for n in room.find_children("*", "StaticBody3D", true, false):
		var at: Vector3 = (n as Node3D).global_position
		if at.x < DynoRoom.CENTER.x - DynoRoom.HALF.x + 1.0 and at.y < 1.2 and absf(at.z - DynoRoom.CENTER.z) < 2.5 \
				and not (n as StaticBody3D).has_meta("dyno_kit"):
			west += 1
	check(west == 0, "the tool chest and spare tyres are gone from the west wall (%d)" % west)
	# The light switch by the door, with F.
	await _aim_point(w, room.get_node("LightSwitch").global_position)
	check(w.target.get("kit", "") == "lights" and w.info.contains("switch them off"), "the dyno room's light switch is by its door (%s)" % str(w.target))
	_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not Shed.dyno["lights"] and not room.lights_shown() and ws._lights_shown, "F switches the dyno room's lights off, not the shed's")
	_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	# The fan.
	await _aim_point(w, room.get_node("FanSwitch").global_position)
	_press("interact")
	for i in 60:
		await get_tree().process_frame
	check(Shed.dyno["fan"] and room._fan_speed > 5.0 and room._fan_sound.playing, "the fan switch spins the fan up, and you hear it")
	# Ear defenders off their hook.
	await _aim_point(w, room.get_node("PhonesHook").global_position)
	check(w.target.get("kit", "") == "phones", "the ear defenders hang by the door")
	_press("interact")
	for i in 3:
		await get_tree().process_frame
	check(Shed.wearing_headphones(Shed.me()) and not room.phones_on_hook() and Sfx.is_muffled(),
		"F puts them on: off the hook, and everything's muffled")
	var rp := RemotePlayer.new()
	add_child(rp)
	rp.setup(4242, "Mate", Color.RED)
	Shed.dyno["headphones"] = 4242
	rp._process(0.0)
	check(rp.wearing_phones(), "another player wearing them has them on their head")
	Shed.dyno["headphones"] = Shed.me()
	rp.queue_free()
	_press("interact")
	for i in 3:
		await get_tree().process_frame
	check(not Shed.wearing_headphones(Shed.me()) and room.phones_on_hook() and not Sfx.is_muffled(), "and F hangs them back up")
	# A bike on the rig: strap it down at the posts with the work button.
	var faithful := _bike_named("Old Faithful")
	_onto_dyno(faithful)
	for i in 4:
		var post: Node3D = room.get_node("Rig/StrapPost%d" % i)
		w.place(Transform3D(Basis(), post.global_position + (post.global_position - DynoRoom.CENTER).normalized() * 1.0 * Vector3(1, 0, 1)))
		await _aim_point(w, post.global_position)
		await _hold_act(main)
	check(Shed.strapped() and room._strap_nodes.all(func(s): return s.visible), "holding the work button at each post straps it down, and the straps show")
	# The hose: off the hook, onto the exhaust.
	w.place(Transform3D(Basis(), DynoRoom.HOSE_HOOK + Vector3(-1.2, -DynoRoom.HOSE_HOOK.y, 0.0)))
	await _aim_point(w, room.get_node("HoseHook").global_position)
	await _hold_act(main)
	check(Shed.hose_holder() == Shed.me(), "the work button at the hook takes the hose")
	await _aim_at(main, faithful, "exhaust")
	await _hold_act(main)
	for i in 3:
		await get_tree().process_frame
	var tip = room.exhaust_tip()
	check(Shed.dyno["hose"] == "bike" and tip is Transform3D and room.get_node("HoseEnd").global_position.distance_to((tip as Transform3D).origin) < 0.05,
		"pushed over the exhaust, the hose is drawn on the tailpipe")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The sandblaster: an engine goes in, ancillaries and all; turn it and blast it, and the rust
## comes off where the jet hits, back to bare metal.
func _test_sandblaster() -> void:
	check(Equipment.KINDS.has("blaster") and Equipment.by_kind("blaster").size() >= 2
		and PartsComputer.all_kinds().has("eq:blaster"), "the parts computer sells sandblasting cabinets")
	# Surface patches face outwards.
	var bm := BikeModel.new()
	add_child(bm)
	bm.build_from(BikeBuild.new())
	var surf := bm.surface_points("tank", 0.03)
	var pts: PackedVector3Array = surf[0]
	var nrm: PackedVector3Array = surf[1]
	var centre := bm.slot_bounds("tank").get_center()
	var out := 0
	for i in pts.size():
		if (pts[i] - centre).dot(nrm[i]) > 0.0:
			out += 1
	check(pts.size() > 50 and out > pts.size() * 0.8, "the coverage map covers the part's surface, normals facing out (%d of %d)" % [out, pts.size()])
	bm.queue_free()

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var me := Shed.me()
	Shed.request({"a": "order_furniture", "model": "blaster_cabinet"})
	var cab := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "blaster":
			cab = id
	check(cab != 0, "a sandblasting cabinet can be ordered")
	var spot := "blast_%d_0" % cab
	var at := Workshop.CENTER + Vector3(1.5, 0.0, 1.8)
	Shed.request({"a": "grab", "furniture": cab})
	Shed.request({"a": "release", "furniture": cab, "xf": Transform3D(Basis(), at)})
	# Only an engine goes in it: the barn find's, off the stand, with its head and carbs on.
	var engine := 0
	var stand_spot := ""
	for s in Shed.stand_spots():
		if Shed.is_engine(Shed.item_at_spot(s)):
			stand_spot = s
			engine = Shed.item_at_spot(s)
	var tyre := _hold_new("sport_road")
	check(Shed.check(me, {"a": "place", "spot": spot}).contains("engines"), "a tyre doesn't go in the sandblaster")
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), at + Vector3(2.0, 0.0, 0.0))})
	Shed.request({"a": "take", "spot": stand_spot})
	Shed.request({"a": "place", "spot": spot})
	check(Shed.item_at_spot(spot) == engine and engine != 0, "the engine goes in the cabinet, ancillaries and all")
	var parts := [engine]
	for slot in PartsDB.ENGINE_SLOTS:
		if Shed.engine_item(engine, slot) != 0:
			parts.append(Shed.engine_item(engine, slot))
	for id in parts:
		Shed.items[id]["rust"] = 0.7
		Shed.items[id]["dirt"] = 0.6
		Shed.items[id]["wear"] = 0.1
	for i in 5:
		await get_tree().process_frame
	# Stand at the front, look in through the glass and put your hands in the gloves (F).
	var view: EquipmentView = main.workshop.furniture_nodes[cab]
	var pivot: Node3D = view.get_node("Pivot")
	w.place(Transform3D(Basis(), at + Vector3(0.0, 0.0, 1.3)))
	await _aim_point(w, pivot.global_position)
	check(w.target.get("spot", "") == spot and w.info.contains("sandblast"), "looking in, the panel says F to sandblast it (%s)" % str(w.target))
	_press("interact")
	for i in 4:
		await get_tree().physics_frame
	check(w.blast != null and Shed.blasting(me) == cab and w.blast.parts.size() == parts.size(),
		"F: hands in the gloves, every part of the engine on the coverage map (%d parts)" % (w.blast.parts.size() if w.blast else 0))
	var start := w.global_position
	# Blast: hold the work button; the jet strips where you aim, with grit and sparks flying.
	Input.action_press("act")
	var saw_jet := false
	for i in 80:
		await get_tree().physics_frame
		saw_jet = saw_jet or (view.blast_firing() and (view.get_node("Nozzle/Jet") as GPUParticles3D).emitting)
	var bare := w.blast.marks.bare_count()
	var total0 := w.blast.total()
	check(saw_jet and bare > 5 and w.blast.total() > 0.0, "holding the work button blasts: sand from the nozzle and bare metal where it hits (%d patches)" % bare)
	check((view.get_node("Rebound") as CPUParticles3D).emitting and view.blast_sound.playing, "dust kicks back off the engine and you hear the roar")
	# Turn the engine with the keys and sweep it.
	var rot0: Vector2 = w.blast.rot
	Input.action_press("move_right")
	for i in 120:
		await get_tree().physics_frame
		if i % 30 == 0:
			w._look(0.0, 0.02 if (i / 30) % 2 == 0 else -0.02)
	Input.action_release("move_right")
	Input.action_press("move_forward")
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_release("act")
	await get_tree().physics_frame
	check(absf(w.blast.rot.x - rot0.x) > 0.5 and w.global_position.distance_to(start) < 0.05,
		"W A S D turn the engine on the turntable instead of walking (%.2f rad)" % (w.blast.rot.x - rot0.x))
	check(pivot.basis.is_equal_approx(BlastGame.pivot_basis(w.blast.rot)), "the engine turns in the cabinet")
	var total := w.blast.total()
	check(w.blast.marks.bare_count() > bare * 1.5 and total > total0 and total > 0.02, "sweeping round, more of it comes up bare (%d%% from %d%%, %d cubes from %d)" % [roundi(total * 100.0), roundi(total0 * 100.0), w.blast.marks.bare_count(), bare])
	# Too long on one spot pits it.
	var game := w.blast
	var id0 := int(game.parts.keys()[0])
	var cells: PackedFloat32Array = game.parts[id0]["cells"]
	var rust_before := float(Shed.items[engine]["rust"])
	# Step back: the host strips each part by how much of it came up bare.
	_press("interact")
	for i in 4:
		await get_tree().physics_frame
	check(w.blast == null and Shed.blasting(me) == 0, "F steps back from the cabinet")
	var stripped := 0
	for id in parts:
		if float(Shed.items[id]["rust"]) < 0.7 - 0.01:
			stripped += 1
	check(stripped >= 1 and float(Shed.items[engine]["rust"]) <= rust_before, "the parts the jet reached have less rust and muck on them (%d)" % stripped)
	# The host's rules: coverage strips rust and muck, overdoing it wears the part.
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	var res := {}
	for id in parts:
		res[id] = [0.95, 0.0]
	res[parts[0]] = [0.95, 0.5]
	var xp_before := int(Progress.profile.get("xp", 0))
	Shed.request({"a": "blast", "spot": spot, "parts": res})
	check(parts.all(func(id): return float(Shed.items[id]["rust"]) == 0.0 and float(Shed.items[id]["dirt"]) == 0.0),
		"blasted all over, the engine and every ancillary come back to bare metal")
	check(float(Shed.items[parts[0]]["wear"]) > 0.15 and float(Shed.items[parts[1]]["wear"]) < 0.11, "lingering pits the metal: the overdone part wears")
	check(int(Progress.profile.get("xp", 0)) > xp_before, "sandblasting earns XP")
	check(Shed.check(me, {"a": "blast", "spot": spot, "parts": res}) != "", "you have to be at the cabinet to blast")
	# Someone else can't take the engine out while you're blasting.
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	Shed.crew[777] = {"name": "Mate"}
	check(Shed.check(777, {"a": "blast_use", "spot": spot, "on": true}).contains("using it")
		and Shed.check(777, {"a": "take", "spot": spot}).contains("blasting"), "one person at the gloves at a time, and the engine stays put")
	Shed.crew.erase(777)
	Shed.request({"a": "blast_use", "on": false})
	# A blast game on its own: one patch held too long goes past bare and pits.
	var g := BlastGame.new()
	g.parts = {1: {"slot": "engine", "name": "Engine", "start": 0, "points": PackedVector3Array([Vector3.ZERO]),
		"normals": PackedVector3Array([Vector3.BACK]), "cells": PackedFloat32Array([BlastGame.OVER + 1.0])}}
	check(float(g.stats(1)["over"]) == 1.0 and float(g.stats(1)["covered"]) == 1.0, "a patch blasted too long counts as pitted")
	Shed.items.erase(tyre)
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------- geometry mode and blueprints

func _test_geo_gizmo_math() -> void:
	var id := GeoGizmo.identity()
	var m := GeoGizmo.moved(id, 0, 0.1234, false)
	check(is_equal_approx((m["p"] as Vector3).x, 0.1234) and (m["p"] as Vector3).y == 0.0 and (m["p"] as Vector3).z == 0.0
		and m["r"] == Vector3.ZERO and m["s"] == Vector3.ONE, "dragging the X arrow moves only X (%s)" % str(m["p"]))
	var ms := GeoGizmo.moved(m, 1, 0.0567, true)
	check(is_equal_approx((ms["p"] as Vector3).y, 0.06) and is_equal_approx((ms["p"] as Vector3).x, 0.1234),
		"Ctrl snaps a move to 1 cm and leaves the other axes (%s)" % str(ms["p"]))
	check(is_equal_approx((GeoGizmo.moved(id, 2, 9.0, false)["p"] as Vector3).z, GeoGizmo.MAX_MOVE), "a move can't go off past the limit")
	var r := GeoGizmo.rotated(id, 1, 33.0, true)
	check(is_equal_approx((r["r"] as Vector3).y, 35.0) and (r["r"] as Vector3).x == 0.0 and (r["r"] as Vector3).z == 0.0
		and r["p"] == Vector3.ZERO, "turning the Y ring turns only about Y, snapped to 5 degrees (%s)" % str(r["r"]))
	check(is_equal_approx((GeoGizmo.rotated(id, 0, 12.3, false)["r"] as Vector3).x, 12.3), "unsnapped, it turns by exactly what was dragged")
	var s := GeoGizmo.scaled(id, 2, 1.37, true)
	check(s["s"] == Vector3(1.0, 1.0, 1.35), "stretching along Z changes only Z, snapped to 5%% (%s)" % str(s["s"]))
	check(GeoGizmo.scaled(id, GeoGizmo.UNIFORM, 2.0, false)["s"] == Vector3(2.0, 2.0, 2.0), "the middle box sizes it all over")
	check(GeoGizmo.scaled(id, 0, 100.0, false)["s"] == Vector3(GeoGizmo.MAX_SCALE, 1.0, 1.0)
		and GeoGizmo.scaled(id, 0, 0.0, false)["s"] == Vector3(GeoGizmo.MIN_SCALE, 1.0, 1.0), "sizes stay in range")
	# Dragging maths: where the mouse ray passes the axis, and the angle round a ring.
	var t := GeoGizmo.line_param(Vector3.ZERO, Vector3.RIGHT, Vector3(0.5, 1.0, 5.0), Vector3(0.0, 0.0, -1.0))
	check(is_equal_approx(t, 0.5), "the mouse ray picks the right point along an arrow (%.3f)" % t)
	check(is_equal_approx(GeoGizmo.angle_about(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), 90.0), "a quarter turn round a ring reads 90 degrees")
	# The offset is about the part's middle.
	var pivot := Vector3(0.2, 0.6, -0.3)
	var turn := GeoGizmo.offset_xform(GeoGizmo.rotated(id, 1, 90.0, false), pivot)
	check((turn * pivot).is_equal_approx(pivot), "a part turns about its own middle")
	check((GeoGizmo.offset_xform(m, pivot) * pivot).is_equal_approx(pivot + Vector3(0.1234, 0.0, 0.0)), "and moves by its offset")
	var clean := GeoGizmo.sanitize({"tank": ms, "saddle": GeoGizmo.identity(), "rocket": m, "fork": {"s": Vector3(9, 9, 9)}})
	check(clean.has("tank") and not clean.has("saddle") and not clean.has("rocket") and clean["fork"]["s"] == Vector3.ONE * GeoGizmo.MAX_SCALE,
		"saving keeps real slots only, drops untouched parts and keeps sizes in range %s" % str(clean.keys()))


func _test_geo_model() -> void:
	var model := BikeModel.new()
	add_child(model)
	model.build_from(BikeBuild.new())
	var tank0 := model.slot_bounds("tank").get_center()
	var frame0 := model.slot_bounds("frame").get_center()
	var wheel0 := model.slot_bounds("front_wheel").get_center()
	var bars0 := model.slot_bounds("handlebars").get_center()
	model.apply_geometry({"tank": {"p": Vector3(0.0, 0.1, 0.0), "r": Vector3.ZERO, "s": Vector3(1.0, 1.0, 1.5)}})
	check(model.slot_bounds("tank").get_center().is_equal_approx(tank0 + Vector3(0.0, 0.1, 0.0)), "the tank moves up 10 cm on the model")
	check(model.slot_bounds("frame").get_center().is_equal_approx(frame0), "and nothing else moves")
	var with_meshes := 0
	for slot in model._slot_meshes:
		if not model._slot_meshes[slot].is_empty():
			with_meshes += 1
	check(model._geo_nodes.size() == with_meshes and with_meshes > 20, "every drawn slot gets its own geometry node (%d)" % with_meshes)
	model.apply_geometry({"front_wheel": {"p": Vector3(0.05, 0.0, 0.0), "r": Vector3.ZERO, "s": Vector3.ONE}})
	check(model.slot_bounds("tank").get_center().is_equal_approx(tank0), "a new fit replaces the old one")
	var moved_wheel := model.slot_bounds("front_wheel").get_center()
	model.update_pose_from(0.0, 1.3, 0.7, 0.0, 0.0, 0.0, 0.0)
	check(model.slot_bounds("front_wheel").get_center().distance_to(moved_wheel) < 0.002 and absf(moved_wheel.x - wheel0.x - 0.05) < 0.002,
		"a moved wheel still spins about its own middle, without wobbling")
	model.apply_geometry({"handlebars": {"p": Vector3(0.0, 0.08, 0.0), "r": Vector3.ZERO, "s": Vector3.ONE}})
	model.update_pose_from(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	check(model.slot_bounds("handlebars").get_center().is_equal_approx(bars0 + Vector3(0.0, 0.08, 0.0)), "raised bars sit higher")
	model.update_pose_from(0.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	check(not model.slot_bounds("handlebars").get_center().is_equal_approx(bars0 + Vector3(0.0, 0.08, 0.0)), "and still turn with the steering")
	model.update_pose_from(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	# Click targets follow the part.
	model.apply_geometry({"saddle": {"p": Vector3(0.0, 0.2, 0.0), "r": Vector3.ZERO, "s": Vector3.ONE}})
	model.build_pickers({"bike": 1})
	var pick: StaticBody3D = model.get_node("Pick_saddle")
	var top := -INF
	for cs in pick.get_children():
		top = maxf(top, (cs as CollisionShape3D).position.y)
	check(top > model.geo_pivot("saddle").y + 0.1, "the saddle's click target moves with it")
	# Set before building: a parked or ridden bike is drawn with its fit straight away.
	var parked := BikeModel.new()
	add_child(parked)
	parked.geometry = {"tank": {"p": Vector3(0.0, 0.1, 0.0), "r": Vector3.ZERO, "s": Vector3.ONE}}
	parked.build_from(BikeBuild.new())
	check(parked.slot_bounds("tank").get_center().is_equal_approx(tank0 + Vector3(0.0, 0.1, 0.0)), "a model built with a fit shows it")
	model.queue_free()
	parked.queue_free()


func _geo_off(y: float) -> Dictionary:
	return {"p": Vector3(0.0, y, 0.0), "r": Vector3(0.0, 15.0, 0.0), "s": Vector3(1.0, 1.0, 1.2)}


func _test_geo_shed() -> void:
	Shed.start_new("Tester", 31)
	var me := Shed.me()
	var a := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == "Rusty Ranger":
			a = id
	var b := Shed._new_bike(Shed.bikes[a]["original"].duplicate(), 3, "Ranger Twin", 0.3)
	check(Shed.item_on(a, "tank") != 0 and Shed.items[Shed.item_on(a, "tank")]["part"] == Shed.items[Shed.item_on(b, "tank")]["part"],
		"two bikes with the same tank")
	check(Shed.check(me, {"a": "geo_save", "bike": a, "geo": {"tank": _geo_off(0.05)}}) == "", "the host lets a bike's fit be saved")
	Shed.request({"a": "geo_save", "bike": a, "geo": {"tank": _geo_off(0.05), "saddle": GeoGizmo.identity(), "nonsense": _geo_off(1.0)}})
	check(Shed.geometry_of(a).has("tank") and Shed.geometry_of(a).size() == 1, "the tank's fit is saved to that bike %s" % str(Shed.geometry_of(a).keys()))
	check(Shed.geometry_of(b).is_empty(), "and the other bike with the same tank is untouched")
	# Swapping the part keeps the slot's fit.
	var tank := Shed.item_on(a, "tank")
	Shed.bikes[a]["slots"]["tank"] = 0
	Shed.items.erase(tank)
	var other := Shed._new_item("sport_17", 0.0, 0.0, 0.0)
	Shed.bikes[a]["slots"]["tank"] = other
	Shed._move(other, "bike", a)
	check(Shed.geometry_of(a).has("tank"), "a different tank in that slot keeps the slot's fit")
	Shed.bikes[a]["rider"] = 99
	check(Shed.check(me, {"a": "geo_save", "bike": a, "geo": {}}).contains("riding"), "not while someone is riding it")
	Shed.bikes[a]["rider"] = 0
	check(Shed.check(me, {"a": "geo_blueprint", "bike": a, "geo": {}, "name": "  "}) != "", "a blueprint needs a name")
	Shed.request({"a": "geo_blueprint", "bike": a, "geo": {"tank": _geo_off(0.07)}, "name": "Ranger Mk2"})
	var bp := Shed.blueprint_named("ranger mk2")
	check(bp != 0 and is_equal_approx((Shed.geometry_of(a)["tank"]["p"] as Vector3).y, 0.07), "Save + blueprint saves the bike's fit and a named blueprint")
	var plan: Dictionary = Shed.blueprints.get(bp, {})
	check(plan.get("parts", {}).get("tank", "") == "sport_17" and plan["parts"].get("frame", "") == Shed.items[Shed.item_on(a, "frame")]["part"]
		and is_equal_approx((plan["geo"]["tank"]["p"] as Vector3).y, 0.07) and plan["paint"] == Shed.bikes[a]["paint"] and plan["colors"].has("tank"),
		"the blueprint has the bike's parts, paint, colours and fit")
	Shed.request({"a": "geo_blueprint", "bike": a, "geo": {"tank": _geo_off(0.07)}, "name": "Ranger MK2"})
	check(Shed.blueprints.size() == 1, "saving again under the same name updates it")
	check(Shed.check(me, {"a": "bp_rename", "bp": bp, "name": "Desert Sled"}) == "", "a blueprint can be renamed")
	Shed.request({"a": "bp_rename", "bp": bp, "name": "Desert Sled"})
	check(Shed.blueprints[bp]["name"] == "Desert Sled", "and is (%s)" % Shed.blueprints[bp]["name"])
	# Kept with the shed.
	var state: Dictionary = Shed.save_snapshot().duplicate(true)
	Shed.start_new("Tester", 32)
	check(Shed.blueprints.is_empty(), "a new shed has no blueprints")
	Shed.load_state(state, "Tester")
	check(Shed.blueprints.has(bp) and is_equal_approx((Shed.blueprints[bp]["geo"]["tank"]["p"] as Vector3).y, 0.07) and Shed.blueprints[bp]["name"] == "Desert Sled",
		"blueprints, with their fit, come back with the save")
	check(Shed.geometry_of(a).has("tank") and Shed.geometry_of(b).is_empty(), "and each bike keeps its own fit")
	var old := state.duplicate(true)
	old.erase("blueprints")
	old.erase("holograms")
	for id in old["bikes"]:
		old["bikes"][id].erase("geo")
	Shed.load_state(old, "Tester")
	check(Shed.blueprints.is_empty() and Shed.holograms.is_empty() and Shed.geometry_of(a).is_empty(), "an older save opens with none")
	Shed.load_state(state, "Tester")
	check(Shed.check(me, {"a": "bp_delete", "bp": bp}) == "", "a blueprint can be deleted")
	Shed.request({"a": "bp_delete", "bp": bp})
	check(Shed.blueprints.is_empty(), "and is gone")
	Shed.stop()


## Fits a new part straight into a slot of a bike (or onto its engine), for building it up quickly.
func _fit_direct(bike: int, slot: String, part: String) -> void:
	var item := Shed._new_item(part, 0.0, 0.0, 0.0)
	var host := Shed.host_of(bike, slot)
	host["slots"][slot] = item
	host["bolted"][slot] = true
	Shed._move(item, "engine" if PartsDB.is_engine_slot(slot) else "bike", int(host["id"]))


func _test_blueprint_build() -> void:
	Shed.start_new("Tester", 33)
	Shed.garage_money = 1000000   # a whole blueprint of parts to pay for
	var me := Shed.me()
	var a := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == "Old Faithful":
			a = id
	Shed.request({"a": "geo_save", "bike": a, "geo": {"tank": _geo_off(0.04)}})
	Shed.request({"a": "geo_blueprint", "bike": a, "geo": {"tank": _geo_off(0.04)}, "name": "Track Day"})
	var bp := Shed.blueprint_named("Track Day")
	check(Shed.check(me, {"a": "bp_build", "bp": bp, "bay": 0}).contains("isn't empty"), "a blueprint only builds in an empty bay")
	check(Shed.check(me, {"a": "bp_build", "bp": bp, "bay": 3}) == "", "bay 4 is free for it")
	Shed.request({"a": "bp_build", "bp": bp, "bay": 3})
	check(Shed.holograms.has(3) and Shed.plan_at(3)["name"] == "Track Day", "a hologram of the blueprint stands in bay 4")
	check(Shed.check(me, {"a": "order"}).contains("full"), "a project bike isn't delivered into a hologram's bay")
	var rows := Shed.plan_rows(Shed.plan_at(3), 0)
	var expect: int = Shed.blueprints[bp]["parts"].values().filter(func(p): return str(p) != "none").size()
	check(rows.size() == expect and rows.all(func(r): return r["state"] == "needed"), "its list has every part on the blueprint, all needed (%d)" % rows.size())
	Shed.request({"a": "bp_order", "bay": 3})
	rows = Shed.plan_rows(Shed.plan_at(3), 0)
	var ordered := rows.filter(func(r): return r["state"] == "ordered").size()
	check(ordered == Shed.DELIVERY_ROWS * Shed.DELIVERY_COLS and ordered < rows.size(), "ordering fills the delivery area (%d ordered)" % ordered)
	var frame_item := int(Shed.plan_at(3)["ordered"]["frame"])
	check(Shed.items[frame_item]["boxed"] and Shed.items[frame_item]["part"] == Shed.blueprints[bp]["parts"]["frame"], "the frame arrives boxed")
	check(Shed.items[frame_item]["color"] == Shed.blueprints[bp]["colors"]["frame"]["color"], "parts come in the blueprint's colours")
	Shed.request({"a": "bp_order", "bay": 3})
	check(Shed.plan_rows(Shed.plan_at(3), 0).filter(func(r): return r["state"] == "ordered").size() == ordered,
		"ordering again doesn't double up while the area is full")
	# Clear the delivery area and order the rest.
	for i in 4:
		for r in Shed.plan_at(3)["ordered"].values():
			if Shed.items[int(r)]["at"] == "floor":
				Shed._move(int(r), "spot", "bench_0")
		Shed.request({"a": "bp_order", "bay": 3})
	check(Shed.plan_rows(Shed.plan_at(3), 0).all(func(r): return r["state"] == "ordered"), "with room, the rest are ordered")
	# The frame goes on the bay: the bike takes the blueprint's name, paint and fit.
	Shed.items[frame_item]["boxed"] = false
	Shed._move(frame_item, "held", me)
	check(Shed.check(me, {"a": "start_build", "bay": 3}) == "", "the frame goes on the hologram's stand")
	Shed.request({"a": "start_build", "bay": 3})
	var bike := Shed.bike_in_bay(3)
	check(bike != 0 and Shed.bikes[bike]["name"] == "Track Day" and Shed.bikes[bike].get("blueprint") is Dictionary and not Shed.holograms.has(3),
		"the new bike carries the blueprint's name and plan")
	check(Shed.geometry_of(bike).has("tank") and is_equal_approx((Shed.geometry_of(bike)["tank"]["p"] as Vector3).y, 0.04)
		and Shed.bikes[bike]["paint"] == Shed.blueprints[bp]["paint"], "and its paint and fit")
	check(Shed.plan_rows(Shed.plan_at(3), bike).filter(func(r): return r["state"] == "fitted").size() == 1, "the frame is ticked off")
	# Fit everything but the saddle, then the saddle by hand: the plan is done.
	var parts: Dictionary = Shed.blueprints[bp]["parts"]
	for slot in PartsDB.SLOTS:
		if slot in ["frame", "saddle"] or str(parts.get(slot, "none")) == "none":
			continue
		_fit_direct(bike, slot, str(parts[slot]))
	check(Shed.bikes[bike].get("blueprint") is Dictionary, "with one part to go it's still a blueprint build")
	var saddle := Shed._new_item(str(parts["saddle"]), 0.0, 0.0, 0.0)
	Shed._move(saddle, "held", me)
	Shed.request({"a": "install", "bike": bike, "slot": "saddle"})
	check(Shed.item_on(bike, "saddle") == saddle and not Shed.bikes[bike].has("blueprint"), "the last part on finishes the build")
	check(Shed.geometry_of(bike).has("tank"), "and the finished bike keeps the blueprint's fit")
	# Cancelling, and a stripped build's hologram going back to its bay.
	Shed.request({"a": "bp_build", "bp": bp, "bay": 3})
	check(not Shed.holograms.has(3), "a bay with a bike in it can't take another hologram")
	Shed.stop()


func _test_geometry_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	var ws: Workshop = main.workshop
	var w: Walker = main.walker
	var a := 0
	var other := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == "Rusty Ranger":
			a = id
		elif Shed.bikes[id]["name"] == "Old Faithful":
			other = id
	var view: Node3D = ws.bike_views[a]
	w.place(Transform3D(Basis(), view.global_position + Vector3(1.4, 0.1, 0.0)))
	await get_tree().physics_frame
	check(main.geometry_bike() == a, "geometry mode picks the bike you're at")
	main.open_geometry()
	var geo: GeometryMode = main.geometry
	check(geo.active and geo.camera.current and w.process_mode == Node.PROCESS_MODE_DISABLED and not main.hud.visible,
		"F2 opens geometry mode: its own camera, and the walker stands still")
	geo.select("tank")
	await get_tree().process_frame
	await get_tree().process_frame
	check(geo.gizmo.visible and geo.gizmo.mode == GeoGizmo.Mode.MOVE, "selecting the tank shows the move handles")
	var model := ws.bike_model(a)
	var tank0 := model.slot_bounds("tank").get_center()
	# Drag the X arrow 10 cm with the mouse.
	var cam := geo.camera
	var size: float = geo.gizmo.global_basis.get_scale().x
	var o := geo.gizmo.global_position
	var dir := geo.gizmo.axis_dir(0)
	var grab := cam.unproject_position(o + dir * GeoGizmo.ARM * size * 0.6)
	check(geo.gizmo.pick(cam, grab) == 0, "the mouse over the X arrow picks it")
	geo._press(grab)
	geo._drag_to(cam.unproject_position(o + dir * (GeoGizmo.ARM * size * 0.6 + 0.1)))
	geo._release()
	var p: Vector3 = GeoGizmo.offset_of(geo.draft, "tank")["p"]
	check(absf(p.x - 0.1) < 0.01 and p.y == 0.0 and p.z == 0.0, "dragging it moves the tank 10 cm along X only (%s)" % str(p))
	check(absf(model.slot_bounds("tank").get_center().x - tank0.x - p.x) < 0.001, "the bike shows the draft at once")
	check(Shed.geometry_of(a).is_empty() and geo.is_dirty(), "but it's only a draft until saved")
	geo.undo()
	check(geo.draft.is_empty(), "Z undoes it")
	geo.set_part_offset("tank", _geo_off(0.05))
	geo.request_exit()
	check(geo.active and geo._confirm.visible, "leaving with changes asks to save or discard")
	geo.discard_and_close()
	await get_tree().process_frame
	check(not geo.active and Shed.geometry_of(a).is_empty() and ws.bike_model(a).slot_bounds("tank").get_center().is_equal_approx(tank0)
		and w.process_mode != Node.PROCESS_MODE_DISABLED and main.hud.visible, "discarding puts the tank back and gives you your legs back")
	main.open_geometry()
	geo.select("tank")
	geo.set_part_offset("tank", _geo_off(0.05))
	geo.save()
	await get_tree().process_frame
	check(Shed.geometry_of(a).has("tank") and not geo.is_dirty(), "Save to this bike keeps the fit on it")
	check(Shed.geometry_of(other).is_empty(), "no other bike changes")
	check(absf(ws.bike_model(a).slot_bounds("tank").get_center().y - tank0.y - 0.05) < 0.03, "the redrawn bike has its tank where it was put")
	geo.save_blueprint("Ranger Mk2")
	geo.request_exit()
	check(not geo.active, "with everything saved it just closes")
	var bp := Shed.blueprint_named("Ranger Mk2")
	check(bp != 0, "Save + blueprint makes a blueprint")
	# The Esc menu's blueprints tab lists it.
	main.menu.show_pause()
	main.menu.show_blueprints()
	await get_tree().process_frame
	var tab: BlueprintTab = main.menu.blueprints
	tab.refresh(true)
	await get_tree().process_frame
	check(tab._list.get_child_count() == 1, "the Blueprints tab lists it")
	main._close_menu()
	# Build it in bay 4: a hologram appears, with the blueprint's fit.
	Shed.request({"a": "bp_build", "bp": bp, "bay": 3})
	await get_tree().process_frame
	check(ws._holo_views.has(3), "a hologram stands in bay 4")
	var ghost: BikeModel = ws._holo_views[3].get_child(0)
	check(ghost.geometry.has("tank") and ghost.is_fitted("frame") and ghost.is_fitted("tank"), "the hologram is the whole bike, with the blueprint's fit")
	var bay_page: Dictionary = ws._bay_data(3)
	check(bay_page.has("blueprint") and (bay_page["blueprint"] as Array).size() > 20, "the bay screen lists the parts it needs")
	var frame := Shed._new_item(str(Shed.blueprints[bp]["parts"]["frame"]), 0.0, 0.0, 0.0)
	Shed._move(frame, "held", Shed.me())
	Shed.request({"a": "start_build", "bay": 3})
	await get_tree().process_frame
	var built := Shed.bike_in_bay(3)
	check(built != 0 and not ws._holo_views.has(3), "with a frame on the stand, the hologram moves onto the bike")
	var holo: BikeModel = ws.bike_views[built].get_child(0).get_node_or_null("Hologram")
	check(holo != null and not holo.is_fitted("frame") and holo.is_fitted("tank"), "the frame shows solid and the rest as ghosts")
	_fit_direct(built, "tank", str(Shed.blueprints[bp]["parts"]["tank"]))
	Shed.changed.emit()
	await get_tree().process_frame
	holo = ws.bike_views[built].get_child(0).get_node_or_null("Hologram")
	check(holo != null and not holo.is_fitted("tank"), "a ghost part vanishes as the real one goes on")
	check(absf(ws.bike_model(built).slot_bounds("tank").get_center().y - ws.bike_model(built).geo_pivot("tank").y - 0.05) < 0.001,
		"the real tank goes on with the blueprint's fit")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame



# ---------------------------------------------------------------------------- scrapping, turning, shelves, board pictures, posters

func _test_scrap() -> void:
	Shed.start_new("Tester", 41)
	var me := Shed.me()
	# The keys: hold Delete to scrap, , and . turn what you hold; none of them do two things.
	for a in ["scrap", "rotate_left", "rotate_right"]:
		check(Settings.binding_text(a, false) != "" and Settings.clash_text(a) == "", "%s has a key of its own (%s)" % [a, Settings.binding_text(a, false)])
	# Shelving with parts on it: carry it, scrap it, and the parts end up on the floor.
	Shed.request({"a": "order_furniture", "model": "shelf_standard"})
	var shelf := _first_furniture("shelf_standard")
	var xf := Transform3D(Basis(Vector3.UP, 0.4), Workshop.CENTER + Vector3(1.0, 0.0, 2.0))
	Shed.furniture[shelf]["xf"] = xf
	var on := []
	for i in 3:
		_in_hands("iridium_plugs")
		if _set_down_near("f%ds%d" % [shelf, i], Vector2.ZERO):
			on.append(Shed.items.keys().max())
	check(on.size() == 3, "three parts go on its shelves")
	check(Shed.check(me, {"a": "scrap", "furniture": shelf}).contains("Take hold"), "you have to be carrying it to scrap it")
	Shed.request({"a": "grab", "furniture": shelf})
	check(Shed.check(me, {"a": "scrap", "furniture": shelf}) == "", "carrying it, it can be scrapped")
	Shed.request({"a": "scrap", "furniture": shelf})
	check(not Shed.furniture.has(shelf) and Shed.moving(me) == 0, "scrapped, the shelving is gone")
	check(_on_floor_near(on, xf.origin, 1.0), "what was on it is on the floor where it stood")
	# The shed's own kit stays.
	for kind in ["booth", "changer", "whiteboard"]:
		var fid := 0
		for id in Shed.furniture:
			if Shed.furniture[id]["kind"] == kind:
				fid = id
		Shed.furniture[fid]["mover"] = me
		check(Shed.check(me, {"a": "scrap", "furniture": fid}).contains("part of the shed"), "the %s can't be scrapped" % kind)
		Shed.furniture[fid]["mover"] = 0
	# A wall TV goes, and its channel with it.
	Shed.request({"a": "order_furniture", "model": "tv_120"})
	var tv := _first_furniture("tv_120")
	Shed.screens["f%d" % tv] = {"ch": 1, "rider": 0}
	Shed.request({"a": "grab", "furniture": tv})
	Shed.request({"a": "scrap", "furniture": tv})
	check(not Shed.furniture.has(tv) and not Shed.screens.has("f%d" % tv), "a TV can be scrapped")
	# Parts in your hands: only what you're holding.
	var plug := _in_hands("iridium_plugs")
	var loose := Shed._new_item("flat_bar", 0.0, 0.0, 0.0)
	Shed._move(loose, "floor", Transform3D(Basis(), Workshop.CENTER))
	check(Shed.check(me, {"a": "scrap", "item": loose}).contains("Hold"), "a part has to be in your hands to scrap it")
	Shed.request({"a": "scrap", "item": plug})
	check(not Shed.items.has(plug) and Shed.held_by(me) == 0, "a part in your hands is scrapped")
	# A wheel's tyre and an engine's parts come off onto the floor first.
	var at := Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 1.5))
	var wheel := _in_hands("spoked_21")
	var tyre := Shed._new_item("knobbly_mx", 0.0, 0.0, 0.0)
	Shed.items[wheel]["tyre"] = tyre
	Shed._move(tyre, "wheel", wheel)
	Shed.items[tyre]["bead"] = 0.9
	Shed.request({"a": "scrap", "item": wheel, "at": at})
	check(not Shed.items.has(wheel) and Shed.items.has(tyre) and Shed.items[tyre]["at"] == "floor" and not Shed.items[tyre].has("bead"),
		"scrapping a wheel leaves its tyre on the floor")
	var block := 0
	var bike := 0
	for b in Shed.bikes:
		var e := int(Shed.bikes[b]["slots"].get("engine", 0))
		if e != 0 and Shed.is_engine(e) and Shed.engine_item(e, "spark_plugs") != 0:
			block = e
			bike = b
			break
	var subs := []
	for s in PartsDB.ENGINE_SLOTS:
		if Shed.engine_item(block, s) != 0:
			subs.append(Shed.engine_item(block, s))
	Shed._detach(bike, "engine", "held", me)
	Shed.request({"a": "scrap", "item": block, "at": at})
	check(block != 0 and not Shed.items.has(block) and not subs.is_empty() and _on_floor_near(subs, at.origin, 1.5),
		"scrapping an engine leaves its %d parts on the floor" % subs.size())
	Shed.stop()


## Whether every item in `ids` is on the floor within `r` of `at` (across), at its height.
func _on_floor_near(ids: Array, at: Vector3, r: float) -> bool:
	for id in ids:
		if not Shed.items.has(id) or Shed.items[id]["at"] != "floor":
			return false
		var o: Vector3 = (Shed.items[id]["ref"] as Transform3D).origin
		if Vector2(o.x - at.x, o.z - at.z).length() > r or absf(o.y - at.y) > 0.001:
			return false
	return true


func _test_scrap_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	Shed.request({"a": "order_furniture", "model": "seat_stool"})
	var stool := _first_furniture("seat_stool")
	var middle := Workshop.CENTER + Vector3(0.0, 0.0, 1.0)
	Shed.furniture[stool]["xf"] = Transform3D(Basis(), middle)
	w.place(Transform3D(Basis(), middle + Vector3(0.0, 0.0, 1.2)))
	Shed.request({"a": "grab", "furniture": stool})
	for i in 3:
		await get_tree().physics_frame
	check(w.info.contains("scrap it"), "carrying equipment, the panel says how to scrap it")
	Input.action_press("scrap")
	var armed := -1
	for i in 240:
		await get_tree().physics_frame
		if not w.scrap_armed.is_empty():
			armed = i
			break
	Input.action_release("scrap")
	await get_tree().physics_frame
	check(armed > 90 and Shed.furniture.has(stool), "held for a second, it asks first and nothing goes yet (%d frames)" % armed)
	_press("scrap")
	await get_tree().physics_frame
	check(not Shed.furniture.has(stool) and w.scrap_armed.is_empty(), "pressed again, the stool is scrapped")
	# A part: left too long, it's kept.
	var plug := _in_hands("iridium_plugs")
	for attempt in 2:
		Input.action_press("scrap")
		for i in 160:
			await get_tree().physics_frame
		Input.action_release("scrap")
		await get_tree().physics_frame
		if attempt == 0:
			check(not w.scrap_armed.is_empty() and int(w.scrap_armed.get("item", 0)) == plug, "holding it with a part in hand asks to scrap the part")
			w.scrap_armed["until"] = 0
			await get_tree().physics_frame
			check(w.scrap_armed.is_empty() and Shed.items.has(plug), "not confirmed in time, it's kept")
	_press("scrap")
	await get_tree().physics_frame
	check(not Shed.items.has(plug) and Shed.held_by(Shed.me()) == 0, "confirmed, the part is gone")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_hold_turning() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var kept: bool = Settings.snap_placement
	Settings.snap_placement = true
	var middle := Workshop.CENTER + Vector3(0.0, 0.0, 1.0)
	w.place(Transform3D(Basis(), middle))
	var bar := _in_hands("flat_bar")
	await _aim_point(w, middle + Vector3(0.0, 0.0, -1.2))
	check(w.plan.get("action", {}).get("a", "") == "drop", "aiming at the floor with a part offers to put it down (%s)" % str(w.plan.get("action", {})))
	_press("rotate_left")
	for i in 3:
		await get_tree().physics_frame
	check(is_equal_approx(w.hold_turn, PI * 0.5), "with snapping on, a press turns it a quarter left (%.2f)" % w.hold_turn)
	var drop: Transform3D = w.plan["action"]["xf"]
	check(absf(wrapf(drop.basis.get_euler().y - w.rotation.y - PI * 0.5, -PI, PI)) < 0.01, "it goes down turned that way")
	check(w._part_ghost != null and w._part_ghost.visible
		and absf(wrapf(w._part_ghost.global_basis.get_euler().y - drop.basis.get_euler().y, -PI, PI)) < 0.01, "and its outline on the floor shows it turned")
	check(w.info.contains("turn it"), "the panel says how to turn it")
	_press("rotate_right")
	_press("rotate_right")
	await get_tree().physics_frame
	check(is_equal_approx(w.hold_turn, -PI * 0.5), "the other key turns it the other way")
	# Snapping off: hold the key and it turns freely.
	Settings.snap_placement = false
	var was := w.hold_turn
	Input.action_press("rotate_left")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("rotate_left")
	await get_tree().physics_frame
	var turned := wrapf(w.hold_turn - was, -PI, PI)
	check(turned > 0.2 and turned < PI * 0.5 and fmod(absf(w.hold_turn), PI * 0.5) > 0.01,
		"with snapping off it turns freely while the key is held (%.0f degrees)" % rad_to_deg(turned))
	var want := w.rotation.y + w.hold_turn
	await _hold_act(main)
	check(Shed.items[bar]["at"] == "floor" and absf(wrapf((Shed.items[bar]["ref"] as Transform3D).basis.get_euler().y - want, -PI, PI)) < 0.02,
		"put down, it lies as it was turned")
	_in_hands("flat_bar")
	await get_tree().physics_frame
	check(w.hold_turn == 0.0, "the next part in your hands starts the way you face")
	# Equipment you carry turns too.
	Shed.request({"a": "order_furniture", "model": "seat_stool"})
	var stool := _first_furniture("seat_stool")
	Shed._erase_item(Shed.held_by(Shed.me()))
	Shed.furniture[stool]["xf"] = Transform3D(Basis(), middle + Vector3(0.0, 0.0, -1.0))
	Settings.snap_placement = true
	Shed.request({"a": "grab", "furniture": stool})
	for i in 3:
		await get_tree().physics_frame
	_press("rotate_left")
	await get_tree().physics_frame
	var sxf: Transform3D = w._push_transform(stool)
	check(is_equal_approx(w.carry_turn, PI * 0.5) and absf(wrapf(sxf.basis.get_euler().y - Placement.snap_yaw(w.rotation.y + PI * 0.5), -PI, PI)) < 0.01,
		"carried equipment turns a quarter with snapping on")
	Settings.snap_placement = false
	Input.action_press("rotate_right")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("rotate_right")
	await get_tree().physics_frame
	sxf = w._push_transform(stool)
	check(w.carry_turn < PI * 0.5 - 0.2 and absf(wrapf(sxf.basis.get_euler().y - w.rotation.y - w.carry_turn, -PI, PI)) < 0.01,
		"and freely with it off (%.0f degrees)" % rad_to_deg(w.carry_turn))
	check(w.info.contains("turn it"), "the panel says how to turn it")
	_press("interact")
	for i in 3:
		await get_tree().physics_frame
	# Down on the repair bench: as turned with snapping off, square to it with snapping on.
	var machine := _first_furniture("repair_standard")
	var mxf: Transform3D = Shed.furniture[machine]["xf"]
	var top := Equipment.work_height("repair_standard")
	w.place(Transform3D(Basis(), mxf * Vector3(-0.3, 0.0, 1.3)))
	_in_hands("iridium_plugs")
	await get_tree().physics_frame
	w.hold_turn = 0.3
	await _aim_point(w, mxf * Vector3(-0.3, top, 0.0))
	var pa: Dictionary = w.plan.get("action", {})
	check(pa.get("a", "") == "set_down", "aiming at the bench top offers to put it down (%s)" % str(pa))
	if pa.get("a", "") == "set_down":
		var rel := wrapf((pa["xf"] as Transform3D).basis.get_euler().y - (w.rotation.y + 0.3 - mxf.basis.get_euler().y), -PI, PI)
		check(absf(rel) < 0.01 or absf(absf(rel) - PI * 0.5) < 0.01, "with snapping off it goes on the bench as turned (%.2f)" % rel)
	Settings.snap_placement = true
	for i in 3:
		await get_tree().physics_frame
	pa = w.plan.get("action", {})
	if pa.get("a", "") == "set_down":
		var yaw := (pa["xf"] as Transform3D).basis.get_euler().y
		check(absf(wrapf(yaw - Placement.snap_yaw(yaw), -PI, PI)) < 0.01, "with snapping on it goes square to the bench (%.2f)" % yaw)
	Settings.snap_placement = kept
	Settings.save_settings()
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_shelf_surfaces() -> void:
	Shed.start_new("Tester", 43)
	var me := Shed.me()
	var shelf := Shed._new_furniture("shelf", Transform3D(Basis(Vector3.UP, PI * 0.5), Workshop.CENTER + Vector3(1.0, 0.0, 2.0)), "shelf_standard")
	var levels := int(Equipment.get_model("shelf_standard")["levels"])
	var cols := int(Equipment.get_model("shelf_standard")["cols"])
	check(Shed.surface("f%ds0" % shelf).get("kind", "") == "shelf" and not Shed.surface("f%ds%d" % [shelf, levels - 1]).is_empty()
		and Shed.surface("f%ds%d" % [shelf, levels]).is_empty(), "each of its %d boards is a surface to put parts on" % levels)
	var key := "f%ds1" % shelf
	var on := []
	for i in 12:
		_in_hands("iridium_plugs")
		if _set_down_near(key, Vector2(-0.5 + i * 0.09, 0.0)):
			on.append(Shed.items.keys().max())
		else:
			Shed._erase_item(Shed.held_by(me))
	check(on.size() > cols, "more than its old %d places go on one board (%d)" % [cols, on.size()])
	var rects := Shed._surface_rects(key)
	var overlaps := 0
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			if (rects[a][1] as Rect2).grow(-Shed.SURFACE_GAP).intersects(rects[b][1]):
				overlaps += 1
	check(overlaps == 0, "none of them overlap")
	check(Shed.surface_items(key).size() == on.size() and Shed.surface_items("f%ds0" % shelf).is_empty() and Shed.surface_items("f%ds2" % shelf).is_empty(),
		"they're on that board and no other")
	var ref := str(Shed.items[on[0]]["ref"])
	var sxf: Transform3D = Shed.furniture[shelf]["xf"]
	check(Shed.surface_of_spot(ref) == key and Shed.spot_role(ref) == "shelf"
		and absf((sxf.affine_inverse() * Shed.spot_transform(ref).origin).y - Equipment.shelf_top("shelf_standard", 1)) < 0.001, "each sits on the board where it was put")
	check(Shed.surface_name(key).contains("shelf 2"), "the board is named for the panel (%s)" % Shed.surface_name(key))
	var box := _in_hands("flat_bar")
	Shed.items[box]["boxed"] = true
	check(_set_down_near("f%ds2" % shelf, Vector2.ZERO), "boxed stock goes on a shelf")
	# Moved, the parts go with it.
	Shed.furniture[shelf]["xf"] = sxf.translated(Vector3(0.5, 0.0, 0.0))
	check(Shed.spot_transform(ref).origin.distance_to((Shed.furniture[shelf]["xf"] as Transform3D) * Shed.item_place(on[0]).origin) < 0.001, "and moves with the shelving")
	# An older save: a part in one of the old numbered places of another unit.
	var old_shelf := Shed._new_furniture("shelf", Transform3D(Basis(), Workshop.CENTER + Vector3(-1.0, 0.0, 2.0)), "shelf_standard")
	var legacy := Shed._new_item("paper_oil", 0.0, 0.0, 0.0)
	var n := cols * 3 + 1
	Shed._move(legacy, "spot", "shelf_%d_%d" % [old_shelf, n])
	check(Shed.surface_items("f%ds3" % old_shelf) == [legacy] and Shed.item_place(legacy) == Equipment.local_place("shelf_standard", n),
		"a part in an old numbered place is on its board, where it was")
	_in_hands("paper_oil")
	check(Shed.check(me, {"a": "set_down", "top": "f%ds3" % old_shelf, "xf": Shed.item_place(legacy)}).contains("in the way"), "and parts are kept clear of it")
	Shed._erase_item(Shed.held_by(me))
	Shed.load_state(str_to_var(var_to_str(Shed._snapshot())), "Tester")
	check(Shed.items[legacy].get("place") is Transform3D and Shed.items[legacy]["place"] == Equipment.local_place("shelf_standard", n)
		and Shed.surface_items("f%ds3" % old_shelf) == [legacy], "opened, the old save keeps it there, now as put down on the board")
	check(on.all(func(id): return Shed.surface_items(key).has(id)), "the rest come back from the save on their board")
	Shed.stop()


func _test_shelf_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var kept: bool = Settings.snap_placement
	Settings.snap_placement = true
	var middle := Workshop.CENTER + Vector3(0.0, 0.0, 1.0)
	var shelf := Shed._new_furniture("shelf", Transform3D(Basis(), middle), "shelf_standard")
	Shed.changed.emit()
	for i in 2:
		await get_tree().process_frame
	w.place(Transform3D(Basis(), middle + Vector3(0.0, 0.0, 1.3)))
	var key := "f%ds2" % shelf
	var top := Equipment.shelf_top("shelf_standard", 2)
	var count := 0
	for i in 4:
		_in_hands("iridium_plugs")
		Shed.changed.emit()
		await _aim_point(w, middle + Vector3(-0.3, top + 0.08, 0.1))
		check(w.plan.get("action", {}).get("a", "") == "set_down" and w.plan["action"].get("top", "") == key and w.plan["blocked"] == "",
			"looking at a shelf with a part offers to put it down on that board (%s, %s)" % [str(w.target), str(w.plan.get("blocked", w.plan))])
		await _hold_act(main)
		if Shed.held_by(Shed.me()) == 0:
			count += 1
	check(count == 4 and Shed.surface_items(key).size() == 4, "four spark plugs go on the one board, side by side (%d)" % Shed.surface_items(key).size())
	Shed.changed.emit()
	await get_tree().process_frame
	var plug: int = Shed.surface_items(key)[0]
	await _aim_point(w, Shed.spot_transform(str(Shed.items[plug]["ref"])).origin + Vector3.UP * 0.02)
	check(w.target.get("kind", "") == "spot" and w.target_item() != 0 and w.plan.get("action", {}).get("a", "") == "take",
		"a part on a shelf can be aimed at and picked up (%s)" % str(w.target))
	Settings.snap_placement = kept
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_board_turning() -> void:
	var b := BoardData.empty()
	var op := BoardData.clean({"a": "board_image", "id": 5, "img": 3, "at": Vector2(500, 200), "sz": Vector2(200, 40), "rot": 450.0}, 1, "T")
	check(is_equal_approx(float(op["rot"]), 90.0), "a picture's turn wraps round into 0 to 360 degrees")
	BoardData.apply(b, op)
	var r := BoardData.bounds(b["marks"][0])
	check(r.size.is_equal_approx(Vector2(40, 200)) and r.get_center().is_equal_approx(Vector2(600, 220)), "turned a quarter it covers a tall box (%s)" % str(r))
	check(BoardData.image_at(b, Vector2(600, 300)) == 5 and BoardData.image_at(b, Vector2(680, 220)) == 0
		and BoardData.ink_at(b, Vector2(600, 300)) == BoardData.IMAGE, "it's found where it shows, turned")
	BoardData.apply(b, BoardData.clean({"a": "board_move", "id": 5, "at": Vector2(500, 200), "sz": Vector2(200, 40), "rot": 30.0}, 1, "T"))
	check(is_equal_approx(BoardData.rotation_of(b["marks"][0]), 30.0), "moving it can turn it")
	BoardData.apply(b, BoardData.clean({"a": "board_move", "id": 5, "at": Vector2(510, 200), "sz": Vector2(200, 40)}, 1, "T"))
	check(is_equal_approx(BoardData.rotation_of(b["marks"][0]), 30.0) and (b["marks"][0]["at"] as Vector2).x == 510.0, "moving it without a turn keeps its turn")
	var node := Whiteboard.mark_node(b["marks"][0], null)
	check(is_equal_approx(node.rotation, deg_to_rad(30.0)) and (node as Control).pivot_offset.is_equal_approx(Vector2(100, 20)), "drawn turned about its middle")
	node.free()
	var kept: bool = Settings.snap_placement
	Settings.snap_placement = true
	check(is_equal_approx(Whiteboard.turned(0.0, 1), 15.0) and is_equal_approx(Whiteboard.turned(7.0, 1), 15.0)
		and is_equal_approx(Whiteboard.turned(7.0, -1), 0.0) and is_equal_approx(Whiteboard.turned(0.0, -1), 345.0), "with snapping on a press turns it 15 degrees")
	Settings.snap_placement = false
	check(is_equal_approx(Whiteboard.turned(7.0, 1), 7.0 + Whiteboard.TURN_NUDGE), "with snapping off a press nudges it")
	# The eraser rubs out a turned picture where it shows, not the box it used to fill.
	for rot in [90.0, 0.0]:
		var rb := BoardData.empty()
		BoardData.apply(rb, BoardData.clean({"a": "board_image", "id": 7, "img": 3, "at": Vector2(450, 280), "sz": Vector2(100, 40), "rot": rot}, 1, "T"))
		BoardData.apply(rb, BoardData.clean({"a": "board_draw", "id": 8, "c": BoardData.ERASER, "pts": PackedVector2Array([Vector2(500, 230), Vector2(500, 370)])}, 1, "T"))
		var gone := BoardData.tidy(rb, 8)
		check(gone.has(7) == (rot == 90.0), "a line down the middle rubs out the picture turned upright, not lying flat (%d degrees)" % roundi(rot))
	# At the board: take hold of a picture, turn it, put it down; turn one you're looking at.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var board: Whiteboard = get_tree().get_first_node_in_group("whiteboard")
	var face: Vector3 = board.global_position
	w.place(Transform3D(Basis(), Vector3(face.x, 0.0, face.z - 1.4)))
	w.rotation.y = PI
	w._pitch = 0.0
	w._look(0.0, -atan2(Walker.EYE - face.y, 1.4))
	for i in 5:
		await get_tree().physics_frame
	Settings.snap_placement = true
	var id := board.add_image(_test_picture(96, 48), BoardData.PX * 0.5)
	check(id != 0, "a picture goes up")
	_press("board_move")
	await get_tree().process_frame
	check(board.carrying == id, "M takes hold of it")
	_press("rotate_right")
	await get_tree().process_frame
	_press("rotate_right")
	await get_tree().process_frame
	_press("board_move")
	await get_tree().process_frame
	var m: Dictionary = Shed.board["marks"][BoardData.find(Shed.board, id)]
	check(board.carrying == 0 and is_equal_approx(BoardData.rotation_of(m), 30.0), "two presses while moving it turn it 30 degrees (%.1f)" % BoardData.rotation_of(m))
	for i in 2:
		await get_tree().process_frame
	check(board._nodes.get(id) is TextureRect and is_equal_approx((board._nodes[id] as Control).rotation, deg_to_rad(30.0)), "the board draws it turned")
	_press("rotate_left")
	await get_tree().process_frame
	m = Shed.board["marks"][BoardData.find(Shed.board, id)]
	check(is_equal_approx(BoardData.rotation_of(m), 15.0), "looking at it, a press turns it back a step (%.1f)" % BoardData.rotation_of(m))
	var copy: Dictionary = str_to_var(var_to_str(main.saver.capture()["shed"]))
	Shed.load_state(copy, "Tester")
	check(is_equal_approx(BoardData.rotation_of(Shed.board["marks"][BoardData.find(Shed.board, id)]), 15.0), "its turn is kept with the shed")
	Shed.board_request({"a": "board_undo"})
	check(BoardData.find(Shed.board, id) < 0, "undo still takes it off")
	Settings.snap_placement = kept
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_poster_sizes() -> void:
	var a1 := Equipment.poster_size("poster_tt", "a1")
	check(is_equal_approx(maxf(a1.x, a1.y), 0.841) and absf(a1.x / a1.y - 0.6 / 0.85) < 0.001, "an A1 print keeps the design's shape, 841 mm tall (%s)" % str(a1))
	check(Equipment.poster_size("poster_tt", "a2").y < a1.y and Equipment.poster_size("poster_tt", "a0").y > a1.y, "A2 is smaller and A0 bigger")
	var ban := Equipment.poster_size("poster_tt", "banner")
	check(ban.x > 2.0 and ban.x > ban.y * 2.5, "the large banner is a long, wide strip (%s)" % str(ban))
	check(Equipment.poster_size("poster_tt", "") == Equipment.get_model("poster_tt")["size"], "a poster from before sizes keeps its own size")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var me := Shed.me()
	Shed.request({"a": "order_furniture", "model": "poster_tt", "psize": "a0"})
	var p := _first_furniture("poster_tt")
	check(p != 0 and Shed.furniture[p]["psize"] == "a0" and Shed.furniture_size(Shed.furniture[p]).is_equal_approx(Equipment.poster_size("poster_tt", "a0")),
		"ordered in A0, it's that big")
	check(Shed.check(me, {"a": "order_furniture", "model": "poster_tt", "psize": "a9"}) != ""
		and Shed.check(me, {"a": "order_furniture", "model": "tv_120", "psize": "a1"}) != "", "only the poster sizes are sold, and only for posters")
	Shed.posters[900] = {"id": 900, "name": "Plan", "by": "Tester", "blob": 0, "imgs": []}
	Shed.request({"a": "order_furniture", "model": Equipment.BOARD_POSTER, "design": 900, "psize": "banner"})
	var bp := _first_furniture(Equipment.BOARD_POSTER)
	var bsize := Shed.furniture_size(Shed.furniture.get(bp, {}))
	check(bp != 0 and is_equal_approx(bsize.x, 2.4) and is_equal_approx(bsize.y, 1.2), "a whiteboard poster as a banner keeps the board's shape (%s)" % str(bsize))
	# Turned before it's hung, a quarter at a time.
	check(Shed.check(me, {"a": "turn_poster", "furniture": p, "turn": 1}) != "", "you turn a poster while you're carrying it")
	Shed.request({"a": "grab", "furniture": p})
	for i in 2:
		await get_tree().physics_frame
	_press("rotate_left")
	await get_tree().physics_frame
	var turned := Shed.furniture_size(Shed.furniture[p])
	check(Shed.furniture[p]["turn"] == 1 and is_equal_approx(turned.x, Equipment.poster_size("poster_tt", "a0").y), "the rotate key turns it on its side, landscape")
	check(w.info.contains("portrait or landscape"), "the panel says how to turn it")
	Shed.changed.emit()
	for i in 2:
		await get_tree().process_frame
	var view: EquipmentView = main.workshop.furniture_nodes[p]
	var sheet: Node3D = view.get_node_or_null("PosterArt")
	check(view.look.ends_with("|1") and sheet != null and is_equal_approx(sheet.rotation.z, PI * 0.5), "and it's drawn turned")
	Shed.request({"a": "turn_poster", "furniture": p, "turn": -2})
	check(Shed.furniture[p]["turn"] == 2, "turns go round in quarters")
	Shed.request({"a": "release", "furniture": p, "xf": Shed.furniture[p]["xf"]})
	Shed.request({"a": "order_furniture", "model": "tv_120"})
	var tv := _first_furniture("tv_120")
	Shed.request({"a": "grab", "furniture": tv})
	check(Shed.check(me, {"a": "turn_poster", "furniture": tv, "turn": 1}).contains("one way"), "a TV doesn't turn")
	Shed.request({"a": "release", "furniture": tv, "xf": Shed.furniture[tv]["xf"]})
	Shed.load_state(str_to_var(var_to_str(Shed._snapshot())), "Tester")
	check(Shed.furniture[p]["psize"] == "a0" and Shed.furniture[p]["turn"] == 2, "size and turn are kept with the shed")
	# The parts computer sells every design in each size.
	var pc: PartsComputer = main.computer
	pc._show_section("shed")
	pc._show_kind("eq:poster")
	pc._pick_part("poster_cafe")
	check(pc._sizes.visible and pc._size_btns.size() == Equipment.POSTER_SIZE_ORDER.size(), "the poster page has a size for each print")
	pc.pick_poster_size("banner")
	check(pc._spec.text.contains("Large banner"), "picking a size shows it (%s)" % pc._spec.text)
	pc._order.pressed.emit()
	var cafe := _first_furniture("poster_cafe")
	check(cafe != 0 and Shed.furniture[cafe]["psize"] == "banner", "and the order comes in that size")
	pc._pick_part("design:900")
	check(pc._sizes.visible, "whiteboard posters come in the sizes too")
	pc.pick_poster_size(Equipment.POSTER_SIZE_DEFAULT)
	pc._pick_part("tv_120")
	check(not pc._sizes.visible, "other kit has no sizes")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_tail_fairing_mirrors_parts() -> void:
	for k in ["tail", "fairing", "mirrors"]:
		check(PartsDB.by_kind[k].size() >= 5, "the shop has %d %s parts" % [PartsDB.by_kind[k].size(), k])
		for id in PartsDB.by_kind[k]:
			if PartsDB.spec_line(id) == "":
				check(false, "%s has a spec line" % id)
	check(not PartsDB.is_optional("tail") and PartsDB.is_optional("fairing") and PartsDB.is_optional("mirrors"),
		"every bike needs a tail unit; fairings and mirrors are extras")
	check(PartsDB.dependents("headlight").has("fairing") and PartsDB.dependents("handlebars").has("mirrors")
		and PartsDB.dependents("frame").has("tail"), "the fairing comes off before the headlight, the mirrors before the bars")
	check(PartsDB.part_mounts("mirrors", "fairing_mirrors").has("fairing") and not PartsDB.part_mounts("mirrors", "round_mirrors").has("fairing"),
		"fairing-mount mirrors need the fairing; bar mirrors don't")
	# A build from before tail units gets the one that suits it.
	var tails := {"flat_bench": "classic_mudguard", "cafe_hump": "cafe_tail", "sport_solo": "sport_tail_tidy", "enduro_seat": "enduro_fender"}
	for saddle in tails:
		check(PartsDB.sanitize_build({"saddle": saddle})["tail"] == tails[saddle], "a bike with a %s gets a %s" % [saddle, tails[saddle]])
	check(PartsDB.sanitize_build({"rear_tyre": "knobbly_mx"})["tail"] == "scrambler_loop", "and knobblies on a bench seat get a scrambler loop")
	check(PartsDB.sanitize_build({"tail": "bobber_fender"})["tail"] == "bobber_fender", "a chosen tail stays")
	var old := BikeBuild.new({})
	check(old.parts["fairing"] == "none" and old.parts["mirrors"] == "none", "and no fairing or mirrors")
	# The fairing cuts drag: more top speed, a bit more weight. A battered one helps less.
	var race := BikeBuild.new({"fairing": "race_fairing"})
	# Geared tall so it runs out of power, not revs.
	var tall := {"sprocket_f": 18.0, "sprocket_r": 36.0}
	var bare_top := BikeBuild.new({}, {}, tall).top_speed_estimate()
	var race_top := BikeBuild.new({"fairing": "race_fairing"}, {}, tall).top_speed_estimate()
	check(race.cda < old.cda - 0.08 and race_top > bare_top + 3.0 and race.bike_mass > old.bike_mass + 6.0,
		"a full race fairing: %.0f -> %.0f km/h, %.0f -> %.0f kg" % [bare_top * 3.6, race_top * 3.6, old.bike_mass, race.bike_mass])
	var tired := BikeBuild.new({"fairing": "race_fairing"}, {"fairing": {"wear": 1.0, "dirt": 1.0}})
	check(tired.cda > race.cda and tired.cda < old.cda, "a cracked, filthy fairing parts the air less well")
	check(BikeBuild.new({"fairing": "carbon_race_fairing"}).bike_mass < race.bike_mass - 2.0, "the carbon one is far lighter")
	check(BikeBuild.new({"mirrors": "touring_mirrors"}).cda > old.cda, "mirrors stick out into the wind a little")
	check(BikeBuild.new({"tail": "enduro_fender"}).bike_mass < BikeBuild.new({"tail": "classic_mudguard"}).bike_mass,
		"a plastic fender weighs less than a steel mudguard")
	# Recycling: what each is made of.
	check(PartsDB.bin_for("classic_mudguard") == "metal" and PartsDB.bin_for("enduro_fender") == "plastic"
		and PartsDB.bin_for("half_fairing") == "plastic" and PartsDB.bin_for("carbon_race_fairing") == "general"
		and PartsDB.bin_for("round_mirrors") == "general", "steel guards go in metal, plastic in plastic, carbon and mirrors in general")
	# Every variant draws, with the rear light where the tail unit puts it.
	var lamps := {}
	for id in PartsDB.by_kind["tail"]:
		var m := BikeModel.new()
		add_child(m)
		m.build_from(BikeBuild.new({"tail": id}))
		var light: Node = m.find_child("TailLight", true, false)
		check(m.slot_bounds("tail").size.length() > 0.1 and light != null and m.tail_light_position() != Vector3.ZERO,
			"the %s is drawn, rear light and all" % id)
		lamps[m.tail_light_position().snapped(Vector3.ONE * 0.01)] = true
		m.free()
	check(lamps.size() >= 5, "each tail puts the rear light somewhere of its own (%d places)" % lamps.size())
	for id in PartsDB.by_kind["fairing"]:
		var m := BikeModel.new()
		add_child(m)
		m.build_from(BikeBuild.new({"fairing": id, "mirrors": "fairing_mirrors"}))
		check(m.slot_bounds("fairing").size.length() > 0.2 and m.slot_bounds("mirrors").size.length() > 0.1,
			"the %s and its mirrors are drawn" % id)
		check(m.slot_bounds("fairing").get_center().z < m.slot_bounds("tank").get_center().z, "round the front of the bike")
		m.free()
	for id in PartsDB.by_kind["mirrors"]:
		var m := BikeModel.new()
		add_child(m)
		m.build_from(BikeBuild.new({"mirrors": id}))
		var glass: Node = m.find_child("MirrorGlass*", true, false)
		var mat: StandardMaterial3D = (glass as MeshInstance3D).material_override if glass is MeshInstance3D else null
		check(m.slot_bounds("mirrors").size.x > 0.3 and mat != null and mat.metallic > 0.9 and mat.roughness < 0.05,
			"the %s are drawn, with mirror glass" % id)
		m.free()
	var bare := BikeModel.new()
	add_child(bare)
	bare.build_from(BikeBuild.new({}), Color.RED, {"tail": false})
	check(not bare.is_fitted("tail"), "with the tail unit off, it and its light are gone")
	bare.free()


func _test_tail_fairing_mirrors_shed() -> void:
	Shed.start_new("Tester", 41)
	var me := Shed.me()
	var expect := {"Rusty Ranger": "enduro_fender", "Barn Find": "cafe_tail", "Old Faithful": "sport_tail_tidy"}
	var sport := 0
	for id in Shed.bikes:
		var tail := Shed.item_on(id, "tail")
		var want := str(expect.get(Shed.bikes[id]["name"], ""))
		check(tail != 0 and Shed.is_bolted(id, "tail") and str(Shed.items[tail]["part"]) == want,
			"%s comes with its %s bolted on" % [Shed.bikes[id]["name"], want])
		if Shed.bikes[id]["name"] == "Old Faithful":
			sport = id
	check(not Shed.missing_slots(sport).has("fairing") and not Shed.missing_slots(sport).has("mirrors"), "no fairing or mirrors needed to ride")
	# Fitting order: mirrors on the fairing need the fairing, the fairing needs the headlight.
	var fairing := Shed._new_item("half_fairing", 0.0, 0.0, 0.0)
	var mirrors := Shed._new_item("fairing_mirrors", 0.0, 0.0, 0.0)
	Shed._move(mirrors, "held", me)
	check(Shed.check(me, {"a": "install", "bike": sport, "slot": "mirrors"}).contains("fairing first"), "fairing mirrors need the fairing on first")
	Shed._move(mirrors, "spot", "bench_0")
	var lamp := Shed.item_on(sport, "headlight")
	Shed.bikes[sport]["slots"]["headlight"] = 0
	Shed._move(lamp, "spot", "bench_1")
	Shed._move(fairing, "held", me)
	check(Shed.check(me, {"a": "install", "bike": sport, "slot": "fairing"}).contains("headlight first"), "a fairing goes on over the headlight")
	Shed.bikes[sport]["slots"]["headlight"] = lamp
	Shed._move(lamp, "bike", sport)
	check(Shed.check(me, {"a": "install", "bike": sport, "slot": "fairing"}) == "", "with the headlight on, the fairing fits")
	Shed.request({"a": "install", "bike": sport, "slot": "fairing"})
	Shed.request({"a": "bolt", "bike": sport, "slot": "fairing"})
	check(Shed.item_on(sport, "fairing") == fairing and Shed.is_bolted(sport, "fairing"), "and bolts up")
	Shed._move(mirrors, "held", me)
	Shed.request({"a": "install", "bike": sport, "slot": "mirrors"})
	Shed.request({"a": "bolt", "bike": sport, "slot": "mirrors"})
	check(Shed.item_on(sport, "mirrors") == mirrors, "then its mirrors go on")
	Shed.request({"a": "unbolt", "bike": sport, "slot": "headlight"})
	check(Shed.check(me, {"a": "remove", "bike": sport, "slot": "headlight"}).contains("fairing off first"), "the headlight can't come out from under the fairing")
	Shed.request({"a": "unbolt", "bike": sport, "slot": "fairing"})
	check(Shed.check(me, {"a": "remove", "bike": sport, "slot": "fairing"}).contains("mirrors off first"), "nor the fairing with its mirrors on")
	Shed.request({"a": "bolt", "bike": sport, "slot": "fairing"})
	Shed.request({"a": "bolt", "bike": sport, "slot": "headlight"})
	var build := Shed.build_of(sport)
	check(build.parts["fairing"] == "half_fairing" and build.cda < BikeBuild.new(Shed.bikes[sport]["original"]).cda,
		"the bike's numbers count the fairing")
	check(Shed.condition_text(Shed.items[fairing]) != "" and build.condition.has("tail") and build.condition.has("fairing"),
		"they have a condition of their own")
	# A blueprint keeps them, and the save keeps everything.
	var bp := Shed._save_blueprint(sport, "Faired")
	check(str(Shed.blueprints[bp]["parts"]["fairing"]) == "half_fairing" and str(Shed.blueprints[bp]["parts"]["tail"]) == "sport_tail_tidy"
		and str(Shed.blueprints[bp]["parts"]["mirrors"]) == "fairing_mirrors", "a blueprint stores the tail, fairing and mirrors")
	var was := SaveGame.slot_override
	SaveGame.slot_override = "test_tail_fairing"
	check(SaveGame.write(SaveGame.active_slot(), {"version": SaveGame.VERSION, "shed": Shed.save_snapshot()}) == OK, "the shed saves")
	var back := SaveGame.read(SaveGame.active_slot())
	SaveGame.delete_slot(SaveGame.active_slot())
	SaveGame.slot_override = was
	Shed.start_new("Tester", 42)
	Shed.load_state(back.get("shed", {}), "Tester")
	var f := Shed.item_on(sport, "fairing")
	var mi := Shed.item_on(sport, "mirrors")
	check(f != 0 and mi != 0 and str(Shed.items[f]["part"]) == "half_fairing" and str(Shed.items[mi]["part"]) == "fairing_mirrors"
		and str(Shed.items[Shed.item_on(sport, "tail")]["part"]) == "sport_tail_tidy", "and loads with the tail, fairing and mirrors on")


func _test_tail_old_save() -> void:
	Shed.start_new("Tester", 43)
	var old: Dictionary = Shed._snapshot().duplicate(true)
	# Take the shed back to before tail units, fairings and mirrors.
	var stripped := 0
	for id in old["bikes"]:
		var bike: Dictionary = old["bikes"][id]
		for slot in ["tail", "fairing", "mirrors"]:
			var item := int(bike["slots"].get(slot, 0))
			if item != 0:
				old["items"].erase(item)
			bike["slots"].erase(slot)
			bike["bolted"].erase(slot)
			bike["original"].erase(slot)
		if bike["name"] == "Barn Find":
			stripped = id
	# One bike has lost its frame too: its new tail unit waits on the bench.
	var frame := int(old["bikes"][stripped]["slots"]["frame"])
	old["bikes"][stripped]["slots"]["frame"] = 0
	old["items"][frame]["at"] = "spot"
	old["items"][frame]["ref"] = "bench_3"
	var parts := PartsDB.sanitize_build({"saddle": "enduro_seat"})
	parts.erase("tail")
	parts.erase("fairing")
	old["blueprints"] = {9000: {"id": 9000, "name": "Old plan", "parts": parts, "colors": {}, "paint": Shed.PAINTS[0], "geo": {}, "from": "x"}}
	Shed.start_new("Tester", 44)
	Shed.load_state(old, "Tester")
	for id in Shed.bikes:
		var tail := Shed.item_on(id, "tail")
		if id == stripped:
			var loose := Shed.items.values().filter(func(it): return it["kind"] == "tail" and it["at"] == "spot")
			check(tail == 0 and loose.size() == 1 and str(loose[0]["part"]) == "cafe_tail", "a bike with no frame gets its tail unit on the bench")
		else:
			check(tail != 0 and Shed.is_bolted(id, "tail") and Shed.items[tail]["at"] == "bike",
				"an old save's %s gets a %s fitted" % [Shed.bikes[id]["name"], Shed.items[tail]["part"] if tail != 0 else "nothing"])
			check(not Shed.missing_slots(id).has("tail"), "so it's no part short")
		check(Shed.item_on(id, "fairing") == 0 and Shed.bikes[id]["slots"].has("mirrors") and Shed.bikes[id]["original"].has("tail"),
			"with empty fairing and mirror slots")
	check(str(Shed.blueprints[9000]["parts"].get("tail", "")) == "enduro_fender", "an old blueprint gets a tail that suits it")
	var rows := Shed.plan_rows(Shed.blueprints[9000], 0)
	check(rows.any(func(r): return r["slot"] == "tail"), "so a build from it orders one")
	check(Shed._next_id > Shed.items.keys().max(), "new parts get fresh ids")



## The headlight is a soft core that lights the road and a wide, dim flood round it that is the
## only light in the fog: both fade from the middle, with a blurred round projector, so neither
## the pool on the road nor the haze in the air has an edge.
func _test_soft_beam() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var dl := Daylight.new()
	add_child(dl)
	var cycle := Settings.day_night_cycle
	Settings.day_night_cycle = false
	dl.setup(env, sun)
	dl.set_time(0.0)
	var fx := BikeEffects.new()
	add_child(fx)
	fx.setup(Vector3(0.2, 0.4, 0.8), Vector3(0.0, 0.0, 0.7), Vector3(0.0, 1.0, -0.8), 1200.0)
	fx.beam_mode = 1
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	var core: SpotLight3D = fx._beam
	var flood: SpotLight3D = fx._flood
	check(core != null and flood != null and flood.get_parent() == core, "the headlight has a core and a flood round it")
	check(flood.spot_angle >= core.spot_angle + 10.0 and flood.light_energy < core.light_energy * 0.5,
		"the flood is much wider (%.0f vs %.0f degrees) and dimmer" % [flood.spot_angle, core.spot_angle])
	check(core.spot_angle_attenuation < 1.0 and flood.spot_angle_attenuation < 0.5,
		"both fade from the middle outwards (falloff %.2f / %.2f), nothing left at the edge" % [core.spot_angle_attenuation, flood.spot_angle_attenuation])
	check(core.light_projector is GradientTexture2D and flood.light_projector == core.light_projector,
		"a blurred round projector softens the pool of light on the road")
	var tex := BikeEffects.soft_spot_texture()
	var mid := tex.gradient.sample(0.0).r
	var rim := tex.gradient.sample(1.0).r
	var half := tex.gradient.sample(0.5).r
	check(tex.fill == GradientTexture2D.FILL_RADIAL and is_equal_approx(tex.fill_to.x - tex.fill_from.x, 0.5),
		"a round spot that reaches black at the cone's edge")
	check(mid > 0.9 and rim < 0.05 and half > rim and half < mid, "the projector fades smoothly from white to black (%.2f, %.2f, %.2f)" % [mid, half, rim])
	check(core.light_volumetric_fog_energy == 0.0 and flood.light_volumetric_fog_energy > 0.0,
		"only the soft flood lights the night air, never the bright core")
	check(fx.beam_fog() > 0.5 and fx.beam_fog() <= BikeEffects.BEAM_FOG_LOW + 0.01, "the haze is faint (%.2f)" % fx.beam_fog())
	check(env.volumetric_fog_density <= 0.0095, "the night air is only lightly hazy (%.4f)" % env.volumetric_fog_density)
	fx.beam_mode = 2
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	check(flood.spot_angle > core.spot_angle and fx.beam_fog() <= BikeEffects.BEAM_FOG_HIGH + 0.01,
		"high beam: the flood still spreads round the narrower core, still faint (%.2f)" % fx.beam_fog())
	dl.set_time(12.0)
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	check(fx.beam_fog() < 0.01, "by day nothing shows in the air")
	Settings.day_night_cycle = cycle
	fx.queue_free()
	dl.queue_free()
	sun.queue_free()
	await get_tree().process_frame


## Tyre sounds: a long skid settles to a quieter screech; the moment grip breaks the tyre barks
## loudly, harder the faster grip goes.
func _test_skid_sounds() -> void:
	var start := BikeEffects.screech_gain(1.0, 0.0, 1.0)
	var held := BikeEffects.screech_gain(1.0, 3.0, 0.0)
	check(held < start * 0.6 and held <= 0.3, "a long skid is much quieter (%.2f) than the moment it starts (%.2f)" % [held, start])
	check(BikeEffects.screech_gain(0.3, 3.0, 0.0) < held, "a light slide is quieter still")
	check(BikeEffects.CHIRP_MAX_DB > 0.0 and BikeEffects.CHIRP_MAX_DB - BikeEffects.CHIRP_MIN_DB >= 10.0,
		"the bark when grip breaks is loud, and scales with how suddenly it goes")
	var fx := BikeEffects.new()
	add_child(fx)
	fx.set_screech(0.0)
	fx.set_screech(0.0)
	check(fx.chirp_count() == 0, "no sound while the tyres grip")
	fx.set_screech(0.9)
	check(fx.screeching(), "grip breaking starts the squeal")
	for i in 12:
		fx.set_screech(0.9)
	check(fx.chirp_count() == 1, "and a moment later the tyre barks once")
	var hard := fx.last_chirp
	for i in 30:
		fx.set_screech(0.85 + 0.1 * (i % 2))
	check(fx.chirp_count() == 1, "a slide that goes on doesn't keep barking")
	for i in 60:
		fx.set_screech(0.0)
	for i in 20:
		fx.set_screech(0.3)
	check(fx.chirp_count() == 2 and fx.last_chirp < hard, "a gentler break barks more softly (%.2f vs %.2f)" % [fx.last_chirp, hard])
	for i in 60:
		fx.set_screech(0.0)
	for i in 20:
		fx.set_screech(0.1)
	check(fx.chirp_count() == 2, "a tyre only just scrubbing doesn't bark")
	var wav := Sfx.stream("chirp")
	check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED and wav.get_length() < 0.6, "the bark is a short one-shot")
	fx.free()
	# On the road: stamp on the back brake at speed and the tyre barks as it locks.
	var r := await ride({}, 7.0, func(b, t):
		b.throttle = 1.0 if t < 5.0 else 0.0
		b.rear_brake = 0.0 if t < 5.0 else 1.0)
	var bike: Bike = r["bike"]
	check(bike.effects.chirp_count() >= 1, "locking the back wheel barks (%d)" % bike.effects.chirp_count())
	await _done(r)


## The Esc menu's Debug tab: reset or max your XP and money, reset everyone's XP, and empty the
## garage's account, every reset behind a confirm dialog. Money is kept in your profile and the
## garage's in the shed save, and the TV money pages show both.
func _test_debug_tab() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_debug_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Tester", 5)
	Progress.select("Tester")
	var me := Shed.me()
	check(Progress.money() == 0 and Shed.garage_money == Money.START_FUNDS, "money starts at nothing for you, and the starting funds for the garage")
	var tab := DebugTab.new()
	add_child(tab)
	Progress.profile["xp"] = Progress.xp_for_level(6)
	Progress.profile["tools"] = {"wrench": 2}
	tab.press("Reset my XP")
	check(tab.asking() and int(Progress.profile["xp"]) > 0, "Reset my XP asks first")
	tab.answer(false)
	check(not tab.asking() and Progress.level() == 6, "cancel leaves it alone")
	tab.press("Reset my XP")
	tab.answer(true)
	check(int(Progress.profile["xp"]) == 0 and Progress.level() == 1 and Progress.tool_stage(me, "wrench") == 0,
		"confirmed: back to level 1, no upgrades")
	tab.press("Max my XP")
	check(Progress.level() == Progress.MAX_LEVEL and Progress.skill_points() == Progress.MAX_LEVEL - 1, "Max my XP: top level, every point to spend")
	tab.press("Reset everyone's XP")
	check(tab.asking(), "resetting everyone asks first")
	tab.answer(true)
	check(Progress.level() == 1, "solo or hosting, everyone's XP goes (yours here; the host tells each client)")
	tab.press("Max my money")
	check(Progress.money() == Progress.MAX_MONEY and int(TvChannels.money_data(me)["cash"]) == Progress.MAX_MONEY,
		"Max my money, and the My money page shows it")
	check(int(Progress.summary(me)["money"]) == Progress.MAX_MONEY and int(Progress._clean_summary(Progress.own_summary())["money"]) == Progress.MAX_MONEY,
		"your money goes to the crew in your summary")
	Progress.save_profile()
	Progress.select("Somebody else")
	check(Progress.money() == 0, "another name has its own money")
	Progress.select("Tester")
	check(Progress.money() == Progress.MAX_MONEY, "money is kept in the profile")
	tab.press("Reset my money")
	check(tab.asking() and Progress.money() == Progress.MAX_MONEY, "Reset my money asks first")
	tab.answer(true)
	check(Progress.money() == 0, "and empties your pocket")
	Shed.garage_money = 5000
	check(int(TvChannels.garage_data()["cash"]) == 5000, "the Garage money page shows the shed's account")
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	tab.press("Reset garage money")
	check(tab.asking() and Shed.garage_money == 5000, "Reset garage money asks first")
	tab.answer(true)
	check(Shed.garage_money == 0, "and empties the shed's account")
	Shed.load_state(copy, "Tester")
	check(Shed.garage_money == 5000, "the garage's money is kept in the shed save")
	copy.erase("garage_money")
	copy.erase("bank")
	Shed.load_state(copy, "Tester")
	check(Shed.garage_money == Money.START_FUNDS, "a shed saved before money opens with the starting funds")
	tab.free()
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


## The weather on its own: each kind's look, changing by itself or held, wet roads and grip,
## and how Daylight greys the sky and thickens the fog.
func _test_weather() -> void:
	var kept := [Settings.weather, Settings.weather_now, Settings.day_night_cycle]
	Settings.weather = "clear"
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var dl := Daylight.new()
	add_child(dl)
	Settings.day_night_cycle = false
	var w := Weather.new()
	add_child(w)
	dl.setup(env, sun)
	dl.set_time(12.0)
	check(Weather.current == w and w.state == "clear" and Weather.rain_level() == 0.0, "held clear, it's clear")
	var clear_fog := env.fog_density
	var clear_sun := sun.light_energy
	check(Weather.grip_mult("tarmac") == 1.0, "dry roads grip fully")
	Settings.weather = "rain"
	await get_tree().process_frame
	await get_tree().process_frame
	check(w.state == "rain" and w.blend < 0.5 and w.rain < 0.5, "held at rain, it turns to rain gradually (%s from %s, %.2f, rain %.2f)" % [w.state, w.from, w.blend, w.rain])
	w.change_to("rain", true)
	dl.set_time(12.0)
	check(Weather.rain_level() == 1.0 and Weather.wetness() == 1.0 and Weather.cover_level() == 1.0, "rain: overcast, raining, soaked")
	check(Weather.grip_mult("tarmac") < 0.9 and Weather.grip_mult("tarmac") > 0.75, "wet tarmac grips a bit less (%.2f)" % Weather.grip_mult("tarmac"))
	check(sun.light_energy < clear_sun * 0.5 and sun.shadow_opacity < 0.6, "the sun is dimmed behind the cloud, shadows soft")
	check(env.fog_density > clear_fog and float(dl._sky_mat.get_shader_parameter("cloud_cover")) == 1.0, "the sky clouds over and the air hazes")
	Settings.weather = "fog"
	w.change_to("fog", true)
	dl.set_time(12.0)
	check(env.fog_density > 0.02 and env.fog_sky_affect > 0.8, "fog: thick depth fog, on every renderer (%.3f)" % env.fog_density)
	check(Weather.rain_level() == 0.0, "no rain in the fog")
	# Drying out after rain.
	w.wet = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(w.wet < 1.0, "after the rain the roads slowly dry")
	# Changing by itself: when a spell ends it moves on to one of the kinds that can follow.
	Settings.weather = "auto"
	w.change_to("clear", true)
	w._spell = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(w.state in Weather.NEXT["clear"] and w.state != "clear", "left to itself, clear skies turn to %s" % w.state)
	check(w._spell >= Weather.SPELL.x - 1.0, "and the new spell lasts a few minutes")
	var data := w.save_data()
	w.change_to("clear", true)
	w.restore(data)
	check(w.state == str(data["state"]) and w.blend == 1.0, "saved weather comes back")
	check(Weather.state_name("rain") == "Rain" and Weather.STATES.size() == 4, "four kinds of weather")
	Settings.weather = kept[0]
	Settings.weather_now = kept[1]
	Settings.day_night_cycle = kept[2]
	w.queue_free()
	dl.queue_free()
	sun.queue_free()
	await get_tree().process_frame


## The weather in the shed: rain round the camera outside but never drawn in the rooms, the
## rain heard outside and on the roof inside, darker shinier roads, the Esc menu setting and
## its saved state. And the day length row in the menu is one normal line.
func _test_weather_session() -> void:
	var kept := [Settings.weather, Settings.weather_now]
	SaveGame.slot_override = "test_weather"
	SaveGame.delete_slot("test_weather")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	var w: Weather = main.world.weather
	check(w != null and Weather.current == w, "the world has weather")
	Settings.weather = "rain"
	w.change_to("rain", true)
	main.walker.place(Transform3D(Basis(), Vector3(0.0, 0.1, 85.0)))
	for i in 6:
		await get_tree().process_frame
	check(not w.indoors and w._rain_mesh.visible and w._outside.playing and not w._roof.playing, "outside in the rain: rain falls round you and you hear it")
	check(Weather.raining_at(Vector3(0.0, 0.0, 85.0)) and not Weather.raining_at(Workshop.CENTER), "it rains in the yard, not in the shed")
	var shelters: PackedVector4Array = w._rain_mat.get_shader_parameter("shelters")
	var c := Workshop.CENTER
	check(shelters.size() == Weather.SHELTERS and shelters[0].x < c.x and shelters[0].z > c.x and shelters[0].y < c.z and shelters[0].w > c.z,
		"no drops are drawn inside the shed's rooms")
	main.walker.place(Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.1, 1.0)))
	for i in 90:
		await get_tree().process_frame
	check(w.indoors and w._roof.playing and not w._outside.playing, "inside the shed you hear it drumming on the roof instead")
	var road: Dictionary = main.world.wet_surfaces.filter(func(e): return float(e["shine"]) == 1.0)[0]
	var mat: StandardMaterial3D = road["mat"]
	check(mat.albedo_color.v < (road["color"] as Color).v and mat.roughness < float(road["rough"]) - 0.3,
		"the tarmac is darker and shinier in the wet")
	# The Esc menu: the weather setting, and the day length on one normal line.
	main.menu.show_pause()
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: MainMenu = main.menu
	check(menu._weather.selected == Weather.STATES.find("rain") + 1, "the menu shows the weather held at rain")
	menu._weather.select(0)
	menu._weather.item_selected.emit(0)
	check(Settings.weather == "auto", "and can leave it to change by itself")
	var row := menu._day_length.get_parent() as Control
	check(row.size.y < 60.0, "the day length row is one normal line (%.0f px tall)" % row.size.y)
	var label: Label = row.get_child(1)
	check(label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.size.x > 60.0, "its label reads across, not down")
	main._close_menu()
	# Saved with the shed.
	Settings.weather = "fog"
	w.change_to("fog", true)
	var data: Dictionary = main.saver.capture()
	check(str(data["weather"]["state"]) == "fog" and str(data["weather_mode"]) == "fog", "the save keeps the weather")
	Settings.weather = "clear"
	w.change_to("clear", true)
	main.saver.restore(data)
	check(w.state == "fog" and Settings.weather == "fog", "and puts it back")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	SaveGame.delete_slot("test_weather")
	SaveGame.slot_override = ""
	Settings.weather = kept[0]
	Settings.weather_now = kept[1]


## The sandblasting cabinets take the biggest engine there is, ancillaries and all, with room to
## turn it right round and tip it over, and have no lamp inside.
func _test_blast_cabinet_fits() -> void:
	for cab in Equipment.by_kind("blaster"):
		var inside := Equipment.blaster_inside(cab)
		var floor_y: float = inside["floor"]
		var roof: float = inside["roof"]
		var hw: float = inside["half_w"]
		var back: float = inside["back"]
		var front: float = inside["front"]
		var g0 := Vector2(float(inside["front_top"]), front)
		var g1 := Vector2(roof, float(inside["glass_z"]))
		var glass_dir := (g1 - g0).normalized()
		var worst := INF
		var worst_engine := ""
		for id in PartsDB.by_kind["engine"]:
			var parts := {"engine": id, "cooling": "race_radiator"}
			for slot in PartsDB.ENGINE_SLOTS:
				if not parts.has(slot):
					parts[slot] = PartsDB.DEFAULT_BUILD[slot]
			var d: Node3D = BikeModel.assembly_display(parts, {})
			var size: Vector3 = d.get_meta("size")
			d.free()
			var centre := Equipment.local_place(cab, 0).origin + Vector3.UP * Equipment.blaster_lift(size)
			for yaw in 12:
				for pitch in [-BlastGame.PITCH_LIMIT, -0.6, 0.0, 0.6, BlastGame.PITCH_LIMIT]:
					var b := BlastGame.pivot_basis(Vector2(yaw * PI / 6.0, pitch))
					for corner in 8:
						var c := Vector3(size.x * (0.5 if corner & 1 else -0.5), size.y * (0.5 if corner & 2 else -0.5),
							size.z * (0.5 if corner & 4 else -0.5))
						var p := centre + b * c
						# Room to the walls, the grate, the roof and the sloping glass.
						var rel := Vector2(p.y, p.z) - g0
						var to_glass := rel.x * glass_dir.y - rel.y * glass_dir.x
						var room := minf(minf(hw - absf(p.x), minf(p.z - back, front - p.z)), minf(p.y - floor_y, roof - p.y))
						room = minf(room, to_glass)
						if room < worst:
							worst = room
							worst_engine = id
		check(worst > 0.0, "the %s takes every engine with room to turn it right over (closest %.0f mm, %s)" % [
			Equipment.get_model(cab)["name"], worst * 1000.0, worst_engine])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	Shed.request({"a": "order_furniture", "model": "blaster_cabinet"})
	await get_tree().process_frame
	var lamps := 0
	var views := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "blaster":
			views += 1
			var stack: Array = [main.workshop.furniture_nodes[id]]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is Light3D:
					lamps += 1
				stack.append_array(n.get_children())
	check(views > 0 and lamps == 0, "no light inside the sandblaster: you see in by the shed's light")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The close-up engine in the cabinet: more castings, bolts and fins, each in its part's own
## material; and the satin bare-metal mask that turns the surface over as you blast.
func _test_blast_detail_and_satin() -> void:
	var parts := {"engine": "twin_700"}
	for slot in PartsDB.ENGINE_SLOTS:
		parts[slot] = PartsDB.DEFAULT_BUILD[slot]
	var d: Node3D = BikeModel.assembly_display(parts, {})
	add_child(d)
	var m: BikeModel = d.get_meta("model")
	var before := {}
	for slot in m._slot_meshes:
		before[slot] = (m._slot_meshes[slot] as Array).size()
	var added := BlastDetail.add_to(m)
	var grown := []
	for slot in ["engine", "head", "fuel", "gearbox", "oil_filter"]:
		if (m._slot_meshes[slot] as Array).size() > int(before[slot]):
			grown.append(slot)
	check(added > 60 and grown.size() == 5, "the cabinet's close-up engine gets castings, fins and bolts on every part (%d pieces on %s)" % [added, ", ".join(grown)])
	check(BlastDetail.add_to(m) == 0, "and only once")
	var pts: PackedVector3Array = m.surface_points("engine", 0.03)[0]
	check(pts.size() > 300, "the coverage map covers the new detail too (%d patches on the engine)" % pts.size())
	var marks := BlastMarks.new()
	marks.setup(m, ["engine", "head", "oil_filter"], BlastGame.OVER)
	m.add_child(marks)
	var mi: GeometryInstance3D = m._slot_meshes["engine"][0]
	var mat := mi.material_override as BaseMaterial3D
	check(mat != null and mat.next_pass is ShaderMaterial and (mat.next_pass as ShaderMaterial).get_shader_parameter("mask") is ImageTexture3D,
		"each part's surface reads the bare-metal mask on top of its own finish")
	var alu: Vector3 = marks.material_for("engine").get_shader_parameter("bare_color")
	var steel: Vector3 = marks.material_for("oil_filter").get_shader_parameter("bare_color")
	check(alu.x > steel.x + 0.1, "castings come up satin aluminium, steel parts bare steel")
	# Blast one spot: it goes bare right there and nowhere else, so missed bits show.
	var b := m.slot_bounds("engine")
	var at := Vector3(b.end.x, b.get_center().y, b.get_center().z)
	for i in 40:
		marks.paint(at, Vector3.LEFT, BlastGame.RADIUS, 0.05)
	var here := marks.coats[marks.index_of(at + Vector3.LEFT * 0.01)]
	var away := marks.coats[marks.index_of(Vector3(b.end.x, b.get_center().y, b.position.z + 0.02))]
	var behind := marks.coats[marks.index_of(Vector3(b.position.x + 0.02, b.get_center().y, b.get_center().z))]
	check(here >= 1.0 and away == 0.0 and behind == 0.0,
		"blasting turns the surface bare where the jet lands, and only there (%.1f there, %.1f along, %.1f behind)" % [here, away, behind])
	marks.restore()
	check(not ((mi.material_override as BaseMaterial3D).next_pass is ShaderMaterial), "stepping back puts each part's own finish back")
	d.queue_free()


## At the gloves: the readout, the rust coming off while you blast, the engine staying put while
## you work, the cheer when a part and then the whole engine come up bare, and the sand itself.
func _test_blast_live_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	Shed.request({"a": "order_furniture", "model": "blaster_cabinet"})
	var cab := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "blaster":
			cab = id
	var spot := "blast_%d_0" % cab
	var at := Workshop.CENTER + Vector3(1.5, 0.0, 1.8)
	Shed.request({"a": "grab", "furniture": cab})
	Shed.request({"a": "release", "furniture": cab, "xf": Transform3D(Basis(), at)})
	var engine := 0
	for s in Shed.stand_spots():
		if engine == 0 and Shed.is_engine(Shed.item_at_spot(s)):
			engine = Shed.item_at_spot(s)
			Shed.request({"a": "take", "spot": s})
	Shed.request({"a": "place", "spot": spot})
	var parts := [engine]
	for slot in PartsDB.ENGINE_SLOTS:
		if Shed.engine_item(engine, slot) != 0:
			parts.append(Shed.engine_item(engine, slot))
	for id in parts:
		Shed.items[id]["rust"] = 0.8
		Shed.items[id]["dirt"] = 0.5
	Shed.changed.emit()
	for i in 5:
		await get_tree().process_frame
	var view: EquipmentView = main.workshop.furniture_nodes[cab]
	var jet: GPUParticles3D = view.get_node("Nozzle/Jet")
	var grain := (jet.draw_pass_1 as QuadMesh).size
	var pm := jet.process_material as ParticleProcessMaterial
	check(jet.amount >= 3000 and grain.x < 0.004 and pm.initial_velocity_min >= 20.0 and pm.collision_mode == ParticleProcessMaterial.COLLISION_RIGID,
		"the nozzle shoots thousands of tiny, fast grains of sand that bounce off what they hit (%d at %.0f m/s)" % [jet.amount, pm.initial_velocity_min])
	var colliders: int = main.workshop.model_for({"engine": engine}).find_children("SandCollider", "GPUParticlesCollisionBox3D", true, false).size()
	check(colliders > 3 and view.get_node("SandWalls").get_child_count() >= 5, "the sand bounces off the engine and the chamber (%d shapes on the engine)" % colliders)
	var post: Node3D = view.get_node("Post")
	var pivot: Node3D = view.get_node("Pivot")
	check(post.scale.y > 0.01 and pivot.position.y > float(Equipment.blaster_inside("blaster_cabinet")["floor"]) + 0.2, "the engine is held up on the turntable's post")
	w.place(Transform3D(Basis(), at + Vector3(0.0, 0.0, 1.3)))
	await _aim_point(w, pivot.global_position)
	_press("interact")
	for i in 4:
		await get_tree().physics_frame
	check(w.blast != null, "hands in the gloves")
	if w.blast == null:
		main._leave()
		main.queue_free()
		await get_tree().physics_frame
		return
	var hud: BlastHud = main.hud.blast_hud
	await get_tree().process_frame
	check(hud.visible and not main.hud._panel.visible, "the big sandblasting readout comes up in place of the side panel")
	var model_before: BikeModel = w.blast.model
	Input.action_press("act")
	var rust_seen := 1.0
	for i in 150:
		await get_tree().physics_frame
		if i % 20 == 0:
			w._look(0.0, 0.03 if (i / 20) % 2 == 0 else -0.03)
		w.blast.turn(Vector2(0.01, 0.0))
		rust_seen = minf(rust_seen, float(Shed.items[engine]["rust"]))
	Input.action_release("act")
	await get_tree().physics_frame
	check(rust_seen < 0.8 - 0.005 and w.blast != null, "the rust comes off while you blast, not just when you stop (%.3f)" % rust_seen)
	check(is_instance_valid(model_before) and w.blast.model == model_before and main.workshop.model_for({"engine": engine}) == model_before,
		"the engine isn't redrawn under you as the numbers change")
	var lines := w.blast.lines()
	check(lines.size() == parts.size() and absf(float(lines[0]["rust"]) - float(Shed.items[int(lines[0]["id"])]["rust"])) < 0.001
		and lines[0].has("health") and lines[0].has("wear"), "each part's rust, dirt, wear and condition show live on the readout")
	# A part comes up bare: a ding, a flash and "Bare metal!"; then the whole engine.
	var id0 := int(w.blast.parts.keys()[0])
	var cells: PackedFloat32Array = w.blast.parts[id0]["cells"]
	cells.fill(1.5)
	w.blast.parts[id0]["cells"] = cells
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(not hud.cue.is_empty() and str(hud.cue["kind"]) == "part" and hud.flash > 0.0, "a part done: the screen flashes and says Bare metal!")
	for id in w.blast.parts:
		var c: PackedFloat32Array = w.blast.parts[id]["cells"]
		c.fill(1.5)
		w.blast.parts[id]["cells"] = c
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(str(hud.cue.get("kind", "")) == "engine" and w.blast != null, "the whole engine done: a big cheer before you step back")
	for i in 400:
		await get_tree().physics_frame
		if w.blast == null:
			break
	check(w.blast == null and float(Shed.items[engine]["rust"]) == 0.0, "then you step back, every part bare metal")
	await get_tree().process_frame
	check(main.workshop.model_for({"engine": engine}) != model_before, "and the engine's redrawn as it is now")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## A part hung in the paint shop swings with its hook and wire from the wire's mount on the
## ceiling rail, for a few seconds after a knock.
func _test_booth_swing_from_rail() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var ws: Workshop = main.workshop
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hook: String = Shed.furniture_spots(booth)[1]
	var disc := _hold_new("solid_240")
	Shed.request({"a": "place", "spot": hook})
	await get_tree().process_frame
	var swing: Swing = ws._spot_nodes[hook].get_parent()
	var view: EquipmentView = ws.furniture_nodes[booth]
	var rail_y := view.global_position.y + Equipment.rail_height(str(Shed.furniture[booth]["model"]))
	check(absf(swing.global_position.y - rail_y) < 0.01 and swing.length > 1.0,
		"the part swings from the wire's mount on the ceiling rail (%.2f m of wire and hook)" % swing.length)
	check(swing.get_node_or_null("HookWire") != null and swing.get_node_or_null("Hook") != null
		and not (view.get_node("Hanger_" + hook) as Node3D).visible, "the wire and hook swing with it")
	swing._angle = Vector2.ZERO
	swing._rate = Vector2.ZERO
	swing.push(Vector3(0.0, 0.0, 0.6))
	var later := 0.0
	for i in 240:
		await get_tree().physics_frame
	for i in 120:
		await get_tree().physics_frame
		later = maxf(later, swing.angle().length())
	check(later > 0.01, "a knock keeps it swinging for a few seconds (%.3f rad after 2 s)" % later)
	var hook_pos: Vector3 = (swing.get_node("Hook") as Node3D).global_position
	check(hook_pos.y > swing.part_position().y + 0.3 and hook_pos.y < rail_y - 0.2, "with the hook on its wire above the part")
	for i in 1200:
		await get_tree().physics_frame
	check(swing.angle().length() < 0.01, "then it settles (%.4f)" % swing.angle().length())
	Shed.request({"a": "take", "spot": hook})
	await get_tree().process_frame
	await get_tree().process_frame
	check((view.get_node("Hanger_" + hook) as Node3D).visible, "an empty hook hangs from the rail again")
	Shed.items.erase(disc)
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## Money: wages for jobs with the business's cut, sending money about, who may take money out
## and change the garage's settings.
func _test_money_pay_and_transfers() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_money_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Boss", 7)
	Progress.select("Boss")
	var me := Shed.me()
	check(Shed.garage_money == Money.START_FUNDS and Progress.money() == 0 and int(Shed.bank["cut"]) == Money.DEFAULT_CUT
		and Money.owner_name() == "Boss" and Money.is_owner(me), "a new shed opens with %s in the business, run by the host" % TvChannels.money_text(Money.START_FUNDS))
	Shed.request({"a": "money_settings", "cut": 25})
	check(int(Shed.bank["cut"]) == 25, "the host sets the business's cut of wages")
	var bank_was := Shed.garage_money
	Progress.award(me, "repair", 1.0, "item:4242")
	var first := Progress.money()
	check(first == 6 - Money.cut_of(6, 25) and Shed.garage_money == bank_was + Money.cut_of(6, 25),
		"a job pays the worker its wage less the cut (%s), the cut going to the business" % TvChannels.money_text(first))
	Progress.award(me, "repair", 1.0, "item:4242")
	check(Progress.money() - first < first, "doing the same job again straight away pays less, as the XP does")
	check(str(Shed.bank["ledger"][-1]["why"]) == "Cut of Boss's wages", "the cut shows in the business's ledger")
	var cash := Progress.money()
	bank_was = Shed.garage_money
	Shed.pay_worker(me, 100, "Test wage")
	check(Progress.money() == cash + 75 and Shed.garage_money == bank_was + 25, "pay_worker: 75 to the worker, 25 to the business")
	check(str(Progress.profile["cash_log"][-1]["why"]) == "Test wage", "and the wage shows in your own money log")
	Progress.award(me, "jump", 1.0)
	check(Progress.money() == cash + 75, "riding tricks pay XP, not wages")
	# Sending money.
	Progress.earn(500, "Test")
	cash = Progress.money()
	bank_was = Shed.garage_money
	check(Money.send(0, 200) == "" and Progress.money() == cash - 200 and Shed.garage_money == bank_was + 200,
		"anyone can send money to the business")
	check(str(Shed.bank["ledger"][-1]["why"]) == "From Boss", "and the ledger says who sent it")
	check(Money.send(0, 1000000) != "" and Progress.money() == cash - 200, "you can't send more than you have")
	check(Money.send(me, 10) != "", "or send money to yourself")
	cash = Progress.money()
	Progress.spend(30, "Test")
	Shed.request({"a": "money_send", "to": 99, "amount": 30})
	check(Progress.money() == cash, "money sent to someone who's gone comes back")
	# A mate in the shed (not really connected here, so it bounces back too).
	Shed.crew[5] = {"name": "Mate", "tool": "hands", "activity": "", "riding": 0}
	cash = Progress.money()
	check(Money.send(5, 40) == "" and Progress.money() == cash, "a mate who can't receive it: the money comes back")
	# Taking money out: the owner only.
	cash = Progress.money()
	bank_was = Shed.garage_money
	Shed.request({"a": "money_withdraw", "amount": 1000})
	check(Progress.money() == cash + 1000 and Shed.garage_money == bank_was - 1000, "the owner takes money out of the business")
	check(Money.check(me, {"a": "money_withdraw", "amount": Shed.garage_money + 1}) != "", "but not more than it has")
	check(Money.check(5, {"a": "money_withdraw", "amount": 10}) != "" and Money.check(5, {"a": "money_settings", "cut": 5}) != "",
		"a mate can't take money out or change the settings")
	Shed.request({"a": "money_settings", "owner": "Mate"})
	check(Money.owner_name() == "Mate" and Money.is_owner(5) and not Money.is_owner(me), "the host can make someone else the owner")
	check(Money.check(5, {"a": "money_withdraw", "amount": 10}) == "" and Money.check(me, {"a": "money_withdraw", "amount": 10}) != "",
		"then only they can take money out")
	check(Money.check(me, {"a": "money_loan", "offer": 0}) != "", "or take out a loan")
	Shed.request({"a": "money_settings", "owner": "Boss"})
	check(str(Shed.bank["owner"]) == "" and Money.is_owner(me), "picking the host again goes back to the default")
	# The Money tab.
	var tab := MoneyTab.new()
	add_child(tab)
	tab.refresh()
	check(tab._summary.text.contains(TvChannels.money_text(Shed.garage_money)) and not tab._take.disabled and tab._cut.editable,
		"the Money tab shows both accounts; the host owner can take out and change the cut")
	cash = Progress.money()
	tab.send_money(0, 5)
	check(Progress.money() == cash - 5, "the tab's Send pays the business")
	tab.free()
	Shed.crew.erase(5)
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


## Bank loans: borrowing, a repayment a day with interest, paying off early, missing one, the
## debt limit, and the bank saved with the shed (old saves get the defaults).
func _test_money_loans() -> void:
	Shed.start_new("Boss", 8)
	var me := Shed.me()
	var start := Shed.garage_money
	Shed.request({"a": "money_loan", "offer": 0})
	var loan: Dictionary = Shed.bank["loans"][0] if not Shed.bank["loans"].is_empty() else {}
	check(Shed.garage_money == start + 5000 and int(loan.get("owed", 0)) == 5000 and Money.debt(Shed.bank) == 5000,
		"borrowing 5k puts it in the business's account")
	var daily := int(loan["daily"])
	check(daily > 500 and daily < 600, "repaid in 10 days with interest (%s a day)" % TvChannels.money_text(daily))
	var bal := Shed.garage_money
	Shed.money_new_day()
	check(int(loan["owed"]) == 5000 + 40 - daily and Shed.garage_money == bal - daily and int(Shed.bank["day"]) == 1,
		"a new day: interest on what's owed, then the day's repayment")
	bal = Shed.garage_money
	Shed.request({"a": "money_repay", "loan": int(loan["id"]), "amount": 1000})
	check(int(loan["owed"]) == 5040 - daily - 1000 and Shed.garage_money == bal - 1000, "paying more off early")
	Shed.request({"a": "money_loan", "offer": 2})
	check(Shed.bank["loans"].size() == 2, "a second loan")
	check(Money.check(me, {"a": "money_loan", "offer": 2}) != "", "but the bank won't lend past %s in all" % TvChannels.money_text(Money.MAX_DEBT))
	# Missing a repayment.
	Shed.garage_money = 0
	var owed := int(loan["owed"])
	Shed.money_new_day()
	check(int(loan["missed"]) == 1 and int(loan["owed"]) > owed and bool(Shed.bank["blocked"]),
		"no money for the repayment: missed, a fee added, and no new loans")
	check(Money.check(me, {"a": "money_loan", "offer": 0}).contains("missed"), "the bank says why")
	# Save and load.
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.request({"a": "money_settings", "cut": 33})
	Shed.load_state(copy, "Boss")
	check(Shed.bank["loans"].size() == 2 and bool(Shed.bank["blocked"]) and int(Shed.bank["cut"]) == Money.DEFAULT_CUT
		and Shed.bank["ledger"].size() > 3 and int(Shed.bank["day"]) == 2, "the bank's loans, ledger, day and settings are saved with the shed")
	# Clearing every loan lifts the block.
	Shed.garage_money = 500000
	for l in Shed.bank["loans"].duplicate():
		Shed.request({"a": "money_repay", "loan": int(l["id"]), "amount": int(l["owed"])})
	check(Shed.bank["loans"].is_empty() and not bool(Shed.bank["blocked"]) and Money.check(me, {"a": "money_loan", "offer": 0}) == "",
		"loans cleared: the bank lends again")
	var old: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	old.erase("bank")
	old["garage_money"] = 0
	Shed.load_state(old, "Boss")
	check(Shed.garage_money == Money.START_FUNDS and Shed.bank["loans"].is_empty() and int(Shed.bank["cut"]) == Money.DEFAULT_CUT,
		"a shed saved before money opens with the starting funds and default settings")


## Prices: parts cost the business money (Haggler takes some off), the business can run out,
## selling loose parts and whole bikes, project bikes, the money milestones and the debug million.
func _test_money_parts_and_selling() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_money_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Boss", 9)
	Progress.select("Boss")
	var me := Shed.me()
	var unpriced := []
	for id in PartsDB.parts:
		if Money.part_price(id) <= 0:
			unpriced.append(id)
	check(unpriced.is_empty(), "every part has a price %s" % str(unpriced))
	check(Money.part_price("carbon_monocoque") > Money.part_price("steel_cradle") and Money.part_price("four_1000") > Money.part_price("single_250"),
		"fancier and bigger parts cost more (carbon frame %s, steel %s)" % [TvChannels.money_text(Money.part_price("carbon_monocoque")),
		TvChannels.money_text(Money.part_price("steel_cradle"))])
	check(Shed.part_price("frame_nope") == 0 and Shed.part_price("steel_cradle") == Money.part_price("steel_cradle"), "Shed.part_price is the same price")
	var price := Money.part_price("chromoly_trellis")
	var bal := Shed.garage_money
	var frame := _order("chromoly_trellis")
	check(frame != 0 and Shed.garage_money == bal - price and str(Shed.bank["ledger"][-1]["why"]).begins_with("Bought"),
		"ordering a part takes its price from the business (%s)" % TvChannels.money_text(price))
	Progress.profile["skills"]["haggler"] = 2
	check(Money.buy_price("chromoly_trellis", me) == roundi(price * 0.9), "Haggler 2: 10% off")
	Progress.profile["skills"].erase("haggler")
	Shed.garage_money = 10
	var count := Shed.items.size()
	check(Shed.check(me, {"a": "order_part", "part": "chromoly_trellis"}).contains("afford"), "the business can't afford it: it says so")
	Shed.request({"a": "order_part", "part": "chromoly_trellis"})
	check(Shed.items.size() == count and Shed.garage_money == 10, "and nothing comes")
	var bikes := Shed.bikes.size()
	Shed.request({"a": "order"})
	check(Shed.bikes.size() == bikes and Shed.items.size() == count, "no money, no project bike")
	Shed.garage_money = 20000
	# Selling a loose part: as good as new, it fetches SELL_RATE of its price.
	var sale := Money.part_sale(frame)
	check(sale == roundi(price * Money.SELL_RATE), "a new part sells for %d%% of its price" % roundi(Money.SELL_RATE * 100.0))
	var rusty := _order("chromoly_trellis")
	Shed.items[rusty]["rust"] = 0.9
	Shed.items[rusty]["wear"] = 0.6
	check(Money.part_sale(rusty) < sale / 2, "a worn, rusty one far less (%s)" % TvChannels.money_text(Money.part_sale(rusty)))
	var sold_was := int(Progress.profile["stats"].get("sell_part", 0))
	bal = Shed.garage_money
	Shed.request({"a": "money_sell_part", "item": frame})
	check(not Shed.items.has(frame) and Shed.garage_money == bal + sale and int(Progress.profile["stats"].get("sell_part", 0)) == sold_was + 1,
		"selling it: the part goes, the money goes to the business and the seller gets the XP")
	var on_bike := Shed.item_on(Shed.bikes.keys()[0], "frame")
	check(Money.check(me, {"a": "money_sell_part", "item": on_bike}) != "", "parts on a bike can't be sold on their own")
	# Selling a whole bike.
	var ranger := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == "Rusty Ranger":
			ranger = id
	var value := Money.bike_sale(ranger)
	var parts_on := []
	for slot in PartsDB.SLOTS:
		if Shed.item_on(ranger, slot) != 0:
			parts_on.append(Shed.item_on(ranger, slot))
	check(value > 0 and Shed.is_complete(ranger), "a complete bike has a price (%s)" % TvChannels.money_text(value))
	var bare := 0.0
	for id in parts_on:
		bare += Money.item_worth(Shed.items[id])
	check(value > roundi(bare * Money.SELL_RATE * (1.0 + Money.BONUS_COMPLETE)) - 2, "with a bonus for being complete (and more ready to ride)")
	bal = Shed.garage_money
	var sold_bikes := int(Progress.profile["stats"].get("sell_bike", 0))
	Shed.request({"a": "money_sell_bike", "bike": ranger})
	check(not Shed.bikes.has(ranger) and parts_on.all(func(i): return not Shed.items.has(i)) and Shed.garage_money == bal + value + Money.cut_of(int(Progress.PAY["sell_bike"]), int(Shed.bank["cut"])),
		"selling the bike: it goes, every part with it, and the business is paid (and takes its cut of the seller's commission)")
	check(int(Progress.profile["stats"].get("sell_bike", 0)) == sold_bikes + 1 and int(TvChannels.money_data(me)["sold"]) == sold_bikes + 1,
		"the seller gets the Bike sold XP, and My money counts it")
	# A project bike costs a bit more than it would fetch.
	bal = Shed.garage_money
	Shed.request({"a": "order"})
	var newest := 0
	for id in Shed.bikes:
		newest = maxi(newest, id)
	check(Shed.bikes.size() == 3 and Shed.garage_money < bal and Shed.garage_money == bal - Money.project_price(newest)
		and Money.project_price(newest) > Money.bike_sale(newest), "a project bike costs more than it fetches as it comes (%s)" % TvChannels.money_text(bal - Shed.garage_money))
	# Money milestones: XP for the crew the first time the business gets there.
	Shed.garage_money = 20000
	var ms := int(Progress.profile["stats"].get("money_milestone", 0))
	Shed.credit_garage(6000, "Test sale")
	check(int(Progress.profile["stats"].get("money_milestone", 0)) == ms + 1 and Shed.bank["milestones"].has(25000),
		"reaching 25k pays the money milestone XP")
	Shed.garage_money = 20000
	Shed.credit_garage(6000, "Test sale")
	check(int(Progress.profile["stats"].get("money_milestone", 0)) == ms + 1, "only the first time")
	# The debug million, and the TV pages.
	var tab := DebugTab.new()
	add_child(tab)
	bal = Shed.garage_money
	tab.press("Give the garage £1,000,000")
	check(Shed.garage_money == bal + 1000000, "Debug: give the garage £1,000,000")
	tab.free()
	var g := TvChannels.garage_data()
	check(int(g["cash"]) == Shed.garage_money and int(g["bike_value"]) > 0 and int(g["income_week"]) >= 1000000 and int(g["outgoings_week"]) > 0
		and (g["history"] as Array).size() == 7, "the Garage money page: bikes' worth, the week in and out")
	var mine := TvChannels.money_data(me)
	check(int(mine["earned_week"]) > 0 and (mine["history"] as Array).size() == 7 and int((mine["history"] as Array)[-1]) == Progress.money(),
		"the My money page: what you earned this week")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


# ---------------------------------------------------------------------------- contracts

## A bike in a known, roadworthy state: new parts, mirrors, fluids full, chain set right.
func _mot_ready_bike(bay: int) -> int:
	var parts: Dictionary = PartsDB.DEFAULT_BUILD.duplicate()
	parts["mirrors"] = "round_mirrors"
	var id := Shed._new_bike(parts, bay, "Test MOT", 0.0)
	_make_roadworthy(id)
	return id


## Puts every part on a bike back to like new, fits what the road needs and fills it up.
func _make_roadworthy(bike_id: int) -> void:
	var road_kit := {"mirrors": "round_mirrors", "headlight": "round_7", "horn": "disc_horn"}
	for slot in road_kit:
		if Shed.item_on(bike_id, slot) == 0:
			var it := Shed._new_item(str(road_kit[slot]), 0.0, 0.0, 0.0)
			Shed._move(it, "bike", bike_id)
			Shed.bikes[bike_id]["slots"][slot] = it
			Shed.bikes[bike_id]["bolted"][slot] = true
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0:
			continue
		var item: Dictionary = Shed.items[id]
		item["rust"] = 0.0
		item["dirt"] = 0.0
		item["wear"] = 0.0
		if slot == "exhaust" and str(item["part"]) == "straight_pipe":
			item["part"] = "stock_muffler"
		if str(PartsDB.get_part(str(item["part"])).get("style", "")) == "slick":
			var wheel := str(Shed.items[Shed.item_on(bike_id, slot.replace("tyre", "wheel"))]["part"])
			item["part"] = PartsDB.tyres_for(wheel).filter(func(t): return str(PartsDB.get_part(str(t)).get("style", "")) != "slick")[0]
		if item.has("fluid"):
			item["fluid"]["litres"] = PartsDB.fluid_capacity(str(item["part"]))
			item["fluid"]["age"] = 0.0
			if str(item["fluid"]["type"]) == "":
				item["fluid"]["type"] = {"engine": "semi_10w40", "tank": "unleaded_95"}.get(slot, "dot4")
		if item.has("slack"):
			item["slack"] = Shed.CHAIN_SLACK_SET
			item["lube"] = 1.0
		if item.has("bead"):
			item["bead"] = 1.0
	for slot in PartsDB.BIKE_SLOTS:
		if Shed.item_on(bike_id, slot) != 0:
			Shed.bikes[bike_id]["bolted"][slot] = true


func _test_contract_customers() -> void:
	Shed.start_new("Tester", 41)
	check(Contracts.customers().is_empty() and Contracts.jobs().is_empty() and Contracts.reputation() == 0,
		"a new shed has no customers, no jobs and no reputation")
	check(Contracts.unlocked(0) == ["maint"] and Contracts.unlocked(int(Contracts.UNLOCK["mot"])).has("mot")
		and Contracts.unlocked(10).size() == 4, "reputation unlocks harder jobs: service first, then MOT, mods and bespoke builds")
	Contracts.advance(Contracts.FIRST_CUSTOMER + 0.05)
	check(Contracts.customers().size() == 1, "the first customer turns up soon after the shed opens")
	var c: Dictionary = Contracts.customers().values()[0]
	check(str(c["offer"]["kind"]) == "maint" and str(c["name"]).contains(" ") and c["look"].get("top") is Color,
		"with an easy job at no reputation, a name and their own clothes (%s, %s)" % [c["name"], c["offer"]["title"]])
	var most := 0
	for i in 12:
		Contracts.advance(Contracts.SPAWN_HOURS.y * 0.25)
		most = maxi(most, Contracts.customers().size())
	check(most <= Contracts.MAX_WAITING and most >= 1, "never more than a couple waiting (at most %d)" % most)
	Contracts.advance(Contracts.PATIENCE_HOURS + 0.1)
	var stayed := Contracts.customers().values().filter(func(x): return Contracts.clock() >= float(x["leave_at"]))
	check(stayed.is_empty(), "ignored customers leave after a while")
	Contracts._st()["reputation"] = 20
	for kind in Contracts.KINDS:
		var id := Contracts.spawn(kind)
		var o: Dictionary = Contracts.customers()[id]["offer"]
		var ok: bool = not o["goals"].is_empty() and int(o["pay"]) > 0 and int(o["days"]) >= 2 \
			and str(o["title"]).begins_with(str(Contracts.KIND_NAMES[kind]))
		if kind in ["mod", "bespoke"]:
			ok = ok and int(o["budget"]) > 0 and o["goals"].size() >= 2
		if kind == "mot":
			ok = ok and o["goals"] == [{"t": "mot"}]
		check(ok, "a %s offer: pay %s, budget %s, %d days (%s)" % [kind, Contracts.money(int(o["pay"])),
			Contracts.money(int(o["budget"])), int(o["days"]), ", ".join(o["goals"].map(func(g): return Contracts.goal_text(g)))])
		Contracts.customers().erase(id)
	var bespoke := Contracts.make_offer("bespoke", "Lady Okafor")
	var maint := Contracts.make_offer("maint", "Dave Smith")
	check(int(bespoke["pay"]) > int(maint["pay"]) * 5 and int(bespoke["days"]) > int(maint["days"]) * 2,
		"a bespoke build pays far more and has far longer than a service")
	var cid := Contracts.spawn("maint")
	check(Shed.check(2, {"a": "contract_spawn"}) != "" and Shed.check(Shed.me(), {"a": "contract_spawn"}) == "",
		"only the host can send customers from the Debug tab")
	Shed.request({"a": "contract_decline", "customer": cid})
	check(not Contracts.customers().has(cid) and Contracts.reputation() == 20, "turning a job down sends them off, no harm done")


func _mot_fail_names(bike: int) -> Array:
	return MotTest.fails(MotTest.inspect(bike)).map(func(r): return r["name"])


func _test_contract_mot() -> void:
	Shed.start_new("Tester", 42)
	var bike := _mot_ready_bike(3)
	var sheet := MotTest.inspect(bike)
	check(sheet.size() >= 30 and MotTest.fails(sheet).is_empty(), "a sound bike passes all %d MOT checks %s" % [sheet.size(),
		str(_mot_fail_names(bike))])
	var areas := {}
	for r in sheet:
		areas[r["area"]] = true
	check(areas.has("Tyres") and areas.has("Brakes") and areas.has("Suspension") and areas.has("Lights") and areas.has("Exhaust")
		and areas.has("Structure") and areas.has("Fluids") and areas.has("Drive"),
		"the sheet covers tyres, brakes, suspension, drive, lights, exhaust, frame and fluids")
	var tyre := Shed.item_on(bike, "front_tyre")
	Shed.items[tyre]["wear"] = 0.9
	check(is_equal_approx(MotTest.tread_mm(Shed.items[tyre]), 0.6), "tread depth comes from tyre wear (0.6 mm left at 90% worn)")
	check(_mot_fail_names(bike).has("Front tyre tread depth"), "under 1 mm of tread fails")
	Shed.items[tyre]["wear"] = 0.8
	check(not _mot_fail_names(bike).has("Front tyre tread depth"), "1.2 mm is still legal")
	Shed.items[Shed.item_on(bike, "rear_pads")]["wear"] = 0.9
	Shed.items[Shed.item_on(bike, "frame")]["rust"] = 0.7
	Shed.items[Shed.item_on(bike, "chain")]["slack"] = 60.0
	Shed._erase_item(Shed.item_on(bike, "mirrors"))
	Shed.bikes[bike]["slots"]["mirrors"] = 0
	Shed.items[Shed.item_on(bike, "exhaust")]["part"] = "straight_pipe"
	var f := _mot_fail_names(bike)
	check(f.has("Rear pads") and f.has("Frame corrosion and damage") and f.has("Chain tension") and f.has("Mirrors fitted")
		and f.has("Exhaust noise"), "worn pads, a rusty frame, a slack chain, no mirrors and a straight pipe all fail (%s)" % str(f))
	# The job: take it on, test it, fix it, test again, hand it back for the certificate.
	Shed.start_new("Tester", 43)
	Contracts._st()["reputation"] = 3
	var cid := Contracts.spawn("mot")
	var cust: String = Contracts.customers()[cid]["name"]
	Shed.request({"a": "contract_accept", "customer": cid})
	check(Contracts.jobs().size() == 1 and not Contracts.customers().has(cid), "accepting takes the job on and the customer goes")
	var job: Dictionary = Contracts.jobs().values()[0]
	var jid := int(job["id"])
	var jb := int(job["bike"])
	check(Shed.bikes.has(jb) and int(Shed.bikes[jb]["bay"]) >= 0 and str(Shed.bikes[jb]["name"]).contains(cust.get_slice(" ", 0)),
		"their bike is delivered to a free bay (%s)" % str(Shed.bikes.get(jb, {}).get("name", "")))
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": jid}) != "", "it can't be handed back where it stands")
	Shed.request({"a": "contract_mot_test", "job": jid})
	check(job["mot"]["tested"] and int(job["mot"]["fails"]) > 0, "the first test finds faults (%d: %s)" % [int(job["mot"]["fails"]),
		str(MotTest.fails(job["mot"]["sheet"]).map(func(r): return r["name"]))])
	check(not Contracts.eval_goal(job, {"t": "mot"})["done"], "a failed test isn't a pass")
	_make_roadworthy(jb)
	Shed.request({"a": "contract_mot_test", "job": jid})
	check(int(job["mot"]["fails"]) == 0 and Contracts.eval_goal(job, {"t": "mot"})["done"] and int(job["mot"]["tests"]) == 2,
		"fixed and re-tested, it passes %s" % str(MotTest.fails(job["mot"]["sheet"]).map(func(r): return r["name"])))
	Contracts.note_action(Shed.me(), {"a": "clean", "bike": jb})
	check(not Contracts.eval_goal(job, {"t": "mot"})["done"] and job["workers"].has(Shed.me()), "work on it after a test means testing it again")
	Shed.request({"a": "contract_mot_test", "job": jid})
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": jid}).contains("reception"), "it has to go round to reception")
	Shed.bikes[jb]["xf"] = Contracts.reception()
	var before := Shed.garage_money
	var expected := int(Contracts.payout(job)["total"])
	Shed.request({"a": "contract_hand_in", "job": jid})
	var done: Dictionary = Contracts._st()["done"][0] if not Contracts._st()["done"].is_empty() else {}
	check(Contracts.jobs().is_empty() and not Shed.bikes.has(jb)
		and not Shed.items.values().any(func(it): return str(it["at"]) == "bike" and int(it["ref"]) == jb),
		"handed back, the customer rides it away")
	check(not done.is_empty() and not done.get("cert", {}).is_empty() and str(done["cert"]["number"]).begins_with("TS-"),
		"with an MOT certificate (%s)" % str(done.get("cert", {}).get("number", "")))
	check(Shed.garage_money > before and Shed.garage_money - before <= expected and Contracts.reputation() == 3 + int(Contracts.REP_GAIN["mot"]),
		"the garage is paid (%s of %s) and the reputation goes up" % [Contracts.money(Shed.garage_money - before), Contracts.money(expected)])


func _test_contract_goals_and_pay() -> void:
	Shed.start_new("Tester", 44)
	Contracts._st()["reputation"] = 20
	# Modifications: known goals on a known bike.
	var cid := Contracts.spawn("mod")
	Shed.request({"a": "contract_accept", "customer": cid})
	var job: Dictionary = Contracts.jobs().values()[0]
	var bike := int(job["bike"])
	var pan := Shed.item_on(bike, "panniers")
	if pan != 0:
		Shed._erase_item(pan)
		Shed.bikes[bike]["slots"]["panniers"] = 0
	var ex := Shed.item_on(bike, "exhaust")
	Shed.items[ex]["part"] = "stock_muffler"
	job["goals"] = [{"t": "fit", "slot": "panniers"}, {"t": "paint", "color": 3}, {"t": "pipes", "from": "stock_muffler"}]
	job["pay"] = 1000
	job["budget"] = 500
	Shed.items[Shed.item_on(bike, "tank")]["color"] = Shed.PAINTS[1]
	check(Contracts.progress(job) == 0.0, "none of the goals are met to start with")
	var bag := Shed._new_item("leather_saddlebags", 0.0, 0.0, 0.0)
	Shed._move(bag, "bike", bike)
	Shed.bikes[bike]["slots"]["panniers"] = bag
	Shed.bikes[bike]["bolted"]["panniers"] = true
	check(is_equal_approx(Contracts.progress(job), 1.0 / 3.0), "panniers on: a third of the way")
	Shed.items[Shed.item_on(bike, "tank")]["color"] = Shed.PAINTS[3]
	Shed.items[ex]["part"] = "full_system"
	check(Contracts.progress(job) == 1.0, "painted %s and a full system on: every goal met" % Shed.PAINT_NAMES[3])
	job["due"] = Contracts.clock() + 10.0
	var pay := Contracts.payout(job, 400)
	check(int(pay["labour"]) == 1000 and int(pay["parts"]) == 400 and int(pay["tip"]) > 0 and int(pay["rep"]) == int(Contracts.REP_GAIN["mod"]),
		"on time and within budget: the full fee, the parts back and a tip (%s)" % Contracts.money(int(pay["total"])))
	var over := Contracts.payout(job, 700)
	check(int(over["over"]) == 200 and int(over["labour"]) == 800 and int(over["parts"]) == 500, "200 over budget comes off the pay")
	job["due"] = Contracts.clock() - 30.0
	var late := Contracts.payout(job, 400)
	check(int(late["late"]) == 2 and int(late["labour"]) == 700 and int(late["tip"]) == 0 and int(late["rep"]) < int(pay["rep"]),
		"two days late: 30% off, no tip, less reputation")
	job["goals"].append({"t": "top_kmh", "min": 900.0})
	var part_met := Contracts.payout(job, 400)
	check(is_equal_approx(float(part_met["sat"]), 0.75) and int(part_met["labour"]) < int(late["labour"]), "a goal missed pays less")
	# Bespoke: the targets set from a style's own parts can be met by building it.
	for style in Contracts.STYLES:
		var ref := Contracts.style_build(style)
		check(int(Contracts.style_marks(style, ref)[0]) >= 3, "a %s built from its own parts counts as one" % style)
	var ref2 := Contracts.style_build("cafe")
	var built := Shed._new_bike(ref2, 3, "Cafe test", 0.0)
	_make_roadworthy(built)
	var goals := Contracts._bespoke_goals("cafe", ref2, Shed._rng)
	for g in goals:
		if g["t"] == "paint":
			g["color"] = Shed.paint_index(Shed.items[Shed.item_on(built, "tank")]["color"])
	var bj := {"id": 999, "kind": "bespoke", "bike": built, "goals": goals, "pay": 3000, "budget": 4000, "due": Contracts.clock() + 100.0,
		"start_parts": {"frame": ref2["frame"]}}
	var rows := Contracts.evaluate(bj)
	check(rows.all(func(r): return r["done"]), "a bespoke cafe racer's targets are reachable: %s" % str(rows.map(func(r): return "%s %s" % [str(r["text"]).left(24), r["have"]])))
	# Maintenance: each task reads the bike.
	Shed.start_new("Tester", 45)
	cid = Contracts.spawn("maint")
	Contracts.customers()[cid]["offer"]["goals"] = Contracts.TASKS.keys().map(func(k): return {"t": "task", "task": k})
	Shed.request({"a": "contract_accept", "customer": cid})
	var mj: Dictionary = Contracts.jobs().values()[0]
	var mrows := Contracts.evaluate(mj)
	check(mrows.all(func(r): return not r["done"]), "a service job's bike comes in needing every task (%s)" % str(mrows.map(func(r): return r["have"])))
	_make_roadworthy(int(mj["bike"]))
	mrows = Contracts.evaluate(mj)
	check(mrows.all(func(r): return r["done"]), "serviced, every task is ticked off (%s)" % str(mrows.map(func(r): return r["have"])))
	# Paying out: the crew who worked on it and the garage.
	Contracts.note_action(Shed.me(), {"a": "unbolt", "bike": int(mj["bike"]), "slot": "chain"})
	check(int(mj["workers"].get(Shed.me(), 0)) == 1, "work on a contract bike counts who did it")
	Shed.bikes[int(mj["bike"])]["xf"] = Transform3D(Basis(), Contracts.door_front())
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": mj["id"]}) == "", "just outside the roller door counts as handing it back")
	var xp_before := int(Progress.profile["xp"])
	var g0 := Shed.garage_money
	var total := int(Contracts.payout(mj)["total"])
	Shed.request({"a": "contract_hand_in", "job": mj["id"]})
	check(Shed.garage_money > g0 and Shed.garage_money - g0 <= total, "the garage gets its share (%s of %s)" % [
		Contracts.money(Shed.garage_money - g0), Contracts.money(total)])
	check(int(Progress.profile["xp"]) > xp_before and Progress.XP.has("contract_maint") and Progress.XP.has("contract_bespoke"),
		"and the crew get contract XP")
	var tv := TvChannels.contracts_data()
	check(not tv["placeholder"] and not tv["done"].is_empty() and str(tv["done"][0].get("title", "")) != "", "the Contracts TV channel lists it as done")


func _test_contract_save() -> void:
	Shed.start_new("Tester", 46)
	Contracts._st()["reputation"] = 12
	var cid := Contracts.spawn("mod")
	var cid2 := Contracts.spawn("bespoke")
	Shed.request({"a": "contract_accept", "customer": cid2})
	Contracts.advance(1.0)
	var job: Dictionary = Contracts.jobs().values()[0]
	var bike := int(job["bike"])
	check(str(job["kind"]) == "bespoke" and Shed.bikes[bike].get("scratch", false) and Shed.item_on(bike, "frame") != 0
		and Shed.item_on(bike, "engine") == 0, "a bespoke build starts as a bare frame on a bay")
	var clock := Contracts.clock()
	var text := var_to_str(Shed.save_snapshot().duplicate(true))
	Shed.start_new("Tester", 47)
	Shed.load_state(str_to_var(text), "Tester")
	check(Contracts.reputation() == 12 and Contracts.customers().has(cid) and Contracts.jobs().size() == 1
		and is_equal_approx(Contracts.clock(), clock), "customers, jobs, reputation and the clock survive a save")
	var back: Dictionary = Contracts.jobs().values()[0]
	check(int(back["bike"]) == bike and Shed.bikes.has(bike) and back["goals"] == job["goals"], "with the job still on its bike")
	var nid := Contracts.spawn("maint")
	check(nid != cid and nid > int(back["id"]), "new customers and jobs get new ids after loading")
	var old: Dictionary = Shed._snapshot().duplicate(true)
	old.erase("contracts")
	Shed.start_new("Tester", 48)
	Shed.load_state(old, "Tester")
	check(Contracts.customers().is_empty() and Contracts.jobs().is_empty() and Contracts.reputation() == 0 and Contracts.clock() == 0.0,
		"a save from before contracts opens with none")


func _test_contract_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	var view: ContractsView = main.contracts_view
	Shed.request({"a": "contract_spawn", "kind": "maint"})
	await get_tree().process_frame
	check(view.views.size() == 1, "a customer appears in the world")
	var cv: CustomerView = view.views.values()[0]
	var start := cv.global_position
	var arrived := [false]
	cv.arrived.connect(func(_v): arrived[0] = true)
	for i in 3000:
		await get_tree().process_frame
		if arrived[0]:
			break
	var at := Contracts.reception().origin
	check(arrived[0] and cv.at_counter and Vector2(cv.global_position.x, cv.global_position.z).distance_to(Vector2(at.x, at.z)) < 0.2
		and start.distance_to(cv.global_position) > 3.0, "they walk to reception and ring the bell")
	check(cv.is_in_group("sales_visitor"), "and open the sales office's doors as they come")
	# Look at them and press F.
	main.walker.global_position = at - Contracts.reception().basis.z * 1.6 + Vector3(0, 0.1, 0)
	await get_tree().physics_frame
	main.walker.camera.look_at(cv.global_position + Vector3.UP * 1.4)
	await get_tree().physics_frame
	check(view.looked_at() == cv.customer_id, "looking at them picks them out")
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	view._unhandled_input(ev)
	await get_tree().physics_frame
	check(main.contract_panel.visible and main.contract_panel.customer_id == cv.customer_id and not main.walker.controls_enabled,
		"F opens their offer card, and you stand still while it's up")
	main.contract_panel.press("Accept")
	await get_tree().process_frame
	check(not main.contract_panel.visible and Contracts.jobs().size() == 1, "Accept takes the job on")
	for i in 30:
		await get_tree().process_frame
	check(view.views.is_empty(), "and they head off")
	var tabs: Array = main.menu.find_children("Contracts", "ContractsTab", true, false)
	if not tabs.is_empty():
		(tabs[0] as ContractsTab).refresh(true)
	check(not tabs.is_empty() and tabs[0].find_children("*", "Button", true, false).any(func(b): return (b as Button).text == "Hand back"),
		"the Esc menu's Contracts tab lists the job")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The sales office's plan: where it stands (clear of the shed's rooms, on the yard, off the road),
## where its rooms are, and the hooks customers use.
func _test_sales_office_layout() -> void:
	var rooms := Workshop.rooms()
	var sales: Rect2 = rooms["sales"]
	var office: Rect2 = rooms["sales_office"]
	check(sales == SalesOffice.footprint() and sales.encloses(office), "the sales office and its mezzanine office are rooms")
	var wash := Rect2(Workshop.WASH_CENTER.x - Workshop.WASH_HALF.x, Workshop.WASH_CENTER.z - Workshop.WASH_HALF.y,
		Workshop.WASH_HALF.x * 2.0, Workshop.WASH_HALF.y * 2.0)
	var clear := not sales.grow(1.0).intersects(wash) and not SalesOffice.FORECOURT.intersects(wash)
	for room in ["shed", "paint", "storage", "dyno"]:
		var r: Rect2 = rooms[room]
		clear = clear and not sales.grow(SalesOffice.WALL + 1.0).intersects(r) and not SalesOffice.FORECOURT.intersects(r.grow(0.3))
	check(clear, "the building and its forecourt keep clear of the shed, its side rooms and the wash bay")
	var yard := Rect2(World.YARD_CENTER - World.YARD_HALF, World.YARD_HALF * 2.0)
	check(yard.encloses(sales.grow(SalesOffice.WALL)) and yard.encloses(SalesOffice.FORECOURT), "it all stands on the flat yard slab")
	check(SalesOffice.FORECOURT.end.y < 95.0, "the car park stops short of the drag strip")
	check(Workshop.room_at(Workshop.RECEPTION.origin) == "sales" and Workshop.room_at(Workshop.RECEPTION_DESK.origin) == "sales",
		"reception is inside")
	var to_desk := (Workshop.RECEPTION_DESK.origin - Workshop.RECEPTION.origin).normalized()
	check((-Workshop.RECEPTION.basis.z).dot(to_desk) > 0.99 and (-Workshop.RECEPTION_DESK.basis.z).dot(-to_desk) > 0.99,
		"the customer faces the desk, and you face the customer")
	var entry: Vector3 = Workshop.CUSTOMER_ENTRY.origin
	check(Workshop.room_at(entry) == "" and SalesOffice.FORECOURT.has_point(Vector2(entry.x, entry.z)), "customers arrive at the car park edge")
	var to_door := (Workshop.SALES_DOOR - entry).normalized()
	check((-Workshop.CUSTOMER_ENTRY.basis.z).dot(to_door) > 0.99, "facing the doors")
	# The straight walk in goes through the doors, clear of the plinths.
	var door_t := (entry.z - Workshop.SALES_DOOR.z) / (entry.z - Workshop.RECEPTION.origin.z)
	var through := entry.lerp(Workshop.RECEPTION.origin, door_t)
	check(absf(through.x - Workshop.SALES_DOOR.x) < SalesOffice.DOOR_HALF - 0.4, "the walk from the car park to the desk goes through the doors (x %.2f)" % through.x)
	var plinths_clear := true
	for i in 40:
		var p := Workshop.SALES_DOOR.lerp(Workshop.RECEPTION.origin, i / 39.0)
		for spot in Workshop.SHOWROOM_SPOTS:
			plinths_clear = plinths_clear and Vector2(p.x - spot.origin.x, p.z - spot.origin.z).length() > SalesOffice.PLINTH_RADIUS + 0.4
	check(plinths_clear, "and past the bikes on show")
	check(Workshop.SHOWROOM_SPOTS.size() == 4 and Workshop.SHOWROOM_SPOTS.all(func(x): return Workshop.room_at(x.origin) == "sales"),
		"four display plinths in the showroom")
	var apart := true
	for i in 4:
		for j in range(i + 1, 4):
			apart = apart and Workshop.SHOWROOM_SPOTS[i].origin.distance_to(Workshop.SHOWROOM_SPOTS[j].origin) > SalesOffice.PLINTH_RADIUS * 2.0 + 0.2
	check(apart, "far enough apart for a bike on each")
	# Upstairs and downstairs.
	var mid := office.get_center()
	check(Workshop.room_at(Vector3(mid.x, 0.0, mid.y)) == "sales" and Workshop.room_at(Vector3(mid.x, SalesOffice.MEZZ_Y + 1.6, mid.y)) == "sales_office",
		"the office is upstairs, over the ground floor")
	check(Workshop.room_at(SalesOffice.at(5.0, 4.0, 0.0)) == "sales", "the showroom is double height")
	check(Weather.shelter_top("sales") > SalesOffice.CEIL_Y and not Weather.raining_at(SalesOffice.CENTER), "its roof keeps the rain off")
	check(SalesOffice.spot_near(Workshop.SHOWROOM_SPOTS[2].origin + Vector3(0.5, 0.0, 0.3)) == 2 and SalesOffice.spot_near(SalesOffice.CENTER + Vector3(-5.0, 0.0, 0.0)) == -1,
		"a bike let go of by a plinth goes onto it")
	var bell := Sfx.stream("bell")
	var chime := Sfx.stream("bell_chime")
	check(bell.data.size() > Sfx.RATE * 2 and chime.data.size() > Sfx.RATE * 2 and not Sfx.LOOPS.has("bell"), "the shop bell and the shed chime are one-shot sounds")


## Bikes on show and the office lights in a save; a save from before the sales office.
func _test_sales_office_save() -> void:
	Shed.start_new("Tester", 31)
	check(Shed.room_lit("sales"), "a new shed's sales office is lit")
	var bike := _bike_named("Old Faithful")
	var spot: Transform3D = Workshop.SHOWROOM_SPOTS[1]
	check(Shed.check(Shed.me(), {"a": "grab_bike", "bike": bike}) == "", "you can wheel a bike to the showroom")
	Shed.request({"a": "grab_bike", "bike": bike})
	Shed.request({"a": "move_bike", "bike": bike, "xf": spot.translated(Vector3(0.4, 0.0, -0.3))})
	Shed.request({"a": "release_bike", "bike": bike, "xf": Transform3D(Basis(), spot.origin + Vector3(0.4, 0.0, -0.3))})
	var xf: Transform3D = Shed.bikes[bike]["xf"]
	check(xf.is_equal_approx(spot) and str(Shed.bikes[bike]["stand"]) == "" and Shed.showroom_spot_of(bike) == 1,
		"let go of by a plinth, it stands square on it, upright on show")
	var ranger := _bike_named("Rusty Ranger")
	Shed.request({"a": "grab_bike", "bike": ranger})
	Shed.request({"a": "release_bike", "bike": ranger, "xf": Transform3D(Basis(), spot.origin + Vector3(-0.5, 0.0, 0.2))})
	check(not (Shed.bikes[ranger]["xf"] as Transform3D).is_equal_approx(spot) and Shed.showroom_spot_of(ranger) == -1,
		"a plinth with a bike on it is taken")
	Shed.request({"a": "lights", "room": "sales", "on": false})
	check(not Shed.room_lit("sales") and Shed.room_lit("paint") and Shed.lights_on, "the office lights have their own switch")
	var snap: Dictionary = Shed._snapshot().duplicate(true)
	Shed.start_new("Tester", 32)
	Shed.load_state(snap, "Tester")
	check((Shed.bikes[bike]["xf"] as Transform3D).is_equal_approx(spot) and not Shed.room_lit("sales"), "and both come back from a save")
	var old: Dictionary = snap.duplicate(true)
	(old["room_lights"] as Dictionary).erase("sales")
	Shed.start_new("Tester", 33)
	Shed.load_state(old, "Tester")
	check(Shed.room_lit("sales") and Shed.bikes.size() == (snap["bikes"] as Dictionary).size(),
		"a save from before the sales office opens with it lit, and nothing else changed")
	Shed.stop()


## Walking it: the floors, the doors, the stairs up to the office and back down, wheeling a
## bike in onto a plinth, the light switches and the bell.
func _test_sales_office_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ws: Workshop = main.workshop
	var so: SalesOffice = ws.sales_office
	check(so != null and so.get_parent() == ws, "the sales office is built with the shed")
	var space: PhysicsDirectSpaceState3D = ws.get_world_3d().direct_space_state
	var down := func(x: float, z: float, from_y: float) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 8.0, z), 1)
		return space.intersect_ray(q)
	var at := func(lx: float, lz: float) -> Vector2:
		return Vector2(SalesOffice.CENTER.x + lx, SalesOffice.CENTER.z + lz)
	# Off the road loop.
	var road_gap := 999.0
	for p in [Vector2(SalesOffice.FORECOURT.position.x, SalesOffice.FORECOURT.end.y), SalesOffice.FORECOURT.end, SalesOffice.footprint().position,
			Vector2(SalesOffice.footprint().end.x, SalesOffice.footprint().position.y)]:
		road_gap = minf(road_gap, (main.world._road_info(p.x, p.y) as Vector2).x)
	check(road_gap > World.ROAD_HALF_WIDTH + 10.0, "the sales office and car park are well off the road (%.0f m)" % road_gap)
	# Floors: the ground floor everywhere (yard level), the mezzanine at its height.
	var level := true
	for p in [Vector2(0.0, 4.0), Vector2(3.9, 1.4), Vector2(-3.5, 0.5), Vector2(-4.0, -4.6), Vector2(-5.0, 1.2), Vector2(6.5, -5.4)]:
		var q: Vector2 = at.call(p.x, p.y)
		var hit: Dictionary = down.call(q.x, q.y, 2.5)
		level = level and not hit.is_empty() and absf((hit["position"] as Vector3).y) < 0.02 and (hit["normal"] as Vector3).y > 0.99
	check(level, "the ground floor is level with the yard")
	var upstairs := true
	for p in [Vector2(-3.8, 2.6), Vector2(-5.5, -4.0), Vector2(-2.0, 5.0), Vector2(-6.0, 3.0)]:
		var q: Vector2 = at.call(p.x, p.y)
		var hit: Dictionary = down.call(q.x, q.y, SalesOffice.CEIL_Y - 0.2)
		upstairs = upstairs and not hit.is_empty() and absf((hit["position"] as Vector3).y - SalesOffice.MEZZ_Y) < 0.02
	check(upstairs, "the mezzanine floor is level")
	var plinth: Vector3 = Workshop.SHOWROOM_SPOTS[0].origin
	var top: Dictionary = down.call(plinth.x, plinth.z, 2.0)
	check(not top.is_empty() and absf((top["position"] as Vector3).y - SalesOffice.PLINTH_TOP) < 0.01, "the plinths are low enough to step and wheel onto")
	# The stairs: a smooth slope under the steps, at a pitch the walker climbs.
	var w: Walker = main.walker
	var ramp_ok := true
	for k in 9:
		var lx := lerpf(SalesOffice.STAIR_LOW_X - 0.2, SalesOffice.MEZZ_EDGE + 0.2, k / 8.0)
		var q: Vector2 = at.call(lx, -5.4)
		var hit: Dictionary = down.call(q.x, q.y, SalesOffice.CEIL_Y - 0.3)
		ramp_ok = ramp_ok and not hit.is_empty() and absf((hit["position"] as Vector3).y - SalesOffice.stair_height(lx)) < 0.08 \
			and (hit["normal"] as Vector3).angle_to(Vector3.UP) < w.floor_max_angle
	check(ramp_ok, "the stairs climb at %.0f degrees, under the walker's %.0f" % [rad_to_deg(atan2(SalesOffice.MEZZ_Y, SalesOffice.STAIR_LOW_X - SalesOffice.MEZZ_EDGE)),
		rad_to_deg(w.floor_max_angle)])
	# The front doors: shut with nobody about, sliding open as you come up.
	w.set_tool("hands")
	var door := Workshop.SALES_DOOR
	w.place(Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.1, 2.0)))
	for i in 120:
		await get_tree().physics_frame
	var through := func() -> bool:
		var q := PhysicsRayQueryParameters3D.create(door + Vector3(0.4, 1.2, 1.0), door + Vector3(0.4, 1.2, -1.0), 1)
		return space.intersect_ray(q).is_empty()
	check(so.door_open_amount < 0.01 and not through.call(), "the sales office doors are shut with nobody about")
	w.place(Transform3D(Basis(), door + Vector3(-0.3, 0.1, 3.5)))
	Input.action_press("move_forward")
	var opened := false
	for i in 360:
		await get_tree().physics_frame
		if absf(w.global_position.z - door.z) < 0.6:
			opened = opened or (so.door_open_amount > 0.9 and through.call())
	Input.action_release("move_forward")
	check(Workshop.room_at(w.global_position) == "sales", "they slide open and you walk in (%s)" % str(w.global_position))
	check(opened, "open wide as you go through them")
	# Up the stairs to the office, and back down.
	var foot: Vector2 = at.call(SalesOffice.STAIR_LOW_X + 1.2, -5.4)
	w.place(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(foot.x, 0.1, foot.y)))
	Input.action_press("move_forward")
	for i in 600:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(absf(w.global_position.y - SalesOffice.MEZZ_Y) < 0.1 and Workshop.room_at(w.global_position) == "sales_office",
		"you can climb the stairs to the mezzanine office (%s)" % str(w.global_position))
	var landing: Vector2 = at.call(SalesOffice.MEZZ_EDGE - 1.0, -5.4)
	w.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(landing.x, SalesOffice.MEZZ_Y + 0.1, landing.y)))
	Input.action_press("move_forward")
	for i in 600:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(absf(w.global_position.y) < 0.1 and w.global_position.x > SalesOffice.CENTER.x + SalesOffice.STAIR_LOW_X,
		"and walk back down (%s)" % str(w.global_position))
	# The balustrade stops you walking off the edge of the mezzanine.
	var edge: Vector2 = at.call(SalesOffice.MEZZ_EDGE - 1.0, 2.6)
	w.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(edge.x, SalesOffice.MEZZ_Y + 0.1, edge.y)))
	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(w.global_position.y > SalesOffice.MEZZ_Y - 0.1, "the glass balustrade keeps you on the mezzanine")
	# Wheel a bike in through the doors and onto a plinth.
	var bike := _bike_named("Old Faithful")
	w.place(Transform3D(Basis(), door + Vector3(-0.75, 0.1, 4.0)))
	await get_tree().physics_frame
	Shed.request({"a": "grab_bike", "bike": bike})
	check(Shed.pushing_bike(Shed.me()) == bike, "you take hold of a bike outside")
	Input.action_press("move_forward")
	for i in 300:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(Workshop.room_at(w.global_position) == "sales" and Workshop.room_at((Shed.bikes[bike]["xf"] as Transform3D).origin) == "sales",
		"and wheel it in through the doors")
	var spot: Transform3D = Workshop.SHOWROOM_SPOTS[0]
	w.place(Transform3D(Basis(), spot.origin - Vector3(0.55, 0.0, 0.1) + Vector3.UP * 0.1))
	for i in 20:
		await get_tree().physics_frame
	_press("interact")
	for i in 5:
		await get_tree().physics_frame
	check(Shed.pushing_bike(Shed.me()) == 0 and Shed.showroom_spot_of(bike) == 0, "let go of by a plinth, it goes on show (%s)" % str((Shed.bikes[bike]["xf"] as Transform3D).origin))
	await get_tree().process_frame
	var view: Node3D = ws.bike_views.get(bike)
	check(view != null and absf(view.global_position.y - SalesOffice.PLINTH_TOP) < 0.01, "drawn standing on the plinth")
	# The light switch by the stairs.
	w.place(Transform3D(Basis(), SalesOffice.CENTER + Vector3(SalesOffice.MEZZ_EDGE + 1.3, 0.1, -2.0)))
	await _aim_point(w, SalesOffice.at(SalesOffice.MEZZ_EDGE + 0.02, 1.35, -2.0))
	check(w.target.get("kind", "") == "lights" and w.target.get("room", "") == "sales" and w.info.contains("Sales office lights"),
		"the sales office light switch (%s)" % str(w.target))
	_press("interact")
	for i in 3:
		await get_tree().process_frame
	check(not Shed.room_lit("sales") and so._lights.all(func(l): return not (l as Light3D).visible), "turns its lights off")
	Shed.request({"a": "lights", "room": "sales", "on": true})
	for i in 3:
		await get_tree().process_frame
	check(so._lights.all(func(l): return (l as Light3D).visible) and so.lights_shown(), "and on")
	# The bell: everyone hears it, and the shop bell swings.
	var heard := [0]
	var on_bell := func(): heard[0] += 1
	Shed.bell_rang.connect(on_bell)
	var before := Shed.bells_heard
	Shed.ring_bell()
	for i in 6:
		await get_tree().process_frame
	check(Shed.bells_heard == before + 1 and heard[0] == 1, "the host rings the sales office bell")
	var bell_s := Sfx.stream("bell")
	var chime_s := Sfx.stream("bell_chime")
	var players := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(p): return p.stream == bell_s or p.stream == chime_s)
	check(players.size() >= 2, "the shop bell rings over its door and the chime in the shed")
	var chime := players.filter(func(p): return p.stream == chime_s)
	check(not chime.is_empty() and Workshop.room_at((chime[0] as Node3D).global_position) == "shed", "the chime is in the shed")
	check(absf((so.get_node("ShopBell") as Node3D).rotation.x) > 0.01, "and the bell over the door swings")
	Shed.bell_rang.disconnect(on_bell)
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The garage upgrades catalogue: every upgrade named and priced from a few thousand up to
## hundreds of thousands, and everything it needs listed before it.
func _test_upgrade_catalogue() -> void:
	var seen := []
	var ok := true
	var top := 0
	var cheapest := 1000000000
	for id in GarageUpgrades.CATALOGUE:
		var u: Dictionary = GarageUpgrades.CATALOGUE[id]
		ok = ok and str(u.get("name", "")) != "" and str(u.get("desc", "")) != "" and GarageUpgrades.CATEGORIES.has(str(u.get("cat", "")))
		for n in u["needs"]:
			ok = ok and seen.has(n)
		top = maxi(top, int(u["price"]))
		cheapest = mini(cheapest, int(u["price"]))
		seen.append(id)
	check(ok, "every upgrade has a name, a description and a group, and comes after what it needs")
	check(cheapest >= 1000 and cheapest < 10000 and top >= 100000, "prices run from %s to %s" % [TvChannels.money_text(cheapest), TvChannels.money_text(top)])
	for key in ["wing", "bays_56", "bay_7", "annex", "racking", "mezzanine", "epoxy", "led", "cladding", "signage", "lounge", "showroom"]:
		check(GarageUpgrades.exists(key), "the catalogue has %s" % GarageUpgrades.title(key))
	check(Progress.XP.has(GarageUpgrades.XP_KEY), "buying one is worth XP")
	# The new buildings stay clear of the shed's rooms, each other and the yard in front.
	var all := Workshop.rooms()
	all.merge(GarageUpgrades.rooms({"wing": true, "annex": true}))
	var clear := true
	for a in all:
		for b in all:
			if a.begins_with("sales") and b.begins_with("sales"):
				continue   # the mezzanine office is upstairs inside the sales office
			if a != b and (all[a] as Rect2).grow(-0.01).intersects((all[b] as Rect2).grow(-0.01)):
				clear = false
				print("    %s overlaps %s" % [a, b])
	check(clear, "the extension and the annex don't overlap any room")
	check(GarageUpgrades.WING.end.y < Workshop.CENTER.z - Workshop.HALF.y and GarageUpgrades.ANNEX.end.y < Workshop.STORE_CENTER.z - Workshop.STORE_HALF.y,
		"both are behind the shed, away from the yard")
	var racks_in := true
	for xf in GarageUpgrades.racking_xfs():
		var size: Vector3 = Equipment.get_model("shelf_racking")["size"]
		var foot := Shed.foot_rect(xf, Vector2(size.x, size.z))
		racks_in = racks_in and GarageUpgrades.ANNEX.encloses(foot)
	check(racks_in, "the racking stands inside the annex")


## Buying upgrades with the garage's money: refused when broke or before what it needs, the
## money taken, XP paid, more bays that take bikes, holograms and builds, racking that is real
## shelving, and all of it kept in the save (old saves have none).
func _test_upgrade_buying() -> void:
	Shed.start_new("Tester", 9)
	var me := Shed.me()
	check(Shed.upgrades.is_empty() and Workshop.bay_count() == Workshop.BAY_COUNT, "a new shed has no upgrades and four bays")
	Shed.request({"a": "buy_upgrade", "id": "wing"})
	check(not GarageUpgrades.owned("wing") and Shed.check(me, {"a": "buy_upgrade", "id": "wing"}).contains("afford"), "the garage can't buy one with no money")
	Shed.request({"a": "garage_money", "value": 100000})
	check(Shed.check(me, {"a": "buy_upgrade", "id": "bays_56"}).contains("Needs the workshop extension"), "bays 5 and 6 need the extension first")
	check(Shed.check(me, {"a": "buy_upgrade", "id": "nope"}) != "", "nothing that isn't in the catalogue")
	var xp := int(Progress.profile.get("xp", 0))
	Shed.request({"a": "buy_upgrade", "id": "wing"})
	check(GarageUpgrades.owned("wing") and Shed.garage_money == 70000, "the extension is built and %s comes out of the garage's money" % TvChannels.money_text(30000))
	check(int(Progress.profile.get("xp", 0)) > xp, "the buyer gets XP")
	check(Shed.check(me, {"a": "buy_upgrade", "id": "wing"}).contains("already"), "it can't be bought twice")
	check(Workshop.rooms().has("wing") and not Workshop.rooms().has("annex"), "the extension is a room now (no rain inside)")
	Shed.request({"a": "buy_upgrade", "id": "bays_56"})
	check(Workshop.bay_count() == 6, "bays 5 and 6: six bays")
	Shed.request({"a": "buy_upgrade", "id": "bay_7"})
	check(Workshop.bay_count() == 7 and Shed.garage_money == 100000 - 30000 - 20000 - 12500, "bay 7: seven bays, and the money's gone down")
	check(TvChannels.screen_exists("bay6") and not TvChannels.screen_exists("bay7"), "each new bay has a screen with channels")
	var spots := {}
	for bay in Workshop.bay_count():
		spots[Workshop.bay_transform(bay).origin.snapped(Vector3.ONE * 0.1)] = true
		check(Shed.bay_at(Workshop.bay_transform(bay).origin) == bay, "bay %d's stand is where bay_at finds it" % (bay + 1))
	check(spots.size() == 7, "every bay has its own spot")
	var inside := true
	for i in 3:
		inside = inside and GarageUpgrades.WING.has_point(Vector2(Workshop.bay_transform(4 + i).origin.x, Workshop.bay_transform(4 + i).origin.z))
	check(inside, "the new bays are in the extension")
	# Project bikes go to the new bays once the shed's own are full.
	Shed.request({"a": "order"})
	Shed.request({"a": "order"})
	var in_five := Shed.bike_in_bay(4)
	check(in_five != 0 and Shed.on_paddock(in_five), "a project bike is delivered to bay 5, on its paddock stand")
	# A blueprint build waiting in bay 6, and a frame started in bay 7.
	var bp := Shed._save_blueprint(in_five, "Bay six special")
	Shed.request({"a": "bp_build", "bp": bp, "bay": 5})
	check(Shed.holograms.has(5) and Shed.plan_bays().has(5), "a blueprint build can wait in bay 6")
	var frame := Shed._new_item("steel_cradle", 0.0, 0.0, 0.0)
	Shed._move(frame, "held", me)
	Shed.request({"a": "start_build", "bay": 6})
	check(Shed.bike_in_bay(6) != 0, "a bike can be started from a bare frame in bay 7")
	check(Shed.free_bay(Workshop.bay_count()) < 0 and Shed.check(me, {"a": "order"}) != "", "with all seven full, no more project bikes")
	# Storage: the annex, then racking that is real shelving.
	Shed.request({"a": "buy_upgrade", "id": "racking"})
	check(not GarageUpgrades.owned("racking"), "racking needs the annex")
	Shed.request({"a": "garage_money", "value": 500000})
	var shelves := Shed.furniture.values().filter(func(f): return f["model"] == "shelf_racking").size()
	Shed.request({"a": "buy_upgrade", "id": "annex"})
	Shed.request({"a": "buy_upgrade", "id": "racking"})
	var racks := Shed.furniture.values().filter(func(f): return f["model"] == "shelf_racking")
	check(racks.size() == shelves + 3 and Shed.furniture_spots(int(racks[0]["id"])).size() > 0, "racking: three runs of heavy-duty shelving in the annex")
	Shed.request({"a": "buy_upgrade", "id": "showroom"})
	check(not GarageUpgrades.owned("showroom") and Shed.check(me, {"a": "buy_upgrade", "id": "showroom"}).contains("Needs"), "the showroom needs the other finishes first")
	# Saved and loaded.
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.start_new("Tester", 9)
	check(Workshop.bay_count() == 4, "a new shed starts without them")
	Shed.load_state(copy, "Tester")
	check(GarageUpgrades.owned("bay_7") and GarageUpgrades.owned("racking") and Workshop.bay_count() == 7 and Shed.bike_in_bay(4) != 0,
		"the upgrades come back with the save, bikes still in the new bays")
	check(Shed.screen_channel("bay6")["ch"] == "bay", "bay 7's screen shows its bay")
	copy.erase("upgrades")
	Shed.load_state(copy, "Tester")
	check(Shed.upgrades.is_empty() and Workshop.bay_count() == 4, "a shed saved before upgrades has none")
	copy["upgrades"] = {"wing": true, "gold_toilet": true}
	Shed.load_state(copy, "Tester")
	check(Shed.upgrades.keys() == ["wing"], "upgrades that don't exist are dropped from a save")
	Shed.stop()


## In the game: buying rebuilds the shed for everyone straight away. The doorway is knocked
## through, the new bays have screens and lights, the stairs can be climbed, and nothing new
## is built through the shed's own walls.
func _test_upgrade_session() -> void:
	SaveGame.slot_override = "test_upgrades"
	SaveGame.delete_slot("test_upgrades")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	await get_tree().physics_frame
	var ws: Workshop = main.world.workshop
	check(ws.upgrades != null and ws.upgrades.built() == "", "the shed starts with nothing built on")
	var space := ws.get_world_3d().direct_space_state
	var through := func(from: Vector3, to: Vector3) -> bool:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		return space.intersect_ray(q).is_empty()
	var door_from := Vector3(GarageUpgrades.WING_DOOR_X, 1.2, 60.5)
	var door_to := Vector3(GarageUpgrades.WING_DOOR_X, 1.2, 57.0)
	check(not through.call(door_from, door_to), "before the extension the back wall is solid there")
	var nodes := ws.get_child_count()
	Shed.request({"a": "garage_money", "value": 1000000})
	for id in GarageUpgrades.CATALOGUE:
		Shed.request({"a": "buy_upgrade", "id": id})
	check(Shed.upgrades.size() == GarageUpgrades.CATALOGUE.size(), "with money enough, everything can be bought in order")
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(ws.upgrades.built().contains("showroom") and ws.get_node_or_null("Upgrades/Built/WingFloor") != null
		and ws.get_node_or_null("Upgrades/Built/AnnexFloor") != null and ws.get_node_or_null("Upgrades/Built/MezzanineDeck") != null,
		"the shed is rebuilt with the extension, the annex and the mezzanine")
	check(through.call(door_from, door_to), "a doorway is knocked through the back wall behind bay 4")
	check(not through.call(Vector3(3.0, 1.2, 60.5), Vector3(3.0, 1.2, 57.0)), "the rest of the back wall is still there")
	check(through.call(Vector3(GarageUpgrades.ANNEX_DOOR_X, 1.2, 56.0), Vector3(GarageUpgrades.ANNEX_DOOR_X, 1.2, 52.0))
		and not through.call(Vector3(-14.0, 1.2, 56.0), Vector3(-14.0, 1.2, 52.0)), "and one through the storage room's back wall into the annex")
	var stairs := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-7.45, 4.0, 51.7), Vector3(-7.45, -1.0, 51.7), 1))
	check(not stairs.is_empty() and absf(float(stairs["position"].y) - 1.2) < 0.25, "the mezzanine stairs are a slope to walk up (%.2f m half way)" % float(stairs.get("position", Vector3.ZERO).y))
	var deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-11.5, 4.0, 48.5), Vector3(-11.5, -1.0, 48.5), 1))
	check(not deck.is_empty() and absf(float(deck["position"].y) - GarageUpgrades.MEZZ_TOP) < 0.05, "the deck is up at %.1f m" % GarageUpgrades.MEZZ_TOP)
	var all := ws.screens()
	check(all.has("bay4") and all.has("bay5") and all.has("bay6") and not all.has("bay7"), "the three new bays have screens")
	check((all["bay6"] as Dashboard).global_position.distance_to(Workshop.bay_transform(6).origin) < 3.5, "bay 7's screen hangs over bay 7")
	var raised: Dashboard = all["bay3"]
	check(raised.global_position.y - raised.width * Dashboard.PX.y / Dashboard.PX.x * 0.5 > GarageUpgrades.WING_DOOR_HEIGHT,
		"bay 4's screen moves up over the new doorway")
	var shelters: PackedVector4Array = main.world.weather._rain_mat.get_shader_parameter("shelters")
	var w := GarageUpgrades.WING.get_center()
	var dry := false
	for r in shelters:
		dry = dry or (w.x > r.x and w.x < r.z and w.y > r.y and w.y < r.w)
	check(dry, "rain isn't drawn inside the extension")
	check(Workshop.room_at(Vector3(w.x, 0.0, w.y)) == "wing", "and it counts as indoors")
	# A bike in a new bay is drawn there, on its paddock stand, and its bay screen shows it.
	Shed.request({"a": "order"})
	Shed.request({"a": "order"})
	await get_tree().process_frame
	var b5 := Shed.bike_in_bay(4)
	check(b5 != 0 and ws.bike_views.has(b5) and (ws.bike_views[b5] as Node3D).global_position.distance_to(Workshop.bay_transform(4).origin) < 0.1,
		"a project bike delivered to bay 5 is drawn in the extension")
	check(str(ws._bay_data(4).get("name", "")) == str(Shed.bikes[b5]["name"]), "bay 5's screen shows its bike")
	# Rebuilding again changes nothing, and nothing piles up.
	var count := ws.upgrades.get_child(0).get_child_count()
	var lights := ws._shed_lights.size()
	var nodes_now := ws.get_child_count()
	ws.upgrades._sig = "?"
	ws.upgrades.sync()
	await get_tree().process_frame
	check(ws.upgrades.get_child_count() == 1 and ws.upgrades.get_child(0).get_child_count() == count and ws._shed_lights.size() == lights
		and ws._bay_screens.size() == 7, "a rebuild replaces what was there")
	check(ws.get_child_count() == nodes_now, "nothing is left behind on the workshop")
	# Gone again in a new shed.
	Shed.upgrades = {}
	Shed.changed.emit()
	await get_tree().process_frame
	await get_tree().physics_frame
	check(ws.upgrades.built() == "" and not through.call(door_from, door_to) and ws._bay_screens.size() == 4
		and is_equal_approx(raised.position.y, 2.45), "with none, the shed is back as it was")
	# The parts computer's Garage upgrades page.
	Shed.request({"a": "garage_money", "value": 0})
	main.computer.open()
	main.computer.open_upgrades()
	var page: UpgradesPanel = main.computer.upgrades_panel
	check(page.visible and page._rows.size() == GarageUpgrades.CATALOGUE.size(), "the parts computer lists every upgrade")
	page.show_upgrade("wing")
	check(page._buy.disabled and page._status.text.contains("afford"), "Buy is greyed out while the garage can't afford it")
	check(UpgradesPanel.row_text("bay_7").contains("needs") and UpgradesPanel.row_text("bay_7").contains(TvChannels.money_text(12500)), "each row shows its price and what it needs")
	Shed.request({"a": "garage_money", "value": 40000})
	page.refresh()
	page.show_upgrade("wing")
	check(not page._buy.disabled, "with the money, it can be bought")
	page.buy()
	await get_tree().process_frame
	check(GarageUpgrades.owned("wing") and UpgradesPanel.row_text("wing").contains("BUILT"), "Buy builds it, and the list says so")
	main.computer.close_computer()
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	SaveGame.delete_slot("test_upgrades")
	SaveGame.slot_override = ""


# ---------------------------------------------------------------------------- rider gear and trinkets

func _test_gear_catalogue() -> void:
	for slot in RiderGear.SLOTS:
		var ids := RiderGear.by_slot(slot)
		var free := ids.filter(func(id): return RiderGear.price(id) == 0)
		check(ids.size() >= 6 and free.size() == 1 and free[0] == RiderGear.DEFAULTS[slot] and ids[0] == RiderGear.DEFAULTS[slot],
			"%s: %d designs, one free default listed first" % [slot, ids.size()])
	var bad := []
	var names := {}
	for id in RiderGear.ITEMS:
		var it: Dictionary = RiderGear.ITEMS[id]
		if not RiderGear.SLOTS.has(str(it["slot"])) or str(it.get("name", "")) == "" or str(it.get("desc", "")) == "" \
				or not RiderFigure.PATTERNS.has(str(it.get("pattern", "plain"))) or not (it["base"] is Color or it["base"] is String):
			bad.append(id)
		names[str(it["slot"]) + str(it["name"])] = true
	check(bad.is_empty(), "every gear item has a slot, name, description, colour and a known pattern (%s)" % str(bad))
	check(names.size() == RiderGear.ITEMS.size(), "no two items in a slot share a name")
	var shapes := {}
	for id in RiderGear.by_slot("helmet"):
		shapes[str(RiderGear.ITEMS[id]["shape"])] = true
	check(shapes.size() >= 5, "helmets come in at least five shapes (%s)" % str(shapes.keys()))
	# Patterns: a stripe runs down the front, hoops go round.
	var b := Color.WHITE
	var t := Color.RED
	check(RiderFigure.pattern_color("stripe", 0.5, 0.3, b, t, b) == t and RiderFigure.pattern_color("stripe", 0.25, 0.3, b, t, b) == b,
		"a stripe is at the front, not the side")
	check(RiderFigure.pattern_color("hoops", 0.1, 0.2, b, t, b) != RiderFigure.pattern_color("hoops", 0.1, 0.05, b, t, b), "hoops go round")
	# Trinkets: sold in the Shop, kit of kind "trinket" once in the shed, not on the parts computer.
	check(Trinkets.MODELS.size() >= 10, "at least ten trinkets (%d)" % Trinkets.MODELS.size())
	var odd := []
	for id in Trinkets.MODELS:
		var m: Dictionary = Trinkets.MODELS[id]
		if Equipment.kind_of(id) != "trinket" or int(m["price"]) <= 0 or not (m["size"] is Vector3) or Equipment.get_model(id).is_empty():
			odd.append(id)
	check(odd.is_empty(), "every trinket is shed kit of kind trinket with a price and a size (%s)" % str(odd))
	check(Equipment.is_wall("trinket_clock") and Equipment.is_wall("trinket_neon") and not Equipment.is_wall("trinket_plant"),
		"the clock and neon sign hang on a wall, the plant stands on the floor")
	check(not PartsComputer.all_kinds().has("eq:trinket") and PartsComputer.search("lava lamp").is_empty(),
		"trinkets aren't on the parts computer")
	# Each trinket draws something.
	var empty := []
	for id in Trinkets.MODELS:
		var n := Node3D.new()
		Trinkets.build(n, id)
		if n.get_child_count() == 0:
			empty.append(id)
		n.free()
	check(empty.is_empty(), "every trinket has a model (%s)" % str(empty))


func _test_gear_buying() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_gear_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Gear Tester", 5)
	Progress.select("Gear Tester")
	var gear: Dictionary = Progress.profile.get("gear", {})
	check(RiderGear.sig(gear.get("worn", {})) == RiderGear.sig(RiderGear.DEFAULTS) and (gear["owned"] as Array).size() == 5,
		"a new rider owns and wears the five free defaults")
	Progress.set_money(100)
	var why := RiderGear.buy("helmet_sprint")
	check(why.contains("afford") and not RiderGear.owns("helmet_sprint") and Progress.money() == 100,
		"too little money: the helmet isn't sold and nothing is taken (%s)" % why)
	check(RiderGear.wear("helmet_sprint") != "" and RiderGear.worn_of(Shed.me())["helmet"] == "helmet_cap", "you can't wear what you haven't bought")
	Progress.set_money(500)
	why = RiderGear.buy("helmet_sprint")
	check(why == "" and RiderGear.owns("helmet_sprint") and Progress.money() == 500 - RiderGear.price("helmet_sprint"),
		"with enough money it's bought and paid for (%d left)" % Progress.money())
	check(RiderGear.buy("helmet_sprint") != "" and Progress.money() == 500 - RiderGear.price("helmet_sprint"), "you can't buy the same thing twice")
	check(RiderGear.wear("helmet_sprint") == "" and RiderGear.worn_of(Shed.me())["helmet"] == "helmet_sprint", "and then worn")
	check(RiderGear.buy("no_such_lid") != "", "an unknown item isn't sold")
	check(Progress.own_summary()["gear"]["helmet"] == "helmet_sprint", "what you wear goes out in your summary")
	# Kept in the profile, so it goes with you to any shed.
	Progress.save_profile()
	Progress.profile = {}
	Progress.select("Gear Tester")
	check(RiderGear.owns("helmet_sprint") and RiderGear.worn_of(Shed.me())["helmet"] == "helmet_sprint", "owned and worn gear are kept in the profile")
	# A profile from before gear gets the defaults; bad entries are dropped.
	var f := FileAccess.open(Progress.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "profiles": {"Old Timer": {"name": "Old Timer", "xp": 10, "money": 40},
		"Cheat": {"name": "Cheat", "gear": {"owned": ["jacket_kestrel", "rocket_boots"], "worn": {"jacket": "jacket_kestrel", "boots": "rocket_boots", "gloves": "gloves_kestrel"}}}}}))
	f.close()
	Progress.select("Old Timer")
	check(RiderGear.sig(RiderGear.worn_of(Shed.me())) == RiderGear.sig(RiderGear.DEFAULTS) and Progress.money() == 40,
		"an old profile without gear wears the defaults")
	Progress.select("Cheat")
	var worn := RiderGear.worn_of(Shed.me())
	check(worn["jacket"] == "jacket_kestrel" and worn["boots"] == "boots_work" and worn["gloves"] == "gloves_work"
		and not RiderGear.owns("rocket_boots"), "unknown gear is dropped, and gear not owned isn't worn (%s)" % str(worn))
	check(RiderGear.sig(Progress._clean_summary({"gear": {"helmet": "helmet_mx", "jacket": 5, "boots": "helmet_mx"}})["gear"]) ==
		"helmet_mx|jacket_overalls|trousers_overalls|boots_work|gloves_work", "a reported summary's gear is checked slot by slot")
	Progress.save_profile()   # into the test file, not the real profile once the path is back
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


func _test_gear_seen_by_others() -> void:
	# Another player in their gear: their figure, and their rider on a bike.
	var peer := 777
	Progress._summaries[peer] = {"name": "Visitor", "gear": RiderGear.clean_worn({"helmet": "helmet_mx", "jacket": "jacket_mx"})}
	var rp := RemotePlayer.new()
	add_child(rp)
	rp.setup(peer, "Visitor", Color(0.2, 0.4, 0.9))
	check(rp.gear["helmet"] == "helmet_mx" and rp.gear["jacket"] == "jacket_mx" and rp.gear["boots"] == "boots_work",
		"another player is drawn in the gear their summary says")
	var meshes := func() -> int: return rp._head_look.get_child_count()
	var was: int = meshes.call()
	Progress._summaries[peer]["gear"] = RiderGear.clean_worn({"helmet": "helmet_cap"})
	for i in 2:
		await get_tree().process_frame
	check(rp.gear["helmet"] == "helmet_cap" and meshes.call() != was, "when they change, they're drawn again (%d -> %d meshes)" % [was, meshes.call()])
	rp.queue_free()
	Progress._summaries.erase(peer)
	# The rider on a bike.
	var plain := BikeModel.new()
	add_child(plain)
	plain.build_from(BikeBuild.new())
	var dressed := BikeModel.new()
	dressed.rider_gear = RiderGear.clean_worn({"helmet": "helmet_kestrel", "jacket": "jacket_kestrel", "boots": "boots_mx", "trousers": "trousers_kestrel"})
	add_child(dressed)
	dressed.build_from(BikeBuild.new())
	check(dressed._rider != null and dressed._rider.get_child_count() > plain._rider.get_child_count(),
		"a rider in race gear on a bike is drawn with it (%d meshes, plain %d)" % [dressed._rider.get_child_count(), plain._rider.get_child_count()])
	var helmeted := 0
	for c in dressed._rider.get_children():
		if (c as VisualInstance3D).layers == 1 << (BikeModel.HELMET_LAYER - 1):
			helmeted += 1
	check(helmeted >= 4, "the helmet, torso and upper arms stay out of the first-person view (%d)" % helmeted)
	dressed.redress(RiderGear.clean_worn({}))
	check(dressed._rider != null and dressed.rider_gear["helmet"] == "helmet_cap", "a rider can be dressed again mid-ride")
	plain.queue_free()
	dressed.queue_free()
	var doll := RiderRagdoll.new()
	add_child(doll)
	doll.dress(RiderGear.clean_worn({"helmet": "helmet_sprint"}), Color.RED)
	check(not (doll.get_node("Helmet") as Node3D).visible and doll.get_child_count() > 4, "a crashed rider wears their own helmet")
	doll.queue_free()
	await get_tree().process_frame


func _test_shop_session() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_gear_test.json"
	DirAccess.remove_absolute(Progress.path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	Progress.select("Gear Tester")
	var w: Walker = main.walker
	var shop: ShopTab = main.menu.shop
	check(shop != null and main.menu._tabs.get_tab_idx_from_control(shop) >= 0, "the Esc menu has a Shop tab")
	# Gear from the Shop tab.
	Progress.set_money(0)
	shop.show_category("boots")
	shop.select("boots_mx")
	shop.buy_selected()
	check(not RiderGear.owns("boots_mx") and shop._status.text.contains("afford"), "broke, the shop says so (%s)" % shop._status.text)
	Progress.set_money(1000)
	shop.buy_selected()
	check(RiderGear.owns("boots_mx") and RiderGear.wearing("boots_mx") and Progress.money() == 1000 - RiderGear.price("boots_mx"),
		"Buy pays for the boots and puts them on")
	shop.select("boots_work")
	shop.wear_selected()
	check(RiderGear.worn_of(Shed.me())["boots"] == "boots_work", "Wear changes back into the old pair")
	shop._update_preview()
	check(shop._turntable.get_child_count() == 1, "the turntable shows the rider")
	# A trinket: paid for from your own money and delivered to the shed.
	var cash := Progress.money()
	shop.show_category("trinket")
	shop.select("trinket_trophy")
	shop.buy_selected()
	var trophy := _first_furniture("trinket_trophy")
	check(trophy != 0 and Progress.money() == cash - Trinkets.price("trinket_trophy") and Shed.furniture[trophy]["kind"] == "trinket",
		"a trophy bought in the Shop arrives in the shed, paid for")
	Progress.set_money(5)
	check(Trinkets.buy("trinket_neon").contains("afford") and _first_furniture("trinket_neon") == 0 and Progress.money() == 5,
		"broke, no neon sign")
	Progress.set_money(1000)
	check(Trinkets.buy("trinket_neon") == "" and Trinkets.buy("trinket_plant") == "", "the neon sign and a plant")
	var neon := _first_furniture("trinket_neon")
	var plant := _first_furniture("trinket_plant")
	await get_tree().process_frame
	check(main.workshop.furniture_nodes.has(trophy) and main.workshop.furniture_nodes[trophy].kind == "trinket", "the trophy is drawn in the shed")
	# Carried and put down on the workbench like any other kit.
	var bz: float = Workshop.spot_transform("bench_1").origin.z
	w.place(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(Workshop.CENTER.x - Workshop.HALF.x + 1.5, 0.0, bz)))
	Shed.request({"a": "grab", "furniture": trophy})
	for i in 4:
		await get_tree().physics_frame
	var xf: Transform3D = w._push_transform(trophy)
	check(absf(xf.origin.y - 0.945) < 0.03, "held over the workbench, the trophy goes down on its top (%.2f)" % xf.origin.y)
	Shed.request({"a": "release", "furniture": trophy, "xf": xf})
	check(Shed.furniture[trophy]["mover"] == 0 and absf((Shed.furniture[trophy]["xf"] as Transform3D).origin.y - 0.945) < 0.03, "and stays there")
	# The neon sign hangs on a wall.
	Shed.request({"a": "grab", "furniture": neon})
	w.place(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(Workshop.CENTER.x - Workshop.HALF.x + 1.2, 0.0, bz + 2.0)))
	w._pitch = 0.0
	w.camera.rotation.x = 0.0
	await get_tree().physics_frame
	var wall_xf: Transform3D = w._push_transform(neon)
	check(w._on_wall and absf(wall_xf.origin.x - (Workshop.CENTER.x - Workshop.HALF.x)) < 0.1, "the neon sign goes on the wall (%s)" % str(wall_xf.origin))
	Shed.request({"a": "release", "furniture": neon, "xf": wall_xf})
	# Scrapped like other kit.
	Shed.request({"a": "grab", "furniture": plant})
	Shed.request({"a": "scrap", "furniture": plant})
	check(not Shed.furniture.has(plant), "a trinket can be scrapped")
	# Saved with the shed.
	Shed.load_state(str_to_var(var_to_str(Shed._snapshot())), "Tester")
	check(Shed.furniture.has(trophy) and Shed.furniture[trophy]["model"] == "trinket_trophy"
		and absf((Shed.furniture[trophy]["xf"] as Transform3D).origin.y - 0.945) < 0.03 and Shed.furniture.has(neon),
		"trinkets are kept with the shed, where they were put")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	Progress.save_profile()   # into the test file, not the real profile once the path is back
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


## Graphics settings: presets set their keys, Custom after a change, saving and loading,
## applying to the viewport headless, the driver override file and the Graphics tab.
func _test_graphics_settings() -> void:
	# Keep the player's own settings file and graphics settings as they were.
	var had := FileAccess.file_exists(Settings.PATH)
	var before := FileAccess.get_file_as_string(Settings.PATH) if had else ""
	var keep := {"high_quality": Settings.high_quality}
	for k in Settings.GFX_KEYS:
		keep[k] = Settings.get(k)
	var changes := [0]
	var count := func(): changes[0] += 1
	Settings.graphics_changed.connect(count)
	# Presets set every key they cover.
	for preset in ["low", "medium", "high", "ultra"]:
		Settings.apply_preset(preset)
		var values: Dictionary = Graphics.PRESETS[preset]
		var wrong := values.keys().filter(func(k): return Settings.get(k) != values[k])
		check(wrong.is_empty() and Settings.gfx_preset == preset and Settings.high_quality == (preset != "low"),
			"the %s preset sets its options %s" % [preset, str(wrong)])
	check(changes[0] == 4, "every preset change tells the game (%d)" % changes[0])
	var shared := ["gfx_gi", "gfx_volumetrics", "gfx_clouds", "gfx_ssr", "gfx_ssao", "gfx_glow", "gfx_shadows", "gfx_draw_distance"]
	check(shared.all(func(k): return Graphics.PRESETS["low"].has(k) and Settings.GFX_KEYS.has(k)), "presets cover the lighting options too")
	# Custom: changing one option the preset covers.
	Settings.apply_preset("high")
	Settings.set_graphics("gfx_fov", 90.0)
	check(Settings.gfx_preset == "high" and is_equal_approx(Graphics.fov_offset(), 15.0), "field of view isn't part of a preset")
	Settings.set_graphics("gfx_ssao", false)
	check(Settings.gfx_preset == "custom" and not Settings.gfx_ssao and Settings.high_quality, "changing one option makes it Custom")
	var res_before := Settings.gfx_resolution
	Settings.set_graphics("gfx_msaa", "16x")
	Settings.set_graphics("gfx_render_scale", 5.0)
	Settings.set_graphics("gfx_resolution", "1x1")
	check(Settings.gfx_msaa == "2x" and is_equal_approx(Settings.gfx_render_scale, 2.0) and Settings.gfx_resolution == res_before,
		"values it can't take are refused or clamped (%s, %.2f, %s)" % [Settings.gfx_msaa, Settings.gfx_render_scale, Settings.gfx_resolution])
	# Saved and loaded back.
	Settings.set_graphics("gfx_window_mode", "borderless")
	Settings.set_graphics("gfx_resolution", "2560x1440")
	Settings.set_graphics("gfx_render_scale", 0.75)
	Settings.set_graphics("gfx_upscaler", "fsr1")
	Settings.set_graphics("gfx_fps_cap", 144)
	Settings.set_graphics("gfx_gi", "ssil")
	Settings.set_graphics("gfx_fps_counter", true)
	var saved := {}
	for k in Settings.GFX_KEYS:
		saved[k] = Settings.get(k)
	Settings.save_settings()
	Settings.apply_preset("ultra")
	Settings.gfx_window_mode = "windowed"
	Settings.gfx_fps_cap = 0
	Settings.load_settings()
	var differ := saved.keys().filter(func(k): return Settings.get(k) != saved[k])
	check(differ.is_empty() and Settings.gfx_preset == "custom", "graphics settings save and load back %s" % str(differ))
	# An old settings file with high quality off comes up on the Low preset.
	var old := ConfigFile.new()
	old.set_value("video", "high_quality", false)
	old.save(Settings.PATH)
	Settings.apply_preset("high")
	Settings.load_settings()
	check(Settings.gfx_preset == "low" and Settings.gfx_gi == "off" and not Settings.high_quality, "an old 'high quality off' file becomes Low")
	# Applying to the viewport (headless, so the window itself is left alone).
	var g: Graphics = null
	for c in Settings.get_children():
		if c is Graphics:
			g = c
	check(g != null, "Settings has a Graphics node")
	Settings.apply_preset("low")
	var vp := get_tree().root
	check(vp.msaa_3d == Viewport.MSAA_DISABLED and vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR and is_equal_approx(vp.scaling_3d_scale, 0.75)
		and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "Low: no MSAA, FSR 1 at 75%%, FXAA (mode %d, %.2f)" % [vp.scaling_3d_mode, vp.scaling_3d_scale])
	Settings.apply_preset("ultra")
	check(vp.msaa_3d == Viewport.MSAA_4X and vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and vp.use_taa
		and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA and vp.mesh_lod_threshold < 0.5, "Ultra: 4x MSAA, TAA, SMAA, native, fine LOD")
	Settings.set_graphics("gfx_render_scale", 0.5)
	Settings.set_graphics("gfx_upscaler", "fsr2")
	check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and not vp.use_taa, "FSR 2.2 upscales and takes over from TAA")
	check(Graphics.scaling_mode("fsr2", 1.5) == Viewport.SCALING_3D_MODE_BILINEAR and Graphics.scaling_mode("fsr1", 1.0) == Viewport.SCALING_3D_MODE_BILINEAR,
		"supersampling and 100% use plain bilinear")
	check(Graphics.parse_resolution("3840x2160") == Vector2i(3840, 2160) and Graphics.parse_resolution("7680x4320") == Vector2i(1600, 900)
		and Graphics.RESOLUTIONS.all(func(r): return r.x <= 3840 and r.y <= 2160), "resolutions go up to 4K")
	await get_tree().process_frame
	# The driver override, read by Godot at the next start.
	check(str(ProjectSettings.get_setting("application/config/project_settings_override")) == Graphics.OVERRIDE_PATH,
		"the project reads the graphics override file at start-up")
	var test_path := "user://test_graphics_override.cfg"
	Graphics.write_driver_override("d3d12", test_path)
	var ovr := ConfigFile.new()
	check(ovr.load(test_path) == OK and ovr.get_value("rendering", "rendering_device/driver.windows", "") == "d3d12"
		and ovr.get_value("rendering", "rendering_device/fallback_to_vulkan", false) == true, "DirectX 12 is written for the next start, falling back to Vulkan")
	Graphics.write_driver_override("vulkan", test_path)
	ovr.load(test_path)
	check(ovr.get_value("rendering", "rendering_device/driver.windows", "") == "vulkan", "and Vulkan back again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	# The Graphics tab: picking a preset, and Custom showing after a change.
	var tab := GraphicsTab.new()
	add_child(tab)
	await get_tree().process_frame
	var preset_box: OptionButton = tab._controls["gfx_preset"]["control"]
	preset_box.select(0)
	preset_box.item_selected.emit(0)
	check(Settings.gfx_preset == "low", "the tab's preset list picks Low")
	var ssr: CheckBox = tab._controls["gfx_ssr"]["control"]
	ssr.button_pressed = true
	check(Settings.gfx_ssr and Settings.gfx_preset == "custom" and preset_box.get_item_text(preset_box.selected) == "Custom",
		"ticking an option in the tab makes the preset Custom")
	tab._rt.button_pressed = true
	check(Settings.gfx_gi == "sdfgi", "the ray-traced lighting switch turns SDFGI on")
	tab.queue_free()
	# Put everything back.
	Settings.graphics_changed.disconnect(count)
	for k in keep:
		Settings.set(k, keep[k])
	Settings.graphics_changed.emit()
	if had:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(before)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	await get_tree().process_frame
## The Graphics settings turned into the environment: SDFGI or SSIL, SSR, SSAO, glow,
## volumetric fog, the cloud sky and shadows; and the plainer look on the compatibility renderer.
func _test_lighting_profile() -> void:
	var best := {"gfx_gi": "sdfgi", "gfx_volumetrics": "high", "gfx_clouds": "high", "gfx_ssr": true, "gfx_ssao": true,
		"gfx_glow": true, "gfx_shadows": "ultra", "gfx_draw_distance": 1.0, "gfx_brightness": 1.0}
	var p := Lighting.profile(best, true)
	check(p["sdfgi"] and not p["ssil"] and p["ssr"] and p["ssao"] and p["glow"] and p["volumetric_fog"] and p["fog_volumes"],
		"the best settings: SDFGI, reflections, AO, glow, volumetric fog and fog volumes")
	check(int(p["sdfgi_cascades"]) == 6 and float(p["sdfgi_min_cell"]) < 0.2, "SDFGI reaches across the map with fine cells near you")
	check(bool(p["clouds"]["volumetric"]) and str(p["clouds"]["res"]) == "half" and int(p["fog_size"]) >= 128, "raymarched clouds at half resolution")
	check(int(p["shadow"]["soft"]) == 5 and bool(p["shadow"]["pcss"]), "ultra shadows are the softest, with contact hardening")
	var ssil := best.duplicate()
	ssil["gfx_gi"] = "ssil"
	ssil["gfx_volumetrics"] = "low"
	ssil["gfx_clouds"] = "low"
	p = Lighting.profile(ssil, true)
	check(p["ssil"] and not p["sdfgi"] and int(p["fog_size"]) < 128, "SSIL is the lighter GI; low fog is coarser")
	check(str(p["clouds"]["res"]) == "quarter" and int(p["clouds"]["steps"]) < 20, "low clouds: quarter resolution, fewer steps")
	var off := best.duplicate()
	off["gfx_gi"] = "off"
	off["gfx_volumetrics"] = "off"
	off["gfx_clouds"] = "off"
	off["gfx_shadows"] = "low"
	p = Lighting.profile(off, true)
	check(not p["sdfgi"] and not p["ssil"] and not p["volumetric_fog"] and not p["fog_volumes"] and not bool(p["clouds"]["volumetric"]),
		"everything off: no GI, no volumetric fog, the flat cloud layer")
	check(not bool(p["shadow"]["omni"]) and int(p["shadow"]["atlas"]) <= 2048, "low shadows: small maps, round lamps don't cast them")
	# The compatibility renderer: none of the Forward+ extras, the flat clouds at "low".
	p = Lighting.profile(best, false)
	check(not p["sdfgi"] and not p["fog_volumes"] and str(p["clouds"]["res"]) == "full", "compatibility: no SDFGI or fog volumes, clouds drawn at full size")
	check(not bool(CloudSky.quality("low", false)["volumetric"]), "compatibility at low: the old flat clouds")
	# Missing settings: the defaults, or the low look with the old quality switch off.
	var hq := Settings.high_quality
	Lighting.overrides = {}
	if Settings.get("gfx_gi") == null:
		Settings.high_quality = true
		check(str(Lighting.option("gfx_gi")) == "sdfgi" and str(Lighting.option("gfx_shadows")) == "high", "no Graphics settings yet: the high defaults")
		Settings.high_quality = false
		check(str(Lighting.option("gfx_gi")) == "off" and str(Lighting.option("gfx_volumetrics")) == "off", "with high quality off: the low look")
	Settings.high_quality = hq
	Lighting.overrides = {"gfx_gi": "ssil"}
	check(str(Lighting.option("gfx_gi")) == "ssil", "overrides win")
	Lighting.overrides = {}
	# Every variant of the sky shader compiles (a broken one has no uniforms).
	for setting in ["off", "low", "high"]:
		for fp in [true, false]:
			var sh := CloudSky.make_shader(CloudSky.quality(setting, fp))
			check(sh.get_shader_uniform_list().size() >= 18, "the %s sky shader compiles (%s)" % [setting, "Forward+" if fp else "compatibility"])
	var fog := Shader.new()
	fog.code = Lighting.DUST_SHADER
	check(fog.get_shader_uniform_list().size() == 5, "the dust fog shader compiles")


## Each lamp lights the fog by a sensible amount and casts shadows to suit the quality, and
## only buildings and big fixed things take part in GI.
func _test_lighting_lamps_and_gi() -> void:
	var opts := Lighting.options()
	opts["gfx_shadows"] = "high"
	var high := Lighting.profile(opts, true)
	opts["gfx_shadows"] = "low"
	var low := Lighting.profile(opts, true)
	var omni := OmniLight3D.new()
	omni.shadow_enabled = true
	var spot := SpotLight3D.new()
	var flood := SpotLight3D.new()
	flood.light_volumetric_fog_energy = 2.5
	flood.add_to_group(Daylight.NIGHT_LIGHTS)
	add_child(omni)
	add_child(spot)
	add_child(flood)
	for l in [omni, spot, flood]:
		Lighting.tune_light(l, high)
	check(is_equal_approx(omni.light_volumetric_fog_energy, Lighting.OMNI_FOG) and is_equal_approx(spot.light_volumetric_fog_energy, Lighting.SPOT_FOG),
		"lamps nobody tuned get a sensible glow in the fog")
	check(is_equal_approx(flood.light_volumetric_fog_energy, 2.5) and flood.shadow_enabled, "a tuned floodlight keeps its glow and casts shadows (god rays) at high")
	for l in [omni, spot, flood]:
		Lighting.tune_light(l, low)
	check(not omni.shadow_enabled and not flood.shadow_enabled, "low shadows: the round lamp and floodlight stop casting them")
	for l in [omni, spot, flood]:
		Lighting.tune_light(l, high)
	check(omni.shadow_enabled and is_equal_approx(omni.light_volumetric_fog_energy, Lighting.OMNI_FOG), "and back at high they come back as they were")
	# The headlight looks after itself (its soft flood is tuned for the fog).
	var fx := BikeEffects.new()
	add_child(fx)
	var beam := SpotLight3D.new()
	beam.light_volumetric_fog_energy = 0.0
	fx.add_child(beam)
	Lighting.tune_light(beam, high)
	check(beam.has_meta("lighting_skip") and beam.light_volumetric_fog_energy == 0.0, "a bike's lights are left alone")
	# GI: a building is static, a small part and anything on a moving body are left out.
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 3.0, 0.2)
	wall.mesh = box
	add_child(wall)
	var bolt := MeshInstance3D.new()
	var little := BoxMesh.new()
	little.size = Vector3(0.1, 0.1, 0.1)
	bolt.mesh = little
	add_child(bolt)
	var body := CharacterBody3D.new()
	add_child(body)
	var big_on_body := MeshInstance3D.new()
	big_on_body.mesh = box
	body.add_child(big_on_body)
	var dust := CPUParticles3D.new()
	add_child(dust)
	check(Lighting.gi_mode_for(wall) == GeometryInstance3D.GI_MODE_STATIC, "walls bounce light (static GI)")
	check(Lighting.gi_mode_for(bolt) == GeometryInstance3D.GI_MODE_DISABLED and Lighting.gi_mode_for(big_on_body) == GeometryInstance3D.GI_MODE_DISABLED
		and Lighting.gi_mode_for(dust) == GeometryInstance3D.GI_MODE_DISABLED, "small props, moving things and particles stay out of GI")
	# Eye adaptation: a dark room opens your eyes up more than a lit one; outdoors is as is.
	check(Lighting.eye_target("", false, 0.0) == 1.0 and Lighting.eye_target("shed", false, 0.0) > Lighting.eye_target("shed", true, 0.0),
		"walking into a dark shed your eyes adjust more than into a lit one")
	check(Lighting.eye_target("shed", true, 1.0) < 1.0, "at night the lamps are bright after the dark")
	for n in [omni, spot, flood, fx, wall, bolt, body, dust]:
		n.queue_free()


## The cloud sky follows the weather: more and heavier cloud from clear to cloudy to rain, lit
## by the moon at night; the cloud setting swaps the shader.
func _test_lighting_clouds() -> void:
	var kept := [Settings.weather, Settings.weather_now, Settings.day_night_cycle]
	Settings.day_night_cycle = false
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var dl := Daylight.new()
	add_child(dl)
	var w := Weather.new()
	add_child(w)
	dl.setup(env, sun)
	var covers := {}
	for st in ["clear", "cloudy", "rain"]:
		Settings.weather = st
		w.change_to(st, true)
		dl.set_time(12.0)
		covers[st] = float(dl._sky_mat.get_shader_parameter("cloud_cover"))
	check(covers["clear"] < covers["cloudy"] and covers["cloudy"] < covers["rain"], "cloud cover grows from clear to cloudy to rain (%s)" % [covers])
	check(float(dl._sky_mat.get_shader_parameter("cloud_rain")) == 1.0, "rain clouds are heavy and dark")
	var wind: Vector2 = dl._sky_mat.get_shader_parameter("wind")
	check(wind.length() > CloudSky.wind_for(0.0).length(), "and the wind blows them faster")
	var lit: Vector3 = dl._sky_mat.get_shader_parameter("cloud_light_dir")
	check(lit.is_equal_approx(dl.sun_dir), "by day the sun lights the clouds")
	dl.set_time(0.5)
	lit = dl._sky_mat.get_shader_parameter("cloud_light_dir")
	check(not lit.is_equal_approx(dl.sun_dir) and lit.y > 0.0, "at night the moon does")
	# Changing the setting swaps the shader, and back.
	dl.set_cloud_quality("off")
	check(not dl._sky_mat.shader.code.contains("#define VOLUMETRIC"), "clouds off: the flat layer")
	dl.set_cloud_quality("high")
	check(dl._sky_mat.shader.code.contains("#define VOLUMETRIC") == bool(CloudSky.quality("high", Lighting.forward_plus())["volumetric"]),
		"clouds high: raymarched")
	check(dl._sky_mat.get_shader_parameter("cloud_noise") != null, "the noise survives the swap")
	Settings.weather = kept[0]
	Settings.weather_now = kept[1]
	Settings.day_night_cycle = kept[2]
	w.queue_free()
	dl.queue_free()
	sun.queue_free()
	await get_tree().process_frame


## In a running shed: the World's Lighting sets the environment up, re-applies when the settings
## change (any mix, without errors), fills the shed with dust (Forward+), the paint shop fills
## with overspray, and your eyes adjust going into a dark shed.
func _test_lighting_session() -> void:
	SaveGame.slot_override = "test_lighting"
	SaveGame.delete_slot("test_lighting")
	var kept_cycle := Settings.day_night_cycle
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	await get_tree().process_frame
	var lt: Lighting = main.world.lighting
	check(lt != null and Lighting.current == lt, "the world has its lighting")
	var env: Environment = lt.env
	var combos := [
		{"gfx_gi": "sdfgi", "gfx_volumetrics": "high", "gfx_clouds": "high", "gfx_shadows": "ultra", "gfx_glow": true, "gfx_ssr": true},
		{"gfx_gi": "ssil", "gfx_volumetrics": "low", "gfx_clouds": "low", "gfx_shadows": "medium", "gfx_glow": false, "gfx_ssr": false},
		{"gfx_gi": "off", "gfx_volumetrics": "off", "gfx_clouds": "off", "gfx_shadows": "low", "gfx_glow": true, "gfx_ssr": true},
	]
	var fp := Lighting.forward_plus()
	for c in combos:
		Lighting.overrides = c
		lt.apply()
		await get_tree().process_frame
		check(env.sdfgi_enabled == (fp and c["gfx_gi"] == "sdfgi") and env.ssil_enabled == (fp and c["gfx_gi"] == "ssil")
			and env.volumetric_fog_enabled == (c["gfx_volumetrics"] != "off") and env.glow_enabled == c["gfx_glow"] and env.ssr_enabled == c["gfx_ssr"],
			"settings %s/%s/%s reach the environment" % [c["gfx_gi"], c["gfx_volumetrics"], c["gfx_shadows"]])
		check(is_instance_valid(lt.dust) == (fp and c["gfx_volumetrics"] != "off"), "the shed's dust is there only with volumetric fog on Forward+")
		var sky_q: Dictionary = main.world.daylight.cloud_quality()
		check(bool(sky_q["volumetric"]) == bool(CloudSky.quality(str(c["gfx_clouds"]), fp)["volumetric"]), "the sky follows the cloud setting")
		var sun: DirectionalLight3D = lt.sun
		check(is_equal_approx(sun.directional_shadow_max_distance, float(Lighting.SHADOWS[c["gfx_shadows"]]["distance"])),
			"the sun's shadows reach as far as the setting says")
	# The polling notices a change without any signal.
	Lighting.overrides = combos[0]
	await get_tree().create_timer(0.6).timeout
	check(env.sdfgi_enabled == fp, "a settings change is picked up by itself")
	# Every lamp in the shed has been tuned.
	var tuned := 0
	for l in lt._lights:
		if is_instance_valid(l) and (l.has_meta("lighting_orig") or l.has_meta("lighting_skip")):
			tuned += 1
	check(lt._lights.size() > 10 and tuned == lt._lights.size(), "every lamp is tuned (%d)" % tuned)
	# Eyes adjusting: into the shed with the lights off by day.
	Settings.day_night_cycle = false
	main.world.daylight.set_time(12.0)
	Shed.request({"a": "lights", "room": "", "on": false})
	main.walker.place(Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.1, 0.0)))
	for i in 5:
		await get_tree().process_frame
	var early := lt.adapt
	for i in 60:
		await get_tree().process_frame
	check(lt.adapt > early and lt.adapt > 1.05, "in the dark shed your eyes slowly open up (%.2f to %.2f)" % [early, lt.adapt])
	Shed.request({"a": "lights", "room": "", "on": true})
	# Overspray: build it up as if someone were spraying in the paint shop.
	if is_instance_valid(lt.overspray):
		lt.overspray_level = 0.8
		lt._update_overspray(0.0)
		check(lt.overspray.visible and float((lt.overspray.material as ShaderMaterial).get_shader_parameter("density")) > 0.0, "spraying fills the paint shop with haze")
		lt._update_overspray(30.0)
		check(lt.overspray_level < 0.8, "and it clears again")
	Lighting.overrides = {}
	lt.apply()
	Settings.day_night_cycle = kept_cycle
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	SaveGame.delete_slot("test_lighting")
	SaveGame.slot_override = ""


## Every player's start spot in the shed has room to walk: forward and back from each of the
## spots a co-op player can be given, nothing pins them in place.
func _test_walker_spawns() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var stuck := []
	for i in Net.MAX_PLAYERS:
		main.walker.place(Workshop.walker_spawn(i))
		for f in 5:
			await get_tree().physics_frame
		var span := AABB(main.walker.global_position, Vector3.ZERO)
		for dir in ["move_forward", "move_back"]:
			Input.action_press(dir)
			for f in 45:
				await get_tree().physics_frame
				span = span.expand(main.walker.global_position)
			Input.action_release(dir)
		if span.size.length() < 1.0:
			stuck.append("%d at %s (%.2f m)" % [i, Workshop.walker_spawn(i).origin, span.size.length()])
	check(stuck.is_empty(), "every start spot in the shed has room to walk %s" % str(stuck))
	main.queue_free()
	await get_tree().process_frame


## Strength of a loop at `hz` (a Goertzel filter over the whole loop).
func _tone(x: PackedFloat32Array, hz: float) -> float:
	var w := TAU * hz / EngineSynth.RATE
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s0 := v + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(maxf(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) / x.size()


func _rms(x: PackedFloat32Array) -> float:
	var t := 0.0
	for v in x:
		t += v * v
	return sqrt(t / maxf(x.size(), 1))


## Strength of each order of the engine cycle (k times the cycle rate), k = 1..count.
func _orders(spec: Dictionary, x: PackedFloat32Array, rpm: float, count: int) -> PackedFloat32Array:
	var cycle_hz := rpm / 60.0 * 360.0 / EngineSynth.cycle_degrees(spec)
	var out := PackedFloat32Array()
	for k in range(1, count + 1):
		out.append(_tone(x, cycle_hz * k))
	return out


func _test_engine_firing() -> void:
	var specs := {
		"single": EngineSynth.make_spec("single", 1, 450.0, {"idle": 1500.0, "redline": 11000.0}),
		"twin 360": EngineSynth.make_spec("twin", 2, 750.0, {"idle": 1050.0, "redline": 7700.0}),
		"parallel 270": EngineSynth.make_spec("parallel", 2, 700.0, {"idle": 1300.0, "redline": 9500.0}),
		"V-twin": EngineSynth.make_spec("vtwin", 2, 1100.0, {"idle": 1000.0, "redline": 8100.0}),
		"boxer": EngineSynth.make_spec("boxer", 2, 1200.0, {"idle": 950.0, "redline": 7900.0}),
		"triple": EngineSynth.make_spec("triple", 3, 850.0, {"idle": 1250.0, "redline": 10500.0}),
		"inline four": EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0}),
		"crossplane four": EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0, "crank": "crossplane"}),
		"two-stroke single": EngineSynth.make_spec("2stroke", 1, 125.0, {"idle": 1450.0, "redline": 14600.0, "peak": 11250.0}),
		"two-stroke triple": EngineSynth.make_spec("2stroke", 3, 750.0, {"idle": 1050.0, "redline": 10600.0, "peak": 8150.0}),
	}
	var even := ["single", "twin 360", "boxer", "triple", "inline four", "two-stroke single", "two-stroke triple"]
	var profiles := {}
	var offbeat := {}
	for name in specs:
		var spec: Dictionary = specs[name]
		var rpm := EngineSynth.loop_rpm(spec, 5000.0)
		var x := EngineSynth.render_loop(spec, "ex_on", rpm)
		var events := EngineSynth.firing_events(spec).size()
		var orders := _orders(spec, x, rpm, 4 * events)
		check(_rms(x) > 0.01, "a %s makes an audible exhaust note (rms %.3f)" % [name, _rms(x)])
		if name in even:
			# Evenly spaced firings: the note is the firing rate, rpm x cylinders / 2 (x cylinders on a two-stroke).
			var best := 0
			for k in orders.size():
				if orders[k] > orders[best]:
					best = k
			var fire_hz := EngineSynth.firing_hz(spec, rpm)
			var expect: float = rpm / 60.0 * spec["cylinders"] * (1.0 if EngineSynth.is_two_stroke(spec) else 0.5)
			check((best + 1) % events == 0 and absf(fire_hz - expect) < 0.01,
				"a %s's strongest note is a harmonic of its firing rate, %.0f Hz at %.0f rpm (order %d, %d firings a cycle)" % [name, fire_hz, rpm, best + 1, events])
		# Its spectral shape: the energy in each octave band up to 8 kHz, in dB of the whole.
		var cycle_hz := rpm / 60.0 * 360.0 / EngineSynth.cycle_degrees(spec)
		var bands := PackedFloat32Array()
		bands.resize(7)
		var order := 1
		while order * cycle_hz < 8000.0:
			var hz := order * cycle_hz
			var band := clampi(int(log(hz / 62.5) / log(2.0)), 0, 6)
			var t := _tone(x, hz)
			bands[band] += t * t
			order += 1 if hz < 1000.0 else 3
		var whole := 0.0
		for v in bands:
			whole += v
		for i in bands.size():
			bands[i] = 10.0 * log(maxf(bands[i] / maxf(whole, 1e-12), 1e-7)) / log(10.0)
		# And its rhythm: the first 16 orders of the cycle, in dB of the strongest.
		var top := 0.0
		for v in orders:
			top = maxf(top, v)
		for q in mini(16, orders.size()):
			bands.append(20.0 * log(maxf(orders[q] / maxf(top, 1e-12), 1e-4)) / log(10.0))
		profiles[name] = bands
		# Off-beat engines have strong in-between orders; even ones barely any.
		var on_beat := 0.0
		var off_beat := 0.0
		for k in orders.size():
			if (k + 1) % events == 0:
				on_beat += orders[k] * orders[k]
			else:
				off_beat += orders[k] * orders[k]
		offbeat[name] = off_beat / maxf(on_beat, 1e-12)
	check(offbeat["parallel 270"] > 4.0 * offbeat["twin 360"],
		"a 270 degree twin lopes where a 360 twin is even (off-beat %.2f vs %.2f)" % [offbeat["parallel 270"], offbeat["twin 360"]])
	check(offbeat["crossplane four"] > 4.0 * offbeat["inline four"],
		"a crossplane four growls where a flat-plane four screams evenly (off-beat %.2f vs %.2f)" % [offbeat["crossplane four"], offbeat["inline four"]])
	# Every layout sounds different from every other: their spectra don't line up.
	var names: Array = specs.keys()
	var closest := 1000.0
	var pair := ""
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: PackedFloat32Array = profiles[names[i]]
			var b: PackedFloat32Array = profiles[names[j]]
			var diff := 0.0
			for q in mini(a.size(), b.size()):
				diff += absf(clampf(a[q], -40.0, 0.0) - clampf(b[q], -40.0, 0.0)) / mini(a.size(), b.size())
			if diff < closest:
				closest = diff
				pair = "%s / %s" % [names[i], names[j]]
	check(closest > 1.5, "every engine layout has its own spectrum and rhythm (closest pair %s, %.1f dB apart per band)" % [pair, closest])
	# A two-stroke comes on the pipe: much stronger in its powerband than below it.
	var two: Dictionary = specs["two-stroke single"]
	var below := EngineSynth.render_loop(two, "ex_on", EngineSynth.loop_rpm(two, two["peak"] * 0.55))
	var on_pipe := EngineSynth.render_loop(two, "ex_on", EngineSynth.loop_rpm(two, two["peak"]))
	check(_rms(on_pipe) > 1.4 * _rms(below), "a two-stroke swells on the pipe (rms %.3f in the powerband, %.3f below)" % [_rms(on_pipe), _rms(below)])
	# Loud pipes are louder and brighter than a stock can.
	var stock := EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0, "exhaust": "stock"})
	var straight := EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0, "exhaust": "straight"})
	var rs := EngineSynth.render_loop(stock, "ex_on", 11000.0)
	var rr := EngineSynth.render_loop(straight, "ex_on", 11000.0)
	check(_rms(rr) > 1.5 * _rms(rs), "a straight pipe is louder than the stock can (%.3f vs %.3f)" % [_rms(rr), _rms(rs)])
	check(_tone(rr, 3000.0) > 2.0 * _tone(rs, 3000.0), "and rasps where the stock can is muffled")
	# On the throttle it barks; off it, the overrun is quieter.
	var off := EngineSynth.render_loop(straight, "ex_off", 11000.0)
	check(_rms(rr) > 2.0 * _rms(off), "on the throttle is louder than the overrun (%.3f vs %.3f)" % [_rms(rr), _rms(off)])
	# Loops repeat without a click at the seam.
	var seam_ok := true
	for layer in EngineSynth.LAYERS:
		var x := EngineSynth.render_loop(specs["triple"], layer, 4000.0)
		var step := 0.0
		for i in range(1, x.size()):
			step += absf(x[i] - x[i - 1])
		step /= x.size()
		seam_ok = seam_ok and absf(x[0] - x[x.size() - 1]) < 6.0 * step + 0.002
	check(seam_ok, "the loops join up seamlessly")
	# The CPU budget: baking runs on a worker thread, but it should still be quick.
	var t0 := Time.get_ticks_usec()
	var made := 0
	for layer in EngineSynth.LAYERS:
		made += EngineSynth.render_loop(specs["inline four"], layer, 9000.0).size()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var per_second := ms / (made / float(EngineSynth.RATE))
	check(per_second < 150.0, "one second of engine sound bakes in %.0f ms (budget 150)" % per_second)


func _test_engine_bank() -> void:
	# The recipe comes from the parts fitted.
	var race := EngineSynth.spec_from_build(BikeBuild.new({"engine": "four_1000", "exhaust": "titanium_race", "gearbox": "six_race_quickshift"}))
	check(race["exhaust"] == "race" and race["shift"] == "slick" and race["quickshifter"] and race["dry_clutch"] and race["crank"] == "crossplane",
		"a race build: race exhaust, slick quickshifter, dry clutch, crossplane crank (%s)" % str([race["exhaust"], race["shift"], race["crank"]]))
	var sport := EngineSynth.spec_from_build(BikeBuild.new({"gearbox": "six_close", "exhaust": "slip_on"}))
	var old := EngineSynth.spec_from_build(BikeBuild.new({"gearbox": "four_vintage", "exhaust": "stock_muffler"}))
	var pipe := EngineSynth.spec_from_build(BikeBuild.new({"exhaust": "straight_pipe"}))
	check(sport["shift"] == "click" and not sport["quickshifter"] and old["shift"] == "clunk",
		"a sports box clicks, an old box clunks (%s, %s)" % [sport["shift"], old["shift"]])
	check(old["exhaust"] == "stock" and sport["exhaust"] == "slip" and pipe["exhaust"] == "straight", "exhausts: stock, slip-on, straight pipe")
	var kicker := EngineSynth.spec_from_build(BikeBuild.new({"engine": "2stroke_125"}))
	check(kicker["kick"] and not race["kick"], "a little two-stroke kick starts; the superbike has a starter")
	# Each gearbox's shift sounds different: slick is short and bright, a clunk long and low.
	var feel := {}
	for kind in ["slick", "click", "clunk"]:
		var x := EngineSynth.render_shift(kind)
		var energy := 0.0
		var late := 0.0
		for i in x.size():
			energy += x[i] * x[i]
			if i > EngineSynth.RATE * 0.03:
				late += x[i] * x[i]
		feel[kind] = {"bright": _tone(x, 5000.0) / maxf(_tone(x, 150.0), 1e-6), "tail": late / maxf(energy, 1e-9)}
	check(feel["slick"]["bright"] > feel["click"]["bright"] and feel["click"]["bright"] > feel["clunk"]["bright"],
		"a quickshifter's shift is crispest, a clunk dullest (%.2f, %.2f, %.2f)" % [feel["slick"]["bright"], feel["click"]["bright"], feel["clunk"]["bright"]])
	check(feel["clunk"]["tail"] > feel["slick"]["tail"], "and the clunk rings on longer")
	# A bank bakes the buckets nearest idle first, and everything else after.
	var spec := EngineSynth.make_spec("triple", 3, 850.0, {"idle": 1250.0, "redline": 10500.0, "exhaust": "full"})
	var bank := EngineBank.new(spec)
	var order := bank.bake_order()
	var nearest := 0
	for i in bank.rpms.size():
		if absf(log(bank.rpms[i] / 1250.0)) < absf(log(bank.rpms[nearest] / 1250.0)):
			nearest = i
	check(order[0] == nearest and bank.rpms[0] < 1250.0 and bank.rpms[-1] > 10500.0,
		"buckets run from below idle (%.0f) past the redline (%.0f), idle baked first" % [bank.rpms[0], bank.rpms[-1]])
	bank.bake_now()
	check(bank.is_baked() and bank.baked.size() == bank.rpms.size() and bank.streams["ex_on"][0] is AudioStreamWAV
		and bank.oneshots.has("pop") and bank.oneshots.has("shift") and bank.oneshots.has("starter"),
		"the bank bakes every loop, the pops, shifts and starter (%d loops in %.0f ms)" % [bank.loop_count(), bank.bake_ms])
	var w := bank.mix_weights(5000.0, 1.0)
	var total := 0.0
	var pitch_ok := true
	for e in w:
		if str(e[0]) == "ex_on":
			total += float(e[2]) * float(e[2])
			pitch_ok = pitch_ok and absf(bank.rpms[e[1]] * float(e[3]) - 5000.0) < 1.0
	check(absf(total - 1.0) < 0.01 and pitch_ok, "loops crossfade at equal power, each pitched to the exact revs")
	var idle_mix := bank.mix_weights(1250.0, 0.0)
	var only_off := true
	for e in idle_mix:
		only_off = only_off and str(e[0]).ends_with("_off")
	check(only_off and not idle_mix.is_empty(), "with the throttle shut only the off-throttle loops play")


func _test_engine_events() -> void:
	var spec := EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0, "exhaust": "straight", "shift": "click"})
	var stock := EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0, "exhaust": "stock"})
	check(EngineSound.pop_rate(spec, 10000.0, 0.2) > 4.0 * EngineSound.pop_rate(stock, 10000.0, 0.2),
		"a straight pipe pops far more than a stock can on the overrun")
	check(EngineSound.pop_rate(spec, 1500.0, 0.2) == 0.0, "nothing pops at tickover")
	var es := EngineSound.new()
	add_child(es)
	es.setup_spec(spec)
	es.bank.bake_now()
	es.running = true
	es.gear = 3
	es.rpm = 10000.0
	es.throttle = 1.0
	for i in 240:
		es._process(1.0 / 60.0)
	check(es.pops == 0, "no pops while the throttle is open")
	check(es.playing_count() >= 2, "the loops play on the throttle (%d players)" % es.playing_count())
	es.throttle = 0.0
	for i in 180:
		es.rpm = lerpf(10000.0, 6000.0, i / 180.0)
		es._process(1.0 / 60.0)
	check(es.pops > 0, "snap the throttle shut at high revs and the pipe pops (%d pops)" % es.pops)
	es.flame.flash(1.0)
	check(es.flame.is_lit(), "a backfire lights the exhaust flame")
	es.rpm = 1300.0
	var before := es.pops
	for i in 240:
		es._process(1.0 / 60.0)
	check(es.pops == before, "and it settles at idle")
	# Shifting: an upshift cuts the sound for a blink; a downshift blips (the bark).
	es.rpm = 9000.0
	es.throttle = 1.0
	es.gear = 4
	es._process(1.0 / 60.0)
	check(es.shifts == 1 and es.last_shift == "click" and es._cut > 0.0, "an upshift clicks and cuts the drive for a moment")
	es.gear = 3
	es.throttle = 0.0
	es._process(1.0 / 60.0)
	check(es.shifts == 2 and es._blip > 0.5, "a downshift blips the throttle")
	es.queue_free()
	var qs := EngineSound.new()
	add_child(qs)
	qs.setup(BikeBuild.new({"engine": "four_1000", "exhaust": "titanium_race", "gearbox": "six_race_quickshift"}))
	qs.running = true
	qs.rpm = 9000.0
	qs.gear = 2
	qs._process(1.0 / 60.0)
	qs.gear = 3
	qs._process(1.0 / 60.0)
	check(qs.last_shift == "slick" and qs._cut > 0.0 and qs._cut < 0.06, "the quickshifter's cut is crisp and short")
	# The runtime cost: one bike's sound updating each frame.
	qs.bank.bake_now()
	var t0 := Time.get_ticks_usec()
	for i in 300:
		qs.rpm = 3000.0 + 20.0 * i
		qs.throttle = float(i % 50) / 50.0
		qs._process(1.0 / 60.0)
	var per := (Time.get_ticks_usec() - t0) / 300.0 / 1000.0
	check(per < 0.5, "a bike's engine sound costs %.3f ms a frame (budget 0.5)" % per)
	qs.queue_free()
	await get_tree().process_frame


func _test_engine_users() -> void:
	# Other players' bikes and the dyno use the same engine sound as your own.
	var build := BikeBuild.new({"engine": "triple_850"})
	var rb := RemoteBike.new()
	add_child(rb)
	rb.setup("Visitor", build, Color.RED)
	check(rb.audio is EngineSound and rb.audio.spec["layout"] == "triple" and rb.audio.infer_cranking,
		"another player's bike plays its own engine sound")
	check(rb.audio.exhaust_at.position.distance_to(rb.model.exhaust_tip()) < 0.01, "from its exhaust")
	rb.queue_free()
	var dyno_src := FileAccess.get_file_as_string("res://scripts/dyno_room.gd")
	check(dyno_src.contains("EngineSound.new()") and not dyno_src.contains("EngineAudio"), "the dyno room uses the same engine sound")
	# The starter: a remote bike guesses it from the revs rising with the engine off.
	var es := EngineSound.new()
	add_child(es)
	es.infer_cranking = true
	es.setup_spec(EngineSynth.make_spec("twin", 2, 750.0, {"idle": 1050.0, "redline": 7700.0}))
	es.bank.bake_now()
	es.running = false
	es.rpm = 0.0
	es._process(1.0 / 60.0)
	es.rpm = 120.0
	es._process(1.0 / 60.0)
	check(es.cranking, "a remote bike's starter is heard when its revs rise with the engine off")
	es.queue_free()
	await get_tree().process_frame


func _test_engine_samples() -> void:
	# Recorded sounds dropped into user://engine_samples/<layout>_<exhaust> replace the synthesised ones.
	var dir := "user://engine_samples/boxer_straight"
	DirAccess.make_dir_recursive_absolute(dir)
	var spec := EngineSynth.make_spec("boxer", 2, 1000.0, {"idle": 1000.0, "redline": 8200.0, "exhaust": "straight"})
	for r in [2000.0, 5000.0]:
		EngineSynth.save_wav(EngineSynth.render_loop(spec, "ex_on", r), dir.path_join("ex_on_%d.wav" % int(r)))
		EngineSynth.save_wav(EngineSynth.render_loop(spec, "ex_off", r), dir.path_join("ex_off_%d.wav" % int(r)))
	EngineSynth.save_wav(EngineSynth.render_pop(spec, 1.0), dir.path_join("pop_1.wav"))
	check(EngineBank.sample_folder(spec) == dir, "a folder of recordings is found for the engine")
	var bank := EngineBank.for_spec(spec)
	bank.bake_now()
	check(bank.recorded and bank.rpms.size() == 2 and absf(bank.rpms[1] - 5000.0) < 1.0 and bank.streams["ex_on"][1] is AudioStreamWAV
		and bank.streams["ex_on"][1].loop_mode == AudioStreamWAV.LOOP_FORWARD, "its loops are used, held at their rpm and looping")
	check(bank.recorded_shots.has("pop") and bank.oneshots["pop"].size() == 1 and bank.oneshots.has("shift"),
		"recorded pops are used; the rest is still synthesised")
	var mix := bank.mix_weights(3500.0, 1.0)
	check(not mix.is_empty(), "and they crossfade like the synthesised loops")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute("user://engine_samples")



## Shed sound: every sound and variant made and audible, variants picked without repeats,
## impacts sounding of their material and surface, footsteps by floor, machine start and stop
## sounds, and the start-up synthesis kept off the main thread and within budget.
func _test_shed_sound_variants() -> void:
	var quiet := []
	var loops_ok := true
	for sound in SfxSynth.all_sounds():
		var list := Sfx.variants(sound)
		for v in list.size():
			var wav: AudioStreamWAV = list[v]
			var loud := 0
			for i in range(0, wav.data.size() - 1, 32):
				loud = maxi(loud, absi(wav.data.decode_s16(i)))
			if wav.data.size() < 1000 or loud < 2000:
				quiet.append("%s#%d (%d)" % [sound, v, loud])
			if (wav.loop_mode == AudioStreamWAV.LOOP_FORWARD) != Sfx.LOOPS.has(sound):
				loops_ok = false
	check(quiet.is_empty(), "every sound and every variant is made and audible (%d sounds) %s" % [SfxSynth.all_sounds().size(), str(quiet)])
	check(loops_ok, "loops loop and one-shots don't")
	check(Sfx.variants("clink").size() >= 4 and Sfx.variants("step_gravel").size() >= 6 and Sfx.variants("impact_metal_concrete").size() >= 4
		and Sfx.variants("pickup").size() >= 4 and Sfx.variants("scrap").size() >= 4, "one-shots come in several variants")
	var same := false
	for sound in ["clink", "step_concrete", "impact_plastic_wood"]:
		var list := Sfx.variants(sound)
		for a in list.size():
			for b in range(a + 1, list.size()):
				same = same or (list[a] as AudioStreamWAV).data == (list[b] as AudioStreamWAV).data
	check(not same, "no two variants are the same")
	# Picked at random, never the same one twice running, and all of them get used.
	var last: AudioStreamWAV = null
	var repeats := 0
	var seen := {}
	for i in 200:
		var s := Sfx.pick("clink")
		if s == last:
			repeats += 1
		last = s
		seen[s] = true
	check(repeats == 0 and seen.size() == Sfx.variants("clink").size(), "a variant never plays twice running (%d repeats, %d of %d used)" % [repeats, seen.size(), Sfx.variants("clink").size()])
	check(Sfx.stream("bell") == Sfx.pick("bell"), "a one-variant sound is always the same stream")
	# Materials and surfaces sound different: brightness (zero crossings) and how long it rings.
	var metal := _zcr(Sfx.stream("impact_metal_concrete"))
	var plastic := _zcr(Sfx.stream("impact_plastic_concrete"))
	var rubber := _zcr(Sfx.stream("impact_rubber_concrete"))
	check(metal > plastic * 1.5 and plastic > rubber, "steel rings brighter than plastic, plastic than a tyre (%d, %d, %d crossings a second)" % [metal, plastic, rubber])
	var on_steel := _tail_energy(Sfx.stream("impact_metal_steel"))
	var on_wood := _tail_energy(Sfx.stream("impact_metal_wood"))
	var on_ground := _tail_energy(Sfx.stream("impact_metal_ground"))
	check(on_steel > on_wood * 1.5 and on_wood > on_ground, "on a steel shelf it rings on; on the bench less; outside it's dead (%.5f, %.5f, %.5f)" % [on_steel, on_wood, on_ground])
	check(_zcr(Sfx.stream("step_gravel")) > _zcr(Sfx.stream("step_concrete")) * 2.0 and _zcr(Sfx.stream("step_carpet")) < _zcr(Sfx.stream("step_tile")),
		"gravel crunches brighter than concrete, carpet is duller than tiles")
	check(Sfx.impact_material("fabric") == "soft" and Sfx.impact_material("electronics") == "plastic" and Sfx.impact_material("rubber") == "rubber"
		and Sfx.impact_material("unknown") == "metal", "parts' materials map onto impact sounds")
	# Start-up: the main thread only sets up buses and starts the worker.
	check(Sfx.ready_ms < 100.0, "starting the sound system takes %.1f ms on the main thread" % Sfx.ready_ms)
	var t0 := Time.get_ticks_msec()
	for sound in ["grinder", "impact_metal_steel", "step_puddle", "amb_out"]:
		for v in SfxSynth.variant_count(sound):
			SfxSynth.make(sound, v)
	var ms := Time.get_ticks_msec() - t0
	check(ms < 8000, "the heaviest sounds synthesise in %d ms" % ms)
	for i in 6000:
		if Sfx.synth_done:
			break
		await get_tree().create_timer(0.05).timeout
	check(Sfx.synth_done, "the worker has made every sound (%.0f ms, %s)" % [Sfx.synth_ms, "from the cache" if Sfx.loaded_from_cache else "synthesised"])
	check(Sfx.synth_ms < 60000.0, "within the start-up budget")
	check(FileAccess.file_exists(Sfx.CACHE_PATH), "and keeps them in a cache for next time")


## Zero crossings a second in the first quarter second: a rough measure of brightness.
func _zcr(wav: AudioStreamWAV) -> int:
	var n := mini(wav.data.size() / 2, int(wav.mix_rate * 0.25))
	var count := 0
	var prev := 0
	for i in n:
		var v := wav.data.decode_s16(i * 2)
		if (v >= 0) != (prev >= 0):
			count += 1
		prev = v
	return int(count / (float(n) / wav.mix_rate))


## Mean square level from 0.3 s to 0.8 s: how long a sound rings on.
func _tail_energy(wav: AudioStreamWAV) -> float:
	var a := int(wav.mix_rate * 0.3)
	var b := mini(wav.data.size() / 2, int(wav.mix_rate * 0.8))
	var sum := 0.0
	for i in range(a, b):
		var v := wav.data.decode_s16(i * 2) / 32768.0
		sum += v * v
	return sum / maxf(b - a, 1.0)


## Room acoustics, routing through walls, footsteps by floor, parts landing by material,
## machines' start and stop sounds and the ambience, in a running shed.
func _test_shed_sound_session() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_sound_test.json"
	DirAccess.remove_absolute(Progress.path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	# Reverb follows the room the listener is in.
	var sizes := {}
	for room in ["shed", "paint", "sales", ""]:
		Sfx.set_listener_room(room)
		sizes[room] = Sfx.room_reverb().room_size
	check(sizes["sales"] > sizes["shed"] and sizes["shed"] > sizes["paint"] and Sfx.room_reverb().wet < 0.1,
		"each room has its own reverb: the showroom's biggest, the paint booth's small, outside almost dry (%s)" % str(sizes))
	var paint_c := Workshop.rooms()["paint"] as Rect2
	var paint_at := Vector3(paint_c.get_center().x, 0.1, paint_c.get_center().y)
	w.place(Transform3D(Basis(), paint_at))
	for i in 10:
		await get_tree().process_frame
	check(Sfx.listener_room == "paint", "walking into the paint shop, you hear its room (%s)" % Sfx.listener_room)
	for i in 120:
		await get_tree().process_frame
	check(absf(Sfx.room_reverb().room_size - float(Sfx.ROOM_PRESETS["paint"]["size"])) < 0.05, "and the reverb eases to the booth's (%.2f)" % Sfx.room_reverb().room_size)
	var shed_at := Workshop.CENTER + Vector3(0.0, 0.1, 0.0)
	check(Sfx.bus_for(paint_at) == "Room" and Sfx.bus_for(shed_at) == "Far" and Sfx.occlusion_db(shed_at) < 0.0 and Sfx.occlusion_db(paint_at) == 0.0,
		"a sound in the shed comes through the wall, muffled and quieter; one in the booth doesn't")
	var outside := SalesOffice.SALES_DOOR + Vector3(0.0, 0.1, 25.0)
	check(Sfx.occlusion_db(outside) <= Sfx.WALL_DB, "outside is through a wall from the paint shop")
	var p := Sfx.play_at("clink", shed_at)
	check(p != null and p.bus == "Far", "a one-shot in another room goes through the far bus")
	# Footsteps by floor.
	check(Sfx.step_surface(shed_at) == "concrete" and Sfx.step_surface(paint_at) == "tile", "concrete in the shed, tiles in the paint shop")
	check(Sfx.step_surface(SalesOffice.at(5.0, 0.0, 0.0) + Vector3.UP * 0.05) == "tile"
		and Sfx.step_surface(Vector3(SalesOffice.office_rect().get_center().x, SalesOffice.MEZZ_Y + 0.05, SalesOffice.office_rect().get_center().y)) == "carpet",
		"the showroom's tiles and the office's carpet")
	Shed.upgrades["epoxy"] = true
	check(Sfx.step_surface(shed_at) == "epoxy", "with the epoxy floor bought, the shed floor sounds of it")
	Shed.upgrades.erase("epoxy")
	var step := Sfx.footstep(paint_at)
	check(step != null and Sfx.variants("step_tile").has(step.stream), "a footstep in the booth is a step on tiles")
	# A part put down sounds of its material and what it lands on.
	var metal_item := 0
	for id in Shed.items:
		if PartsDB.material(str(Shed.items[id]["part"])) == "metal" and not Shed.items[id].get("boxed", false):
			metal_item = id
			break
	var before := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).size()
	Sfx.job_done("drop", {"a": "drop", "xf": Transform3D(Basis(), shed_at)}, metal_item, shed_at)
	Sfx.job_done("set_down", {"a": "set_down", "top": "bench", "xf": Transform3D(Basis(), shed_at)}, metal_item, shed_at)
	var players := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false)
	var on_floor := players.filter(func(q): return Sfx.variants("impact_metal_concrete").has(q.stream))
	var on_bench := players.filter(func(q): return Sfx.variants("impact_metal_wood").has(q.stream))
	check(metal_item != 0 and players.size() >= before + 2 and not on_floor.is_empty() and not on_bench.is_empty(),
		"a steel part dropped on the floor clanks on concrete, set on the bench it knocks on wood")
	# Machines spin up and run down either side of their loop.
	var holder := Node3D.new()
	main.add_child(holder)
	holder.global_position = shed_at
	var loop := Sfx.make_loop_player(holder)
	Sfx.set_loop(loop, "grinder")
	var ups := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(q): return Sfx.variants("grinder_up").has(q.stream))
	check(loop.playing and not ups.is_empty(), "the grinder spins up as it starts")
	Sfx.set_loop(loop, "")
	var downs := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(q): return Sfx.variants("grinder_down").has(q.stream))
	check(not loop.playing and not downs.is_empty(), "and runs down when it stops")
	check(Sfx.WORK_LOOPS["tyre_fit"] == "changer" and Sfx.TOOL_LOOPS["gun"] == "spray_gun" and Sfx.DONE_SOUNDS["tyre_remove"] == "bead_pop",
		"the tyre changer, the spray gun and the bead have their own sounds")
	# The ambience: room tone, lights, outdoors and the compressor.
	for i in 6000:
		if Sfx.synth_done and Sfx.ambience() != null:
			break
		await get_tree().create_timer(0.05).timeout
	var amb: SfxAmbience = Sfx.ambience()
	check(amb != null, "the shed has its ambience")
	if amb:
		amb.kick_compressor()
		check(amb.compressor_on and amb._comp.playing and amb._comp.stream == Sfx.stream("compressor"), "the compressor in the corner kicks in")
		w.place(Transform3D(Basis(), shed_at))
		for i in 90:
			await get_tree().process_frame
		check(amb._tone.playing and amb._hum.playing and amb._wind.playing, "indoors: room tone, the lights' hum and the outdoors muffled through the walls")
		var lp := AudioServer.get_bus_effect(AudioServer.get_bus_index("AmbOut"), 0) as AudioEffectLowPassFilter
		check(lp.cutoff_hz < 5000.0, "the outdoor sounds are muffled indoors (%.0f Hz)" % lp.cutoff_hz)
		check(SfxAmbience.lit("shed") == Shed.lights_on, "the hum follows the shed's lights")
	main._leave()
	main.queue_free()
	await get_tree().create_timer(2.0).timeout
	# One-shots left here with no listener in the world any more never finish: tidy them up.
	for q in find_children("*", "AudioStreamPlayer3D", false, false):
		(q as AudioStreamPlayer3D).stop()
		q.queue_free()
	await get_tree().process_frame
	Sfx.set_listener_room("shed")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


## The parts computer and its Garage upgrades page fit on the screen, and every list in them
## scrolls far enough to show its last entry, in every aisle.
func _test_computer_fits_screen() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var keep := get_window().size
	get_window().size = Vector2i(1920, 1080)
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	var pc: PartsComputer = main.computer
	pc.open()
	await get_tree().process_frame
	var panel: Control = pc.get_child(1).get_child(0)
	var head: Control = panel.get_child(0).get_child(0)
	check(head.size.y < 80.0, "the parts computer's header is one row (%.0f px)" % head.size.y)
	var cut := []
	var off := []
	for sec in PartsComputer.SECTIONS:
		pc._show_section(sec)
		for k in PartsComputer.all_kinds() + PartsComputer.SELL_KINDS:
			if PartsComputer.section_of(k) != sec:
				continue
			pc._show_kind(k)
			await get_tree().process_frame
			if panel.get_global_rect().end.y > vp.end.y + 1.0:
				off.append(k)
			for col in [pc._kinds, pc._variants]:
				if not await _scrolls_to_end(col):
					cut.append(k)
	check(off.is_empty(), "the parts computer stays on the screen in every aisle %s" % str(off))
	check(cut.is_empty(), "every list in the parts computer scrolls to its last entry %s" % str(cut))
	pc.open_upgrades()
	await get_tree().process_frame
	var up: UpgradesPanel = pc.upgrades_panel
	var up_panel: Control = up.get_child(1).get_child(0)
	check(up_panel.get_global_rect().end.y <= vp.end.y + 1.0 and await _scrolls_to_end(up._list),
		"the Garage upgrades page fits and its list scrolls to the end (%s)" % up_panel.get_global_rect())
	pc.close_computer()
	get_window().size = keep
	main.queue_free()
	await get_tree().process_frame


## Scrolls the list's ScrollContainer to the bottom: whether its last entry is then in view.
func _scrolls_to_end(col: Control) -> bool:
	var sc: ScrollContainer = col.get_parent()
	await get_tree().process_frame
	sc.scroll_vertical = 1000000
	await get_tree().process_frame
	await get_tree().process_frame
	var kids: Array = col.get_children().filter(func(c): return not c.is_queued_for_deletion() and c.visible)
	if kids.is_empty():
		return true
	var vis := sc.get_global_rect()
	return (kids[-1] as Control).get_global_rect().end.y <= vis.end.y + 1.0 and vis.end.y <= get_viewport().get_visible_rect().end.y + 1.0


## Garage upgrade options: every finish's choices are sound, buying one keeps the looks picked,
## they can be changed later for a small fee (and only to something new), and they're kept in
## the save. Old saves (no looks) keep the look each finish always had.
func _test_upgrade_options() -> void:
	var sound := true
	for id in GarageUpgrades.OPTIONS:
		sound = sound and GarageUpgrades.exists(id)
		for g in GarageUpgrades.options(id):
			var ids := []
			for c in g["choices"]:
				ids.append(str(c["id"]))
				sound = sound and str(c.get("name", "")) != "" and (str(g["kind"]) != "colour" or c.get("color") is Color)
			sound = sound and ids.has(str(g["default"])) and ids.size() >= 3 and str(g["kind"]) in ["colour", "style"]
			for i in ids.size():
				sound = sound and ids.find(ids[i]) == i
	check(sound, "every option has a default among at least three named choices, no repeats, and swatches for colours")
	for id in ["epoxy", "led", "cladding", "showroom", "signage", "lounge"]:
		check(GarageUpgrades.has_options(id), "the %s has choices" % GarageUpgrades.title(id).to_lower())
	check(not GarageUpgrades.has_options("wing") and GarageUpgrades.options("bays_56").is_empty(), "building work has none")
	check(GarageUpgrades.default_looks("epoxy") == {"colour": "charcoal", "effect": "flake"}, "the epoxy floor is charcoal flake as standard")
	var fx_names := []
	for c in GarageUpgrades._group("epoxy", "effect")["choices"]:
		fx_names.append(str(c["name"]).to_lower())
	check(str(fx_names).contains("flake") and str(fx_names).contains("metallic") and str(fx_names).contains("gloss"), "epoxy comes with flake, metallic and gloss effects")
	check(GarageUpgrades.clean_looks("epoxy", {"colour": "red", "effect": "glitter", "smell": "pine"}) == {"colour": "red", "effect": "flake"},
		"unknown choices fall back to the default, unknown options are dropped")
	check(GarageUpgrades.looks_text("epoxy", {"colour": "red", "effect": "metallic"}) == "Racing red, metallic swirl", "looks read out in words")
	check(GarageUpgrades.restyle_fee("epoxy") >= GarageUpgrades.RESTYLE_MIN and GarageUpgrades.restyle_fee("showroom") <= GarageUpgrades.RESTYLE_MAX
		and GarageUpgrades.restyle_fee("showroom") < GarageUpgrades.price("showroom") / 20, "changing a look later costs a small fee")
	Shed.start_new("Tester", 9)
	var me := Shed.me()
	Shed.request({"a": "garage_money", "value": 100000})
	check(Shed.check(me, {"a": "restyle_upgrade", "id": "epoxy", "looks": {"colour": "red"}}).contains("first"), "nothing to change before it's bought")
	Shed.request({"a": "buy_upgrade", "id": "epoxy", "looks": {"colour": "red", "effect": "metallic"}})
	check(GarageUpgrades.owned("epoxy") and Shed.looks.get("epoxy", {}) == {"colour": "red", "effect": "metallic"}, "bought in racing red with a metallic swirl")
	check(Shed.garage_money == 100000 - GarageUpgrades.price("epoxy"), "picking colours costs nothing extra")
	Shed.request({"a": "buy_upgrade", "id": "led"})
	check(GarageUpgrades.looks_of("led", Shed.looks) == GarageUpgrades.default_looks("led"), "bought with no choices: the standard look")
	check(Shed.check(me, {"a": "restyle_upgrade", "id": "epoxy", "looks": {"colour": "red", "effect": "metallic"}}).contains("already"),
		"changing it to how it is already is refused")
	check(Shed.check(me, {"a": "restyle_upgrade", "id": "wing", "looks": {}}) != "", "building work can't be restyled")
	var before := Shed.garage_money
	Shed.request({"a": "restyle_upgrade", "id": "epoxy", "looks": {"colour": "blue", "effect": "gloss"}})
	check(Shed.looks["epoxy"] == {"colour": "blue", "effect": "gloss"} and Shed.garage_money == before - GarageUpgrades.restyle_fee("epoxy"),
		"changed to blue gloss for %s" % TvChannels.money_text(GarageUpgrades.restyle_fee("epoxy")))
	check(str(Shed.bank).contains("Restyled"), "the fee is in the garage's accounts")
	Shed.request({"a": "garage_money", "value": 0})
	check(Shed.check(me, {"a": "restyle_upgrade", "id": "epoxy", "looks": {"colour": "white"}}).contains("afford"), "no money, no change")
	# Saved and loaded; old saves keep the standard looks.
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.start_new("Tester", 9)
	check(Shed.looks.is_empty(), "a new shed has no looks chosen")
	Shed.load_state(copy, "Tester")
	check(Shed.looks.get("epoxy", {}) == {"colour": "blue", "effect": "gloss"}, "the looks come back with the save")
	copy.erase("looks")
	Shed.load_state(copy, "Tester")
	check(Shed.looks.is_empty() and GarageUpgrades.looks_of("epoxy", Shed.looks) == GarageUpgrades.default_looks("epoxy"),
		"a shed saved before choices keeps the standard looks")
	copy["looks"] = {"epoxy": {"colour": "plaid"}, "showroom": {"floor": "redblack"}, "nope": {}}
	Shed.load_state(copy, "Tester")
	check(Shed.looks.keys() == ["epoxy"] and Shed.looks["epoxy"]["colour"] == "charcoal", "looks for things not built, or not real, are dropped")
	Shed.stop()


## In the game: the looks are drawn on the shed (standard when nothing was chosen), the upgrades
## page shows the choices and a preview, trying one on changes the shed on this screen only and
## comes off when the page closes, and buying or changing one rebuilds it.
func _test_upgrade_options_session() -> void:
	SaveGame.slot_override = "test_upgrade_looks"
	SaveGame.delete_slot("test_upgrade_looks")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	await get_tree().physics_frame
	var ws: Workshop = main.world.workshop
	var floor_m: StandardMaterial3D = ws._mats["floor"]
	var bare := floor_m.albedo_color
	Shed.request({"a": "garage_money", "value": 1000000})
	# Bought with no choices: exactly the look it always had.
	Shed.request({"a": "buy_upgrade", "id": "epoxy"})
	Shed.request({"a": "buy_upgrade", "id": "cladding"})
	await get_tree().process_frame
	check(floor_m.albedo_color.is_equal_approx(Color(0.2, 0.22, 0.25)) and is_equal_approx(floor_m.roughness, 0.12) and is_equal_approx(floor_m.metallic, 0.15),
		"the standard epoxy floor is the charcoal flake it always was")
	check((ws._mats["wall_in"] as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.94, 0.94, 0.95)), "standard cladding is white")
	# The page: choices with swatches, and a preview room.
	main.computer.open()
	main.computer.open_upgrades()
	var page: UpgradesPanel = main.computer.upgrades_panel
	page.show_upgrade("led")
	check(page._swatches.has("tone") and page._swatches["tone"].size() == 4 and page._swatches.has("fx"), "the LED lighting shows its colours and effects")
	check(page._thumb.visible and page._thumb.shown.has("led") and page._thumb.shown.has("epoxy"), "the preview room shows it with what's built")
	var lights_before: Color = (ws._shed_lights[0] as Light3D).light_color
	page.choose("tone", "warm")
	await get_tree().process_frame
	check(page.previewing and WorkshopUpgrades.preview_id == "led" and (ws._shed_lights[0] as Light3D).light_color.is_equal_approx(Color(1.0, 0.85, 0.66)),
		"picking warm white tries it on the shed's lights before it's bought")
	check(not GarageUpgrades.owned("led") and page._buy.text.contains("Warm white"), "nothing is bought yet; Buy says what it buys")
	page.start_peek()
	check(page.peeking and not page._center.visible and page._peek_bar.visible, "See it in the shed hides the page")
	page.stop_peek()
	check(not page.peeking and page._center.visible, "and it comes back")
	page.show_upgrade("wing")
	await get_tree().process_frame
	check(not page.previewing and WorkshopUpgrades.preview_id == "" and (ws._shed_lights[0] as Light3D).light_color.is_equal_approx(lights_before),
		"looking at another upgrade puts the shed back as it is")
	check(not page._thumb_box.visible, "building work has no choices to show")
	# Buy it in the colour picked.
	page.show_upgrade("led")
	page.choose("tone", "warm")
	page.choose("strip", "purple")
	page.choose("fx", "pulse")
	page.buy()
	await get_tree().process_frame
	check(GarageUpgrades.owned("led") and Shed.looks["led"] == {"tone": "warm", "strip": "purple", "fx": "pulse"}, "bought with the choices picked")
	check(ws.upgrades.looks_shown()["led"]["strip"] == "purple" and not ws.upgrades._fx.is_empty(), "the strip is purple and pulses")
	# Changing a built finish.
	page.show_upgrade("epoxy")
	check(page._buy.disabled and page._buy.text.begins_with("Built"), "a built finish says so until new colours are picked")
	page.choose("colour", "green")
	page.choose("effect", "metallic")
	check(not page._buy.disabled and page._buy.text.contains(TvChannels.money_text(GarageUpgrades.restyle_fee("epoxy"))), "then it offers the change for the fee")
	await get_tree().process_frame
	check(floor_m.albedo_color.is_equal_approx(GarageUpgrades.choice("epoxy", "colour", {"colour": "green"})["color"]), "and the floor shows it while picking")
	page.buy()
	await get_tree().process_frame
	check(Shed.looks["epoxy"] == {"colour": "green", "effect": "metallic"} and is_equal_approx(floor_m.metallic, 0.65), "changed: green metallic")
	# The showroom: its styles.
	for id in ["lounge", "showroom"]:
		for need in GarageUpgrades.missing_needs(id, Shed.upgrades):
			Shed.request({"a": "buy_upgrade", "id": need})
		Shed.request({"a": "buy_upgrade", "id": id})
	page.show_upgrade("showroom")
	check(page._swatches.has("floor") and page._swatches.has("ceiling") and page._swatches.has("trim"), "the showroom offers floors, ceilings and trim")
	page.choose("floor", "redblack")
	page.buy()
	await get_tree().process_frame
	var tile := (floor_m.albedo_texture as ImageTexture).get_image() if floor_m.albedo_texture is ImageTexture else null
	check(tile != null and tile.get_pixel(0, 0).r > 0.4 and tile.get_pixel(0, 0).g < 0.2, "the showroom floor is red and black chequer")
	# Closing the page takes any preview off.
	page.choose("trim", "gold")
	check(WorkshopUpgrades.preview_id == "showroom", "trying gold trim")
	main.computer.close_computer()
	await get_tree().process_frame
	check(WorkshopUpgrades.preview_id == "" and ws.upgrades.looks_shown()["showroom"]["trim"] == "chrome", "closing the computer puts the shed back")
	# A shed without choices: the standard looks; no finishes, the bare floor again.
	Shed.looks = {}
	Shed.changed.emit()
	await get_tree().process_frame
	check(ws.upgrades.looks_shown()["led"] == GarageUpgrades.default_looks("led"), "no looks saved: the standard ones")
	Shed.upgrades = {}
	Shed.changed.emit()
	await get_tree().process_frame
	check(floor_m.albedo_color.is_equal_approx(bare), "with no finishes the floor is bare concrete again")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	SaveGame.delete_slot("test_upgrade_looks")
	SaveGame.slot_override = ""
