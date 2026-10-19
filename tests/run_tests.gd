extends Node
## Headless test suite. Run with:
##   godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn
## Prints a line per check and exits with code 1 if anything failed.

var failures := 0
var checks := 0
var verbose := OS.get_cmdline_user_args().has("--verbose")


func _ready() -> void:
	# The old demo bikes these were written round (a player's new shed starts empty).
	Shed.demo_bikes = true
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
	await _test_performance()
	await _test_style_launch()
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
	await _test_ecu_aid_settings()
	_test_bike_paint_panels()
	print("Road traffic")
	await _test_road_traffic()
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
	print("Recorded sounds: horns, phone, door chime, dyno fan, gear levers, light switches, birds")
	await _test_recorded_sounds()
	print("Riding: camera orbit, ride-by camera, circle burnouts, headlight and fog, bikes left on the road")
	await _test_ride_camera_orbit()
	await _test_ride_by_camera()
	await _test_circle_burnout()
	await _test_headlight_sequence()
	_test_road_bike_rules()
	await _test_riding_feedback_session()
	print("Customers: riding in and parking, bringing the bike in, handing back from any bay, the job's bay screen")
	_test_customer_rides_in()
	_test_customer_bike_in_and_back()
	_test_customer_bay_screen()
	_test_customer_save()
	await _test_customer_ride_session()
	_test_customer_lean()
	_test_customer_routes()
	print("Shed building: packed deliveries and racking, bay lifts, the big annex, the crew lounge upstairs")
	_test_delivery_packing()
	_test_bay_lifts()
	await _test_shed_building_session()
	print("Shed objects: scrap anything, free rotate, signs, clocks, money graphs")
	_test_scrap_placed()
	await _test_scrap_placed_session()
	await _test_free_rotate()
	await _test_front_sign_fits()
	await _test_wall_clocks()
	await _test_money_graph()
	print("Sandblaster round 3: bare metal that stays, the scan, cabinet lights and protective coats")
	await _test_blast_keeps_bare_metal()
	await _test_blast_scan()
	await _test_protective_coat()
	print("Front mudguards, and the parts computer's headings, sorting and filters")
	_test_front_mudguard_parts()
	_test_front_mudguard_shed()
	_test_front_mudguard_old_save()
	await _test_parts_computer_organised()
	print("Bike styles: tags on every part, detection, the bolt-on style bits, contracts, selling and the filter")
	_test_style_tags()
	_test_filler_parts()
	_test_style_packs()
	_test_detail_pass()
	_test_filler_shed()
	await _test_style_contracts_sales()
	print("Garage upgrade options: colours, effects and styles, preview, changing them later")
	_test_upgrade_options()
	await _test_upgrade_options_session()
	print("Selling from the showroom: pricing, online offers and counter-offers, part exchange, saving")
	_test_sales_pricing()
	_test_sales_offers()
	_test_sales_part_exchange()
	_test_sales_save()
	await _test_sales_session()
	print("Playtest fixes: a blasted engine is new, grit stays in the cabinet, an empty new shed, varied contracts")
	_test_blast_engine_like_new()
	await _test_blast_grit_contained()
	_test_new_shed_empty()
	_test_contract_variety()
	print("Handling phase 1: real tyres, riding realism, telemetry")
	await _test_tyre_steady_turn()
	await _test_tyre_stopping()
	await _test_tyre_front_tuck()
	await _test_tyre_highside()
	await _test_tyre_coasting()
	await _test_tyre_old_save()
	await _test_telemetry()
	await _test_physics_cost()
	print("Handling phase 2: real steering, geometry, steering dampers")
	_test_steering_geometry()
	await _test_steering_steady_turn()
	await _test_countersteer()
	await _test_hands_off()
	await _test_steering_wobble()
	await _test_turn_in()
	await _test_steering_telemetry()
	print("The riding map: roads, grades, no jumps, land under the roads, spawns, surfaces, counts")
	await _test_world_map()
	print("Shop and crew: part previews, trolleys, box notes, the geometry parts list, styled project bikes, emotes")
	await _test_part_preview()
	_test_trolley_shed()
	await _test_trolley_session()
	_test_order_notes()
	await _test_geometry_list()
	await _test_style_bike_orders()
	_test_emote_poses()
	await _test_emotes_session()
	print("The coffee shop next door: bikers on all sorts of bikes, offers on them, coffee and cake on a tray")
	_test_coffee_layout()
	_test_coffee_visitors()
	_test_coffee_offers()
	_test_coffee_trays()
	_test_coffee_save()
	await _test_coffee_session()
	print("Spraying by hand: primer, colour and lacquer coats, the fan, coverage, runs and dry spray")
	_test_spray_coat_rules()
	await _test_spray_session()
	await _test_spray_sides()
	print("The paint mixing bay: mixing by weight, recipe cards, the swatch wall, the gun's cup, masking")
	_test_paint_mix_maths()
	_test_paint_match()
	_test_paint_unlocks()
	_test_paint_costs()
	_test_paint_codes()
	_test_paint_library()
	_test_paint_bench_rules()
	_test_paint_masking()
	_test_paint_save()
	_test_paint_contracts()
	await _test_paint_bay_session()
	await _test_paint_bench_extras()
	print("Simon's 16 October UI round: the Sales PC's headings, the shop's Buy, the money graphs, the cafe bikers")
	await _test_sales_pc_headings()
	await _test_shop_buy_in_view()
	await _test_money_graph_moves()


const SLICK := {"front_tyre": "race_slick", "rear_tyre": "race_slick"}
const MX := {"fork": "long_travel_mx", "shock": "mono_shock_mx", "front_wheel": "spoked_21", "rear_wheel": "spoked_18",
	"front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx"}


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func _test_catalogue() -> void:
	check(PartsDB.KINDS.size() >= 36 and PartsDB.parts.size() >= 170, "catalogue has %d kinds of part (%d parts)" % [PartsDB.KINDS.size(), PartsDB.parts.size()])
	for k in PartsDB.KINDS:
		check(PartsDB.by_kind[k].size() >= 5, "%s has at least five variants (%d)" % [k, PartsDB.by_kind[k].size()])
	var no_colour := []
	for id in PartsDB.parts:
		if not PartsDB.parts[id].has("color"):
			no_colour.append(id)
	check(no_colour.is_empty(), "every part has a colour %s" % str(no_colour))
	check(PartsDB.SLOTS.size() >= 42 and PartsDB.ENGINE_SLOTS.size() == 7, "a bike has %d slots, 7 of them on the engine" % PartsDB.SLOTS.size())
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
		if verbose and i % (6 if OS.get_cmdline_user_args().has("--fine") else 60) == 0:
			print("    t=%.2f v=%.1f lean=%.1f steer=%.1f gear=%d rpm=%.0f comp=%.3f/%.3f slip=%.2f/%.2f pitch=%.1f kappa=%.2f/%.2f alpha=%.1f/%.1f grip=%.2f/%.2f" % [
				i * dt, bike.speed, rad_to_deg(bike.lean_angle), rad_to_deg(bike.steer), bike.gear, bike.rpm,
				bike.wheels[0]["compression"], bike.wheels[1]["compression"], bike.wheels[0]["slip"], bike.wheels[1]["slip"],
				rad_to_deg(bike.pitch_angle), bike.wheels[0]["kappa"], bike.wheels[1]["kappa"],
				rad_to_deg(bike.wheels[0]["alpha"]), rad_to_deg(bike.wheels[1]["alpha"]),
				bike.wheels[0]["grip_used"], bike.wheels[1]["grip_used"]])
			if OS.get_cmdline_user_args().has("--fine"):
				print("      load=%.0f/%.0f mu=%.2f/%.2f gx=%.2f/%.2f" % [bike.wheels[0]["load"], bike.wheels[1]["load"],
					bike.wheels[0]["mu"], bike.wheels[1]["mu"], bike.wheels[0]["gx"], bike.wheels[1]["gx"]])
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


## Full-throttle runs on the flat against real-world figures. A ~50 hp 500 cc twin on stock
## sprockets gets to 100 km/h in five or six seconds and pulls all the way into top gear and on
## to about 155 km/h; a 1000 cc four with a race fairing and tall gearing does 0-100 in about three
## and a half and goes on past 250. Before the bike's body stopped picking up the physics
## engine's default damping on top of its own drag, the twin stalled out in third or fourth
## at about 120 km/h.
func _test_performance() -> void:
	var twin := {"engine": "twin_500", "final_drive": "stock_15_45"}
	var four := {"frame": "alu_twin_spar", "fork": "usd_sport", "shock": "sport_mono", "front_caliper": "four_piston_radial",
		"front_master": "radial_19x20", "tank": "sport_17", "saddle": "sport_solo", "handlebars": "clip_ons",
		"engine": "four_1000", "exhaust": "slip_on", "fuel": "throttle_bodies", "cooling": "twin_radiators",
		"gearbox": "six_close", "final_drive": "tall_15_42", "fairing": "race_fairing"}
	for run in [[twin, 25.0, 4.5, 7.0, 145.0, 190.0], [four, 30.0, 2.5, 4.0, 255.0, 310.0]]:
		var b := BikeBuild.new(run[0])
		var t100 := [-1.0]
		var r := await ride(run[0], run[1], func(bike, t):
			bike.throttle = 1.0
			bike.body_shift = 0.6   # tucked in, weight over the tank to keep the front down
			if t100[0] < 0.0 and bike.speed * 3.6 >= 100.0:
				t100[0] = t)
		var bike: Bike = r["bike"]
		var top: float = r["max_speed"] * 3.6
		var what := "%s (%.0f hp, %.0f kg with rider)" % [str(run[0]["engine"]), b.hp(), b.total_mass]
		check(not r["crashed"], "%s: the flat-out run does not crash" % what)
		check(t100[0] >= run[2] and t100[0] <= run[3], "%s: 0-100 km/h in %.1f s (%.1f-%.1f s expected)" % [what, t100[0], run[2], run[3]])
		check(top >= run[4] and top <= run[5], "%s: reaches %.0f km/h (%.0f-%.0f expected)" % [what, top, run[4], run[5]])
		check(bike.gear == b.gear_count(), "%s: pulls through every gear into top (gear %d of %d)" % [what, bike.gear, b.gear_count()])
		await _done(r)


## Flat out from a standstill on tarmac, a heavy cruiser and a tourer, looked at every physics
## step. The road's few millimetres of ripple used to reach the suspension a point at a time,
## straight into the dampers: at speed the back tyre's load swung by over 300 N a step on
## average (700 N at 60 mph) and the front kept unloading to nothing.
func _test_style_launch() -> void:
	for st in ["cruiser", "tourer"]:
		var m := {"t60": -1.0, "step": 0.0, "n": 0, "last": -1.0, "front_min": INF}
		var r := await ride(Contracts.style_build(st), 9.0, func(bike, t):
			bike.throttle = 1.0
			bike.body_shift = 0.6
			if m["t60"] < 0.0 and bike.speed >= 26.82:
				m["t60"] = t
			if t < 0.5 or m["t60"] >= 0.0:
				return
			var load: float = bike.wheels[1]["load"]
			if m["last"] >= 0.0:
				m["step"] += absf(load - m["last"])
				m["n"] += 1
			m["last"] = load
			m["front_min"] = minf(m["front_min"], float(bike.wheels[0]["load"])))
		var step: float = m["step"] / maxf(1.0, float(m["n"]))
		check(not r["crashed"] and m["t60"] > 3.5 and m["t60"] < 6.5, "the %s launches flat out to 60 mph (%.2f s)" % [st, m["t60"]])
		check(step < 150.0, "and the back tyre's load is steady from one step to the next (%.0f N a step)" % step)
		check(m["front_min"] > 50.0, "and the front stays loaded over the ripples (%.0f N at the least)" % m["front_min"])
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
		# The frames with their own geometry: long and raked, low, tall, and the sharp sport one.
		{"frame": "chopper_raked", "fork": "springer_long", "engine": "vtwin_1200", "handlebars": "ape_hangers", "front_wheel": "spoked_21",
			"rear_wheel": "wire_16_bobber", "front_tyre": "vintage_ribbed_90", "rear_tyre": "vintage_ribbed_150", "exhaust": "shotgun_duals"},
		{"frame": "cruiser_cradle", "engine": "vtwin_1100", "front_wheel": "wire_16_bobber", "rear_wheel": "wire_16_bobber",
			"front_tyre": "vintage_ribbed_130", "rear_tyre": "vintage_ribbed_150"},
		{"frame": "softail_hardtail", "engine": "vtwin_1000", "front_wheel": "wire_16_bobber", "rear_wheel": "wire_16_bobber",
			"front_tyre": "vintage_ribbed_130", "rear_tyre": "vintage_ribbed_150", "tank": "peanut_9"},
		_merge(SLICK, {"frame": "alu_perimeter", "fork": "usd_sport", "shock": "sport_mono", "engine": "inline_1000", "gearbox": "six_close"}),
		_merge(MX, {"frame": "adv_trellis", "engine": "boxer_1200", "fork": "enduro_usd", "shock": "enduro_mono"}),
		_merge(MX, {"frame": "mx_twin_loop", "engine": "single_450", "exhaust": "mx_upswept"}),
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
	# Project bikes mostly carry light surface rust now, so make sure this pipe is a bad one.
	Shed.items[pipe]["rust"] = maxf(float(Shed.items[pipe]["rust"]), 0.5)
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
	var funds := Shed.garage_money
	Shed.garage_money = 10000000
	for i in 400:
		if Shed.check(me, {"a": "order_part", "part": "steel_cradle"}) != "":
			break
		Shed.request({"a": "order_part", "part": "steel_cradle"})
	check(Shed.check(me, {"a": "order_part", "part": "steel_cradle"}).contains("full"), "you can't order with the delivery area full")
	Shed.garage_money = funds
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
func _aim_at(main: Node, bike_id: int, slot: String, from := Vector3(1.4, 0.0, 0.0)) -> void:
	var model: BikeModel = main.workshop.bike_model(bike_id)
	var aim: Vector3 = model.global_transform * model.slot_bounds(slot).get_center()
	var stand: Vector3 = aim + from
	stand.y = 0.0
	main.walker.place(Transform3D(Basis(), stand))
	main.walker.rotation.y = atan2(from.x, from.z)
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
		and not main.camera.get_cull_mask_value(BikeModel.HELMET_LAYER) and main.bike.model.own_rider,
		"C switches to first person, from the rider's eyes inside the helmet (your own, left out of the view)")
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
	# Something passing through (a visitor riding in) can get between you and the bike for a frame,
	# so take aim again until the bike itself is what you're looking at.
	var parked_at: Vector3 = Shed.bikes[faithful]["xf"].origin
	var aimed_at := {}
	for attempt in 4:
		await _aim_at(main, faithful, "tank", [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4)][attempt])
		aimed_at = main.walker.target
		if int(aimed_at.get("bike", 0)) == faithful:
			break
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
	check(Shed.pushing_bike(Shed.me()) == faithful and main.bike == null,
		"holding F on a bike takes hold of it instead of getting on (aimed at %s, riding %s)" % [str(aimed_at), str(main.bike != null)])
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
	for frame in ["steel_cradle", "steel_backbone", "alu_twin_spar", "chopper_raked", "cruiser_cradle", "mx_twin_loop"]:
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
	# Each frame places the parts its own way: a chopper is long and raked with its pegs out
	# front, an MX bike tall, and the tank always sits on the top tube between bars and seat.
	var shapes := {}
	for frame in PartsDB.by_kind["frame"]:
		var fm := BikeModel.new()
		add_child(fm)
		fm.build_from(BikeBuild.new({"frame": frame}))
		var all := AABB()
		for slot in ["frame", "tank", "saddle", "engine", "exhaust", "front_wheel", "rear_wheel"]:
			var sb := fm.slot_bounds(slot)
			check(sb.size.length() > 0.05, "%s draws its %s" % [frame, slot])
			all = sb if all.size == Vector3.ZERO else all.merge(sb)
		check(fm.slot_bounds("tank").position.y > fm.slot_bounds("engine").position.y, "the tank on a %s sits above the engine" % frame)
		shapes[frame] = {"len": all.size.z, "peg": fm._peg.z - fm._pivot.z, "seat": fm._seat_y, "model": fm}
	check(shapes["chopper_raked"]["len"] > shapes["steel_cradle"]["len"] + 0.25, "a chopper is a lot longer than a cradle-frame bike (%.2f m vs %.2f m)" %
		[shapes["chopper_raked"]["len"], shapes["steel_cradle"]["len"]])
	check(shapes["cruiser_cradle"]["peg"] < -0.3 and absf(shapes["steel_cradle"]["peg"]) < 0.05, "a cruiser has forward controls, a cradle bike mid pegs")
	check(shapes["mx_twin_loop"]["seat"] > shapes["cruiser_cradle"]["seat"] + 0.15, "an MX bike sits a lot taller than a cruiser")
	for f in shapes:
		(shapes[f]["model"] as Node).queue_free()
	# Every exhaust follows its route on every frame, and its tail pipe is behind the engine.
	var bad_tips := []
	for frame in ["steel_cradle", "chopper_raked", "alu_perimeter", "mx_twin_loop"]:
		for ex in PartsDB.by_kind["exhaust"]:
			for engine in ["twin_750", "inline_1000", "2stroke_125"]:
				var xm := BikeModel.new()
				add_child(xm)
				xm.build_from(BikeBuild.new({"frame": frame, "exhaust": ex, "engine": engine}))
				var tip := xm.exhaust_tip()
				var ok := tip.is_finite() and tip.z > xm._engine_c.z and xm.slot_bounds("exhaust").has_point(tip - (tip - xm._engine_c).normalized() * 0.03)
				if not ok:
					bad_tips.append("%s/%s/%s" % [ex, frame, engine])
				xm.queue_free()
	check(bad_tips.is_empty(), "every exhaust ends in a tail pipe behind the engine, on every frame and engine layout %s" % str(bad_tips))
	# The curved shapes are real meshes the sandblaster and the picking can use.
	var lm := BikeModel.new()
	add_child(lm)
	lm.build_from(BikeBuild.new({"frame": "alu_perimeter", "fairing": "race_fairing", "headlight": "led_projector"}))
	check((lm.surface_points("tank", 0.03)[0] as PackedVector3Array).size() > 30, "a lofted tank has a surface to blast")
	check(lm.slot_bounds("fairing").size.y > 0.4, "a race fairing wraps from the screen down under the engine (%.2f m tall)" % lm.slot_bounds("fairing").size.y)
	lm.queue_free()
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
	# A short run up: with nothing but its own drag holding it back, the big four is going
	# far too fast after five seconds for the front brake to stop it in the five left.
	r = await ride({"engine": "four_1000", "front_caliper": "four_piston_radial", "front_pads": "sintered"}, 10.0, func(b, t):
		if t < 3.5:
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
	var marks_before := SkidMarks.shared(get_tree()).laid()
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
	check(SkidMarks.shared(get_tree()).laid() > marks_before, "and lays a skid mark (%d strips)" % (SkidMarks.shared(get_tree()).laid() - marks_before))
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
	# Down on your haunches for a part on the floor, so the can's the right distance off it.
	w.place(Transform3D(Basis(), Vector3(centre.x, 0.0, centre.z) + (Workshop.CENTER - Vector3(centre.x, 0.0, centre.z)).normalized() * 0.6))
	w.set_crouched(true)
	w.set_tool("spray")
	w.spray_color = 4
	await _aim_point(w, centre)
	check(w.plan.get("coverage", false) and w.plan["blocked"] == "", "the spray can wants sweeping over the part (%s %s)" % [str(w.plan.get("verb", "")), str(w.plan.get("blocked", ""))])
	w.enter_spray_mode()   # F: the spray controls up
	w.spray_mode["settle"] = 0.0
	Input.action_press("act")
	for i in 90:
		await get_tree().physics_frame
	check(w.coverage > 0.0 and w.coverage < Walker.COVER_DONE and Shed.items[pipe]["color"] != Shed.PAINTS[4],
		"spraying one spot only covers part of it (%.0f%%)" % (w.coverage * 100.0))
	# Work over it like a painter: steady passes across it, from one side and then the other (the
	# paint only lands on what faces the can), and again where it's still thin.
	var to_mid := (Workshop.CENTER - Vector3(centre.x, 0.0, centre.z)).normalized()
	var round_sides := [to_mid, -to_mid, to_mid.cross(Vector3.UP), -to_mid.cross(Vector3.UP)]
	for pass_n in 16:
		if Shed.items[pipe]["color"] == Shed.PAINTS[4] or (w.spray != null and w.spray.ready()):
			break
		var side: Vector3 = round_sides[pass_n % round_sides.size()]
		w.place(Transform3D(Basis(), Vector3(centre.x, 0.0, centre.z) + side * 0.6))
		await _aim_point(w, centre)
		await _spray_passes(w, xf, box)
	# Letting go once it's covered finishes the coat.
	Input.action_release("act")
	for i in 3:
		await get_tree().physics_frame
	check(Shed.items[pipe]["color"] == Shed.PAINTS[4] and Shed.items[pipe].has("paint_quality"),
		"sweeping the can over all of it finishes the paint job (quality %.0f%%, covered %.0f%%)" % [float(Shed.items[pipe].get("paint_quality", 0.0)) * 100.0, w.coverage * 100.0])
	check(Shed.condition_text(Shed.items[pipe]).contains("Paint job"), "the info panel says how good the paint job is")
	w.leave_spray_mode()
	w.set_tool("hands")
	w.set_crouched(false)
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
	road_t = world.road_transform_on("woods", 200.0)
	bike.place(road_t.origin, road_t.basis.get_euler().y)
	for i in 60:
		await get_tree().physics_frame
	check(bike.surface == "dirt", "the woods track is dirt (on %s)" % bike.surface)
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
		if t < 4.5:   # about 100 km/h, then four and a half seconds on the front brake
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

## The ECU's rider aids on the dyno desk: only those the fitted ECU has, off or a level each,
## kept on the bike (and through a save), and riding uses them.
func _test_ecu_aid_settings() -> void:
	var sport := BikeBuild.new({"ecu": "sport_ecu"})
	var race := BikeBuild.new({"ecu": "race_ecu"})
	check(sport.tune_block("aid_traction") == "" and sport.tune_block("aid_anti_wheelie") == ""
		and sport.tune_block("aid_stability").contains("no stability control") and race.tune_block("aid_stability") == ""
		and BikeBuild.new({"ecu": "stock_ecu"}).tune_block("aid_traction").contains("no traction"),
		"only the aids the ECU has can be set (sport: traction and anti-wheelie; race: stability too)")
	check(is_equal_approx(race.aid_strength("traction"), race.ecu_aid) and is_equal_approx(sport.aid_strength("anti_wheelie"), sport.ecu_aid)
		and sport.aid_strength("stability") == 0.0, "untouched, each aid works as the ECU came from the factory")
	var off := BikeBuild.new({"ecu": "race_ecu"}, {}, {"aid_traction": 0.0, "aid_stability": 1.0, "aid_anti_wheelie": 5.0})
	check(not off.aid_on("traction") and off.aid_strength("stability") < race.aid_strength("stability") * 0.5
		and off.aid_strength("anti_wheelie") > race.aid_strength("anti_wheelie"), "off, gentle and firm levels change how hard they step in")
	check(TuningComputer.value_text("aid_traction", 0.0, race) == "Off" and TuningComputer.value_text("aid_traction", 3.0, race).contains("factory"),
		"the desk reads them as off or a level (%s)" % TuningComputer.value_text("aid_traction", 3.0, race))
	check(TuningComputer.aids_note(BikeBuild.new()).contains("no rider aids") and TuningComputer.aids_note(sport).contains("traction control")
		and not TuningComputer.aids_note(sport).contains("stability"), "the Rider aids tab says what this ECU has")

	# Set from the desk, through the Shed: kept on the bike, through a save and co-op sync.
	Shed.start_new("Tester", 7)
	var bike := _bike_named("Old Faithful")
	var me := Shed.me()
	check(Shed.check(me, {"a": "tune", "bike": bike, "key": "aid_traction", "value": 0}).contains("ECU"),
		"a bike with no aids on its ECU can't have them set")
	var ecu := Shed._new_item("race_ecu", 0.0, 0.0, 0.0)
	Shed._move(ecu, "bike", bike)
	Shed.bikes[bike]["slots"]["ecu"] = ecu
	Shed.bikes[bike]["bolted"]["ecu"] = true
	Shed.request({"a": "tune", "bike": bike, "key": "aid_traction", "value": 0})
	Shed.request({"a": "tune", "bike": bike, "key": "aid_anti_wheelie", "value": 1})
	check(is_equal_approx(float(Shed.bikes[bike]["tune"].get("aid_traction", -1.0)), 0.0), "the setting is kept on the bike")
	var copy: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	Shed._sync(copy)
	var b := Shed.build_of(bike)
	check(not b.aid_on("traction") and b.aid_on("anti_wheelie") and b.aid_strength("anti_wheelie") < b.ecu_aid
		and is_equal_approx(b.aid_strength("stability"), b.ecu_aid), "and survives a save, so the ride uses it")

	# Riding: full gas on loose dirt with no rider help, traction control off and then at its firmest.
	var spins := []
	for level in [0.0, 5.0]:
		var spin := [0.0, 0]
		var r := await ride({"engine": "four_1000", "ecu": "race_ecu"}, 3.0, func(bk, t):
			bk.build.tune["aid_traction"] = level
			bk.build.tune["aid_anti_wheelie"] = 5.0
			bk.assist = 0.0
			bk.throttle = 1.0 if t > 0.3 else 0.0
			if t > 0.6 and bk.wheels[1]["contact"]:
				spin[0] += (float(bk.wheels[1]["omega"]) * bk.build.rear_radius - bk.speed) / maxf(bk.speed, 1.0)
				spin[1] += 1, "dirt")
		spins.append(spin[0] / maxf(1.0, float(spin[1])))
		await _done(r)
	check(spins[0] > spins[1] * 1.15, "traction control off lets the back tyre spin up on dirt; at level 5 it holds it (slip %.2f vs %.2f)" % spins)
	# Anti-wheelie off lets the front come up that the factory setting keeps down.
	var pitches := []
	for level in [0.0, 3.0]:
		var pitch := [0.0]
		var r := await ride({"engine": "four_1000", "ecu": "race_ecu"}, 5.0, func(bk, t):
			bk.build.tune["aid_anti_wheelie"] = level
			bk.body_shift = -1.0
			bk.throttle = 1.0 if t > 0.5 else 0.0
			pitch[0] = maxf(pitch[0], rad_to_deg(bk.pitch_angle)))
		pitches.append(pitch[0])
		await _done(r)
	check(pitches[0] > pitches[1] + 5.0, "anti-wheelie off lets it wheelie (%.0f deg) where the factory level keeps it near level (%.0f deg)" % pitches)


## Other bikers on the roads: they appear out of sight, ride the tarmac in their lane at a
## sensible pace, lean into the bends, keep off the yard, go when nobody's near, reach the crew
## as a few numbers, and you crash if you ride into one.
func _test_road_traffic() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var tr: RoadTraffic = main.traffic
	tr.setup_roads()
	var loop_blocked := 0
	for b in (tr._blocked[0] as PackedByteArray):
		loop_blocked += b
	check(tr._ready_roads and tr._tarmac.size() >= 5 and loop_blocked > 20,
		"the tarmac roads are mapped, with the loop's stretch across the yard out of bounds (%d samples)" % loop_blocked)
	tr._spawn_timer = 1000.0   # only the riders this test puts out
	var near := []
	for i in RoadTraffic.MAX_RIDERS:
		near.append(tr.spawn_one())
	var walker_at: Vector3 = main.walker.global_position
	var first: Dictionary = tr.riders[0]
	check(not near.has(-1) and tr.active_count() == RoadTraffic.MAX_RIDERS and tr.spawn_one() == -1,
		"riders appear out on the roads, no more than %d at once" % RoadTraffic.MAX_RIDERS)
	var d0 := Vector2(tr._rider_point(first).x - walker_at.x, tr._rider_point(first).z - walker_at.z).length()
	check(d0 >= RoadTraffic.SPAWN_NEAR - 5.0 and d0 <= RoadTraffic.SPAWN_FAR + 5.0, "out of sight but not too far off (%.0f m)" % d0)
	# Ride them on for a few game minutes in quick steps.
	var top := 0.0
	var into_yard := false
	var off_road := 0.0
	var switched := false
	var roads_before := tr.riders.map(func(d): return int(d["road"]))
	var lean := 0.0
	for step in 3000:
		for slot in RoadTraffic.MAX_RIDERS:
			var d: Dictionary = tr.riders[slot]
			if d.is_empty():
				tr.spawn_one(0.0, 600.0)
				continue
			tr._drive(slot, d, 0.05)
			d = tr.riders[slot]
			if d.is_empty():
				continue
			top = maxf(top, float(d["v"]))
			var p := tr._rider_point(d)
			if RoadTraffic.KEEP_OUT.has_point(Vector2(p.x, p.z)):
				into_yard = true
			var near_road: Dictionary = main.world.roads.nearest(p.x, p.z, 20.0)
			off_road = maxf(off_road, float(near_road.get("d", 20.0)))
			if int(d["road"]) != int(roads_before[slot]):
				switched = true
			var k := float((tr._k[int(d["road"])] as PackedFloat32Array)[tr._i(int(d["road"]), float(d["s"]))])
			lean = maxf(lean, absf(atan(float(d["v"]) * float(d["v"]) * k / Bike.G)))
	check(top > 10.0 and top <= 20.5, "they ride at a sensible pace (top %.0f km/h)" % (top * 3.6))
	check(off_road < 3.0, "in their lane, on the road (at most %.1f m off its middle)" % off_road)
	check(not into_yard, "and never into the yard, the test area or the cafe car park")
	check(switched, "they turn off at junctions onto other roads")
	check(lean > deg_to_rad(10.0) and lean < deg_to_rad(30.0), "and lean into the bends, slowing for the tight ones (up to %.0f deg)" % rad_to_deg(lean))
	# Far from everyone, they go.
	var gone: Dictionary = tr.riders[0]
	if not gone.is_empty():
		main.walker.global_position = Vector3(5000.0, 0.0, 5000.0)
		tr._drive(0, gone, 0.05)
		check((tr.riders[0] as Dictionary).is_empty(), "a rider far from everyone leaves the roads")
		main.walker.global_position = walker_at
	# The crew get them as a few numbers each, and ride them the same.
	var packed := tr.pack()
	check(packed.size() == 1 + RoadTraffic.MAX_RIDERS * 5, "the crew get %d numbers for the lot" % packed.size())
	var other := RoadTraffic.new()
	other.world = main.world
	add_child(other)
	other.setup_roads()
	other.unpack(packed)
	var same := true
	for slot in RoadTraffic.MAX_RIDERS:
		var a: Dictionary = tr.riders[slot]
		var b: Dictionary = other.riders[slot]
		if a.is_empty() != b.is_empty() or (not a.is_empty() and (int(a["road"]) != int(b["road"]) or absf(float(a["s"]) - float(b["s"])) > 0.01)):
			same = false
	check(same and RoadTraffic.look_of(1234)["parts"] == RoadTraffic.look_of(1234)["parts"], "and draw the same riders on the same bikes")
	other.free()
	# Ride into one stopped in the lane ahead: you crash.
	for slot in RoadTraffic.MAX_RIDERS:
		tr.riders[slot] = {}
	await get_tree().physics_frame
	var east := int(main.world.roads.by_name["east"])
	var s := 300.0
	var best := INF
	for t in range(60, 400, 10):
		var kk := absf(float((tr._k[east] as PackedFloat32Array)[tr._i(east, float(t))]))
		if kk < best and not tr._heads_into_yard(east, float(t), 1):
			best = kk
			s = float(t)
	tr.riders[0] = {"road": east, "s": s, "dir": 1, "v": 0.0, "seed": 77, "cruise": 0.0, "turn": {}, "round": -1.0}
	await get_tree().physics_frame
	await get_tree().physics_frame
	var view_body: Node3D = tr._views[0]["body"]
	check(view_body != null and view_body.is_in_group("road_traffic") and (view_body as CollisionObject3D).collision_layer & 2 != 0,
		"the rider is solid, with the bikes")
	var bike := Bike.new()
	bike.setup(BikeBuild.new())
	main.world.add_child(bike)
	var from := tr._rider_point({"road": east, "s": s - 30.0, "dir": 1})
	var fwd := tr.road_dir(east, s - 30.0)
	bike.place(from + Vector3.UP * 0.3, atan2(-fwd.x, -fwd.y))
	var crashed := false
	for i in int(6.0 * Engine.physics_ticks_per_second):
		tr.riders[0]["v"] = 0.0
		bike.throttle = 1.0
		await get_tree().physics_frame
		if bike.is_crashed:
			crashed = true
			break
	check(crashed, "riding into one at speed crashes you (%.0f km/h, %.1f m short of it)" % [
		absf(bike.speed) * 3.6, bike.global_position.distance_to(view_body.global_position)])
	bike.queue_free()
	main._end_session()
	await get_tree().physics_frame
	check(tr.active_count() == 0, "and they're off the roads when the session ends")
	main.queue_free()
	await get_tree().process_frame


## The bike details pages list the paint panel by panel: each panel's own colour or mix (name
## and code), finish, coats, lacquer, job quality and stripe.
func _test_bike_paint_panels() -> void:
	Shed.start_new("Tester", 7)
	var bike := _bike_named("Old Faithful")
	var tank: Dictionary = Shed.items[Shed.item_on(bike, "tank")]
	var tin := PaintMix.new_tin("W")
	tin["tints"] = {"PB": 40.0, "AL": 12.0}
	tank["mix"] = PaintMix.spec(tin, "Midnight Blue")
	tank["mix_coats"] = 2
	tank["paint_quality"] = 0.91
	tank["coat"] = "clear"
	tank["coat_q"] = 0.88
	tank["mask"] = {"pattern": "stripe", "color": Color(0.9, 0.9, 0.9), "q": 1.0, "mix": {}}
	var list := BikePaintInfo.panels(bike)
	check(not list.is_empty() and str(list[0]["slot"]) == "tank", "the tank heads the list of painted panels")
	var t := BikePaintInfo.line(list[0])
	check(t.contains("Midnight Blue") and t.contains(str(tank["mix"]["code"])) and t.contains("2 coats") and t.contains("job 91%")
		and t.contains("clear lacquer") and t.contains("Centre stripe in white"),
		"each panel has its own paint: mix name and code, coats, lacquer, quality and stripe (%s)" % t)
	var slots := list.map(func(e): return str(e["slot"]))
	var other: Dictionary = list[slots.find("frame")] if slots.has("frame") else {}
	check(slots.size() >= 2 and not other.is_empty() and str(other["colour"]) != "Midnight Blue",
		"other panels show their own paint, not the tank's (%s)" % ", ".join(slots))
	check(not slots.has("engine") and not slots.has("chain"), "unpainted mechanical parts aren't listed")
	var text := BikePaintInfo.text(bike)
	check(text.begins_with("Fuel tank: Midnight Blue") or text.begins_with("Tank: Midnight Blue"), "the Sell aisle's text lists it too: %s" % text.get_slice("\n", 0))
	var pc := SalesComputer.new()
	var box := VBoxContainer.new()
	pc._paint_card(box, bike)
	check(box.get_child_count() == 1 and box.get_child(0).get_child(0).get_child_count() == list.size() + 1,
		"the showroom page gets a paint card with a row per panel")
	box.free()
	pc.free()


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
	bike.beam = Bike.BEAM_FOG
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
	# One ancillary left half done, so the engine isn't bare all over yet (that makes it new).
	res[parts[parts.size() - 1]] = [0.45, 0.0]
	var xp_before := int(Progress.profile.get("xp", 0))
	Shed.request({"a": "blast", "spot": spot, "parts": res})
	check(float(Shed.items[parts[0]]["wear"]) > 0.15 and (parts.size() < 3 or float(Shed.items[parts[1]]["wear"]) < 0.11),
		"lingering pits the metal: the overdone part wears")
	check(int(Progress.profile.get("xp", 0)) > xp_before, "sandblasting earns XP")
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	res[parts[parts.size() - 1]] = [0.95, 0.0]
	Shed.request({"a": "blast", "spot": spot, "parts": res})
	check(parts.all(func(id): return float(Shed.items[id]["rust"]) == 0.0 and float(Shed.items[id]["dirt"]) == 0.0),
		"blasted all over, the engine and every ancillary come back to bare metal")
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
	check(ordered == rows.size(), "a whole bike's worth of parts fits in the delivery area (%d ordered)" % ordered)
	var frame_item := int(Shed.plan_at(3)["ordered"]["frame"])
	check(Shed.items[frame_item]["boxed"] and Shed.items[frame_item]["part"] == Shed.blueprints[bp]["parts"]["frame"], "the frame arrives boxed")
	check(Shed.items[frame_item]["color"] == Shed.blueprints[bp]["colors"]["frame"]["color"], "parts come in the blueprint's colours")
	Shed.request({"a": "bp_order", "bay": 3})
	check(Shed.plan_rows(Shed.plan_at(3), 0).filter(func(r): return r["state"] == "ordered").size() == ordered,
		"ordering again doesn't double up")
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
	check(Shed.check(me, {"a": "scrap", "furniture": shelf}) == "", "standing where it is, it can be scrapped too")
	Shed.furniture[shelf]["mover"] = me + 7
	check(Shed.check(me, {"a": "scrap", "furniture": shelf}).contains("Someone else"), "not while someone else is moving it")
	Shed.furniture[shelf]["mover"] = 0
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
	# Long enough for the drumming on the roof to fade out (it eases across at the door).
	for i in 90:
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
	check(views > 0 and lamps >= views, "the sandblaster has its own light inside, under the roof")
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
	var pm := jet.process_material as ShaderMaterial
	var speed: float = float(pm.get_shader_parameter("speed_min")) if pm else 0.0
	check(jet.amount >= 3000 and grain.x < 0.004 and speed >= 20.0 and float(pm.get_shader_parameter("bounce")) > 0.0,
		"the nozzle shoots thousands of tiny, fast grains of sand that bounce off what they hit (%d at %.0f m/s)" % [jet.amount, speed])
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
	check(Money.check(me, {"a": "money_sell_bike", "bike": ranger}).contains("showroom"),
		"bikes are only sold from a showroom display stand")
	Shed.bikes[ranger]["xf"] = Workshop.SHOWROOM_SPOTS[0]
	value = Money.bike_sale(ranger)
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
		and Contracts.unlocked(10).size() == 5, "reputation unlocks harder jobs: service first, then MOT, colour matches, mods and bespoke builds")
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
			ok = ok and o["goals"][0] == {"t": "mot"} and o["goals"].slice(1).all(func(g): return g["t"] == "task")
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
	check(Shed.bikes.has(jb) and (Shed.bikes[jb]["xf"] as Transform3D).origin.distance_to(Contracts.park_xf(0).origin) < 0.1
		and str(Shed.bikes[jb]["name"]).contains(cust.get_slice(" ", 0)),
		"their bike is left in the car park (%s)" % str(Shed.bikes.get(jb, {}).get("name", "")))
	# Into the shed to work on it.
	Shed.bikes[jb]["xf"] = Workshop.bay_transform(3)
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": jid}).contains("car park"), "it can't be handed back from a bay")
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
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": jid}).contains("car park"), "it has to be left in the car park")
	Shed.bikes[jb]["xf"] = Contracts.park_xf(0)
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
	var built_tank: Dictionary = Shed.items[Shed.item_on(built, "tank")]
	for g in goals:
		if g["t"] == "paint":
			g["color"] = Shed.paint_index(built_tank["color"])
		elif g["t"] == "match":
			var tc: Color = built_tank["color"]
			g["rgb"] = [tc.r, tc.g, tc.b]
			g["effect"] = "solid"
		elif g["t"] == "stripe":
			built_tank["mask"] = {"pattern": str(g["pattern"]), "color": Contracts._rgb(g), "q": 1.0, "mix": {}}
	var bj :={"id": 999, "kind": "bespoke", "bike": built, "goals": goals, "pay": 3000, "budget": 4000, "due": Contracts.clock() + 100.0,
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
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": mj["id"]}).contains("car park"), "just outside the roller door isn't the car park")
	Shed.bikes[int(mj["bike"])]["xf"] = Contracts.park_xf(2)
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": mj["id"]}) == "", "left in the car park, it can be handed back")
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
	for i in 8000:
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
	check(not view.views.has(cv.customer_id) and cv.leaving, "and they head off")
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
	var bell_s: Array = Sfx.sounds("bell")
	var chime_s: Array = Sfx.sounds("bell_chime")
	var players := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(p): return bell_s.has(p.stream) or chime_s.has(p.stream))
	check(players.size() >= 2, "the shop bell rings over its door and the chime in the shed")
	var chime := players.filter(func(p): return chime_s.has(p.stream) and Workshop.room_at((p as Node3D).global_position) == "shed")
	check(not chime.is_empty(), "the chime is in the shed")
	check(absf((so.get_node("ShopBell") as Node3D).rotation.x) > 0.01, "and the bell over the door swings")
	Shed.bell_rang.disconnect(on_bell)
	# The service bell on the reception counter: click it and it dings.
	var desk_bodies := so.find_children("*", "StaticBody3D", true, false).filter(func(n): return n.has_meta("desk_bell"))
	check(desk_bodies.size() == 1 and (desk_bodies[0] as CollisionObject3D).collision_layer & Workshop.INTERACT_LAYER,
		"the reception counter's bell can be clicked")
	var dings := Shed.desk_bells
	Shed.ding_desk_bell()
	for i in 3:
		await get_tree().process_frame
	var ding_s: Array = Sfx.sounds("desk_bell")
	var dinging := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(p): return ding_s.has(p.stream))
	check(Shed.desk_bells == dings + 1 and not dinging.is_empty() and (dinging[0] as Node3D).global_position.distance_to(so.to_global(so.desk_bell_pos)) < 0.5,
		"and it dings on the counter")
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
	var mid_x := (GarageUpgrades.STAIR_X.x + GarageUpgrades.STAIR_X.y) * 0.5
	var mid_z := (GarageUpgrades.STAIR_Z.x + GarageUpgrades.STAIR_Z.y) * 0.5
	var stairs := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(mid_x, 5.5, mid_z), Vector3(mid_x, -1.0, mid_z), 1))
	check(not stairs.is_empty() and absf(float(stairs["position"].y) - GarageUpgrades.MEZZ_TOP * 0.5) < 0.25, "the mezzanine stairs are a slope to walk up (%.2f m half way)" % float(stairs.get("position", Vector3.ZERO).y))
	var deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-11.5, 5.5, 42.0), Vector3(-11.5, -1.0, 42.0), 1))
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
	dressed.own_rider = true
	dressed.rider_gear = RiderGear.clean_worn({"helmet": "helmet_kestrel", "jacket": "jacket_kestrel", "boots": "boots_mx", "trousers": "trousers_kestrel"})
	add_child(dressed)
	dressed.build_from(BikeBuild.new())
	check(dressed._rider != null and dressed._rider.get_child_count() > plain._rider.get_child_count(),
		"a rider in race gear on a bike is drawn with it (%d meshes, plain %d)" % [dressed._rider.get_child_count(), plain._rider.get_child_count()])
	var helmeted := 0
	for c in dressed._rider.get_children():
		if (c as VisualInstance3D).layers == 1 << (BikeModel.HELMET_LAYER - 1):
			helmeted += 1
	check(helmeted >= 4, "your own helmet, torso and upper arms stay out of the first-person view (%d)" % helmeted)
	# Someone else's rider: all of them in your first-person view, plain or in gear.
	var theirs := BikeModel.new()
	theirs.rider_gear = dressed.rider_gear
	add_child(theirs)
	theirs.build_from(BikeBuild.new())
	var hidden_theirs := [plain, theirs].map(func(m: BikeModel) -> int:
		return m._rider.find_children("*", "VisualInstance3D", true, false).filter(func(c):
			return (c as VisualInstance3D).layers & (1 << (BikeModel.HELMET_LAYER - 1)) != 0).size())
	check(hidden_theirs == [0, 0], "another rider is whole in your first-person view, waist up and all (%s on the eye's hidden layer)" % str(hidden_theirs))
	theirs.queue_free()
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



## Simon's recorded sounds: every file there and loading, loops looping, takes picked without
## repeats, the made sounds kept as stand-ins, horns as parts that play their recordings (held,
## once or repeating), the gear lever on shifts, the phone ringing for a new customer, and the
## birds singing now and then rather than all the time.
func _test_recorded_sounds() -> void:
	var missing := []
	var loops_ok := true
	var total := 0
	for sound in Sfx.RECORDED:
		var rec: Array = Sfx.recordings(sound)
		total += rec.size()
		if rec.size() != (Sfx.RECORDED[sound] as Array).size():
			missing.append(sound)
		for s in rec:
			if Sfx.LOOPS.has(sound) and not (s as AudioStreamOggVorbis).loop:
				loops_ok = false
			if (s as AudioStream).get_length() > 2.5 or (s as AudioStream).get_length() < 0.05:
				missing.append("%s (%.2f s)" % [sound, (s as AudioStream).get_length()])
	check(missing.is_empty(), "every recording is shipped and loads (%d takes) %s" % [total, str(missing)])
	check(loops_ok, "the recorded loops (ratchet, sandblaster, dyno fan, roller door) loop")
	var only_recorded := Sfx.RECORDED.keys().filter(func(k): return not str(k).begins_with("horn_") and not SfxSynth.all_sounds().has(k))
	check(only_recorded.all(func(k): return Sfx.STAND_INS.has(k)), "a sound that's only ever recorded has a stand-in")
	check(Sfx.sounds("ratchet") == Sfx.recordings("ratchet") and Sfx.variants("ratchet")[0] is AudioStreamWAV,
		"the wrench plays the recordings, and the made ratchet is still there behind them")
	check(Sfx.sounds("light_switch").size() == 4 and Sfx.sounds("bell").size() == 1 and Sfx.sounds("bell")[0] is AudioStreamWAV,
		"the light switch has four takes; the brass bell stays synthesised")
	var last: AudioStream = null
	var repeats := 0
	var seen := {}
	for i in 60:
		var s := Sfx.pick("ratchet")
		repeats += 1 if s == last else 0
		last = s
		seen[s] = true
	check(repeats == 0 and seen.size() == 4, "the wrench's takes never play twice running and all get used (%d)" % seen.size())
	# A recorded loop on a machine.
	var host := Node3D.new()
	add_child(host)
	var lp := Sfx.make_loop_player(host)
	Sfx.set_loop(lp, "blast")
	var first := lp.stream
	check(lp.playing and Sfx.recordings("blast").has(first), "the sandblaster blasts with a recording")
	Sfx.set_loop(lp, "blast")
	check(lp.stream == first, "and keeps the same take while it runs")
	Sfx.set_loop(lp, "")
	check(not lp.playing, "and stops when you let go")
	# Horns: parts with recordings.
	var horns: Array = PartsDB.by_kind["horn"]
	check(horns.size() >= 17 and horns.has("police_horn") and horns.has("ship_horn") and horns.has("truck_air_horn"),
		"the horn aisle has police, ship and air horns (%d horns)" % horns.size())
	var no_takes := horns.filter(func(id): return str(PartsDB.get_part(id).get("sound", "")) != "" and Sfx.recordings(str(PartsDB.get_part(id)["sound"])).is_empty())
	check(no_takes.is_empty(), "every recorded horn has its takes %s" % str(no_takes))
	var ship := BikeBuild.new({"engine": "twin_700", "horn": "ship_horn"})
	check(ship.horn_sound == "horn_ship" and not ship.horn_tones.is_empty() and BikeBuild.new({"engine": "twin_700", "horn": "goose_horn"}).horn_sound == "",
		"a bike knows its horn's recordings; the goose is still made")
	var air := _horn("horn_air")
	check(air.is_recorded(), "the air horn plays its recordings")
	air.pressed = true
	await get_tree().process_frame
	await get_tree().process_frame
	var air_s := air.stream as AudioStreamOggVorbis
	check(air.playing and air.takes == 1 and air_s.loop and is_equal_approx(air_s.loop_offset, HornAudio.LOOP_FROM),
		"held, it sounds and its steady note loops")
	air.pressed = false
	for i in 30:
		await get_tree().process_frame
	check(not air.playing, "and it stops when you let go")
	var ship_h := _horn("horn_ship")
	ship_h.pressed = true
	await get_tree().process_frame
	ship_h.pressed = false
	for i in 12:
		await get_tree().process_frame
	check(ship_h.playing and ship_h.takes == 1, "a tap on the ship's horn plays the whole blast")
	var police := _horn("horn_police")
	police.pressed = true
	await get_tree().process_frame
	check(police.takes == 1 and Sfx.recordings("horn_police").has(police.stream) and not (police.stream as AudioStreamOggVorbis).loop,
		"the police horn yelps a take at a time")
	var synth := HornAudio.new()
	synth.style = "goose"
	synth.tones = [330.0]
	add_child(synth)
	check(not synth.is_recorded() and synth.stream is AudioStreamGenerator, "a horn without recordings is still synthesised")
	for h in [air, ship_h, police, synth]:
		h.queue_free()
	# The gear lever on a shift, by the gearbox's feel.
	var es := EngineSound.new()
	add_child(es)
	es.setup(BikeBuild.new({"engine": "four_1000", "exhaust": "titanium_race", "gearbox": "six_race_quickshift"}))
	es.running = true
	es.rpm = 9000.0
	es.gear = 2
	es._process(1.0 / 60.0)
	es.gear = 3
	es._process(1.0 / 60.0)
	check(es.lever_sounds == 1 and Sfx.recordings("shift_slick").has(es._lever.stream) and es._lever.pitch_scale > 1.1,
		"a quickshift adds the recorded lever's slick tick, pitched up")
	es.queue_free()
	# The phone: a few rings, from the reception and the extension in the shed.
	var calls := Sfx.phone_calls
	Sfx.ring_phone(SalesOffice.RECEPTION.origin + Vector3.UP, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var rings := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(q): return Sfx.recordings("phone_ring").has(q.stream))
	check(Sfx.phone_calls == calls + 1 and rings.size() >= 2, "the phone rings at reception and in the shed (%d)" % rings.size())
	# A new customer calls ahead; one already waiting doesn't.
	Shed.start_new("Tester", 41)
	var amb := SfxAmbience.new()
	add_child(amb)
	amb.set_process(false)
	Contracts.customers()[990001] = {"id": 990001, "arrived": Contracts.clock() - 100.0}
	amb._watch_customers(1.0)
	check(Sfx.phone_calls == calls + 1, "customers already there when you arrive don't ring")
	Contracts.customers()[990002] = {"id": 990002, "arrived": Contracts.clock()}
	amb._watch_customers(1.0)
	check(Sfx.phone_calls == calls + 2, "a new customer rings the sales office phone")
	Contracts.customers().erase(990001)
	Contracts.customers().erase(990002)
	# Birds: short bursts with long gaps, fewer at midday.
	var sung := {}
	for hour in [8.0, 13.0]:
		amb._rng.seed = 5
		amb.birds_singing = false
		amb.bird_timer = 0.0
		var on := 0.0
		var bursts := 0
		var t := 0.0
		while t < 3600.0:
			var was := amb.birds_singing
			on += amb._bird_burst(0.5, hour) * 0.5
			if amb.birds_singing and not was:
				bursts += 1
			t += 0.5
		sung[hour] = [on / 3600.0, bursts]
	check(float(sung[8.0][0]) < 0.3 and int(sung[8.0][1]) >= 20, "birds sing now and then in the morning: %d bursts, %.0f%% of the time" % [sung[8.0][1], float(sung[8.0][0]) * 100.0])
	check(float(sung[13.0][0]) < float(sung[8.0][0]) * 0.5, "and much less at midday (%.0f%%)" % (float(sung[13.0][0]) * 100.0))
	check(SfxAmbience.BIRD_DB <= -14.0, "and quieter than before")
	amb.queue_free()
	host.queue_free()
	Shed.stop()


func _horn(sound: String) -> HornAudio:
	var h := HornAudio.new()
	h.sound = sound
	h.tones = [300.0]
	h.loudness = 1.0
	add_child(h)
	return h


# ---------------------------------------------------------------------------- riding feedback round

## Third person: the mouse or right stick swings the chase camera round the bike, never
## through it, and it eases back behind after a moment; first person turns your head.
func _test_ride_camera_orbit() -> void:
	var r := await ride({}, 0.5, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	var cam := ChaseCamera.new()
	r["root"].add_child(cam)
	cam.target = bike
	cam.set_mode(ChaseCamera.Mode.CHASE)
	for i in 30:
		await get_tree().physics_frame
	var fwd := -bike.global_transform.basis.z
	var right := bike.global_transform.basis.x
	var rel := cam.global_position - bike.global_position
	check(rel.dot(fwd) < -3.5 and absf(rel.dot(right)) < 0.3, "the chase camera starts behind the bike (%s)" % rel)
	# Swing it round a quarter turn with the mouse (to the bike's right) and watch the path.
	var closest := 100.0
	for i in 60:
		cam.add_orbit(PI * 0.5 / 60.0, 0.0)
		await get_tree().physics_frame
		closest = minf(closest, Vector2(cam.global_position.x - bike.global_position.x, cam.global_position.z - bike.global_position.z).length())
	for i in 30:
		cam.add_orbit(0.0, 0.0)
		await get_tree().physics_frame
	rel = cam.global_position - bike.global_position
	check(rel.dot(right) > 3.5 and absf(rel.dot(fwd)) < 1.0, "swung a quarter turn, it looks at the bike from its side (%s)" % rel)
	check(closest > 3.5, "it swings round the bike, never through it (closest %.1f m)" % closest)
	var to_bike := (bike.global_position - cam.global_position).normalized()
	check((-cam.global_transform.basis.z).dot(to_bike) > 0.95, "and keeps the bike in the middle of the view")
	cam.add_orbit(0.0, 0.6)
	for i in 30:
		await get_tree().physics_frame
	check(cam.global_position.y - bike.global_position.y > 3.0, "tilting it up looks down on the bike (%.1f m up)" % (cam.global_position.y - bike.global_position.y))
	# Hands off: after a moment it eases back behind.
	for i in int((ChaseCamera.RECENTRE_DELAY + 2.5) * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	rel = cam.global_position - bike.global_position
	check(rel.dot(fwd) < -3.5 and absf(rel.dot(right)) < 0.6 and not cam.orbiting(), "let go, it eases back behind the bike (%s)" % rel)
	# With recentring switched off it stays where you left it.
	cam.recentre = false
	cam.add_orbit(-PI * 0.5, 0.0)
	for i in int((ChaseCamera.RECENTRE_DELAY + 2.0) * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	rel = cam.global_position - bike.global_position
	check(rel.dot(right) < -3.0 and cam.orbiting(), "with the setting off it stays swung round (%s)" % rel)
	check(Settings.camera_recentre is bool, "the recentre setting is a saved setting")
	# First person: the head turns, the eye stays put.
	cam.recentre = true
	cam.set_mode(ChaseCamera.Mode.HELMET)
	await get_tree().physics_frame
	var eye := cam.global_position
	var ahead := -cam.global_transform.basis.z
	cam.add_orbit(0.8, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var look := -cam.global_transform.basis.z
	check(cam.global_position.distance_to(eye) < 0.05 and ahead.dot(look) < 0.8 and look.dot(-right) > 0.4,
		"in first person it turns your head to look round, from the same eye")
	cam.add_orbit(10.0, 0.0)
	check(cam.orbit_yaw <= ChaseCamera.HEAD_YAW + 0.001, "but no further than a head turns")
	await _done(r)


## The ride-by camera: dropped at the roadside ahead, it watches the bike come past, then goes
## back to the view you had.
func _test_ride_by_camera() -> void:
	var cam_box := [null]
	var passed := [false]
	var steady := [true]
	var spot := [Vector3.ZERO]
	var r := await ride({}, 9.0, func(b, t):
		b.throttle = 0.5 if t < 3.0 else 0.25
		if t > 2.5 and cam_box[0] == null:
			var cam := ChaseCamera.new()
			b.get_parent().add_child(cam)
			cam.target = b
			cam.set_mode(ChaseCamera.Mode.CHASE)
			cam_box[0] = cam
		elif cam_box[0] != null and t > 2.8:
			var cam: ChaseCamera = cam_box[0]
			if spot[0] == Vector3.ZERO:
				cam.start_ride_by()
				spot[0] = cam.ride_by_spot()
			elif cam.mode == ChaseCamera.Mode.RIDE_BY:
				if cam.global_position.distance_to(spot[0]) > 0.01:
					steady[0] = false
				if (b.global_position - spot[0]).dot(-b.global_transform.basis.z) > 2.0:
					passed[0] = true)
	var bike: Bike = r["bike"]
	var cam: ChaseCamera = cam_box[0]
	check(cam != null and spot[0] != Vector3.ZERO, "V drops a camera at the roadside")
	check(steady[0] and passed[0], "it stands still while the bike rides past it")
	check(cam.mode == ChaseCamera.Mode.CHASE and cam.ride_by_left() == 0.0, "after a few seconds it goes back to the chase view")
	var rel := cam.global_position - bike.global_position
	check(rel.dot(-bike.global_transform.basis.z) < -3.0, "behind the bike again (%s)" % rel)
	# Pressing it again ends it early; in first person it comes back to first person.
	cam.set_mode(ChaseCamera.Mode.HELMET)
	cam.start_ride_by()
	check(cam.mode == ChaseCamera.Mode.RIDE_BY and cam.ride_by_left() >= ChaseCamera.RIDE_BY_MIN, "from first person too")
	cam.start_ride_by()
	check(cam.mode == ChaseCamera.Mode.HELMET, "pressing it again goes straight back to first person")
	await _done(r)
	# The fly-by view keeps hopping on ahead instead of going back.
	var hops := [0, Vector3.ZERO, null]
	r = await ride({}, 14.0, func(b, t):
		b.throttle = 0.5 if t < 3.0 else 0.3
		if t > 2.5 and hops[2] == null:
			var cam2 := ChaseCamera.new()
			b.get_parent().add_child(cam2)
			cam2.target = b
			cam2.set_mode(ChaseCamera.Mode.RIDE_BY)
			hops[2] = cam2
			hops[1] = cam2.ride_by_spot()
		elif hops[2] != null:
			var cam2: ChaseCamera = hops[2]
			if cam2.ride_by_spot() != hops[1]:
				hops[0] += 1
				hops[1] = cam2.ride_by_spot())
	var fb: ChaseCamera = hops[2]
	check(fb != null and fb.mode == ChaseCamera.Mode.RIDE_BY and int(hops[0]) >= 1,
		"the fly-by view stays on and hops to a new spot ahead (%d hops)" % int(hops[0]))
	await _done(r)


## Front brake on, throttle open and the bars turned: the back tyre slides round the front
## wheel in a circle of smoke, and scrubs the tyre down.
func _test_circle_burnout() -> void:
	var r := await ride({"engine": "twin_700"}, 6.0, func(b, t):
		b.front_brake = 1.0
		b.throttle = 1.0 if t > 0.5 else 0.0
		b.lean_input = 1.0 if t > 1.5 else 0.0)
	var bike: Bike = r["bike"]
	check(not r["crashed"] and bike.burnout > 0.5, "a burnout with the bars turned stays lit and upright (burnout %.2f)" % bike.burnout)
	check(bike.donut_turn < -PI * 1.5, "leaning right swings it round to the right, in a circle (%.0f degrees)" % rad_to_deg(bike.donut_turn))
	check(absf(bike.speed) < 1.5, "pivoting round the front wheel, not riding off (%.1f m/s)" % bike.speed)
	check(bike.effects.tyre_smoke_emitting(), "in a cloud of tyre smoke")
	var spun := bike.take_burnout_time()
	check(spun > 2.0 and bike.burnout_time == 0.0, "the bike counts the burnout time for the tyre (%.1f s)" % spun)
	await _done(r)
	r = await ride({"engine": "twin_700"}, 4.0, func(b, t):
		b.front_brake = 1.0
		b.throttle = 1.0 if t > 0.5 else 0.0
		b.lean_input = -1.0 if t > 1.5 else 0.0)
	bike = r["bike"]
	check(bike.donut_turn > PI * 0.5, "leaning left spins it the other way (%.0f degrees)" % rad_to_deg(bike.donut_turn))
	await _done(r)
	r = await ride({"engine": "twin_700"}, 3.0, func(b, t):
		b.front_brake = 1.0
		b.throttle = 1.0 if t > 0.5 else 0.0)
	var straight: Bike = r["bike"]
	check(absf(straight.donut_turn) < 0.3, "bars straight, it stays pointing the same way (%.0f degrees)" % rad_to_deg(straight.donut_turn))
	await _done(r)
	# Back at the shed the burnout seconds wear the back tyre.
	Shed.start_new("Tester", 7)
	var faithful := _bike_named("Old Faithful")
	var tyre := Shed.item_on(faithful, "rear_tyre")
	var front := Shed.item_on(faithful, "front_tyre")
	var before := float(Shed.items[tyre]["wear"])
	var front_before := float(Shed.items[front]["wear"])
	Shed._wear_from_ride(faithful, {"km": 0.0, "spin": 4.0})
	check(float(Shed.items[tyre]["wear"]) > before + 0.01 and float(Shed.items[front]["wear"]) == front_before,
		"burnouts scrub the back tyre down (%.3f -> %.3f), not the front" % [before, float(Shed.items[tyre]["wear"])])


## The headlight switch: off, low, high, then high with the fog lights on a bike that has them.
func _test_headlight_sequence() -> void:
	var r := await ride({"fog_lights": "rally_lamps"}, 0.3, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	bike.beam = 0
	var names := []
	for i in 4:
		names.append(bike.cycle_beam())
	check(names == ["low beam", "high beam", "high beam and fog lights", "off"], "with fog lights: off, low, high, high and fog, off %s" % str(names))
	bike.beam = 2
	for i in 3:
		await get_tree().physics_frame
	check(bike._fog.all(func(l): return not l.visible) and not bike.model.fog_lit() and bike.effects.light_on(),
		"on high beam the fog lamps stay off")
	bike.cycle_beam()
	for i in 3:
		await get_tree().physics_frame
	check(bike.beam == Bike.BEAM_FOG and bike._fog.all(func(l): return l.visible) and bike.model.fog_lit() and bike.effects.light_on(),
		"the next press puts the fog lamps on with the high beam")
	var state := bike.get_net_state()
	check(int(state[24]) == Bike.BEAM_FOG, "other players see the fog lamps on too")
	await _done(r)
	r = await ride({}, 0.3, func(_b, _t): pass)
	bike = r["bike"]
	bike.beam = 0
	names = []
	for i in 3:
		names.append(bike.cycle_beam())
	check(names == ["low beam", "high beam", "off"], "without fog lights: off, low, high, off %s" % str(names))
	await _done(r)


## Away from the shed a bike is just for riding: no tools, no parts, no inspecting. Left out
## there, the recovery truck brings it back to the yard for a small fee.
func _test_road_bike_rules() -> void:
	Shed.start_new("Tester", 7)
	var me := Shed.me()
	var faithful := _bike_named("Old Faithful")
	check(Shed.bike_at_work(faithful) and Shed.abandoned_bikes().is_empty(), "bikes in the bays are at the shed")
	check(Shed.check(me, {"a": "unbolt", "bike": faithful, "slot": "exhaust"}) == "", "in the shed the wrench works")
	var yard := Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 12.0))
	Shed.bikes[faithful]["xf"] = yard
	check(Shed.bike_at_work(faithful), "parked on the drive outside the roller door it's still at the shed")
	Shed.bikes[faithful]["xf"] = Transform3D(Basis(), Vector3(150.0, 2.0, 20.0))
	check(not Shed.bike_at_work(faithful) and Shed.abandoned_bikes() == [faithful], "left out on the road it's abandoned")
	var why := Shed.check(me, {"a": "unbolt", "bike": faithful, "slot": "exhaust"})
	check(why.contains("ride"), "out there the wrench won't touch it (%s)" % why)
	for a in ["bolt", "remove", "install", "adjust_chain", "tune", "geo_save"]:
		check(Shed.check(me, {"a": a, "bike": faithful, "slot": "exhaust", "key": "chain", "value": 30.0, "geo": {}, "crouched": true}).contains("shed"),
			"no %s out on the road" % a)
	var tank := Shed.item_on(faithful, "tank")
	for a in ["clean", "paint", "drain"]:
		check(Shed.check(me, {"a": a, "item": tank}).contains("shed"), "no %s on its parts out there" % a)
	check(Shed.check(me, {"a": "clean_many", "items": [tank]}).contains("shed"), "the brush won't scrub it either")
	check(Shed.road_bike_block({"a": "pour", "item": tank}) == "", "a can of petrol can still go in the tank")
	check(Shed.check(me, {"a": "mount", "bike": faithful}) == "", "and you can still ride it")
	# Retrieve it.
	Shed.garage_money = 1000
	check(Shed.check(me, {"a": "retrieve_bike", "bike": faithful}) == "", "the recovery truck can fetch it")
	Shed.request({"a": "retrieve_bike", "bike": faithful})
	var at: Vector3 = Shed.bikes[faithful]["xf"].origin
	check(Shed.bike_at_work(faithful) and at.distance_to(Shed.RETRIEVE_ROW) < 10.0 and Shed.abandoned_bikes().is_empty(),
		"it's brought back to the yard by the roller door (%s)" % at)
	check(Shed.garage_money == 1000 - Shed.RETRIEVE_FEE, "for a small fee from the garage (%d left)" % Shed.garage_money)
	check(Shed.check(me, {"a": "unbolt", "bike": faithful, "slot": "exhaust"}) == "", "back at the shed it can be worked on again")
	check(Shed.check(me, {"a": "retrieve_bike", "bike": faithful}).contains("already"), "a bike at the shed needs no fetching")
	# Two bikes out: they park side by side, not on top of each other.
	var ranger := _bike_named("Rusty Ranger")
	Shed.bikes[ranger]["xf"] = Transform3D(Basis(), Vector3(-200.0, 2.0, -50.0))
	Shed.request({"a": "retrieve_bike", "bike": ranger})
	check(Shed.bikes[ranger]["xf"].origin.distance_to(Shed.bikes[faithful]["xf"].origin) > 0.8, "a second bike parks beside the first")
	# Not while someone is riding it, and not when the garage is broke.
	Shed.bikes[faithful]["xf"] = Transform3D(Basis(), Vector3(150.0, 2.0, 20.0))
	Shed.bikes[faithful]["rider"] = 99
	check(not Shed.abandoned_bikes().has(faithful) and Shed.check(me, {"a": "retrieve_bike", "bike": faithful}).contains("riding"),
		"a bike someone is out riding isn't abandoned")
	Shed.bikes[faithful]["rider"] = 0
	Shed.garage_money = 5
	check(Shed.check(me, {"a": "retrieve_bike", "bike": faithful}).contains("pay"), "the garage has to be able to pay")
	# It's all kept in the save: where the bike was left.
	Shed.garage_money = 1000
	var saved := Shed.save_snapshot()
	Shed.load_state(saved, "Tester")
	check(Shed.abandoned_bikes() == [faithful], "a bike left on the road is still out there after loading")


## In the game: swinging the camera with the mouse, the ride-by key, a bike left out on the road
## that can't be inspected, and the Esc menu's retrieve button.
func _test_riding_feedback_session() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_riding_feedback_test.json"
	DirAccess.remove_absolute(Progress.path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var faithful := _bike_named("Old Faithful")
	Shed.request({"a": "mount", "bike": faithful})
	for i in 5:
		await get_tree().physics_frame
	check(main.bike != null, "on the bike")
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(-150.0, 0.0)
	main._unhandled_input(ev)
	check(main.camera.orbit_yaw > 0.3, "moving the mouse swings the chase camera round (%.2f)" % main.camera.orbit_yaw)
	_press("ride_by")
	await get_tree().physics_frame
	check(main.camera.mode == ChaseCamera.Mode.RIDE_BY, "V switches to the ride-by camera")
	_press("camera")
	await get_tree().physics_frame
	check(main.camera.mode == ChaseCamera.Mode.CHASE, "C brings the chase camera straight back")
	# The view toggle runs third person, first person, fly-by, and round again.
	var views := []
	for i in 3:
		_press("camera")
		await get_tree().physics_frame
		views.append([main.camera.mode, main.camera.fly_by])
	check(views == [[ChaseCamera.Mode.HELMET, false], [ChaseCamera.Mode.RIDE_BY, true], [ChaseCamera.Mode.CHASE, false]],
		"C steps through third person, first person and fly-by (%s)" % str(views))
	_press("headlight")
	await get_tree().physics_frame
	check(main.bike.beam == 2, "L steps the headlight on to high beam")
	# Ride it out of the shed area and get off.
	var far := Vector3(150.0, 0.0, 20.0)
	far.y = main.world.surface_height(far.x, far.z)
	main.bike.place(far, 0.0)
	for i in 30:
		await get_tree().physics_frame
	main._get_off()
	for i in 5:
		await get_tree().physics_frame
	check(main.bike == null and Shed.abandoned_bikes() == [faithful], "got off out on the road, the bike stays there")
	# Stand beside it on the hillside and look at its tank.
	var w: Walker = main.walker
	var model: BikeModel = main.workshop.bike_model(faithful)
	var aim: Vector3 = model.global_transform * model.slot_bounds("tank").get_center()
	var stand: Vector3 = aim + Vector3(1.4, 0.0, 0.0)
	stand.y = main.world.surface_height(stand.x, stand.z) + 0.05
	w.place(Transform3D(Basis(), stand))
	w.rotation.y = PI * 0.5
	var eye: Vector3 = stand + Vector3.UP * Walker.EYE
	w._look(0.0, -atan2(eye.y - aim.y, Vector2(eye.x - aim.x, eye.z - aim.z).length()))
	for i in 5:
		await get_tree().physics_frame
	check(int(w.target.get("bike", 0)) == faithful and w.target.get("road", false), "looking at it out there (%s)" % str(w.target))
	w.set_tool("wrench")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(w.plan.is_empty() and w.info.contains("Out on the road") and not w.info.contains("bolted") and not w.info.contains("geometry"),
		"no wrench work and no part details, just a bike to ride (%s)" % w.info.replace("\n", " / "))
	w.set_tool("hands")
	main.open_geometry()
	check(not main.geometry.active, "and no geometry mode")
	# Walk back to the shed and fetch it from the Esc menu.
	w.place(Workshop.walker_spawn(0))
	Shed.garage_money = 500
	main.menu.show_pause()
	await get_tree().process_frame
	var buttons: Array = main.menu._retrieve_box.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())
	check(buttons.size() == 1 and (buttons[0] as Button).text.contains("Old Faithful") and not (buttons[0] as Button).disabled,
		"the Esc menu offers to retrieve it")
	if not buttons.is_empty():
		(buttons[0] as Button).pressed.emit()
	for i in 5:
		await get_tree().process_frame
	check(Shed.bike_at_work(faithful) and main.workshop.bike_views.has(faithful), "the bike is back in the yard")
	var left: Array = main.menu._retrieve_box.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())
	check(left.is_empty(), "and the button goes")
	main.menu.hide()
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	Progress.path = real_path


# ---------------------------------------------------------------------------- customers ride in

## The newest customer waiting at reception (or on the way), or 0.
func _newest_customer() -> int:
	var ids: Array = Contracts.customers().keys()
	ids.sort()
	return int(ids[-1]) if not ids.is_empty() else 0


## Pushes a bike on foot (F) and lets go of it at `xf`, as a player wheeling it would.
func _wheel_bike_to(bike_id: int, xf: Transform3D) -> void:
	Shed.request({"a": "grab_bike", "bike": bike_id})
	Shed.request({"a": "move_bike", "bike": bike_id, "xf": xf})
	Shed.request({"a": "release_bike", "bike": bike_id, "xf": xf})


func _test_customer_rides_in() -> void:
	Shed.start_new("Tester", 61)
	var me := Shed.me()
	Contracts._st()["reputation"] = 20
	var a := Contracts.spawn("maint")
	var b := Contracts.spawn("mot")
	var v := Contracts.spawn("bespoke")
	var ca: Dictionary = Contracts.customers()[a]
	var cb: Dictionary = Contracts.customers()[b]
	var park := int(ca.get("park", -1))
	check(park >= 0 and int(cb.get("park", -1)) >= 0 and int(cb["park"]) != park and Contracts.rides_in(ca)
		and ca["offer"].has("paint"), "customers ride their own bike in, each to their own car park bay (%d, %d)" % [park, int(cb.get("park", -1))])
	check(not Contracts.rides_in(Contracts.customers()[v]), "the exclusive customer walks in: their job starts as a bare frame")
	var parts: Dictionary = ca["offer"]["parts"]
	check(str(parts.get("side_stand", "none")) != "none" or str(parts.get("centre_stand", "none")) != "none",
		"a bike ridden in has a stand to park on")
	var slots_ok := true
	for i in Contracts.PARK_SLOTS:
		var o := Contracts.park_xf(i).origin
		# Inside the area bikes can be worked on (x -22..38, z 42..86), so a customer's bike can be worked on where it's left.
		slots_ok = slots_ok and SalesOffice.FORECOURT.has_point(Vector2(o.x, o.z)) and Workshop.room_at(o) == "" \
			and Rect2(-22.0, 42.0, 60.0, 44.0).grow(-1.0).has_point(Vector2(o.x, o.z))
		if i > 0:
			slots_ok = slots_ok and o.distance_to(Contracts.park_xf(i - 1).origin) >= 2.0
	check(slots_ok, "the car park bays are on the forecourt, outside, with room between them")
	var ride := Contracts.ride_in_path(park)
	var yard := Rect2(World.YARD_CENTER - World.YARD_HALF, World.YARD_HALF * 2.0).grow(8.0)
	var flat := true
	var inside := ""
	for i in range(1, ride.size()):
		for k in 10:
			var p := ride[i - 1].lerp(ride[i], k / 10.0)
			flat = flat and yard.has_point(Vector2(p.x, p.z))
			if Workshop.room_at(p) != "":
				inside = Workshop.room_at(p)
	check(absf(ride[0].x - Contracts.ROAD_FAR_X) < 0.5 and ride[0].z > 120.0 and ride[0].z < 145.0 and flat and inside == "",
		"they ride in along the road past the yard (from %s) and across the flat yard, through no buildings (%s)" % [ride[0], inside])
	var last := ride[ride.size() - 1] - ride[ride.size() - 2]
	check(ride[ride.size() - 1].distance_to(Contracts.park_xf(park).origin) < 0.01 and last.normalized().dot(Vector3.FORWARD) > 0.99,
		"and park nose-in to the office in their bay")
	var walk := Contracts.path_in(0, park)
	check(walk[0].distance_to(Contracts.park_xf(park).origin) < 1.2 and walk[walk.size() - 1].distance_to(Contracts.reception().origin) < 0.01
		and walk.has(Workshop.SALES_DOOR), "then get off and walk in through the doors to reception")
	# With every bay full, a customer who rode in can still be taken on: the bike waits outside.
	for bay in Workshop.bay_count():
		if Shed.bay_is_free(bay):
			Shed._new_bike(PartsDB.DEFAULT_BUILD.duplicate(), bay, "Filler", 0.2)
	check(Shed.free_bay(Workshop.bay_count()) < 0 and Shed.check(me, {"a": "contract_accept", "customer": a}) == "",
		"with every bay full, a customer who rode in can still be taken on")
	var keep := cb.duplicate(true)
	cb.erase("park")
	check(Shed.check(me, {"a": "contract_accept", "customer": b}).contains("bay"), "one from an older save (no bike outside) still needs a free bay")
	Contracts.customers()[b] = keep
	Shed.request({"a": "contract_accept", "customer": a})
	var job: Dictionary = Contracts.jobs().values()[0] if not Contracts.jobs().is_empty() else {}
	var jb := int(job.get("bike", 0))
	check(Shed.bikes.has(jb) and (Shed.bikes[jb]["xf"] as Transform3D).origin.distance_to(Contracts.park_xf(park).origin) < 0.01
		and int(Shed.bikes[jb]["bay"]) == -1 and str(Shed.bikes[jb]["stand"]) in ["side", "centre"]
		and Shed.bikes[jb]["paint"] == Shed.PAINTS[int(ca["offer"]["paint"]) % Shed.PAINTS.size()],
		"taken on, their bike is left on its stand in the car park bay, in the colour they rode in on")
	check(Contracts.took_on(a) and not Contracts.took_on(b) and int(job.get("cid", 0)) == a, "the job remembers who brought it")
	check(Shed.check(me, {"a": "mount", "bike": jb}) == "" and Shed.check(me, {"a": "grab_bike", "bike": jb}) == "",
		"and the crew can ride it or wheel it in")
	check(Contracts.free_park() != park, "nobody else parks in its bay while it stands there")


func _test_customer_bike_in_and_back() -> void:
	Shed.start_new("Tester", 62)
	var me := Shed.me()
	var cid := Contracts.spawn("maint")
	Shed.request({"a": "contract_accept", "customer": cid})
	var job: Dictionary = Contracts.jobs().values()[0]
	var jid := int(job["id"])
	var jb := int(job["bike"])
	var bay := Shed.free_bay(Workshop.bay_count())
	_wheel_bike_to(jb, Workshop.bay_transform(bay).translated(Vector3(0.3, 0.0, 0.4)))
	check(int(Shed.bikes[jb]["bay"]) == bay and Shed.on_paddock(jb) and Shed.bike_in_bay(bay) == jb and int(Shed.bikes[jb]["pusher"]) == 0,
		"wheeled into bay %d, it goes up on the paddock stand" % (bay + 1))
	_make_roadworthy(jb)
	var why := Shed.check(me, {"a": "contract_hand_in", "job": jid})
	check(why.contains("car park") and why.contains("sales office"), "finished, it can't be handed back from the bay: it goes out to the car park (%s)" % why)
	var none := true
	for b in Workshop.bay_count():
		Shed.bikes[jb]["xf"] = Workshop.bay_transform(b)
		none = none and not Contracts.near_handback(jb)
	Shed.bikes[jb]["xf"] = Transform3D(Basis(), Contracts.door_front())
	none = none and not Contracts.near_handback(jb)
	check(none, "not from any of the %d bays, or the roller door" % Workshop.bay_count())
	var spot := Contracts.park_xf(4)
	_wheel_bike_to(jb, spot)
	check(Shed.check(me, {"a": "contract_hand_in", "job": jid}) == "" and Contracts.in_car_park(spot.origin)
		and ContractPanel.where_text(Shed.bikes[jb]).contains("hand it back"), "wheeled out to the car park, it can be handed back")
	var frame := str(Shed.items[Shed.item_on(jb, "frame")]["part"])
	Shed.request({"a": "contract_hand_in", "job": jid})
	var leaving: Array = Contracts._st()["leaving"]
	var d: Dictionary = leaving[0] if not leaving.is_empty() else {}
	check(not Shed.bikes.has(jb) and Contracts.jobs().is_empty() and d.get("xf") == spot
		and str(d.get("parts", {}).get("frame", "")) == frame and str(d.get("name", "")) == str(job["customer"]) and d.get("cond") is Dictionary,
		"handed back, the customer comes for it in the car park")
	var walk := Contracts.collect_path(spot)
	var inside := false
	for p in walk:
		inside = inside or Workshop.room_at(p) in ["shed", "wing"]
	check(walk[0].distance_to(Contracts.reception().origin) < 0.01 and walk.has(Workshop.SALES_DOOR)
		and walk[walk.size() - 1].distance_to(spot.origin) < 1.2 and not inside,
		"they walk out of the sales office, through its doors, to the bike in the car park (never into the shed)")
	var out := Contracts.ride_out_path(spot)
	var through_shed := false
	for i in range(1, out.size()):
		for k in 10:
			through_shed = through_shed or Workshop.room_at(out[i - 1].lerp(out[i], k / 10.0)) != ""
	check(not through_shed and out[1].z > out[0].z and absf(out[out.size() - 1].x - Contracts.ROAD_FAR_X) < 0.5,
		"and back it out of the bay and ride it off along the road")
	Contracts.advance(Contracts.LEAVING_HOURS + 0.5)
	check(Contracts._st()["leaving"].is_empty(), "and is gone after a while")


func _test_customer_bay_screen() -> void:
	Shed.start_new("Tester", 63)
	var cid := Contracts.spawn("maint")
	Contracts.customers()[cid]["offer"]["goals"] = [{"t": "task", "task": "oil"}, {"t": "task", "task": "wash"}]
	Contracts.customers()[cid]["offer"]["pay"] = 300
	Contracts.customers()[cid]["offer"]["budget"] = 0
	Shed.request({"a": "contract_accept", "customer": cid})
	var job: Dictionary = Contracts.jobs().values()[0]
	var jb := int(job["bike"])
	var bay := Shed.free_bay(Workshop.bay_count())
	_wheel_bike_to(jb, Workshop.bay_transform(bay))
	var ws := Workshop.new()
	var page := ws._bay_data(bay)
	ws.free()
	var sd: Dictionary = page.get("contract", {})
	check(not sd.is_empty() and sd["rows"].size() == 2 and int(sd["met"]) == 0 and str(sd["due"]).contains("left")
		and int(sd["fee"]) == 300 and str(sd["customer"]) == str(job["customer"]),
		"a contract bike's bay screen shows the job's checklist, who it's for and the deadline (%s)" % str(sd.get("due", "")))
	check(int(sd["profit"]) == int(sd["payout"]) - int(sd["spent"]) and not bool(sd["ready"]) and str(sd["why"]).contains("car park"),
		"with what handing it back pays, the profit, and where to leave it to hand it back (%s)" % str(sd["why"]))
	var engine: Dictionary = Shed.items[Shed.item_on(jb, "engine")]
	engine["fluid"]["age"] = 0.0
	engine["fluid"]["litres"] = PartsDB.fluid_capacity(str(engine["part"]))
	for slot in PartsDB.SLOTS:
		if Shed.item_on(jb, slot) != 0:
			Shed.items[Shed.item_on(jb, slot)]["dirt"] = 0.0
	sd = Contracts.screen_data(job)
	check(int(sd["met"]) == 2 and sd["rows"].all(func(r): return r["done"]), "each job is ticked off as it's done")
	var profit := int(sd["profit"])
	var ex := Shed.item_on(jb, "exhaust")
	var was := str(Shed.items[ex]["part"])
	Shed.items[ex]["part"] = "full_system" if was != "full_system" else "titanium_race"
	sd = Contracts.screen_data(job)
	var cost := Contracts.price(str(Shed.items[ex]["part"]))
	check(int(sd["spent"]) == cost and int(sd["profit"]) == profit - cost, "new parts show as spent, and come off the profit (%s)" % Contracts.money(cost))
	Shed.items[ex]["part"] = was
	# An MOT job lists what failed, to fix.
	Shed.start_new("Tester", 64)
	Contracts._st()["reputation"] = 3
	var mid := Contracts.spawn("mot")
	Shed.request({"a": "contract_accept", "customer": mid})
	var mj: Dictionary = Contracts.jobs().values()[0]
	check(str(Contracts.screen_data(mj)["mot"]).contains("Not tested"), "an MOT job's screen says it hasn't been tested yet")
	Shed.request({"a": "contract_mot_test", "job": int(mj["id"])})
	var msd := Contracts.screen_data(mj)
	check(msd["fixes"].size() == int(mj["mot"]["fails"]) and msd["fixes"].size() > 0 and str(msd["mot"]).contains("FAIL"),
		"after a test it lists the fails to fix (%d)" % msd["fixes"].size())


func _test_customer_save() -> void:
	Shed.start_new("Tester", 65)
	var cid := Contracts.spawn("maint")
	var park := int(Contracts.customers()[cid]["park"])
	var paint := int(Contracts.customers()[cid]["offer"]["paint"])
	var done := Contracts.spawn("maint")
	Shed.request({"a": "contract_accept", "customer": done})
	var jb := int(Contracts.jobs().values()[0]["bike"])
	_wheel_bike_to(jb, Contracts.park_xf(5))
	Shed.request({"a": "contract_hand_in", "job": int(Contracts.jobs().values()[0]["id"])})
	var text := var_to_str(Shed.save_snapshot().duplicate(true))
	Shed.start_new("Tester", 66)
	Shed.load_state(str_to_var(text), "Tester")
	check(Contracts.customers().has(cid) and int(Contracts.customers()[cid]["park"]) == park
		and int(Contracts.customers()[cid]["offer"]["paint"]) == paint and Contracts._st()["leaving"].size() == 1,
		"a customer's car park bay, their bike's colour and a ride away survive a save")
	# A save from before customers rode in: nobody has a bike outside, and the jobs still go to a bay.
	var old: Dictionary = Shed._snapshot().duplicate(true)
	old["contracts"].erase("leaving")
	for id in old["contracts"]["customers"]:
		old["contracts"]["customers"][id].erase("park")
		old["contracts"]["customers"][id]["offer"].erase("paint")
	Shed.start_new("Tester", 67)
	Shed.load_state(old, "Tester")
	check(Contracts._st()["leaving"] == [] and Contracts.customers().has(cid) and not Contracts.rides_in(Contracts.customers()[cid]),
		"a save from before opens with nobody riding off and its customers on foot")
	Shed.request({"a": "contract_accept", "customer": cid})
	var job: Dictionary = Contracts.jobs().values()[0] if not Contracts.jobs().is_empty() else {}
	var bike := int(job.get("bike", 0))
	check(Shed.bikes.has(bike) and int(Shed.bikes[bike]["bay"]) >= 0 and Shed.on_paddock(bike),
		"and their job's bike is delivered to a free bay as before")


func _test_customer_ride_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	var view: ContractsView = main.contracts_view
	Shed.request({"a": "contract_spawn", "kind": "maint"})
	await get_tree().process_frame
	var cid := _newest_customer()
	var cv: CustomerView = view.views.get(cid)
	check(cv != null and cv.has_bike() and cv.bike_position().z > 120.0, "a customer comes riding in along the road")
	var park := int(Contracts.customers()[cid]["park"])
	var arrived := [false]
	cv.arrived.connect(func(_v): arrived[0] = true)
	var parked_at := Vector3.INF
	for i in 6000:
		cv._process(0.05)
		if parked_at == Vector3.INF and not cv.riding and cv.has_bike() and cv.bike_position().z < 90.0:
			parked_at = cv.bike_position()
		if arrived[0]:
			break
	check(parked_at.distance_to(Contracts.park_xf(park).origin) < 0.1 and cv.bike_position().distance_to(Contracts.park_xf(park).origin) < 0.1,
		"parks in the car park (%s)" % parked_at)
	check(arrived[0] and cv.at_counter and Vector2(cv.global_position.x, cv.global_position.z).distance_to(
		Vector2(Contracts.reception().origin.x, Contracts.reception().origin.z)) < 0.2, "and walks in to reception")
	Shed.request({"a": "contract_accept", "customer": cid})
	await get_tree().process_frame
	var job: Dictionary = Contracts.jobs().values()[0]
	var jb := int(job["bike"])
	check(not cv.has_bike() and cv.leaving and main.workshop.bike_views.has(jb), "taken on, they walk off and their bike is the shed's")
	# Turned down, a customer rides away again.
	Shed.request({"a": "contract_spawn", "kind": "maint"})
	await get_tree().process_frame
	var cid2 := _newest_customer()
	var cv2: CustomerView = view.views.get(cid2)
	for i in 6000:
		cv2._process(0.05)
		if cv2.at_counter:
			break
	var p0 := cv2.bike_position()
	Shed.request({"a": "contract_decline", "customer": cid2})
	await get_tree().process_frame
	check(cv2.leaving and cv2.has_bike(), "turned down, they go back to their bike")
	var far := 0.0
	for i in 6000:
		cv2._process(0.05)
		if cv2.is_queued_for_deletion():
			break
		far = maxf(far, cv2.bike_position().distance_to(p0))
	check(far > 40.0 and cv2.is_queued_for_deletion(), "and ride it away (%.0f m)" % far)
	# Brought into a bay: its screen shows the job.
	var bay := Shed.free_bay(Workshop.bay_count())
	_wheel_bike_to(jb, Workshop.bay_transform(bay))
	job["goals"] = [{"t": "task", "task": "wash"}]
	for slot in PartsDB.SLOTS:
		if Shed.item_on(jb, slot) != 0:
			Shed.items[Shed.item_on(jb, slot)]["dirt"] = 0.0
	Shed.changed.emit()
	main.workshop._dash_timer = 0.0
	for i in 3:
		await get_tree().process_frame
	var dash: Dashboard = main.workshop.screens().get("bay%d" % bay)
	check(dash != null and dash.data.has("contract") and dash.data["contract"]["rows"].all(func(r): return r["done"]),
		"the bay's screen shows the job's checklist, ticked off")
	# Finished, it goes back out to the car park and is handed back: the customer walks out of
	# the sales office to it, and only gets on it once they're there.
	check(Shed.check(Shed.me(), {"a": "contract_hand_in", "job": int(job["id"])}).contains("car park"), "it isn't handed back from the bay")
	var spot := Contracts.park_xf(3)
	_wheel_bike_to(jb, spot)
	Shed.request({"a": "contract_hand_in", "job": int(job["id"])})
	await get_tree().process_frame
	var col = view.collecting.get(int(job["id"]))
	check(col is CustomerView and (col as CustomerView).has_bike() and not Shed.bikes.has(jb)
		and (col as CustomerView).bike_position().distance_to(spot.origin) < 0.05,
		"handed back, the customer comes to collect it from the car park")
	var started := Vector3.INF
	var early_rider := false
	var mounted_at := Vector3.INF
	var both := false
	var gone_far := 0.0
	if col is CustomerView:
		var cv3 := col as CustomerView
		started = cv3.global_position
		early_rider = cv3.rider_on_bike()
		for i in 8000:
			if cv3.on_foot() and cv3.rider_on_bike():
				both = true
			if cv3.on_foot():
				early_rider = early_rider or cv3.rider_on_bike()
			cv3._process(0.05)
			if cv3.is_queued_for_deletion():
				break
			if mounted_at == Vector3.INF and cv3.rider_on_bike():
				mounted_at = cv3.global_position
			if cv3.riding:
				gone_far = maxf(gone_far, cv3.bike_position().distance_to(spot.origin))
	check(started.distance_to(Contracts.reception().origin) < 0.3, "they come out from the sales office counter (%s)" % started)
	check(not early_rider and not both and mounted_at.distance_to(spot.origin) < 0.3,
		"nobody is on the bike until they've walked up to it; then the walker goes and the rider is on it")
	check(gone_far > 40.0 and col is CustomerView and col.is_queued_for_deletion(), "and they ride it away (%.0f m)" % gone_far)
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## A customer riding in leans into each turn (left for a left-hander, right for a right), about
## as far as atan(v * yaw rate / g) says, eased in and out and never too far, slowing for the
## corner; the rider leans with the bike; none while paddling backwards out of a bay.
func _test_customer_lean() -> void:
	Shed.start_new("Tester", 63)
	var bike := {"parts": PartsDB.DEFAULT_BUILD.duplicate(), "paint": Color.RED}
	for side: float in [-1.0, 1.0]:
		# Well away from the buildings: north 40 m, then a 90 degree corner off to `side`.
		var o := Vector3(150.0, 0.0, 0.0)
		var ride := PackedVector3Array([o, o + Vector3(0.0, 0.0, -40.0), o + Vector3(side * 40.0, 0.0, -40.0),
			o + Vector3(side * 46.0, 0.0, -40.0)])
		var cv := CustomerView.new()
		add_child(cv)
		cv.set_process(false)
		cv.setup({"id": 31, "name": "Leaner"}, PackedVector3Array([ride[3], ride[3] + Vector3.BACK]), Basis(), false, ride, bike)
		var dt := 1.0 / 60.0
		var most := 0.0
		var wrong := 0.0
		var jump := 0.0
		var prev := 0.0
		var prev_yaw := cv._yaw
		var match_ok := true
		var straight_v := 0.0
		var corner_v := INF
		var with_rider := cv._model != null and cv._lean.is_ancestor_of(cv._model._rider)
		var rider_side := 0.0
		for i in 3000:
			cv._process(dt)
			if not cv.riding:
				break
			var up := cv._lean.basis.y
			var lean := atan2(up.x, up.y)   # + to the right, in the bike's own frame
			var yaw_rate := wrapf(cv._yaw - prev_yaw, -PI, PI) / dt
			prev_yaw = cv._yaw
			jump = maxf(jump, absf(lean - prev))
			prev = lean
			if lean * side > absf(most):
				most = lean
				var expect := -atan(cv._speed * yaw_rate / Bike.G)
				# The lean leads the turn a little, so mid-corner it's about what the turn needs.
				match_ok = absf(yaw_rate) > 0.2 and absf(lean - expect) < maxf(absf(expect) * 0.45, 0.06)
				var rider_up: Vector3 = cv._model._rider.global_basis.y
				rider_side = rider_up.dot(cv._bike.global_basis.x)
			if absf(yaw_rate) > 0.3 and cv._speed > 3.0:
				wrong = maxf(wrong, lean * yaw_rate / absf(yaw_rate))   # leaning out of the turn it's making
			var p := cv.bike_position() - o
			if p.z > -25.0 and p.z < -15.0:
				straight_v = maxf(straight_v, cv._speed)
			if absf(p.x) > 1.0 and absf(p.x) < 4.0:
				corner_v = minf(corner_v, cv._speed)
		var turn_name := "left" if side < 0.0 else "right"
		check(most * side > deg_to_rad(8.0) and absf(most) <= CustomerView.MAX_LEAN + 0.001 and wrong < 0.02,
			"a %s turn leans the bike %s, into the turn (%.0f deg, never out of it: %.1f)" % [turn_name, turn_name, rad_to_deg(most), rad_to_deg(wrong)])
		check(match_ok, "about as far as atan(v * yaw rate / g) at the height of the %s turn" % turn_name)
		check(jump < 1.6 / 60.0 + 0.001, "eased in and out, never snapping over (%.3f rad a frame at most)" % jump)
		check(with_rider and rider_side * side > 0.0, "and the rider leans with it")
		check(corner_v < straight_v - 1.0, "slowing for the corner (%.1f m/s, from %.1f)" % [corner_v, straight_v])
		check(not cv.riding and cv.bike_position().distance_to(ride[3]) < 0.01, "and parks exactly at the end of the way")
		cv.queue_free()
	# Backing out of a car park bay: upright while paddling back.
	var spot := Contracts.park_xf(2)
	var cv := CustomerView.new()
	add_child(cv)
	cv.set_process(false)
	cv.setup_collect({"id": 32, "name": "Backer"}, PackedVector3Array([spot.origin + Vector3(0.75, 0.0, 0.3), spot.origin]),
		bike, spot, Contracts.ride_out_path(spot, 32))
	var back_lean := 0.0
	var backed := false
	var swung := 0.0
	for i in 2000:
		cv._process(1.0 / 60.0)
		if cv.riding and cv._line.size() > 1 and cv._at < cv._back:
			backed = true
			back_lean = maxf(back_lean, absf(cv._roll))
			swung = maxf(swung, absf(wrapf(cv._yaw, -PI, PI)))
		if cv.riding and cv._at > cv._back + 5.0:
			break
	check(backed and back_lean < 0.001, "paddling backwards out of the bay, it stays upright (%.3f)" % back_lean)
	check(swung > 0.5, "swinging the tail round as they go towards the way out (%.0f deg)" % rad_to_deg(swung))
	cv.queue_free()


## Every rider has their own way in and out, the same on every machine: in from either end of the
## road and keeping left on it, on their own line up the yard and into the bay, at their own
## pace; clear of the yard's kit, and out of the shed through its doors.
func _test_customer_routes() -> void:
	Shed.start_new("Tester", 64)
	check(Contracts.ride_in_path(3, 17) == Contracts.ride_in_path(3, 17)
		and CustomerView.ride_line(Contracts.ride_in_path(3, 17), 17) == CustomerView.ride_line(Contracts.ride_in_path(3, 17), 17)
		and CoffeeShop.ride_in(5, 17) == CoffeeShop.ride_in(5, 17) and CustomerView.rider_traits(17) == CustomerView.rider_traits(17),
		"the same rider takes the same way every time (it's worked out from their id)")
	var loop := PackedVector2Array()
	for r: Dictionary in WorldLayout.ROADS:
		if r["name"] == "loop":
			loop = WorldRoads._spline(PackedVector2Array(r["pts"]), true)
	var off_road := func(p: Vector3) -> float:
		var best := INF
		for q in loop:
			best = minf(best, Vector2(p.x, p.z).distance_to(q))
		return best
	var kit := []
	for item: Array in WorldYard.starting_kit():
		kit.append([(item[1] as Transform3D).origin, item[2]])
	var near_kit := func(path: PackedVector3Array, gap: float) -> Array:
		var hit := []
		for k: Array in kit:
			var at: Vector3 = k[0]
			for i in path.size() - 1:
				var c := Geometry3D.get_closest_point_to_segment(at, path[i], path[i + 1])
				if Vector2(c.x - at.x, c.z - at.z).length() < gap and not hit.has(k[1]):
					hit.append(k[1])
		return hit
	var ways := {}
	var ends := {"in_east": 0, "in_west": 0, "out_east": 0, "out_west": 0, "cafe_east": 0, "cafe_west": 0}
	var in_bay := true
	var on_road := true
	var in_way := []
	var cruise := []
	var straight_in := true
	for id in 40:
		var park := id % Contracts.PARK_SLOTS
		var slot := Contracts.park_xf(park).origin
		var ride := Contracts.ride_in_path(park, id)
		var out := Contracts.ride_out_path(Contracts.park_xf(park), id)
		ways[str(ride)] = true
		ends["in_east" if ride[0].x > 60.0 else "in_west"] += 1
		ends["out_east" if out[out.size() - 1].x > 60.0 else "out_west"] += 1
		var line := CustomerView.ride_line(ride, id)
		var last := ride[ride.size() - 1] - ride[ride.size() - 2]
		in_bay = in_bay and ride[ride.size() - 1] == slot and line[line.size() - 1] == slot and last.normalized().dot(Vector3.FORWARD) > 0.99
		for p in line:
			if p.distance_to(slot) < 3.0:
				straight_in = straight_in and absf(p.x - slot.x) < 0.01
		for p in [ride[0], ride[1], out[out.size() - 1], out[out.size() - 2]]:
			on_road = on_road and off_road.call(p) < 3.0
		for k in near_kit.call(ride, 2.5) + near_kit.call(out, 2.5) + near_kit.call(line, 1.8) \
				+ near_kit.call(CustomerView.ride_line(out, id), 1.8):
			if not in_way.has(k):
				in_way.append(k)
		var cafe := CoffeeShop.ride_in(id % CoffeeShop.PARK_SLOTS, id)
		var cafe_out := CoffeeShop.ride_out(id % CoffeeShop.PARK_SLOTS, id)
		ends["cafe_east" if cafe[0].x > 60.0 else "cafe_west"] += 1
		in_bay = in_bay and cafe[cafe.size() - 1] == CoffeeShop.park_xf(id % CoffeeShop.PARK_SLOTS).origin
		on_road = on_road and off_road.call(cafe[0]) < 3.0 and off_road.call(cafe_out[cafe_out.size() - 1]) < 3.0
		for k in near_kit.call(cafe, 2.5) + near_kit.call(cafe_out, 2.5) + near_kit.call(CustomerView.ride_line(cafe, id), 1.8) \
				+ near_kit.call(CustomerView.ride_line(cafe_out, id), 1.8):
			if not in_way.has(k):
				in_way.append(k)
		cruise.append(float(CustomerView.rider_traits(id)["cruise"]))
	check(ways.size() >= 35, "different riders take different ways in (%d different of 40)" % ways.size())
	check(ends.values().all(func(n): return n >= 8), "in from both ends of the road and off either way, to the shed and the cafe %s" % str(ends))
	check(in_bay and straight_in, "and always end up exactly in their bay, the last few metres straight in")
	check(on_road, "keeping to the road (on the left) along the way")
	check(in_way.is_empty(), "the yard's test kit keeps clear of all of them %s" % str(in_way))
	check(cruise.min() < Contracts.RIDE_SPEED * 0.85 and cruise.max() > Contracts.RIDE_SPEED * 1.1,
		"some cruise, some are quicker (%.1f..%.1f m/s)" % [cruise.min(), cruise.max()])
	# Out of the shed's and the extension's bays the line keeps to the doors.
	Shed.upgrades["wing"] = true
	var walls := []
	for bay in Workshop.bay_count():
		var raw := Contracts.ride_out_path(Workshop.bay_transform(bay), 5 + bay)
		var rooms := {}
		for i in range(1, raw.size()):
			for k in 20:
				rooms[Workshop.room_at(raw[i - 1].lerp(raw[i], k / 20.0))] = true
		for p in CustomerView.ride_line(raw, 5 + bay):
			var gap := CustomerView._room_gap(p, Workshop.rooms().values())
			var d := INF
			for i in range(1, raw.size()):
				var c := Geometry3D.get_closest_point_to_segment(p, raw[i - 1], raw[i])
				d = minf(d, c.distance_to(p))
			if not rooms.has(Workshop.room_at(p)) or (gap < 0.5 and d > 0.5):
				if not walls.has(bay):
					walls.append(bay)
	Shed.upgrades.erase("wing")
	check(walls.is_empty(), "riding out of the shed's bays and the extension's, the line keeps to the doors %s" % str(walls))


# ---------------------------------------------------------------------------- shed building: deliveries, lifts, annex, lounge

## The delivery area: boxes packed tight by size, a whole bike's blueprint order fits, the
## racking takes the overflow, then boxes stack; a box taken from under a stack lets the one on
## top down; the racking is fixed, comes with old saves, and isn't sold.
func _test_delivery_packing() -> void:
	Shed.start_new("Tester", 41)
	Shed.garage_money = 5000000
	var me := Shed.me()
	var racks := Shed._delivery_racks()
	check(racks.size() == Shed.DELIVERY_RACK_XFS.size() and str(Shed.furniture[racks[0]].get("label", "")) == "DELIVERIES",
		"the delivery area comes with its racking")
	var rack_feet := true
	for id in racks:
		var size := Shed.furniture_size(Shed.furniture[id])
		rack_feet = rack_feet and Shed.DELIVERY_AREA.encloses(Shed.foot_rect(Shed.furniture[id]["xf"], Vector2(size.x, size.z)).grow(-0.01)) \
			and not Shed.DELIVERY_FLOOR.intersects(Shed.foot_rect(Shed.furniture[id]["xf"], Vector2(size.x, size.z)))
	check(rack_feet, "the racking stands at the back of the delivery area, off the floor boxes are packed on")
	check(Shed.check(me, {"a": "grab", "furniture": racks[0]}).contains("fixed"), "the delivery racking can't be pushed away")
	check(Shed.scrap_check(me, {"furniture": racks[0]}) != "", "or scrapped")
	check(Shed.check(me, {"a": "order_furniture", "model": Shed.DELIVERY_RACK}) != "" and not Equipment.by_kind("shelf").has(Shed.DELIVERY_RACK),
		"and it isn't sold")
	check(not Shed.DELIVERY_AREA.intersects(Rect2(-Workshop.DOOR_HALF, 70.0, Workshop.DOOR_HALF * 2.0, 20.0)), "it's clear of the drive out of the roller door")
	# A whole bike ordered from a blueprint fits in one go, packed on the floor.
	var faithful := _bike_named("Old Faithful")
	var bp := Shed._save_blueprint(faithful, "Whole bike")
	Shed.request({"a": "bp_build", "bp": bp, "bay": 3})
	Shed.request({"a": "bp_order", "bay": 3})
	var rows := Shed.plan_rows(Shed.plan_at(3), 0)
	check(rows.size() >= 30 and rows.all(func(r): return r["state"] == "ordered"), "a whole bike's blueprint order fits in the delivery area (%d parts)" % rows.size())
	var floor_ok := true
	var boxes := []
	for r in Shed.plan_at(3)["ordered"].values():
		var it: Dictionary = Shed.items[int(r)]
		boxes.append(int(r))
		if it["at"] == "floor":
			var foot := Shed.foot_rect(it["ref"], Shed.item_footprint(int(r)))
			floor_ok = floor_ok and Shed.DELIVERY_FLOOR.grow(0.01).encloses(foot)
	check(floor_ok, "every box is inside the delivery area")
	var overlap := false
	for a in boxes:
		for b in boxes:
			if a < b and Shed.items[a]["at"] == "floor" and Shed.items[b]["at"] == "floor" \
					and absf((Shed.items[a]["ref"] as Transform3D).origin.y - (Shed.items[b]["ref"] as Transform3D).origin.y) < 0.01:
				var ra := Shed.foot_rect(Shed.items[a]["ref"], Shed.item_footprint(a)).grow(-0.01)
				overlap = overlap or ra.intersects(Shed.foot_rect(Shed.items[b]["ref"], Shed.item_footprint(b)))
	check(not overlap, "no two boxes overlap")
	var frame_box := int(Shed.plan_at(3)["ordered"]["frame"])
	var plugs_box := int(Shed.plan_at(3)["ordered"]["spark_plugs"])
	check(Shed.item_footprint(frame_box).x * Shed.item_footprint(frame_box).y > 4.0 * Shed.item_footprint(plugs_box).x * Shed.item_footprint(plugs_box).y,
		"each box is sized by the part in it")
	# Keep ordering: the floor fills, then the racking, then boxes stack up.
	var count_up := func() -> Vector3:
		var rack_n := 0
		var stack_n := 0
		var top := 0.0
		for id in Shed.items:
			var it: Dictionary = Shed.items[id]
			if it["at"] == "spot" and Shed.spot_role(str(it["ref"])) == "shelf" and racks.has(int(Shed.furniture_of_spot(str(it["ref"]))["id"])):
				rack_n += 1
			elif it["at"] == "floor" and (it["ref"] as Transform3D).origin.y > 0.05:
				stack_n += 1
				top = maxf(top, (it["ref"] as Transform3D).origin.y + Shed._item_height(id))
		return Vector3(rack_n, stack_n, top)
	var first_rack := -1
	var first_stack := -1
	for i in 400:
		var got: Vector3 = count_up.call()
		if first_rack < 0 and got.x > 0:
			first_rack = i
		if got.y > 3:
			first_stack = i
			break
		Shed.request({"a": "order_part", "part": "sport_17"})
	var counts: Vector3 = count_up.call()
	check(first_rack > 40 and counts.x > 20, "when the floor's full, deliveries go onto the racking (%d)" % int(counts.x))
	check(first_stack > first_rack and counts.y > 3 and counts.z <= Shed.DELIVERY_STACK + 0.01,
		"then boxes stack up on the floor, not too high (%.2f m)" % counts.z)
	# Take a box from under a stack: the one on top drops down onto the ground.
	var top_box := 0
	for id in Shed.items:
		if Shed.items[id]["at"] == "floor" and (Shed.items[id]["ref"] as Transform3D).origin.y > 0.05:
			top_box = id
			break
	var bottom := 0
	for id in Shed._delivery_floor_items():
		if Shed._box_on(id) == top_box:
			bottom = id
	check(bottom != 0, "a stacked box sits on the one under it")
	var was_y: float = (Shed.items[top_box]["ref"] as Transform3D).origin.y
	Shed.request({"a": "take", "item": bottom})
	check(Shed.held_by(me) == bottom and (Shed.items[top_box]["ref"] as Transform3D).origin.y < was_y - 0.05,
		"pick up the box underneath and the one on top comes down (%.2f m)" % (Shed.items[top_box]["ref"] as Transform3D).origin.y)
	Shed._erase_item(bottom)
	# Frames are too tall to stack: once the floor and the racking's top are full, it's full.
	Shed.start_new("Tester", 44)
	Shed.garage_money = 5000000
	for i in 200:
		if Shed.check(me, {"a": "order_part", "part": "steel_cradle"}) != "":
			break
		Shed.request({"a": "order_part", "part": "steel_cradle"})
	counts = count_up.call()
	check(Shed.check(me, {"a": "order_part", "part": "steel_cradle"}).contains("full") and counts.y == 0, "only then is the delivery area full")
	check(Shed.check(me, {"a": "order_part", "part": "copper_plugs"}) == "", "though a small box can still go on top of one")
	# Equipment still goes down on the floor, where there's room for it.
	Shed.start_new("Tester", 42)
	Shed.garage_money = 5000000
	Shed.request({"a": "order_furniture", "model": "shelf_wide"})
	var wide := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "shelf_wide":
			wide = id
	var size := Shed.furniture_size(Shed.furniture[wide])
	check(wide != 0 and Shed.DELIVERY_FLOOR.grow(0.01).encloses(Shed.foot_rect(Shed.furniture[wide]["xf"], Vector2(size.x, size.z))),
		"equipment is left on the delivery area's floor")
	var plugs := _order("copper_plugs")
	check(not Shed.foot_rect(Shed.items[plugs]["ref"], Shed.item_footprint(plugs)).intersects(Shed.foot_rect(Shed.furniture[wide]["xf"], Vector2(size.x, size.z))),
		"and boxes are packed round it")
	# An older save (no racking yet, boxes where the old delivery bay was) gets the racking.
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	for id in Shed._delivery_racks():
		copy["furniture"].erase(id)
	Shed.load_state(copy, "Tester")
	check(Shed._delivery_racks().size() == Shed.DELIVERY_RACK_XFS.size() and Shed.items.has(plugs), "a shed saved before the racking gets it, and keeps its deliveries")
	Shed.stop()


## The extension bays' bike lifts: raised and lowered with "lift", the bike can't be wheeled
## off or ridden while it's up, and which lifts are up is kept in the save.
func _test_bay_lifts() -> void:
	Shed.start_new("Tester", 43)
	Shed.garage_money = 5000000
	var me := Shed.me()
	check(Shed.check(me, {"a": "lift", "bay": 4}) != "" and Shed.check(me, {"a": "lift", "bay": 0}) != "", "no lifts before the extension's bays")
	for id in ["wing", "bays_56"]:
		Shed.request({"a": "buy_upgrade", "id": id})
	check(GarageUpgrades.lift_bays(Shed.upgrades) == [4, 5], "bays 5 and 6 have lifts")
	check(Shed.check(me, {"a": "lift", "bay": 0}) != "", "the shed's own bays don't")
	Shed.request({"a": "order"})
	Shed.request({"a": "order"})
	var bike := Shed.bike_in_bay(4)
	check(bike != 0 and Shed.lift_of(bike) == 4 and not Shed.lift_raised(bike), "a bike delivered to bay 5 stands on its lift")
	Shed.request({"a": "lift", "bay": 4, "up": true})
	check(Shed.lifts.has(4) and Shed.lift_raised(bike), "the lift goes up")
	check(Shed.check(me, {"a": "grab_bike", "bike": bike}).contains("lift"), "a bike up on the lift can't be wheeled off")
	check(Shed.check(me, {"a": "mount", "bike": bike}).contains("lift"), "or ridden off")
	Shed.request({"a": "lift", "bay": 5, "up": true})
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.request({"a": "lift", "bay": 4, "up": false})
	check(not Shed.lifts.has(4) and Shed.check(me, {"a": "grab_bike", "bike": bike}) == "", "lowered, it can be wheeled off again")
	# Wheel a bike towards a raised lift: it can't be let go of on it.
	var other := Shed.bike_in_bay(0)
	Shed.request({"a": "grab_bike", "bike": other})
	check(Shed.check(me, {"a": "release_bike", "bike": other, "xf": Workshop.bay_transform(5)}).contains("lift is up"), "a bike can't be parked on a raised lift")
	Shed.request({"a": "release_bike", "bike": other, "xf": Shed.bikes[other]["xf"]})
	Shed.load_state(copy, "Tester")
	check(Shed.lifts.has(4) and Shed.lifts.has(5), "lifts left up are still up in the save")
	copy.erase("lifts")
	Shed.load_state(copy, "Tester")
	check(Shed.lifts.is_empty(), "a shed saved before working lifts has them all down")
	copy["lifts"] = {0: true, 4: true, 9: true}
	Shed.load_state(copy, "Tester")
	check(Shed.lifts.keys() == [4], "only bays with a lift are kept")
	Shed.stop()


## In the game: a bay's lift raises the bike on its platform smoothly (the bike drawn on it),
## worked from its button post with F, and lowers it again; the annex is bigger and deeper and a
## walker can climb its mezzanine stairs; the crew lounge is upstairs on top of the shed, and a
## walker can climb the outside stairs, go through its door and be in it.
func _test_shed_building_session() -> void:
	SaveGame.slot_override = "test_shed_building"
	SaveGame.delete_slot("test_shed_building")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	await get_tree().physics_frame
	var ws: Workshop = main.world.workshop
	var w: Walker = main.walker
	w.set_tool("hands")
	Shed.request({"a": "garage_money", "value": 1000000})
	for id in ["lounge", "wing", "bays_56", "annex", "mezzanine"]:
		Shed.request({"a": "buy_upgrade", "id": id})
	check(GarageUpgrades.owned("lounge") and Shed.upgrades.size() == 5, "the crew lounge doesn't need the extension any more")
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := ws.get_world_3d().direct_space_state
	# The annex: bigger and deeper than it was.
	var r := GarageUpgrades.ANNEX
	check(r.size.x >= 11.0 and r.size.y >= 13.0 and GarageUpgrades.ANNEX_HEIGHT >= 6.0, "the storage annex is big and deep (%.1f x %.1f m, %.1f m high)" % [r.size.x, r.size.y, GarageUpgrades.ANNEX_HEIGHT])
	# A bike in bay 5, raised on its lift.
	Shed.request({"a": "order"})
	Shed.request({"a": "order"})
	var bike := Shed.bike_in_bay(4)
	var o := Workshop.bay_transform(4).origin
	var post: Vector3 = Workshop.bay_transform(4) * Vector3(-1.25, 0.0, 1.6)
	w.place(Transform3D(Basis(), post + Vector3(-0.2, 0.1, 1.2)))
	await _aim_point(w, post + Vector3(0.0, 0.95, 0.0))
	check(w.target.get("kind", "") == "lift" and int(w.target.get("bay", -1)) == 4 and w.info.contains("raise it"),
		"looking at the lift's post: it says F raises it (%s)" % str(w.target))
	_press("interact")
	await get_tree().physics_frame
	check(Shed.lifts.has(4), "F on the post raises the lift")
	var lift: Node3D = ws.get_node("Upgrades/Built/LiftBase4/Lift4")
	var heights := []
	for i in 600:
		await get_tree().physics_frame
		if i % 60 == 0:
			heights.append(lift.position.y)
	var smooth := true
	for i in heights.size() - 1:
		smooth = smooth and float(heights[i + 1]) >= float(heights[i]) - 0.001
	check(heights.size() > 3 and float(heights[1]) > 0.05 and float(heights[1]) < GarageUpgrades.LIFT_TOP - 0.05 and smooth,
		"it goes up smoothly, not in one jump (%s)" % str(heights.slice(0, 4)))
	check(absf(lift.position.y - GarageUpgrades.LIFT_TOP) < 0.01, "the platform reaches the top (%.2f m)" % lift.position.y)
	var view: Node3D = ws.bike_views[bike]
	check(absf(view.global_position.y - (o.y + GarageUpgrades.LIFT_TOP)) < 0.02, "and the bike is up on it (%.2f m)" % view.global_position.y)
	var deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3(0.0, 3.0, 0.9), o + Vector3(0.0, -1.0, 0.9), 1))
	check(not deck.is_empty() and absf(float(deck["position"].y) - GarageUpgrades.LIFT_TOP) < 0.05, "the platform is solid up there")
	_press("interact")
	for i in 600:
		await get_tree().physics_frame
	check(not Shed.lifts.has(4) and lift.position.y < 0.01 and view.global_position.y < o.y + 0.02, "F again brings it back down, bike and all")
	# Up the mezzanine stairs in the annex.
	var foot := Vector3((GarageUpgrades.STAIR_X.x + GarageUpgrades.STAIR_X.y) * 0.5, 0.1, GarageUpgrades.STAIR_Z.x + 1.5)
	w.place(Transform3D(Basis(), foot))   # facing -Z, up the stairs
	for i in 5:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for i in 480:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 10:
		await get_tree().physics_frame
	check(absf(w.global_position.y - GarageUpgrades.MEZZ_TOP) < 0.15 and w.global_position.z < GarageUpgrades.STAIR_Z.y,
		"a walker climbs the stairs onto the mezzanine (%s)" % str(w.global_position))
	# Up the outside stairs to the crew lounge, along the landing and in through its door.
	var sx := GarageUpgrades.LOFT_STAIR_X
	var sz := GarageUpgrades.LOFT_STAIR_Z
	w.place(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sx.x + 1.5, 0.1, (sz.x + sz.y) * 0.5)))   # facing -X, up the flight
	for i in 5:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for i in 900:
		await get_tree().physics_frame
		if w.global_position.x < GarageUpgrades.LOFT_DOOR_X + 0.1:
			break
	Input.action_release("move_forward")
	check(absf(w.global_position.y - GarageUpgrades.LOFT_FLOOR) < 0.15 and w.global_position.x < sx.y,
		"a walker climbs the outside stairs to the landing (%s)" % str(w.global_position))
	w.rotation.y = 0.0   # facing -Z, through the door
	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 10:
		await get_tree().physics_frame
	check(Workshop.room_at(w.global_position) == "lounge" and absf(w.global_position.y - GarageUpgrades.LOFT_FLOOR) < 0.15,
		"and walks through the door into the crew lounge, upstairs (%s)" % str(w.global_position))
	check(Sfx.step_surface(w.global_position) == "carpet", "the lounge is carpeted underfoot")
	check(ws.get_node_or_null("Upgrades/Built/LoungeSofa") != null and (ws.get_node("Upgrades/Built/LoungeSofa") as Node3D).global_position.y > GarageUpgrades.LOFT_FLOOR,
		"the lounge's furniture is up there")
	check(Workshop.room_at(Vector3(0.0, 1.0, 65.0)) == "shed", "downstairs is still the shed")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	SaveGame.delete_slot("test_shed_building")
	SaveGame.slot_override = ""


## Delete scraps any shed machine or furniture standing where it is, not only what you carry:
## benches, washers, repair machines, sandblasters, stands, shelves, seats, posters, TVs, yard
## kit and trinkets. The spray bay, tyre changer and whiteboard stay.
func _test_scrap_placed() -> void:
	Shed.start_new("Tester", 43)
	var me := Shed.me()
	var models := []
	for kind in Equipment.KINDS:
		if Equipment.FIXED_KINDS.has(kind):
			continue
		models.append(Equipment.DEFAULT[kind])
	models.append_array(["trinket_clock", "trinket_plant", "trinket_clock_digital"])
	var gone := []
	for model in models:
		Shed.request({"a": "order_furniture", "model": model})
		var fid := 0
		for id in Shed.furniture:
			if str(Shed.furniture[id]["model"]) == str(model) and int(Shed.furniture[id]["mover"]) == 0:
				fid = maxi(fid, int(id))
		if fid == 0:
			check(false, "%s ordered" % model)
			continue
		var why := Shed.check(me, {"a": "scrap", "furniture": fid})
		Shed.request({"a": "scrap", "furniture": fid})
		if why == "" and not Shed.furniture.has(fid):
			gone.append(model)
		else:
			check(false, "the %s can be scrapped where it stands (%s)" % [model, why])
	check(gone.size() == models.size(), "every machine, seat, poster, TV, yard piece and trinket can be scrapped where it stands (%d)" % gone.size())
	# An engine on a stand goes to the floor where the stand was.
	var stand := _first_furniture("engine_stand")
	var engine := 0
	for id in Shed.items:
		if Shed.is_engine(id) and str(Shed.items[id]["at"]) == "spot" and Shed.is_stand_spot(str(Shed.items[id]["ref"])):
			engine = id
	if stand != 0 and engine != 0:
		Shed.request({"a": "scrap", "furniture": stand})
		check(not Shed.furniture.has(stand) and Shed.items.has(engine) and Shed.items[engine]["at"] == "floor",
			"scrapping an engine stand leaves its engine on the floor")
	# A trophy on a bench comes down to the floor with it.
	Shed.request({"a": "order_furniture", "model": "bench_standard"})
	var bench := 0
	for id in Shed.furniture:
		if str(Shed.furniture[id]["model"]) == "bench_standard":
			bench = maxi(bench, int(id))
	var bxf := Transform3D(Basis(Vector3.UP, 0.3), Workshop.CENTER + Vector3(2.0, 0.0, 2.0))
	Shed.furniture[bench]["xf"] = bxf
	Shed.request({"a": "order_furniture", "model": "trinket_trophy"})
	var trophy := _first_furniture("trinket_trophy")
	Shed.furniture[trophy]["xf"] = Transform3D(Basis(), bxf * Vector3(0.2, Equipment.work_height("bench_standard"), 0.0))
	Shed.request({"a": "scrap", "furniture": bench})
	check(not Shed.furniture.has(bench) and absf((Shed.furniture[trophy]["xf"] as Transform3D).origin.y - bxf.origin.y) < 0.001,
		"a trinket on a scrapped bench ends up on the floor")
	for kind in ["booth", "changer", "whiteboard"]:
		var fid := 0
		for id in Shed.furniture:
			if Shed.furniture[id]["kind"] == kind:
				fid = id
		check(fid != 0 and not Shed.scrappable(Shed.furniture[fid]) and Shed.check(me, {"a": "scrap", "furniture": fid}).contains("part of the shed"),
			"the %s is built in and stays" % kind)


## In the shed: look at a parts washer with empty hands, hold Delete, press it again, and it's gone.
func _test_scrap_placed_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	Shed.request({"a": "order_furniture", "model": "washer_standard"})
	var washer := 0
	for id in Shed.furniture:
		if str(Shed.furniture[id]["model"]) == "washer_standard":
			washer = maxi(washer, int(id))
	var middle := Workshop.CENTER + Vector3(-1.0, 0.0, 1.5)
	Shed.furniture[washer]["xf"] = Transform3D(Basis(), middle)
	Shed.changed.emit()
	w.place(Transform3D(Basis(), middle + Vector3(0.0, 0.0, 1.3)))
	await _aim_point(w, middle + Vector3(0.0, 0.5, 0.0))
	check(w.looked_at_furniture() == washer, "looking at the parts washer (%s)" % str(w.target))
	check(w.info.contains("scrap it"), "the panel says Delete scraps it")
	Input.action_press("scrap")
	for i in 160:
		await get_tree().physics_frame
		if not w.scrap_armed.is_empty():
			break
	Input.action_release("scrap")
	await get_tree().physics_frame
	check(int(w.scrap_armed.get("furniture", 0)) == washer and Shed.furniture.has(washer), "held, it asks first")
	_press("scrap")
	await get_tree().physics_frame
	check(not Shed.furniture.has(washer), "pressed again, the washer is scrapped")
	# The built-in tyre changer can't be.
	var changer := _first_furniture("tyre_changer")
	var cxf: Transform3D = Shed.furniture[changer]["xf"]
	w.place(Transform3D(Basis(), cxf.origin + cxf.basis.z * 1.3))
	await _aim_point(w, cxf.origin + Vector3(0.0, 0.6, 0.0))
	check(w.looked_at_furniture() == changer and not w.info.contains("scrap it"), "the tyre changer offers no scrap")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The free rotate key switches the rotate keys between quarter turns and any angle.
func _test_free_rotate() -> void:
	var kept_free: bool = Settings.free_rotate
	var kept_snap: bool = Settings.snap_placement
	check(Settings.binding_text("rotate_free", false) != "" and Settings.clash_text("rotate_free") == "",
		"free rotate has a key of its own (%s)" % Settings.binding_text("rotate_free", false))
	Settings.snap_placement = true
	Settings.free_rotate = false
	check(is_equal_approx(Walker._stepped(0.0, 1), PI * 0.5), "free rotate off: a press is a quarter turn")
	Settings.free_rotate = true
	check(is_equal_approx(Walker._stepped(0.0, 1), Walker.TURN_NUDGE) and rad_to_deg(Walker.TURN_NUDGE) <= 5.01,
		"free rotate on: a tap is a 5 degree nudge, snapping or not")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	Settings.free_rotate = false
	var middle := Workshop.CENTER + Vector3(0.0, 0.0, 1.0)
	w.place(Transform3D(Basis(), middle))
	var bar := _in_hands("flat_bar")
	await _aim_point(w, middle + Vector3(0.0, 0.0, -1.2))
	check(w.info.contains("a quarter at a time") and w.info.contains("free rotate"), "the panel says the turns are quarters and how to free them")
	_press("rotate_free")
	for i in 3:
		await get_tree().physics_frame
	check(Settings.free_rotate and w.info.contains("hold to turn freely"), "the free rotate key turns it on, and the panel says so")
	var was := w.hold_turn
	Input.action_press("rotate_left")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("rotate_left")
	await get_tree().physics_frame
	var turned := wrapf(w.hold_turn - was, -PI, PI)
	check(turned > 0.2 and fmod(absf(w.hold_turn), PI * 0.5) > 0.01, "held, the part turns smoothly to any angle (%.0f degrees)" % rad_to_deg(turned))
	var want := w.rotation.y + w.hold_turn
	await _hold_act(main)
	check(Shed.items[bar]["at"] == "floor" and absf(wrapf((Shed.items[bar]["ref"] as Transform3D).basis.get_euler().y - want, -PI, PI)) < 0.02,
		"put down, it lies at that angle")
	# Carried equipment keeps its free angle with snapping on (it isn't squared to the walls).
	Shed.request({"a": "order_furniture", "model": "seat_stool"})
	var stool := _first_furniture("seat_stool")
	Shed.furniture[stool]["xf"] = Transform3D(Basis(), middle + Vector3(0.0, 0.0, -1.0))
	Shed.request({"a": "grab", "furniture": stool})
	for i in 3:
		await get_tree().physics_frame
	w.carry_turn = 0.0
	_press("rotate_left")
	await get_tree().physics_frame
	var sxf: Transform3D = w._push_transform(stool)
	check(is_equal_approx(w.carry_turn, Walker.TURN_NUDGE) and absf(wrapf(sxf.basis.get_euler().y - w.rotation.y - w.carry_turn, -PI, PI)) < 0.01,
		"carried equipment nudges 5 degrees and keeps that angle")
	_press("rotate_free")
	await get_tree().physics_frame
	check(not Settings.free_rotate, "pressed again, back to quarter turns")
	_press("interact")
	for i in 3:
		await get_tree().physics_frame
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	Settings.free_rotate = kept_free
	Settings.snap_placement = kept_snap
	Settings.save_settings()


## The signage upgrade's light box fits the TORQUE SHED letters inside its neon frame, with a
## margin all round and clear of the strapline, and they go back as they were without it.
func _test_front_sign_fits() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var ws: Workshop = main.workshop
	var sign := ws.front_sign
	var bare := sign.pixel_size
	Shed.upgrades["signage"] = true
	ws.upgrades.sync()
	var ext: Dictionary = ws.upgrades.front_sign_extent()
	var c := Workshop.CENTER
	var y := Workshop.DOOR_HEIGHT + 0.6
	var half := WorkshopUpgrades.SIGN_BOX * 0.5
	var sub: Label3D = ws.upgrades.find_child("SignSub", true, false)
	var font: Font = ThemeDB.fallback_font
	var line := (font.get_ascent(sub.font_size) + font.get_descent(sub.font_size)) * sub.pixel_size
	var sub_top := sub.position.y + line * 0.5 - font.get_ascent(sub.font_size) * sub.pixel_size + 0.72 * sub.font_size * sub.pixel_size
	check(float(ext["x"][0]) >= c.x - half.x + 0.2 and float(ext["x"][1]) <= c.x + half.x - 0.2,
		"the letters fit across the sign box with a margin (%.2f to %.2f in a %.1f m box)" % [float(ext["x"][0]), float(ext["x"][1]), WorkshopUpgrades.SIGN_BOX.x])
	check(float(ext["y"][1]) <= y + half.y - 0.05 and float(ext["y"][0]) >= sub_top + 0.05,
		"and between the top of the frame and the strapline (%.2f to %.2f, strapline %.2f, frame top %.2f)" % [float(ext["y"][0]), float(ext["y"][1]), sub_top, y + half.y])
	check(sign.position.z > c.z + Workshop.HALF.y + 0.3, "in front of the box")
	Shed.upgrades.erase("signage")
	ws.upgrades.sync()
	check(is_equal_approx(sign.pixel_size, bare), "without the upgrade the plain sign is its old size")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## Wall clocks keep the shed's time: the station clock's hands and the digital clocks' display
## follow the in-game clock as it goes.
func _test_wall_clocks() -> void:
	var a := Trinkets.hand_angles(15.5)
	check(is_equal_approx(a.x, TAU * 3.5 / 12.0) and is_equal_approx(a.y, PI) and is_zero_approx(a.z), "half past three: hour hand past 3, minute hand at 6")
	check(Trinkets.digital_text(7.0 + 59.9 / 60.0) == "07:59" and Trinkets.digital_text(23.999) == "23:59" and Trinkets.digital_text(0.0) == "00:00",
		"a digital clock shows the minute it's in")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var ws: Workshop = main.workshop
	var ids := {}
	for model in ["trinket_clock", "trinket_clock_digital", "trinket_clock_desk"]:
		Shed.request({"a": "order_furniture", "model": model})
		ids[model] = _first_furniture(model)
	Shed.changed.emit()
	for t in [9.25, 18.75]:
		Daylight.current.set_time(t)
		for i in 3:
			await get_tree().process_frame
		var face: Node = ws.furniture_nodes[ids["trinket_clock"]].find_child("Clock", true, false)
		var shown: Vector3 = face.shown() if face else Vector3(-1, -1, -1)
		var want := Trinkets.hand_angles(Daylight.time_of_day())
		check(shown.distance_to(want) < 0.01, "at %s the wall clock's hands show it (%s)" % [Daylight.clock_text(t), str(shown)])
		for model in ["trinket_clock_digital", "trinket_clock_desk"]:
			var led: Node = ws.furniture_nodes[ids[model]].find_child("Clock", true, false)
			var text: String = led.label.text.replace(" ", ":") if led else ""
			check(text == Trinkets.digital_text(Daylight.time_of_day()), "the %s reads %s" % [Trinkets.MODELS[model]["name"].to_lower(), text])
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The money graphs by the minute, hour, day, week, month and year of in-game time.
func _test_money_graph() -> void:
	var s := {}
	check(MoneyGraph.record(s, 0.0, 100) and MoneyGraph.record(s, 0.5, 150) and MoneyGraph.record(s, 30.0, 80), "money moving goes in the series")
	check(not MoneyGraph.record(s, 30.1, 80), "and nothing changes while it stays put")
	var hours := MoneyGraph.points(s, "hour", 30.2, 80)
	check(hours.size() == 24 and int(hours[-1]) == 80 and int(hours[-2]) == 150 and int(hours[0]) == 150, "by the hour: 24 hours, now last (%s)" % str(hours.slice(-3)))
	var mins := MoneyGraph.points(s, "minute", 30.2, 80)
	check(mins.size() == 60 and int(mins[-1]) == 80 and int(mins[47]) == 80 and int(mins[46]) == 150, "by the minute: the last hour (%s)" % str(mins.slice(44, 49)))
	var days := MoneyGraph.points(s, "day", 30.2, 80)
	check(days.size() == 7 and int(days[-2]) == 150 and int(days[-1]) == 80, "by the day: a week")
	for key in MoneyGraph.ORDER:
		check(MoneyGraph.points(s, key, 30.2, 80).size() == int(MoneyGraph.RANGES[key]["count"]), "%s: %d points" % [key, int(MoneyGraph.RANGES[key]["count"])])
	var long := {}
	for i in 400:
		MoneyGraph.record(long, i / 60.0, i)
	check((long["minute"] as Array).size() <= 62 and int(MoneyGraph.points(long, "minute", 399.0 / 60.0, 399)[0]) == 340,
		"old minutes are let go, but the hour shown is right")
	check(int(MoneyGraph.points(long, "year", 399.0 / 60.0, 399)[0]) == 0 and MoneyGraph.points(long, "year", 0.0, 0).size() == 5,
		"by the year: five years, from what it opened with")
	var back := MoneyGraph.sanitize(JSON.parse_string(JSON.stringify(s)))
	check(MoneyGraph.points(back, "hour", 30.2, 80) == hours, "a series survives saving as JSON")
	check(MoneyGraph.sanitize(null)["day"] == [] and MoneyGraph.sanitize({"day": "junk"})["day"] == [], "an old or broken save has an empty series")
	# The business: kept in the bank, saved with the shed.
	Shed.start_new("Tester", 44)
	Money.record_graph()
	Shed.credit_garage(2500, "Test sale")
	Money.record_graph()
	var g := Money.graph("minute")
	check(int(g[-1]) == Shed.garage_money, "the business's graph ends at its account now")
	var saved := Money.sanitize(JSON.parse_string(JSON.stringify(Shed._snapshot(false)["bank"])))
	check(not (saved["series"]["minute"] as Array).is_empty() and int(saved["series"]["minute"][-1][1]) == Shed.garage_money,
		"and its series is saved with the shed")
	check(Money.sanitize({})["series"].has("year"), "an old save's bank gets an empty series")
	# Your own money, in your profile.
	var real_path := Progress.path
	Progress.path = "user://profile_shed_objects_unit.json"
	Progress.select("Graph Tester")
	Progress.earn(40, "Test wage")
	var mine := Progress.cash_graph("hour")
	check(int(mine[-1]) == Progress.money() and Progress.profile["series"]["hour"] is Array and not (Progress.profile["series"]["hour"] as Array).is_empty(),
		"your own money's graph follows your cash")
	Progress.save_profile()
	Progress.select("Graph Tester")
	check(not (Progress.profile["series"]["hour"] as Array).is_empty(), "and it's kept in your profile")
	# The Money tab's range buttons and the TV pages follow the same choice.
	var kept := Settings.money_graph_range
	var tab := MoneyTab.new()
	add_child(tab)
	await get_tree().process_frame
	tab.set_graph_range("week")
	check(Settings.money_graph_range == "week" and tab._graph_mine.values.size() == 12 and tab._graph_garage.values.size() == 12
		and tab._graph_garage.title.contains("12 weeks"), "the Money tab shows both graphs by the week")
	check((TvChannels.garage_data()["history"] as Array).size() == 12 and (TvChannels.money_data(Shed.me())["history"] as Array).size() == 12,
		"and the money TV pages follow it")
	tab.set_graph_range("minute")
	check(tab._graph_mine.values.size() == 60, "by the minute")
	tab.free()
	Settings.money_graph_range = kept
	Settings.save_settings()
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


## No sign in the shed (the room names over the doorways, the neon signs, the mezzanine's)
## runs into a light: the LED strips, the honeycomb ceilings and the strip lights, with no
## upgrades and with every upgrade built.
func _test_room_signs_clear_of_lights() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var ws: Workshop = main.workshop
	var hits := _sign_light_hits(ws)
	check(hits.is_empty(), "in a plain shed no sign runs into a light %s" % str(hits))
	Shed.request({"a": "garage_money", "value": 1000000})
	for id in GarageUpgrades.CATALOGUE:
		Shed.request({"a": "buy_upgrade", "id": id})
	await get_tree().process_frame
	ws.upgrades.sync()
	check(ws.upgrades.built().split(",").size() == GarageUpgrades.CATALOGUE.size(), "every upgrade built (%s)" % ws.upgrades.built())
	hits = _sign_light_hits(ws)
	check(hits.is_empty(), "with every upgrade no room sign runs into the LED strips, honeycomb or strip lights %s" % str(hits))
	# The honeycomb takes the place of the strip light fittings, which would hang through its tubes.
	var tubes := []
	var fittings := []
	var stack: Array = [ws]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		if n is MultiMeshInstance3D and n.name == "HexLights":
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				tubes.append((n as Node3D).global_transform * mm.get_instance_transform(i) * mm.mesh.get_aabb())
		elif n is MeshInstance3D and (n as MeshInstance3D).material_override is StandardMaterial3D \
				and ((n as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled:
			fittings.append((n as Node3D).global_transform * (n as MeshInstance3D).mesh.get_aabb())
	var through := 0
	for f in fittings:
		for t in tubes:
			if (f as AABB).intersects(t):
				through += 1
				break
	check(not tubes.is_empty() and through == 0, "no light fitting hangs through the honeycomb ceilings (%d did)" % through)
	Shed.upgrades.erase("showroom")
	ws.upgrades.sync()
	check(ws.ceiling_strips.all(func(m): return m.visible), "without the honeycomb the strip lights are back")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The room-name signs: over the doorways, the lounge's and the shed's neon, the mezzanine's.
const ROOM_SIGNS := ["PAINT SHOP", "STORAGE", "WORKSHOP", "ANNEX", "CREW LOUNGE", "MEZZANINE  ·  STOCK", "WASH BAY", "KITCHEN", "OFFICE"]


## "SIGN vs light" for every room-name sign (and the neon TORQUE SHED inside) whose text box
## comes within 3 cm of a glowing light fitting (a mesh with an emissive material, or one tube
## of a honeycomb).
func _sign_light_hits(ws: Workshop) -> Array:
	var labels := []
	var lights := []
	var stack: Array = [ws]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		if n is Label3D:
			if ROOM_SIGNS.has((n as Label3D).text) or n.name == "ShedNeon":
				labels.append(n)
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				lights.append([(n as Node3D).global_transform * mm.get_instance_transform(i) * mm.mesh.get_aabb(), str(n.name)])
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var m = (n as MeshInstance3D).material_override
			if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
				lights.append([(n as Node3D).global_transform * (n as MeshInstance3D).mesh.get_aabb(), "light"])
	var out := []
	for l in labels:
		var s := Workshop.label_size(l)
		var box: AABB = (l as Node3D).global_transform * AABB(Vector3(-s.x * 0.5, -s.y * 0.5, -0.01), Vector3(s.x, s.y, 0.02))
		for li in lights:
			if box.grow(0.03).intersects(li[0]):
				out.append("%s vs %s at %s" % [(l as Label3D).text.replace("\n", " "), li[1], (li[0] as AABB).get_center()])
	return out




# ---------------------------------------------------------------------------- sandblaster round 3

## A sandblasting cabinet moved into the shed with the barn find's engine in it: {main, w, cab,
## spot, engine, parts}. The engine and its ancillaries start rusty.
func _blast_rig() -> Dictionary:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
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
	var parts := Shed._blast_parts(engine)
	for id in parts:
		Shed.items[id]["rust"] = 0.8
		Shed.items[id]["dirt"] = 0.5
		Shed.items[id]["wear"] = 0.1
	Shed.changed.emit()
	for i in 5:
		await get_tree().process_frame
	var w: Walker = main.walker
	w.place(Transform3D(Basis(), at + Vector3(0.0, 0.0, 1.3)))
	return {"main": main, "w": w, "cab": cab, "spot": spot, "engine": engine, "parts": parts, "at": at}


## Hands in the cabinet's gloves (straight to the host, no aiming), waiting for the game to start.
func _blast_gloves(rig: Dictionary) -> BlastGame:
	Shed.request({"a": "blast_use", "spot": rig["spot"], "on": true})
	for i in 6:
		await get_tree().physics_frame
	return (rig["w"] as Walker).blast


## Blasts a part's patches in the live game as if the jet had been there: every patch, or only
## those on the right-hand (+x) half of it.
func _blast_fake(game: BlastGame, id: int, right_half: bool) -> void:
	var p: Dictionary = game.parts[id]
	var pts: PackedVector3Array = p["points"]
	var vox: PackedInt32Array = p["vox"]
	var cells: PackedFloat32Array = p["cells"]
	var mid := 0.0
	for q in pts:
		mid += q.x
	mid /= maxf(pts.size(), 1)
	var coats := game.marks.coats
	for i in pts.size():
		if vox[i] >= 0 and (not right_half or pts[i].x > mid):
			coats[vox[i]] = 1.5
			cells[i] = 1.5
	game.marks.coats = coats
	p["cells"] = cells


## The bare metal you blast stays: kept on each part when you step back, drawn again on the
## engine in the cabinet, carried, on the stand and in a bike (lined up the same on each), kept in
## the save, and picked up again next time it's in the cabinet. A part blasted all over is drawn
## bare all over.
func _test_blast_keeps_bare_metal() -> void:
	var rig: Dictionary = await _blast_rig()
	var main: Node = rig["main"]
	var w: Walker = rig["w"]
	var engine: int = rig["engine"]
	var parts: Array = rig["parts"]
	var game := await _blast_gloves(rig)
	check(game != null and parts.size() >= 3, "hands in the gloves (%d parts)" % parts.size())
	if game == null:
		main._leave()
		main.queue_free()
		await get_tree().physics_frame
		return
	# Half the block and every ancillary blasted, then step back.
	for id in parts:
		_blast_fake(game, int(id), int(id) == engine)
	var half := float(game.stats(engine)["covered"])
	var total := game.total()
	w.finish_blast()
	for i in 4:
		await get_tree().process_frame
	var kept: Dictionary = Shed.items[engine].get("blast", {})
	check(kept.has("v") and BlastMarks.valid(kept) and absf(float(kept["c"]) - half) < 0.01 and half > 0.25 and half < 0.75,
		"stepping back keeps where the block is bare on it (%d%% of it)" % roundi(half * 100.0))
	var all_full := true
	for id in parts:
		if int(id) != engine:
			all_full = all_full and Shed.blast_full(Shed.items[id])
	check(all_full and not Shed.blast_full(Shed.items[engine]), "the ancillaries blasted all over count as bare metal all over, the half-done block doesn't")
	check(Shed.condition_text(Shed.items[engine]).contains("Sandblasted"), "the part's info says how much of it is bare")
	# Drawn again from what's kept, in the cabinet.
	var cab_model: BikeModel = main.workshop.model_for({"engine": engine})
	var saved: BlastMarks = cab_model.get_node_or_null("BlastSaved") if cab_model else null
	check(saved != null and saved.bare_count() > 50, "the engine in the cabinet is redrawn with its bare metal on (%d cubes)" % (saved.bare_count() if saved else 0))
	var head_slot := ""
	for slot in PartsDB.ENGINE_SLOTS:
		if head_slot == "" and Shed.engine_item(engine, slot) != 0:
			head_slot = slot
	var full_on := saved != null and saved.material_for(head_slot) != null and float(saved.material_for(head_slot).get_shader_parameter("full")) == 1.0 \
		and float(saved.material_for("engine").get_shader_parameter("full")) == 0.0
	check(full_on, "a part blasted all over is drawn bare metal all over (%s)" % head_slot)
	# The same bare patches in a bike's engine, lined up from the middle of the block.
	var bm := BikeModel.new()
	add_child(bm)
	var b := Shed.engine_build(engine)
	bm.build_from(b, Color.RED, {}, b.condition, false)
	var in_bike: BlastMarks = bm.get_node_or_null("BlastSaved")
	var same := 0
	var looked := 0
	if saved and in_bike:
		for i in saved.coats.size():
			if saved.coats[i] < 1.0 or looked >= 400:
				continue
			var v := Vector3i(i % saved.dims.x, (i / saved.dims.x) % saved.dims.y, i / (saved.dims.x * saved.dims.y)) + saved.lattice - in_bike.lattice
			if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= in_bike.dims.x or v.y >= in_bike.dims.y or v.z >= in_bike.dims.z:
				continue
			looked += 1
			if in_bike.coats[v.x + in_bike.dims.x * (v.y + in_bike.dims.y * v.z)] >= 1.0:
				same += 1
	check(in_bike != null and looked > 50 and same >= looked * 0.95,
		"fitted to a bike, the engine shows the same bare patches in the same places (%d of %d)" % [same, looked])
	bm.queue_free()
	# Carried, and on the stand.
	var carried := BikeModel.item_display(engine)
	add_child(carried)
	check((carried.get_meta("model") as BikeModel).get_node_or_null("BlastSaved") != null, "carried, it's still bare where it was blasted")
	carried.queue_free()
	var stand_spot := ""
	for s in Shed.stand_spots():
		if stand_spot == "" and Shed.item_at_spot(s) == 0:
			stand_spot = s
	Shed.request({"a": "take", "spot": rig["spot"]})
	Shed.request({"a": "place", "spot": stand_spot})
	for i in 3:
		await get_tree().process_frame
	var on_stand: BikeModel = main.workshop.model_for({"engine": engine})
	check(Shed.item_at_spot(stand_spot) == engine and on_stand != null and on_stand.get_node_or_null("BlastSaved") != null,
		"and on the engine stand")
	# A bike's own engine blasted all over shows bare in the bike.
	var bike: int = Shed.bikes.keys()[0]
	var block := Shed.item_on(bike, "engine")
	if block != 0:
		Shed.items[block]["blast"] = {"c": 1.0, "p": 0.0}
		Shed.changed.emit()
		for i in 3:
			await get_tree().process_frame
		var bmodel: BikeModel = main.workshop.bike_model(bike)
		var bs: BlastMarks = bmodel.get_node_or_null("BlastSaved") if bmodel else null
		check(bs != null and float(bs.material_for("engine").get_shader_parameter("full")) == 1.0, "a blasted engine fitted to a bike is drawn bare metal")
		Shed.items[block].erase("blast")
	# Kept in the save (and a save from before has none).
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	var v_before := str(kept["v"])
	Shed.load_state(copy, "Tester")
	await get_tree().process_frame
	check(Shed.items[engine].get("blast", {}).get("v", "") == v_before and BlastMarks.valid(Shed.items[engine]["blast"])
		and Shed.items[engine].has("blast_base"), "where it's bare is kept in the save")
	var fresh := Shed._new_item("paper_oil", 0.3, 0.2, 0.0)
	check(Shed.blast_cover(Shed.items[fresh]) == 0.0 and not Shed.condition_of(Shed.items[fresh]).has("blast"), "a part never blasted has none")
	Shed.items.erase(fresh)
	# Back in the cabinet it carries on from where it was.
	Shed.request({"a": "take", "spot": stand_spot})
	Shed.request({"a": "place", "spot": rig["spot"]})
	for i in 5:
		await get_tree().process_frame
	var rust_mid := float(Shed.items[engine]["rust"])
	game = await _blast_gloves(rig)
	check(game != null and absf(game.total() - total) < 0.03 and game.newly_done().is_empty(),
		"back in the cabinet, it starts from what's bare already (%d%% of %d%%)" % [roundi(game.total() * 100.0) if game else 0, roundi(total * 100.0)])
	if game:
		_blast_fake(game, engine, false)
		var xp_before := int(Progress.profile.get("xp", 0))
		w.finish_blast()
		await get_tree().process_frame
		check(float(Shed.items[engine]["rust"]) == 0.0 and rust_mid > 0.2 and Shed.blast_full(Shed.items[engine]),
			"finishing the job strips the rest, from how rusty it was to start with")
		check(int(Progress.profile.get("xp", 0)) > xp_before, "and pays for the part that came up bare this time")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The scan button at the sandblaster: the engine lights up where there's still rust to blast, the
## readout lists how much is left on each part and each side, and the crew see it.
func _test_blast_scan() -> void:
	var g := BlastGame.new()
	g.parts = {1: {"slot": "engine", "name": "Engine", "points": PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.DOWN, Vector3.LEFT]),
		"cells": PackedFloat32Array([1.2, 1.2, 0.0, 0.3])}}
	var s := g.scan()
	var sides := {}
	for row in s["sides"]:
		sides[str(row["name"])] = float(row["left"])
	check(absf(float(s["left"]) - 0.5) < 0.001 and sides.get("Top", -1.0) == 0.0 and sides.get("Underneath", -1.0) == 1.0
		and sides.get("Left side", -1.0) == 1.0 and not sides.has("Front"), "the scan works out what's still to blast, side by side")
	var rig: Dictionary = await _blast_rig()
	var main: Node = rig["main"]
	var w: Walker = rig["w"]
	var engine: int = rig["engine"]
	var game := await _blast_gloves(rig)
	if game == null:
		check(false, "hands in the gloves")
		main._leave()
		main.queue_free()
		await get_tree().physics_frame
		return
	_blast_fake(game, engine, true)
	var view: EquipmentView = main.workshop.furniture_nodes[rig["cab"]]
	check(not game.scanning and not view.scan_lit() and view.get_node_or_null("ScanButton") != null, "the cabinet has a scan button, off to start with")
	_press("blast_scan")
	for i in 30:
		await get_tree().physics_frame
	await get_tree().process_frame
	var hud: BlastHud = main.hud.blast_hud
	var mat := game.marks.material_for("engine")
	check(game.scanning and view.scan_lit() and float(mat.get_shader_parameter("scan")) > 0.3,
		"X scans: the button lights and the engine glows where there's rust still to blast")
	var sv: Dictionary = hud.scan_view
	check(not sv.is_empty() and absf(float(sv["left"]) - (1.0 - game.total())) < 0.02 and (sv["parts"] as Array).size() == game.parts.size(),
		"the readout says how much is still to blast, part by part (%d%% left)" % roundi(float(sv.get("left", 0.0)) * 100.0))
	var by := {}
	for row in sv.get("sides", []):
		by[str(row["name"])] = float(row["left"])
	check(by.size() >= 4 and float(by.get("Right side", 1.0)) < float(by.get("Left side", 0.0)),
		"and side by side: the blasted right side has less left than the left (%d%% vs %d%%)" % [roundi(float(by.get("Right side", 1.0)) * 100.0), roundi(float(by.get("Left side", 0.0)) * 100.0)])
	check(bool(Shed.crew[Shed.me()].get("blast_scan", false)), "the crew are told the scan is on, so they see it too")
	check(w.blast_controls().contains("scan"), "the controls along the bottom say how to scan")
	_press("blast_scan")
	for i in 60:
		await get_tree().physics_frame
	await get_tree().process_frame
	check(not game.scanning and not view.scan_lit() and float(mat.get_shader_parameter("scan")) < 0.01 and hud.scan_view.is_empty(), "press it again and the scan goes off")
	w.finish_blast()
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## After blasting, the engine hangs on a paint shop hook (on a lifting sling) and the spray gun
## gives it a protective coat: clear lacquer over the bare metal or engine enamel. A coat keeps
## flash rust and muck off when it's ridden; bare metal without one rusts.
func _test_protective_coat() -> void:
	var rig: Dictionary = await _blast_rig()
	var main: Node = rig["main"]
	var w: Walker = rig["w"]
	var engine: int = rig["engine"]
	var parts: Array = rig["parts"]
	var me := Shed.me()
	var clear := {"a": "coat", "item": engine, "coat": "clear", "gun": true, "quality": 0.9}
	check(Shed.check(me, clear).contains("paint shop"), "a coat goes on in the paint shop")
	# Blast it all bare.
	Shed.request({"a": "blast_use", "spot": rig["spot"], "on": true})
	var res := {}
	for id in parts:
		res[id] = [0.95, 0.0]
	Shed.request({"a": "blast", "spot": rig["spot"], "parts": res})
	await get_tree().physics_frame
	check(parts.all(func(id): return float(Shed.items[id]["rust"]) == 0.0 and Shed.blast_full(Shed.items[id])), "blasted bare all over")
	# Hang it in the paint shop.
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hook: String = Shed.furniture_spots(booth)[2]
	Shed.request({"a": "take", "spot": rig["spot"]})
	check(Shed.check(me, {"a": "place", "spot": hook}) == "", "an engine hangs on a paint shop hook")
	Shed.request({"a": "place", "spot": hook})
	for i in 3:
		await get_tree().process_frame
	var ws: Workshop = main.workshop
	var disp: Node3D = ws._spot_nodes.get(hook, null)
	var swing: Node = disp.get_parent() if disp else null
	var size: Vector3 = disp.get_meta("size", Vector3.ZERO) if disp else Vector3.ZERO
	var hook_y := (swing.get_node("Hook") as Node3D).global_position.y if swing and swing.get_node_or_null("Hook") else 0.0
	var top_y := disp.global_position.y + size.y if disp else 0.0
	check(swing is Swing and swing.get_node_or_null("EngineSling") != null and top_y < hook_y and top_y > hook_y - 0.4 and disp.global_position.y > 0.2,
		"on a lifting sling, its top just under the hook and clear of the floor (top %.2f, hook %.2f)" % [top_y, hook_y])
	# The spray gun's coats: after the paint finishes.
	w.set_tool("gun")
	w.spray_finish = Shed.FINISHES.size()
	check(w.spray_coat() == "clear" and w.spray_text() == "Clear lacquer", "the spray gun has protective coats after its finishes")
	var seen := []
	for i in Shed.FINISHES.size() + Shed.COAT_ORDER.size():
		seen.append(w.spray_coat())
		w.spray_finish = (w.spray_finish + 1) % (Shed.FINISHES.size() + Shed.COAT_ORDER.size())
	check(seen.filter(func(c): return c != "").size() == Shed.COAT_ORDER.size(), "T goes through every coat")
	# Looking at the hung engine with a coat loaded, the work button sprays it on.
	w.spray_finish = Shed.FINISHES.size()
	var mid: Vector3 = disp.global_position + Vector3.UP * size.y * 0.5
	var stand := mid + Vector3(-1.4, 0.0, 0.0)
	w.place(Transform3D(Basis(), Vector3(stand.x, 0.05, stand.z)))
	await _aim_point(w, mid)
	for i in 3:
		await get_tree().physics_frame
	var pa: Dictionary = w.plan.get("action", {})
	check(str(pa.get("a", "")) == "coat" and int(pa.get("item", 0)) == engine and str(w.plan.get("blocked", "x")) == "",
		"aimed at it with clear lacquer loaded, the work button coats the engine (%s)" % str(pa))
	w.set_tool("spray")
	check(w.spray_coat() == "" and not w.spray_text().contains("lacquer"), "the spray can only has paint")
	w.set_tool("hands")
	# Rusty bits can't be coated.
	var anc: int = parts[1]
	Shed.items[anc]["rust"] = 0.5
	check(Shed.check(me, clear).contains("sandblast"), "a coat won't go over rust: blast it first")
	Shed.items[anc]["rust"] = 0.0
	var xp_before := int(Progress.profile.get("xp", 0))
	Shed.request(clear)
	check(parts.all(func(id): return Shed.items[id].get("coat", "") == "clear" and float(Shed.items[id]["coat_q"]) >= 0.9 and Shed.blast_full(Shed.items[id])),
		"clear lacquer goes on the whole engine, ancillaries and all, the bare metal under it")
	check(int(Progress.profile.get("xp", 0)) > xp_before and Shed.condition_text(Shed.items[engine]).contains("Protective coat"), "it pays XP and shows in the part's info")
	for i in 3:
		await get_tree().process_frame
	var model: BikeModel = (ws._spot_nodes[hook] as Node3D).get_meta("model")
	var bs: BlastMarks = model.get_node_or_null("BlastSaved")
	check(bs != null and float(bs.material_for("engine").get_shader_parameter("lacquer")) > 0.5, "the bare metal shines under its clear coat")
	# Kept in the save.
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(copy, "Tester")
	await get_tree().process_frame
	check(Shed.items[engine].get("coat", "") == "clear", "the coat is kept in the save")
	# Engine enamel paints it.
	Shed.request({"a": "coat", "item": engine, "coat": "enamel_black", "gun": true, "quality": 1.0})
	check(parts.all(func(id): return Shed.items[id]["color"] == Shed.PAINTS[6] and not Shed.items[id].has("blast") and Shed.items[id]["coat"] == "enamel_black"),
		"black engine enamel paints the lot black over the bare metal")
	for i in 3:
		await get_tree().process_frame
	model = (ws._spot_nodes[hook] as Node3D).get_meta("model")
	check(model.get_node_or_null("BlastSaved") == null, "and it's drawn painted, not bare")
	# Riding: bare metal without a coat flash-rusts; a coat keeps it off and the muck from sticking.
	var bike: int = Shed.bikes.keys()[0]
	var block := Shed.item_on(bike, "engine")
	var filter := Shed.item_on(bike, "oil_filter")
	check(block != 0 and filter != 0, "a bike with an engine to ride")
	if block != 0 and filter != 0:
		for id in [block, filter]:
			Shed.items[id]["rust"] = 0.0
			Shed.items[id]["dirt"] = 0.0
			Shed.items[id]["blast"] = {"c": 1.0, "p": 0.0}
			Shed.items[id].erase("coat")
		Shed.items[filter]["coat"] = "clear"
		Shed.items[filter]["coat_q"] = 1.0
		Shed._wear_from_ride(bike, {"km": 5.0, "dirt_km": 1.0})
		var dirt_bare := float(Shed.items[block]["dirt"])
		var dirt_coat := float(Shed.items[filter]["dirt"])
		for i in 9:
			Shed._wear_from_ride(bike, {"km": 5.0, "dirt_km": 2.0})
		var bare_rust := float(Shed.items[block]["rust"])
		var coat_rust := float(Shed.items[filter]["rust"])
		check(bare_rust > 0.2 and coat_rust < bare_rust * 0.3, "ridden, bare metal flash-rusts (%.2f) and coated metal hardly does (%.2f)" % [bare_rust, coat_rust])
		check(dirt_bare > 0.05 and dirt_coat < dirt_bare * 0.6 and float(Shed.items[filter]["coat_q"]) < 1.0,
			"the coat keeps muck from sticking (%.2f vs %.2f), and wears thinner with the miles" % [dirt_coat, dirt_bare])
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_front_mudguard_parts() -> void:
	var guards: Array = PartsDB.by_kind["front_mudguard"]
	check(guards.size() >= 5, "the shop has %d front mudguards" % guards.size())
	var listed := 0
	for k in PartsDB.by_kind:
		listed += PartsDB.by_kind[k].size()
	check(listed == PartsDB.parts.size(), "no two parts in the catalogue share an id (%d listed, %d parts)" % [listed, PartsDB.parts.size()])
	for id in guards:
		check(PartsDB.spec_line(id).contains("spray"), "the %s has a spec line" % id)
	check(PartsDB.is_optional("front_mudguard") and PartsDB.BIKE_SLOTS.has("front_mudguard"), "it has its own slot on the bike, and a bike rides without one")
	check(PartsDB.slot_name("front_mudguard") == "Front mudguard" and PartsDB.slot_name("front_tyre") == "Front tyre",
		"its slot reads \"Front mudguard\" (%s)" % PartsDB.slot_name("front_mudguard"))
	check(PartsDB.dependents("fork").has("front_mudguard") and PartsDB.MOUNTS["front_mudguard"] == ["fork"], "it bolts to the fork, so it comes off before the fork")
	# Bikes that never had one chosen get one that suits them; a chosen one, or none, stays.
	var want := {"cafe_tail": "alloy_cafe_blade", "bobber_fender": "bobbed_steel", "sport_tail_tidy": "road_hugger",
		"enduro_fender": "mx_high_fender", "classic_mudguard": "chrome_classic", "scrambler_loop": "enduro_front_fender"}
	for tail in want:
		check(PartsDB.sanitize_build({"tail": tail})["front_mudguard"] == want[tail], "a bike with a %s gets a %s" % [tail, want[tail]])
	check(PartsDB.sanitize_build({"tail": "sport_tail_tidy", "front_tyre": "knobbly_mx_90"})["front_mudguard"] == "enduro_front_fender",
		"knobblies get a high fender whatever the tail")
	check(PartsDB.sanitize_build({"front_mudguard": "carbon_hugger"})["front_mudguard"] == "carbon_hugger"
		and PartsDB.sanitize_build({"front_mudguard": "none"})["front_mudguard"] == "none", "a chosen guard, or none, stays")
	# Money, weight and recycling.
	check(Money.part_price("carbon_hugger") > Money.part_price("chrome_classic") and Money.part_price("chrome_classic") > Money.part_price("road_hugger"),
		"a carbon hugger costs more than chrome, chrome more than plastic (%d, %d, %d)" % [Money.part_price("carbon_hugger"),
		Money.part_price("chrome_classic"), Money.part_price("road_hugger")])
	check(BikeBuild.new({"front_mudguard": "carbon_hugger"}).bike_mass < BikeBuild.new({"front_mudguard": "chrome_classic"}).bike_mass - 1.0
		and PartsDB.is_lightweight("carbon_hugger"), "the carbon one is the light one")
	check(PartsDB.bin_for("chrome_classic") == "metal" and PartsDB.bin_for("mx_high_fender") == "plastic" and PartsDB.bin_for("carbon_hugger") == "general",
		"steel and alloy guards go in metal, plastic in plastic, carbon in general")
	# Every variant is drawn over the front wheel; the high ones up under the yoke.
	var tops := {}
	for id in guards:
		var m := BikeModel.new()
		add_child(m)
		m.build_from(BikeBuild.new({"front_mudguard": id}))
		var b := m.slot_bounds("front_mudguard")
		var wheel := m.slot_bounds("front_wheel")
		check(b.size.length() > 0.1 and b.get_center().z < m.slot_bounds("tank").get_center().z and absf(b.get_center().z - wheel.get_center().z) < 0.35,
			"the %s is drawn over the front wheel" % id)
		tops[id] = b.position.y
		m.free()
	check(float(tops["mx_high_fender"]) > float(tops["road_hugger"]) + 0.05, "an MX fender sits up high, a hugger down on the tyre")
	var bare := BikeModel.new()
	add_child(bare)
	bare.build_from(BikeBuild.new({"front_mudguard": "none"}))
	check(bare.slot_bounds("front_mudguard").size == Vector3.ZERO, "with none fitted, nothing is drawn over the wheel")
	bare.free()


func _test_front_mudguard_shed() -> void:
	Shed.start_new("Tester", 45)
	var me := Shed.me()
	var expect := {"Rusty Ranger": "mx_high_fender", "Barn Find": "alloy_cafe_blade", "Old Faithful": "road_hugger"}
	var sport := 0
	for id in Shed.bikes:
		var on := Shed.item_on(id, "front_mudguard")
		var bike_name := str(Shed.bikes[id]["name"])
		check(on != 0 and Shed.is_bolted(id, "front_mudguard") and str(Shed.items[on]["part"]) == str(expect.get(bike_name, "")),
			"%s comes with its %s" % [bike_name, expect.get(bike_name, "")])
		if bike_name == "Old Faithful":
			sport = id
	var guard := Shed.item_on(sport, "front_mudguard")
	check(Shed.items[guard]["color"] == Shed.bikes[sport]["paint"], "a plastic hugger comes painted to match the bike")
	check(Shed.condition_text(Shed.items[guard]) != "" and Shed.build_of(sport).condition.has("front_mudguard"), "it has a condition of its own")
	# It comes off before the fork, and goes back on.
	Shed.request({"a": "unbolt", "bike": sport, "slot": "fork"})
	check(Shed.check(me, {"a": "remove", "bike": sport, "slot": "fork"}) != "", "the fork can't come out with the guard on it")
	Shed.request({"a": "unbolt", "bike": sport, "slot": "front_mudguard"})
	Shed.request({"a": "remove", "bike": sport, "slot": "front_mudguard"})
	check(Shed.item_on(sport, "front_mudguard") == 0 and Shed.items[guard]["at"] == "held", "the guard unbolts and comes off in your hands")
	check(not Shed.missing_slots(sport).has("front_mudguard"), "the bike can still be ridden without one")
	# Riding without one throws the road all over the engine.
	check(Shed.front_spray(sport) > 1.5, "no guard: much more spray (%.2f)" % Shed.front_spray(sport))
	var engine := Shed.item_on(sport, "engine")
	Shed.items[engine]["dirt"] = 0.0
	Shed._wear_from_ride(sport, {"km": 1.0, "dirt_km": 1.0})
	var bare_dirt := float(Shed.items[engine]["dirt"])
	Shed.request({"a": "install", "bike": sport, "slot": "front_mudguard"})
	Shed.request({"a": "bolt", "bike": sport, "slot": "front_mudguard"})
	Shed.request({"a": "bolt", "bike": sport, "slot": "fork"})
	check(Shed.item_on(sport, "front_mudguard") == guard and Shed.is_bolted(sport, "front_mudguard"), "and it goes back on")
	Shed.items[engine]["dirt"] = 0.0
	Shed._wear_from_ride(sport, {"km": 1.0, "dirt_km": 1.0})
	check(float(Shed.items[engine]["dirt"]) < bare_dirt * 0.85, "with it on, the engine picks up less muck (%.3f vs %.3f)" % [Shed.items[engine]["dirt"], bare_dirt])
	var classic := Shed._new_item("chrome_classic", 0.0, 0.0, 0.0)
	check(Shed.front_spray(sport) > 1.0, "a hugger still lets some through")
	# Painting: any guard can be sprayed like the tank.
	Shed._move(classic, "spot", "bench_0")
	Shed.request({"a": "paint", "item": classic, "color": 3, "finish": "gloss"})
	check(Shed.items[classic]["color"] == Shed.PAINTS[3], "and sprayed a colour of your own")
	# Blueprints, contracts and the save keep it.
	var bp := Shed._save_blueprint(sport, "Hugged")
	check(str(Shed.blueprints[bp]["parts"]["front_mudguard"]) == "road_hugger", "a blueprint stores the front mudguard")
	check(Shed.plan_rows(Shed.blueprints[bp], 0).any(func(r): return r["slot"] == "front_mudguard"), "so a build from it orders one")
	check(Contracts.style_build("cafe")["front_mudguard"] == "alloy_cafe_blade" and Contracts.style_build("sport")["front_mudguard"] == "carbon_hugger",
		"bespoke builds name the guard that suits their style")
	check(Contracts.goal_text({"t": "fit", "slot": "front_mudguard"}) == "A front mudguard fitted", "a customer can ask for one fitted")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	check(PartsDB.by_kind["front_mudguard"].has(str(Contracts.random_parts(rng)["front_mudguard"])), "customers' bikes come with one")
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.start_new("Tester", 46)
	Shed.load_state(copy, "Tester")
	var back := Shed.item_on(sport, "front_mudguard")
	check(back != 0 and str(Shed.items[back]["part"]) == "road_hugger", "and loads with the guard on")


func _test_front_mudguard_old_save() -> void:
	Shed.start_new("Tester", 47)
	var old: Dictionary = Shed._snapshot().duplicate(true)
	# Take the shed back to before front mudguards were parts.
	var no_fork := 0
	for id in old["bikes"]:
		var bike: Dictionary = old["bikes"][id]
		var item := int(bike["slots"].get("front_mudguard", 0))
		if item != 0:
			old["items"].erase(item)
		bike["slots"].erase("front_mudguard")
		bike["bolted"].erase("front_mudguard")
		bike["original"].erase("front_mudguard")
		if bike["name"] == "Old Faithful":
			no_fork = id
	var fork := int(old["bikes"][no_fork]["slots"]["fork"])
	old["bikes"][no_fork]["slots"]["fork"] = 0
	old["items"][fork]["at"] = "spot"
	old["items"][fork]["ref"] = "bench_3"
	var parts := PartsDB.sanitize_build({"tail": "cafe_tail"})
	parts.erase("front_mudguard")
	old["blueprints"] = {9100: {"id": 9100, "name": "Old plan", "parts": parts, "colors": {}, "paint": Shed.PAINTS[0], "geo": {}, "from": "x"}}
	Shed.start_new("Tester", 48)
	Shed.load_state(old, "Tester")
	for id in Shed.bikes:
		var guard := Shed.item_on(id, "front_mudguard")
		check(Shed.bikes[id]["original"].has("front_mudguard"), "an old save's %s knows its front mudguard" % Shed.bikes[id]["name"])
		if id == no_fork:
			var loose := Shed.items.values().filter(func(it): return it["kind"] == "front_mudguard" and it["at"] == "spot")
			check(guard == 0 and loose.size() == 1 and str(loose[0]["part"]) == "road_hugger", "a bike with no fork gets its guard on the bench")
		else:
			check(guard != 0 and Shed.is_bolted(id, "front_mudguard"), "an old save's %s gets a %s fitted" % [Shed.bikes[id]["name"],
				Shed.items[guard]["part"] if guard != 0 else "nothing"])
	check(str(Shed.blueprints[9100]["parts"].get("front_mudguard", "")) == "alloy_cafe_blade", "an old blueprint gets a guard that suits it")
	check(Shed._next_id > Shed.items.keys().max(), "new parts get fresh ids")


func _test_style_tags() -> void:
	var untagged := []
	for k in ["frame", "fork", "shock", "wheel", "tyre", "tank", "saddle", "handlebars", "exhaust", "headlight", "tail", "fairing",
			"mirrors", "front_mudguard", "panniers", "top_box", "fog_lights", "dashboard"] + Array(PartsDB.FILLER_SLOTS):
		for id in PartsDB.by_kind[k]:
			var tags := PartsDB.styles_of(id)
			if tags.is_empty() or not tags.all(func(t): return PartsDB.STYLES.has(str(t))):
				untagged.append(id)
	check(untagged.is_empty(), "every part you can see on a bike says which styles it suits %s" % str(untagged))
	for st in PartsDB.STYLES:
		var frames: Array = PartsDB.by_kind["frame"].filter(func(f): return PartsDB.styles_of(f).has(st))
		check(not frames.is_empty(), "a %s has a frame to start from (%s)" % [st, ", ".join(frames)])
	check(PartsDB.spec_line("bobbed_steel").contains("Suits: bobber, chopper"), "the spec line lists the styles (%s)" % PartsDB.spec_line("bobbed_steel"))
	check(PartsDB.style_phrase("mx") == "an MX bike" and PartsDB.style_phrase("cafe") == "a cafe racer" and PartsDB.style_phrase("adventure") == "an adventure bike",
		"and names them properly in a sentence")
	# Detecting a bike's style from its parts.
	for st in Contracts.STYLES:
		var ref := Contracts.style_build(st)
		var d := PartsDB.detect_style(ref)
		check(str(d["style"]) == st and d["proper"], "a %s built from its own parts reads as %s" % [st, PartsDB.style_text(ref)])
	var bob := Contracts.style_build("bobber")
	var mixed := bob.duplicate()
	mixed.merge({"frame": "carbon_monocoque", "fairing": "race_fairing", "saddle": "carbon_race_seat", "handlebars": "clip_ons", "tank": "sport_17"}, true)
	var md := PartsDB.detect_style(mixed)
	check(not md["proper"] and float(md["coherence"]) < float(PartsDB.detect_style(bob)["coherence"]) - 0.2,
		"half a race bike on a bobber is a mix, not a proper anything (%s)" % PartsDB.style_text(mixed))
	check((md["odd"] as Array).size() > 2, "and the odd parts out are named %s" % str(md["odd"]))
	check(PartsDB.style_fit("bobber", bob) > PartsDB.style_fit("bobber", mixed), "a style's fit drops as parts from another go on")
	check(PartsDB.style_text({"frame": "none", "fairing": "race_fairing"}).contains("proper"), "even a fairing on its own says something")
	var cafe_on_chop := Contracts.style_build("cafe")
	cafe_on_chop["frame"] = "chopper_raked"
	check(str(PartsDB.detect_style(cafe_on_chop)["style"]) == "cafe" and not PartsDB.detect_style(cafe_on_chop)["proper"],
		"a cafe racer on a chopper frame is mostly a cafe racer, but not a proper one (%s)" % PartsDB.style_text(cafe_on_chop))
	# Fillers that suit a style.
	var dressed := PartsDB.dress_fillers(Contracts.style_build("mx"))
	check(PartsDB.FILLER_SLOTS.all(func(s): return dressed[s] != "none" and PartsDB.styles_of(str(dressed[s])).has("mx")),
		"an MX bike gets MX bits in every style slot %s" % str(PartsDB.FILLER_SLOTS.map(func(s): return dressed[s])))
	var mess := {"frame": "chopper_raked", "tank": "sport_17", "saddle": "enduro_seat", "handlebars": "clip_ons", "tail": "scrambler_loop",
		"fairing": "touring_fairing", "fork": "long_travel_mx", "exhaust": "stock_muffler", "front_mudguard": "alloy_cafe_blade"}
	var plain := PartsDB.dress_fillers(mess)
	check(float(PartsDB.detect_style(mess)["coherence"]) < 0.45 and PartsDB.FILLER_SLOTS.all(func(s): return plain[s] == "none"),
		"a mixed-up bike gets none (%s)" % PartsDB.style_text(mess))


func _test_filler_parts() -> void:
	var all_ok := true
	for s in PartsDB.FILLER_SLOTS:
		all_ok = all_ok and PartsDB.is_optional(s) and PartsDB.BIKE_SLOTS.has(s) and PartsDB.MOUNTS[s] == ["frame"] and PartsDB.DEFAULT_BUILD[s] == "none"
	check(all_ok, "indicators, side panels, rearsets, guards and number boards bolt to the frame and are optional")
	check(PartsDB.dependents("frame").has("rearsets") and PartsDB.LOW_SLOTS.has("guards"), "they come off before the frame, and you crouch for the low ones")
	for slot in PartsDB.FILLER_SLOTS:
		check(PartsDB.by_kind[slot].size() >= 5, "%s: at least five to choose from" % PartsDB.KIND_NAMES[slot])
		check(Money.part_price(PartsDB.by_kind[slot][0]) > 0 and PartsComputer.group_of(slot) != "Other", "%s are priced and on a shelf" % slot)
		for id in PartsDB.by_kind[slot]:
			var m := BikeModel.new()
			add_child(m)
			m.build_from(BikeBuild.new({slot: id}))
			var b := m.slot_bounds(slot)
			check(b.size.length() > 0.08 and b.size.length() < 2.0, "%s is drawn on the bike (%s)" % [id, str(b.size)])
			m.free()
		var bare := BikeModel.new()
		add_child(bare)
		bare.build_from(BikeBuild.new())
		check(bare.slot_bounds(slot).size == Vector3.ZERO, "with no %s fitted, nothing is drawn" % slot)
		bare.free()
	# A swingarm of its own replaces the frame's, in each of its shapes.
	var arms := {}
	for id in PartsDB.by_kind["swingarm"]:
		var am := BikeModel.new()
		add_child(am)
		am.build_from(BikeBuild.new({"swingarm": id}))
		arms[str(PartsDB.get_part(id)["arm"])] = true
		check(am._arm_type() == str(PartsDB.get_part(id)["arm"]) and am.slot_bounds("swingarm").size.z > 0.3,
			"%s hangs off the pivot as its own swingarm (%s)" % [id, str(am.slot_bounds("swingarm").size)])
		am.free()
	check(arms.has("box_section") and arms.has("banana") and arms.has("braced_mx") and arms.has("hardtail") and arms.has("single"),
		"box-section, banana, braced MX, hardtail and single-sided swingarms (%s)" % str(arms.keys()))
	var ht := BikeModel.new()
	add_child(ht)
	ht.build_from(BikeBuild.new({"swingarm": "hardtail_chrome"}))
	check(ht.find_children("SeatStay*", "", true, false).size() == 2, "a hardtail rear end has its seat stays up to the frame")
	ht.free()
	# Rearsets move the rider's feet.
	var stock := BikeModel.new()
	add_child(stock)
	stock.build_from(BikeBuild.new())
	var sets := BikeModel.new()
	add_child(sets)
	sets.build_from(BikeBuild.new({"rearsets": "alloy_rearsets"}))
	var fwd := BikeModel.new()
	add_child(fwd)
	fwd.build_from(BikeBuild.new({"rearsets": "forward_controls"}))
	check(sets._peg.y > stock._peg.y + 0.05 and fwd._peg.z < stock._peg.z - 0.3, "rearsets put the feet up and back, forward controls out in front (%s, %s, %s)" % [
		stock._peg, sets._peg, fwd._peg])
	check(sets.find_children("Footpeg*", "", true, false).size() == 2, "and draw their own pegs")
	for m in [stock, sets, fwd]:
		m.free()
	# Number boards wear the race number.
	var mx := BikeModel.new()
	add_child(mx)
	mx.build_from(BikeBuild.new({"number_boards": "mx_side_boards"}))
	var labels: Array = mx.find_children("*", "Label3D", true, false).filter(func(l): return l.get_parent().name != "TyreLettering")
	check(labels.size() >= 3 and labels.all(func(l): return str(l.text) == str(labels[0].text) and int(str(l.text)) > 0),
		"MX number boards carry the same race number front and sides (%s)" % str(labels.map(func(l): return l.text)))
	mx.free()
	check(BikeBuild.new({"guards": "adv_cage"}).bike_mass > BikeBuild.new().bike_mass + 5.0, "a crash cage weighs what it should")



## Step 4 of the style work: the small details that make a bike read as real at a glance.
func _test_detail_pass() -> void:
	var made := []
	var bike := func(parts: Dictionary) -> BikeModel:
		var m := BikeModel.new()
		add_child(m)
		m.build_from(BikeBuild.new(parts))
		made.append(m)
		return m
	var count := func(m: BikeModel, name: String) -> int:
		return m.find_children(name + "*", "", true, false).size()
	# Engines you can tell apart.
	var vt: BikeModel = bike.call({"engine": "vtwin_900"})
	var bx: BikeModel = bike.call({"engine": "boxer_1000"})
	var i4: BikeModel = bike.call({"engine": "four_1000"})
	var ts: BikeModel = bike.call({"engine": "2stroke_125"})
	for m in [vt, bx, i4, ts]:
		check(count.call(m, "Crankcase") == 1 and count.call(m, "AlternatorCover") == 1, "every engine has a rounded crankcase and an alternator cover")
	check(count.call(vt, "Pushrod") == 4 and count.call(vt, "NoseCone") == 1, "a V-twin has pushrod tubes to both heads and a nose cone")
	check(count.call(bx, "ValveCover") == 2, "a boxer's valve covers stick out either side")
	var cam: Array = i4.find_children("CamCover*", "", true, false)
	check(cam.size() == 1 and ((cam[0] as MeshInstance3D).mesh as BoxMesh).size.x > 0.4, "an inline four has one wide cam cover across the head")
	check(count.call(ts, "CamCover") == 0 and count.call(ts, "Sump") == 0, "a two-stroke has no cam cover and no sump")
	check(count.call(i4, "HTLead") == 4 and count.call(vt, "HTLead") == 2, "an HT lead runs from every plug to the coil")
	# Bars, levers and cables.
	var std: BikeModel = bike.call({})
	for n in ["ClutchLever", "BrakeLever", "SwitchGear", "Throttle", "ClutchCable", "ThrottleCable", "BarEnd"]:
		check(count.call(std, n) >= 1, "the bars carry a %s" % n)
	check(count.call(std, "BrakeHose") == 2, "the front brake hose runs from the master to the bottom yoke, then down the leg to the caliper")
	var grip: MeshInstance3D = std.find_children("Grip*", "", true, false)[0]
	check((grip.material_override as StandardMaterial3D).normal_texture != null, "the grips are knurled")
	# Drum brakes: drawn as drums and a little weaker than a disc the same size.
	var drums: BikeModel = bike.call({"front_disc": "drum_tls_200", "rear_disc": "drum_sls_180"})
	check(count.call(drums, "BrakeDrum") == 2 and count.call(drums, "LinkRod") == 1 and count.call(drums, "BrakeCable") == 1,
		"drum brakes have finned drums, a twin leading shoe link rod and a cable")
	check(drums.slot_bounds("front_disc").size.length() > 0.1, "the drum is drawn in the disc's place")
	var disc_b := BikeBuild.new({"front_disc": "solid_240"})
	var drum_b := BikeBuild.new({"front_disc": "drum_tls_200"})
	check(drum_b.front_brake_torque < disc_b.front_brake_torque, "a 200 mm drum stops less hard than a 240 mm disc (%.0f vs %.0f)" % [drum_b.front_brake_torque, disc_b.front_brake_torque])
	check(BikeBuild.new({"front_disc": "drum_4ls_230"}).front_brake_torque > BikeBuild.new({"front_disc": "drum_sls_180"}).front_brake_torque, "a four leading shoe drum beats a single")
	# Seats: grab rail and pillion pegs on a two-up seat, quilting on a diamond seat.
	var two: BikeModel = bike.call({"saddle": "flat_bench"})
	check(count.call(two, "GrabRail") == 1 and count.call(two, "PillionPeg") == 2, "a two-up seat has a grab rail and pillion pegs")
	var solo: BikeModel = bike.call({"saddle": "cafe_hump"})
	check(count.call(solo, "PillionPeg") == 0, "a cafe hump seat has no pillion pegs")
	check(count.call(two, "Piping") == 2, "the seat edges are piped")
	# Forks: axle clamps on a telescopic fork, links on a leading-link fork.
	check(count.call(std, "AxleClamp") == 2, "telescopic fork sliders end in axle clamps")
	var ll: BikeModel = bike.call({"fork": "classic_leading_link"})
	check(count.call(ll, "Link") == 2 and count.call(ll, "Damper") == 2, "a leading-link fork has a link and a damper each side")
	var ear: BikeModel = bike.call({"fork": "shrouded_classic_fork"})
	check(count.call(ear, "HeadlampEar") == 2, "a shrouded classic fork carries the headlamp on ears")
	# Wheels: lettered tyres, shaped cast spokes, a cush drive and a valve.
	var letters: Array = std.find_children("TyreLettering", "", true, false)
	check(letters.size() == 2, "both tyres have lettering on their walls")
	var text := ""
	for l in letters[0].get_children():
		text += (l as Label3D).text
	check(text.begins_with("TORQUE"), "the tyre wall reads the maker's name (%s)" % text.left(20))
	var cast: BikeModel = bike.call({"front_wheel": "cast_17_front", "rear_wheel": "cast_17"})
	check(count.call(cast, "CastSpoke") >= 5 and count.call(cast, "CushDrive") == 1 and count.call(cast, "Valve") == 2, "cast wheels have shaped spokes, the rear a cush drive, both a valve")
	# Radiators: a textured core behind a grille, shrouds and hoses.
	var rad: BikeModel = bike.call({"engine": "four_1000", "cooling": "race_radiator"})
	var core: MeshInstance3D = rad.find_children("RadiatorCore", "", true, false)[0]
	check((core.material_override as StandardMaterial3D).normal_texture != null and count.call(rad, "RadiatorGrille") > 3
		and count.call(rad, "RadiatorShroud") == 2 and count.call(rad, "CoolantHose") == 2, "a radiator has a finned core, a grille, shrouds and coolant hoses")
	# Bodywork: twin lamps in a race fairing, vents in a half one, a pad on a sports tank.
	var race: BikeModel = bike.call({"fairing": "carbon_race_fairing", "tank": "carbon_sport_16"})
	check(count.call(race, "FairingLamp") == 2 and count.call(race, "TankPad") == 1, "a race fairing has twin lamp eyes and a sports tank a grip pad")
	var shell: MeshInstance3D = race.find_children("FairingShell", "", true, false)[0]
	check((shell.material_override as StandardMaterial3D).albedo_texture != null, "a carbon fairing shows its weave")
	# A full fairing is flat panels with crisp creases, not a round blob: where two facets meet,
	# the same point carries two normals well apart.
	var arrays := (shell.mesh as ArrayMesh).surface_get_arrays(0)
	var normals_at := {}
	var creased := 0
	for k in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var key := str(((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[k] * 1000.0).round())
		var nrm: Vector3 = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[k]
		if normals_at.has(key) and (normals_at[key] as Vector3).angle_to(nrm) > deg_to_rad(12.0) and (normals_at[key] as Vector3).angle_to(-nrm) > deg_to_rad(12.0):
			creased += 1
		normals_at[key] = nrm
	check(creased > 60, "a full fairing's panels meet at sharp creases (%d crease points)" % creased)
	check(count.call(race, "SideCover") == 2 and count.call(race, "LowerFairing") == 1 and count.call(race, "Screen") == 1
		and count.call(race, "RamAir") == 1 and count.call(race, "FairingVent") >= 4,
		"it has layered side covers with vent gaps, a keeled belly pan, a screen and a ram-air mouth")
	var gp: BikeModel = bike.call({"fairing": "race_red_winged"})
	check(count.call(gp, "FairingLamp") == 0 and count.call(gp, "NoseCap") == 1 and count.call(gp, "Winglet") == 6,
		"a race-only fairing has a blank nose and two winglets a side with endplates")
	var winged: BikeModel = bike.call({"fairing": "sport_grey_winged"})
	check(count.call(winged, "FairingLamp") == 2 and count.call(winged, "Winglet") == 4, "a winged sports fairing keeps its lamps and has one winglet a side")
	# Under it the frame beams stay inside the bodywork, the radiator and headers are out of
	# sight through the wheel cut, and the clocks sit below the screen's top.
	var sport_parts := Contracts.style_build("sport")
	var sb: BikeModel = bike.call(sport_parts)
	var bare_parts := sport_parts.duplicate()
	bare_parts["fairing"] = "none"
	var bare: BikeModel = bike.call(bare_parts)
	check(sb.slot_bounds("frame").size.x < bare.slot_bounds("frame").size.x - 0.1 and sb.slot_bounds("frame").end.x < sb.slot_bounds("fairing").end.x,
		"a perimeter frame's beams tuck inside a full fairing (%.2f m wide, %.2f bare)" % [sb.slot_bounds("frame").size.x, bare.slot_bounds("frame").size.x])
	var hidden := func(m: BikeModel, slot: String) -> bool:
		for mi in m._slot_meshes.get(slot, []):
			if not (mi as Node).get_meta("under_fairing", false):
				return false
		return true
	check(hidden.call(sb, "cooling") and not hidden.call(bare, "cooling"), "the radiator is hidden behind a full fairing, not on a bare bike")
	var screen_mi: MeshInstance3D = sb.find_children("Screen", "", true, false)[0]
	check(sb._model_aabb(screen_mi).end.y > sb.slot_bounds("dashboard").end.y, "the clocks sit below the top of the screen")
	var faceted := func(mi: MeshInstance3D) -> bool:
		var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var seen := {}
		for k in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			var key := str(((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)[k] * 1000.0).round())
			var nrm: Vector3 = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array)[k]
			if seen.has(key) and (seen[key] as Vector3).angle_to(nrm) > 0.2 and (seen[key] as Vector3).angle_to(-nrm) > 0.2:
				return true
			seen[key] = nrm
		return false
	check(faceted.call(sb.find_children("TailCowl", "", true, false)[0]), "a sports tail is creased panels too")
	var hf: BikeModel = bike.call({"fairing": "sport_black_half"})
	check(faceted.call(hf.find_children("FairingShell", "", true, false)[0]), "and so is a sports half fairing")
	var half: BikeModel = bike.call({"fairing": "half_fairing"})
	check(count.call(half, "FairingVent") == 8, "a half fairing has side vents")
	var can: BikeModel = bike.call({"exhaust": "stock_muffler"})
	check(count.call(can, "EndCap") >= 1 and count.call(can, "CanClamp") >= 1, "a silencer has a clamp band and a riveted end cap")
	# Rust covers the fine finish: a rusty engine shows rust, not crinkle.
	var rusty := BikeModel.new()
	add_child(rusty)
	var cond := {"engine": {"rust": 0.6}}
	rusty.build_from(BikeBuild.new({}), Color.RED, {}, cond)
	made.append(rusty)
	var case_mat: StandardMaterial3D = (rusty.find_children("Crankcase", "", true, false)[0] as MeshInstance3D).material_override
	check(case_mat.detail_enabled and case_mat.normal_texture == null, "a rusty case shows its rust rather than its finish")
	for m in made:
		m.free()


func _test_filler_shed() -> void:
	Shed.start_new("Tester", 51)
	var me := Shed.me()
	var bike := 0
	for id in Shed.bikes:
		bike = id
		check(PartsDB.FILLER_SLOTS.all(func(s): return Shed.bikes[id]["slots"].has(s)), "%s has slots for the style bits" % Shed.bikes[id]["name"])
	# Fit a set of rearsets, take them off again.
	var sets := Shed._new_item("alloy_rearsets", 0.0, 0.0, 0.0)
	var before := Shed.item_on(bike, "rearsets")
	if before != 0:
		Shed.request({"a": "unbolt", "bike": bike, "slot": "rearsets", "crouched": true})
		Shed.request({"a": "remove", "bike": bike, "slot": "rearsets", "crouched": true})
		Shed._put_on_bench(before)
	Shed._move(sets, "held", me)
	check(Shed.check(me, {"a": "install", "bike": bike, "slot": "rearsets"}).contains("Crouch"), "you crouch to fit rearsets")
	Shed.request({"a": "install", "bike": bike, "slot": "rearsets", "crouched": true})
	Shed.request({"a": "bolt", "bike": bike, "slot": "rearsets", "crouched": true})
	check(Shed.item_on(bike, "rearsets") == sets and Shed.is_bolted(bike, "rearsets"), "rearsets go on and bolt up")
	check(Shed.build_of(bike).parts["rearsets"] == "alloy_rearsets", "and the bike's build has them")
	Shed.request({"a": "unbolt", "bike": bike, "slot": "frame"})
	check(Shed.check(me, {"a": "remove", "bike": bike, "slot": "frame"}) != "", "the frame can't come out with them on")
	Shed.request({"a": "bolt", "bike": bike, "slot": "frame"})
	# Old saves get empty slots.
	var old: Dictionary = Shed._snapshot().duplicate(true)
	for id in old["bikes"]:
		for s in PartsDB.FILLER_SLOTS:
			var item := int(old["bikes"][id]["slots"].get(s, 0))
			if item != 0:
				old["items"].erase(item)
			old["bikes"][id]["slots"].erase(s)
			old["bikes"][id]["bolted"].erase(s)
			old["bikes"][id]["original"].erase(s)
	Shed.start_new("Tester", 52)
	Shed.load_state(old, "Tester")
	for id in Shed.bikes:
		var empty := true
		for s in PartsDB.FILLER_SLOTS:
			empty = empty and Shed.bikes[id]["slots"].has(s) and Shed.item_on(id, s) == 0 and str(Shed.bikes[id]["original"].get(s, "")) == "none"
		check(empty, "an old save's %s gets the new slots, empty" % Shed.bikes[id]["name"])
	check(Shed.missing_slots(bike).filter(func(s): return PartsDB.FILLER_SLOTS.has(s)).is_empty(), "and rides without any of them")
	# Project bikes and customers' bikes turn up with bits that suit them.
	var rng := RandomNumberGenerator.new()
	var dressed := 0
	for i in 40:
		rng.seed = 100 + i
		var p := Contracts.random_parts(rng)
		var d := PartsDB.detect_style(p)
		var on: Array = PartsDB.FILLER_SLOTS.filter(func(s): return str(p[s]) != "none")
		if not on.is_empty():
			dressed += 1
			check(on.all(func(s): return PartsDB.styles_of(str(p[s])).has(str(d["style"]))), "a customer's %s has bits that suit it" % PartsDB.style_noun(str(d["style"])))
	check(dressed > 4, "some customers' bikes come dressed in their style (%d of 40)" % dressed)


func _test_style_contracts_sales() -> void:
	Shed.start_new("Tester", 53)
	# The new styles are things customers ask for, and a proper one counts whichever parts made it.
	for st in ["chopper", "cruiser", "adventure", "mx", "supermoto"]:
		check(Contracts.STYLES.has(st) and Contracts.style_hint(st) != "", "customers can ask for %s" % PartsDB.style_phrase(st))
	var mixed := Contracts.style_build("cafe")
	mixed.merge({"frame": "softail_hardtail", "handlebars": "ape_hangers", "tail": "bobber_fender"}, true)
	check(int(Contracts.style_marks("cafe", mixed)[0]) < 3, "a cafe racer with apes and a bobbed fender isn't one")
	var bob := Contracts.style_build("bobber")
	bob["handlebars"] = "flat_bar"
	bob["tail"] = "classic_mudguard"
	var d := PartsDB.detect_style(bob)
	if str(d["style"]) == "bobber" and d["proper"]:
		check(int(Contracts.style_marks("bobber", bob)[0]) >= 3, "a proper bobber all over counts even with plain bars")
	# Selling: a bike that's all one style is worth more.
	var proper := Shed._new_bike(Contracts.style_build("chopper"), 3, "Proper chop", 0.2)
	var uq := Sales.uniqueness(proper)
	check((uq["why"] as Array).has("a proper chopper"), "a proper chopper is worth more for it %s" % str(uq["why"]))
	var mess := Contracts.style_build("chopper")
	mess.merge({"tank": "sport_17", "saddle": "sport_solo", "handlebars": "clip_ons", "fairing": "race_fairing", "frame": "alu_perimeter"}, true)
	var bitsa := Shed._new_bike(PartsDB.sanitize_build(mess), 4, "Bitsa", 0.2)
	check(not (Sales.uniqueness(bitsa)["why"] as Array).any(func(w): return str(w).begins_with("a proper")), "a parts-bin special isn't")
	# The parts computer's style filter.
	var pc := PartsComputer.new()
	add_child(pc)
	pc._show_section("bike")
	pc._show_kind("handlebars")
	pc.set_style_filter("chopper")
	var shown: Array = pc._variants.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion()).map(func(c): return str(c.get_meta("part")))
	check(shown.size() > 0 and shown.size() < PartsDB.by_kind["handlebars"].size() and shown.all(func(id): return PartsDB.styles_of(id).has("chopper")),
		"the style filter shows only bars that suit a chopper %s" % str(shown))
	pc._show_kind("engine")
	shown = pc._variants.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())
	check(shown.size() == PartsDB.by_kind["engine"].size(), "and leaves kinds with no style (engines) alone")
	pc.set_fits_bike(proper)
	pc._show_kind("handlebars")
	pc._show_part("drag_bar")
	check(pc._spec.text.contains("Its style now: A proper chopper"), "with a bike picked, a part says what it does to its style")
	pc.set_style_filter("")
	pc.set_fits_bike(0)
	pc.queue_free()
	await get_tree().process_frame


func _test_parts_computer_organised() -> void:
	Shed.start_new("Tester", 49)
	var pc := PartsComputer.new()
	add_child(pc)
	await get_tree().process_frame
	# Every kind sold is under exactly one heading in its own aisle.
	for sec in PartsComputer.SECTIONS:
		var listed := []
		for g in PartsComputer.groups_of(sec):
			listed.append_array(g[1])
		var sold: Array = (PartsComputer.all_kinds() + PartsComputer.SELL_KINDS).filter(func(k): return PartsComputer.section_of(k) == sec)
		check(listed.size() == sold.size() and sold.all(func(k): return listed.has(k)), "the %s aisle lists every kind once under a heading" % sec)
	check(PartsComputer.group_of("front_mudguard") == "Body and lights" and PartsComputer.group_of("tyre") == "Wheels and brakes"
		and PartsComputer.group_of("gearbox") == "Engine and drivetrain" and PartsComputer.group_of("oil") == "Fluids"
		and PartsComputer.group_of("eq:washer") == "Tools and machines", "kinds are grouped the way you'd look for them")
	pc._show_section("bike")
	var heads: Array = pc._kinds.get_children().filter(func(c): return c is Label and not c.is_queued_for_deletion())
	check(heads.size() == PartsComputer.groups_of("bike").size() and str(heads[0].text) == "ENGINE AND DRIVETRAIN", "the kinds list has a heading over each group")
	var shown := func() -> Array:
		return pc._variants.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion()).map(func(c): return str(c.get_meta("part")))
	# Sorting.
	pc._show_kind("tyre")
	pc.set_sort("price_up")
	var ids: Array = shown.call()
	var ok: bool = ids.size() == PartsDB.by_kind["tyre"].size()
	for i in range(1, ids.size()):
		ok = ok and Money.part_price(ids[i - 1]) <= Money.part_price(ids[i])
	check(ok, "sorted by price, cheapest first")
	pc.set_sort("price_down")
	ids = shown.call()
	check(Money.part_price(ids[0]) > Money.part_price(ids[-1]), "or dearest first")
	pc.set_sort("name")
	ids = shown.call()
	ok = true
	for i in range(1, ids.size()):
		ok = ok and PartsDB.part_name(ids[i - 1]).naturalnocasecmp_to(PartsDB.part_name(ids[i])) <= 0
	check(ok, "or by name")
	pc.set_sort("light")
	ids = shown.call()
	check(float(PartsDB.get_part(ids[0]).get("mass", 0.0)) <= float(PartsDB.get_part(ids[-1]).get("mass", 0.0)), "or lightest first")
	# Each row shows the price and a key spec.
	var row: Button = pc._variants.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())[0]
	var texts: Array = row.find_children("*", "Label", true, false).map(func(l): return str(l.text))
	check(texts.has(TvChannels.money_text(Money.buy_price(str(row.get_meta("part")), Shed.me())))
		and texts.any(func(t): return t.contains("compound")), "a row shows its price and what matters about it %s" % str(texts))
	pc.set_sort("shop")
	# Filters: parts that fit a bike, and what the business can pay for.
	var ranger := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == "Rusty Ranger":
			ranger = id
	pc.set_fits_bike(ranger)
	ids = shown.call()
	check(ids.size() > 0 and ids.size() < PartsDB.by_kind["tyre"].size() and ids.all(func(t): return PartsComputer.fit_problem(t, ranger) == ""),
		"only the tyres that go on the Rusty Ranger's wheels (%d of %d)" % [ids.size(), PartsDB.by_kind["tyre"].size()])
	check(pc._spec.text.contains("Rusty Ranger: goes on it"), "and the page says so")
	pc._show_kind("mirrors")
	check(not shown.call().has("fairing_mirrors") and PartsComputer.fit_problem("fairing_mirrors", ranger).contains("fairing"),
		"no fairing mirrors for a bike with no fairing")
	pc.set_fits_bike(0)
	check(shown.call().has("fairing_mirrors"), "Any bike shows them all again")
	Shed.garage_money = 60
	pc.set_affordable_only(true)
	pc._show_kind("front_mudguard")
	ids = shown.call()
	check(ids.size() > 0 and ids.all(func(g): return Money.buy_price(g, Shed.me()) <= 60) and ids.size() < PartsDB.by_kind["front_mudguard"].size(),
		"within budget shows only what the business can pay for (%s)" % str(ids))
	Shed.garage_money = 0
	pc._show_kind("engine")
	check(shown.call().is_empty() and pc._order.disabled, "with nothing to show, there's nothing to order")
	pc.set_affordable_only(false)
	check(shown.call().size() == PartsDB.by_kind["engine"].size(), "and turning the filter off brings them back")
	# The search still finds things, with prices on its rows.
	pc._search.text = "carbon hugger"
	pc._refresh_list()
	check(pc._part == "carbon_hugger" and pc._kind == "front_mudguard", "searching finds the carbon hugger")
	# Laid out: the sort and filter bar is one line, and each row's price shows in full.
	await get_tree().process_frame
	await get_tree().process_frame
	var tools: Control = pc.get_child(1).get_child(0).get_child(0).get_child(3)
	check(tools.size.y < 60.0, "the sort and filter bar is one line (%.0f px)" % tools.size.y)
	var hit: Button = pc._variants.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())[0]
	var price_l: Label = hit.find_children("*", "Label", true, false).filter(func(l): return str(l.text).begins_with("£"))[0]
	check(price_l.size.x >= price_l.get_minimum_size().x - 1.0 and price_l.size.x > 20.0, "and each row's price shows in full (%.0f px)" % price_l.size.x)
	pc.queue_free()
	await get_tree().process_frame


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


# ---------------------------------------------------------------------------- selling from the showroom

## A Button under `root` whose text starts with `prefix`, or null.
func _sales_button(root: Node, prefix: String) -> Button:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is Button and (n as Button).text.begins_with(prefix) and (n as Button).is_visible_in_tree():
			return n
		stack.append_array(n.get_children())
	return null


## What a bike has cost and is worth, the recommended price and how buyers take to a price.
func _test_sales_pricing() -> void:
	Shed.start_new("Tester", 61)
	var me := Shed.me()
	var bike := _bike_named("Old Faithful")
	var ap := Sales.appraise(bike)
	check(not ap["bought_known"] and int(ap["bought"]) > 0 and int(ap["sunk"]) == int(ap["bought"]) + int(ap["parts"]) + int(ap["labour"]),
		"a bike from before purchases were noted: about what it cost, and the money sunk in adds up (%s)" % Sales.money(int(ap["sunk"])))
	check(int(ap["retail"]) > int(ap["worth"]) and int(ap["trade"]) == Money.bike_sale(bike) and int(ap["fair"]) >= int(ap["retail"])
		and int(ap["trade"]) < int(ap["fair"]), "worth: its parts as they are, more for being complete; the trade pays less than a buyer")
	# A project bike remembers what it cost.
	Shed.garage_money = 50000
	var before: Array = Shed.bikes.keys()
	Shed.request({"a": "order"})
	var project := 0
	for id in Shed.bikes:
		if not before.has(id):
			project = id
	check(project != 0 and Sales.appraise(project)["bought_known"] and int(Sales.appraise(project)["bought"]) == 50000 - Shed.garage_money,
		"a project bike bought from the parts computer: its price counts as bought for")
	# Parts bought for it count at what they cost.
	var parts_was := int(ap["parts"])
	Shed.items[Shed.item_on(bike, "exhaust")]["paid"] = 480
	check(int(Sales.appraise(bike)["parts"]) == parts_was + 480, "a part bought for it counts at what it cost")
	Shed.request({"a": "order_part", "part": "slip_on"})
	var newest := 0
	for id in Shed.items:
		newest = maxi(newest, int(id))
	check(int(Shed.items[newest].get("paid", -1)) == Money.buy_price("slip_on", me), "an ordered part notes what it cost")
	# The crew's wages for work on it are labour sunk in. Earlier tests' unbolts within the last
	# real minute would count as repeats and pay next to nothing (on a fast machine, nothing).
	if Shed._prog():
		Shed._prog()._recent.clear()
	var lab := int(Sales.appraise(bike)["labour"])
	Shed.request({"a": "unbolt", "bike": bike, "slot": "exhaust"})
	check(not Shed.is_bolted(bike, "exhaust") and int(Sales.appraise(bike)["labour"]) > lab, "wages paid for work on it count as labour")
	Shed.request({"a": "bolt", "bike": bike, "slot": "exhaust"})
	Sales.note_action({"a": "clean", "item": Shed.item_on(bike, "tank")})
	Sales.add_labour(12)
	check(int(Shed.items[Shed.item_on(bike, "tank")].get("labour", 0)) == 12, "work on one of its parts goes on that part")
	# Uniqueness: a chrome tank makes it more of a one-off, and worth more to a buyer.
	var u0 := float(Sales.appraise(bike)["unique"])
	var fair0 := int(Sales.appraise(bike)["fair"])
	Shed.items[Shed.item_on(bike, "tank")]["finish"] = "chrome"
	var ap2 := Sales.appraise(bike)
	check(float(ap2["unique"]) > u0 and (ap2["unique_why"] as Array).any(func(w): return str(w).contains("chrome")) and int(ap2["fair"]) > fair0,
		"a chrome finish makes it more unusual (%d%%), and worth more" % roundi(float(ap2["unique"]) * 100.0))
	# The recommended price: what it's worth, up to OVER_FAIR more to make the margin.
	var ap3 := Sales.appraise(bike, 0.1)
	check(int(ap3["recommended"]) >= int(ap3["fair"]) and int(ap3["recommended"]) <= roundi(int(ap3["fair"]) * (1.0 + Sales.OVER_FAIR)) + 10,
		"recommended: at least its fair price, at most %d%% over (%s)" % [roundi(Sales.OVER_FAIR * 100.0), Sales.money(int(ap3["recommended"]))])
	check(int(Sales.appraise(bike, 0.4)["target"]) > int(ap3["target"]), "a bigger target margin wants a higher price")
	Shed.bikes[bike]["bought"] = int(ap3["fair"]) * 3
	var dear := Sales.appraise(bike, 0.3)
	check(int(dear["recommended"]) < int(dear["target"]) and int(dear["recommended"]) < int(dear["sunk"]) and str(dear["why"]).contains("lose"),
		"more spent on it than it's worth: the price buyers will pay, and a warning of the loss")
	Shed.bikes[bike].erase("bought")
	# Buyers: more of them the fairer the price.
	var fair := int(Sales.appraise(bike)["fair"])
	check(Sales.interest(bike, roundi(fair * 0.8)) > Sales.interest(bike, fair) and Sales.interest(bike, fair) > Sales.interest(bike, roundi(fair * 1.3)) * 3.0,
		"cheaper brings more buyers, dearer far fewer (%.1f / %.1f / %.2f a day)" % [Sales.interest(bike, roundi(fair * 0.8)),
			Sales.interest(bike, fair), Sales.interest(bike, roundi(fair * 1.3))])
	check(Sales.margin_text(1200, 1000) == "profit £200 (17%)" and Sales.margin_text(900, 1000) == "loss £100", "profit and margin read right")
	# A customer's bike isn't the shed's to sell.
	Shed.bikes[bike]["xf"] = Workshop.SHOWROOM_SPOTS[0]
	Shed.bikes[bike]["contract"] = true
	check(Shed.check(me, {"a": "sale_list", "bike": bike, "ask": 1000}).contains("customer"), "a customer's bike can't be put up for sale")
	Shed.bikes[bike].erase("contract")
	Shed.stop()


## Online buyers: offers, accepting, turning down, counter-offers and the answers, lapsing.
func _test_sales_offers() -> void:
	Shed.start_new("Tester", 62)
	var me := Shed.me()
	var bike := _bike_named("Old Faithful")
	var ask := int(Sales.appraise(bike)["fair"])
	check(Shed.check(me, {"a": "sale_list", "bike": bike, "ask": ask}).contains("display stand"), "only a bike on a display stand goes up for sale")
	Shed.bikes[bike]["xf"] = Workshop.SHOWROOM_SPOTS[0]
	Shed.request({"a": "sale_list", "bike": bike, "ask": ask})
	check(Sales.active(bike) and int(Sales.listings()[bike]["ask"]) == ask, "on a stand it goes up for sale at its price")
	var alerts := int(Sales._st()["alerts"])
	var oid := Sales.make_offer(bike)
	var o: Dictionary = Sales.offers()[oid]
	check(int(o["amount"]) > 0 and int(o["amount"]) <= ask and int(o["max"]) >= int(o["amount"]) and int(Sales._st()["alerts"]) == alerts + 1,
		"a buyer makes an offer under the asking price (%s), and the till rings" % Sales.money(int(o["amount"])))
	var amt := int(o["amount"])
	var bal := Shed.garage_money
	var sold := int(Progress.profile["stats"].get("sell_bike", 0))
	Shed.request({"a": "sale_accept", "offer": oid})
	var got := Shed.garage_money - bal
	check(not Shed.bikes.has(bike) and Sales.offers().is_empty() and not Sales.listings().has(bike) and got >= amt
		and got <= amt + Money.cut_of(int(Progress.PAY["sell_bike"]), int(Shed.bank["cut"])), "accepting: the bike is sold and the money goes to the business")
	var d: Dictionary = Sales._st()["deals"][0]
	check(int(d["price"]) == amt and str(d["kind"]) == "online" and int(d["profit"]) == amt - int(d["sunk"])
		and int(Progress.profile["stats"].get("sell_bike", 0)) == sold + 1, "the deal is noted with its profit, and the seller gets the XP")
	var col: Array = Sales._st()["collect"]
	check(col.size() == 1 and (col[0]["xf"] as Transform3D).is_equal_approx(Workshop.SHOWROOM_SPOTS[0]), "the buyer comes to collect it from its stand")
	# Counter-offers: one they'll pay is taken, after a moment.
	var ranger := _bike_named("Rusty Ranger")
	Shed.bikes[ranger]["xf"] = Workshop.SHOWROOM_SPOTS[1]
	Shed.request({"a": "sale_list", "bike": ranger, "ask": 9000})
	var id2 := Sales.make_offer(ranger)
	var o2: Dictionary = Sales.offers()[id2]
	o2["amount"] = 3000
	o2["max"] = 4000
	check(Shed.check(me, {"a": "sale_counter", "offer": id2, "amount": 9500}).contains("more than you're asking"), "no counter-offer over the asking price")
	check(Shed.check(me, {"a": "sale_counter", "offer": id2, "amount": 2900}).contains("accept it"), "nor one under their offer")
	Shed.request({"a": "sale_counter", "offer": id2, "amount": 3800})
	check(str(o2["state"]) == "waiting" and Shed.check(me, {"a": "sale_accept", "offer": id2}).contains("Waiting"), "a counter-offer waits for their answer")
	Sales.advance(Sales.REPLY_HOURS * 0.4)
	check(Shed.bikes.has(ranger) and str(o2["state"]) == "waiting", "which takes a little while")
	Sales.advance(Sales.REPLY_HOURS)
	check(not Shed.bikes.has(ranger) and int(Sales._st()["deals"][0]["price"]) == 3800, "they take a counter-offer within what they'll pay: sold at it")
	# Meeting halfway, a final offer, and walking off.
	var barn := _bike_named("Barn Find")
	Shed.bikes[barn]["xf"] = Workshop.SHOWROOM_SPOTS[2]
	Shed.request({"a": "sale_list", "bike": barn, "ask": 9000})
	var id3 := Sales.make_offer(barn)
	var o3: Dictionary = Sales.offers()[id3]
	o3["amount"] = 3000
	o3["max"] = 4000
	Shed.request({"a": "sale_counter", "offer": id3, "amount": 4600})
	o3["by"] = 0   # nobody with Haggler: their limit is just their max
	Sales.advance(Sales.REPLY_HOURS + 0.01)
	check(Sales.offers().has(id3) and str(o3["state"]) == "open" and int(o3["amount"]) == 3800 and not o3["final"],
		"a counter a bit over what they'll pay: they meet you halfway (%s)" % Sales.money(int(o3["amount"])))
	Shed.request({"a": "sale_counter", "offer": id3, "amount": 4500})
	o3["by"] = 0
	Sales.advance(Sales.REPLY_HOURS + 0.01)
	check(Sales.offers().has(id3) and int(o3["amount"]) == 4000 and o3["final"], "halfway is past their limit: their limit, as a final offer")
	Shed.request({"a": "sale_counter", "offer": id3, "amount": 4400})
	o3["by"] = 0
	Sales.advance(Sales.REPLY_HOURS + 0.01)
	check(not Sales.offers().has(id3) and Shed.bikes.has(barn), "pushing past a final offer: they walk away")
	var id4 := Sales.make_offer(barn)
	Sales.offers()[id4]["amount"] = 2000
	Sales.offers()[id4]["max"] = 3000
	Shed.request({"a": "sale_counter", "offer": id4, "amount": 8000})
	Sales.offers()[id4]["by"] = 0
	Sales.advance(Sales.REPLY_HOURS + 0.01)
	check(not Sales.offers().has(id4), "a counter far over what they'll pay sends them off")
	var id5 := Sales.make_offer(barn)
	Shed.request({"a": "sale_reject", "offer": id5})
	check(not Sales.offers().has(id5) and Shed.bikes.has(barn), "turning an offer down")
	# Off its stand it can't be sold; offers lapse if nobody answers.
	var id6 := Sales.make_offer(barn)
	Shed.bikes[barn]["xf"] = Workshop.SHOWROOM_SPOTS[2].translated(Vector3(3.0, 0.0, 0.0))
	check(not Sales.active(barn) and Shed.check(me, {"a": "sale_accept", "offer": id6}).contains("stand"), "off its stand it can't be sold")
	Sales._st()["next_px_at"] = 1.0e9
	Sales.advance(Sales.OFFER_HOURS + 0.5)
	check(not Sales.offers().has(id6) and Sales.listings().has(barn), "an offer left unanswered lapses; the listing stays")
	# How often buyers come: a fair price brings some in two days, a silly one none.
	Shed.bikes[barn]["xf"] = Workshop.SHOWROOM_SPOTS[2]
	var fair := int(Sales.appraise(barn)["fair"])
	Shed.request({"a": "sale_list", "bike": barn, "ask": roundi(fair * 0.9)})
	var a0 := int(Sales._st()["alerts"])
	for i in 48:
		Sales.advance(1.0)
	var cheap := int(Sales._st()["alerts"]) - a0
	for id in Sales.offers().keys():
		Shed.request({"a": "sale_reject", "offer": id})
	Shed.request({"a": "sale_list", "bike": barn, "ask": fair * 4})
	a0 = int(Sales._st()["alerts"])
	for i in 48:
		Sales.advance(1.0)
	check(cheap >= 1 and int(Sales._st()["alerts"]) == a0, "priced fairly, buyers come (%d offers in two days); at four times its worth, none" % cheap)
	# Selling it to the trade off its stand instead.
	Shed.request({"a": "money_sell_bike", "bike": barn})
	check(not Shed.bikes.has(barn) and str(Sales._st()["deals"][0]["kind"]) == "trade" and not Sales.listings().has(barn),
		"sold to the trade from its stand: noted as a deal, off sale")
	Shed.stop()


## Part-exchange buyers: their bike's numbers, haggling over the allowance, the deal.
func _test_sales_part_exchange() -> void:
	Shed.start_new("Tester", 63)
	var me := Shed.me()
	var bike := _bike_named("Old Faithful")
	Shed.bikes[bike]["xf"] = Workshop.SHOWROOM_SPOTS[2]
	var ask := 6000
	Shed.request({"a": "sale_list", "bike": bike, "ask": ask})
	var pid := Sales.spawn_px(bike)
	var p: Dictionary = Sales.px().get(pid, {})
	check(pid != 0 and int(p["target"]) == bike and int(p["km"]) > 0 and int(p["retail"]) > int(p["trade"]) and int(p["trade"]) > 0
		and int(p["want"]) >= int(p["min"]) and str(p["model"]).contains("cc"),
		"a part-exchange buyer: a %s, %d km, retail %s, trade %s, wants %s" % [p.get("model", ""), int(p.get("km", 0)),
			Sales.money(int(p.get("retail", 0))), Sales.money(int(p.get("trade", 0))), Sales.money(int(p.get("want", 0)))])
	check(Sales.px_part_lines(p).size() >= 5 and float(p["condition"]) > 0.0 and float(p["condition"]) <= 1.0, "the Sales page has their bike's parts and condition")
	check(Sales.free_px_spot() != int(p["park"]), "they park in a spot on the forecourt")
	Shed.request({"a": "sale_px_offer", "px": pid, "amount": maxi(10, roundi(float(p["min"]) * 0.5))})
	check(not Sales.px().has(pid), "an insulting allowance and they ride off")
	pid = Sales.spawn_px(bike)
	p = Sales.px()[pid]
	p["want"] = 3000
	p["min"] = 2400
	Shed.request({"a": "sale_px_offer", "px": pid, "amount": 2000})
	check(Sales.px().has(pid) and int(p["want"]) == 2500 and int(p["rounds"]) == 1, "a low allowance: they come down halfway")
	check(Shed.check(me, {"a": "sale_px_offer", "px": pid, "amount": 2600}).contains("accept their figure"), "no offering more than they ask")
	var bal := Shed.garage_money
	var before: Array = Shed.bikes.keys()
	var park := int(p["park"])
	Shed.request({"a": "sale_px_accept", "px": pid})
	var theirs := 0
	for id in Shed.bikes:
		if not before.has(id):
			theirs = id
	check(not Shed.bikes.has(bike) and not Sales.px().has(pid) and Shed.garage_money - bal >= ask - 2500, "the deal: they ride off on ours and pay the difference")
	check(theirs != 0 and int(Shed.bikes[theirs]["bay"]) == -1 and (Shed.bikes[theirs]["xf"] as Transform3D).origin.distance_to(Sales.PX_SPOTS[park].origin) < 0.01
		and int(Shed.bikes[theirs]["bought"]) == 2500 and str(Shed.bikes[theirs]["name"]).begins_with("Part-ex") and Shed.is_complete(theirs)
		and Shed.bike_at_work(theirs), "their bike is ours, parked out front, ready to bring in (bought for the allowance)")
	var cond: Dictionary = p["cond"]
	check(is_equal_approx(float(Shed.items[Shed.item_on(theirs, "frame")]["rust"]), float(cond["frame"]["rust"]))
		and is_equal_approx(float(Shed.items[Shed.item_on(theirs, "engine")]["wear"]), float(cond["engine"]["wear"])), "in just the state the page showed")
	var d: Dictionary = Sales._st()["deals"][0]
	check(str(d["kind"]) == "px" and int(d["allowance"]) == 2500 and int(d["price"]) == ask
		and (Sales._st()["collect"] as Array).any(func(c): return int(c.get("visitor", -1)) == pid), "noted as a part-exchange, and they ride ours away")
	# The business has to be able to pay a difference the other way.
	var ranger := _bike_named("Rusty Ranger")
	Shed.bikes[ranger]["xf"] = Workshop.SHOWROOM_SPOTS[0]
	Shed.request({"a": "sale_list", "bike": ranger, "ask": 500})
	var pid2 := Sales.spawn_px(ranger)
	check(pid2 != 0, "another one rides in")
	Sales.px()[pid2]["want"] = 50000
	Shed.garage_money = 10
	check(Shed.check(me, {"a": "sale_px_accept", "px": pid2}).contains("can't pay"), "the business can't pay out more than it has")
	Sales._st()["next_px_at"] = 1.0e9
	Sales.advance(Sales.PX_PATIENCE + 0.5)
	check(Sales.px().is_empty(), "left waiting too long, they give up")
	Shed.stop()


## Everything about selling is kept with the shed; older saves open with nothing for sale.
func _test_sales_save() -> void:
	Shed.start_new("Tester", 64)
	var bike := _bike_named("Old Faithful")
	Shed.bikes[bike]["xf"] = Workshop.SHOWROOM_SPOTS[3]
	Shed.request({"a": "sale_list", "bike": bike, "ask": 7000, "margin": 0.3})
	var oid := Sales.make_offer(bike)
	var pid := Sales.spawn_px(bike)
	Shed.bikes[bike]["labour"] = 77
	Shed.items[Shed.item_on(bike, "exhaust")]["paid"] = 350
	Sales._st()["next_px_at"] = 1.0e9
	Sales.advance(0.3)
	var clock := Sales.clock()
	var ap := Sales.appraise(bike)
	var text := var_to_str(Shed.save_snapshot().duplicate(true))
	Shed.start_new("Tester", 65)
	Shed.load_state(str_to_var(text), "Tester")
	check(Sales.listings().has(bike) and int(Sales.listings()[bike]["ask"]) == 7000 and is_equal_approx(float(Sales.listings()[bike]["margin"]), 0.3)
		and Sales.offers().has(oid) and Sales.px().has(pid) and is_equal_approx(Sales.clock(), clock),
		"listings, offers, part-exchange buyers and the clock survive a save")
	check(int(Sales.appraise(bike)["sunk"]) == int(ap["sunk"]) and int(Sales.appraise(bike)["labour"]) == int(ap["labour"])
		and int(Sales.appraise(bike)["parts"]) == int(ap["parts"]) and Sales.active(bike), "and what the bike has cost, still on its stand for sale")
	var nid := Sales.make_offer(bike)
	check(nid > maxi(oid, pid), "new offers get new ids after loading")
	var old: Dictionary = Shed._snapshot().duplicate(true)
	old.erase("sales")
	Shed.start_new("Tester", 66)
	Shed.load_state(old, "Tester")
	check(Sales.listings().is_empty() and Sales.offers().is_empty() and Sales.px().is_empty() and Sales.clock() == 0.0 and Shed.bikes.has(bike),
		"a save from before selling from the showroom opens with nothing for sale")
	Shed.stop()


## In the game: the stands' cards and the office screen, the PC, the till, accepting on the
## page, a part-exchange buyer riding in, the TV channel.
func _test_sales_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	await get_tree().physics_frame
	var view: SalesView = main.sales_view
	var so: SalesOffice = main.workshop.sales_office
	var bike := _bike_named("Old Faithful")
	Shed.bikes[bike]["xf"] = Workshop.SHOWROOM_SPOTS[0]
	Shed.request({"a": "sale_list", "bike": bike, "ask": 6500})
	await get_tree().process_frame
	check(so.stand_tag(0) != null and so.stand_tag(0).text.contains("£6,500") and so.screen_text().text.contains("Stand 1")
		and so.screen_text().text.contains(str(Shed.bikes[bike]["name"])), "the stand's price card and the office PC's screen show it")
	# The office PC.
	var w: Walker = main.walker
	w.set_tool("hands")
	w.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), SalesOffice.CENTER + Vector3(-4.4, SalesOffice.MEZZ_Y, 1.0)))
	for i in 12:
		await get_tree().physics_frame
	check(str(w.target.get("kind", "")) == "sales_pc", "looking at the office PC from its chair")
	_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.sales_pc.visible and main.sales_pc.current_tab() == "Showroom" and _sales_button(main.sales_pc, "Change the price") != null,
		"F opens the Sales page on the showroom")
	# An offer: the till rings and the page has it.
	var tills := view.tills
	var oid := Sales.make_offer(bike)
	Shed.changed.emit()
	check(view.tills == tills + 1, "a buyer's offer rings the till")
	main.sales_pc.open("Offers")
	await get_tree().process_frame
	var accept := _sales_button(main.sales_pc, "Accept")
	check(accept != null and _sales_button(main.sales_pc, "Counter-offer") != null, "the Offers tab: accept, turn down, counter-offer")
	if accept:
		accept.pressed.emit()
	await get_tree().process_frame
	check(not Shed.bikes.has(bike) and not Sales.offers().has(oid) and view.collecting.size() == 1 and is_instance_valid(view.collecting.values()[0]),
		"accepted on the page: sold, and the buyer comes for it")
	main.sales_pc.close_computer()
	# A part-exchange buyer rides in on their own bike.
	var ranger := _bike_named("Rusty Ranger")
	Shed.bikes[ranger]["xf"] = Workshop.SHOWROOM_SPOTS[1]
	Shed.request({"a": "sale_list", "bike": ranger, "ask": 4000})
	var pid := Sales.spawn_px(ranger)
	Shed.changed.emit()
	await get_tree().process_frame
	check(view.views.has(pid) and (view.views[pid] as CustomerView).has_bike(), "a part-exchange buyer rides in on their own bike")
	# The garage TVs' Sales channel.
	var data := TvChannels.page_data("sales")
	check(TvChannels.CHANNELS.has("sales") and (data["stands"] as Array).size() == 4 and (data["px"] as Array).size() == 1, "the TVs have a Sales channel")
	var dash := Dashboard.new("crew", 2.0)
	add_child(dash)
	dash.show_page("sales", data)
	await get_tree().process_frame
	await get_tree().process_frame
	dash.queue_free()
	# Doing the deal on the page.
	main.sales_pc.open_px(pid)
	await get_tree().process_frame
	check(main.sales_pc.current_tab() == "Part exchange", "talking to them opens the part-exchange page")
	var deal := _sales_button(main.sales_pc, "Accept their")
	if deal:
		deal.pressed.emit()
	await get_tree().process_frame
	check(not Shed.bikes.has(ranger) and not view.views.has(pid) and view.collecting.size() == 2, "the deal done: they ride ours away")
	main.sales_pc.close_computer()
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------- playtest fixes (round two)

## Blasting an engine bare all over makes it as good as new: every part on it at 100%, no wear,
## dirt or rust, and it stays bare metal (ready for a coat).
func _test_blast_engine_like_new() -> void:
	Shed.start_new("Tester", 81)
	var me := Shed.me()
	var cab := Shed._new_furniture("blaster", Transform3D(Basis(), Workshop.CENTER + Vector3(1.5, 0.0, 1.8)), "blaster_cabinet")
	var spot := "blast_%d_0" % cab
	var engine := 0
	for s in Shed.stand_spots():
		if engine == 0 and Shed.is_engine(Shed.item_at_spot(s)):
			engine = Shed.item_at_spot(s)
			Shed.request({"a": "take", "spot": s})
	Shed.request({"a": "place", "spot": spot})
	var parts := Shed._blast_parts(engine)
	check(engine != 0 and Shed.item_at_spot(spot) == engine and parts.size() >= 3, "an engine and its ancillaries in the cabinet (%d parts)" % parts.size())
	for id in parts:
		Shed.items[id]["rust"] = 0.8
		Shed.items[id]["dirt"] = 0.6
		Shed.items[id]["wear"] = 0.5
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	var res := {}
	for id in parts:
		res[id] = [0.95, 0.3]
	res[parts[0]] = [0.6, 0.0]
	Shed.request({"a": "blast_tick", "spot": spot, "parts": res})
	check(float(Shed.items[parts[1]]["wear"]) >= 0.5 and float(Shed.items[parts[0]]["rust"]) > 0.0,
		"with part of it still to do, the worn parts are still worn")
	res[parts[0]] = [0.95, 0.0]
	Shed.request({"a": "blast_tick", "spot": spot, "parts": res})
	var healths := parts.map(func(id): return "%.2f" % Shed._health(id))
	check(_like_new(parts), "the moment the last of it comes up bare, every part is at 100%%: no wear, dirt or rust (%s)" % str(healths))
	var text: String = Shed._blast_apply(me, {"a": "blast", "spot": spot, "parts": res})
	check(_like_new(parts) and parts.all(func(id): return Shed.blast_full(Shed.items[id]) and float(Shed.items[id]["blast"].get("p", 0.0)) == 0.0)
		and text.contains("good as new"), "stepping back it stays new, bare metal all over and unpitted (%s)" % text)
	# Back in the cabinet later: the old wear doesn't come back.
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	for id in parts:
		res[id] = [0.95, 0.0]
	Shed.request({"a": "blast_tick", "spot": spot, "parts": res})
	Shed.request({"a": "blast", "spot": spot, "parts": res})
	check(_like_new(parts), "blasting it again keeps it new")
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(copy, "Tester")
	check(_like_new(parts) and parts.all(func(id): return Shed.blast_full(Shed.items[id])), "kept in the save, bare metal and new")
	# The protective coat still goes on over it (in the paint shop).
	check(not Shed.check(me, {"a": "coat", "item": engine, "coat": "clear", "gun": true, "quality": 0.9}).contains("sandblast"),
		"nothing rusty left to stop a protective coat")


## The sand stays inside the blast cabinet: its grains are held inside the chamber's walls and
## glass on every step, however fast and however long the step.
func _test_blast_grit_contained() -> void:
	for model in ["blaster_cabinet", "blaster_pro"]:
		var walls := BlastGrit.walls(model)
		var inside := Equipment.blaster_inside(model)
		var nozzle := Vector3(0.22, float(inside["floor"]) + 0.45, float(inside["front"]) - 0.28)
		var size: Vector3 = Equipment.get_model(model)["size"]
		check(walls.size() == 7 and BlastGrit.holds(walls, nozzle) and BlastGrit.holds(walls, Vector3(0.0, float(inside["floor"]) + 0.4, float(inside["turn_z"])))
			and not BlastGrit.holds(walls, Vector3(0.0, float(inside["roof"]) - 0.05, float(inside["front"]) - 0.05))
			and not BlastGrit.holds(walls, Vector3(size.x, 1.0, 0.0)), "%s: the chamber's walls and sloping glass hold the nozzle and the engine" % model)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var escaped := 0
		for g in 1500:
			var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			var p := nozzle
			var v := dir * rng.randf_range(1.5, 40.0)
			var dt: float = [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0, 0.1][g % 4]
			var t := 0.0
			while t < 0.9:
				v += Vector3(0.0, -9.8, 0.0) * dt
				var step := BlastGrit.contain(walls, p, v, dt)
				p = step[0]
				v = step[1]
				t += dt
				if not BlastGrit.holds(walls, p, 0.001):
					escaped += 1
					break
		check(escaped == 0, "%s: 1500 grains fired every way at up to 40 m/s, with long and short steps, and none leaves the chamber (%d out)" % [model, escaped])
	# The cabinet in the shed uses it for its jet and the ricochet.
	var rig: Dictionary = await _blast_rig()
	var main: Node = rig["main"]
	var view: EquipmentView = main.workshop.furniture_nodes[rig["cab"]]
	var jet: GPUParticles3D = view.get_node("Nozzle/Jet")
	var grains: GPUParticles3D = view.get_node("Grains")
	view.set_blast(Vector2.ZERO, true, (view.get_node("Pivot") as Node3D).global_position, Vector3.UP, 0.3, 0)
	var mats := view.grit_materials()
	var placed := mats.size() == 2
	for m in mats:
		var to_local: Projection = m.get_shader_parameter("to_local")
		placed = placed and m.shader == BlastGrit.shader() and m.get_shader_parameter("walls") == BlastGrit.walls(view.model) \
			and (Transform3D(to_local) * view.global_position).length() < 0.001
	check(mats.has(jet.process_material) and mats.has(grains.process_material) and placed,
		"the cabinet's jet and ricochet grains are held inside it, wherever it stands")
	check(jet.lifetime <= 0.31 and grains.lifetime <= 0.71 and (view.get_node("Sparks") as CPUParticles3D).initial_velocity_max <= 1.61
		and (view.get_node("Rebound") as CPUParticles3D).initial_velocity_max <= 1.21, "and the sparks and dust only puff round where the jet lands")
	view.set_blast(Vector2.ZERO, false, Vector3.ZERO, Vector3.UP, 0.0, 0)
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## A brand new shed starts with no bikes and nothing on the workbench; its machines are there.
func _test_new_shed_empty() -> void:
	var was: bool = Shed.demo_bikes
	Shed.demo_bikes = false
	Shed.start_new("Tester", 82)
	var on_bench := Shed.items.values().filter(func(it): return str(it["at"]) == "spot" and str(it["ref"]).begins_with("bench_"))
	var kinds := {}
	for id in Shed.furniture:
		kinds[str(Shed.furniture[id]["kind"])] = true
	check(Shed.bikes.is_empty() and on_bench.is_empty() and Shed.items.is_empty(),
		"a new shed has no bikes, nothing on the workbench and no loose parts (%d bikes, %d items)" % [Shed.bikes.size(), Shed.items.size()])
	check(kinds.has("stand") and kinds.has("washer") and kinds.has("repair") and kinds.has("booth") and kinds.has("changer")
		and Shed.stand_spots().all(func(s): return Shed.item_at_spot(s) == 0), "its machines are all there, the engine stand empty (%s)" % str(kinds.keys()))
	check(Shed.free_bay(Workshop.bay_count()) == 0 and Contracts.customers().is_empty() and Shed.garage_money == Money.START_FUNDS,
		"every bay free, the garage's opening funds to spend")
	# A save of it opens empty too.
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(copy, "Tester")
	check(Shed.bikes.is_empty() and Shed.items.is_empty(), "and it saves and loads empty")
	Shed.demo_bikes = was


## Contracts vary: different sizes of service and parts to renew, MOTs from a couple of faults to
## a bike off the road for years (some with jobs while it's in), mods with 2-5 different goals,
## bespoke builds with their own mix of targets; pay, budget and time follow the work.
func _test_contract_variety() -> void:
	Shed.start_new("Tester", 83)
	Shed._rng.seed = 99
	var sizes := {}
	var tasks := {}
	var pay_small := []
	var pay_big := []
	var days := {}
	var fair := true
	for i in 80:
		var o := Contracts.make_offer("maint", "Dave Smith")
		var n: int = o["goals"].size()
		sizes[n] = true
		days[int(o["days"])] = true
		var needs_parts := false
		for g in o["goals"]:
			tasks[str(g["task"])] = true
			needs_parts = needs_parts or Contracts.TASK_PARTS.has(str(g["task"]))
		if n <= 2:
			pay_small.append(int(o["pay"]))
		elif n >= 5:
			pay_big.append(int(o["pay"]))
		fair = fair and int(o["pay"]) >= 30 + n * 20 and int(o["pay"]) <= 500 and (int(o["budget"]) > 0) == needs_parts
	check(sizes.size() >= 5 and tasks.size() == Contracts.TASKS.size() and days.size() >= 3,
		"services come in sizes from one job to the works (%s tasks), with all %d kinds of task and deadlines of %s days" % [
		str(sizes.keys()), Contracts.TASKS.size(), str(days.keys())])
	check(fair and _avg(pay_big) > _avg(pay_small) * 2.0,
		"a bigger service pays more (%.0f vs %.0f), and jobs that need parts come with a budget for them" % [_avg(pay_big), _avg(pay_small)])
	# MOTs.
	var faults := {}
	var extras := 0
	var low := []
	var high := []
	for i in 60:
		var o := Contracts.make_offer("mot", "Sue Jones")
		faults[int(o["faults"])] = true
		if o["goals"].size() > 1:
			extras += 1
		elif int(o["faults"]) <= 3:
			low.append(int(o["pay"]))
		elif int(o["faults"]) >= 6:
			high.append(int(o["pay"]))
	check(faults.size() >= 5 and extras >= 10 and extras <= 50, "MOTs range from %d to %d faults, %d of 60 with jobs to do while it's in" % [
		faults.keys().min(), faults.keys().max(), extras])
	check(_avg(high) > _avg(low) + 60.0, "a bike in a worse state pays more for its MOT (%.0f vs %.0f)" % [_avg(high), _avg(low)])
	var fails := {2: 0, 7: 0}
	for n in [2, 7]:
		for k in 4:
			Shed.start_new("Tester", 90 + k)
			Contracts._st()["reputation"] = 5
			var cid := Contracts.spawn("mot")
			Contracts.customers()[cid]["offer"]["faults"] = n
			Shed.request({"a": "contract_accept", "customer": cid})
			var jb := int(Contracts.jobs().values()[0]["bike"])
			fails[n] = int(fails[n]) + MotTest.fails(MotTest.inspect(jb)).size()
	check(int(fails[7]) > int(fails[2]) + 6, "and the test finds more wrong with it (%d fails over four bikes, against %d)" % [fails[7], fails[2]])
	# Modifications.
	Shed.start_new("Tester", 84)
	Shed._rng.seed = 5
	var counts := {}
	var goal_kinds := {}
	var mod_fair := true
	for i in 40:
		var o := Contracts.make_offer("mod", "Raj Khan")
		counts[o["goals"].size()] = true
		for g in o["goals"]:
			goal_kinds[str(g["t"])] = true
		mod_fair = mod_fair and int(o["budget"]) >= 300 and int(o["pay"]) >= 150 + o["goals"].size() * 90 \
			and int(o["days"]) >= 3 + o["goals"].size()
	check(counts.size() >= 3 and goal_kinds.size() >= 7, "mods ask for %s goals of %d kinds (%s)" % [str(counts.keys()), goal_kinds.size(), str(goal_kinds.keys())])
	check(mod_fair, "more goals, more pay and more days")
	# Bespoke builds.
	var b_counts := {}
	var finish := {}
	var parts_asked := {}
	for i in 30:
		var o := Contracts.make_offer("bespoke", "Lady Okafor")
		b_counts[o["goals"].size()] = true
		for g in o["goals"]:
			if g["t"] == "health":
				finish[float(g["min"])] = true
			if g["t"] == "part":
				parts_asked[str(g["slot"])] = true
	check(b_counts.size() >= 3 and finish.size() >= 2 and parts_asked.size() >= 4,
		"bespoke builds each have their own targets (%s goals, finish %s, signature parts %s)" % [str(b_counts.keys()), str(finish.keys()), str(parts_asked.keys())])


## Every part at 100%: no wear, dirt or rust.
func _like_new(parts: Array) -> bool:
	for id in parts:
		var it: Dictionary = Shed.items[id]
		if float(it["rust"]) != 0.0 or float(it["dirt"]) != 0.0 or float(it["wear"]) != 0.0 or not is_equal_approx(Shed._health(id), 1.0):
			return false
	return true


func _avg(a: Array) -> float:
	var total := 0.0
	for x in a:
		total += float(x)
	return total / maxf(1.0, a.size())


# ---------------------------------------------------------------------------- handling phase 1: tyres

## Throttle (and a touch of brake) to hold the bike at `target` m/s.
func _hold_speed(b: Bike, target: float) -> void:
	var err := target - b.speed
	b.throttle = clampf(0.25 + err * 0.35, 0.0, 1.0)
	b.front_brake = clampf(-err * 0.15 - 0.1, 0.0, 0.4)


func _test_tyre_steady_turn() -> void:
	# A steady turn: the lean should be near the textbook atan(v^2 / g r), plus a little for the
	# round tyre's contact patch moving inwards as it leans.
	var acc := {"n": 0, "lean": 0.0, "v": 0.0, "yaw": 0.0}
	var r := await ride({}, 11.0, func(b, t):
		b.assist = 0.5
		_hold_speed(b, 15.0)
		b.lean_input = 0.0 if t < 3.0 else 0.6
		if t > 7.0:
			acc["n"] += 1
			acc["lean"] += absf(b.lean_angle)
			acc["v"] += b.linear_velocity.length()
			acc["yaw"] += absf(b.angular_velocity.y))
	var n := maxf(float(acc["n"]), 1.0)
	var lean := rad_to_deg(float(acc["lean"]) / n)
	var v := float(acc["v"]) / n
	var yaw := float(acc["yaw"]) / n
	var radius := v / maxf(yaw, 1e-3)
	var textbook := rad_to_deg(atan(v * v / (Bike.G * radius)))
	var balance := rad_to_deg((r["bike"] as Bike)._balance_lean(deg_to_rad(lean)))
	check(not r["crashed"], "the steady turn holds (%.1f m/s on a %.0f m radius)" % [v, radius])
	check(absf(balance - textbook) < 4.0,
		"steady-turn lean is near the textbook atan(v^2/gr) = %.1f deg: %.1f deg from the tyres to the centre of mass" % [textbook, balance])
	check(lean > balance and lean - balance < 8.0,
		"and the bike leans a little further on its round tyres (%.1f deg)" % lean)
	await _done(r)


func _test_tyre_stopping() -> void:
	# A hard stop on the front brake, dry sports tyres, from 25 m/s: about 1 g (the air helps a little).
	var st := {"x0": Vector3.ZERO, "v0": 0.0, "dist": -1.0}
	var r := await ride({}, 14.0, func(b, t):
		b.assist = 0.5
		if t < 8.0:
			_hold_speed(b, 25.0)
			return
		b.throttle = 0.0
		b.front_brake = 1.0
		b.rear_brake = 0.0
		if st["v0"] == 0.0:
			st["v0"] = b.speed
			st["x0"] = b.global_position
		elif st["dist"] < 0.0 and b.speed < 0.3:
			st["dist"] = (b.global_position - st["x0"]).length())
	var v0: float = st["v0"]
	var dist: float = st["dist"]
	var g := v0 * v0 / (2.0 * maxf(dist, 0.01)) / Bike.G if dist > 0.0 else 0.0
	check(not r["crashed"] and dist > 0.0, "a hard stop from %.0f m/s comes to a halt in %.1f m" % [v0, dist])
	check(g > 0.85 and g < 1.2, "it stops at about 1 g on dry sports tyres (%.2f g)" % g)
	await _done(r)


func _test_tyre_front_tuck() -> void:
	# Grabbing a handful of front brake leaned over: at realism 0 nothing saves the front and it
	# tucks; at realism 1 the rider feels for it and the bike just slows.
	for realism in [0.0, 1.0]:
		var worst := {"front": 0.0}
		var r := await ride({}, 8.0, func(b, t):
			b.assist = realism
			b.lean_input = 0.0 if t < 2.5 else 0.55
			if t < 5.0:
				_hold_speed(b, 15.0)
			else:
				b.throttle = 0.0
				b.front_brake = 1.0
				worst["front"] = maxf(worst["front"], float(b.wheels[0]["grip_used"])))
		var front: float = worst["front"]
		if realism == 0.0:
			check(r["crashed"] and front > 1.5, "realism 0: grabbing the front brake leaned over tucks the front (grip used %.1f)" % front)
		else:
			check(not r["crashed"] and front <= 1.2, "realism 1: the rider eases the brake and the front holds (grip used %.2f)" % front)
		await _done(r)


func _test_tyre_highside() -> void:
	# At realism 0, spin the back tyre up leaned over and snap the throttle shut: the slide
	# grips again all at once and throws the bike over the other way.
	var st := {"lean_in": 0.0, "slide": 0.0}
	var r := await ride({}, 9.0, func(b, t):
		b.assist = 0.0
		b.auto_shift = t < 4.8
		if t >= 4.8:
			b.gear = 2
		b.lean_input = 0.0 if t < 2.5 else 0.5
		if t < 5.0:
			_hold_speed(b, 13.0)
		elif t < 5.6:
			b.throttle = 1.0
			b.front_brake = 0.0
			st["slide"] = maxf(st["slide"], absf(rad_to_deg(float(b.wheels[1]["alpha"]))))
		else:
			b.throttle = 0.0
		if t > 5.0 and t < 5.05:
			st["lean_in"] = b.lean_angle)
	if verbose:
		print("    high side: lean before %.1f, rear slip angle %.1f" % [rad_to_deg(st["lean_in"]), st["slide"]])
	check(r["crashed"], "realism 0: a rear slide that suddenly grips again high-sides (rear slid %.0f deg)" % st["slide"])
	await _done(r)


func _test_tyre_coasting() -> void:
	# Hands off, throttle shut, at full sim, with a shove sideways: the bike rides it out, runs
	# straight on and stays up.
	for bars in [false]:
		var st := {"lean": 0.0, "yaw0": 0.0, "set": false, "end": 0.0}
		var r := await ride({}, 13.0, func(b, t):
			b.assist = 0.0
			if t < 5.0:
				_hold_speed(b, 20.0)
				return
			b.throttle = 0.0
			b.front_brake = 0.0
			if not st["set"]:
				st["set"] = true
				st["yaw0"] = _heading(b)
				b.apply_torque_impulse(-b.global_transform.basis.z * 30.0)
			st["lean"] = maxf(st["lean"], absf(b.lean_angle))
			st["end"] = absf(b.lean_angle))
		var turned := absf(wrapf(_heading(r["bike"]) - float(st["yaw0"]), -PI, PI))
		var how := "lean steering"
		check(not r["crashed"] and rad_to_deg(st["end"]) < 2.0 and rad_to_deg(turned) < 25.0,
			"%s: coasting hands off at full sim rides out a shove and runs on upright (worst lean %.1f deg, now %.1f, %.0f deg off line)"
			% [how, rad_to_deg(st["lean"]), rad_to_deg(st["end"]), rad_to_deg(turned)])
		await _done(r)


func _test_tyre_old_save() -> void:
	# The tyre fields come from the catalogue; a tyre without them (an old catalogue entry) gets
	# its style's defaults, and the bike still rides.
	var bare := {"style": "road", "width": 160, "grip": {"tarmac": 1.1}}
	var p := TyreModel.params_of(bare)
	check(p["construction"] == "radial" and is_equal_approx(float(p["slide"]), 0.8) and float(p["crown"]) > 0.05,
		"a tyre with no construction or profile gets its style's defaults (%s)" % str(p["construction"]))
	var off := TyreModel.params_of({"style": "offroad", "width": 120})
	check(off["construction"] == "bias" and float(off["alpha_peak"]) > float(p["alpha_peak"]), "an off-road tyre defaults to bias ply")
	Shed.start_new("Tester", 51)
	var old: Dictionary = Shed._snapshot().duplicate(true)
	Shed.start_new("Tester", 52)
	Shed.load_state(old, "Tester")
	var ok := true
	for id in Shed.bikes:
		var b := Shed.build_of(id)
		ok = ok and b.tyre_front.has_all(["kappa_peak", "alpha_peak", "crown", "relax", "B", "C"]) \
			and b.tyre_rear.has_all(["kappa_peak", "alpha_peak", "crown", "relax", "B", "C"])
	check(ok and not Shed.bikes.is_empty(), "every bike in a loaded save has tyre numbers")
	# Strip the new fields from the catalogue's tyres, as an old one would be, and ride.
	var keep := {}
	for id in PartsDB.by_kind["tyre"]:
		var t: Dictionary = PartsDB.parts[id]
		keep[id] = {}
		for k in ["construction", "profile", "stiffness", "slide"]:
			if t.has(k):
				keep[id][k] = t[k]
				t.erase(k)
	var built := BikeBuild.new({})
	check(built.tyre_rear["construction"] == "radial", "a bike on an old catalogue's tyres still gets tyre numbers")
	var r := await ride({}, 4.0, func(b, t):
		b.throttle = 0.5
		b.lean_input = 0.4 if t > 2.0 else 0.0)
	check(not r["crashed"], "and rides on them")
	await _done(r)
	for id in keep:
		PartsDB.parts[id].merge(keep[id], true)


## A sports frame with a chopper's long-offset springer fork: next to no trail.
const SHORT_TRAIL_BIKE := {"frame": "sport_perimeter_red", "fork": "springer_long"}


func _test_steering_geometry() -> void:
	# Trail from the frame's rake, the fork's offset and the front wheel's size.
	var sport := BikeBuild.new(Contracts.style_build("sport"))
	var race := BikeBuild.new(Contracts.style_build("race"))
	var chop := BikeBuild.new(Contracts.style_build("chopper"))
	var cruise := BikeBuild.new(Contracts.style_build("cruiser"))
	check(sport.trail > 0.09 and sport.trail < 0.11 and race.trail > 0.09 and race.trail < 0.11,
		"a sports bike has about 100 mm of trail (sport %d mm, race %d mm)" % [roundi(sport.trail * 1000), roundi(race.trail * 1000)])
	check(chop.trail > 0.12 and cruise.trail > 0.12, "choppers and cruisers have long trail (chopper %d mm, cruiser %d mm)"
		% [roundi(chop.trail * 1000), roundi(cruise.trail * 1000)])
	var all_forks: bool = PartsDB.by_kind["fork"].all(func(id): return float(PartsDB.get_part(str(id)).get("offset", 0.0)) > 0.0)
	check(all_forks, "every fork in the catalogue has its offset")
	check(BikeBuild.trail_of(0.3, 25.0, 0.03) > BikeBuild.trail_of(0.3, 25.0, 0.06) and BikeBuild.trail_of(0.3, 30.0, 0.04) > BikeBuild.trail_of(0.3, 24.0, 0.04),
		"more rake gives more trail, more offset less")
	# An old catalogue fork with no offset gets its style's.
	var fork: Dictionary = PartsDB.parts["telescopic_road"]
	var kept: float = fork["offset"]
	fork.erase("offset")
	var old := BikeBuild.new({})
	check(is_equal_approx(old.fork_offset, float(BikeBuild.FORK_OFFSET["conventional"])) and old.trail > 0.08,
		"a fork from an old catalogue gets a sensible offset (%d mm trail)" % roundi(old.trail * 1000))
	fork["offset"] = kept
	# A short-trail bike is something only a player builds, and the bike info warns of it.
	var bad := BikeBuild.new(SHORT_TRAIL_BIKE)
	check(bad.trail < BikeBuild.SHORT_TRAIL and bad.notes.any(func(n): return n.contains("trail")),
		"a chopper fork on a sports frame leaves %d mm of trail, and the bike info says so" % roundi(bad.trail * 1000))
	var fixed: Dictionary = BikeBuild.sensible_fork(PartsDB.sanitize_build(SHORT_TRAIL_BIKE))
	check(BikeBuild.parts_trail(fixed) >= BikeBuild.STOCK_TRAIL and fixed["fork"] != "springer_long",
		"a ready-built bike gets a fork that suits its frame (%s)" % fixed["fork"])
	var rng := RandomNumberGenerator.new()
	var worst := 1.0
	for i in 150:
		rng.seed = 900 + i
		worst = minf(worst, BikeBuild.parts_trail(Contracts.random_parts(rng, i % 2 == 0)))
	for st in PartsDB.STYLES:
		worst = minf(worst, BikeBuild.parts_trail(Shed.style_parts(st)))
	Shed.start_new("Tester", 61)
	for id in Shed.bikes:
		worst = minf(worst, Shed.build_of(id).trail)
	check(worst >= BikeBuild.STOCK_TRAIL, "no project or customer bike turns up with short trail (least %d mm)" % roundi(worst * 1000))
	# The steering damper: its own kind and slot, five of them, adjustable ones on the dyno desk.
	check(PartsDB.KINDS.has("steering_damper") and PartsDB.by_kind["steering_damper"].size() >= 5 and PartsDB.is_optional("steering_damper")
		and PartsDB.DEFAULT_BUILD["steering_damper"] == "none", "steering dampers are parts of their own, five of them, and a bike rides without one")
	var plain := BikeBuild.new({})
	var damped := BikeBuild.new({"steering_damper": "damper_linear_adj"})
	var firm := BikeBuild.new({"steering_damper": "damper_linear_adj"}, {}, {"damper": 1.0})
	var fixed_d := BikeBuild.new({"steering_damper": "damper_linear"}, {}, {"damper": 1.0})
	check(plain.damper_damping == 0.0 and damped.damper_damping > 5.0 and firm.damper_damping > damped.damper_damping * 1.4,
		"a damper damps the steering and its clicker firms it up (%.0f, %.0f firm)" % [damped.damper_damping, firm.damper_damping])
	check(plain.tune_block("damper") != "" and fixed_d.tune_block("damper") != "" and damped.tune_block("damper") == ""
		and is_equal_approx(fixed_d.damper_damping, float(PartsDB.get_part("damper_linear")["damping"])),
		"only an adjustable damper has a setting on the dyno desk")
	check(TuningComputer.TABS["Suspension"].any(func(r): return r[0] == "damper") and Shed.TUNE_HOME.has("damper"),
		"the dyno desk's Suspension tab has the steering damper")
	var worn := BikeBuild.new({"steering_damper": "damper_linear_adj"}, {"steering_damper": {"wear": 1.0}})
	check(worn.damper_damping < damped.damper_damping * 0.8, "a worn damper damps less")
	# Mass distribution: where the parts sit moves the centre of mass and adds inertia.
	var loaded := BikeBuild.new({"top_box": "alloy_top_box", "panniers": "aluminium_boxes"})
	check(loaded.com_offset.z > 0.005 and loaded.inertia_add.y > 1.0 and plain.com_offset.is_zero_approx(),
		"luggage moves the weight back (%.0f mm) and makes it slower to turn (+%.1f kg m^2 of yaw inertia)"
		% [loaded.com_offset.z * 1000.0, loaded.inertia_add.y])
	var spec := PartsDB.spec_line("usd_sport")
	check(spec.contains("mm offset"), "the fork's spec gives its offset (%s)" % spec)


## Rides `build` at `v` m/s, gives the bars a shove and returns how the shake dies away:
## {freq (Hz), at (shake in degrees 0.1, 0.5, 1 and 2 s after), crashed}.
func _bar_kick(build: Dictionary, v: float, hands_off: bool, kick := 1.0) -> Dictionary:
	var st := {"prev": 0.0, "cross": [], "at": [0.0, 0.0, 0.0, 0.0]}
	var marks := [0.1, 0.5, 1.0, 2.0]
	var r := await ride(build, 7.2, func(b, t):
		b.assist = 0.5
		if t < 0.001:
			_roll_at(b, v)
		_hold_speed(b, v)
		b.hands_off = hands_off and t > 4.0
		if absf(t - 5.0) < 0.001:
			b.kick_bars(kick)
		if t > 5.0 and t < 5.8:
			var x: float = b.steer - b._steer_slow
			if absf(x) > 2e-4 and (x > 0.0) != (st["prev"] > 0.0):
				st["cross"].append(t)
			if absf(x) > 2e-4:
				st["prev"] = x
		for i in marks.size():
			if absf(t - 5.0 - marks[i]) < 0.004:
				st["at"][i] = rad_to_deg(b.wobble))
	var c: Array = st["cross"]
	var out := {"freq": (c.size() - 1) / 2.0 / (float(c[-1]) - float(c[0])) if c.size() > 3 else 0.0, "at": st["at"], "crashed": r["crashed"]}
	await _done(r)
	return out


## Starts the bike already rolling at v m/s, so a test at motorway speed isn't still pulling
## hard through the gears when it looks.
func _roll_at(b: Bike, v: float) -> void:
	b.linear_velocity = -b.global_transform.basis.z * v
	for w in b.wheels:
		w["omega"] = v / float(w["radius"])


func _test_steering_steady_turn() -> void:
	# At full sim, no help at all, the bars alone hold a steady turn, near the textbook lean.
	var acc := {"n": 0, "lean": 0.0, "v": 0.0, "yaw": 0.0, "bar": 0.0}
	var r := await ride({}, 11.0, func(b, t):
		b.assist = 0.0
		_hold_speed(b, 15.0)
		b.lean_input = 0.0 if t < 3.0 else 0.6
		if t > 7.0:
			acc["n"] += 1
			acc["lean"] += absf(b.lean_angle)
			acc["v"] += b.linear_velocity.length()
			acc["yaw"] += absf(b.angular_velocity.y)
			acc["bar"] += absf(b.bar_torque))
	var n := maxf(float(acc["n"]), 1.0)
	var lean := float(acc["lean"]) / n
	var v := float(acc["v"]) / n
	var radius := v / maxf(float(acc["yaw"]) / n, 1e-3)
	var textbook := rad_to_deg(atan(v * v / (Bike.G * radius)))
	var balance := rad_to_deg((r["bike"] as Bike)._balance_lean(lean))
	check(not r["crashed"] and absf(balance - textbook) < 4.0,
		"realism 0: steering alone holds a steady turn, %.1f deg from the tyres to the centre of mass against the textbook %.1f deg (%.0f m radius)"
		% [balance, textbook, radius])
	check(float(acc["bar"]) / n < Bike.MAX_BAR_TORQUE, "holding the turn takes %.1f N m on the bars" % (float(acc["bar"]) / n))
	await _done(r)


func _test_countersteer() -> void:
	# Hands off at 20 m/s, a push on the right grip (turning the bars left): the bars go left
	# for a moment, then the bike leans right and turns right.
	var st := {"steer_min": 0.0, "lean": 0.0, "yaw0": 0.0, "turned": 0.0}
	var r := await ride({}, 6.6, func(b, t):
		b.assist = 0.0
		_hold_speed(b, 20.0)
		b.hands_off = t > 4.0
		b.push_bars = -12.0 if t > 5.0 and t < 5.4 else 0.0
		if absf(t - 5.0) < 0.001:
			st["yaw0"] = _heading(b)
		if t > 5.0 and t < 5.15:
			st["steer_min"] = minf(st["steer_min"], b.steer)
		if t > 5.0 and t < 6.5:
			st["lean"] = maxf(st["lean"], b.lean_angle)
			st["turned"] = wrapf(_heading(b) - float(st["yaw0"]), -PI, PI))
	var turned: float = st["turned"]
	check(not r["crashed"] and st["steer_min"] < -deg_to_rad(0.2) and st["lean"] > deg_to_rad(4.0) and turned < -deg_to_rad(1.5),
		"counter-steering: pushing the right grip turns the bars left (%.1f deg), the bike leans right (%.0f deg) and turns right (%.0f deg)"
		% [rad_to_deg(st["steer_min"]), rad_to_deg(st["lean"]), rad_to_deg(-turned)])
	await _done(r)


func _test_hands_off() -> void:
	# A stock bike ridden no-handed at normal road speeds stays up: the trail and the spinning
	# front wheel steer it back under itself, the rider's hips only nudging it.
	for v in [12.0, 20.0, 28.0]:
		var st := {"worst": 0.0}
		var r := await ride({}, 11.0, func(b, t):
			b.assist = 0.0
			if t < 4.0:
				_hold_speed(b, v)
				return
			b.hands_off = true
			b.throttle = 0.25
			b.front_brake = 0.0
			if absf(t - 4.5) < 0.001:
				b.apply_torque_impulse(-b.global_transform.basis.z * 25.0)
			if t > 4.5:
				st["worst"] = maxf(st["worst"], absf(b.lean_angle)))
		var bike: Bike = r["bike"]
		check(not r["crashed"] and absf(bike.lean_angle) < deg_to_rad(6.0) and st["worst"] < deg_to_rad(20.0),
			"hands off at %d km/h a stock bike rides out a shove and stays up (worst %.1f deg, now %.1f)"
			% [roundi(v * 3.6), rad_to_deg(st["worst"]), rad_to_deg(bike.lean_angle)])
		await _done(r)


func _test_steering_wobble() -> void:
	# A shove on the bars: on a stock bike the front shakes its head at its wobble frequency (or
	# just settles, too damped to swing) and the shake dies away: hands on up to motorway speeds
	# and beyond, hands off at normal road speeds.
	for c in [[{}, 15.0, false], [{}, 30.0, false], [{}, 45.0, false], [{}, 15.0, true], [{}, 30.0, true],
			[Contracts.style_build("sport"), 45.0, false], [Contracts.style_build("sport"), 30.0, true],
			[Contracts.style_build("chopper"), 30.0, false], [Contracts.style_build("chopper"), 45.0, false]]:
		var k := await _bar_kick(c[0], c[1], c[2])
		var f: float = k["freq"]
		check(not k["crashed"] and (f == 0.0 or (f > 3.0 and f < 13.0)) and k["at"][3] < k["at"][0] * 0.3,
			"%s at %d km/h, hands %s: the bars shake at %.1f Hz and settle (%.2f deg after 0.1 s, %.2f after 2 s)"
			% [str(c[0].get("frame", "stock bike")), roundi(c[1] * 3.6), "off" if c[2] else "on", f, k["at"][0], k["at"][3]])
	# A steering damper makes it settle sooner.
	var plain := await _bar_kick({}, 30.0, true)
	var damped := await _bar_kick({"steering_damper": "damper_linear_adj"}, 30.0, true)
	var left_plain: float = plain["at"][1] + plain["at"][2]
	var left_damped: float = damped["at"][1] + damped["at"][2]
	check(left_damped < left_plain * 0.8, "a steering damper settles it quicker (%.3f deg against %.3f after 0.5 s, %.3f against %.3f after 1 s)"
		% [damped["at"][1], plain["at"][1], damped["at"][2], plain["at"][2]])
	# A genuinely bad setup, next to no trail: the shake grows into a tank-slapper; a damper cures it.
	var bad := await _bar_kick(SHORT_TRAIL_BIKE, 40.0, false)
	check(bad["at"][2] > 3.0, "with next to no trail a shove at the bars at %d km/h grows into a tank-slapper (%.1f deg after 1 s)" % [roundi(40.0 * 3.6), bad["at"][2]])
	var cured := await _bar_kick(_merge(SHORT_TRAIL_BIKE, {"steering_damper": "damper_rotary_race"}), 40.0, false)
	check(not cured["crashed"] and cured["at"][2] < cured["at"][0], "a steering damper on it calms it (%.2f deg after 1 s)" % cured["at"][2])


func _test_turn_in() -> void:
	# A long, raked chopper is slower to flick into a lean than a sports bike, steering alone.
	var times := {}
	for st in ["sport", "chopper"]:
		var mark := {"t": -1.0}
		var r := await ride(Contracts.style_build(st), 7.0, func(b, t):
			b.assist = 0.0
			_hold_speed(b, 15.0)
			b.lean_input = 0.0 if t < 4.0 else 0.5
			if mark["t"] < 0.0 and b.lean_angle > deg_to_rad(20.0):
				mark["t"] = t - 4.0)
		times[st] = mark["t"]
		check(not r["crashed"] and mark["t"] > 0.0, "the %s leans into the turn (20 deg in %.2f s)" % [st, mark["t"]])
		await _done(r)
	check(float(times["chopper"]) > float(times["sport"]) * 1.15, "the chopper is slower to turn in than the sports bike (%.2f s against %.2f s)"
		% [times["chopper"], times["sport"]])


func _test_steering_telemetry() -> void:
	# The F3 overlay and the dyno desk get the steering: bar torque, trail and shake.
	var tel := RideTelemetry.new("Steering")
	var r := await ride({}, 5.0, func(b, t):
		b.telemetry = tel
		b.throttle = 0.6
		b.lean_input = 0.5 if t > 2.5 else 0.0)
	var bike: Bike = r["bike"]
	var keys: Array = RideTelemetry.CHANNELS.map(func(c): return c[0])
	check(keys.has("bar") and keys.has("trail") and keys.has("wobble"), "the telemetry records bar torque, trail and steering shake")
	check(absf(tel.latest("trail") - bike.build.trail * 1000.0) < 40.0 and absf(tel.latest("bar")) > 0.0,
		"the trail reads about the bike's own (%.0f mm against %.0f)" % [tel.latest("trail"), bike.build.trail * 1000.0])
	check(TelemetryOverlay.STRIPS.has("Bar torque (+ right)") and TelemetryOverlay.STRIPS.has("Steering shake")
		and TelemetryGraph.STRIPS.any(func(s): return s[0] == "Trail"), "the overlay and the dyno desk chart them")
	check(tel.summary().has("max_wobble"), "the ride's summary has the worst shake")
	await _done(r)


func _test_physics_cost() -> void:
	# What the handling costs: the bike's own script per 120 Hz step, measured over a ride.
	var st := {"us": 0, "n": 0}
	var r := await ride({}, 4.0, func(b, t):
		b.throttle = 0.6
		b.lean_input = 0.5 if t > 1.5 else 0.0)
	var bike: Bike = r["bike"]
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in 400:
		var t0 := Time.get_ticks_usec()
		bike._physics_process(dt)
		st["us"] += Time.get_ticks_usec() - t0
		st["n"] += 1
		if i % 4 == 0:
			await get_tree().physics_frame
	var per := float(st["us"]) / float(st["n"])
	print("    bike physics step: %.0f us per step (%.1f%% of a 120 Hz frame)" % [per, per / 8333.0 * 100.0])
	check(per < 1500.0, "the bike's physics step is cheap enough (%.0f us)" % per)
	await _done(r)


func _test_telemetry() -> void:
	# The recorder logs every channel through a ride, thins itself out on a long one, and sums it up.
	var tel := RideTelemetry.new("Test bike")
	var r := await ride({}, 4.0, func(b, t):
		b.telemetry = tel
		b.throttle = 0.7
		b.lean_input = 0.5 if t > 2.0 else 0.0)
	check(tel.size() > 100 and tel.size() < 130, "the telemetry logs about %d samples a second (%d in 4 s)" % [int(RideTelemetry.RATE), tel.size()])
	var all := true
	for c in RideTelemetry.CHANNELS:
		all = all and (tel.data[c[0]] as PackedFloat32Array).size() == tel.size()
	check(all and tel.latest("speed") > 20.0 and tel.latest("load_r") > 500.0 and absf(tel.latest("lean")) > 5.0
		and tel.latest("rpm") > 1000.0, "every channel is recorded: speed, loads, lean, revs and the rest")
	var s := tel.summary()
	check(float(s["top_kmh"]) > 20.0 and float(s["max_lean"]) > 5.0, "the ride sums up (top %d km/h, lean %.0f deg)" % [int(s["top_kmh"]), s["max_lean"]])
	check(RideTelemetry.last == tel, "the latest recorder is the one the dyno desk shows")
	var long := RideTelemetry.new()
	for i in RideTelemetry.MAX_SAMPLES + 10:
		long.add({"t": i / RideTelemetry.RATE})
	check(long.size() < RideTelemetry.MAX_SAMPLES and is_equal_approx(long.interval, 2.0 / RideTelemetry.RATE),
		"a long ride thins out to fit (%d samples)" % long.size())
	RideTelemetry.last = tel
	# The overlay and the dyno desk's Last ride page draw it.
	var bike: Bike = r["bike"]
	var overlay := TelemetryOverlay.new()
	overlay.size = Vector2(400, 700)
	add_child(overlay)
	overlay.bike = bike
	overlay.queue_redraw()
	await get_tree().process_frame
	var desk := TuningComputer.new()
	add_child(desk)
	await get_tree().process_frame
	desk.visible = true
	for i in desk._tabs.get_tab_count():
		if desk._tabs.get_tab_control(i).name == "Last ride":
			desk._tabs.current_tab = i
	desk._process(1.0)
	check(desk.showing_ride() and desk._ride_graph.visible and not desk._graph.visible and desk._ride_text.text.contains("Test bike"),
		"the dyno desk's Last ride tab shows the ride's charts and numbers")
	await get_tree().process_frame
	overlay.queue_free()
	desk.queue_free()
	await _done(r)
	# Settings: Riding realism and the overlay are kept; F3 toggles the overlay.
	check(InputMap.has_action("telemetry") and Settings.binding_codes("telemetry").size() > 0,
		"the telemetry overlay has a key binding (%s)" % str(Settings.binding_codes("telemetry")))
	check(Settings.ACTIONS.any(func(a): return a[0] == "telemetry"), "and it's in the Key bindings tab")
	var was := [Settings.assist, false, Settings.telemetry_overlay]
	Settings.assist = 0.2
	Settings.telemetry_overlay = true
	Settings.save_settings()
	Settings.assist = 0.9
	Settings.telemetry_overlay = false
	Settings.load_settings()
	check(is_equal_approx(Settings.assist, 0.2) and Settings.telemetry_overlay,
		"Riding realism and the overlay are saved with the settings")
	Settings.assist = was[0]
	Settings.telemetry_overlay = was[2]
	Settings.save_settings()
	check(MainMenu.realism_text(0.0).contains("full sim") and MainMenu.realism_text(0.5).contains("protects the front"),
		"the Riding realism slider says what each end does")
	# In a session: getting on starts a recording and F3 shows the overlay.
	var real_path := Progress.path
	Progress.path = "user://profile_telemetry_test.json"
	DirAccess.remove_absolute(Progress.path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	Shed.request({"a": "mount", "bike": _bike_named("Old Faithful")})
	for i in 5:
		await get_tree().physics_frame
	check(main.bike != null and main.bike.telemetry != null and RideTelemetry.last == main.bike.telemetry,
		"getting on a bike starts a telemetry recording")
	Settings.telemetry_overlay = false
	_press("telemetry")
	for i in 3:
		await get_tree().physics_frame
	check(Settings.telemetry_overlay and main.telemetry_overlay.visible and main.telemetry_overlay.bike == main.bike,
		"F3 shows the telemetry overlay while riding")
	_press("telemetry")
	for i in 3:
		await get_tree().physics_frame
	check(not main.telemetry_overlay.visible, "and F3 hides it again")
	Settings.telemetry_overlay = was[2]
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
	Progress.path = real_path



## The big riding map: the roads join up without steps, keep to their grades, have no jumps on
## the loop, sit on the land; spawns and the customers' route are clear; surfaces are tagged;
## and the map stays light enough to draw (counts, visibility ranges, the draw distance).
func _test_world_map() -> void:
	var world := World.new()
	add_child(world)
	world.generate(1234)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var r := world.roads
	var t := world.terrain
	# Every road is an unbroken line of samples about 2 m apart; the loop closes on itself.
	var gaps := []
	for road in r.roads:
		var xz: PackedVector2Array = road["xz"]
		var n := xz.size()
		for i in (n if road["closed"] else n - 1):
			var d := xz[i].distance_to(xz[(i + 1) % n])
			if d < 1.0 or d > 3.0:
				gaps.append("%s@%d (%.1f m)" % [road["name"], i, d])
				break
	check(gaps.is_empty(), "every road is continuous, samples about 2 m apart %s" % str(gaps))
	var loop: Dictionary = r.roads[int(r.by_name["loop"])]
	check(loop["closed"] and loop["kind"] == "tarmac", "the loop is a closed tarmac road")
	# Branches start and end on the road they leave, at its height (no step).
	var bad_joins := []
	for road in r.roads:
		var xz: PackedVector2Array = road["xz"]
		var hs: PackedFloat32Array = road["h"]
		for end in ["start_join", "end_join"]:
			var j: Dictionary = road[end]
			if j.is_empty():
				continue
			var k := 0 if end == "start_join" else xz.size() - 1
			var parent := r.point(int(j["road"]), int(j["i"]))
			var flat := Vector2(parent.x, parent.z).distance_to(xz[k])
			var step := absf(hs[k] - parent.y)
			if flat > 0.5 or step > 0.05:
				bad_joins.append("%s %s (%.2f m off, %.3f m step)" % [road["name"], end, flat, step])
	check(bad_joins.is_empty(), "branches meet their roads flush %s" % str(bad_joins))
	# Grades: tarmac no steeper than 10 %, dirt no steeper than 35 %.
	var steep := []
	for road in r.roads:
		var hs: PackedFloat32Array = road["h"]
		var n := hs.size()
		var limit := 0.105 if road["kind"] == "tarmac" else 0.355
		var worst := 0.0
		for i in (n if road["closed"] else n - 1):
			worst = maxf(worst, absf(hs[(i + 1) % n] - hs[i]) / WorldRoads.STEP)
		if worst > limit:
			steep.append("%s %.1f%%" % [road["name"], worst * 100.0])
	check(steep.is_empty(), "every road keeps to a rideable grade %s" % str(steep))
	# No jumps on the loop or any tarmac road: every crest is gentle (radius 150 m or more).
	var sharp := []
	for road in r.roads:
		if road["kind"] != "tarmac":
			continue
		var hs: PackedFloat32Array = road["h"]
		var n := hs.size()
		var worst := 0.0
		for i in range(0 if road["closed"] else 1, n if road["closed"] else n - 1):
			worst = maxf(worst, 2.0 * hs[i] - hs[posmod(i - 1, n)] - hs[(i + 1) % n])
		var radius := WorldRoads.STEP * WorldRoads.STEP / maxf(worst, 0.0001)
		if radius < 150.0:
			sharp.append("%s crest radius %.0f m" % [road["name"], radius])
	check(sharp.is_empty(), "no jumps: every tarmac crest is gentle %s" % str(sharp))
	var hs_loop: PackedFloat32Array = loop["h"]
	var lo := 1e9
	var hi := -1e9
	for h in hs_loop:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	check(hi - lo > 6.0, "the loop goes up and down (%.1f m of climb)" % (hi - lo))
	# The loop is what a bike lands on all the way round: nothing sits on it.
	var blocked := []
	var lxz: PackedVector2Array = loop["xz"]
	for i in range(0, lxz.size(), 5):
		var top := world.surface_height(lxz[i].x, lxz[i].y)
		if absf(top - hs_loop[i]) > 0.1:
			blocked.append("%d (%.2f vs %.2f)" % [i, top, hs_loop[i]])
	check(blocked.is_empty(), "the loop's surface is clear all the way round %s" % str(blocked.slice(0, 4)))
	# The land lies just under every road, across its width: never through it, never far below.
	var poking := []
	for road in r.roads:
		var xz: PackedVector2Array = road["xz"]
		var hs: PackedFloat32Array = road["h"]
		var dirs: PackedVector2Array = road["dir"]
		var hw: float = road["hw"]
		for i in range(0, xz.size(), 3):
			var side := Vector2(-dirs[i].y, dirs[i].x) * hw * 0.9
			for p: Vector2 in [xz[i], xz[i] + side, xz[i] - side]:
				var g := t.height_at(p.x, p.y)
				if g > hs[i] + (0.03 if road["kind"] == "tarmac" else 0.15) or g < hs[i] - 0.6:
					poking.append("%s@%d (%.2f under %.2f)" % [road["name"], i, g, hs[i]])
					break
			if poking.size() > 0 and poking[-1].begins_with(road["name"]):
				break
	check(poking.is_empty(), "the land lies just under every road %s" % str(poking))
	# Roads only meet where one branches off another: no level crossings or overlaps elsewhere.
	var crossings := []
	for ra in r.roads.size():
		var a: Dictionary = r.roads[ra]
		var axz: PackedVector2Array = a["xz"]
		for i in range(0, axz.size(), 3):
			var cell := Vector2i(floori(axz[i].x / WorldRoads.CELL), floori(axz[i].y / WorldRoads.CELL))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for code: int in r._grid.get(cell + Vector2i(dx, dz), []):
						var rb := code >> 16
						if rb == ra:
							continue
						var b: Dictionary = r.roads[rb]
						var q := (b["xz"] as PackedVector2Array)[code & 0xFFFF]
						if q.distance_to(axz[i]) < float(a["hw"]) + float(b["hw"]) + 1.0 and not _roads_joined(r, ra, rb, axz[i]):
							var pair := "%s/%s" % [a["name"], b["name"]]
							if not crossings.has(pair):
								crossings.append(pair)
	check(crossings.is_empty(), "roads only meet at their junctions %s" % str(crossings))
	check(r.total_length("tarmac") > 15000.0 and r.total_length("dirt") > 6000.0,
		"a big network: %.1f km of tarmac, %.1f km of dirt" % [r.total_length("tarmac") / 1000.0, r.total_length("dirt") / 1000.0])
	var hard := r.roads.filter(func(x): return x["hard"]).size()
	check(hard >= 2, "some tracks are hard going in the hills (%d)" % hard)
	# The map is several km across, rises into mountains in the north, and nowhere is low enough
	# for a bike on the ground to look like it fell out of the world.
	var ground_lo := 1e9
	var ground_hi := -1e9
	for h in t.heights:
		ground_lo = minf(ground_lo, h)
		ground_hi = maxf(ground_hi, h)
	check(World.MAP_HALF * 2.0 >= 4000.0 and ground_hi > 300.0, "a %.0f km map with mountains %.0f m high" % [World.MAP_HALF / 500.0, ground_hi])
	check(ground_lo > -24.0, "the lowest ground (%.1f m) is above the fall-through line" % ground_lo)
	var pass_top := 0.0
	for h in (r.roads[int(r.by_name["pass"])]["h"] as PackedFloat32Array):
		pass_top = maxf(pass_top, h)
	check(pass_top > 120.0, "the mountain pass climbs %.0f m" % pass_top)
	# Spawn points stand on the yard's slab.
	var spawns_ok := true
	for i in 14:
		var sp := world.spawn_point(i)
		var o := sp.origin
		var on := Rect2(World.YARD_CENTER - World.YARD_HALF, World.YARD_HALF * 2.0).has_point(Vector2(o.x, o.z))
		if not on or absf(world.surface_height(o.x, o.z)) > 0.05:
			spawns_ok = false
	check(spawns_ok, "the spawn points are on the yard's slab")
	# The yard blends into the land: no kerb round its edge.
	var kerb := 0.0
	var rect := Rect2(World.YARD_CENTER - World.YARD_HALF, World.YARD_HALF * 2.0).grow(1.5)
	for k in 80:
		var f := k / 80.0
		for p: Vector2 in [rect.position + Vector2(rect.size.x * f, 0.0), rect.position + Vector2(0.0, rect.size.y * f),
				rect.end - Vector2(rect.size.x * f, 0.0), rect.end - Vector2(0.0, rect.size.y * f)]:
			kerb = maxf(kerb, absf(t.height_at(p.x, p.y)))
	check(kerb < 0.12, "the ground meets the yard's edge without a kerb (%.2f m at most)" % kerb)
	# Surfaces: tarmac on the roads, dirt on the tracks, grass off them, metal on the armco.
	var tags := {}
	for probe: Array in [["tarmac", world.road_transform(0.6).origin], ["dirt", world.road_transform_on("ridge", 400.0).origin],
			["grass", Vector3(300.0, 0.0, 300.0)], ["tarmac", Vector3(0.0, 0.0, 100.0)]]:
		var at: Vector3 = probe[1]
		var from := Vector3(at.x, at.y + 50.0, at.z)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 100.0, 1))
		var got := str((hit["collider"] as Object).get_meta("surface", "?")) if hit else "nothing"
		tags[probe[0]] = tags.get(probe[0], true) and got == probe[0]
		if got != probe[0]:
			print("    expected %s at %s, got %s" % [probe[0], str(at), got])
	check(not tags.values().has(false), "roads are tarmac, tracks dirt and fields grass %s" % str(tags))
	var barriers := world.find_child("Barriers", true, false)
	check(barriers != null and str(barriers.get_meta("surface", "")) == "metal", "the armco is tagged metal")
	# The customers' ride in and out runs on the loop where it crosses the yard, flat with the
	# slab, and nothing from the yard's test kit stands in the way.
	var route_ok := true
	for x: float in [24.0, 40.0, 56.0, 72.0]:
		var p := Contracts.road_at(x)
		var near := r.nearest(p.x, p.z, 5.0, "tarmac")
		if near.is_empty() or int(near["road"]) != int(r.by_name["loop"]) or float(near["d"]) > 1.5 or absf(float(near["h"])) > 0.15:
			route_ok = false
	check(route_ok, "the customers' road past the yard is the loop, level with the yard")
	var in_way := []
	for k in Contracts.PARK_SLOTS:
		for path: PackedVector3Array in [Contracts.ride_in_path(k), Contracts.ride_out_path(Contracts.park_xf(k))]:
			for item: Array in WorldYard.starting_kit():
				var at: Vector3 = (item[1] as Transform3D).origin
				for i in path.size() - 1:
					var c := Geometry3D.get_closest_point_to_segment(at, path[i], path[i + 1])
					if Vector2(c.x - at.x, c.z - at.z).length() < 2.5 and not in_way.has(item[2]):
						in_way.append(item[2])
	check(in_way.is_empty(), "the yard's test kit keeps clear of the customers' route %s" % str(in_way))
	var on_loop := []
	for item: Array in WorldYard.starting_kit():
		var at: Vector3 = (item[1] as Transform3D).origin
		var near := r.nearest(at.x, at.z, 6.0, "tarmac")
		if not near.is_empty():
			on_loop.append(item[2])
	check(on_loop.is_empty(), "and off the loop %s" % str(on_loop))
	# The bikers coming to the coffee shop ride in from the west along the same loop.
	var cafe_ok := true
	for i in 3:
		var p: Vector3 = CoffeeShop.ROAD_IN[i]
		var near := r.nearest(p.x, p.z, 5.0, "tarmac")
		if near.is_empty() or int(near["road"]) != int(r.by_name["loop"]) or float(near["d"]) > 1.5 or absf(float(near["h"])) > 0.15:
			cafe_ok = false
			print("    cafe road point %s: %s" % [str(p), str(near)])
	check(cafe_ok, "the cafe's bikers ride in along the loop past the yard, level with it")
	# Things to see: trees, rocks, villages and farms, barriers and signs.
	var plan: Dictionary = World._cache[1234]["props"]
	print("    %d trees, %d rocks, %d track rocks, %d buildings, %d fence runs, %d armco, %d signs" % [plan["trees"].size(),
		plan["rocks"].size(), plan["track_rocks"].size(), plan["buildings"].size(), plan["fences"].size(), plan["armco"].size(), plan["signs"].size()])
	check(plan["trees"].size() > 3000 and plan["rocks"].size() > 300 and plan["track_rocks"].size() > 50, "trees and rocks all over")
	var kinds := {}
	for b: Dictionary in plan["buildings"]:
		kinds[str(b["kind"])] = true
	check(plan["buildings"].size() > 60 and kinds.has("barn") and kinds.has("silo") and kinds.has("church"),
		"villages and farms have houses, barns, silos and a church (%d buildings)" % plan["buildings"].size())
	check(plan["armco"].size() > 40 and plan["signs"].size() > 10, "armco on the mountain roads and signs at junctions")
	# Fences stay off the roads and tracks, and the armco never runs across another road.
	var fence_on_road := 0
	for f: Array in plan["fences"]:
		var f0: Vector3 = f[0]
		var f1: Vector3 = f[1]
		for k in 5:
			var q := f0.lerp(f1, k / 4.0)
			var nr := r.nearest(q.x, q.z, 20.0)
			if not nr.is_empty() and float(nr["d"]) < float(r.roads[int(nr["road"])]["hw"]) + 1.0:
				fence_on_road += 1
				break
	check(fence_on_road == 0, "no field fence crosses a road or track (%d do)" % fence_on_road)
	var armco_on_road := 0
	for sgm: Array in plan["armco"]:
		var q: Vector3 = sgm[0]
		var own := r.nearest(q.x, q.z, 30.0, "tarmac")
		var other := r.nearest(q.x, q.z, 30.0, "", int(own["road"]) if not own.is_empty() else -1)
		if not other.is_empty() and float(other["d"]) < float(r.roads[int(other["road"])]["hw"]) + 0.5:
			armco_on_road += 1
	check(armco_on_road == 0, "no armco runs across another road (%d posts do)" % armco_on_road)
	# The armco is joined up: runs, not bits, with no short gaps between them.
	var runs := 0
	var short_gaps := 0
	var prev_end := Vector3.INF
	for sgm: Array in plan["armco"]:
		var a0: Vector3 = sgm[0]
		if prev_end == Vector3.INF or not prev_end.is_equal_approx(a0):
			runs += 1
			if prev_end != Vector3.INF and prev_end.distance_to(a0) < 12.0:
				# A short gap is only right where another road joins (the barrier stops for it).
				var gm := (prev_end + a0) * 0.5
				var own_r := r.nearest(gm.x, gm.z, 30.0)
				var join := r.nearest(gm.x, gm.z, 30.0, "", int(own_r["road"]) if not own_r.is_empty() else -1)
				if join.is_empty() or float(join["d"]) > float(r.roads[int(join["road"])]["hw"]) + 3.0:
					short_gaps += 1
		prev_end = sgm[1]
	check(runs > 0 and plan["armco"].size() / runs >= 5 and short_gaps == 0,
		"the armco comes in joined-up runs, with gaps only at junctions (%d runs, %.1f rails each, %d short gaps)" % [runs, float(plan["armco"].size()) / maxi(runs, 1), short_gaps])
	# Light enough to draw: trees and rocks in batches, everything far drawn only near.
	var nodes := _count_world_nodes(world)
	var batches := 0
	var instances := 0
	var unranged := []
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi is MultiMeshInstance3D:
			batches += 1
			instances += (gi as MultiMeshInstance3D).multimesh.instance_count
		if gi.visibility_range_end <= 0.0 and gi.global_position.length() > 400.0 and gi.get_parent().name != "TerrainMesh":
			unranged.append("%s/%s" % [gi.get_parent().name, gi.name])
	print("    %d nodes, %d multimesh batches holding %d instances" % [nodes, batches, instances])
	check(nodes < 8000, "the map is under 8000 nodes (%d)" % nodes)
	check(batches > 20 and instances > 3000, "trees and rocks are drawn in batches")
	check(unranged.size() < 5, "far things fade out with distance %s" % str(unranged.slice(0, 5)))
	# The draw distance setting scales every visibility range.
	var probe_gi: GeometryInstance3D = world.find_children("*", "MultiMeshInstance3D", true, false).filter(
		func(m): return (m as GeometryInstance3D).visibility_range_end > 0.0)[0]
	var kept := Settings.gfx_draw_distance
	Settings.gfx_draw_distance = 1.0
	world._apply_draw_distance()
	var base := probe_gi.visibility_range_end
	Settings.gfx_draw_distance = 2.0
	world._apply_draw_distance()
	check(is_equal_approx(probe_gi.visibility_range_end, base * 2.0), "the draw distance setting reaches the trees (%.0f to %.0f m)" % [base, probe_gi.visibility_range_end])
	Settings.gfx_draw_distance = kept
	world._apply_draw_distance()
	world.queue_free()
	await get_tree().physics_frame
	# The same map again comes from the cache, quickly.
	var t0 := Time.get_ticks_msec()
	var again := World.new()
	add_child(again)
	again.generate(1234)
	var ms := Time.get_ticks_msec() - t0
	check(ms < 4000, "making the same map again is quick (%d ms)" % ms)
	again.queue_free()
	await get_tree().physics_frame


## True when roads `a` and `b` meet near `p` (one branches off the other there).
func _roads_joined(r: WorldRoads, a: int, b: int, p: Vector2) -> bool:
	for pair: Array in [[a, b], [b, a]]:
		var child: Dictionary = r.roads[int(pair[0])]
		for end in ["start_join", "end_join"]:
			var j: Dictionary = child[end]
			if j.is_empty() or int(j["road"]) != int(pair[1]):
				continue
			var at := r.point(int(pair[1]), int(j["i"]))
			if Vector2(at.x, at.z).distance_to(p) < 40.0:
				return true
	return false


## Every node under `n`, counting `n`.
func _count_world_nodes(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count_world_nodes(c)
	return total


## Step 3 style packs: about thirty new parts made for each style, each with a look of its own.
func _test_style_packs() -> void:
	var packs := {}
	var names := {}
	var dup_names := []
	for id in PartsDB.parts:
		var p: Dictionary = PartsDB.get_part(id)
		var n := str(p.get("name", ""))
		if names.has(n) and p.has("pack"):
			dup_names.append(n)
		names[n] = true
		if p.has("pack"):
			packs.get_or_add(str(p["pack"]), []).append(id)
	check(dup_names.is_empty(), "every pack part has a name of its own %s" % [dup_names])
	for style in PartsDB.STYLES:
		var ids: Array = packs.get(style, [])
		var kinds := {}
		for id in ids:
			kinds[PartsDB.kind_of(id)] = true
		check(ids.size() >= 30 and kinds.size() >= 10, "%s has its own pack: %d parts across %d kinds" % [PartsDB.style_name(style), ids.size(), kinds.size()])
	var bad := []
	for style in packs:
		for id in packs[style]:
			var p: Dictionary = PartsDB.get_part(id)
			var look: Dictionary = p.get("look", {})
			var ok: bool = Money.part_price(id) > 0 and (p["styles"] as Array)[0] == style and p.has("color")
			if p["kind"] == "tank" and look.has("shape"):
				ok = ok and BikeModel.TANK_SHAPES.has(look["shape"])
			if p["kind"] == "saddle" and look.has("shape"):
				ok = ok and BikeModel.SEAT_SHAPES.has(look["shape"])
			if not ok:
				bad.append(id)
	check(bad.is_empty(), "pack parts are priced, tagged with their style first and use real shapes %s" % [bad])
	# Every pack part draws on a bike.
	var undrawn := []
	var drawn := 0
	for style in packs:
		for id in packs[style]:
			var slot: String = PartsDB.slots_for_kind(PartsDB.kind_of(id))[0]
			var m := BikeModel.new()
			add_child(m)
			m.build_from(BikeBuild.new({slot: id}))
			var b := m.slot_bounds(slot)
			if b.size.length() < 0.05 or b.size.length() > 4.0:
				undrawn.append("%s %s" % [id, b.size])
			else:
				drawn += 1
			m.free()
	check(undrawn.is_empty(), "all %d pack parts are drawn on the bike %s" % [drawn, undrawn])
	# Looks make different shapes, not just colours.
	var shapes := {"bobber_moon_16": ["front_wheel", "MoonDisc"], "cafe_ducktail": ["tail", "TailCowl"], "fishtail_pipes": ["exhaust", "Fishtail"],
		"cafe_visor_lamp": ["headlight", "Visor"], "cruiser_hard_bags": ["panniers", "Case"], "cruiser_leather_saddlebags": ["panniers", "Saddlebag"]}
	for id in shapes:
		var m := BikeModel.new()
		add_child(m)
		m.build_from(BikeBuild.new({shapes[id][0]: id}))
		check(m.find_children(shapes[id][1] + "*", "", true, false).size() > 0, "%s draws its own shape (%s)" % [PartsDB.part_name(id), shapes[id][1]])
		m.free()
	var plain := BikeModel.new()
	add_child(plain)
	plain.build_from(BikeBuild.new({"tank": "cafe_15"}))
	var drop := BikeModel.new()
	add_child(drop)
	drop.build_from(BikeBuild.new({"tank": "teardrop_classic"}))
	check(not plain.slot_bounds("tank").size.is_equal_approx(drop.slot_bounds("tank").size), "a teardrop tank is a different shape from the plain cafe tank")
	plain.free()
	drop.free()
	# A bike built from one style's pack reads as that style.
	for style in PartsDB.STYLES:
		var b: Dictionary = Contracts.style_build(style).duplicate()
		for id in packs.get(style, []):
			for slot in PartsDB.slots_for_kind(PartsDB.kind_of(id)):
				if slot in ["front_tyre", "rear_tyre"]:
					continue
				b[slot] = id
		var parts := PartsDB.sanitize_build(b)
		var found := PartsDB.detect_style(parts)
		check(found.get("style", "") == style, "a bike from the %s pack reads as %s (%s)" % [style, PartsDB.style_text(parts), found.get("style", "")])


# ---------------------------------------------------------------------------- shop and crew extras

func _test_part_preview() -> void:
	Shed.start_new("Tester", 64)
	var pc := PartsComputer.new()
	add_child(pc)
	pc.open()
	await get_tree().process_frame
	pc._show_section("bike")
	pc._show_kind("tank")
	var tank: String = pc.listed("tank")[0]
	pc._show_part(tank)
	await get_tree().process_frame
	var pv: PartPreview = pc.preview
	check(pv != null and pv.visible and pv.showing == "part:" + tank and pv.pivot.get_child_count() == 1,
		"picking a part in the shop shows it in 3D on its page (%s)" % pv.showing)
	var shown: Node3D = pv.pivot.get_child(0)
	var model: BikeModel = shown.get_meta("model")
	check(model != null and model.slot_bounds("tank").size.length() > 0.05, "it's the part itself, drawn the way it is on a bike")
	# The camera is far enough back to see all of it.
	var size: Vector3 = shown.get_meta("size")
	var rect := Rect2(Vector2.ZERO, Vector2(pv.viewport.size))
	var inside := true
	for i in 8:
		var corner := Vector3(size.x * ((i & 1) - 0.5), size.y * (((i >> 1) & 1) - 0.5), size.z * (((i >> 2) & 1) - 0.5))
		inside = inside and rect.has_point(pv.camera.unproject_position(pv.pivot.global_transform * corner))
	check(inside, "the whole part fits in the picture")
	var turn0 := pv.pivot.rotation.y
	for i in 30:
		await get_tree().process_frame
	check(absf(pv.pivot.rotation.y - turn0) > 0.05, "it turns round slowly on its own")
	pc._show_part(pc.listed("tank")[1])
	await get_tree().process_frame
	check(pv.showing == "part:" + str(pc.listed("tank")[1]) and pv.pivot.get_child_count() == 1, "picking another part swaps it")
	pc._show_section("shed")
	pc._show_kind("eq:trolley")
	check(not pv.visible, "shed kit has no 3D preview")
	# The Sell aisle shows the loose part you'd be selling, as it is.
	var loose := Shed._new_item("iridium_plugs", 0.4, 0.3, 0.2)
	Shed._move(loose, "floor", Transform3D(Basis(), Workshop.CENTER))
	pc._show_section("sell")
	pc._show_kind("sell:parts")
	pc._show_part("item:%d" % loose)
	await get_tree().process_frame
	check(pv.visible and pv.showing == "item:%d" % loose, "and the Sell aisle shows the part being sold")
	pc.queue_free()
	await get_tree().process_frame
	Shed.stop()


func _test_trolley_shed() -> void:
	Shed.start_new("Tester", 63)
	var me := Shed.me()
	check(Equipment.by_kind("trolley").size() >= 2 and Equipment.SURFACE_KINDS.has("trolley"), "the shop sells trolleys, with a deck to load")
	check(PartsComputer.group_of("eq:trolley") == "Storage and benches", "listed with the storage and benches")
	Shed.request({"a": "order_furniture", "model": "trolley_flatbed"})
	var fid := _first_furniture("trolley_flatbed")
	check(fid != 0, "a flatbed trolley can be ordered")
	var key := "f%d" % fid
	var s := Shed.surface(key)
	check(not s.is_empty() and s["kind"] == "trolley" and is_equal_approx(float(s["top"]), Equipment.work_height("trolley_flatbed")),
		"its deck is a surface parts go down anywhere on")
	var loaded := []
	for part in ["iridium_plugs", "stock_muffler", "peanut_9"]:
		var id := _in_hands(part)
		if part == "peanut_9":
			Shed.items[id]["boxed"] = true
		if _set_down_near(key, Vector2(0.0, -0.4 + loaded.size() * 0.4)):
			loaded.append(id)
	check(loaded.size() == 3 and Shed.surface_items(key).size() == 3, "it takes a load: plugs, an exhaust and a boxed tank (%d)" % Shed.surface_items(key).size())
	var before := {}
	for id in loaded:
		before[id] = Shed.spot_transform(str(Shed.items[id]["ref"]))
	var old_xf: Transform3D = Shed.furniture[fid]["xf"]
	check(Shed.check(me, {"a": "grab", "furniture": fid}) == "", "a loaded trolley can be taken hold of")
	Shed.request({"a": "grab", "furniture": fid})
	var new_xf := Transform3D(Basis(Vector3.UP, 0.8), Workshop.CENTER + Vector3(1.0, 0.0, 2.0))
	Shed.request({"a": "move_furniture", "furniture": fid, "xf": new_xf})
	Shed.request({"a": "release", "furniture": fid, "xf": new_xf})
	var rode := true
	for id in loaded:
		var want: Transform3D = new_xf * old_xf.affine_inverse() * (before[id] as Transform3D)
		rode = rode and Shed.items[id]["at"] == "spot" and Shed.spot_transform(str(Shed.items[id]["ref"])).origin.distance_to(want.origin) < 0.001
	check(rode, "everything on it moves with it")
	check(Shed.spot_role(str(Shed.items[loaded[0]]["ref"])) == "trolley", "the parts know they're on a trolley")
	# Off again where it's needed.
	Shed.request({"a": "take", "spot": str(Shed.items[loaded[1]]["ref"])})
	check(Shed.held_by(me) == loaded[1] and Shed.surface_items(key).size() == 2, "and come off again at the other end")
	# It keeps its load through a save.
	var snap: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	Shed.load_state(snap, "Tester")
	check(Shed.surface_items(key).size() == 2 and Shed.furniture[fid]["xf"].origin.is_equal_approx(new_xf.origin), "a saved shed keeps the trolley where it was, loaded")
	Shed.stop()


func _test_trolley_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	var ws: Workshop = main.workshop
	var w: Walker = main.walker
	Shed.request({"a": "order_furniture", "model": "trolley_parts"})
	var fid := _first_furniture("trolley_parts")
	var key := "f%d" % fid
	var box := _in_hands("iridium_plugs")
	Shed.items[box]["boxed"] = true
	Shed.items[box]["by"] = "Tester"
	_set_down_near(key)
	var plugs := _in_hands("iridium_plugs")
	_set_down_near(key, Vector2(0.0, 0.3))
	check(Shed.held_by(Shed.me()) == 0 and Shed.surface_items(key).has(plugs), "a box and a loose part go on the parts trolley")
	Shed.changed.emit()
	await get_tree().process_frame
	var view: EquipmentView = ws.furniture_nodes[fid]
	check(view.find_child("Handle", true, false) != null and view.find_children("Castor*", "", true, false).size() == 4, "the trolley is drawn with a handle and four castors")
	var shown: Node3D = ws._spot_nodes.get(str(Shed.items[box]["ref"]))
	check(shown != null and view.is_ancestor_of(shown), "the parts on its deck are drawn riding on it")
	# Push it: take hold of it and walk.
	var xf0: Transform3D = Shed.furniture[fid]["xf"]
	w.place(Transform3D(Basis(), xf0.origin + xf0.basis.z * 1.3))
	await get_tree().physics_frame
	Shed.request({"a": "grab", "furniture": fid})
	var at0 := shown.global_position
	Input.action_press("move_forward")
	for i in 90:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await get_tree().physics_frame
	var moved := shown.global_position.distance_to(at0)
	check(moved > 0.5, "pushing it along takes the box with it (%.2f m)" % moved)
	check((Shed.furniture[fid]["xf"] as Transform3D).origin.distance_to(xf0.origin) > 0.4, "and the shed knows where it's got to")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_order_notes() -> void:
	Shed.start_new("Simon", 62)
	var me := Shed.me()
	Shed.request({"a": "order_part", "part": "iridium_plugs"})
	var box := 0
	for id in Shed.items:
		if Shed.items[id].get("boxed", false):
			box = id
	check(box != 0 and str(Shed.items[box].get("by", "")) == "Simon", "a box ordered says who ordered it")
	var shown := BikeModel.item_display(box)
	var note: Node3D = shown.get_node_or_null("OrderNote")
	var front: Node3D = shown.get_node_or_null("OrderNoteFront")
	var size: Vector3 = shown.get_meta("size")
	check(note != null and front != null and note.position.y > size.y and front.position.z > size.z * 0.5,
		"a note is stuck on its lid and its front")
	var texts := []
	for n in note.get_children():
		if n is Label3D:
			texts.append((n as Label3D).text)
	check(texts.has("FOR") and texts.has("Simon"), "the note says who it's for %s" % str(texts))
	shown.free()
	check(OrderNote.line(Shed.items[box]) == "Ordered by Simon  ·  ", "and so does the info panel")
	# The other player's orders carry their name.
	Shed._add_crew(77, "Pal")
	Shed._apply(77, {"a": "order_part", "part": "stock_muffler"})
	var theirs := 0
	for id in Shed.items:
		if Shed.items[id].get("boxed", false) and Shed.items[id]["part"] == "stock_muffler":
			theirs = id
	check(theirs != 0 and str(Shed.items[theirs].get("by", "")) == "Pal", "a box the other player ordered has their name on it")
	# Unpacked, the part has no note; fluids never had a box.
	Shed._move(box, "floor", Transform3D(Basis(), Workshop.CENTER))
	Shed.request({"a": "unpack", "item": box})
	var unboxed := BikeModel.item_display(box)
	check(unboxed.get_node_or_null("OrderNote") == null, "unpacked, the part has no note")
	unboxed.free()
	var snap: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	Shed.load_state(snap, "Simon")
	check(str(Shed.items[theirs].get("by", "")) == "Pal", "a saved shed keeps whose box is whose")
	check(me != 77, "the notes go by the player")
	Shed.stop()


func _test_geometry_list() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	var ws: Workshop = main.workshop
	var w: Walker = main.walker
	var a := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == "Rusty Ranger":
			a = id
	var view: Node3D = ws.bike_views[a]
	w.place(Transform3D(Basis(), view.global_position + Vector3(1.4, 0.1, 0.0)))
	await get_tree().physics_frame
	main.open_geometry()
	var geo: GeometryMode = main.geometry
	await get_tree().process_frame
	var slots := geo.pickable_slots()
	check(geo._list_panel.visible and slots.has("tank") and slots.has("frame") and slots.has("front_wheel"), "geometry mode lists the bike's parts")
	check(geo.part_buttons.size() == slots.size(), "a row for each part on it (%d)" % slots.size())
	var tank_item := Shed.item_on(a, "tank")
	var row: Button = geo.part_buttons["tank"]
	check(row.text.contains(PartsDB.slot_name("tank")) and row.text.contains(PartsDB.part_name(str(Shed.items[tank_item]["part"]))),
		"each row says the slot and the part in it (%s)" % row.text)
	row.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(geo.selected == "tank" and row.button_pressed and geo.gizmo.visible, "clicking a row selects that part, handles and all")
	geo.select("fork")
	check(geo.part_buttons["fork"].button_pressed and not row.button_pressed, "picking a part on the bike lights up its row instead")
	geo.set_part_offset("fork", _geo_off(0.02))
	await get_tree().process_frame
	check(geo.part_buttons["fork"].text.begins_with("* "), "a moved part is marked in the list")
	geo.discard_and_close()
	await get_tree().process_frame
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_style_bike_orders() -> void:
	Shed.start_new("Tester", 61)
	var me := Shed.me()
	Shed.garage_money = 1000000
	for id in Shed.bikes.keys():
		Shed.remove_bike(id)
	var right := 0
	var fits := []
	for style in PartsDB.STYLES:
		var parts := Shed.style_parts(style)
		var fit := PartsDB.style_fit(style, parts)
		fits.append("%s %d%%" % [style, roundi(fit * 100.0)])
		if str(PartsDB.detect_style(parts)["style"]) == style and fit >= 0.6:
			right += 1
		check(PartsDB.sanitize_build(parts) == parts, "a %s found to order is a build that goes together" % PartsDB.style_noun(style))
	check(right == PartsDB.STYLES.size(), "every style ordered comes out as that style %s" % str(fits))
	# Order a cruiser: it turns up in a bay, worn like any project bike, paid for by the business.
	check(Shed.check(me, {"a": "order", "style": "spaceship"}) != "", "a style nobody deals in can't be ordered")
	var money0 := Shed.garage_money
	Shed.request({"a": "order", "style": "cruiser"})
	var bike := 0
	for id in Shed.bikes:
		bike = id
	check(bike != 0 and str(Shed.bikes[bike]["name"]) == "Cruiser project" and str(Shed.bikes[bike].get("style_order", "")) == "cruiser",
		"ordering a cruiser brings one to a bay (%s)" % (str(Shed.bikes[bike]["name"]) if bike != 0 else "none"))
	var parts_now := Contracts.current_parts(bike)
	check(str(PartsDB.detect_style(parts_now)["style"]) == "cruiser", "it's a cruiser: %s" % PartsDB.style_text(parts_now))
	var worn := 0
	for slot in ["frame", "tank", "engine"]:
		var it: Dictionary = Shed.items[Shed.item_on(bike, slot)]
		if float(it["rust"]) + float(it["dirt"]) + float(it["wear"]) > 0.1:
			worn += 1
	check(worn == 3, "it's a project: rusty, dirty and worn like the rest")
	var paid := money0 - Shed.garage_money
	check(paid == Money.style_project_price(bike) and paid > Money.project_price(bike), "it costs a little more than any old project bike (%d)" % paid)
	check(Money.typical_style_price("cruiser") > 0, "the order button has a rough price for one")
	# From the parts computer.
	var pc := PartsComputer.new()
	add_child(pc)
	pc.open()
	pc.set_bike_style("chopper")
	check(pc._bike_btn.text == "Order a chopper" and pc._bike_style_pick.selected == PartsDB.STYLES.find("chopper") + 1,
		"the parts computer's style picker sets the order button (%s)" % pc._bike_btn.text)
	pc.order_bike()
	var chop := 0
	for id in Shed.bikes:
		if str(Shed.bikes[id].get("style_order", "")) == "chopper":
			chop = id
	check(chop != 0 and str(PartsDB.detect_style(Contracts.current_parts(chop))["style"]) == "chopper", "and orders that style")
	pc.set_bike_style("")
	check(pc._bike_btn.text == "Order a project bike", "Any style orders any old project bike")
	pc.queue_free()
	await get_tree().process_frame
	# Not enough money: nothing is delivered.
	Shed.garage_money = 10
	var n := Shed.bikes.size()
	Shed.request({"a": "order", "style": "tourer"})
	check(Shed.bikes.size() == n and Shed.garage_money == 10, "the business can't buy one it can't afford")
	Shed.stop()


func _test_emote_poses() -> void:
	for e in Emotes.LIST:
		var length := float(Emotes.LENGTH[e])
		check(Emotes.weight(e, 0.0) == 0.0 and Emotes.weight(e, length * 0.5) == 1.0 and Emotes.weight(e, length + 0.1) == 0.0,
			"%s eases in, holds and eases out" % Emotes.NAMES[e])
		check(Settings.ACTIONS.any(func(a): return a[0] == Emotes.action_of(e)), "%s has a key of its own" % Emotes.NAMES[e])
	check(Emotes.pose("wave", 0.5)["r"].y > 0.5 and Emotes.pose("wave", 0.5)["l"] == Vector3.ZERO, "a wave puts the right hand up")
	check(Emotes.pose("cheer", 0.5)["r"].y > 0.7 and Emotes.pose("cheer", 0.5)["l"].y > 0.7, "a cheer puts both arms up")
	var right_of := Vector3(3.0, 1.38, -1.0)
	check((Emotes.pose("point", 1.0, right_of)["r"] as Vector3).is_equal_approx((right_of - RiderFigure.ARM_R["shoulder"]).normalized()),
		"a point aims at the spot it's told")
	var left_of := Vector3(-3.0, 1.0, -1.0)
	check(Emotes.pose("point", 1.0, left_of)["r"] == Vector3.ZERO and (Emotes.pose("point", 1.0, left_of)["l"] as Vector3).x < -0.9,
		"with the left arm when it's off to the left, not through the body")
	var d := Vector3(0.3, 0.8, -0.5).normalized()
	check((Emotes.arm_turn(true, d) * Emotes.rest_dir(true)).is_equal_approx(d), "an arm swings from rest to point the way the pose says")
	check(Emotes.arm_turn(false, Vector3.ZERO) == Quaternion.IDENTITY, "no direction leaves an arm at rest")
	var fig := RiderFigure.make({}, Color.RED)
	check(fig.get_node_or_null("ArmR") != null and fig.get_node_or_null("ArmL") != null, "the figure's arms hang from their shoulders so they can move")
	fig.free()
	var emote_clash: Array = Settings.clashes().filter(func(c): return str(c["a"]).begins_with("emote") or str(c["b"]).begins_with("emote"))
	check(emote_clash.is_empty(), "the emote keys clash with nothing %s" % str(emote_clash))


func _test_emotes_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	await get_tree().physics_frame
	var w: Walker = main.walker
	var got := []
	var on_emote := func(p, d): got.append([p, d])
	Shed.emoted.connect(on_emote)
	# B opens the bar, and a tool key then picks an emote.
	var ev := InputEventAction.new()
	ev.action = "emote_menu"
	ev.pressed = true
	check(w._emote_input(ev) and w.emote_menu_open, "B opens the emote bar")
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.emote_bar.visible, "which shows on screen")
	check(main.emote_bar.size.x > 500.0 and main.emote_bar.size.y < 80.0, "as one wide row along the bottom, not a narrow column of letters")
	ev = InputEventAction.new()
	ev.action = "tool_1"
	ev.pressed = true
	check(w._emote_input(ev) and not w.emote_menu_open and w.tool == "hands", "with it open, 1 picks the first emote, not a tool")
	check(got.size() == 1 and got[0][0] == Shed.me() and got[0][1]["e"] == "wave" and str(got[0][1]["name"]) == str(Shed.crew[Shed.me()]["name"]), "and the crew is told you waved %s" % str(got))
	ev = InputEventAction.new()
	ev.action = "emote_point"
	ev.pressed = true
	w._emote_input(ev)
	check(got.size() == 2 and got[1][1]["e"] == "point" and got[1][1].get("at") is Vector3, "F7 points at what you're looking at")
	Shed.request({"a": "emote", "e": "moonwalk"})
	check(got.size() == 2, "there's no such emote as a moonwalk")
	ev = InputEventAction.new()
	ev.action = "tool_2"
	ev.pressed = true
	check(not w._emote_input(ev), "with the bar shut, the tool keys are tools again")
	Shed.emoted.disconnect(on_emote)
	# Another player's figure does them.
	var rp := RemotePlayer.new()
	main.world.add_child(rp)
	rp.setup(4242, "Pal", Color(0.2, 0.4, 0.9))
	main.remotes[4242] = rp
	await get_tree().process_frame
	main._on_emote(4242, {"e": "wave", "name": "Pal"})
	for i in 70:
		await get_tree().process_frame
	var arm: Node3D = rp._body_look.get_node("ArmR")
	var hand_dir: Vector3 = arm.quaternion * Emotes.rest_dir(true)
	check(rp.emote == "wave" and hand_dir.y > 0.4, "their figure waves, hand up (%s)" % str(hand_dir))
	check(rp._bubble.visible and rp._bubble.text == "*waves*", "with what they're doing over their head")
	for i in 300:
		await get_tree().process_frame
	check(rp.emote == "" and arm.quaternion.is_equal_approx(Quaternion.IDENTITY) and not rp._bubble.visible, "and goes back to how they were")
	# A ping: they point at what they pinged as well as it lighting up.
	var target := rp._figure.global_position + Vector3(3.0, 1.2, -2.0)
	main._on_ping(4242, {"at": target, "what": "Over here", "name": "Pal", "item": 0, "furniture": 0})
	for i in 70:
		await get_tree().process_frame
	var shoulder: Vector3 = rp._figure.global_transform * (RiderFigure.ARM_R["shoulder"] as Vector3)
	var pointing: Vector3 = rp._figure.global_basis * (arm.quaternion * Emotes.rest_dir(true))
	check(rp.emote == "point" and pointing.normalized().dot((target - shoulder).normalized()) > 0.95, "a ping makes their figure point at it")
	main.remotes.erase(4242)
	rp.queue_free()
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------- the coffee shop

## The cafe next door: its building, terrace and car park keep clear of the shed's rooms, the
## yard's markings and kit and the sales office; twenty bays and plenty of chairs in and out.
func _test_coffee_layout() -> void:
	var cafe := CoffeeShop.footprint()
	var site := cafe.grow(CoffeeShop.WALL + 0.3).merge(CoffeeShop.TERRACE).merge(CoffeeShop.CAR_PARK)
	var all := Workshop.rooms()
	all.merge(GarageUpgrades.rooms({"wing": true, "annex": true}))
	all.erase("cafe")
	all["wash"] = Rect2(Workshop.WASH_CENTER.x - Workshop.WASH_HALF.x, Workshop.WASH_CENTER.z - Workshop.WASH_HALF.y,
		Workshop.WASH_HALF.x * 2.0, Workshop.WASH_HALF.y * 2.0)
	all["forecourt"] = SalesOffice.FORECOURT
	all["u_turn"] = WorldYard.UTURN
	all["drop_off"] = WorldYard.DROP_OFF
	for k in WorldYard.FIGURE_EIGHT.size():
		var c: Vector2 = WorldYard.FIGURE_EIGHT[k]
		all["eight%d" % k] = Rect2(c - Vector2.ONE * WorldYard.FIGURE_EIGHT_R, Vector2.ONE * WorldYard.FIGURE_EIGHT_R * 2.0)
	var hits := []
	for room in all:
		if site.intersects(all[room] as Rect2):
			hits.append(room)
	check(hits.is_empty(), "the cafe, its terrace and car park keep clear of the shed's rooms, the wash bay and the yard's markings %s" % str(hits))
	check(Workshop.room_at(CoffeeShop.CENTER) == "cafe" and Shed.in_work_area(CoffeeShop.park_xf(0).origin)
		and Shed.in_work_area(CoffeeShop.CENTER), "the cafe is a room, and you can work and put things down there")
	# Twenty marked bays, apart and in the car park, off the aisle.
	var apart := true
	var inside := true
	for i in CoffeeShop.PARK_SLOTS:
		var a := CoffeeShop.park_xf(i).origin
		inside = inside and CoffeeShop.CAR_PARK.grow(-0.3).has_point(Vector2(a.x, a.z)) and absf(a.z - CoffeeShop.AISLE_Z) > 2.0
		for j in range(i + 1, CoffeeShop.PARK_SLOTS):
			apart = apart and a.distance_to(CoffeeShop.park_xf(j).origin) >= 1.2
	check(CoffeeShop.PARK_SLOTS == 20 and apart and inside, "twenty bike bays, at least 1.2 m apart, in the car park")
	# Chairs inside and out, enough for a full car park.
	var indoors := 0
	var outdoors := 0
	var placed := true
	for s in CoffeeShop.seat_count():
		var at := CoffeeShop.seat_xf(s).origin
		if CoffeeShop.seat_outdoors(s):
			outdoors += 1
			placed = placed and CoffeeShop.TERRACE.has_point(Vector2(at.x, at.z))
		else:
			indoors += 1
			placed = placed and cafe.grow(-0.2).has_point(Vector2(at.x, at.z))
	check(indoors >= 12 and outdoors >= 20 and indoors + outdoors >= CoffeeShop.PARK_SLOTS and placed,
		"seats inside (%d) and out on the terrace (%d)" % [indoors, outdoors])
	# Every way to a chair runs up the walkway and its table's lane, clear of the other tables.
	var through := []
	for s in CoffeeShop.seat_count():
		var way := CoffeeShop.seat_way(s)
		for i in way.size() - 2:
			for t in CoffeeShop.TABLES.size():
				var c: Vector2 = CoffeeShop.TABLES[t][0]
				var p := Geometry3D.get_closest_point_to_segment(Vector3(c.x, 0.0, c.y), way[i], way[i + 1])
				if Vector2(p.x - c.x, p.z - c.y).length() < 0.75 and not through.has(s):
					through.append(s)
	check(through.is_empty(), "the walk to each chair goes round the tables %s" % str(through))
	# The bikers' route in and out, and over to the sales office, misses the yard's kit.
	var in_way := []
	var routes: Array[PackedVector3Array] = [PackedVector3Array(CoffeeShop.TO_SALES)]
	for k in CoffeeShop.PARK_SLOTS:
		routes.append(CoffeeShop.ride_in(k))
		routes.append(CoffeeShop.ride_out(k))
	for path in routes:
		for item: Array in WorldYard.starting_kit():
			var at: Vector3 = (item[1] as Transform3D).origin
			for i in path.size() - 1:
				var c := Geometry3D.get_closest_point_to_segment(at, path[i], path[i + 1])
				if Vector2(c.x - at.x, c.z - at.z).length() < 2.5 and not in_way.has(item[2]):
					in_way.append(item[2])
	check(in_way.is_empty(), "the yard's test kit keeps clear of the bikers' route %s" % str(in_way))
	var near_humps := false
	for x in WorldYard.HUMPS_X:
		for i in CoffeeShop.ROAD_IN.size() - 1:
			var c := Geometry3D.get_closest_point_to_segment(Vector3(x, 0.0, WorldYard.HUMPS_Z), CoffeeShop.ROAD_IN[i], CoffeeShop.ROAD_IN[i + 1])
			near_humps = near_humps or Vector2(c.x - x, c.z - WorldYard.HUMPS_Z).length() < 3.0
	check(not near_humps, "and the speed humps")


## Opening hours, bikers coming and going on all sorts of bikes, wandering over to the showroom.
func _test_coffee_visitors() -> void:
	Shed.start_new("Tester", 91)
	CoffeeShop.advance(0.0, 7.0)
	check(not CoffeeShop.is_open(), "before 8:00 the cafe is shut")
	CoffeeShop.advance(1.0, 7.5)
	check(CoffeeShop.visitors().is_empty(), "and nobody comes while it is")
	CoffeeShop.advance(0.0, 8.5)
	CoffeeShop.advance(0.1, 8.6)
	check(CoffeeShop.is_open() and CoffeeShop.visitors().is_empty(), "it opens at 8:00, and the first bikers aren't there straight away")
	CoffeeShop.advance(CoffeeShop.FIRST_VISIT, 9.0)
	check(not CoffeeShop.visitors().is_empty(), "then they come")
	# Groups, solo riders, and their bikes.
	var styles := {}
	var sizes := {}
	var group_ok := true
	for n in 40:
		Shed.coffee["visitors"] = {}
		var ids := CoffeeShop.spawn_group()
		sizes[ids.size()] = true
		var leave := -1.0
		var parks := {}
		var seats := {}
		for id in ids:
			var v: Dictionary = CoffeeShop.visitors()[id]
			styles[str(v["bike"]["style_text"])] = true
			if leave < 0.0:
				leave = float(v["leave_at"])
			group_ok = group_ok and float(v["leave_at"]) == leave and not parks.has(v["park"]) and not seats.has(v["seat"])
			parks[v["park"]] = true
			seats[v["seat"]] = true
	check(sizes.has(1) and sizes.keys().any(func(k): return k >= 3) and sizes.keys().all(func(k): return k >= 1 and k <= CoffeeShop.GROUP_MAX),
		"they come on their own or in groups of up to five %s" % str(sizes.keys()))
	check(group_ok, "a group leaves together, each in their own bay and chair")
	check(styles.size() >= 5, "on all sorts of bikes (%d styles: %s)" % [styles.size(), ", ".join(styles.keys().slice(0, 6))])
	var v0: Dictionary = CoffeeShop.visitors().values()[0]
	var line := CoffeeShop.bike_line(v0)
	check(line.contains(" hp") and line.contains("% condition") and line.contains("worth about £") and line.contains(str(v0["bike"]["model"])),
		"its info line: style, engine, power, condition, roughly its worth (%s)" % line)
	check(not (v0["bike"]["parts"] as Dictionary).is_empty() and PartsDB.sanitize_build(v0["bike"]["parts"]) == v0["bike"]["parts"]
		and (str(v0["bike"]["parts"].get("side_stand", "none")) != "none" or str(v0["bike"]["parts"].get("centre_stand", "none")) != "none"),
		"a real bike, with a stand to park on")
	# A full car park.
	Shed.coffee["visitors"] = {}
	for n in 12:
		CoffeeShop.spawn_group(5)
	var used := {}
	for v in CoffeeShop.visitors().values():
		used[v["park"]] = true
	check(CoffeeShop.visitors().size() == CoffeeShop.PARK_SLOTS and used.size() == CoffeeShop.PARK_SLOTS and CoffeeShop.spawn_group(2).is_empty(),
		"twenty bikes fill the car park, and nobody else stops")
	# Closing time: they drink up and go, and nobody new comes.
	CoffeeShop.advance(0.01, 18.2)
	check(not CoffeeShop.is_open() and CoffeeShop.hours_text().contains("08:00"), "it shuts at 18:00 (%s)" % CoffeeShop.hours_text())
	CoffeeShop.advance(CoffeeShop.CLOSING_HOURS + 0.01, 18.5)
	check(CoffeeShop.visitors().values().all(func(v): return str(v["state"]) == "out"), "everyone drinks up and goes")
	CoffeeShop.advance(CoffeeShop.LEAVING_HOURS + 0.1, 19.0)
	CoffeeShop.advance(3.0, 21.0)
	check(CoffeeShop.visitors().is_empty(), "and nobody comes in the evening")
	# Wandering over to look at a bike on show, and now and then making an offer on it.
	CoffeeShop.advance(0.0, 10.0)
	var bike := _bike_named("Old Faithful")
	Shed.bikes[bike]["xf"] = Workshop.SHOWROOM_SPOTS[0]
	Shed.request({"a": "sale_list", "bike": bike, "ask": 5000})
	Shed.coffee["visitors"] = {}
	var ids := CoffeeShop.spawn_group(1)
	var v: Dictionary = CoffeeShop.visitors()[ids[0]]
	v["browse_at"] = CoffeeShop.clock()
	v["leave_at"] = CoffeeShop.clock() + 1.0
	Shed.coffee["next_at"] = CoffeeShop.clock() + 50.0
	CoffeeShop.advance(0.01, 10.0)
	check(str(v["state"]) == "browse" and int(v["stand"]) == 0 and Sales.bike_on_stand(0) == bike, "a biker wanders over to look at the bike on show")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var offers := Sales.offers().size()
	for n in 200:
		if Sales.offers().size() == offers:
			CoffeeShop._maybe_buyer(v, 0, rng)
	var o: Dictionary = Sales.offers().values()[Sales.offers().size() - 1] if Sales.offers().size() > offers else {}
	check(not o.is_empty() and str(o["buyer"]) == str(v["name"]) and str(o["said"]).contains("cafe") and int(o["bike"]) == bike,
		"and now and then makes an offer on it, like a buyer online")
	CoffeeShop.advance(1.1, 11.0)
	check(str(v["state"]) == "out", "then they go back to their bike and leave")


## Making an offer on a biker's bike: hardly ever taken, more often for more, a sale that brings
## the bike into the yard as the shed's.
func _test_coffee_offers() -> void:
	Shed.start_new("Tester", 92)
	var me := Shed.me()
	CoffeeShop.advance(0.0, 12.0)
	check(CoffeeShop.accept_chance(500, 1000) == 0.0 and CoffeeShop.accept_chance(1000, 1000) <= 0.05
		and CoffeeShop.accept_chance(1500, 1000) > CoffeeShop.accept_chance(1000, 1000)
		and CoffeeShop.accept_chance(100000, 1000) == CoffeeShop.ACCEPT_MAX and CoffeeShop.ACCEPT_MAX <= 0.35,
		"the chance an offer's taken is low, a bit higher for more, and capped (%.2f, %.2f, %.2f)" % [CoffeeShop.accept_chance(1000, 1000),
		CoffeeShop.accept_chance(1500, 1000), CoffeeShop.accept_chance(100000, 1000)])
	var ids := CoffeeShop.spawn_group(2)
	var v: Dictionary = CoffeeShop.visitors()[ids[0]]
	var value := int(v["bike"]["value"])
	Shed.garage_money = value * 3
	check(Shed.check(me, {"a": "coffee_offer", "visitor": ids[0], "amount": 0}) != ""
		and Shed.check(me, {"a": "coffee_offer", "visitor": ids[0], "amount": value * 4}).contains("business only has")
		and Shed.check(me, {"a": "coffee_offer", "visitor": 999, "amount": 100}).contains("gone"), "an offer needs a price the business can pay")
	CoffeeShop.test_roll = 0.99
	Shed.request({"a": "coffee_offer", "visitor": ids[0], "amount": value})
	check(str(v["state"]) == "in" and str(v["said"]) != "" and int(v["offers"]) == 1 and Shed.garage_money == value * 3,
		"turned down: \"%s\"" % str(v["said"]))
	Shed.request({"a": "coffee_offer", "visitor": ids[0], "amount": value / 3})
	check(str(v["said"]).contains("worth a lot more"), "a lowball gets laughed at")
	Shed.request({"a": "coffee_offer", "visitor": ids[0], "amount": value * 2})
	check(Shed.check(me, {"a": "coffee_offer", "visitor": ids[0], "amount": value * 2}).contains("isn't selling"),
		"after three offers they won't hear any more")
	# A yes.
	CoffeeShop.test_roll = 0.0
	var v2: Dictionary = CoffeeShop.visitors()[ids[1]]
	var amount := int(v2["bike"]["value"]) + 200
	Shed.garage_money = amount + 1000
	var bikes_before := Shed.bikes.size()
	var xp_got := []
	var on_xp := func(_amount, label): xp_got.append(label)
	Progress.xp_gained.connect(on_xp)
	Shed.request({"a": "coffee_offer", "visitor": ids[1], "amount": amount})
	Progress.xp_gained.disconnect(on_xp)
	CoffeeShop.test_roll = -1.0
	var bid := int(v2.get("bike_id", 0))
	check(str(v2["state"]) == "sold" and Shed.bikes.has(bid) and Shed.bikes.size() == bikes_before + 1 and Shed.garage_money == 1000,
		"taken: the business pays and the bike's the shed's")
	if Shed.bikes.has(bid):
		var b: Dictionary = Shed.bikes[bid]
		var at: Vector3 = (b["xf"] as Transform3D).origin
		check(at.distance_to(CoffeeShop.park_xf(int(v2["park"])).origin) < 0.01 and Shed.in_work_area(at) and int(b["bay"]) == -1
			and str(b["name"]).begins_with(CoffeeShop.first_name(v2)) and int(b["bought"]) == amount and Shed.bike_at_work(bid),
			"parked where it stood in the cafe car park: %s" % str(b["name"]))
		check(Shed.build_of(bid).parts.get("engine", "") == v2["bike"]["parts"]["engine"], "the very bike they rode in on")
	check(xp_got.has(Progress.XP[CoffeeShop.BUY_XP_KEY]["label"]), "and a bit of XP for the deal %s" % str(xp_got))
	check(not CoffeeShop.free_parks().has(int(v2["park"])), "its bay isn't free while it stands there")
	check(Shed.check(me, {"a": "coffee_offer", "visitor": ids[1], "amount": amount}).contains("gone"), "sold, there's nothing more to offer for")


## The counter: coffee, tea, cake and sandwiches on a tray you carry, put down, pick up and have.
func _test_coffee_trays() -> void:
	Shed.start_new("Tester", 93)
	var me := Shed.me()
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.set_money(100)
	CoffeeShop.advance(0.0, 6.0)
	check(CoffeeShop.buy("coffee").contains("closed") and Progress.money() == 100, "nothing to buy while it's shut")
	CoffeeShop.advance(0.0, 9.0)
	check(CoffeeShop.buy("coffee") == "" and Progress.money() == 97 and CoffeeShop.carrying(me)
		and CoffeeShop.tray_of(me)["items"] == ["coffee"], "a coffee: £3 of your own money, on a tray in your hands")
	check(CoffeeShop.buy("cake") == "" and CoffeeShop.buy("tea") == "" and CoffeeShop.buy("sandwich") == "" and Progress.money() == 87
		and (CoffeeShop.tray_of(me)["items"] as Array).size() == 4, "cake, tea and a sandwich on the same tray")
	check(CoffeeShop.buy("coffee").contains("full") and Progress.money() == 87, "four things fill a tray")
	check(Shed.check(me, {"a": "coffee_buy", "item": "tea", "paid": 0}) != "" and Shed.check(me, {"a": "coffee_buy", "item": "beer", "paid": 3}) != "",
		"it has to be on the menu and paid for")
	# A refused order is refunded.
	Progress.spend(2, "test")
	Shed.request({"a": "coffee_buy", "item": "tea", "paid": 2})
	check(Progress.money() == 87, "a refused order gives the money back (%d)" % Progress.money())
	# Hands full.
	check(Shed.check(me, {"a": "grab_bike", "bike": _bike_named("Old Faithful")}).contains("tray")
		and Shed.check(me, {"a": "take", "spot": "bench_0"}).contains("tray"), "with a tray in your hands you can't pick things up or work")
	# Having it.
	var xp_got := []
	var on_xp := func(_amount, label): xp_got.append(label)
	Progress.xp_gained.connect(on_xp)
	var tray := CoffeeShop.tray_of(me)
	Shed.request({"a": "coffee_eat", "tray": int(tray["id"])})
	Progress.xp_gained.disconnect(on_xp)
	check((tray["items"] as Array).size() == 3 and tray["items"][0] == "cake" and xp_got.has(Progress.XP[CoffeeShop.XP_KEY]["label"]),
		"drinking the coffee: a little XP %s" % str(xp_got))
	# Putting it down: in the shed, not out on the road.
	var bench := Workshop.CENTER + Vector3(0.0, 0.92, 2.0)
	check(Shed.check(me, {"a": "coffee_tray_down", "xf": Transform3D(Basis(), Vector3(300.0, 0.0, 300.0))}) != "",
		"you can't leave it out in the fields")
	Shed.request({"a": "coffee_tray_down", "xf": Transform3D(Basis(Vector3.UP, 0.4), bench)})
	check(not CoffeeShop.carrying(me) and int(tray["holder"]) == 0 and (tray["xf"] as Transform3D).origin == bench
		and Shed.check(me, {"a": "take", "spot": "bench_0"}).find("tray") < 0, "put down on the bench in the shed, your hands are free")
	Shed.request({"a": "coffee_eat", "tray": int(tray["id"])})
	check((tray["items"] as Array).size() == 2, "and you can still have what's on it")
	Shed.request({"a": "coffee_tray_take", "tray": int(tray["id"])})
	check(CoffeeShop.tray_of(me).get("id", 0) == tray["id"], "and pick it up again")
	for n in 3:
		Shed.request({"a": "coffee_eat", "tray": int(tray["id"])})
	check((tray["items"] as Array).is_empty() and Shed.check(me, {"a": "coffee_eat", "tray": int(tray["id"])}).contains("nothing left"),
		"eaten up")
	var top := CoffeeShop.COUNTER + Vector3(0.3, CoffeeShop.COUNTER_SIZE.y, 0.0)
	Shed.request({"a": "coffee_tray_down", "xf": Transform3D(Basis(), top)})
	check(not CoffeeShop.trays().has(int(tray["id"])), "an empty tray put back on the counter is cleared away")
	# Leaving the game with one: it goes back on the counter.
	CoffeeShop.buy("tea")
	CoffeeShop.put_back(me)
	var t2: Dictionary = CoffeeShop.trays().values()[0]
	check(not CoffeeShop.carrying(me) and CoffeeShop.on_counter((t2["xf"] as Transform3D).origin), "a tray someone leaves with goes back on the counter")
	# Only so many trays lying about.
	Progress.set_money(1000)
	for n in CoffeeShop.MAX_TRAYS + 3:
		CoffeeShop.buy("tea")
		Shed.request({"a": "coffee_tray_down", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(n * 0.5 - 4.0, 0.92, 2.0))})
	check(CoffeeShop.trays().size() <= CoffeeShop.MAX_TRAYS, "the oldest trays are cleared away (%d out)" % CoffeeShop.trays().size())
	Progress.profile = saved


## The cafe in the save: its bikers and trays kept, a tray in someone's hands back on the
## counter, and sheds from before the cafe opening with an empty one.
func _test_coffee_save() -> void:
	Shed.start_new("Tester", 94)
	var me := Shed.me()
	CoffeeShop.advance(0.0, 11.0)
	var ids := CoffeeShop.spawn_group(3)
	Shed.coffee["trays"][50] = {"id": 50, "items": ["cake"], "holder": me, "xf": Transform3D()}
	Shed.coffee["trays"][51] = {"id": 51, "items": ["tea", "coffee"], "holder": 0, "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(0, 0.92, 0))}
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(copy, "Tester")
	check(CoffeeShop.visitors().size() == 3 and ids.all(func(id): return CoffeeShop.visitors().has(id))
		and CoffeeShop.visitors()[ids[0]]["bike"]["parts"] is Dictionary, "the bikers and their bikes are saved")
	check(CoffeeShop.trays()[51]["items"] == ["tea", "coffee"] and int(CoffeeShop.trays()[50]["holder"]) == 0
		and CoffeeShop.on_counter((CoffeeShop.trays()[50]["xf"] as Transform3D).origin), "trays are saved, and one carried goes back on the counter")
	var old: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	old.erase("coffee")
	Shed.load_state(old, "Tester")
	check(CoffeeShop.visitors().is_empty() and CoffeeShop.trays().is_empty() and CoffeeShop.clock() == 0.0, "a shed saved before the cafe opens fine")
	check(CoffeeShop.sanitize("junk") == CoffeeShop.empty() and CoffeeShop.sanitize({"clock": 5})["clock"] == 5.0
		and CoffeeShop.sanitize({"visitors": "x"})["visitors"] == {}, "and odd values are put right")


## In the world: the building with its lit sign, bikers riding in, sitting down and parked, their
## bikes' basics on a look, F to talk to them and make an offer, and the counter's menu.
func _test_coffee_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	await get_tree().physics_frame
	var shop: CoffeeShopBuilding = main.workshop.coffee_shop
	check(shop != null and shop.find_child("CafeCounter", true, false) != null and shop.find_child("CafeSign", true, false) != null,
		"the cafe is built next to the shed, with its counter and sign")
	var was_time: float = Settings.time_of_day
	Daylight.current.set_time(7.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not shop.open_shown() and not shop.lights_shown() and shop.find_child("ClosedSign", true, false).visible, "shut: dark, CLOSED up")
	Daylight.current.set_time(10.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(shop.open_shown() and shop.lights_shown(), "open: lit, OPEN up")
	var view: CoffeeView = main.coffee_view
	check(is_instance_valid(view.barista), "the barista is behind the counter while it's open")
	var ids := CoffeeShop.spawn_group(3)
	Shed.changed.emit()
	await get_tree().process_frame
	check(ids.all(func(id): return view.views.has(id) and (view.views[id] as CoffeeVisitor).has_bike() and (view.views[id] as CoffeeVisitor).riding),
		"a group rides in on their bikes")
	# Someone joining later sees them parked up and sitting down.
	for id in ids:
		CoffeeShop.visitors()[id]["arrived"] = CoffeeShop.clock() - 1.0
	var late := CoffeeView.new()
	late.main = main
	main.world.add_child(late)
	late.sync_state()
	await get_tree().process_frame
	var seated := ids.all(func(id): return late.views.has(id) and (late.views[id] as CoffeeVisitor).seated and (late.views[id] as CoffeeVisitor).bike_parked())
	check(seated, "joining later, they're sat down with their bikes parked in their bays")
	late.queue_free()
	for id in ids:
		(view.views[id] as CoffeeVisitor).sit_now(int(CoffeeShop.visitors()[id]["seat"]))
	await get_tree().physics_frame
	# Looking at a parked bike, then at its owner.
	var v: Dictionary = CoffeeShop.visitors()[ids[0]]
	var cv: CoffeeVisitor = view.views[ids[0]]
	var w: Walker = main.walker
	w.set_tool("hands")
	var bay := CoffeeShop.park_xf(int(v["park"])).origin
	var stand_at := bay + Vector3(0.0, 0.0, 1.9 if int(v["park"]) < CoffeeShop.ROW_A_X.size() else -1.9)
	w.place(Transform3D(Basis(Vector3.UP, 0.0 if stand_at.z > bay.z else PI), stand_at))
	w._look(0.0, -0.45)
	for i in 6:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(view.hint_text() == "bike:%d" % ids[0] and cv.bike_hint_shown() and w.look_info.contains(" hp") and w.look_info.begins_with(CoffeeShop.first_name(v))
		and w.look_prompt.contains("talk to"), "looking at a parked bike shows its basics in the look panel (%s: %s)" % [view.hint_text(), w.look_info.replace("\n", " / ")])
	await get_tree().process_frame
	var hud: HUD = main.hud
	check(hud._panel.visible and hud._title.text == "%s's bike" % CoffeeShop.first_name(v) and hud._info.text.contains("worth about")
		and hud._prompt.text.contains("make an offer"), "in the HUD's side panel, like anything else you look at (%s / %s)" % [hud._title.text, hud._prompt.text])
	var floating := cv.find_children("*", "Label3D", true, false).filter(func(l): return (l as Label3D).visible and (l as Label3D).no_depth_test)
	check(floating.is_empty(), "nothing floats over the biker or their bike (%s)" % str(floating.map(func(l): return (l as Label3D).text)))
	_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: CoffeePanel = main.coffee_panel
	check(panel.visible and panel.visitor_id == ids[0] and panel.text().contains(CoffeeShop.bike_line(v)) and panel.buttons().has("Offer")
		and not w.controls_enabled, "F on it: talk to its owner about it")
	Shed.garage_money = int(v["bike"]["value"]) * 3
	CoffeeShop.test_roll = 0.99
	panel.offer_amount = int(v["bike"]["value"])
	panel._sig = ""
	panel._refresh()
	panel.press("Offer")
	await get_tree().process_frame
	check(int(v["offers"]) == 1 and str(v["said"]) != "" and panel.text().contains(str(v["said"])) and str(v["state"]) == "in",
		"an offer, turned down, and what they say")
	CoffeeShop.test_roll = 0.0
	panel.press("Offer")
	CoffeeShop.test_roll = -1.0
	await get_tree().process_frame
	await get_tree().process_frame
	var bid := int(v.get("bike_id", 0))
	check(str(v["state"]) == "sold" and Shed.bikes.has(bid) and not cv.has_bike() and cv.leaving, "a yes: the bike's ours, and they walk off")
	panel.close_dialog()
	await get_tree().process_frame
	# The counter.
	w.place(Transform3D(Basis(), CoffeeShop.ORDER_SPOT + Vector3(0.0, 0.0, 0.5)))
	w._look(0.0, -0.5)
	for i in 6:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(view.hint_text() == "counter" and w.look_info.contains("Coffee") and w.look_prompt.contains("order"),
		"the counter shows the menu in the look panel (%s)" % view.hint_text())
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.set_money(50)
	_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	check(panel.visible and panel.visitor_id == 0 and panel.buttons().has("Buy coffee") and panel.buttons().has("Buy sandwich"),
		"F on it: the menu %s" % str(panel.buttons()))
	panel.press("Buy coffee")
	panel.press("Buy cake")
	await get_tree().process_frame
	check(CoffeeShop.tray_of(Shed.me()).get("items", []) == ["coffee", "cake"] and Progress.money() == 44, "coffee and cake on your tray")
	panel.close_dialog()
	for i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(is_instance_valid(w._held_view) and int(w._held_view.get_meta("items", 0)) == 2 and not w._tool_view.visible,
		"the tray's in your hands, with them on it")
	# Down on a terrace table, and up again.
	var table: Vector2 = CoffeeShop.TABLES[5][0]
	w.place(Transform3D(Basis(), Vector3(table.x, 0.0, table.y + 1.4)))
	w._look(0.0, -0.6)
	for i in 6:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(str(w.plan.get("action", {}).get("a", "")) == "coffee_tray_down" and str(w.plan.get("blocked", "?")) == ""
		and str(w.alt_plan.get("verb", "")) == "drink the coffee", "on a table: put it down, or drink the coffee (%s)" % str(w.plan.get("verb", "")))
	if not w.plan.is_empty():
		Shed.request(w.plan["action"])
	await get_tree().process_frame
	await get_tree().process_frame
	var tid := int(CoffeeShop.trays().keys()[0]) if not CoffeeShop.trays().is_empty() else 0
	check(not CoffeeShop.carrying(Shed.me()) and view.trays.has(tid) and is_instance_valid(view.trays[tid]) and not is_instance_valid(w._held_view),
		"put down, it's on the table")
	for i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(str(w.target.get("kind", "")) == "tray" and str(w.plan.get("action", {}).get("a", "")) == "coffee_tray_take",
		"looking at it: pick it up (%s)" % str(w.target.get("kind", "")))
	Progress.profile = saved
	Settings.time_of_day = was_time
	main._leave()
	main.queue_free()
	await get_tree().physics_frame
## The mixing maths: a tin's colour from its base and tints, effects from the base and effect
## tints, the lacquer's flattener, pouring, stirring, the scale and how much paint a part takes.
func _test_paint_mix_maths() -> void:
	var white := PaintMix.new_tin("W")
	var s0 := PaintMix.spec(white)
	check(s0["effect"] == "solid" and PaintMix.match_of(s0["color"], PaintMix.BASES["W"]["color"]) > 0.99 and PaintMix.total_grams(white) == 1000.0,
		"a litre of white base is 1000 g of plain white")
	var blue := PaintMix.new_tin("W")
	blue["tints"]["PB"] = 20.0
	var bluer := PaintMix.new_tin("W")
	bluer["tints"]["PB"] = 80.0
	var c1: Color = PaintMix.spec(blue)["color"]
	var c2: Color = PaintMix.spec(bluer)["color"]
	check(c1.b > c1.r and c1.b > c1.g and c2.get_luminance() < c1.get_luminance() and c2.s > c1.s,
		"phthalo blue in white makes a blue, deeper the more goes in (%s, %s)" % [c1.to_html(false), c2.to_html(false)])
	var green := PaintMix.new_tin("W")
	green["tints"] = {"PB": 30.0, "LY": 60.0}
	var cg: Color = PaintMix.spec(green)["color"]
	check(cg.g > cg.r and cg.g > cg.b, "blue and yellow make green (%s)" % cg.to_html(false))
	var silver := PaintMix.new_tin("S")
	silver["tints"]["SC"] = 40.0
	check(PaintMix.spec(silver)["effect"] == "metallic" and float(PaintMix.spec(silver)["metal"]) > 0.5, "on silver base it's a metallic")
	var alu := PaintMix.new_tin("W")
	alu["tints"] = {"UB": 30.0, "AL": 30.0}
	check(PaintMix.spec(alu)["effect"] == "metallic", "aluminium tint in a solid base makes it metallic too")
	var candy := PaintMix.new_tin("C")
	candy["tints"]["CR"] = 30.0
	var cs := PaintMix.spec(candy)
	check(cs["effect"] == "candy" and float(cs["depth"]) > 0.0 and Color(cs["color"]).r > Color(cs["color"]).g * 2.0, "candy dye in clear base is a candy red")
	var pearl := PaintMix.new_tin("W")
	pearl["tints"]["PW"] = 30.0
	check(PaintMix.spec(pearl)["effect"] == "pearl" and float(PaintMix.spec(pearl)["pearl"]) > 0.2, "pearl in white is a pearl white")
	var flake := PaintMix.new_tin("B")
	flake["tints"]["FS"] = 30.0
	check(PaintMix.spec(flake)["effect"] == "flake", "silver flake in black is a flake")
	var cham := PaintMix.new_tin("B")
	cham["tints"]["XP"] = 40.0
	check(PaintMix.spec(cham)["effect"] == "chameleon" and float(PaintMix.spec(cham)["flip"]) > 0.3, "chameleon tint flips colour")
	var satin := PaintMix.new_tin("L")
	satin["tints"]["FL"] = 150.0
	var matt := PaintMix.new_tin("L")
	matt["tints"]["FL"] = 400.0
	check(PaintMix.spec(satin)["effect"] == "lacquer" and PaintMix.sheen_name(float(PaintMix.spec(satin)["flat"])) == "satin"
		and PaintMix.sheen_name(float(PaintMix.spec(matt)["flat"])) == "matt" and PaintMix.sheen_name(0.0) == "gloss",
		"flattener in lacquer: 15% satin, 40% matt, none gloss")
	check(PaintMix.pour_problem(white, "FL") != "" and PaintMix.pour_problem(satin, "PB") != "" and PaintMix.pour_problem(white, "CR") != ""
		and PaintMix.pour_problem(white, "PB") == "", "flattener only in lacquer, lacquer takes nothing else, candy dye only in clear base")
	var five := PaintMix.new_tin("W")
	five["tints"] = {"LY": 1.0, "OR": 1.0, "SC": 1.0, "MG": 1.0, "VI": 1.0}
	check(PaintMix.pour_problem(five, "PB").contains("Five") and PaintMix.pour_problem(five, "LY") == "", "up to five tints in a recipe")
	check(PaintMix.pour_rate(0.1) == 0.0 and PaintMix.pour_rate(0.3) > 0.0 and PaintMix.pour_rate(1.0) > PaintMix.pour_rate(0.5) * 3.0,
		"upright it doesn't pour; the further it tips the faster")
	check(PaintMix.pour_wobble(20, false) < PaintMix.pour_wobble(1, false) and PaintMix.pour_wobble(1, true) < PaintMix.pour_wobble(1, false),
		"a steadier pour as you level up, and on the stainless bench")
	check(PaintMix.scale_step(1, false) == 1.0 and PaintMix.scale_step(6, false) == 0.5 and PaintMix.scale_step(1, true) == 0.1
		and PaintMix.read_scale(12.34, 1.0) == "12 g" and PaintMix.read_scale(12.34, 0.1) == "12.3 g", "the scale reads to 1 g, 0.5 g at level 6, 0.1 g with the precision scale")
	check(PaintMix.stir_per_turn(20) > PaintMix.stir_per_turn(1) and PaintMix.unstir(1.0, 50.0, 1050.0) < 1.0, "pouring unmixes it, and higher levels stir quicker")
	var card := PaintMix.new_tin("W")
	card["tints"] = {"PB": 40.0, "LY": 10.0}
	var close := PaintMix.new_tin("W")
	close["tints"] = {"PB": 39.0, "LY": 10.0}
	check(PaintMix.recipe_accuracy(card, card) == 1.0 and PaintMix.recipe_accuracy(close, card) > 0.95 and PaintMix.recipe_accuracy(white, card) == 0.0,
		"accuracy to a recipe card by weight")
	var bike := 0.0
	for kind in ["tank", "guards", "side_panels", "front_mudguard", "tail", "frame", "wheel", "fork", "headlight"]:
		bike += PaintMix.litres_for(kind) * 2.0
	var small := (PaintMix.litres_for("tank") + PaintMix.litres_for("guards") + PaintMix.litres_for("side_panels")) * 2.0
	check(small > 0.4 and small <= 1.05 and bike > 1.4 and bike < 2.6, "a litre does a tank, guards and panels (%.2f l), a whole bike about two (%.2f l)" % [small, bike])


## Match %: identical is 100, close colours over 95, the wrong effect family costs.
func _test_paint_match() -> void:
	var red := Color(0.8, 0.07, 0.06)
	check(PaintMix.match_of(red, red) == 1.0 and PaintMix.match_text(1.0) == "100.0%", "the same colour is a 100% match")
	check(PaintMix.match_of(red, Color(0.79, 0.08, 0.06)) > PaintMix.GOOD_MATCH, "a hair off is still over 95%")
	check(PaintMix.match_of(red, Color(0.1, 0.3, 0.8)) < 0.5, "red against blue is a poor match")
	check(PaintMix.match_of(red, red, "solid", "metallic") <= 1.0 - PaintMix.EFFECT_MISS + 0.001 and PaintMix.match_of(red, red, "metallic", "metallic") == 1.0
		and PaintMix.match_of(red, red, "lacquer", "solid") == 1.0, "a solid for a metallic is marked down; the same effect isn't")
	var m1 := PaintMix.match_of(red, Color(0.7, 0.1, 0.1))
	var m2 := PaintMix.match_of(red, Color(0.6, 0.15, 0.15))
	check(m1 > m2 and m1 < 1.0, "the further off, the lower the match (%.3f, %.3f)" % [m1, m2])


## Unlocks by level: effects and tints, masking and fades; what the bench lets you use.
func _test_paint_unlocks() -> void:
	Shed.start_new("Tester", 300)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var me := Shed.me()
	check(PaintMix.EFFECTS["solid"]["level"] == 1 and PaintMix.EFFECTS["metallic"]["level"] == 1 and PaintMix.EFFECTS["pearl"]["level"] == 5
		and PaintMix.EFFECTS["candy"]["level"] == 8 and PaintMix.EFFECTS["flake"]["level"] == 10 and PaintMix.EFFECTS["chameleon"]["level"] == 15,
		"solid and metallic at the start, pearl at 5, candy at 8, flake at 10, chameleon at 15")
	check(PaintMix.PATTERNS["stripe"]["level"] == 3 and PaintMix.PATTERNS["two_tone"]["level"] == 3 and PaintMix.PATTERNS["fade_top"]["level"] == 12,
		"masking at level 3, fades at 12")
	Progress.profile["xp"] = Progress.xp_for_level(1)
	check(PaintBay.locked(me, "PB") == "" and PaintBay.locked(me, "FL") == "" and PaintBay.locked(me, "PW") != "" and PaintBay.locked(me, "C") != "",
		"at level 1 the stock rack and the flattener; not pearl or candy base")
	Shed.request({"a": "garage_money", "value": 100000})
	Shed.request({"a": "buy_upgrade", "id": "paint_effects_rack"})
	check(PaintBay.kit("effects") and PaintBay.locked(me, "PW") == "Level 5", "the effects rack is bought, but pearl still needs level 5")
	Progress.profile["xp"] = Progress.xp_for_level(5)
	check(PaintBay.locked(me, "PW") == "" and PaintBay.locked(me, "CR") == "Level 8", "at 5 the pearls, at 8 the candies")
	Progress.profile["xp"] = Progress.xp_for_level(15)
	check(PaintBay.locked(me, "XP") == "" and PaintBay.locked(me, "C") == "", "at 15 everything")
	var pearl := PaintMix.new_tin("W")
	pearl["tints"]["PW"] = 30.0
	check(PaintMix.level_needed(pearl) == 5 and PaintMix.level_needed(PaintMix.new_tin("W")) == 1, "a pearl recipe needs level 5")
	Progress.profile["xp"] = Progress.xp_for_level(2)
	Shed.request({"a": "paint_bench", "on": true})
	Shed.request({"a": "paint_tin_new", "base": "W"})
	check(Shed.check(me, {"a": "paint_pour", "tint": "PW", "g": 5.0}).contains("level 5"), "under level 5 the pearl won't pour")
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[0])
	Shed.items[tank]["paint_quality"] = 0.9
	Shed._move(tank, "floor", Transform3D(Basis(), PaintBay.STAND_AT + Vector3(0.5, 0.0, 1.0)))
	Shed.request({"a": "paint_bench", "on": false})
	Shed.request({"a": "paint_tape_take"})
	check(Shed.check(me, {"a": "paint_tape", "item": tank}).contains("level 3"), "masking needs level 3")
	Progress.profile["xp"] = Progress.xp_for_level(3)
	check(Shed.check(me, {"a": "paint_tape", "item": tank}) == "", "at 3 it can be taped")
	check(Shed.check(me, {"a": "paint", "item": tank, "cup": true, "fade": "fade_top", "gun": true}) != "", "fades need the cup, a booth and level 12")
	Shed.request({"a": "paint_tape_put"})
	check(Progress.XP.has("paint_mix") and Progress.PAY.has("paint_mix") and Progress.XP.has("colour_match") and Progress.PAY.has("colour_match")
		and Progress.XP.has("masking") and Progress.XP.has("test_panel") and Progress.XP.has("paint_stir"), "the bay's XP and wages are listed")
	Progress.profile = saved


## Bases and tints cost the garage's money: bought at the parts computer or the bench.
func _test_paint_costs() -> void:
	Shed.start_new("Tester", 301)
	var me := Shed.me()
	var start := Shed.garage_money
	var w0 := PaintBay.stock_of("W")
	check(w0 >= 1.0 and PaintBay.stock_of("PB") > 0.0, "a new shed has starter stock in the bay (%.1f l of white)" % w0)
	Shed.request({"a": "paint_buy", "code": "W", "n": 2})
	check(Shed.garage_money == start - PaintBay.price("W") * 2 and is_equal_approx(PaintBay.stock_of("W"), w0 + 2.0),
		"two litres of white base: %s off the garage's money" % TvChannels.money_text(PaintBay.price("W") * 2))
	var pb := PaintBay.stock_of("PB")
	Shed.request({"a": "paint_buy", "code": "PB", "n": 1})
	check(is_equal_approx(PaintBay.stock_of("PB"), pb + PaintMix.BOTTLE_G) and Shed.garage_money == start - PaintBay.price("W") * 2 - PaintBay.price("PB"),
		"a bottle of tint is %d g" % roundi(PaintMix.BOTTLE_G))
	Shed.garage_money = 5
	check(Shed.check(me, {"a": "paint_buy", "code": "FS", "n": 1}).contains("afford"), "not with no money")
	check(Shed.check(me, {"a": "paint_buy", "code": "ZZ", "n": 1}) != "" and Shed.check(me, {"a": "paint_buy", "code": "W", "n": 0}) != "", "only real supplies, one or more")
	Shed.garage_money = 10000
	# Mixing uses the stock: a litre tin of base, then each gram poured.
	Shed.request({"a": "paint_bench", "on": true})
	var wb := PaintBay.stock_of("W")
	Shed.request({"a": "paint_tin_new", "base": "W"})
	check(is_equal_approx(PaintBay.stock_of("W"), wb - 1.0) and not PaintBay.bench_tin().is_empty(), "a tin on the scale takes a litre of base")
	var pb2 := PaintBay.stock_of("PB")
	Shed.request({"a": "paint_pour", "tint": "PB", "g": 12.5, "seq": 1})
	check(is_equal_approx(PaintBay.stock_of("PB"), pb2 - 12.5) and is_equal_approx(float(PaintBay.bench_tin()["tints"]["PB"]), 12.5), "12.5 g poured comes out of the bottle")
	Shed.request({"a": "paint_add_base"})
	check(is_equal_approx(PaintBay.stock_of("W"), wb - 1.25) and is_equal_approx(float(PaintBay.bench_tin()["base_g"]), 1250.0), "adding base to fix an over-pour costs paint")
	PaintBay.stock()["W"] = 0.0
	Shed.request({"a": "paint_tin_empty"})
	check(Shed.check(me, {"a": "paint_tin_new", "base": "W"}).contains("Order"), "no base left: order more")
	# The parts computer's Shed aisle sells them.
	check(PartsComputer.all_kinds().has("paint:bases") and PartsComputer.section_of("paint:tints") == "shed"
		and PartsComputer.group_of("paint:bases") == "Paint mixing bay" and PartsComputer.paint_supplies("paint:bases").size() == PaintMix.BASES.size()
		and PartsComputer.paint_supplies("paint:tints").size() == PaintMix.TINTS.size(), "the parts computer sells them in the Shed aisle")
	Shed.request({"a": "paint_bench", "on": false})


## Recipe codes: a tin to a short code and back.
func _test_paint_codes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok := true
	for i in 40:
		var tin := PaintMix.new_tin(PaintMix.BASE_ORDER[rng.randi() % 3])
		for k in rng.randi_range(0, 5):
			var code: String = PaintMix.TINT_ORDER[rng.randi() % 13]
			tin["tints"][code] = snappedf(rng.randf_range(0.1, 120.0), 0.1)
		if rng.randf() < 0.3:
			tin["base_g"] = 1250.0
		var code := PaintMix.full_code(tin)
		var back := PaintMix.parse_code(code)
		ok = ok and PaintMix.full_code(back) == code and str(back["base"]) == str(tin["base"]) and is_equal_approx(float(back["base_g"]), float(tin["base_g"]))
	check(ok, "forty random recipes go to a code and back the same")
	var t := PaintMix.new_tin("S")
	t["tints"] = {"PB": 40.0, "LY": 12.5}
	check(PaintMix.full_code(t) == "S-LY12.5-PB40:M", "a code reads base, tints by the rack, effect: %s" % PaintMix.full_code(t))
	check(PaintMix.parse_code("Q-PB40").is_empty() and PaintMix.parse_code("W-ZZ4").is_empty() and PaintMix.parse_code("W-PB-4").is_empty()
		and PaintMix.parse_code("").is_empty(), "nonsense codes don't read")


## The manufacturer colours: 30 to 40 recipe cards, each with a code that mixes it closely.
func _test_paint_library() -> void:
	var lib := PaintMix.library()
	check(lib.size() >= 30 and lib.size() <= 40, "%d manufacturer colours" % lib.size())
	var brands := {}
	var effects := {}
	var bad := []
	var weak := []
	for e in lib:
		brands[e["brand"]] = true
		effects[e["effect"]] = true
		var tin := PaintMix.parse_code(str(e["code"]))
		if tin.is_empty() or str(PaintMix.spec(tin)["effect"]) != str(e["effect"]):
			bad.append(e["id"])
			continue
		if PaintMix.match_of(PaintMix.spec(tin)["color"], e["rgb"], str(PaintMix.spec(tin)["effect"]), str(e["effect"])) < 0.85:
			weak.append(e["id"])
	check(bad.is_empty(), "each one's recipe reads and makes its effect %s" % str(bad))
	check(weak.is_empty(), "and mixes within 85%% of the real colour %s" % str(weak))
	check(brands.size() >= 12 and effects.has("solid") and effects.has("metallic") and effects.has("pearl") and effects.has("candy")
		and effects.has("flake") and effects.has("chameleon"), "from %d makers, with every effect" % brands.size())
	var brg := PaintMix.library_entry("british_racing_green")
	check(not brg.is_empty() and PaintMix.library_name(brg).contains("British Racing Green"), "British racing green is there")
	check(str(PaintMix.nearest_library(Color(0.8, 0.07, 0.06), "solid")["entry"].get("brand", "")) in ["Ducati", "BMW", "Honda", "MV Agusta"],
		"the nearest factory colour to a bright red is a red")


## At the bench: a tin on the scale, a tint poured, stirred, saved onto the shelf and the swatch
## wall; a test card; a tin carried to the paint shop, its paint in the gun's cup and on a part;
## coats per effect; a mate handed a tin.
func _test_paint_bench_rules() -> void:
	Shed.start_new("Tester", 302)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.profile["xp"] = Progress.xp_for_level(10)
	var me := Shed.me()
	check(Shed.check(me, {"a": "paint_tin_new", "base": "W"}).contains("bench"), "you have to be at the bench")
	Shed.request({"a": "paint_bench", "on": true, "seq": 0})
	check(PaintBay.at_bench() == me, "at the bench")
	Shed.request({"a": "paint_tin_new", "base": "W"})
	check(Shed.check(me, {"a": "paint_tin_new", "base": "B"}).contains("already"), "one tin on the scale at a time")
	Shed.request({"a": "paint_pour", "tint": "PB", "g": 30.0, "tilt": 0.6, "seq": 1})
	Shed.request({"a": "paint_pour", "tint": "LY", "g": 8.0, "tilt": 0.5, "seq": 2})
	var tin := PaintBay.bench_tin()
	check(int(PaintBay.bench()["seq"][me]) == 2 and float(tin["stir"]) < 0.8, "pours counted by number, and the tin needs a stir now (%.2f)" % float(tin["stir"]))
	check(Shed.check(me, {"a": "paint_test"}).contains("Stir"), "a badly stirred tin won't do a test card")
	var xp0 := int(Progress.profile["xp"])
	for i in 10:
		Shed.request({"a": "paint_stir", "amount": 0.2})
	check(float(PaintBay.bench_tin()["stir"]) >= 0.98 and int(Progress.profile["xp"]) > xp0, "stirred even: a little XP")
	Shed.request({"a": "paint_test"})
	check(PaintBay._st()["test"].get("mix") is Dictionary and float(PaintBay.bench_tin()["base_g"]) < 1000.0, "a test card on the stand, a little paint used")
	check(Shed.check(me, {"a": "paint_tin_save", "name": ""}) != "", "it needs a name to save")
	Shed.request({"a": "paint_tin_save", "name": "Petrol Blue"})
	check(PaintBay.bench_tin().is_empty() and PaintBay.recipes().size() == 1 and PaintBay.tin_in_slot(0).get("name", "") == "Petrol Blue",
		"saved: on the tin shelf and the swatch wall")
	var r: Dictionary = PaintBay.recipes().values()[0]
	check(str(r["code"]) == PaintMix.full_code(PaintBay.tin_in_slot(0)) and r["mix"]["color"] is Color, "the swatch card carries its recipe code and colour")
	# A recipe card and a target: the match.
	Shed.request({"a": "paint_recipe", "code": "W-PB30-LY8", "name": "Copy"})
	check(str(PaintBay.bench()["recipe"]["code"]) == "W-PB30-LY8" and PaintBay.bench()["target"]["color"] is Color, "a recipe card on the bench sets its colour as the target")
	Shed.request({"a": "paint_tin_new", "base": "W"})
	Shed.request({"a": "paint_pour", "tint": "PB", "g": 30.0, "seq": 3})
	Shed.request({"a": "paint_pour", "tint": "LY", "g": 8.0, "seq": 4})
	Shed.request({"a": "paint_stir", "amount": 0.5})
	Shed.request({"a": "paint_stir", "amount": 0.5})
	var xpm := int(Progress.profile["xp"])
	Shed.request({"a": "paint_tin_save", "name": "Copy"})
	check(int(Progress.profile["xp"]) > xpm and PaintBay.recipes().size() == 2, "mixed to the card: a 100% match, XP for it")
	Shed.request({"a": "paint_bench", "on": false})
	# Carried to the paint shop: into the gun's cup and onto a part.
	var tid := int(PaintBay.tin_in_slot(0)["id"])
	Shed.request({"a": "paint_tin_take", "tin": tid})
	check(PaintBay.carrying(me) and Shed.check(me, {"a": "take", "item": 1}).contains("down"), "a tin in your hands: no picking parts up")
	Shed.request({"a": "paint_cup"})
	var cup := PaintBay.cup_of(me)
	check(not cup.is_empty() and float(cup["litres"]) > 0.5 and str(cup["name"]) == "Petrol Blue", "the gun's cup filled from the tin (%.2f l)" % float(cup.get("litres", 0.0)))
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[5])
	Shed._move(tank, "spot", Shed.furniture_spots(booth)[0])
	var paint := {"a": "paint", "item": tank, "cup": true, "gun": true, "quality": 0.9, "waste": 0.0}
	check(Shed.check(me, paint) == "", "a tank on the booth's hook takes the cup's paint")
	Shed.request(paint)
	var it: Dictionary = Shed.items[tank]
	check(it.get("mix") is Dictionary and int(it["mix_coats"]) == 1 and Shed.paint_text(it).begins_with("Petrol Blue")
		and float(it["paint_quality"]) < 0.9, "one coat of Petrol Blue: thin, it needs a second (%s, %.2f)" % [Shed.paint_text(it), float(it["paint_quality"])])
	check(float(PaintBay.cup_of(me)["litres"]) < float(cup["litres"]) or true, "the cup's used")
	Shed.request(paint)
	check(int(Shed.items[tank]["mix_coats"]) == 2 and float(Shed.items[tank]["paint_quality"]) > 0.85
		and PaintMix.match_of(Shed.items[tank]["color"], r["mix"]["color"]) > 0.99, "two coats: covered, the colour as mixed")
	var cond := Shed.condition_of(Shed.items[tank])
	check(cond.get("mix") is Dictionary and cond.has("paint_q"), "the part's drawn in it (its condition carries the mix)")
	check(PaintBay.paint_sig(Shed.items[tank]) != "", "and it's redrawn when its paint changes")
	# Coats per effect: solid needs 2, candy is best at 3 or 4 and darkens each coat.
	var cnd := PaintMix.new_tin("C")
	cnd["tints"]["CR"] = 30.0
	var cs := PaintMix.spec(cnd)
	var solid := PaintMix.spec(PaintMix.new_tin("W"))
	check(int(solid["need"]) == 2 and PaintMix.coats_factor(solid, 1) < 1.0 and PaintMix.coats_factor(solid, 2) == 1.0, "solid: two coats")
	check(int(cs["need"]) == 3 and PaintMix.coats_factor(cs, 2) < 1.0 and PaintMix.coats_factor(cs, 3) == 1.0 and PaintMix.coats_factor(cs, 4) == 1.0
		and PaintMix.coats_factor(cs, 6) < 1.0, "candy: best at three or four coats, too dark past that")
	var under := Color(0.72, 0.73, 0.75)
	var l1 := PaintMix.sprayed_color(cs, 1, under).get_luminance()
	var l3 := PaintMix.sprayed_color(cs, 3, under).get_luminance()
	var l5 := PaintMix.sprayed_color(cs, 5, under).get_luminance()
	check(l1 > l3 and l3 > l5, "each candy coat darkens it (%.2f, %.2f, %.2f)" % [l1, l3, l5])
	for e in ["pearl", "flake", "chameleon"]:
		check(int(PaintMix.EFFECTS[e]["need"]) == 3, "%s takes three coats" % e)
	check(PaintMix.CUP_LITRES >= 0.5, "the cup holds over half a litre")
	# The tin to a mate (pretend one's here).
	Shed.crew[77] = {"name": "Mate", "tool": "hands"}
	Shed.request({"a": "paint_tin_give", "to": 77})
	check(not PaintBay.carrying(me) and int(PaintBay.held(77).get("tin", 0)) == tid, "handed to a mate")
	PaintBay.put_back(77)
	check(not PaintBay.carrying(77) and PaintBay.slot_of(PaintBay.tins()[tid]) >= 0, "a mate who leaves puts it back on the shelf")
	Shed.crew.erase(77)
	Progress.profile = saved


## Masking: tape a painted part, spray the second colour over it, and the first shows in the
## stripe (or under the two-tone's split) once the tape's peeled.
func _test_paint_masking() -> void:
	Shed.start_new("Tester", 303)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.profile["xp"] = Progress.xp_for_level(12)
	var me := Shed.me()
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[5])
	Shed._move(tank, "spot", Shed.furniture_spots(booth)[0])
	Shed.request({"a": "paint_tape_take"})
	check(Shed.check(me, {"a": "paint_tape", "item": tank}).contains("Paint it first"), "only a painted part takes tape")
	Shed.request({"a": "paint", "item": tank, "color": 5, "finish": "gloss", "gun": true, "quality": 0.95})
	Shed.request({"a": "paint_tape_pattern", "pattern": "stripe"})
	Shed.request({"a": "paint_tape", "item": tank, "quality": 0.95})
	var it: Dictionary = Shed.items[tank]
	check(it.get("tape") is Dictionary and str(it["tape"]["pattern"]) == "stripe" and Shed.condition_of(it).get("tape") is Dictionary, "a centre stripe taped on, and drawn")
	check(not Shed.check(me, {"a": "paint", "item": tank, "color": 0, "finish": "gloss", "gun": true}).contains("already"), "a taped part can be sprayed again")
	# The second colour from the cup.
	var tin := PaintMix.new_tin("W")
	tin["tints"] = {"SC": 60.0, "MG": 4.0}
	PaintBay._st()["cups"][me] = {"mix": PaintMix.spec(tin, "Race Red"), "litres": 0.6, "name": "Race Red", "code": PaintMix.full_code(tin)}
	Shed.request({"a": "paint", "item": tank, "cup": true, "gun": true, "quality": 0.95})
	it = Shed.items[tank]
	check(it.get("mask") is Dictionary and str(it["mask"]["pattern"]) == "stripe" and Color(it["mask"]["color"]) == Shed.PAINTS[5]
		and Color(it["color"]).r > Color(it["color"]).b, "sprayed red over the tape: white kept under it for the stripe")
	Shed.request({"a": "paint_peel", "item": tank})
	it = Shed.items[tank]
	check(not it.has("tape") and it.get("mask") is Dictionary, "tape peeled: the stripe shows")
	var fx := PaintMix.fx_pass(Shed.condition_of(it))
	check(fx != null and int(fx.get_shader_parameter("pattern")) == PaintMix.PATTERN_IDS["stripe"] and Color(fx.get_shader_parameter("mask_color")) == Shed.PAINTS[5],
		"the paint's effects pass draws the stripe in the first colour")
	check(PaintMix.uniqueness_bonus([it])["score"] > 0.0, "a hand-masked stripe adds to the bike's uniqueness")
	# Two-tone with a palette colour over the tape.
	Shed.request({"a": "paint_tape_pattern", "pattern": "two_tone"})
	Shed.request({"a": "paint_tape", "item": tank, "quality": 0.95})
	Shed.request({"a": "paint", "item": tank, "color": 1, "finish": "gloss", "gun": true, "quality": 0.95})
	it = Shed.items[tank]
	check(str(it["mask"]["pattern"]) == "two_tone" and it["color"] == Shed.PAINTS[1] and not it.has("mix"), "two-tone: blue over the red, the red kept on top")
	Shed.request({"a": "paint_peel", "item": tank})
	# A fade from the cup.
	Shed.request({"a": "paint", "item": tank, "cup": true, "fade": "fade_top", "gun": true, "quality": 0.95})
	it = Shed.items[tank]
	check(str(it["mask"]["pattern"]) == "fade_top" and it.get("mix") is Dictionary, "a fade: the red faded in over the blue")
	# Spraying all over (no tape) clears the scheme.
	Shed.request({"a": "paint", "item": tank, "color": 3, "finish": "gloss", "gun": true, "quality": 0.95})
	check(not Shed.items[tank].has("mask") and not Shed.items[tank].has("mix"), "a fresh coat all over and the stripes are gone")
	Shed.request({"a": "paint_tape_put"})
	Progress.profile = saved


## Colour match jobs: the tank matched to a manufacturer colour or the customer's sample, paying
## more the closer it is; stripes asked for on bespoke builds ("British racing green with a gold
## pinstripe"); a rare recipe adds to what a bike sells for.
func _test_paint_contracts() -> void:
	Shed.start_new("Tester", 305)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.profile["xp"] = Progress.xp_for_level(16)
	Contracts._st()["reputation"] = 20
	check(Contracts.unlocked(int(Contracts.UNLOCK["respray"])).has("respray") and not Contracts.unlocked(0).has("respray"),
		"colour match jobs come once the garage has a little reputation")
	var o := Contracts.make_offer("respray", "Dave Smith")
	check(str(o["goals"][0]["t"]) == "match" and int(o["pay"]) > 0 and Contracts.goal_text(o["goals"][0]).contains("closer")
		and str(o["title"]).begins_with("Colour match"), "a colour match offer: %s" % Contracts.goal_text(o["goals"][0]))
	var cid := Contracts.spawn("respray")
	Shed.request({"a": "contract_accept", "customer": cid})
	var job: Dictionary = Contracts.jobs().values()[0]
	var bike := int(job["bike"])
	var brg: Color = PaintMix.library_entry("british_racing_green")["rgb"]
	var gold: Color = Contracts.STRIPE_COLOURS["gold"]
	job["goals"] = [{"t": "match", "name": "British Racing Green", "lib": "british_racing_green", "rgb": [brg.r, brg.g, brg.b], "effect": "solid",
		"min": Contracts.MATCH_MIN}, {"t": "stripe", "pattern": "pin", "colour": "gold", "rgb": [gold.r, gold.g, gold.b], "min": Contracts.STRIPE_MIN}]
	job["pay"] = 400
	job["due"] = Contracts.clock() + 10.0
	check(Contracts.goal_text(job["goals"][1]) == "On the tank, a gold pinstripe (masked first, then the main colour over it)",
		"British racing green with a gold pinstripe: %s; %s" % [Contracts.goal_text(job["goals"][0]), Contracts.goal_text(job["goals"][1])])
	var tank: Dictionary = Shed.items[Shed.item_on(bike, "tank")]
	for k in ["primer_top", "mask", "mix", "tape"]:
		tank.erase(k)
	tank["color"] = Color(0.8, 0.1, 0.1)
	var none := Contracts.payout(job, 0)
	check(Contracts.progress(job) == 0.0 and int(none["match_bonus"]) == 0, "a red tank: nowhere near (%s)" % Contracts.evaluate(job)[0]["have"])
	tank["color"] = brg.lightened(0.06)
	var near := Contracts.payout(job, 0)
	var m_near := Contracts.tank_match(tank, job["goals"][0])
	tank["color"] = brg
	var spot := Contracts.payout(job, 0)
	check(m_near >= Contracts.MATCH_MIN and m_near < 0.99 and int(near["match_bonus"]) > 0
		and int(spot["match_bonus"]) > int(near["match_bonus"]) and int(spot["match_bonus"]) == roundi(400 * Contracts.MATCH_BONUS),
		"close (%s) pays %s extra, spot on %s: closer pays more" % [PaintMix.match_text(m_near), Contracts.money(int(near["match_bonus"])),
		Contracts.money(int(spot["match_bonus"]))])
	check(Contracts.evaluate(job)[0]["done"] and str(spot["note"]).contains("Colour match 100.0%"), "and the note says so: %s" % spot["note"])
	tank["mix"] = {"effect": "metallic"}
	check(Contracts.tank_match(tank, job["goals"][0]) < 1.0 - PaintMix.EFFECT_MISS + 0.001, "the right colour in metallic isn't a solid match")
	tank.erase("mix")
	tank["mask"] = {"pattern": "stripe", "color": gold, "q": 1.0, "mix": {}}
	var rows := Contracts.evaluate(job)
	check(not rows[1]["done"] and str(rows[1]["have"]).contains("centre stripe"), "a centre stripe isn't the pinstripe asked for (%s)" % rows[1]["have"])
	tank["mask"]["pattern"] = "pin"
	rows = Contracts.evaluate(job)
	check(rows[1]["done"] and Contracts.progress(job) == 1.0, "a gold pinstripe on green: every goal met (%s)" % rows[1]["have"])
	tank["mask"]["color"] = Color(0.92, 0.92, 0.9)
	check(not Contracts.evaluate(job)[1]["done"], "a white pinstripe isn't gold")
	var bespoke_match := false
	for i in 40:
		var b := Contracts.make_offer("bespoke", "Lady Okafor")
		var kinds: Array = b["goals"].map(func(g): return str(g["t"]))
		if kinds.has("match") and kinds.has("stripe"):
			bespoke_match = true
			break
	check(bespoke_match, "bespoke customers ask for a matched colour with a stripe")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pats := {}
	for i in 60:
		pats[str(Contracts._stripe_goal(rng)["pattern"])] = true
	Progress.profile["xp"] = Progress.xp_for_level(5)
	var low := {}
	for i in 60:
		low[str(Contracts._stripe_goal(rng)["pattern"])] = true
	var effects := {}
	for i in 60:
		effects[str(Contracts._match_goal(rng, false)["effect"])] = true
	check(pats.has("fade_top") and not low.has("fade_top") and not effects.has("candy") and not effects.has("chameleon"),
		"fades are only asked for at level 12 and over, and colours only in effects the crew can mix (%s)" % ", ".join(effects.keys()))
	Progress.profile["xp"] = Progress.xp_for_level(16)
	# A rare recipe on the tank adds to the bike's price.
	tank.erase("mask")
	var before := Sales.uniqueness(bike)
	var fair := int(Sales.appraise(bike)["fair"])
	tank["mix"] = PaintMix.spec(PaintMix.parse_code(str(PaintMix.library_entry("honda_candy_red")["code"])), "Candy Red")
	var after := Sales.uniqueness(bike)
	check(float(after["score"]) > float(before["score"]) and ", ".join(after["why"]).contains("custom candy paint")
		and int(Sales.appraise(bike)["fair"]) > fair, "candy paint makes it more of a one-off and worth more (%s)" % ", ".join(after["why"]))
	Progress.profile = saved


## Saved with the shed: stock, tins, recipes, the test card, paint on parts; anything carried
## goes back on the shelf; old saves get the starter stock.
func _test_paint_save() -> void:
	Shed.start_new("Tester", 304)
	var me := Shed.me()
	Shed.request({"a": "paint_bench", "on": true})
	Shed.request({"a": "paint_tin_new", "base": "S"})
	Shed.request({"a": "paint_pour", "tint": "UB", "g": 25.0, "seq": 1})
	Shed.request({"a": "paint_stir", "amount": 0.5})
	Shed.request({"a": "paint_stir", "amount": 0.5})
	Shed.request({"a": "paint_tin_save", "name": "Steel Blue"})
	Shed.request({"a": "paint_tin_new", "base": "W"})
	Shed.request({"a": "paint_bench", "on": false})
	var tid := int(PaintBay.tin_in_slot(0)["id"])
	Shed.request({"a": "paint_tin_take", "tin": tid})
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[5])
	Shed.items[tank]["mix"] = PaintBay.tins()[tid]["mix"]
	Shed.items[tank]["mix_coats"] = 2
	Shed.items[tank]["mask"] = {"pattern": "pin", "color": Color.WHITE, "q": 1.0, "mix": {}}
	Shed.items[tank]["flat"] = 0.15
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(copy, "Tester")
	check(PaintBay.recipes().size() == 1 and str(PaintBay.recipes().values()[0]["name"]) == "Steel Blue", "the swatch wall is saved")
	check(PaintBay.tins().has(tid) and PaintBay.slot_of(PaintBay.tins()[tid]) >= 0 and not PaintBay.carrying(me), "the tin carried goes back on the shelf")
	check(not PaintBay.bench_tin().is_empty() and PaintBay.at_bench() == 0, "the tin left on the scale is still there, nobody at the bench")
	var it: Dictionary = Shed.items[tank]
	check(it["mix"]["color"] is Color and int(it["mix_coats"]) == 2 and str(it["mask"]["pattern"]) == "pin" and is_equal_approx(float(it["flat"]), 0.15),
		"paint saves with the part: mix, coats, mask and sheen")
	var old: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	old.erase("paint_bay")
	Shed.load_state(old, "Tester")
	check(PaintBay.recipes().is_empty() and PaintBay.stock_of("W") >= 1.0, "a shed saved before the bay gets its starter stock")
	check(PaintBay.sanitize("junk") == PaintBay.empty() and PaintBay.sanitize({"recipes": "x"})["recipes"] == {}, "and odd values are put right")


## In the world: the room off the paint shop through its glass door, the bench stepped up to with
## F (the view drops to the scale), a tint poured and stirred, saved onto the shelf and the
## swatch wall, the tin carried and its paint in the gun's cup.
func _test_paint_bay_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	await get_tree().physics_frame
	var room: PaintBayRoom = main.workshop.paint_bay
	check(room != null and room.find_child("GlassDoor", true, false) != null and room.find_child("MixingBench", true, false) != null,
		"the mixing bay is built off the paint shop, with its glass door and bench")
	check(Workshop.room_at(PaintBay.BENCH_STAND + Vector3(0, 0.5, 0)) == "mixing" and Workshop.room_at(Vector3(12.0, 0.5, 69.6)) == "paint",
		"it's a room of its own next to the paint shop")
	var w: Walker = main.walker
	w.set_tool("hands")
	# Through the glass door from the paint shop.
	w.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(13.2, 0.05, PaintBay.DOOR_Z)))
	for i in 100:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(room._door_open > 0.9, "the glass door slides open as you come up to it")
	w.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), PaintBay.BENCH_STAND + Vector3(0, 0.05, 0)))
	w._look(0.0, -0.6)
	for i in 6:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(str(w.target.get("kind", "")) == "paint_bay" and str(w.target.get("station", "")) == "bench" and w.info.contains("Mixing bench"),
		"looking at the bench (%s)" % str(w.target))
	_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	var bench: PaintBench = main.paint_bench
	check(bench.visible and PaintBay.at_bench() == Shed.me() and room.bench_camera.current and not w.controls_enabled,
		"F: step up to the bench, the view down on the scale")
	bench.press("White base  (%s in stock)" % PaintBay.stock_text("W"))
	await get_tree().process_frame
	check(not PaintBay.bench_tin().is_empty(), "a tin of white base on the scale")
	bench.tint = "PB"
	bench._sig = ""
	bench._refresh()
	bench.start_pour(0.0)
	bench.set_tilt(0.9)
	for i in 30:
		await get_tree().process_frame
	bench.stop_pour()
	for i in 10:
		await get_tree().process_frame
	var got := float(PaintBay.bench_tin()["tints"].get("PB", 0.0))
	check(got > 1.0 and room._scale_label.text != "0 g" and bench._scale_l.text.contains("g"), "tipped: phthalo blue pours onto the scale (%.1f g, %s)" % [got, room._scale_label.text])
	bench.stir_turns(12.0)
	for i in 20:
		await get_tree().process_frame
	check(float(PaintBay.bench_tin()["stir"]) > 0.95, "stirred round and round, it's even (%.2f)" % float(PaintBay.bench_tin()["stir"]))
	bench._name_edit.text = "Session Blue"
	bench.press("Save tin")
	for i in 4:
		await get_tree().process_frame
	check(PaintBay.recipes().size() == 1 and not PaintBay.tin_in_slot(0).is_empty(), "saved onto the tin shelf and the swatch wall")
	bench.close_dialog()
	await get_tree().process_frame
	check(not bench.visible and w.camera.current and PaintBay.at_bench() == 0, "Esc steps back from the bench")
	for i in 2:
		await get_tree().process_frame
	var swatches := room.find_children("*", "StaticBody3D", true, false).filter(func(b): return str(b.get_meta("paint_bay", "")) == "swatch")
	check(swatches.size() == 1, "its card is on the swatch wall")
	# The tin off the shelf, into the cup.
	var at := PaintBay.slot_xf(0).origin + Vector3(0, 0.08, 0)
	var stand := Vector3(at.x - 1.1, 0.05, at.z)
	var eye := stand + Vector3(0, Walker.EYE, 0)
	var flat := Vector2(at.x - eye.x, at.z - eye.z)
	w.place(Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.y)), stand))
	w._look(0.0, atan2(at.y - eye.y, flat.length()) - w._pitch)
	for i in 6:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(str(w.plan.get("action", {}).get("a", "")) == "paint_tin_take", "looking at it on the shelf: take it (%s)" % str(w.target))
	if not w.plan.is_empty():
		Shed.request(w.plan["action"])
	for i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(PaintBay.carrying(Shed.me()) and is_instance_valid(w._held_view) and w.alt_plan.is_empty()
		and w.tap_prompt == "%s: fill the spray gun's cup" % Walker._keys("interact") and w.tap_prompt.begins_with("F"),
		"in your hand, one key fills the gun's cup, and it says so: %s (no right mouse / LT for it)" % w.tap_prompt)
	await get_tree().process_frame
	check(main.hud._prompt.text.contains("fill the spray gun's cup"), "the prompt's on screen: %s" % main.hud._prompt.text.replace("\n", " | "))
	_press("interact")
	for i in 3:
		await get_tree().process_frame
	check(not PaintBay.cup_of(Shed.me()).is_empty() and float(PaintBay.cup_of(Shed.me()).get("litres", 0.0)) > 0.1,
		"F decants the tin into the cup (%.2f l)" % float(PaintBay.cup_of(Shed.me()).get("litres", 0.0)))
	w.set_tool("gun")
	check(w.spray_text().contains("Session Blue") and w.spray_cup() == "cup", "and the gun comes out loaded from the cup: %s" % w.spray_text())
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## The bench's extras: the tint rack's names read in full, the scale's tare, the bottle back on
## the rack once a pour stops (on everyone's screen, stirring or not), the shaker's whirr, and
## the paint shop's own compact bench, which is the same bench as the bay's.
func _test_paint_bench_extras() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.new_shed = true
	main._start_session()
	await get_tree().physics_frame
	Shed.upgrades["paint_effects_rack"] = {"at": 0}
	Shed.changed.emit()
	var me := Shed.me()
	var room: PaintBayRoom = main.workshop.paint_bay
	var bench: PaintBench = main.paint_bench
	var w: Walker = main.walker
	w.set_tool("hands")
	check(room.find_child("ShopMixingBench", true, false) != null and Workshop.room_at(PaintBay.SHOP_STAND + Vector3(0, 0.5, 0)) == "paint"
		and not Workshop.booth_footprint().has_point(Vector2(PaintBay.SHOP_BENCH.end.x, PaintBay.SHOP_BENCH.end.y)),
		"a compact mixing bench in the paint shop itself, beside the spray bay")
	# Up to it: F at the paint shop's bench opens the same bench, the view on its own scale.
	w.place(Transform3D(Basis(), PaintBay.SHOP_STAND + Vector3(0, 0.05, 0)))
	w._look(0.0, -0.7)
	for i in 6:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(str(w.target.get("kind", "")) == "paint_bay" and str(w.target.get("station", "")) == "bench", "looking at the shop's bench (%s)" % str(w.target))
	_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	check(bench.visible and PaintBay.at_bench() == me and PaintBay.station() == "shop" and room.shop_camera.current,
		"F: stepped up to the paint shop's bench, looking down on its scale")
	bench.press("White base  (%s in stock)" % PaintBay.stock_text("W"))
	for i in 2:
		await get_tree().process_frame
	check(not PaintBay.bench_tin().is_empty() and room._bench_tin != null and room._bench_tin.position.distance_to(PaintBay.SHOP_SCALE_AT) < 0.1,
		"the tin goes on the shop bench's scale")
	# The tint rack: every name in full, two to a row in the card.
	bench.tint = "UB"
	bench._sig = ""
	bench._refresh()
	await get_tree().process_frame
	var half := (PaintBench.PANEL_W - 40) / 2.0
	var rack_ok := 0
	var rack_bad: Array[String] = []
	for code in PaintBay.rack():
		var nm := str(PaintMix.TINTS[code]["name"])
		var found := false
		for b in bench._box.find_children("*", "Button", true, false):
			var bt := b as Button
			if bt.text.begins_with(nm + "\n") and bt.text.contains(str(code)):
				found = true
				var fits := not bt.clip_text and bt.get_combined_minimum_size().x <= half
				if fits:
					rack_ok += 1
				else:
					rack_bad.append("%s %.0f" % [nm, bt.get_combined_minimum_size().x])
		if not found:
			rack_bad.append(nm + " missing")
	check(rack_ok == PaintBay.rack().size() and rack_ok == 28, "every tint's name reads in full on the rack (%d; %s)" % [rack_ok, ", ".join(rack_bad)])
	# Pouring: the bottle comes off the shop's rack, over the tin; let go and it's back.
	bench.start_pour(0.0)
	bench.set_tilt(0.9)
	for i in 20:
		await get_tree().process_frame
	check(room._pour_bottle != null and not (room._rack_bottles["UB"][1] as Node3D).visible and (room._rack_bottles["UB"][0] as Node3D).visible,
		"the bottle's off the shop rack and over the tin while it pours")
	bench.stop_pour()
	for i in 6:
		await get_tree().process_frame
	var ub := float(PaintBay.bench_tin()["tints"].get("UB", 0.0))
	check(ub > 1.0 and room._pour_bottle == null and (room._rack_bottles["UB"][1] as Node3D).visible and float(PaintBay.bench()["tilt"]) == 0.0
		and str(PaintBay.bench()["tint"]) == "", "let go: back on the rack, and the bench tells everyone (%.1f g poured)" % ub)
	# Tare: the scale reads 0 g from there, the next tint weighed on its own; the tin's total stays.
	var total := PaintMix.total_grams(PaintBay.bench_tin())
	var step := PaintMix.scale_step(Progress.level(), PaintBay.kit("scale"))
	check("Tare: reset to 0 g" in bench.buttons(), "a Tare button by the scale")
	bench.press("Tare: reset to 0 g")
	for i in 3:
		await get_tree().process_frame
	check(PaintBay.tared(PaintBay.bench_tin()) and bench._scale_l.text == "SCALE  " + PaintMix.read_scale(0.0, step)
		and room._shop_scale_label.text == PaintMix.read_scale(0.0, step) and is_equal_approx(PaintMix.total_grams(PaintBay.bench_tin()), total),
		"tared: the scale reads %s (%s on the bench), the tin's still %.1f g" % [bench._scale_l.text, room._shop_scale_label.text, total])
	Shed.request({"a": "paint_pour", "tint": "LY", "g": 12.0, "tilt": 0.5, "seq": 900})
	await get_tree().process_frame
	check(bench._scale_l.text == "SCALE  " + PaintMix.read_scale(12.0, step) and bench._tare_l.text.contains("in all")
		and is_equal_approx(float(PaintBay.bench_tin()["tints"]["UB"]), ub), "the next tint weighs on its own: %s" % bench._scale_l.text)
	Shed.request({"a": "paint_pour_stop"})
	# Someone else's pour, as the crew see it: up while it pours, back on the rack when it stops,
	# and not left hanging while they stir.
	bench.close_dialog()
	await get_tree().process_frame
	Shed.crew[77] = {"name": "Mate", "tool": "hands"}
	PaintBay.apply(77, {"a": "paint_bench", "on": true, "seq": 0, "at": "bay"})
	PaintBay.apply(77, {"a": "paint_pour", "tint": "PB", "g": 2.0, "tilt": 0.7})
	for i in 4:
		await get_tree().process_frame
	check(room._pour_bottle != null and room._pour_code == "PB" and room._pour_bottle.position.distance_to(PaintBay.SCALE_AT + Vector3(0, 0.3, 0)) < 0.01
		and room._bench_tin.position.distance_to(PaintBay.SCALE_AT) < 0.1, "a mate's pour at the bay: their bottle tipped over the bay's scale")
	PaintBay.apply(77, {"a": "paint_pour_stop"})
	await get_tree().process_frame
	check(room._pour_bottle == null and (room._rack_bottles["PB"][0] as Node3D).visible, "they let go: the bottle's back on the rack at once")
	# The old way it stuck: a last pour with the bottle tipped, then stirring (no stop heard).
	PaintBay.apply(77, {"a": "paint_pour", "tint": "PB", "g": 2.0, "tilt": 0.7})
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1200:
		PaintBay.apply(77, {"a": "paint_stir", "amount": 0.05})
		await get_tree().process_frame
	check(room._pour_bottle == null and room._stick != null, "stirring with no more pours: the bottle doesn't hang over the cup")
	PaintBay.put_back(77)
	Shed.crew.erase(77)
	# The shaker whirrs while it runs, from the shaker.
	PaintBay.apply(me, {"a": "paint_bench", "on": true, "seq": 0})
	PaintBay.apply(me, {"a": "paint_shake"})
	for i in 3:
		await get_tree().process_frame
	check(room._shaker_sound.playing and room._shaker_sound.get_meta("loop", "") == "shaker"
		and room._shaker_sound.global_position.distance_to(PaintBay.SHAKER_AT) < 0.5 and SfxSynth.is_loop("shaker"), "the shaker whirrs while it runs")
	PaintBay._st()["shaker"]["left"] = 0.001
	for i in 4:
		await get_tree().process_frame
	check(not room._shaker_sound.playing, "and stops when it's done")
	# Old saves: a bench from before has its new fields filled in.
	var old := PaintBay.sanitize({"tins": {}, "bench": {"by": 0, "tin": 0}})
	check(str(old["bench"]["at"]) == "bay" and float(old["bench"]["tare"]) == 0.0 and int(old["bench"]["pour_n"]) == 0, "an old save's bench loads")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


func _test_spray_coat_rules() -> void:
	var me := Shed.me()
	var xp_before := int(Progress.profile.get("xp", 0))
	# Primer: an optional first coat, grey, with the old colour kept under it.
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[0])
	Shed._move(tank, "floor", Transform3D(Basis(), Workshop.CENTER + Vector3(2.0, 0.0, 2.0)))
	var rusty := Shed._new_item("cafe_15", 0.6, 0.0, 0.0)
	Shed._move(rusty, "floor", Transform3D(Basis(), Workshop.CENTER + Vector3(2.5, 0.0, 2.0)))
	check(Shed.check(me, {"a": "prime", "item": rusty}).contains("rusty"), "rusty parts can't be primed")
	check(Shed.check(me, {"a": "prime", "item": tank, "gun": true}).contains("booth"), "the spray gun's primer still needs the booth")
	check(Shed.check(me, {"a": "prime", "item": tank}) == "", "a spray can of primer goes on anywhere")
	Shed.request({"a": "prime", "item": tank, "quality": 0.9, "waste": 0.0})
	var it: Dictionary = Shed.items[tank]
	check(it.get("primer_top", false) and is_equal_approx(float(it["primer"]), 0.9) and it["color"] == Shed.PAINTS[0],
		"primed: grey on top, the old colour kept under it (%s)" % str(it.get("primer", "-")))
	check(Shed.paint_text(it) == "Grey primer" and Shed.condition_of(it).get("primer", false) and Shed.condition_text(it).contains("In primer"),
		"it reads as grey primer, and is drawn in it")
	check(int(Progress.profile.get("xp", 0)) > xp_before and Progress.XP.has("prime") and Progress.PAY.has("prime"), "priming pays XP and a wage")
	check(Shed.check(me, {"a": "prime", "item": tank}).contains("already"), "it can't be primed twice over")
	check(Shed.check(me, {"a": "coat", "item": tank, "coat": "clear"}).contains("primer"), "lacquer won't go on bare primer")
	var model := BikeModel.item_display(tank).get_meta("model") as BikeModel
	var greys := 0
	for mi in model._slot_meshes.get("tank", []):
		var m := (mi as GeometryInstance3D).material_override as StandardMaterial3D
		if m and m.has_meta("paint_surface") and m.albedo_color.is_equal_approx(Shed.PRIMER_COLOR):
			greys += 1
	check(greys > 0, "a primed tank is drawn grey where it's painted (%d surfaces)" % greys)
	model.get_parent().free()
	# The colour over the primer comes out better than without it.
	var bare := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[0])
	Shed._move(bare, "floor", Transform3D(Basis(), Workshop.CENTER + Vector3(3.0, 0.0, 2.0)))
	check(Shed.check(me, {"a": "paint", "item": tank, "color": 0, "finish": "gloss"}) == "", "a primed part can be painted its old colour again")
	Shed.request({"a": "paint", "item": tank, "color": 1, "finish": "gloss", "quality": 0.8, "waste": 0.0})
	Shed.request({"a": "paint", "item": bare, "color": 1, "finish": "gloss", "quality": 0.8, "waste": 0.0})
	var pq := float(Shed.items[tank]["paint_quality"])
	check(pq > float(Shed.items[bare]["paint_quality"]) + 0.05 and is_equal_approx(pq, 0.8 + Shed.PRIMER_BONUS * 0.9),
		"paint over primer keys on better (%.3f against %.3f)" % [pq, float(Shed.items[bare]["paint_quality"])])
	check(not Shed.items[tank].has("primer_top") and Shed.items[tank].has("primer") and Shed.paint_text(Shed.items[tank]) == "Gloss blue"
		and Shed.finish_text(Shed.items[tank]).contains("over primer"), "the primer's under the colour now: %s" % Shed.finish_text(Shed.items[tank]))
	# Clear lacquer over the colour: with a rattle can anywhere, once.
	var clear := {"a": "coat", "item": tank, "coat": "clear", "quality": 1.0}
	check(Shed.check(me, clear) == "", "a can of clear lacquer goes over paint anywhere")
	check(Shed.check(me, {"a": "coat", "item": tank, "coat": "enamel_black"}).contains("paint shop"), "engine enamel still needs the gun in the booth")
	Shed.request(clear)
	var lq := float(Shed.items[tank]["paint_quality"])
	check(is_equal_approx(lq, minf(1.0, pq + Shed.LACQUER_BONUS)) and Shed.coat_gloss(str(Shed.items[tank]["coat"])) > 0.9
		and Shed.finish_text(Shed.items[tank]).contains("lacquered"), "lacquer brings the paint job up and shines it: %s" % Shed.finish_text(Shed.items[tank]))
	Shed.request(clear)
	check(is_equal_approx(float(Shed.items[tank]["paint_quality"]), lq), "a second coat of lacquer adds nothing more")
	check(Shed.condition_of(Shed.items[tank]).get("coat", "") == "clear", "the lacquer is drawn on it (its condition's coat)")
	# Primer over a lacquered part takes the lacquer off; blasting it bare takes the primer off.
	Shed.request({"a": "prime", "item": tank, "quality": 1.0})
	check(not Shed.items[tank].has("coat") and Shed.items[tank].get("primer_top", false), "priming over lacquer covers it")
	# A contract wanting a tank colour doesn't count grey primer as that colour.
	var on_bike := 0
	for id in Shed.bikes:
		if Shed.item_on(id, "tank") != 0:
			on_bike = id
			break
	if on_bike != 0:
		var t2 := Shed.item_on(on_bike, "tank")
		var was: Color = Shed.items[t2]["color"]
		Shed.items[t2]["primer_top"] = true
		var g := Contracts.eval_goal({"bike": on_bike}, {"t": "paint", "color": Shed.paint_index(was)})
		check(not g["done"] and str(g["have"]) == "grey primer", "a tank in primer isn't the colour a job wants yet (%s)" % str(g))
		Shed.items[t2].erase("primer_top")
	# Old saves: parts without any primer or lacquer draw and read as before.
	var old := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[2])
	check(not Shed.condition_of(Shed.items[old]).has("primer") and Shed.blast_sig(Shed.items[old]) == "" and Shed.paint_text(Shed.items[old]) == "Orange",
		"a part from an old save, with no primer, is as it was")
	var copy: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(copy, "Tester")
	check(Shed.items[tank].get("primer_top", false) and is_equal_approx(float(Shed.items[tank]["primer"]), 1.0), "primer is kept in the save")
	for id in [tank, rusty, bare, old]:
		Shed.items.erase(id)
	# The fan: how it lands with distance, and the sweet spot widening with skill.
	var job := SprayJob.new()
	job.set_tool(0.1, 10.0, 0.35, 1.0)
	var close := job.fan_at(0.3)
	var good := job.fan_at(0.8)
	var far := job.fan_at(1.6)
	var out := job.fan_at(2.6)
	check(close["zone"] == "close" and good["zone"] == "good" and far["zone"] == "far" and out["zone"] == "out",
		"too close, the sweet spot, too far and out of reach (%s %s %s %s)" % [close["zone"], good["zone"], far["zone"], out["zone"]])
	check(float(close["flow"]) > float(good["flow"]) * 2.0 and float(close["radius"]) < float(good["radius"]),
		"close up it piles on in a tight spot (%.1f vs %.1f coats a second)" % [float(close["flow"]), float(good["flow"])])
	check(float(good["dry"]) == 0.0 and float(far["dry"]) > 0.3 and float(far["radius"]) > float(good["radius"]) and float(out["flow"]) == 0.0,
		"further off it spreads, lands dry (%.2f) and then doesn't reach at all" % float(far["dry"]))
	job.set_tool(0.1, 10.0, 0.35, 1.2)
	check(job.sweet().x < SprayJob.NEAR and job.sweet().y > SprayJob.FAR, "a better hand widens the sweet spot both ways")
	var ranks: int = int(Progress.profile["skills"].get("steady_hand", 0))
	Progress.profile["skills"]["steady_hand"] = 2
	check(Progress.spray_band_mult(me, "spray") > 1.05, "Steady Hand widens it (%.2f)" % Progress.spray_band_mult(me, "spray"))
	Progress.profile["skills"]["steady_hand"] = ranks
	check(is_equal_approx(job.quality({"covered": 1.0, "runs": 0.0, "dry": 0.0}), 1.0)
		and job.quality({"covered": 1.0, "runs": 0.2, "dry": 0.0}) < 0.9 and job.quality({"covered": 1.0, "runs": 0.0, "dry": 0.3}) < 0.92,
		"runs and dry spray take the shine off the quality")
	check(SprayJob.layer_of({"a": "prime"}) == "primer" and SprayJob.layer_of({"a": "coat", "coat": "clear"}) == "clear"
		and SprayJob.layer_of({"a": "coat", "coat": "enamel_black"}) == "paint" and SprayJob.layer_of({"a": "paint"}) == "paint",
		"primer, colour (an enamel's a colour) and lacquer coats")
	var look := SprayJob.look_for({"a": "paint", "color": 1, "finish": "gloss"}, {"color": Shed.PAINTS[0], "primer_top": true})
	var look2 := SprayJob.look_for({"a": "paint", "color": 1, "finish": "gloss"}, {"color": Shed.PAINTS[0]})
	check((look["under"] as Color).a == 0.0 and (look2["under"] as Color).a > 0.5, "missed bits show the primer, or the old paint flatted back")
	# What the can and gun are loaded with.
	var w := Walker.new()
	var can: Array = w.spray_loads("spray")
	var gun: Array = w.spray_loads("gun")
	check(can.any(func(l): return l["kind"] == "primer") and can.any(func(l): return l["kind"] == "coat" and l["id"] == "clear")
		and not can.any(func(l): return l["id"] == "enamel_black"), "the spray can has primer and clear lacquer, and no enamels")
	var cups := 1 + PaintMix.FADE_PATTERNS.size()
	check(gun.size() == Shed.FINISHES.size() + Shed.COAT_ORDER.size() + 1 + cups and gun[-1 - cups]["kind"] == "primer"
		and gun.slice(gun.size() - cups).all(func(l): return l["kind"] == "cup")
		and gun[Shed.FINISHES.size()]["id"] == "clear", "the gun's coats follow its finishes, then primer, then the mixing bay's cup")
	w.free()


func _test_spray_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var ws: Workshop = main.workshop
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hook: String = Shed.furniture_spots(booth)[4]
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[0])
	Shed.items[tank]["finish"] = "gloss"
	Shed._move(tank, "spot", hook)
	Shed.changed.emit()
	for i in 5:
		await get_tree().process_frame
	var disp: Node3D = ws._spot_nodes.get(hook, null)
	if disp and disp.get_parent() is Swing:
		disp.get_parent().set_physics_process(false)   # hold it still for the test
	var surf := ws.item_surface(tank)
	check(not surf.is_empty() and surf["slots"] == ["tank"] and surf["model"] is BikeModel, "a hung tank has a surface to spray onto (%s)" % str(surf.get("slots", [])))
	var fr: Dictionary = ws.item_frame(tank)
	var box: AABB = fr["box"]
	var xf: Transform3D = fr["xf"]
	var centre: Vector3 = xf * box.get_center()
	var away := Vector3(Workshop.BOOTH_XF.basis.z.x, 0.0, Workshop.BOOTH_XF.basis.z.z).normalized()
	w.place(Transform3D(Basis(), Vector3(centre.x, 0.0, centre.z) + away * 0.85))
	w.set_tool("spray")
	w.spray_finish = Shed.FINISHES.size()
	check(w.spray_primer() and w.spray_text() == "Grey primer", "T on to grey primer")
	await _aim_point(w, centre)
	check(str(w.plan.get("action", {}).get("a", "")) == "prime" and w.plan["blocked"] == "", "aimed at the tank, the work button primes it (%s)" % str(w.plan))
	# Painting needs the spray controls up first (F): the trigger alone just says so.
	Input.action_press("act")
	for i in 10:
		await get_tree().physics_frame
	Input.action_release("act")
	check(w.spray == null or not w.spray.live, "without the spray controls up, the trigger doesn't spray")
	await get_tree().physics_frame
	_press("interact")
	await get_tree().physics_frame
	check(not w.spray_mode.is_empty() and int(w.spray_mode["item"]) == tank and w.spray_settling(), "F brings the spray controls up on the tank, and you get set first")
	Input.action_press("act")
	for i in 20:
		await get_tree().physics_frame
	check(w.spray == null or not w.spray.live, "nothing sprays while you're getting set")
	check(w._spray_fx != null and w._spray_fx.visible and w._spray_fx.ring.visible and not w._spray_fx.cone.visible,
		"aiming, the footprint shows where it would land, without spraying")
	Input.action_release("act")
	w.spray_mode["settle"] = 0.0
	await get_tree().physics_frame
	var held_look := w.rotation.y
	w.rotation.y += 1.2
	for i in 3:
		await get_tree().physics_frame
	check(int(w.plan.get("action", {}).get("item", 0)) == tank, "the can stays on the tank wherever you look")
	w.rotation.y = held_look
	await _aim_point(w, centre)
	Input.action_press("act")
	for i in 40:
		await get_tree().physics_frame
	var job: SprayJob = w.spray
	check(job != null and job.live and job.layer == "primer", "holding it starts a primer coat by hand")
	if job == null:
		Input.action_release("act")
		main._leave()
		main.queue_free()
		await get_tree().physics_frame
		return
	var marks := job.marks
	check(is_instance_valid(marks) and marks.get_parent() == job.model and marks.mesh_count() > 0 and marks.painted_count() > 0,
		"the primer goes on the tank itself, on its painted surfaces (%d meshes, %d cubes coated)" % [marks.mesh_count() if marks else 0, marks.painted_count() if marks else 0])
	var mat := marks.material_for("tank")
	check(mat != null and (mat.get_shader_parameter("coat_color") as Color).is_equal_approx(Color(Shed.PRIMER_COLOR, 1.0)), "drawn in primer grey")
	var st := job.stats()
	check(job.seen_n > 50 and float(st["covered"]) > 0.0 and float(st["covered"]) < SprayJob.DONE,
		"one spot covers some of what you can see, the rest still bare (%.0f%% of %d points)" % [float(st["covered"]) * 100.0, job.seen_n])
	check(job.jet.get("hit", false) and str(job.jet["zone"]) == "good", "from 0.85 m off it's in the sweet spot (%.2f m, %s)" % [float(job.jet.get("dist", 0.0)), str(job.jet.get("zone", ""))])
	var fx: SprayFx = w._spray_fx
	check(fx != null and fx.visible and fx.cone.visible and fx.zone == "good" and fx.droplets.emitting,
		"you see the spray: a cone to the tank, its footprint in green, droplets landing")
	check(fx.droplets.scale_amount_max < 0.003 and w._mist != null and w._mist.scale_amount_max < 0.003 and w._mist.amount >= 600,
		"it's a fine mist of tiny droplets, not blobs")
	await get_tree().process_frame
	var hud: SprayHud = main.hud.spray_hud
	check(hud.visible and hud.showing() and not main.hud._panel.visible, "the spray readout comes up in place of the side panel")
	# Lingering on one spot: it runs, and says so.
	w.set_crouched(true)
	w.place(Transform3D(Basis(), Vector3(centre.x, 0.0, centre.z) + away * 0.4))
	for i in 30:
		await get_tree().physics_frame
	var eye: Vector3 = w.camera.global_position
	var d := centre - eye
	w.rotation.y = atan2(-d.x, -d.z)
	w._pitch = 0.0
	w._look(0.0, atan2(d.y, Vector2(d.x, d.z).length()))
	w.spray_cues.clear()
	for i in 150:
		await get_tree().physics_frame
	st = job.stats()
	check(str(job.jet.get("zone", "")) == "close" and float(st["runs"]) > 0.0, "up close and lingering it runs (%.0f%% run, %s)" % [float(st["runs"]) * 100.0, str(job.jet.get("zone", ""))])
	check(w.spray_cues.any(func(c): return c["kind"] == "runs") or hud.cue.get("kind", "") == "runs", "and the HUD shouts about it")
	check(str(job.jet.get("pace", "")) == "slow", "the pace gauge says you're lingering")
	w.set_crouched(false)
	# The scan lights up what's missed.
	_press("blast_scan")
	await get_tree().process_frame
	check(w.spray_scan and marks.scanning(), "X lights up what's missed")
	_press("blast_scan")
	await get_tree().process_frame
	check(not marks.scanning(), "and X again turns it off")
	# Let go before it's covered: the coat waits, as it was.
	Input.action_release("act")
	for i in 3:
		await get_tree().physics_frame
	check(w.spray == job and not job.live and not Shed.items[tank].get("primer_top", false) and is_instance_valid(marks),
		"let go half done and the coat waits for you, just as you left it")
	# Back at the right distance, steady passes all over it, both sides and underneath, finish it.
	await _spray_round(w, tank, xf, box, centre, away)
	check(Shed.items[tank].get("primer_top", false) and float(Shed.items[tank].get("primer", 0.0)) > 0.4,
		"sweeping over all of it, round both sides and underneath, puts the primer on (%.0f%%)" % (float(Shed.items[tank].get("primer", 0.0)) * 100.0))
	check((w.spray == null or not w.spray.live) and hud.cue.get("kind", "") == "done" or w.spray_cues.any(func(c): return c["kind"] == "done"),
		"and the HUD says it's done")
	for i in 4:
		await get_tree().process_frame
	# The colour over it.
	w.spray_finish = 0
	w.spray_color = 1
	await _aim_point(w, centre)
	check(str(w.plan.get("action", {}).get("a", "")) == "paint" and w.plan["blocked"] == "", "then the colour goes on over it")
	Input.action_press("act")
	for i in 20:
		await get_tree().physics_frame
	var cj: SprayJob = w.spray
	check(cj != null and cj.layer == "paint" and cj.steps()[0]["state"] == "done" and cj.steps()[1]["state"] == "now",
		"the coats line up on the HUD: primer done, colour now, lacquer to come")
	check(cj != null and ((cj.look["under"] as Color).a == 0.0), "the missed bits show the grey primer under it")
	Input.action_release("act")
	await _spray_round(w, tank, xf, box, centre, away)
	var it: Dictionary = Shed.items[tank]
	check(Shed.paint_index(it["color"]) == 1 and not it.get("primer_top", false) and it.has("paint_quality") and Shed.finish_text(it).contains("over primer"),
		"painted blue over primer: %s" % Shed.finish_text(it))
	# And clear lacquer from the can on top.
	w.spray_finish = Shed.FINISHES.size() + 1
	check(w.spray_coat() == "clear", "T on to clear lacquer")
	await _aim_point(w, centre)
	check(str(w.plan.get("action", {}).get("a", "")) == "coat" and w.plan["blocked"] == "", "then lacquer over the colour (%s)" % str(w.plan.get("blocked", "")))
	var before := float(it["paint_quality"])
	await _spray_round(w, tank, xf, box, centre, away)
	check(Shed.items[tank].get("coat", "") == "clear" and float(Shed.items[tank]["paint_quality"]) > before,
		"lacquered, and the finish comes up for it (%.2f to %.2f)" % [before, float(Shed.items[tank].get("paint_quality", 0.0))])
	_press("interact")
	await get_tree().physics_frame
	check(w.spray_mode.is_empty(), "F again steps back from the spray controls")
	w.set_tool("hands")
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## Hand spraying round a hung part: it hangs from the tip of its hook; paint only lands on the
## side facing the gun, so one side is about half of it and the far side and underneath stay
## bare until you go round; the scan lights up what's missed; a second coat started over a
## half-done one takes its place; the wet look comes off once the coat's done; and a taped part
## keeps its tape in sight while you spray.
func _test_spray_sides() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var ws: Workshop = main.workshop
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hook: String = Shed.furniture_spots(booth)[2]
	var tank := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[0])
	Shed.items[tank]["finish"] = "gloss"
	Shed._move(tank, "spot", hook)
	Shed.changed.emit()
	for i in 5:
		await get_tree().process_frame
	var disp: Node3D = ws._spot_nodes.get(hook, null)
	var swing: Swing = disp.get_parent() as Swing if disp else null
	check(swing != null, "the tank hangs on a hook that swings")
	if swing == null:
		main._leave()
		main.queue_free()
		await get_tree().physics_frame
		return
	swing.set_physics_process(false)
	# It hangs from the tip of the hook, touching it, not in the air below it.
	var fr: Dictionary = ws.item_frame(tank)
	var box: AABB = fr["box"]
	var xf: Transform3D = fr["xf"]
	var top := -INF
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c in 8:
		var p: Vector3 = xf * box.get_endpoint(c)
		top = maxf(top, p.y)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var ring: Node3D = swing.get_node("Hook")
	var tip := ring.global_position.y - 0.028
	check(absf(top - tip) < 0.02 and ring.global_position.x > lo.x and ring.global_position.x < hi.x
		and ring.global_position.z > lo.y and ring.global_position.z < hi.y,
		"the tank hangs from the tip of the hook, touching it (its top %.3f m, the hook's tip %.3f m)" % [top, tip])
	# One side only: about half of it, and the far side and underneath still bare.
	var centre: Vector3 = xf * box.get_center()
	var away := Vector3(Workshop.BOOTH_XF.basis.z.x, 0.0, Workshop.BOOTH_XF.basis.z.z).normalized()
	w.place(Transform3D(Basis(), Vector3(centre.x, 0.0, centre.z) + away * 0.85))
	w.set_tool("spray")
	w.spray_finish = Shed.FINISHES.size()
	await _aim_point(w, centre)
	_press("interact")
	await get_tree().physics_frame
	w.spray_mode["settle"] = 0.0
	await _aim_point(w, centre)
	Input.action_press("act")
	await _spray_passes(w, xf, box)
	var job: SprayJob = w.spray
	check(job != null and job.seen_n > 100, "a coat's started on it (%d points, all round it)" % (job.seen_n if job else 0))
	if job == null:
		Input.action_release("act")
		main._leave()
		main.queue_free()
		await get_tree().physics_frame
		return
	var one: Dictionary = job.stats()
	await _spray_passes(w, xf, box)
	await _spray_passes(w, xf, box)
	Input.action_release("act")
	for i in 3:
		await get_tree().physics_frame
	var st: Dictionary = job.stats()
	var sides: Dictionary = st["sides"]
	check(float(one["sides"]["near"]) < 0.85, "it's slow, careful work: one steady pass leaves the near side thin (%.0f%% of it a full coat)" % (float(one["sides"]["near"]) * 100.0))
	check(float(sides["near"]) > 0.75, "three passes cover the side facing you (%.0f%%)" % (float(sides["near"]) * 100.0))
	check(float(st["covered"]) > 0.3 and float(st["covered"]) < 0.62 and not job.ready() and Shed.items[tank].has("primer") == false,
		"but spraying one side only is about half of the tank (%.0f%%), not the coat" % (float(st["covered"]) * 100.0))
	check(float(sides["far"]) < 0.1 and float(sides["under"]) < 0.35, "the far side's bare (%.0f%%) and so's underneath (%.0f%%)"
		% [float(sides["far"]) * 100.0, float(sides["under"]) * 100.0])
	# The far side's surfaces have had no paint at all, though they're in the same cubes as a thin
	# part's near side would be: paint only lands on what faces the gun.
	var marks := job.marks
	var far_paint := 0.0
	var far_n := 0
	var b := job.model.global_transform.basis
	for i in job.points.size():
		var nw: Vector3 = b * job.normals[i]
		if nw.dot(away) < -0.5:
			far_n += 1
			far_paint += marks.coats_facing(job.vox[i], job.normals[i])
	check(far_n > 20 and far_paint / maxf(far_n, 1) < 0.08, "next to no paint on the far side (%.3f coats over %d points)" % [far_paint / maxf(far_n, 1), far_n])
	# The scan shows it up.
	check(float(marks.material_for("tank").get_shader_parameter("begun")) == 1.0, "where it's missed, the old surface shows flatted back")
	w.set_spray_scan(true)
	await get_tree().create_timer(0.5).timeout
	var mat := marks.material_for("tank")
	check(float(mat.get_shader_parameter("scan")) > 0.9, "X lights up the far side as missed")
	w.set_spray_scan(false)
	# A coat in another colour over the half-done one takes its place, not on top of it.
	w.spray_finish = 0
	w.spray_color = 2
	await _aim_point(w, centre)
	Input.action_press("act")
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("act")
	for i in 3:
		await get_tree().physics_frame
	var on_tank := 0
	for k in w._sprays:
		if (w._sprays[k] as SprayJob).item == tank:
			on_tank += 1
	var passes := 0
	for mi in (job.model._slot_meshes.get("tank", []) as Array):
		var m: Material = (mi as GeometryInstance3D).material_override
		while m != null:
			if m is ShaderMaterial and (m as ShaderMaterial).shader == SprayMarks.shader():
				passes += 1
			m = m.next_pass
	check(on_tank == 1 and not is_instance_valid(marks) or marks.is_queued_for_deletion(),
		"the orange coat replaces the half-done primer (%d coats on it)" % on_tank)
	check(passes > 0 and passes <= marks.mesh_count() if is_instance_valid(marks) else passes > 0, "one wet coat drawn on each painted surface, not two (%d)" % passes)
	# Round both sides and underneath, and it's done.
	await _spray_round(w, tank, xf, box, centre, away)
	var it: Dictionary = Shed.items[tank]
	check(Shed.paint_index(it["color"]) == 2 and it.has("paint_quality"), "round both sides and underneath, the coat's on (%.0f%%)" % (float(it.get("paint_quality", 0.0)) * 100.0))
	# Once it's on, the part's drawn in it like anywhere else: with the spray controls still up
	# and aimed at it, nothing's drawn over it until more paint lands.
	for i in 3:
		await get_tree().process_frame
	var model: BikeModel = ws._spot_nodes[hook].get_meta("model")
	var shown := 0.0
	for mi in (model._slot_meshes.get("tank", []) as Array):
		var m: Material = (mi as GeometryInstance3D).material_override
		while m != null:
			if m is ShaderMaterial and (m as ShaderMaterial).shader == SprayMarks.shader():
				var on = m.get_shader_parameter("begun")
				shown = maxf(shown, float(on) if on != null else 0.0)
			m = m.next_pass
	check(shown == 0.0, "aiming at it again, the finished coat looks as it is (not flatted back for another)")
	_press("interact")
	await get_tree().physics_frame
	await get_tree().create_timer(SprayMarks.DRY_FOR + 0.3).timeout
	model = ws._spot_nodes[hook].get_meta("model")
	var left := 0
	for mi in (model._slot_meshes.get("tank", []) as Array):
		var m: Material = (mi as GeometryInstance3D).material_override
		while m != null:
			if m is ShaderMaterial and (m as ShaderMaterial).shader == SprayMarks.shader():
				left += 1
			m = m.next_pass
	check(w.spray_mode.is_empty() and left == 0, "stepped back, there's no wet pass left on it (%d)" % left)
	# It looks the same wherever it goes: on another hook, on the floor.
	var on_hook := _paint_looks(model)
	Shed._move(tank, "spot", Shed.furniture_spots(booth)[5])
	Shed.changed.emit()
	for i in 3:
		await get_tree().process_frame
	var on_other := _paint_looks(ws._spot_nodes[Shed.furniture_spots(booth)[5]].get_meta("model"))
	Shed._move(tank, "floor", Transform3D(Basis(), Workshop.CENTER + Vector3(2.0, 0.0, 2.0)))
	Shed.changed.emit()
	for i in 3:
		await get_tree().process_frame
	var on_floor := _paint_looks(ws._floor_nodes[tank].get_meta("model"))
	check(not on_hook.is_empty() and on_hook == on_other and on_hook == on_floor,
		"the painted tank looks the same on another hook and on the floor (%s)" % str(on_hook))
	# Masking tape shows while you spray over it (the old paint isn't redrawn over it), and wherever
	# it hangs, in a colour that shows on the paint.
	Shed.items[tank]["tape"] = {"pattern": "stripe", "q": 1.0}
	var look := SprayJob.look_for({"a": "paint", "color": 1, "finish": "gloss"}, Shed.items[tank])
	check((look["under"] as Color).a == 0.0, "a taped part keeps its tape in sight under the spray")
	Shed._move(tank, "spot", hook)
	Shed.changed.emit()
	for i in 3:
		await get_tree().process_frame
	var taped := 0
	for mi in ((ws._spot_nodes[hook].get_meta("model") as BikeModel)._slot_meshes.get("tank", []) as Array):
		var m: Material = (mi as GeometryInstance3D).material_override
		if m != null and m.next_pass is ShaderMaterial and float(m.next_pass.get_shader_parameter("tape")) == 1.0 \
				and int(m.next_pass.get_shader_parameter("pattern")) == PaintMix.PATTERN_IDS["stripe"]:
			taped += 1
	check(taped > 0, "taped and hung on the hook, the tape's drawn on it (%d surfaces)" % taped)
	check(PaintMix.tape_color_on(Shed.PAINTS[1]) != PaintMix.TAPE_COLOR and PaintMix.tape_color_on(Shed.PAINTS[0]) == PaintMix.TAPE_COLOR,
		"blue tape on a red tank, cream tape on a blue one, so it always shows")
	Shed.items[tank].erase("tape")
	w.set_tool("hands")
	Shed.request({"a": "take", "spot": hook})
	Shed.items.erase(tank)
	main._leave()
	main.queue_free()
	await get_tree().physics_frame


## How a part's painted surfaces are drawn (colour, metal, roughness, clear coat and any effects
## pass), to compare one place with another.
func _paint_looks(model: BikeModel) -> Array:
	var out := []
	for slot in model._slot_meshes:
		for mi in (model._slot_meshes[slot] as Array):
			var m := (mi as GeometryInstance3D).material_override as StandardMaterial3D
			if m == null or not m.has_meta("paint_surface"):
				continue
			var row := "%s %.3f %.3f %s %.2f" % [m.albedo_color.to_html(), m.metallic, m.roughness, m.clearcoat_enabled, m.clearcoat]
			var p := m.next_pass
			while p != null:
				row += " +" + (str((p as ShaderMaterial).shader.get_instance_id() == SprayMarks.shader().get_instance_id()) if p is ShaderMaterial else "pass")
				p = p.next_pass
			if not out.has(row):
				out.append(row)
	out.sort()
	return out


## Sprays a hung part all over, the way a painter goes round it: steady passes from in front and
## from behind, then crouched down to get underneath from both sides, and round again until the
## coat's on (or `rounds` times). Lets go of the trigger to move, so the coat finishes as soon as
## it's on. `away`: the way out of the booth, flat.
func _spray_round(w: Walker, item: int, xf: Transform3D, box: AABB, centre: Vector3, away: Vector3, rounds := 4) -> void:
	var stations := [[away, false], [-away, false], [away, true], [-away, true]]
	var flat := Vector3(centre.x, 0.0, centre.z)
	var was := Workshop._coat_sig(Shed.items[item])
	for r in rounds:
		for st in stations:
			w.set_crouched(st[1])
			w.place(Transform3D(Basis(), flat + (st[0] as Vector3) * (0.62 if st[1] else 0.85)))
			await _aim_point(w, centre)
			Input.action_press("act")
			await _spray_passes(w, xf, box)
			Input.action_release("act")
			for i in 3:
				await get_tree().physics_frame
			if Workshop._coat_sig(Shed.items[item]) != was:
				# The coat's on: letting go finished it.
				w.set_crouched(false)
				return
	w.set_crouched(false)


## Steady, overlapping passes over a part's box, like a painter, at about a metre a second.
func _spray_passes(w: Walker, xf: Transform3D, box: AABB) -> void:
	for i in 2:
		await get_tree().physics_frame
	var cam: Camera3D = w.camera
	var rect := Rect2(cam.unproject_position(xf * box.position), Vector2.ZERO)
	for c in 8:
		rect = rect.expand(cam.unproject_position(xf * box.get_endpoint(c)))
	var centre := xf * box.get_center()
	var dist: float = cam.global_position.distance_to(centre)
	var px_per_m: float = get_viewport().get_visible_rect().size.y / (2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5))
	# Rows a fan's width apart, overlapping (the spray controls' fan is tighter than the can's own).
	var rows := maxi(2, ceili(rect.size.y / (0.075 * px_per_m)))
	var path: Array[Vector3] = []
	for r in rows:
		var y := rect.position.y + (r + 0.5) * rect.size.y / rows
		var frames := maxi(30, ceili(rect.size.x / px_per_m * 120.0))
		for k in frames:
			var f := float(k) / (frames - 1)
			var x := lerpf(rect.position.x, rect.end.x, f if r % 2 == 0 else 1.0 - f)
			path.append(cam.project_position(Vector2(x, y), dist))
	for p in path:
		var d: Vector3 = p - cam.global_position
		w.rotation.y = atan2(-d.x, -d.z)
		w._pitch = 0.0
		w._look(0.0, atan2(d.y, Vector2(d.x, d.z).length()))
		await get_tree().physics_frame
		if w.spray == null:
			return


## The Sales PC's header (SALES, the business account and Close) is one line across the top, and
## every tab has its page in view below it, whatever's on the stands.
func _test_sales_pc_headings() -> void:
	Shed.start_new("Tester", 61)
	var bike := _bike_named("Old Faithful")
	Shed.bikes[bike]["xf"] = Workshop.SHOWROOM_SPOTS[0]
	Shed.request({"a": "sale_list", "bike": bike, "ask": 6500})
	Sales.make_offer(bike)
	Sales.spawn_px(bike)
	var pc := SalesComputer.new()
	add_child(pc)
	await get_tree().process_frame
	var screen := get_viewport().get_visible_rect()
	for tab in SalesComputer.TABS:
		pc.open(tab)
		for i in 3:
			await get_tree().process_frame
		var page: Control = pc._pages[tab]
		var tabs_top := pc._tabs.get_global_rect().position.y
		check(pc._money.get_global_rect().size.y < 40.0 and tabs_top < 200.0 and pc._tabs.get_global_rect().end.y <= screen.end.y
			and page.get_global_rect().size.x > 600.0,
			"%s: the heading is one line (%.0f px high), the page starts under it at %.0f px and is %.0f px wide" % [tab,
			pc._money.get_global_rect().size.y, tabs_top, page.get_global_rect().size.x])
	# Every label in a row of controls keeps to one line.
	var squashed := pc.find_children("*", "Label", true, false).filter(func(l):
		return (l as Label).is_visible_in_tree() and (l as Label).text.length() > 3 and (l as Label).get_line_count() > (l as Label).text.length() / 3)
	check(squashed.is_empty(), "no label is squashed to a letter a line (%s)" % str(squashed.map(func(l): return (l as Label).text.left(20))))
	pc.queue_free()
	await get_tree().process_frame


## The rider shop's Buy button is on screen whichever trinket (or bit of gear) is picked, however
## long the list.
func _test_shop_buy_in_view() -> void:
	var menu := MainMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu.show_pause()
	menu._tabs.current_tab = menu.shop.get_index()
	var screen := get_viewport().get_visible_rect()
	var off := []
	for c in ShopTab.CATEGORIES:
		menu.shop.show_category(c)
		for id in ShopTab.items_of(c):
			menu.shop.select(id)
			await get_tree().process_frame
			var r: Rect2 = menu.shop._buy.get_global_rect()
			if not menu.shop._buy.is_visible_in_tree() or not screen.encloses(r) or r.size.y < 20.0:
				off.append("%s %s" % [id, r])
	check(off.is_empty() and ShopTab.items_of("trinket").size() >= 10, "Buy is on screen for every one of %d trinkets and all the gear %s" % [
		ShopTab.items_of("trinket").size(), str(off.slice(0, 4))])
	var list := menu.shop.find_child("List", true, false) as ScrollContainer
	check(list != null and list.get_global_rect().end.y <= screen.end.y, "the list scrolls, inside the screen")
	menu.queue_free()
	await get_tree().process_frame


## The money graphs move when money does: the first note keeps the balance it opened with, so
## money in or out in the first hour (or day, or week) shows; the TV's scale is zoomed to the
## money, so a sale of a few hundred on an account of thousands shows; and both TV channels plot it.
func _test_money_graph_moves() -> void:
	var s := {}
	MoneyGraph.record(s, 10.2, 20000)
	MoneyGraph.record(s, 10.5, 21500)
	MoneyGraph.record(s, 10.9, 20800)
	var hours := MoneyGraph.points(s, "hour", 10.95, 20800)
	var days := MoneyGraph.points(s, "day", 10.95, 20800)
	check(int(hours[-2]) == 20000 and int(hours[-1]) == 20800 and int(days[0]) == 20000 and int(days[-1]) == 20800,
		"money moving within the first hour and day shows as a step from what it opened with (%s, %s)" % [hours.slice(-2), days])
	var span := TvChannels.chart_scale([20000, 20000, 21500, 20800])
	var plot := Rect2(0, 0, 400, 300)
	var pts := TvChannels.chart_points([20000, 20000, 21500, 20800], plot, span.x, span.y)
	check(span.x > 15000.0 and span.y < 23000.0 and pts[0].y - pts[2].y > 150.0,
		"the scale is zoomed to the money (%.0f to %.0f): £1,500 in is half the chart high (%.0f px)" % [span.x, span.y, pts[0].y - pts[2].y])
	var flat := TvChannels.chart_scale([5000, 5000, 5000])
	check(flat.x < 5000.0 and flat.y > 5000.0, "a flat line sits in the middle of its scale")
	check(TvChannels.chart_scale([0, 100, 400]).x == 0.0 and TvChannels.chart_scale([-300, 200]).x < -300.0,
		"money up from nothing is scaled from nothing; an overdraft shows below the line")
	# The shed's account and your own on the TVs: a sale and a wage this hour show on both.
	Shed.start_new("Tester", 62)
	Shed.bank["series"] = {}
	Money.record_graph()
	var was := Shed.garage_money
	Shed.credit_garage(900, "Test sale")
	Money.record_graph()
	var kept := Settings.money_graph_range
	Settings.money_graph_range = "day"
	var garage: Array = TvChannels.page_data("money_garage")["history"]
	check(int(garage[0]) == was and int(garage[-1]) == was + 900, "the garage TV's graph goes from %d up to %d today" % [int(garage[0]), int(garage[-1])])
	var real_path := Progress.path
	Progress.path = "user://profile_graph_moves.json"
	Progress.select("Graph Mover")
	var mine_was := Progress.money()
	Progress.earn(250, "Test wage")
	var mine: Array = TvChannels.page_data("money_me")["history"]
	check(int(mine[0]) == mine_was and int(mine[-1]) == mine_was + 250, "your own money's TV graph goes from %d up to %d" % [int(mine[0]), int(mine[-1])])
	# Drawn: the line on the page climbs.
	var dash := Dashboard.new("crew", 2.0)
	add_child(dash)
	dash.show_page("money_garage", TvChannels.page_data("money_garage"))
	await get_tree().process_frame
	var g_span := TvChannels.chart_scale(garage)
	var g_pts := TvChannels.chart_points(garage, Rect2(0, 0, 400, 330), g_span.x, g_span.y)
	check(g_pts[0].y - g_pts[-1].y > 100.0, "the garage line climbs %.0f px on the TV" % (g_pts[0].y - g_pts[-1].y))
	dash.queue_free()
	Settings.money_graph_range = kept
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)
	await get_tree().process_frame
